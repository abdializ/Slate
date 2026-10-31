// File purpose: Checks metadata round trips, lazy restore, private-tab exclusion, and corrupt-file
// preservation. Tests document the behavior they assert; they do not change production browser
// behavior.

#include "platform/macos/session_store.h"
#include "core/tab_model.h"
#import <Foundation/Foundation.h>
#include <cstdlib>
#include <iostream>
void check(bool condition) { if(!condition) std::abort(); }
// Slate note: Run the synthetic scenarios below; failed assertions/checks terminate the executable so
// CTest can report a failure.
int main() { @autoreleasepool {
 NSString* directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 NSString* path=[directory stringByAppendingPathComponent:@"session.json"];
 auto store=slate::make_session_store(path.UTF8String);
 check(store->load().empty());
 slate::TabModel model;
 for(int i=0;i<20;++i) model.add("https://example.com/"+std::to_string(i));
 model.update(1,{},"Quotes \" & Unicode — مرحباً"); model.protect(1,true); model.pin(1,true); model.select(3);
 model.set_zoom(1,125); model.set_zoom(3,90);
 store->save(model.tabs());
 auto saved=store->load();
 check(saved.size()==20 && saved[0].title==model.find(1)->title && saved[0].protected_content && saved[0].pinned);
 check(saved[0].zoom_percent==125 && saved[2].zoom_percent==90 && saved[1].zoom_percent==100);
 // Slate note: Restore selection metadata while leaving the selected record unloaded until the application
 // activates it.
 check(saved[2].selected && saved[2].state==slate::Lifecycle::Discarded);
 slate::TabModel incogModel;
 incogModel.add("https://regular.example/1");
 incogModel.add("https://secret.example/stealth", true);
 incogModel.add("https://regular.example/2");
 store->save(incogModel.tabs());
 auto incogSaved=store->load();
 check(incogSaved.size()==2);
 check(incogSaved[0].url=="https://regular.example/1");
 check(incogSaved[1].url=="https://regular.example/2");
 [@"{\"version\":1,\"tabs\":[{\"id\":\"9\",\"url\":\"https://example.com\",\"title\":\"legacy\",\"selected\":true,\"protected\":false}]}" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
 auto legacy=store->load();
 check(legacy.size()==1 && !legacy[0].pinned && legacy[0].zoom_percent==100);
 for(id invalid in @[@24,@501,@100.5,@YES,@"125"]) {
  NSMutableDictionary* row=[@{@"id":@"1",@"url":@"https://example.com",@"title":@"zoom",@"selected":@YES,@"protected":@NO,@"zoom":invalid} mutableCopy];
  NSData* bytes=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"tabs":@[row]} options:0 error:nil];
  [bytes writeToFile:path atomically:YES];
  bool rejected=false; try { store->load(); } catch(...) { rejected=true; }
  check(rejected && [[NSData dataWithContentsOfFile:path] isEqual:bytes]);
 }
 for(NSString* broken in @[@"{broken", @"{\"version\":99,\"tabs\":[]}",
  @"{\"version\":1,\"tabs\":[{\"id\":\"1\",\"url\":\"javascript:alert(1)\",\"title\":\"bad\",\"selected\":true,\"protected\":false}]}"]) {
  [broken writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  bool rejected=false; try { store->load(); } catch(...) { rejected=true; }
  check(rejected);
  check([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:broken]);
 }
 [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
 std::cout << "Session round trip, lazy state, Unicode and corrupt-file preservation passed\n";
}}
