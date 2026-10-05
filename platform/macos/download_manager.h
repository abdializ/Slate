#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, SlateDownloadState) {
    SlateDownloadStateInProgress = 0,
    SlateDownloadStateCompleted,
    SlateDownloadStateFailed,
    SlateDownloadStateCancelled,
    SlateDownloadStatePaused,
    SlateDownloadStateFinishing
};

@interface SlateDownloadItem : NSObject

@property (nonatomic, copy) NSString* identifier;
@property (nonatomic, copy) NSString* filename;
@property (nonatomic, strong) NSURL* originalURL;
@property (nonatomic, strong) NSURL* destinationURL;
@property (nonatomic, assign) int64_t totalBytes;
@property (nonatomic, assign) int64_t receivedBytes;
@property (nonatomic, assign) double progress; // 0.0 to 1.0
@property (nonatomic, assign) SlateDownloadState state;
@property (nonatomic, strong) NSDate* startDate;
@property (nonatomic, copy) NSString* errorDescription;
@property (nonatomic, strong) WKDownload* activeDownload;
@property (nonatomic, weak) WKWebView* sourceWebView;
@property (nonatomic, strong) NSData* resumeData;
@property (nonatomic, strong) NSURL* stagingURL;
@property (nonatomic, copy) NSString* targetDirectory;
@property (nonatomic, assign) BOOL privateDownload;
@property (nonatomic, assign) BOOL usesURLSession;
@property (nonatomic, assign) BOOL hasSuggestedFilename;
@property (nonatomic, assign) double bytesPerSecond;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;
@property (nonatomic, assign) int64_t lastSampleBytes;
@property (nonatomic, readonly) BOOL canResume;
@property (nonatomic, readonly) BOOL fileAvailable;
@property (nonatomic, strong) NSURLSessionDownloadTask* activeTask;

- (NSString*)formattedSize;
- (NSString*)formattedStatus;
- (NSString*)formattedDate;
- (NSImage*)fileIcon;
- (void)showInFinder;
- (void)openFile;
- (void)cancel;
- (void)pause;
- (void)resume;

- (NSDictionary*)dictionaryRepresentation;
+ (instancetype)fromDictionary:(NSDictionary*)dict;

@end

extern NSString* const SlateDownloadsChangedNotification;
extern NSString* const SlateDownloadProgressNotification;

@interface SlateDownloadManager : NSObject <WKDownloadDelegate, NSURLSessionDownloadDelegate>

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSArray<SlateDownloadItem*>* items;
@property (nonatomic, readonly) NSArray<SlateDownloadItem*>* activeDownloads;
@property (nonatomic, readonly) BOOL hasActiveDownloads;
@property (nonatomic, readonly) double overallProgress;
@property (nonatomic, copy) NSString* downloadsDirectory;

- (void)registerDownload:(WKDownload*)download forWebView:(WKWebView*)webView;
- (void)registerDownload:(WKDownload*)download forWebView:(WKWebView*)webView
       requestedFilename:(NSString*)filename inDirectory:(NSString*)directory;
- (SlateDownloadItem*)startDownloadFromURL:(NSURL*)url suggestedFilename:(NSString*)filename;
- (void)cancelDownloadItem:(SlateDownloadItem*)item;
- (void)pauseDownloadItem:(SlateDownloadItem*)item;
- (void)resumeDownloadItem:(SlateDownloadItem*)item;
- (void)removeItem:(SlateDownloadItem*)item;
- (void)clearCompleted;
- (SlateDownloadItem*)itemForDownload:(WKDownload*)download;

+ (NSURL*)uniqueDestinationURLForFilename:(NSString*)filename inDirectory:(NSString*)directory;

@end
