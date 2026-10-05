#import "platform/macos/download_manager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/xattr.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>
#import <math.h>

NSString* const SlateDownloadsChangedNotification = @"SlateDownloadsChangedNotification";
NSString* const SlateDownloadProgressNotification = @"SlateDownloadProgressNotification";

static BOOL SecureAttachQuarantine(int fd, const char* path) {
 // Check if quarantine attribute is already securely present (e.g. attached by WebKit Networking process)
 char checkBuf[512] = {0};
 ssize_t existingLen = -1;
 if (fd >= 0) {
  existingLen = fgetxattr(fd, "com.apple.quarantine", checkBuf, sizeof(checkBuf) - 1, 0, 0);
 } else if (path != NULL) {
  struct stat st;
  if (lstat(path, &st) != 0 || S_ISLNK(st.st_mode)) {
   fprintf(stderr, "SLATE_DOWNLOAD_SECURITY_ERR: quarantine refused on invalid or symlink path: %s\n", path);
   return NO;
  }
  existingLen = getxattr(path, "com.apple.quarantine", checkBuf, sizeof(checkBuf) - 1, 0, XATTR_NOFOLLOW);
 }
 if (existingLen > 0) {
  fprintf(stderr, "SLATE_DOWNLOAD_QUARANTINE_PRESENT on %s (len=%zd): %.*s\n",
          path ? path : "fd", existingLen, (int)existingLen, checkBuf);
  return YES;
 }

 time_t now = time(NULL);
 NSString* uuidStr = [[NSUUID UUID] UUIDString];
 NSString* qAttr = [NSString stringWithFormat:@"0081;%lx;dev.slate.browser;%@", (long)now, uuidStr];
 const char* qVal = [qAttr UTF8String];
 size_t qLen = strlen(qVal);
 int res = -1;
 if (fd >= 0) {
  res = fsetxattr(fd, "com.apple.quarantine", qVal, qLen, 0, 0);
 } else if (path != NULL) {
  res = setxattr(path, "com.apple.quarantine", qVal, qLen, 0, XATTR_NOFOLLOW);
 }
 if (res != 0) {
  int setErr = errno;
  // If setxattr returned EPERM, check if quarantine attribute is present
  ssize_t retryLen = -1;
  if (fd >= 0) {
   retryLen = fgetxattr(fd, "com.apple.quarantine", checkBuf, sizeof(checkBuf) - 1, 0, 0);
  } else if (path != NULL) {
   retryLen = getxattr(path, "com.apple.quarantine", checkBuf, sizeof(checkBuf) - 1, 0, XATTR_NOFOLLOW);
  }
  if (retryLen > 0) {
   fprintf(stderr, "SLATE_DOWNLOAD_QUARANTINE_CONFIRMED on %s despite EPERM (len=%zd): %.*s\n",
           path ? path : "fd", retryLen, (int)retryLen, checkBuf);
   return YES;
  }
  fprintf(stderr, "SLATE_DOWNLOAD_SECURITY_ERR: Failed to set quarantine on %s (setErr=%d: %s, getErr=%d: %s)\n",
          path ? path : "fd", setErr, strerror(setErr), errno, strerror(errno));
  return NO;
 }
 return YES;
}

