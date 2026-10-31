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
  pageLeading,plateTrailing,[plate.topAnchor constraintEqualToAnchor:root.topAnchor constant:8],[plate.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-8],
  [toolbar.leadingAnchor constraintEqualToAnchor:plate.leadingAnchor],[toolbar.trailingAnchor constraintEqualToAnchor:plate.trailingAnchor],[toolbar.topAnchor constraintEqualToAnchor:plate.topAnchor],[toolbar.heightAnchor constraintEqualToConstant:52],
  navLeading,[nav.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor constant:1],[nav.widthAnchor constraintEqualToConstant:120],[nav.heightAnchor constraintEqualToConstant:26],
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
 // Reproduce the screenshot: native titlebar buttons sit above the toolbar.
 NSButton* nativeClose=[window standardWindowButton:NSWindowCloseButton];
 NSView* nativeParent=nativeClose.superview;
 NSRect originalNativeFrame=nativeClose.frame;
 NSRect nativeRect=[nativeParent convertRect:nativeClose.frame toView:root];
 NSRect navRect=[nav convertRect:nav.bounds toView:root];
 Check(fabs(NSMidY(nativeRect)-NSMidY(navRect))>5,"old titlebar position reproduces vertical misalignment");
 NSView* cluster=Box(root,NSColor.clearColor);
 NSLayoutConstraint* controlTop=[cluster.topAnchor constraintEqualToAnchor:root.topAnchor constant:12];
 [NSLayoutConstraint activateConstraints:@[
  [cluster.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],controlTop,
  [cluster.widthAnchor constraintEqualToConstant:68],[cluster.heightAnchor constraintEqualToConstant:18]
 ]];
 NSArray<NSButton*>* buttons=SlateCreateToolbarWindowControls(window,cluster);
 Check(buttons.count==3,"three AppKit-created toolbar window controls");
 for(BOOL fullscreen : {NO,YES}) for(int repeat=0;repeat<3;++repeat) {
  [window setContentSize:NSMakeSize(repeat==0 ? 1200 : repeat==1 ? 780 : 480,repeat==2 ? 360 : 800)];
  SlateConfigureToolbarWindowControls(window,cluster,buttons,YES,fullscreen);
  [root layoutSubtreeIfNeeded];
  SlateAlignWindowControlsWithNavigation(cluster,controlTop,nav);
  [root layoutSubtreeIfNeeded];
  NSRect controls=[cluster convertRect:cluster.bounds toView:root];
  NSRect navigation=[nav convertRect:nav.bounds toView:root];
  Check(fabs(NSMidY(controls)-NSMidY(navigation))<0.5,"window buttons align with navigation controls");
  SlateApplyWindowControlClearance(trafficInset,navLeading,YES,NSMaxX(controls),5);
  [root layoutSubtreeIfNeeded];
  navigation=[nav convertRect:nav.bounds toView:root];
  Check(NSMinX(navigation)>=NSMaxX(controls)+15.5,"toolbar buttons do not overlap window controls");
  Check(fabs(NSMinX(plate.frame)-5)<0.5,"alignment never reintroduces sidebar gutter");
  Check(!cluster.hiddenOrHasHiddenAncestor,"toolbar controls are visible");
  Check(nativeClose.superview==nativeParent && NSEqualRects(nativeClose.frame,originalNativeFrame),"native titlebar hierarchy and geometry stay intact");
  if(!fullscreen) Check(nativeClose.hidden && nativeClose.alphaValue==0,"no duplicate native controls in hidden-tabs mode");
  for(NSButton* button in buttons) {
   Check(button.target==window,"window control actions target the real window");
   Check(button.action==@selector(performClose:) || button.action==@selector(performMiniaturize:) || button.action==@selector(toggleFullScreen:),"native window actions remain connected");
   Check(button.enabled==!(fullscreen && button.action==@selector(performMiniaturize:)),"minimize stays enabled outside fullscreen");
   NSPoint center=[button convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) toView:root.superview];
   NSView* hit=[root hitTest:center];
   Check(hit==button || [hit isDescendantOf:button],"each window control receives clicks at its visual center");
   NSView* frame=root.superview;
   NSPoint framePoint=[button convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) toView:frame.superview];
   NSView* windowHit=[frame hitTest:framePoint];
   Check(windowHit==button || [windowHit isDescendantOf:button],"native titlebar does not intercept toolbar window controls");
  }
  SlateConfigureToolbarWindowControls(window,cluster,buttons,NO,NO);
  Check(cluster.hidden && !nativeClose.hidden && nativeClose.alphaValue==1,"showing tabs restores native titlebar controls");
 }
 [window close]; puts("PASS: hide/show, icon rail, 3 window widths, full-screen toolbar clearance, centered clickable window controls and no leftover sidebar gutter");
 } return 0; }
