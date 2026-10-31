#import "window_chrome_layout.h"
#include <cmath>
#include <algorithm>
#include <initializer_list>

void SlateApplyWindowControlClearance(NSLayoutConstraint* plateFromTraffic,
 NSLayoutConstraint* navigationLeading, BOOL sharesToolbar,
 CGFloat trafficRightEdge, CGFloat plateInset) {
 const CGFloat safeLeading=trafficRightEdge>0 ? std::ceil(trafficRightEdge+16) : 0;
 // Retain this measurement for a revealed narrow icon rail, but never use it
 // as a full-height page constraint when the sidebar is hidden.
 if(std::abs(plateFromTraffic.constant-safeLeading)>0.5) plateFromTraffic.constant=safeLeading;
 plateFromTraffic.active=NO;
 const CGFloat leading=sharesToolbar && trafficRightEdge>0
  ? std::max<CGFloat>(16,safeLeading-plateInset) : 16;
 if(std::abs(navigationLeading.constant-leading)>0.5) navigationLeading.constant=leading;
}

void SlateConfigureToolbarWindowControls(NSWindow* window, NSView* cluster,
 NSArray<NSButton*>* buttons, BOOL sharesToolbar, BOOL fullScreen) {
 const BOOL useCluster=sharesToolbar || fullScreen;
 cluster.hidden=!useCluster;
 // AppKit remains responsible for native controls in fullscreen transitions.
 if(!fullScreen) for(NSWindowButton kind : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
  NSButton* native=[window standardWindowButton:kind];
  native.hidden=useCluster;
  native.alphaValue=useCluster ? 0 : 1;
 }
 for(NSButton* button in buttons) {
  button.enabled=!window.attachedSheet && !(fullScreen && button.action==@selector(performMiniaturize:));
  if(button.action==@selector(toggleFullScreen:)) {
   button.accessibilityLabel=fullScreen ? @"Exit full screen" : @"Enter full screen";
   button.toolTip=button.accessibilityLabel;
  }
 }
}

void SlateAlignWindowControlsWithNavigation(NSView* cluster,
 NSLayoutConstraint* top, NSView* navigation) {
 NSView* root=cluster.superview;
 if(!root || !navigation.window || cluster.hidden) return;
 NSRect nav=[navigation convertRect:navigation.bounds toView:root];
 const CGFloat centerFromTop=root.isFlipped ? NSMidY(nav)-NSMinY(root.bounds)
  : NSMaxY(root.bounds)-NSMidY(nav);
 const CGFloat value=centerFromTop-NSHeight(cluster.bounds)/2;
 if(std::abs(top.constant-value)>0.5) top.constant=value;
}

NSArray<NSButton*>* SlateCreateToolbarWindowControls(NSWindow* window, NSView* cluster) {
 NSMutableArray<NSButton*>* fullScreenButtons=[NSMutableArray array];
 NSUInteger trafficIndex=0;
 for(NSWindowButton kind : {NSWindowCloseButton,NSWindowMiniaturizeButton,NSWindowZoomButton}) {
  NSButton* button=[NSWindow standardWindowButton:kind forStyleMask:window.styleMask];
  if(!button) continue;
  button.frame=NSMakeRect(trafficIndex*20,2,14,14);
  button.target=window;
  button.action=kind==NSWindowCloseButton ? @selector(performClose:) :
   kind==NSWindowMiniaturizeButton ? @selector(performMiniaturize:) : @selector(toggleFullScreen:);
  button.refusesFirstResponder=YES;
  button.accessibilityLabel=kind==NSWindowCloseButton ? @"Close window" :
   kind==NSWindowMiniaturizeButton ? @"Minimize window" : @"Exit full screen";
  button.identifier=kind==NSWindowCloseButton ? @"SlateFullscreenClose" :
   kind==NSWindowMiniaturizeButton ? @"SlateFullscreenMinimize" : @"SlateFullscreenExit";
  button.toolTip=button.accessibilityLabel;
  [cluster addSubview:button];
  [fullScreenButtons addObject:button];
  ++trafficIndex;
 }
 return fullScreenButtons;
}
