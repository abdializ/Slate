// File purpose: Custom edge-disc back/forward trackpad swipe navigation, JS horizontal-scroll
// arbitration, hold-to-pick history scrubbing, and mouse side-button navigation for WKWebView.

#pragma once

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// JavaScript injected into pages to determine whether a horizontal wheel gesture belongs to
/// a scrollable container, pinched viewport, or custom wheel handler (maps/sheets/canvases).
NSString* SlateSwipeWatchScript(void);

/// Async JavaScript round-trip used on finger lift so busy pages get the last word before
/// navigation fires.
NSString* SlateSwipeHeardScript(void);

/// Script message handler name used by SlateSwipeWatchScript().
extern NSString* const kSlateSwipeScrollMessageName;

/// WKWebView subclass implementing Search/lovesea-style edge-disc back/forward swipe gestures,
/// hold-for-history-list scrubbing, mouse buttons 3/4, and Logi Options+ swipe events.
@interface SlateSwipeWebView : WKWebView

/// Called when the page's SlateSwipeWatchScript reports whether the current horizontal scroll
/// is free (YES) or taken by the page (NO).
- (void)handleSwipeScrollAnswerFree:(BOOL)isFree;

/// Configures native WebKit edge rubber-banding so horizontal edges only bounce when pinched in.
- (void)calmHorizontalRubberBanding;

/// Waits until WebKit's next presentation update (or timeout), used to avoid resize flashes when
/// folding the sidebar away.
- (void)waitForNextPresentationWithin:(NSTimeInterval)timeout completion:(dispatch_block_t)completion;

/// Optional callback invoked right before programmatic back/forward navigation triggers.
@property(nonatomic, copy, nullable) dispatch_block_t onWillNavigate;

@end

NS_ASSUME_NONNULL_END
#endif
