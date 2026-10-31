#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "platform/macos/omnibox_overlay.h"
#include <cstdio>
#include <cstdlib>
@interface OmniboxHarness : NSObject <SlateOmniboxDelegate>
@property(copy) NSString* query;
@property NSInteger submissions;
@end
@implementation OmniboxHarness
- (void)showSuggestionsForCard:(SlateOmniboxCard*)card query:(NSString*)query { self.query=query; }
- (NSString*)completionForCard:(SlateOmniboxCard*)card query:(NSString*)query { return [query isEqual:@"git"] ? @"hub.com" : nil; }
- (void)submitOmniboxCard:(SlateOmniboxCard*)card { ++self.submissions; }
- (void)moveSuggestionDelta:(NSInteger)delta {}
- (void)hideSuggestions {}
@end
static void Check(BOOL value,const char* message) { if(!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static void CaptureOmnibox(NSView* view,NSString* path) {
 [view layoutSubtreeIfNeeded];
 NSBitmapImageRep* image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
 [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
 Check([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],"save preview");
}
int main(int argc,char** argv) { @autoreleasepool {
 [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 NSString* out=argc>1 ? @(argv[1]) : NSTemporaryDirectory();
 [[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
 NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,640) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO; window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
 OmniboxHarness* harness=[OmniboxHarness new];
 SlateOmniboxOverlay* overlay=[[SlateOmniboxOverlay alloc] initWithDelegate:harness];
 [overlay showOver:window.contentView initialText:@"https://example.com/long/path"];
 [window.contentView layoutSubtreeIfNeeded];
 Check(NSWidth(overlay.card.frame)==560 && NSHeight(overlay.card.frame)==50,"reference field dimensions");
 Check(NSMidY(overlay.card.frame)==NSMidY(overlay.bounds)+30,"field lifted above center");
 SlateOmniboxCard* card=overlay.card;
 Check(card.field.cell.scrollable && card.field.lineBreakMode==NSLineBreakByClipping,"long addresses scroll with the caret");
 [card setText:@"git" selectAll:NO]; [card focusSelectingAll:NO];
 [card controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:card.field]];
 NSTextView* editor=(NSTextView*)card.field.currentEditor;
 Check([card.field.stringValue isEqual:@"github.com"] && [card.typedText isEqual:@"git"] && card.hasCompletion,"selected inline ending");
 Check(NSEqualRanges(editor.selectedRange,NSMakeRange(3,7)),"only the offered suffix is selected");
 Check(![card control:card.field textView:editor doCommandBySelector:@selector(deleteBackward:)],"Backspace remains a real editing command");
 [editor deleteBackward:nil];
 Check([card.field.stringValue isEqual:@"git"] && !card.hasCompletion,"Backspace does not reinsert the suffix");
 [card controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:card.field]];
 Check([card control:card.field textView:editor doCommandBySelector:@selector(moveRight:)] && !card.hasCompletion && [card.typedText isEqual:@"github.com"],"right arrow accepts ending");
 [card setText:@"😀 draft" selectAll:NO]; [card focusSelectingAll:NO];
 Check(editor.selectedRange.location==[@"😀 draft" length] && !editor.selectedRange.length,"caret uses UTF-16 offsets and preserves draft");
 NSDictionary* site=@{@"name":@"Reddit",@"host":@"reddit.com",@"template":@"https://www.reddit.com/search?q=%s"};
 card.suggestedSite=site;
 Check([card control:card.field textView:editor doCommandBySelector:@selector(insertTab:)] && [card.searchSite isEqual:site],"Tab activates site chip");
 [card control:card.field textView:editor doCommandBySelector:@selector(deleteBackward:)];
 Check(!card.searchSite,"empty Backspace removes chip");
 [card setText:@"git" selectAll:NO];
 NSRect stable=card.frame;
 NSView* list=[[NSView alloc] initWithFrame:NSMakeRect(NSMinX(stable),NSMinY(stable)-8-148,560,148)];
 list.wantsLayer=YES; list.layer.cornerRadius=14; list.layer.borderWidth=1;
 list.layer.borderColor=SlateOmniboxHairline(window.effectiveAppearance).CGColor;
 list.layer.backgroundColor=SlateOmniboxGround(window.effectiveAppearance).CGColor;
 list.layer.shadowColor=NSColor.blackColor.CGColor; list.layer.shadowRadius=20; list.layer.shadowOpacity=0.07;
 [overlay addSubview:list];
 __block NSInteger clicked=0;
 NSArray* kinds=@[@"site",@"bookmark",@"visited",@"search"];
 NSArray* titles=@[@"Search GitHub",@"github.com/openai",@"github.com",@"git"];
 NSArray* details=@[@"",@"OpenAI",@"GitHub",@"Google"];
 SlateOmniboxRow* first=nil;
 for(NSInteger i=0;i<4;++i) {
  SlateOmniboxRow* row=[[SlateOmniboxRow alloc] initWithTitle:titles[i] detail:details[i] kind:kinds[i] image:nil action:^{ ++clicked; }];
  row.translatesAutoresizingMaskIntoConstraints=YES; row.frame=NSMakeRect(6,148-6-(i+1)*34,548,34); [list addSubview:row];
  if(i==1) row.highlighted=YES;
  if(i==0) first=row;
 }
 NSEvent* pointer=[NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:1 trackingNumber:1 userData:NULL];
 [first mouseEntered:pointer];
 Check(first.hovering && !first.highlighted && [card.field.stringValue isEqual:@"git"],"hover does not walk keyboard selection or rewrite the field");
 first.highlighted=YES; [first mouseExited:pointer];
 Check(!first.hovering && first.highlighted,"pointer exit preserves keyboard selection");
 first.highlighted=NO; [first mouseDown:pointer]; Check(clicked==1,"rows take the first click");
 Check(NSEqualRects(stable,card.frame),"list growth does not shift field");
 [window.contentView layoutSubtreeIfNeeded];
 CaptureOmnibox(window.contentView,[out stringByAppendingPathComponent:@"omnibox-light.png"]);
 window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; [overlay applyTheme];
 list.layer.backgroundColor=SlateOmniboxGround(window.effectiveAppearance).CGColor;
 list.layer.borderColor=SlateOmniboxHairline(window.effectiveAppearance).CGColor;
 CaptureOmnibox(window.contentView,[out stringByAppendingPathComponent:@"omnibox-dark.png"]);
 [list removeFromSuperview];
 [overlay setFrameSize:NSMakeSize(260,500)]; [overlay layout]; [card layout];
 Check(NSWidth(card.frame)==232 && NSMinX(card.frame)==14 && NSWidth(card.field.frame)>100,"split-pane field fits without clipping");
 SlateOmniboxStack* stack=[[SlateOmniboxStack alloc] initWithFrame:NSMakeRect(0,0,560,352)];
 stack.orientation=NSUserInterfaceLayoutOrientationVertical; stack.edgeInsets=NSEdgeInsetsMake(6,6,6,6);
 for(int i=0;i<10;i++) {
  SlateOmniboxRow* row=[[SlateOmniboxRow alloc] initWithTitle:@"History result" detail:@"" kind:@"visited" image:nil action:^{}];
  [stack addArrangedSubview:row]; [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-12].active=YES;
 }
 [stack layoutSubtreeIfNeeded];
 Check(stack.isFlipped && NSMinY(stack.arrangedSubviews.firstObject.frame)<NSMinY(stack.arrangedSubviews.lastObject.frame),"scrolling dropdown starts with its first result");
 SlateOmniboxCard* arriving=[[SlateOmniboxCard alloc] initWithDelegate:harness];
 [arriving setText:@"saved draft" selectAll:NO]; [arriving focusSelectingAll:NO];
 [window.contentView addSubview:arriving];
 NSDate* until=[NSDate dateWithTimeIntervalSinceNow:0.05];
 while([until timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
 Check(arriving.field.currentEditor!=nil,"focus request survives arrival in a window");
 [window close]; puts("PASS: omnibox layout, suffix editing, UTF-16 selection, site chips, hover and focus arrival");
 } return 0; }