static NSString* SafeDownloadFilename(NSString* filename) {
 NSString* name=[(filename ?: @"download") lastPathComponent];
 NSMutableString* clean=[NSMutableString string];
 for(NSUInteger i=0;i<name.length;++i) {
  unichar c=[name characterAtIndex:i];
  if(c<0x20 || c==0x7f || (c>=0x202a && c<=0x202e) || (c>=0x2066 && c<=0x2069)) continue;
  [clean appendFormat:@"%C",(unichar)(c=='\\' ? '_' : c)];
 }
 name=[clean stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];
 if(!name.length) return @"download";
 NSString* extension=name.pathExtension;
 NSString* suffix=extension.length>0 && extension.length<32 ? [@"." stringByAppendingString:extension] : @"";
 NSString* base=suffix.length ? name.stringByDeletingPathExtension : name;
 while([[base stringByAppendingString:suffix] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>240 && base.length>1) {
  NSRange range=[base rangeOfComposedCharacterSequenceAtIndex:base.length-1];
  base=[base substringToIndex:range.location];
 }
 if(!base.length) base=@"download";
 name=[base stringByAppendingString:suffix];
 return name;
}

static NSString* DownloadsDataDirectory() {
 NSString* override = NSProcessInfo.processInfo.environment[@"SLATE_DATA_DIR"];
 if (override.length && override.isAbsolutePath) return override;
 NSString* support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
 return [support stringByAppendingPathComponent:@"Slate"];
}

static NSString* DownloadsPersistencePath() {
 return [DownloadsDataDirectory() stringByAppendingPathComponent:@"downloads.json"];
}

// Only publish a fully written, quarantined regular file. RENAME_EXCL never
// replaces another file, even if a download finishes during a name collision.
static BOOL PublishDownload(SlateDownloadItem* item, NSString* directory, NSError** error) {
 int fd=open(item.stagingURL.path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
 struct stat st;
 if(fd<0 || fstat(fd,&st)!=0 || !S_ISREG(st.st_mode)) {
  if(fd>=0) close(fd);
  *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{NSLocalizedDescriptionKey:@"The downloaded file could not be verified."}];
  return NO;
 }
 BOOL safe=SecureAttachQuarantine(fd,item.stagingURL.path.fileSystemRepresentation);
 if(safe) safe=fchmod(fd,0600)==0 && fsync(fd)==0;
 close(fd);
 if(!safe) {
  *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{NSLocalizedDescriptionKey:@"The file could not be saved with macOS security protection."}];
  return NO;
 }
 for(int attempt=0;attempt<64;++attempt) {
  NSURL* destination=[SlateDownloadManager uniqueDestinationURLForFilename:item.filename inDirectory:directory];
  if(renamex_np(item.stagingURL.path.fileSystemRepresentation,destination.path.fileSystemRepresentation,RENAME_EXCL)==0) {
   item.destinationURL=destination;
   item.filename=destination.lastPathComponent;
   item.totalBytes=st.st_size;
   item.receivedBytes=st.st_size;
   return YES;
  }
  if(errno!=EEXIST) break;
 }
 *error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:@"The file could not be moved into Downloads. Check available space and folder access."}];
 return NO;
}
static NSURL* DownloadStagingURL(NSString* directory) {
 return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@".slate-%@.slatedownload",NSUUID.UUID.UUIDString]]];
}
static BOOL IsUnfinished(SlateDownloadItem* item) {
 return item.state==SlateDownloadStateInProgress || item.state==SlateDownloadStatePaused || item.state==SlateDownloadStateFinishing;
}

@implementation SlateDownloadItem

- (instancetype)init {
 self = [super init];
 if (self) {
  _identifier = [[NSUUID UUID] UUIDString];
  _startDate = [NSDate date];
  _state = SlateDownloadStateInProgress;
  _totalBytes = -1;
  _receivedBytes = 0;
  _progress = 0.0;
 }
 return self;
}

- (NSString*)formattedSize {
 if (self.totalBytes > 0) {
  return [NSByteCountFormatter stringFromByteCount:self.totalBytes countStyle:NSByteCountFormatterCountStyleFile];
 }
 if (self.receivedBytes > 0) {
  return [NSByteCountFormatter stringFromByteCount:self.receivedBytes countStyle:NSByteCountFormatterCountStyleFile];
 }
 return @"--";
}

- (NSString*)formattedStatus {
 if(self.state==SlateDownloadStateFinishing) return @"Saving securely…";
 if(self.state==SlateDownloadStatePaused) return (!self.activeTask && !self.sourceWebView) ? @"Source tab closed · download again from the website" : @"Paused";
 if (self.state == SlateDownloadStateInProgress) {
  if (self.totalBytes > 0) {
   NSString* rec = [NSByteCountFormatter stringFromByteCount:self.receivedBytes countStyle:NSByteCountFormatterCountStyleFile];
   NSString* tot = [NSByteCountFormatter stringFromByteCount:self.totalBytes countStyle:NSByteCountFormatterCountStyleFile];
   NSString* rate=self.bytesPerSecond>1 ? [NSString stringWithFormat:@" · %@/s",[NSByteCountFormatter stringFromByteCount:(int64_t)self.bytesPerSecond countStyle:NSByteCountFormatterCountStyleFile]] : @"";
   NSString* remaining=@"";
   if(self.bytesPerSecond>1 && self.receivedBytes<self.totalBytes) {
    NSInteger seconds=(NSInteger)ceil((self.totalBytes-self.receivedBytes)/self.bytesPerSecond);
    remaining=seconds<60 ? [NSString stringWithFormat:@" · %lds left",(long)seconds] : [NSString stringWithFormat:@" · %ldm left",(long)ceil(seconds/60.0)];
   }
   return [NSString stringWithFormat:@"%@ of %@%@%@",rec,tot,rate,remaining];
  }
  if (self.receivedBytes > 0) {
   return [NSByteCountFormatter stringFromByteCount:self.receivedBytes countStyle:NSByteCountFormatterCountStyleFile];
  }
  return @"Downloading…";
 }
 if (self.state == SlateDownloadStateCompleted) {
  return [NSString stringWithFormat:@"%@ • %@", [self formattedSize], [self formattedDate]];
 }
 if (self.state == SlateDownloadStateCancelled) {
  return @"Cancelled";
 }
 if (self.state == SlateDownloadStateFailed) {
  return self.errorDescription.length ? [NSString stringWithFormat:@"Failed: %@", self.errorDescription] : @"Download failed";
 }
 return @"";
}

