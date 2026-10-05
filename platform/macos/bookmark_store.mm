#include "bookmark_store.h"
#import <Foundation/Foundation.h>
#include <algorithm>
#include <stdexcept>

NSNotificationName const SlateBookmarksChangedNotification = @"SlateBookmarksChangedNotification";

@implementation SlateBookmark

+ (instancetype)siteWithTitle:(NSString*)title url:(NSString*)url {
  SlateBookmark* b = [[SlateBookmark alloc] init];
  b.identifier = [[NSUUID UUID] UUIDString];
  b.title = title.length ? title : (url ?: @"Untitled");
  b.url = url ?: @"";
  b.children = nil;
  return b;
}

+ (instancetype)folderWithTitle:(NSString*)title children:(NSArray<SlateBookmark*>*)children {
  SlateBookmark* b = [[SlateBookmark alloc] init];
  b.identifier = [[NSUUID UUID] UUIDString];
  b.title = title.length ? title : @"New Folder";
  b.url = nil;
  b.children = children ? [children mutableCopy] : [NSMutableArray array];
  return b;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _identifier = [[NSUUID UUID] UUIDString];
    _title = @"";
    _url = nil;
    _children = nil;
  }
  return self;
}

- (BOOL)isFolder {
  return self.url == nil || self.url.length == 0;
}

- (NSString*)host {
  if (self.isFolder || !self.url.length) return nil;
  NSURL* u = [NSURL URLWithString:self.url];
  return u.host.lowercaseString;
}

- (id)copyWithZone:(NSZone*)zone {
  SlateBookmark* copy = [[[self class] allocWithZone:zone] init];
  copy.identifier = [self.identifier copy];
  copy.title = [self.title copy];
  copy.url = [self.url copy];
  if (self.children) {
    NSMutableArray* kids = [NSMutableArray arrayWithCapacity:self.children.count];
    for (SlateBookmark* child in self.children) {
      [kids addObject:[child copy]];
    }
    copy.children = kids;
  }
  return copy;
}

- (NSDictionary*)toDictionary {
  NSMutableDictionary* dict = [NSMutableDictionary dictionary];
  dict[@"id"] = self.identifier ?: [[NSUUID UUID] UUIDString];
  dict[@"title"] = self.title ?: @"";
  if (self.isFolder) {
    NSMutableArray* kids = [NSMutableArray array];
    for (SlateBookmark* child in (self.children ?: @[])) {
      [kids addObject:[child toDictionary]];
    }
    dict[@"children"] = kids;
  } else {
    dict[@"url"] = self.url ?: @"";
  }
  return dict;
}

+ (instancetype)fromDictionary:(NSDictionary*)dict {
  if (![dict isKindOfClass:[NSDictionary class]]) return nil;
  NSString* ident = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
  NSString* title = dict[@"title"] ?: @"";
  NSString* url = dict[@"url"];
  id kidsObj = dict[@"children"];

  if (kidsObj && [kidsObj isKindOfClass:[NSArray class]]) {
    NSMutableArray<SlateBookmark*>* kids = [NSMutableArray array];
    for (id childDict in kidsObj) {
      SlateBookmark* child = [SlateBookmark fromDictionary:childDict];
      if (child) [kids addObject:child];
    }
    SlateBookmark* folder = [SlateBookmark folderWithTitle:title children:kids];
    folder.identifier = ident;
    return folder;
  }

  if (url.length) {
    SlateBookmark* site = [SlateBookmark siteWithTitle:title url:url];
    site.identifier = ident;
    return site;
  }

  // Fallback: empty folder
  SlateBookmark* folder = [SlateBookmark folderWithTitle:title children:@[]];
  folder.identifier = ident;
  return folder;
}

@end

#pragma mark - SlateBookmarks Store

@interface SlateBookmarks ()
@property (nonatomic, copy) NSString* currentFilePath;
@end

@implementation SlateBookmarks

+ (instancetype)sharedStore {
  static SlateBookmarks* s_store = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_store = [[SlateBookmarks alloc] init];
    [s_store load];
  });
  return s_store;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _roots = @[];
  }
  return self;
}

- (BOOL)isEmpty {
  return self.roots.count == 0;
}

- (NSUInteger)count {
  return [SlateBookmarks countNodes:self.roots];
}

