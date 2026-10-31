#import "platform/macos/passwords_panel.h"
#import <AppKit/AppKit.h>
#include <cassert>
@interface SlatePasswordsPanel (Checks)
- (void)addPassword:(id)sender;
- (void)saveAddedPassword:(id)sender;
- (void)searchChanged:(id)sender;
@end
static void CollectText(NSView* view,NSMutableArray<NSString*>* strings) {
 if([view isKindOfClass:NSTextField.class]) [strings addObject:((NSTextField*)view).stringValue];
 for(NSView* sub in view.subviews)CollectText(sub,strings);
}
int main(int argc,char** argv) { @autoreleasepool {
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 slate::CredentialStore store;
 for(const auto& origin:{"https://example.com","https://accounts.example.org"}) {
  slate::Credential c;c.origin=origin;c.username="reader@example.com";c.password="FAKE-SECRET-MUST-STAY-HIDDEN";store.save(c);
 }
 __block int saves=0;
 SlatePasswordsPanel* panel=[SlatePasswordsPanel sharedPanel];
 [panel prepareForCredentialStore:&store onSave:^{++saves;}];
 assert(!panel.visible);assert(store.items().size()==2);
 NSTableView* table=[panel valueForKey:@"tableView"];
 assert(table.numberOfRows==2);
 [panel setValue:@"example.com" forKey:@"expandedSite"];
 [panel searchChanged:nil];
 assert(table.numberOfRows==3);
 NSMutableArray* text=[NSMutableArray array];
 for(NSInteger row=0;row<table.numberOfRows;++row) CollectText([panel tableView:table viewForTableColumn:table.tableColumns[0] row:row],text);
 assert([text containsObject:@"••••••••••"]);
 assert(![text containsObject:@"FAKE-SECRET-MUST-STAY-HIDDEN"]);
 [panel addPassword:nil];
 assert([panel valueForKey:@"addForm"]);
 ((NSTextField*)[panel valueForKey:@"addSite"]).stringValue=@"new.example.net";
 ((NSTextField*)[panel valueForKey:@"addUser"]).stringValue=@"new-reader";
 ((NSSecureTextField*)[panel valueForKey:@"addSecret"]).stringValue=@"NEW-FAKE-SECRET";
 [panel saveAddedPassword:nil];
 assert(store.items().size()==3 && saves==1);
 assert(![panel valueForKey:@"addForm"]);
 NSSearchField* search=[panel valueForKey:@"searchField"];search.stringValue=@"example.org";[panel searchChanged:nil];
 assert(table.numberOfRows==1);
 assert([((NSButton*)[panel valueForKey:@"removeShown"]).title isEqualToString:@"Remove 1…"]);
 search.stringValue=@"not-found";[panel searchChanged:nil];assert(table.numberOfRows==0);
 assert(((NSButton*)[panel valueForKey:@"removeShown"]).hidden);
 search.stringValue=@"";[panel searchChanged:nil];[panel addPassword:nil];
 if(argc>1) {
  NSView* view=panel.contentView;
  [view layoutSubtreeIfNeeded];
  for(NSInteger row=0;row<table.numberOfRows;++row)[table viewAtColumn:0 row:row makeIfNecessary:YES];
  [table layoutSubtreeIfNeeded];
  NSBitmapImageRep* image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
  if(image) { [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
   [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]; }
 }
 [panel close];
 assert(!panel.visible);
 puts("Native password panel grouping, masked secrets, inline Add, search, and filtered removal controls passed without opening a window.");
} }