- (NSString*)formattedDate {
 if (!self.startDate) return @"";
 NSCalendar* cal = [NSCalendar currentCalendar];
 if ([cal isDateInToday:self.startDate]) {
  static NSDateFormatter* timeFormatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
   timeFormatter = [[NSDateFormatter alloc] init];
   timeFormatter.dateStyle = NSDateFormatterNoStyle;
   timeFormatter.timeStyle = NSDateFormatterShortStyle;
  });
  return [NSString stringWithFormat:@"Today, %@", [timeFormatter stringFromDate:self.startDate]];
 }
 static NSDateFormatter* dateFormatter = nil;
 static dispatch_once_t onceToken;
 dispatch_once(&onceToken, ^{
  dateFormatter = [[NSDateFormatter alloc] init];
  dateFormatter.dateStyle = NSDateFormatterShortStyle;
  dateFormatter.timeStyle = NSDateFormatterShortStyle;
 });
 return [dateFormatter stringFromDate:self.startDate];
}

- (NSImage*)fileIcon {
 if (self.destinationURL.path.length && [[NSFileManager defaultManager] fileExistsAtPath:self.destinationURL.path]) {
  return [[NSWorkspace sharedWorkspace] iconForFile:self.destinationURL.path];
 }
 NSString* ext = self.filename.pathExtension;
 if (ext.length) {
  if (@available(macOS 12.0, *)) {
   UTType* type = [UTType typeWithFilenameExtension:ext];
   if (type) return [[NSWorkspace sharedWorkspace] iconForContentType:type];
  }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [[NSWorkspace sharedWorkspace] iconForFileType:ext];
#pragma clang diagnostic pop
 }
 return [NSImage imageNamed:NSImageNameMultipleDocuments];
}