+ (NSUInteger)countNodes:(NSArray<SlateBookmark*>*)nodes {
  NSUInteger sum = 0;
  for (SlateBookmark* node in nodes) {
    if (node.isFolder) {
      sum += [SlateBookmarks countNodes:node.children];
    } else {
      sum += 1;
    }
  }
  return sum;
}

+ (NSArray<NSString*>*)urlsForNodes:(NSArray<SlateBookmark*>*)nodes {
  NSMutableArray<NSString*>* urls = [NSMutableArray array];
  for (SlateBookmark* node in nodes) {
    if (node.isFolder) {
      [urls addObjectsFromArray:[SlateBookmarks urlsForNodes:node.children]];
    } else if (node.url.length) {
      [urls addObject:node.url];
    }
  }
  return urls;
}

+ (NSArray<NSDictionary*>*)foldersForNodes:(NSArray<SlateBookmark*>*)nodes depth:(NSInteger)depth {
  NSMutableArray<NSDictionary*>* list = [NSMutableArray array];
  for (SlateBookmark* node in nodes) {
    if (node.isFolder) {
      [list addObject:@{ @"node": node, @"depth": @(depth) }];
      if (node.children.count) {
        [list addObjectsFromArray:[SlateBookmarks foldersForNodes:node.children depth:depth + 1]];
      }
    }
  }
  return list;
}

+ (BOOL)node:(SlateBookmark*)node holdsIdentifier:(NSString*)identifier {
  if (!node || !identifier.length) return NO;
  if ([node.identifier isEqualToString:identifier]) return YES;
  if (node.isFolder && node.children) {
    for (SlateBookmark* child in node.children) {
      if ([SlateBookmarks node:child holdsIdentifier:identifier]) return YES;
    }
  }
  return NO;
}

- (BOOL)containsURL:(NSString*)urlString {
  if (!urlString.length) return NO;
  return [self findURL:urlString] != nil;
}

- (SlateBookmark*)findURL:(NSString*)urlString {
  if (!urlString.length) return nil;
  __block SlateBookmark* found = nil;
  void (^walk)(NSArray<SlateBookmark*>*);
  __block void (^weakWalk)(NSArray<SlateBookmark*>*);
  weakWalk = walk = ^(NSArray<SlateBookmark*>* nodes) {
    for (SlateBookmark* node in nodes) {
      if (found) return;
      if (!node.isFolder && [node.url isEqualToString:urlString]) {
        found = node;
        return;
      }
      if (node.isFolder && node.children.count) {
        weakWalk(node.children);
      }
    }
  };
  walk(self.roots);
  return found;
}

- (SlateBookmark*)findNodeWithIdentifier:(NSString*)identifier {
  if (!identifier.length) return nil;
  __block SlateBookmark* found = nil;
  void (^walk)(NSArray<SlateBookmark*>*);
  __block void (^weakWalk)(NSArray<SlateBookmark*>*);
  weakWalk = walk = ^(NSArray<SlateBookmark*>* nodes) {
    for (SlateBookmark* node in nodes) {
      if (found) return;
      if ([node.identifier isEqualToString:identifier]) {
        found = node;
        return;
      }
      if (node.isFolder && node.children.count) {
        weakWalk(node.children);
      }
    }
  };
  walk(self.roots);
  return found;
}

- (void)addURL:(NSString*)urlString title:(NSString*)title {
  if (!urlString.length || [self containsURL:urlString]) return;
  SlateBookmark* site = [SlateBookmark siteWithTitle:title url:urlString];
  NSMutableArray<SlateBookmark*>* newRoots = [self.roots mutableCopy];
  [newRoots addObject:site];
  self.roots = newRoots;
  [self save];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
}

- (void)removeWithIdentifier:(NSString*)identifier {
  if (!identifier.length) return;
  NSArray<SlateBookmark*>* pruned = [self pruneIdentifier:identifier fromNodes:self.roots];
  self.roots = pruned;
  [self save];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
}

- (NSArray<SlateBookmark*>*)pruneIdentifier:(NSString*)identifier fromNodes:(NSArray<SlateBookmark*>*)nodes {
  NSMutableArray<SlateBookmark*>* result = [NSMutableArray array];
  for (SlateBookmark* node in nodes) {
    if ([node.identifier isEqualToString:identifier]) continue;
    SlateBookmark* copy = [node copy];
    if (node.isFolder && node.children) {
      copy.children = [[self pruneIdentifier:identifier fromNodes:node.children] mutableCopy];
    }
    [result addObject:copy];
  }
  return result;
}

