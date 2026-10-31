#import <AppKit/AppKit.h>
#import "platform/macos/window_chrome_layout.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <initializer_list>
static void Check(BOOL value,const char* message) { if(!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static NSView* Box(NSView* parent, NSColor* color) {
 NSView* view=[[NSView alloc] initWithFrame:NSZeroRect]; view.translatesAutoresizingMaskIntoConstraints=NO;
 view.wantsLayer=YES; view.layer.backgroundColor=color.CGColor; [parent addSubview:view]; return view;
}
int main() { @autoreleasepool {
 [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1200,800)
  styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO; window.titleVisibility=NSWindowTitleHidden; window.titlebarAppearsTransparent=YES;
 NSView* root=window.contentView;
 NSView* sidebar=Box(root,NSColor.windowBackgroundColor);
 NSView* plate=Box(root,NSColor.whiteColor);
 NSView* toolbar=Box(plate,NSColor.whiteColor);
 NSView* nav=Box(toolbar,NSColor.controlAccentColor);
 NSView* page=Box(plate,[NSColor colorWithWhite:0.98 alpha:1]);
 NSLayoutConstraint* sideWidth=[sidebar.widthAnchor constraintEqualToConstant:240];
 NSLayoutConstraint* pageLeading=[plate.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:8];
 pageLeading.priority=NSLayoutPriorityDefaultHigh;
 NSLayoutConstraint* trafficInset=[plate.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.leadingAnchor constant:98];
 NSLayoutConstraint* navLeading=[nav.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:16];
 NSLayoutConstraint* plateTrailing=[plate.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-8];
 [NSLayoutConstraint activateConstraints:@[
  [sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[sidebar.topAnchor constraintEqualToAnchor:root.topAnchor],[sidebar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],sideWidth,
  pageLeading,plateTrailing,[plate.topAnchor constraintEqualToAnchor:root.topAnchor constant:-8],[plate.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:8],
  [toolbar.leadingAnchor constraintEqualToAnchor:plate.leadingAnchor],[toolbar.trailingAnchor constraintEqualToAnchor:plate.trailingAnchor],[toolbar.topAnchor constraintEqualToAnchor:plate.topAnchor],[toolbar.heightAnchor constraintEqualToConstant:52],
  navLeading,[nav.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],[nav.widthAnchor constraintEqualToConstant:120],[nav.heightAnchor constraintEqualToConstant:26],
  [page.leadingAnchor constraintEqualToAnchor:plate.leadingAnchor],[page.trailingAnchor constraintEqualToAnchor:plate.trailingAnchor],[page.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],[page.bottomAnchor constraintEqualToAnchor:plate.bottomAnchor]
 ]];
 [root layoutSubtreeIfNeeded];
 CGFloat right=0;
 for(NSWindowButton kind:{NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
  NSButton* button=[window standardWindowButton:kind];
  NSRect frame=[button.superview convertRect:button.frame toView:root]; right=MAX(right,NSMaxX(frame));
 }
 Check(right>0,"native traffic lights were measured");
 // Reproduce the reported leftover strip before invoking the production fix.
 sideWidth.constant=0; trafficInset.active=YES; trafficInset.constant=ceil(right+16);
 [root layoutSubtreeIfNeeded];
 Check(NSMinX(plate.frame)>8,"old clearance reproduces the full-height gutter");
 for(CGFloat width:{1200.0,780.0,480.0}) {
  [window setContentSize:NSMakeSize(width,800)];
  for(CGFloat sidebarWidth:{240.0,96.0,0.0,240.0,0.0}) {
   sideWidth.constant=sidebarWidth; sidebar.hidden=sidebarWidth==0;
   SlateApplyWindowControlClearance(trafficInset,navLeading,sidebarWidth==0,right,8);
   [root layoutSubtreeIfNeeded];
   Check(!trafficInset.active,"no full-height traffic-light constraint remains");
   Check(fabs(NSMinX(plate.frame)-(sidebarWidth+8))<0.5,"page consumes all of the collapsed sidebar space");
   if(sidebarWidth==0) {
    Check(fabs(NSWidth(page.frame)-(NSWidth(root.bounds)-16))<0.5,"hidden sidebar leaves only the normal window border");
    NSRect navigation=[nav convertRect:nav.bounds toView:root];
    Check(NSMinX(navigation)>=right+15.5,"toolbar controls remain clear of the traffic lights");
   } else Check(fabs(navLeading.constant-16)<0.5,"showing sidebar restores ordinary toolbar spacing");
  }
 }
 // The full-screen traffic controls share the same toolbar but use a 5pt inset.
 sideWidth.constant=0; pageLeading.constant=5; plateTrailing.constant=-5;
 SlateApplyWindowControlClearance(trafficInset,navLeading,YES,82,5);
 [root layoutSubtreeIfNeeded];
 Check(fabs(NSMinX(plate.frame)-5)<0.5,"full-screen hidden sidebar has no gutter");
 Check(NSMinX([nav convertRect:nav.bounds toView:root])>=98,"full-screen controls retain their own toolbar clearance");
 // Hidden horizontal tabs use the same row, with no special sidebar reservation.
 SlateApplyWindowControlClearance(trafficInset,navLeading,YES,0,5);
 Check(navLeading.constant==16 && !trafficInset.active,"no invisible-controls reservation");
 [window close]; puts("PASS: hide/show, icon rail, 3 window widths, full-screen toolbar clearance and no leftover sidebar gutter");
 } return 0; }