- (BOOL)fileAvailable {
 if(self.state!=SlateDownloadStateCompleted || !self.destinationURL.isFileURL) return NO;
 struct stat st;
 return lstat(self.destinationURL.path.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode);
}
- (BOOL)canResume {
 return (self.state==SlateDownloadStatePaused || self.state==SlateDownloadStateFailed) && (self.activeTask || (self.resumeData.length && self.sourceWebView));
}
- (void)showInFinder {
 if(self.fileAvailable) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.destinationURL]];
}
- (void)openFile {
 if(!self.fileAvailable) return;
 int fd=open(self.destinationURL.path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
 struct stat st;
 BOOL safe=fd>=0 && fstat(fd,&st)==0 && S_ISREG(st.st_mode) && SecureAttachQuarantine(fd,self.destinationURL.path.fileSystemRepresentation);
 if(fd>=0) close(fd);
 if(safe) [NSWorkspace.sharedWorkspace openURL:self.destinationURL];
}
- (void)cancel { [[SlateDownloadManager sharedManager] cancelDownloadItem:self]; }
- (void)pause { [[SlateDownloadManager sharedManager] pauseDownloadItem:self]; }
- (void)resume { [[SlateDownloadManager sharedManager] resumeDownloadItem:self]; }

- (NSDictionary*)dictionaryRepresentation {
 NSMutableDictionary* dict = [NSMutableDictionary dictionary];
 dict[@"id"] = self.identifier ?: @"";
 dict[@"filename"] = self.filename ?: @"";
 if(self.originalURL) {
  NSURLComponents* source=[NSURLComponents componentsWithURL:self.originalURL resolvingAgainstBaseURL:NO];
  source.user=nil; source.password=nil;
  if(source.URL.absoluteString) dict[@"originalURL"]=source.URL.absoluteString;
 }
 if (self.destinationURL.path) dict[@"destinationPath"] = self.destinationURL.path;
 dict[@"totalBytes"] = @(self.totalBytes);
 dict[@"receivedBytes"] = @(self.receivedBytes);
 dict[@"state"] = @((NSInteger)self.state);
 if(self.errorDescription.length) dict[@"error"] = self.errorDescription;
 if (self.startDate) dict[@"timestamp"] = @([self.startDate timeIntervalSince1970]);
 return dict;
}

+ (instancetype)fromDictionary:(NSDictionary*)dict {
 if (![dict isKindOfClass:[NSDictionary class]]) return nil;
 SlateDownloadItem* item = [[SlateDownloadItem alloc] init];
 item.identifier=[dict[@"id"] isKindOfClass:NSString.class] ? dict[@"id"] : NSUUID.UUID.UUIDString;
 item.filename=[dict[@"filename"] isKindOfClass:NSString.class] ? dict[@"filename"] : @"Download";
 NSString* orig=[dict[@"originalURL"] isKindOfClass:NSString.class] ? dict[@"originalURL"] : nil;
 if(orig.length) item.originalURL=[NSURL URLWithString:orig];
 NSString* dest=[dict[@"destinationPath"] isKindOfClass:NSString.class] ? dict[@"destinationPath"] : nil;
 if(dest.isAbsolutePath) item.destinationURL=[NSURL fileURLWithPath:dest];
 for(NSString* key in @[@"totalBytes",@"receivedBytes",@"state",@"timestamp"]) {
  if(dict[key] && ![dict[key] isKindOfClass:NSNumber.class]) return nil;
 }
 item.totalBytes = [dict[@"totalBytes"] longLongValue];
 item.receivedBytes = [dict[@"receivedBytes"] longLongValue];
 NSInteger stateVal = [dict[@"state"] integerValue];
 if (stateVal == SlateDownloadStateInProgress || stateVal == SlateDownloadStatePaused || stateVal == SlateDownloadStateFinishing) stateVal = SlateDownloadStateCancelled; // reset interrupted downloads on restart
 if(stateVal<0 || stateVal>SlateDownloadStateFinishing) return nil;
 item.state = (SlateDownloadState)stateVal;
 if(item.destinationURL && item.state==SlateDownloadStateCompleted) item.filename=SafeDownloadFilename(item.destinationURL.lastPathComponent);
 item.errorDescription=[dict[@"error"] isKindOfClass:NSString.class] ? dict[@"error"] : nil;
 item.progress = (item.totalBytes > 0) ? ((double)item.receivedBytes / (double)item.totalBytes) : 1.0;
 double ts = [dict[@"timestamp"] doubleValue];
 if (ts > 0) item.startDate = [NSDate dateWithTimeIntervalSince1970:ts];
 return item;
}

@end

@interface SlateDownloadManager () {
 NSMutableArray<SlateDownloadItem*>* _items;
 NSMapTable<WKDownload*, SlateDownloadItem*>* _downloadMap;
 NSMapTable<NSURLSessionDownloadTask*, SlateDownloadItem*>* _taskMap;
 NSTimer* _progressTimer;
 NSURLSession* _urlSession;
}
@end

@implementation SlateDownloadManager

+ (instancetype)sharedManager {
 static SlateDownloadManager* instance = nil;
 static dispatch_once_t onceToken;
 dispatch_once(&onceToken, ^{
  instance = [[SlateDownloadManager alloc] init];
 });
 return instance;
}

- (instancetype)init {
 self = [super init];
 if (self) {
  _items = [NSMutableArray array];
  _downloadMap = [NSMapTable weakToStrongObjectsMapTable];
  _taskMap = [NSMapTable weakToStrongObjectsMapTable];
  NSString* envDown = NSProcessInfo.processInfo.environment[@"SLATE_DOWNLOADS_DIR"];
  if (envDown.length && envDown.isAbsolutePath) {
   _downloadsDirectory = [envDown copy];
  } else {
   _downloadsDirectory = [NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject copy];
  }
  [[NSFileManager defaultManager] createDirectoryAtPath:_downloadsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
  NSURLSessionConfiguration* cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
  _urlSession = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
  [self loadHistory];
 }
 return self;
}

- (NSArray<SlateDownloadItem*>*)items {
 return [_items copy];
}

- (NSArray<SlateDownloadItem*>*)activeDownloads {
 NSMutableArray* active = [NSMutableArray array];
 for (SlateDownloadItem* it in _items) {
  if (it.state == SlateDownloadStateInProgress || it.state==SlateDownloadStateFinishing) {
   [active addObject:it];
  }
 }
 return active;
}

- (BOOL)hasActiveDownloads {
 return self.activeDownloads.count > 0;
}

- (double)overallProgress {
 NSArray* active = self.activeDownloads;
 if (active.count == 0) return 0.0;
 double received=0,total=0;
 for(SlateDownloadItem* item in active) {
  if(item.totalBytes>0) { total+=item.totalBytes; received+=MIN(item.receivedBytes,item.totalBytes); }
 }
 return total>0 ? MAX(0,MIN(1,received/total)) : 0;
}

+ (NSURL*)uniqueDestinationURLForFilename:(NSString*)filename inDirectory:(NSString*)directory {
 NSString* cleanName=SafeDownloadFilename(filename);

 NSString* ext = [cleanName pathExtension];
 NSString* base = [cleanName stringByDeletingPathExtension];
 if (!base.length) base = @"download";

 // Canonicalize destination directory using realpath to prevent symlink bypass and prefix collisions
 char realDirBuf[PATH_MAX];
 const char* dirRep = directory.fileSystemRepresentation;
 if (!realpath(dirRep, realDirBuf)) {
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  if (!realpath(dirRep, realDirBuf)) {
   return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:cleanName]];
  }
 }
 NSString* realDir = [NSString stringWithUTF8String:realDirBuf];

 // Check candidates using lstat to detect symlinks as well as regular files
 NSString* candidate = [realDir stringByAppendingPathComponent:cleanName];
 int count = 1;
 struct stat st;
 while (lstat(candidate.fileSystemRepresentation, &st) == 0 && count < 10000) {
  NSString* newName = ext.length > 0 ?
   [NSString stringWithFormat:@"%@ (%d).%@", base, count, ext] :
   [NSString stringWithFormat:@"%@ (%d)", base, count];
  candidate = [realDir stringByAppendingPathComponent:newName];
  count++;
 }

 // Strict containment verification: candidate parent directory must equal realDir exactly
 NSString* candidateParent = [candidate stringByDeletingLastPathComponent];
 char realParentBuf[PATH_MAX];
 if (!realpath(candidateParent.fileSystemRepresentation, realParentBuf) ||
     strcmp(realParentBuf, realDirBuf) != 0) {
  candidate = [realDir stringByAppendingPathComponent:[NSString stringWithFormat:@"download_%lx", (long)time(NULL)]];
 }

 return [NSURL fileURLWithPath:candidate];
}

