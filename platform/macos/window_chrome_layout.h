#pragma once
#import <AppKit/AppKit.h>

// Traffic lights share the toolbar when both tab layouts are hidden. Their
// clearance belongs to that row; it must never reserve a full-height gutter.
void SlateApplyWindowControlClearance(NSLayoutConstraint* _Nullable plateFromTraffic,
 NSLayoutConstraint* _Nullable navigationLeading, BOOL sharesToolbar,
 CGFloat trafficRightEdge, CGFloat plateInset);

NS_ASSUME_NONNULL_BEGIN

// Use separate AppKit-created buttons in the content toolbar while retaining
// the titlebar-owned controls in their original hierarchy for window transitions.
void SlateConfigureToolbarWindowControls(NSWindow* window, NSView* cluster,
 NSArray<NSButton*>* buttons, BOOL sharesToolbar, BOOL fullScreen);
void SlateAlignWindowControlsWithNavigation(NSView* cluster,
 NSLayoutConstraint* top, NSView* navigation);

NSArray<NSButton*>* SlateCreateToolbarWindowControls(NSWindow* window, NSView* cluster);

NS_ASSUME_NONNULL_END