- (void)moveWithIdentifier:(NSString*)identifier intoFolderWithIdentifier:(NSString*)folderID {
  if (!identifier.length || [identifier isEqualToString:folderID]) return;
  NSMutableArray<SlateBookmark*>* working = [NSMutableArray array];
  for (SlateBookmark* n in self.roots) [working addObject:[n copy]];

  SlateBookmark* detached = [self detachIdentifier:identifier fromNodes:working];
  if (!detached) return;

  if (folderID.length) {
    // Check if detached node contains folderID (prevent loop into itself or its own descendants)
    if ([SlateBookmarks node:detached holdsIdentifier:folderID]) return;
    if (![self insertNode:detached intoFolderWithIdentifier:folderID inNodes:working]) return;
  } else {
    [working addObject:detached];
  }

  self.roots = working;
  [self save];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
}

- (SlateBookmark*)detachIdentifier:(NSString*)identifier fromNodes:(NSMutableArray<SlateBookmark*>*)nodes {
  for (NSUInteger i = 0; i < nodes.count; i++) {
    SlateBookmark* node = nodes[i];
    if ([node.identifier isEqualToString:identifier]) {
      [nodes removeObjectAtIndex:i];
      return node;
    }
    if (node.isFolder && node.children) {
      SlateBookmark* found = [self detachIdentifier:identifier fromNodes:node.children];
      if (found) return found;
    }
  }
  return nil;
}

- (BOOL)insertNode:(SlateBookmark*)node intoFolderWithIdentifier:(NSString*)folderID inNodes:(NSArray<SlateBookmark*>*)nodes {
  for (SlateBookmark* candidate in nodes) {
    if ([candidate.identifier isEqualToString:folderID] && candidate.isFolder) {
      if (!candidate.children) candidate.children = [NSMutableArray array];
      [candidate.children addObject:node];
      return YES;
    }
    if (candidate.isFolder && candidate.children.count) {
      if ([self insertNode:node intoFolderWithIdentifier:folderID inNodes:candidate.children]) return YES;
    }
  }
  return NO;
}

- (void)takeNodes:(NSArray<SlateBookmark*>*)nodes fromBrowserNamed:(NSString*)name {
  if (!nodes.count) return;
  NSMutableArray<SlateBookmark*>* working = [NSMutableArray array];
  for (SlateBookmark* n in self.roots) [working addObject:[n copy]];

  if (!working.count) {
    for (SlateBookmark* n in nodes) [working addObject:[n copy]];
  } else {
    for (NSInteger i = (NSInteger)working.count - 1; i >= 0; --i) {
      SlateBookmark* n = working[i];
      if (n.isFolder && [n.title isEqualToString:name]) {
        [working removeObjectAtIndex:i];
      }
    }
    SlateBookmark* folder = [SlateBookmark folderWithTitle:name children:nodes];
    [working addObject:folder];
  }

  self.roots = working;
  [self save];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
}

- (SlateBookmark*)insertNode:(SlateBookmark*)node intoParent:(NSString*)parentID {
  if (!node) return nil;
  if (parentID.length) {
    NSMutableArray<SlateBookmark*>* working = [NSMutableArray array];
    for (SlateBookmark* n in self.roots) [working addObject:[n copy]];
    if ([self insertNode:node intoFolderWithIdentifier:parentID inNodes:working]) {
      self.roots = working;
      [self save];
      [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
      return node;
    }
  }
  NSMutableArray<SlateBookmark*>* working = [self.roots mutableCopy];
  [working addObject:node];
  self.roots = working;
  [self save];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
  return node;
}

- (void)updateWithIdentifier:(NSString*)identifier title:(NSString*)title url:(NSString*)url {
  if (!identifier.length) return;
  SlateBookmark* node = [self findNodeWithIdentifier:identifier];
  if (!node) return;
  if (title) node.title = title;
  if (url && !node.isFolder) node.url = url;
  [self save];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateBookmarksChangedNotification object:self];
}