- (SlateDownloadItem*)itemForDownload:(WKDownload*)download {
 return [_downloadMap objectForKey:download];
}

- (void)registerDownload:(WKDownload*)download forWebView:(WKWebView*)webView {
 [self registerDownload:download forWebView:webView requestedFilename:nil inDirectory:nil];
}

- (void)registerDownload:(WKDownload*)download forWebView:(WKWebView*)webView
       requestedFilename:(NSString*)filename inDirectory:(NSString*)directory {
 if([_downloadMap objectForKey:download]) return;
 SlateDownloadItem* item = [[SlateDownloadItem alloc] init];
 item.targetDirectory=[(directory.length ? directory : self.downloadsDirectory) copy];
 item.originalURL = download.originalRequest.URL;
 item.sourceWebView=webView;
 item.privateDownload=webView && !webView.configuration.websiteDataStore.isPersistent;
 item.hasSuggestedFilename=filename.length>0;
 item.filename = filename.length ? SafeDownloadFilename(filename) : (download.originalRequest.URL.lastPathComponent ?: @"download");
 item.destinationURL = [SlateDownloadManager uniqueDestinationURLForFilename:item.filename inDirectory:item.targetDirectory];
 item.state = SlateDownloadStateInProgress;
 item.activeDownload = download;
 [_downloadMap setObject:item forKey:download];
 [_items insertObject:item atIndex:0];
 [self startProgressTimerIfNeeded];
 [self notifyChanged];
}

