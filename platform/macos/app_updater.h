#pragma once
#import <Cocoa/Cocoa.h>

// Sparkle owns downloading, signature verification, replacement, and relaunch.
@interface SlateAppUpdater : NSObject
+ (instancetype)sharedUpdater;
@property(readonly) BOOL canCheckForUpdates;
@property BOOL automaticallyChecksForUpdates;
@property BOOL automaticallyDownloadsUpdates;
@property(copy) void (^beforeInstall)(void);
@property(copy) void (^whenChecking)(void);
@property(readonly,copy) NSString* status;
- (void)start;
- (IBAction)checkForUpdates:(id)sender;
#if defined(SLATE_ENABLE_VERIFY)
@property(readonly,copy) NSString* verificationResult;
@property(readonly) BOOL started;
- (void)installPendingTestUpdate;
#endif
@end