- (NSString*)defaultFilePath {
  NSString* dataDir = NSProcessInfo.processInfo.environment[@"SLATE_DATA_DIR"];
  if (!dataDir.length) {
    NSString* appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    dataDir = [appSupport stringByAppendingPathComponent:@"Slate"];
  }
  return [dataDir stringByAppendingPathComponent:@"bookmarks.json"];
}

- (void)load {
  [self loadFromPath:[self defaultFilePath]];
}

- (void)loadFromPath:(NSString*)path {
  _currentFilePath = [path copy];
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    _roots = @[];
    return;
  }

  NSData* data = [NSData dataWithContentsOfFile:path];
  if (!data) return;

  NSError* error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || !json) return;

  NSMutableArray<SlateBookmark*>* items = [NSMutableArray array];

  if ([json isKindOfClass:[NSArray class]]) {
    for (id itemDict in json) {
      SlateBookmark* b = [SlateBookmark fromDictionary:itemDict];
      if (b) [items addObject:b];
    }
  } else if ([json isKindOfClass:[NSDictionary class]]) {
    // Legacy format: { "version": 1, "bookmarks": [ { "id", "title", "url" }, ... ] }
    id rows = json[@"bookmarks"];
    if ([rows isKindOfClass:[NSArray class]]) {
      for (id row in rows) {
        if ([row isKindOfClass:[NSDictionary class]]) {
          NSString* ident = row[@"id"];
          NSString* title = row[@"title"];
          NSString* url = row[@"url"];
          if (url.length) {
            SlateBookmark* site = [SlateBookmark siteWithTitle:title url:url];
            if (ident.length) site.identifier = ident;
            [items addObject:site];
          }
        }
      }
    }
  }

  _roots = [items copy];
}

- (void)save {
  [self saveToPath:_currentFilePath ?: [self defaultFilePath]];
}

- (void)saveToPath:(NSString*)path {
  _currentFilePath = [path copy];
  NSMutableArray* rows = [NSMutableArray array];
  for (SlateBookmark* node in self.roots) {
    [rows addObject:[node toDictionary]];
  }

  NSError* error = nil;
  NSData* data = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:&error];
  if (!data || error) return;

  NSString* parentDir = [path stringByDeletingLastPathComponent];
  [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
  [data writeToFile:path atomically:YES];
}

- (void)syncToBookmarkList:(slate::BookmarkList&)list {
  for (NSString* url in [SlateBookmarks urlsForNodes:self.roots]) {
    SlateBookmark* b = [self findURL:url];
    std::string sUrl = url.UTF8String;
    std::string sTitle = b ? b.title.UTF8String : sUrl;
    if (!list.find_url(sUrl)) {
      try { list.add(sUrl, sTitle); } catch (...) {}
    }
  }
}

- (void)syncFromBookmarkList:(const slate::BookmarkList&)list {
  for (const auto& item : list.items()) {
    NSString* url = [NSString stringWithUTF8String:item.url.c_str()];
    NSString* title = [NSString stringWithUTF8String:item.title.c_str()];
    if (![self containsURL:url]) {
      [self addURL:url title:title];
    }
  }
}

@end

#pragma mark - C++ Bridge Functions

namespace slate {

std::unique_ptr<BookmarkList> load_bookmarks(const std::string& path) {
  @autoreleasepool {
    NSString* filePath = [NSString stringWithUTF8String:path.c_str()];
    [[SlateBookmarks sharedStore] loadFromPath:filePath];

    std::vector<Bookmark> items;
    for (NSString* url in [SlateBookmarks urlsForNodes:[SlateBookmarks sharedStore].roots]) {
      SlateBookmark* b = [[SlateBookmarks sharedStore] findURL:url];
      std::string sId = b ? b.identifier.UTF8String : "";
      std::string sTitle = b ? b.title.UTF8String : url.UTF8String;
      std::string sUrl = url.UTF8String;
      items.push_back(Bookmark{sId, sTitle, sUrl});
    }
    return std::make_unique<BookmarkList>(std::move(items));
  }
}

void save_bookmarks(const std::string& path, const BookmarkList& list) {
  @autoreleasepool {
    NSString* filePath = [NSString stringWithUTF8String:path.c_str()];
    [[SlateBookmarks sharedStore] syncFromBookmarkList:list];
    [[SlateBookmarks sharedStore] saveToPath:filePath];
  }
}

} // namespace slate
