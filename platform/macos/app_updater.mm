#import "app_updater.h"
#import <Sparkle/Sparkle.h>

@interface SlateAppUpdater () <SPUUpdaterDelegate>
@property(strong) SPUUpdater* engine;
@property(strong) id<SPUUserDriver> driver;
@property BOOL started;
@property(copy) NSString* status;
@property(copy) NSString* verificationResult;
@end

// Routine check results stay in Settings. Sparkle retains its standard install UI.
@interface SlateInlineUpdateDriver : SPUStandardUserDriver
@property(weak) SlateAppUpdater* owner;
@end
@implementation SlateInlineUpdateDriver
- (void)showUserInitiatedUpdateCheckWithCancellation:(void(^)(void))cancellation {
 self.owner.status=@"Checking for updates…";
}
- (void)showUpdateNotFoundWithError:(NSError*)error acknowledgement:(void(^)(void))acknowledgement {
 self.owner.status=error.localizedDescription.length ? error.localizedDescription : @"You’re up to date.";
 acknowledgement();
}
- (void)showUpdaterError:(NSError*)error acknowledgement:(void(^)(void))acknowledgement {
 self.owner.status=@"Couldn’t check for updates. Please try again later.";
 acknowledgement();
}
@end

#if defined(SLATE_ENABLE_VERIFY)
// A quiet user driver for disposable tests. It never opens or activates a window.
@interface SlateQuietUpdateDriver : NSObject <SPUUserDriver>
@property(copy) void (^ready)(SPUUserUpdateChoice);
@end
@implementation SlateQuietUpdateDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest*)request reply:(void(^)(SUUpdatePermissionResponse*))reply { reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void(^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem*)item state:(SPUUserUpdateState*)state reply:(void(^)(SPUUserUpdateChoice))reply {
 fprintf(stderr,"SLATE_UPDATER_FOUND version=%s\n",item.versionString.UTF8String);
 reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData*)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError*)error {}
- (void)showUpdateNotFoundWithError:(NSError*)error acknowledgement:(void(^)(void))acknowledgement { acknowledgement(); }
- (void)showUpdaterError:(NSError*)error acknowledgement:(void(^)(void))acknowledgement { acknowledgement(); }
- (void)showDownloadInitiatedWithCancellation:(void(^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void(^)(SPUUserUpdateChoice))reply { self.ready=reply; fprintf(stderr,"SLATE_UPDATER_READY\n"); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void(^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement { acknowledgement(); }
- (void)dismissUpdateInstallation { self.ready=nil; }
@end
#endif

@implementation SlateAppUpdater
+ (instancetype)sharedUpdater {
 static SlateAppUpdater* shared;
 static dispatch_once_t once;
 dispatch_once(&once, ^{ shared=[SlateAppUpdater new]; });
 return shared;
}
- (instancetype)init {
 if((self=[super init])) {
#if defined(SLATE_ENABLE_VERIFY)
  if([NSProcessInfo.processInfo.environment[@"SLATE_HEADLESS_UPDATE_TEST"] boolValue]) _driver=[SlateQuietUpdateDriver new];
  else
#endif
  {
   SlateInlineUpdateDriver* driver=[[SlateInlineUpdateDriver alloc] initWithHostBundle:NSBundle.mainBundle delegate:nil];
   driver.owner=self; _driver=driver;
  }
  _engine=[[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:NSBundle.mainBundle userDriver:_driver delegate:self];
  _status=@"Updates download and install directly in Slate.";
  _verificationResult=@"not-started";
 }
 return self;
}
+ (NSSet<NSString*>*)keyPathsForValuesAffectingCanCheckForUpdates { return [NSSet setWithObjects:@"started",@"engine.canCheckForUpdates",nil]; }
- (void)start {
 if(self.started) return;
 NSError* error=nil;
 self.started=[self.engine startUpdater:&error];
 if(!self.started) {
  self.status=@"Updates are temporarily unavailable. Please try again later.";
  self.verificationResult=@"configuration-error";
  NSLog(@"Slate updater could not start: %@",error);
 } else self.verificationResult=@"ready";
}
- (BOOL)canCheckForUpdates { return self.started && self.engine.canCheckForUpdates; }
- (BOOL)automaticallyChecksForUpdates { return self.engine.automaticallyChecksForUpdates; }
- (void)setAutomaticallyChecksForUpdates:(BOOL)value { self.engine.automaticallyChecksForUpdates=value; }
- (BOOL)automaticallyDownloadsUpdates { return self.engine.automaticallyDownloadsUpdates; }
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value { self.engine.automaticallyDownloadsUpdates=value; }
- (IBAction)checkForUpdates:(id)sender {
 if(self.whenChecking) self.whenChecking();
 [self start];
 if(!self.started || !self.canCheckForUpdates) return;
 self.verificationResult=@"checking"; self.status=@"Checking for updates…";
 [self.engine checkForUpdates];
}
- (BOOL)validateMenuItem:(NSMenuItem*)item { return self.canCheckForUpdates; }
- (void)updater:(SPUUpdater*)updater didFindValidUpdate:(SUAppcastItem*)item {
 self.status=@"An update is available.";
 self.verificationResult=@"update-available";
}
- (void)updaterDidNotFindUpdate:(SPUUpdater*)updater {
 self.status=@"You’re up to date.";
 self.verificationResult=@"up-to-date";
}
- (void)updater:(SPUUpdater*)updater didAbortWithError:(NSError*)error {
#if defined(SLATE_ENABLE_VERIFY)
 fprintf(stderr,"SLATE_UPDATER_ERROR code=%ld message=%s\n",(long)error.code,error.localizedDescription.UTF8String);
#endif
 if(error.code==SUNoUpdateError) { self.verificationResult=@"up-to-date"; self.status=@"You’re up to date."; }
 else { self.verificationResult=@"check-failed"; self.status=@"Couldn’t check for updates. Please try again later."; }
}
- (void)updater:(SPUUpdater*)updater willInstallUpdate:(SUAppcastItem*)item {
 if(self.beforeInstall) self.beforeInstall();
}
#if defined(SLATE_ENABLE_VERIFY)
- (void)installPendingTestUpdate {
 if(![self.driver isKindOfClass:SlateQuietUpdateDriver.class]) return;
 SlateQuietUpdateDriver* driver=(SlateQuietUpdateDriver*)self.driver;
 void(^reply)(SPUUserUpdateChoice)=driver.ready;
 driver.ready=nil;
 if(reply) { fprintf(stderr,"SLATE_UPDATER_INSTALL\n"); reply(SPUUserUpdateChoiceInstall); }
}
- (NSString*)feedURLStringForUpdater:(SPUUpdater*)updater {
 NSDictionary* env=NSProcessInfo.processInfo.environment;
 NSURL* url=[NSURL URLWithString:env[@"SLATE_TEST_UPDATE_FEED"] ?: @""];
 if(env[@"SLATE_DATA_DIR"] && env[@"SLATE_COMMAND_FILE"] &&
    ([url.host isEqual:@"127.0.0.1"] || [url.host isEqual:@"localhost"])) return url.absoluteString;
 return [NSBundle.mainBundle objectForInfoDictionaryKey:@"SUFeedURL"];
}
#endif
@end