- (SlateDownloadItem*)startDownloadFromURL:(NSURL*)url suggestedFilename:(NSString*)filename {
 if (!url || !([url.scheme.lowercaseString isEqualToString:@"http"] || [url.scheme.lowercaseString isEqualToString:@"https"])) return nil;
 SlateDownloadItem* item = [[SlateDownloadItem alloc] init];
 item.targetDirectory=[self.downloadsDirectory copy];
 item.originalURL = url;
 item.usesURLSession=YES;
 item.hasSuggestedFilename=filename.length>0;
 item.filename = filename.length ? filename : (url.lastPathComponent.length ? url.lastPathComponent : @"download");
 item.destinationURL = [SlateDownloadManager uniqueDestinationURLForFilename:item.filename inDirectory:self.downloadsDirectory];
 item.state = SlateDownloadStateInProgress;
 NSURLSessionDownloadTask* task = [_urlSession downloadTaskWithURL:url];
 item.activeTask = task;
 [_taskMap setObject:item forKey:task];
 [_items insertObject:item atIndex:0];
 [task resume];
 [self startProgressTimerIfNeeded];
 [self notifyChanged];
 return item;
}

- (void)cancelDownloadItem:(SlateDownloadItem*)item {
 if(item.state!=SlateDownloadStateInProgress && item.state!=SlateDownloadStatePaused) return;
 item.state=SlateDownloadStateCancelled;
 [item.activeTask cancel]; item.activeTask=nil;
 [item.activeDownload cancel:^(NSData* data) {
  if(item.stagingURL) unlink(item.stagingURL.path.fileSystemRepresentation);
 }]; item.activeDownload=nil;
 item.resumeData=nil;
 [self notifyChanged];
}
- (void)pauseDownloadItem:(SlateDownloadItem*)item {
 if(item.state!=SlateDownloadStateInProgress) return;
 if((item.totalBytes>0 && item.receivedBytes>=item.totalBytes) || item.activeTask.state==NSURLSessionTaskStateCompleted) return;
 item.state=SlateDownloadStatePaused;
 item.bytesPerSecond=0;
 if(item.activeTask) [item.activeTask suspend];
 else if(item.activeDownload) {
  WKDownload* download=item.activeDownload;
  [_downloadMap removeObjectForKey:download];
  [download cancel:^(NSData* data) {
   dispatch_async(dispatch_get_main_queue(), ^{
    if(item.state!=SlateDownloadStatePaused) return;
    item.activeDownload=nil;
    item.resumeData=data;
    if(!data.length) { item.state=SlateDownloadStateFailed; item.errorDescription=@"This download cannot be resumed. Download it again from the website."; }
    [self notifyChanged];
   });
  }];
 }
 [self notifyChanged];
}
- (void)resumeDownloadItem:(SlateDownloadItem*)item {
 if(!item.canResume) return;
 item.state=SlateDownloadStateInProgress;
 item.lastSampleTime=0; item.errorDescription=nil;
 if(item.activeTask) [item.activeTask resume];
 else {
  NSData* data=item.resumeData; item.resumeData=nil;
  [item.sourceWebView resumeDownloadFromResumeData:data completionHandler:^(WKDownload* download) {
   if(item.state!=SlateDownloadStateInProgress) { [download cancel:^(NSData* data) {}]; return; }
   download.delegate=self; item.activeDownload=download;
   [self->_downloadMap setObject:item forKey:download];
   [self notifyChanged];
  }];
 }
 [self startProgressTimerIfNeeded]; [self notifyChanged];
}

- (void)removeItem:(SlateDownloadItem*)item {
 if ([_items containsObject:item] && !IsUnfinished(item)) {
  [_items removeObject:item];
  [self saveHistory];
  [self notifyChanged];
 }
}

- (void)clearCompleted {
 NSMutableArray* toRemove = [NSMutableArray array];
 for (SlateDownloadItem* it in _items) {
  if (!IsUnfinished(it)) {
   [toRemove addObject:it];
  }
 }
 [_items removeObjectsInArray:toRemove];
 [self saveHistory];
 [self notifyChanged];
}

