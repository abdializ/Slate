#pragma once
#import <Cocoa/Cocoa.h>
#import <Security/Security.h>

@class SlateDelegate;

/// The site card: floating non-activating panel shown under the address / active tab
/// displaying connection privacy, security certificate details, copy address, print, and zoom.
@interface SlateSiteCardPanel : NSPanel

+ (instancetype)sharedPanel;
+ (BOOL)isShown;
+ (void)hide;

@property (nonatomic, weak) SlateDelegate* owner;
@property (nonatomic, strong) NSURL* pageURL;
@property (nonatomic, assign) SecTrustRef serverTrust;
@property (nonatomic, assign) BOOL hasOnlySecureContent;
@property (nonatomic, assign) int currentZoomPercent;

- (void)showForAnchor:(NSView*)anchor inWindow:(NSWindow*)window;
- (void)toggleForAnchor:(NSView*)anchor inWindow:(NSWindow*)window;
- (void)hidePanel;

- (void)updateZoomPercent:(int)percent;
- (void)updateWithURL:(NSURL*)url trust:(SecTrustRef)trust secureContent:(BOOL)secure zoom:(int)zoom;
- (void)showDeeperViewAnimated:(BOOL)animated;
- (void)showFrontViewAnimated:(BOOL)animated;

@end
