#pragma once
#import <AppKit/AppKit.h>

// Traffic lights share the toolbar when both tab layouts are hidden. Their
// clearance belongs to that row; it must never reserve a full-height gutter.
void SlateApplyWindowControlClearance(NSLayoutConstraint* _Nullable plateFromTraffic,
 NSLayoutConstraint* _Nullable navigationLeading, BOOL sharesToolbar,
 CGFloat trafficRightEdge, CGFloat plateInset);