- (void)startProgressTimerIfNeeded {
 if (_progressTimer) return;
 _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.125 repeats:YES block:^(NSTimer * _Nonnull timer) {
  (void)timer;
  BOOL anyActive = NO;
  for (SlateDownloadItem* item in self->_items) {
   if (item.state == SlateDownloadStateInProgress) {
    anyActive = YES;
    if (item.activeDownload && item.activeDownload.progress) {
     NSProgress* p = item.activeDownload.progress;
     item.progress = p.fractionCompleted;
     item.receivedBytes = p.completedUnitCount;
     if (p.totalUnitCount > 0) item.totalBytes = p.totalUnitCount;
    }
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(item.lastSampleTime>0 && now-item.lastSampleTime>=0.5) {
     double speed=MAX(0,(item.receivedBytes-item.lastSampleBytes)/(now-item.lastSampleTime));
     item.bytesPerSecond=item.bytesPerSecond>0 ? 0.65*item.bytesPerSecond+0.35*speed : speed;
     item.lastSampleTime=now; item.lastSampleBytes=item.receivedBytes;
    } else if(item.lastSampleTime==0) { item.lastSampleTime=now; item.lastSampleBytes=item.receivedBytes; }
   }
  }
  if (!anyActive) {
   [self->_progressTimer invalidate];
   self->_progressTimer = nil;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateDownloadProgressNotification object:self];
 }];
}

- (void)notifyChanged {
 [self saveHistory];
 dispatch_async(dispatch_get_main_queue(), ^{
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateDownloadsChangedNotification object:self];
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateDownloadProgressNotification object:self];
 });
}

- (void)saveHistory {
 NSMutableArray* arr = [NSMutableArray array];
 for (SlateDownloadItem* it in _items) {
  if(it.privateDownload) continue;
  [arr addObject:[it dictionaryRepresentation]];
  if (arr.count >= 100) break; // keep at most 100 items
 }
 NSData* data = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
 if (data) {
  [[NSFileManager defaultManager] createDirectoryAtPath:DownloadsDataDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
  [data writeToFile:DownloadsPersistencePath() atomically:YES];
  chmod(DownloadsPersistencePath().fileSystemRepresentation,0600);
 }
}

- (void)loadHistory {
 NSData* data = [NSData dataWithContentsOfFile:DownloadsPersistencePath()];
 if (!data) return;
 NSArray* arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
 if (![arr isKindOfClass:[NSArray class]]) return;
 [_items removeAllObjects];
 for (NSDictionary* d in arr) {
  SlateDownloadItem* it = [SlateDownloadItem fromDictionary:d];
  if(it) [_items addObject:it];
 }
}

#pragma mark - WKDownloadDelegate

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL * _Nullable destination))completionHandler {
 NSString* name = suggestedFilename.length ? suggestedFilename : download.originalRequest.URL.lastPathComponent;
 if (!name.length) name = @"download";
 SlateDownloadItem* item = [self itemForDownload:download];
 if(!item) { completionHandler(nil); return; }
 NSURL* dest = DownloadStagingURL(item.targetDirectory ?: self.downloadsDirectory);
 if([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse*)response).statusCode>=400) {
  if(item) { item.state=SlateDownloadStateFailed; item.errorDescription=[NSString stringWithFormat:@"The website returned HTTP %ld.",(long)((NSHTTPURLResponse*)response).statusCode]; item.activeDownload=nil; [self notifyChanged]; }
  completionHandler(nil); return;
 }
 if(response.URL) item.originalURL=response.URL;

 if (item) {
  NSString* chosenName = item.hasSuggestedFilename ? item.filename : name;
  if (item.hasSuggestedFilename && !chosenName.pathExtension.length &&
      [response.MIMEType.lowercaseString hasPrefix:@"image/"]) {
   UTType* type = [UTType typeWithMIMEType:response.MIMEType];
   NSString* extension = type.preferredFilenameExtension;
   if (extension.length) chosenName = [chosenName stringByAppendingPathExtension:extension];
  }
  item.filename = SafeDownloadFilename(chosenName);
  item.stagingURL = dest;
  item.destinationURL = nil;
  if (response.expectedContentLength > 0) {
   item.totalBytes = response.expectedContentLength;
  }
  [self notifyChanged];
 }
 fprintf(stderr, "SLATE_DOWNLOAD_DESTINATION file=%s path=%s\n",
         name.UTF8String, dest.path.UTF8String ?: "nil");
 completionHandler(dest);
}

