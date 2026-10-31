#import <AppKit/AppKit.h>
#import "platform/macos/omnibox_overlay.h"
#import "platform/macos/find_bar.h"
#import "platform/macos/pdf_overlay.h"
#import "SlateSearch-Swift.h"
#import <PDFKit/PDFKit.h>
#include <cstdio>
#include <cstdlib>

// The component fixture has no document overlay; the real PDF path is built in Slate.
@implementation SlatePDFOverlay
+ (PDFView*)findPDFViewInView:(NSView*)view { return nil; }
@end
@interface SearchHarness : NSObject <SlateOmniboxDelegate>
@end
@implementation SearchHarness
- (void)showSuggestionsForCard:(SlateOmniboxCard*)card query:(NSString*)query {}
- (void)submitOmniboxCard:(SlateOmniboxCard*)card {}
- (void)moveSuggestionDelta:(NSInteger)delta {}
- (void)hideSuggestions {}
@end
static void Check(BOOL value,const char* message) { if(!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static void Capture(NSView* view,NSString* path) {
 [view layoutSubtreeIfNeeded];
 NSBitmapImageRep* image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
 [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
 [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
int main(int argc,char** argv) {
 @autoreleasepool {
  [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
  NSString* out=argc>1 ? @(argv[1]) : NSTemporaryDirectory();
  [[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
  NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,620,220) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed=NO;
  SearchHarness* harness=[SearchHarness new];
  SlateOmniboxCard* card=[[SlateOmniboxCard alloc] initWithDelegate:harness];
  card.frame=NSMakeRect(30,90,560,52); [window.contentView addSubview:card];
  card.suggestedSite=@{@"name":@"YouTube",@"host":@"youtube.com",@"template":@"https://www.youtube.com/results?search_query=%s"};
  card.field.stringValue=@"yt";
  Check([card control:card.field textView:[NSTextView new] doCommandBySelector:@selector(insertTab:)],"Tab activates site");
  Check([card.searchSite[@"name"] isEqual:@"YouTube"] && !card.field.stringValue.length,"site chip and empty query");
  card.field.stringValue=@"cats and dogs"; [card layoutSubtreeIfNeeded];
  Check(NSMinX(card.field.frame)>24,"site chip reserves space");
  Capture(window.contentView,[out stringByAppendingPathComponent:@"search-site-chip.png"]);
  card.field.stringValue=@"";
  Check([card control:card.field textView:[NSTextView new] doCommandBySelector:@selector(deleteBackward:)] && !card.searchSite,"Backspace removes empty site");
  SlateFindBar* bar=[[SlateFindBar alloc] initWithOwner:nil];
  [bar showInView:window.contentView initialQuery:@"example"];
  [window.contentView layoutSubtreeIfNeeded];
  Check(!bar.prevButton.hidden && !bar.nextButton.hidden,"wide Find has navigation");
  Capture(window.contentView,[out stringByAppendingPathComponent:@"search-find.png"]);
  [bar setFrameSize:NSMakeSize(246,38)]; [bar layout];
  Check(bar.prevButton.hidden && bar.nextButton.hidden && NSWidth(bar.searchField.frame)>=40,"narrow Find retains usable field");
  [bar hideAnimated];
  Check(!bar.isVisible && bar.hidden,"Escape/close hides Find");
  NSView* settings=[SlateSearchServices settingsView];
  NSWindow* panel=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,492,500) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  panel.releasedWhenClosed=NO; panel.contentView=settings;
  settings.wantsLayer=YES; settings.layer.backgroundColor=NSColor.windowBackgroundColor.CGColor;
  [settings layoutSubtreeIfNeeded];
  NSScrollView* scroll=(NSScrollView*)settings.subviews.firstObject;
  [scroll.documentView layoutSubtreeIfNeeded];
  NSStackView* stack=(NSStackView*)scroll.documentView.subviews.firstObject;
  NSView* heading=stack.arrangedSubviews.firstObject;
  NSRect headingRect=[heading convertRect:heading.bounds toView:scroll.contentView];
  Check(NSIntersectsRect(headingRect,scroll.contentView.bounds),"Search settings starts at its heading");
  Capture(settings,[out stringByAppendingPathComponent:@"search-settings.png"]);
  [panel close]; [window close];
  puts("PASS: search chip activation/removal and responsive Find controls");
 }
 return 0;
}
