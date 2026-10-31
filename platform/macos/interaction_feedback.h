// File purpose: Declares temporary zoom feedback and the download-arrival visual effect.

#pragma once
#import <Cocoa/Cocoa.h>

// Transient native feedback: no idle rendering or repeating animation timers.
// Slate note: showPercent presents the current zoom near its page; dismiss removes transient feedback.
@interface SlateZoomIndicator : NSVisualEffectView
@property(nonatomic, readonly) int percent;
- (void)showPercent:(int)percent inView:(NSView*)host target:(id)target action:(SEL)action;
- (void)dismiss;
@end

@interface SlateDownloadArrival : NSView
+ (void)playInWindow:(NSWindow*)window fromView:(NSView*)source toIcon:(NSView*)icon;
@end
