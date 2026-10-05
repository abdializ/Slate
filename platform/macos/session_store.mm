#include "session_store.h"
#include "core/tab_model.h"
#import <Foundation/Foundation.h>
#include <charconv>
#include <stdexcept>
namespace slate {
namespace {
void require(bool condition) { if(!condition) throw std::runtime_error("Invalid session file; original preserved"); }
bool valid_url(NSString* value) {
 if([value isEqualToString:@"about:blank"]) return true;
 NSURL* url=[NSURL URLWithString:value];
 return ([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"]) && url.host.length;
}
class JsonSessionStore final : public SessionStore {
 public:
 explicit JsonSessionStore(std::string path):path_(std::move(path)) {}
 std::vector<TabGroup> last_groups() const override { return groups_; }
 std::vector<Tab> load() override { @autoreleasepool {
  NSString* path=[NSString stringWithUTF8String:path_.c_str()];
  if(![[NSFileManager defaultManager] fileExistsAtPath:path]) return {};
  NSError* error=nil;
  NSDictionary* attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
  require(attributes && [attributes fileSize]<=8*1024*1024);
  NSData* bytes=[NSData dataWithContentsOfFile:path options:0 error:&error];
  require(bytes!=nil);
  id root=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:&error];
  require([root isKindOfClass:NSDictionary.class]);
  require([root[@"version"] isKindOfClass:NSNumber.class] && [root[@"version"] isEqual:@1]);
  id rows=root[@"tabs"];
  require([rows isKindOfClass:NSArray.class] && [rows count]<=500);
  std::vector<Tab> tabs;
  for(id row in rows) {
   require([row isKindOfClass:NSDictionary.class]);
   id idText=row[@"id"], url=row[@"url"], title=row[@"title"];
   require([idText isKindOfClass:NSString.class] && [url isKindOfClass:NSString.class] && [title isKindOfClass:NSString.class]);
   require([url length]<=8192 && [title length]<=4096 && valid_url(url));
   require([row[@"selected"] isKindOfClass:NSNumber.class] && [row[@"protected"] isKindOfClass:NSNumber.class]);
   require(CFGetTypeID((__bridge CFTypeRef)row[@"selected"])==CFBooleanGetTypeID() &&
           CFGetTypeID((__bridge CFTypeRef)row[@"protected"])==CFBooleanGetTypeID());
   bool pinned=false;
   if(row[@"pinned"]) {
    require([row[@"pinned"] isKindOfClass:NSNumber.class] &&
            CFGetTypeID((__bridge CFTypeRef)row[@"pinned"])==CFBooleanGetTypeID());
    pinned=[row[@"pinned"] boolValue];
   }
   const std::string text=[idText UTF8String];
   TabId id=0;
   auto result=std::from_chars(text.data(),text.data()+text.size(),id);
   require(result.ec==std::errc() && result.ptr==text.data()+text.size());
   Tab tab{id,[url UTF8String],[title UTF8String],Lifecycle::Discarded,
    [row[@"selected"] boolValue],[row[@"protected"] boolValue]};
   tab.pinned=pinned;
   if(row[@"group"]) {
    require([row[@"group"] isKindOfClass:NSString.class] && [row[@"group"] length]<=32);
    tab.group_id=[row[@"group"] UTF8String];
   }
   tabs.push_back(std::move(tab));
  }
  groups_.clear();
  if(root[@"groups"]) {
   require([root[@"groups"] isKindOfClass:NSArray.class] && [root[@"groups"] count]<=50);
   for(id row in root[@"groups"]) {
    require([row isKindOfClass:NSDictionary.class]);
    require([row[@"id"] isKindOfClass:NSString.class] && [row[@"title"] isKindOfClass:NSString.class]);
    require([row[@"id"] length]<=32 && [row[@"title"] length]<=128);
    bool collapsed=false;
    if(row[@"collapsed"]) {
     require([row[@"collapsed"] isKindOfClass:NSNumber.class] &&
             CFGetTypeID((__bridge CFTypeRef)row[@"collapsed"])==CFBooleanGetTypeID());
     collapsed=[row[@"collapsed"] boolValue];
    }
    groups_.push_back(TabGroup{[row[@"id"] UTF8String],[row[@"title"] UTF8String],collapsed});
   }
  }
  TabModel checked(std::move(tabs), groups_);
  groups_=checked.groups();
  return checked.tabs(); // Validate IDs, normalize selection; all tabs start unloaded.
 }}
 void save(const std::vector<Tab>& tabs) override { save(tabs, groups_); }
 void save(const std::vector<Tab>& tabs, const std::vector<TabGroup>& groups) override { @autoreleasepool {
  require(tabs.size()<=500);
  require(groups.size()<=50);
  groups_=groups;
  NSMutableArray* rows=[NSMutableArray array];
  for(const auto& tab:tabs) {
   if(tab.incognito) continue;
   NSString* url=[NSString stringWithUTF8String:tab.url.c_str()];
   NSString* title=[NSString stringWithUTF8String:tab.title.c_str()];
   require(url && title && url.length<=8192 && title.length<=4096 && valid_url(url));
   NSMutableDictionary* row=[@{@"id":[NSString stringWithFormat:@"%llu",static_cast<unsigned long long>(tab.id)],
    @"url":url,@"title":title,@"selected":@(tab.selected),@"protected":@(tab.protected_content),
    @"pinned":@(tab.pinned)} mutableCopy];
   if(!tab.group_id.empty())
    row[@"group"]=[NSString stringWithUTF8String:tab.group_id.c_str()];
   [rows addObject:row];
  }
  NSMutableArray* groupRows=[NSMutableArray array];
  for(const auto& group:groups) {
   require(!group.id.empty() && group.id.size()<=32 && group.title.size()<=128);
   [groupRows addObject:@{@"id":[NSString stringWithUTF8String:group.id.c_str()],
    @"title":[NSString stringWithUTF8String:group.title.c_str()],
    @"collapsed":@(group.collapsed)}];
  }
  NSError* error=nil;
  NSData* data=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"tabs":rows,@"groups":groupRows}
   options:NSJSONWritingPrettyPrinted error:&error];
  if(!data) throw std::runtime_error("Cannot encode session");
  NSString* path=[NSString stringWithUTF8String:path_.c_str()];
  if(![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
     withIntermediateDirectories:YES attributes:nil error:&error] ||
     ![data writeToFile:path options:NSDataWritingAtomic error:&error])
   throw std::runtime_error("Cannot save session");
 }}
 private:
 std::string path_;
 std::vector<TabGroup> groups_;
};
}
std::unique_ptr<SessionStore> make_session_store(const std::string& path) {
 return std::make_unique<JsonSessionStore>(path);
}
}