- (void)finishStagedItem:(SlateDownloadItem*)item {
 item.state=SlateDownloadStateFinishing;
 [self notifyChanged];
 NSString* directory=[(item.targetDirectory ?: self.downloadsDirectory) copy];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
  NSError* error=nil;
  BOOL success=PublishDownload(item,directory,&error);
  if(!success && item.stagingURL) unlink(item.stagingURL.path.fileSystemRepresentation);
  dispatch_async(dispatch_get_main_queue(), ^{
   item.state=success ? SlateDownloadStateCompleted : SlateDownloadStateFailed;
   item.progress=success ? 1.0 : item.progress;
   item.errorDescription=error.localizedDescription;
   item.activeDownload=nil; item.activeTask=nil; item.stagingURL=nil;
   [self notifyChanged];
   fprintf(stderr,"SLATE_DOWNLOAD_PUBLISHED success=%d file=%s\n",success,item.filename.UTF8String);
  });
 });
}
- (void)downloadDidFinish:(WKDownload*)download {
 SlateDownloadItem* item=[self itemForDownload:download];
 if(item && item.state==SlateDownloadStateInProgress) [self finishStagedItem:item];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
 SlateDownloadItem* item = [self itemForDownload:download];
 if (item && item.state==SlateDownloadStateInProgress) {
  item.state = SlateDownloadStateFailed;
  item.resumeData=resumeData;
  item.errorDescription = error.localizedDescription;
  item.activeDownload = nil;
  [self notifyChanged];
  fprintf(stderr, "SLATE_DOWNLOAD_FAILED file=%s error=%s\n",
          item.filename.UTF8String, error.localizedDescription.UTF8String ?: "nil");
 }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
 (void)session; (void)bytesWritten;
 SlateDownloadItem* item = [_taskMap objectForKey:downloadTask];
 if (item) {
  item.receivedBytes = totalBytesWritten;
  if (totalBytesExpectedToWrite > 0) {
   item.totalBytes = totalBytesExpectedToWrite;
   item.progress = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:SlateDownloadProgressNotification object:self];
 }
}

- (void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)downloadTask didFinishDownloadingToURL:(NSURL*)location {
 (void)session;
 SlateDownloadItem* item=[_taskMap objectForKey:downloadTask];
 if(!item || item.state!=SlateDownloadStateInProgress) return;
 NSURLResponse* response=downloadTask.response;
 if([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse*)response).statusCode>=400) {
  item.state=SlateDownloadStateFailed; item.errorDescription=[NSString stringWithFormat:@"The website returned HTTP %ld.",(long)((NSHTTPURLResponse*)response).statusCode]; item.activeTask=nil; [self notifyChanged]; return;
 }
 if(response.URL) item.originalURL=response.URL;
 if(!item.hasSuggestedFilename && downloadTask.response.suggestedFilename.length) item.filename=downloadTask.response.suggestedFilename.lastPathComponent;
 // NSURLSession removes its temporary file after this callback. A same-volume
 // move retains it without copying a large file on the main thread.
 item.stagingURL=DownloadStagingURL(NSTemporaryDirectory());
 NSError* error=nil;
 if(![NSFileManager.defaultManager moveItemAtURL:location toURL:item.stagingURL error:&error]) {
  item.state=SlateDownloadStateFailed; item.errorDescription=error.localizedDescription;
  item.activeTask=nil; [self notifyChanged]; return;
 }
 item.state=SlateDownloadStateFinishing; [self notifyChanged];
 NSString* directory=[(item.targetDirectory ?: self.downloadsDirectory) copy];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
  NSURL* local=DownloadStagingURL(directory);
  NSError* copyError=nil;
  BOOL copied=[NSFileManager.defaultManager copyItemAtURL:item.stagingURL toURL:local error:&copyError];
  [NSFileManager.defaultManager removeItemAtURL:item.stagingURL error:nil];
  if(!copied) [NSFileManager.defaultManager removeItemAtURL:local error:nil];
  dispatch_async(dispatch_get_main_queue(), ^{
   item.stagingURL=local;
   if(copied) [self finishStagedItem:item];
   else { item.state=SlateDownloadStateFailed; item.errorDescription=copyError.localizedDescription; item.activeTask=nil; [self notifyChanged]; }
  });
 });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
 (void)session;
 if (error && [task isKindOfClass:[NSURLSessionDownloadTask class]]) {
  SlateDownloadItem* item = [_taskMap objectForKey:(NSURLSessionDownloadTask*)task];
  if (item && item.state == SlateDownloadStateInProgress) {
   item.state = (error.code == NSURLErrorCancelled) ? SlateDownloadStateCancelled : SlateDownloadStateFailed;
   item.errorDescription = error.localizedDescription;
   item.activeTask = nil;
   [self notifyChanged];
  }
 }
}

@end
