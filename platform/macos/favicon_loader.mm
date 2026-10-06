#import "favicon_loader.h"
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>

static constexpr NSUInteger kMaxIconBytes = 256 * 1024;
static constexpr NSUInteger kMaxActiveIcons = 4;
static constexpr NSUInteger kMaxQueuedIcons = 128;

@interface SlateFaviconRequest ()
@property(nonatomic, weak) SlateFaviconLoader* owner;
@property(nonatomic, strong) NSURL* url;
@property(nonatomic, strong) NSURLSessionDataTask* task;
@property(nonatomic, strong) NSMutableData* bytes;
@property(nonatomic, copy) void (^completion)(NSData*);
@property(nonatomic) BOOL privateIcon;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) NSUInteger redirects;
@end
@interface SlateFaviconLoader ()
@property(nonatomic, strong) NSURLSession* session;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSData*>* cache;
@property(nonatomic, strong) NSMutableArray<NSString*>* cacheOrder;
@property(nonatomic) NSUInteger cachedBytes;
@property(nonatomic) BOOL invalidated;
@property(nonatomic, strong) NSMutableArray<SlateFaviconRequest*>* pending;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, SlateFaviconRequest*>* active;
- (void)cancelRequest:(SlateFaviconRequest*)request;
- (void)pump;
@end
@implementation SlateFaviconRequest
- (void)cancel { [self.owner cancelRequest:self]; }
@end

static NSData* SmallIcon(NSData* data) {
 if (!data.length || data.length > kMaxIconBytes) return nil;
 CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,
   (__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceShouldCache:@NO});
 if (!source) return nil;
 NSDictionary* properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr));
 const uint64_t width = [properties[(__bridge NSString*)kCGImagePropertyPixelWidth] unsignedLongLongValue];
 const uint64_t height = [properties[(__bridge NSString*)kCGImagePropertyPixelHeight] unsignedLongLongValue];
 CGImageRef image = nullptr;
 if (width && height && width <= 4096 && height <= 4096 && width * height <= 4 * 1024 * 1024) {
  image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
   (__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
   (__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@64,
   (__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,
   (__bridge NSString*)kCGImageSourceShouldCacheImmediately:@YES});
 }
 CFRelease(source);
 if (!image) return nil;
 NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
 CGImageRelease(image);
 return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

@implementation SlateFaviconLoader
+ (instancetype)sharedLoader {
 static SlateFaviconLoader* loader;
 static dispatch_once_t once;
 dispatch_once(&once, ^{ loader = [[self alloc] initWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]]; });
 return loader;
}
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration*)configuration {
 if ((self = [super init])) {
  configuration = [configuration copy];
  configuration.URLCache = nil;
  configuration.HTTPCookieStorage = nil;
  configuration.HTTPShouldSetCookies = NO;
  configuration.URLCredentialStorage = nil;
  configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  configuration.timeoutIntervalForRequest = 4;
  configuration.timeoutIntervalForResource = 6;
  configuration.HTTPMaximumConnectionsPerHost = 2;
  self.cache = [NSMutableDictionary dictionary];
  self.cacheOrder = [NSMutableArray array];
  self.pending = [NSMutableArray array];
  self.active = [NSMutableDictionary dictionary];
  self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
 }
 return self;
}
- (SlateFaviconRequest*)loadURL:(NSURL*)url private:(BOOL)isPrivate completion:(void (^)(NSData*))completion {
 NSAssert(NSThread.isMainThread, @"Favicon requests belong to the UI thread");
 SlateFaviconRequest* request = [[SlateFaviconRequest alloc] init];
 request.owner = self; request.url = url; request.privateIcon = isPrivate;
 request.completion = completion;
 if (!url || self.invalidated || url.absoluteString.length > 8192 || ![@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) {
  request.completion = nil;
  return request;
 }
 NSData* cached = isPrivate ? nil : [self cachedIcon:url.absoluteString];
 if (cached) {
  [self deliverCached:cached request:request];
 } else {
  // A background icon must not build an unbounded queue during rapid navigation.
  if (self.pending.count >= kMaxQueuedIcons) [self.pending.firstObject cancel];
  [self.pending addObject:request];
  [self pump];
 }
 return request;
}
- (NSData*)cachedIcon:(NSString*)key {
 NSData* data = self.cache[key];
 if (data) { [self.cacheOrder removeObject:key]; [self.cacheOrder addObject:key]; }
 return data;
}
- (void)deliverCached:(NSData*)cached request:(SlateFaviconRequest*)request {
 // Never reenter navigation callbacks; cancellation can suppress cached results.
 dispatch_async(dispatch_get_main_queue(), ^{
  if (!request.cancelled && request.completion) request.completion(cached);
  request.completion = nil;
 });
}
- (void)storeIcon:(NSData*)png key:(NSString*)key {
 if (png.length > 2 * 1024 * 1024) return;
 self.cachedBytes -= self.cache[key].length;
 [self.cache removeObjectForKey:key]; [self.cacheOrder removeObject:key];
 while (self.cacheOrder.count && (self.cache.count >= 128 || self.cachedBytes + png.length > 2 * 1024 * 1024)) {
  NSString* oldest = self.cacheOrder.firstObject;
  self.cachedBytes -= self.cache[oldest].length;
  [self.cache removeObjectForKey:oldest]; [self.cacheOrder removeObjectAtIndex:0];
 }
 self.cache[key] = png; [self.cacheOrder addObject:key]; self.cachedBytes += png.length;
}
- (void)pump {
 while (self.active.count < kMaxActiveIcons && self.pending.count) {
  SlateFaviconRequest* request = self.pending.firstObject;
  [self.pending removeObjectAtIndex:0];
  if (request.cancelled) continue;
  // An earlier active request may have filled the cache while this job waited.
  NSData* cached = request.privateIcon ? nil : [self cachedIcon:request.url.absoluteString];
  if (cached) { [self deliverCached:cached request:request]; continue; }
  request.bytes = [NSMutableData data];
  request.task = [self.session dataTaskWithURL:request.url];
  self.active[@(request.task.taskIdentifier)] = request;
  [request.task resume];
 }
}
- (void)cancelRequest:(SlateFaviconRequest*)request {
 NSAssert(NSThread.isMainThread, @"Favicon cancellation belongs to the UI thread");
 request.cancelled = YES;
 request.completion = nil;
 request.bytes = nil;
 [self.pending removeObjectIdenticalTo:request];
 [request.task cancel];
 // Count active cancelled tasks until network completion arrives.
}
- (void)invalidate {
 self.invalidated = YES;
 for (SlateFaviconRequest* request in [self.pending copy]) [request cancel];
 for (SlateFaviconRequest* request in self.active.allValues) [request cancel];
 [self.session invalidateAndCancel];
 self.session = nil;
 [self trimCache];
}
- (void)trimCache { [self.cache removeAllObjects]; [self.cacheOrder removeAllObjects]; self.cachedBytes = 0; }
- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task
 didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
 SlateFaviconRequest* request = self.active[@(task.taskIdentifier)];
 const NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse*)response).statusCode : 0;
 const BOOL accept = request && !request.cancelled && status >= 200 && status < 300 && response.expectedContentLength <= (int64_t)kMaxIconBytes;
 completion(accept ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data {
 SlateFaviconRequest* request = self.active[@(task.taskIdentifier)];
 if (!request || request.cancelled) return;
 if (data.length > kMaxIconBytes - request.bytes.length) { [request cancel]; return; }
 [request.bytes appendData:data];
}
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task
 willPerformHTTPRedirection:(NSHTTPURLResponse*)response newRequest:(NSURLRequest*)redirect
 completionHandler:(void (^)(NSURLRequest*))completion {
 SlateFaviconRequest* request = self.active[@(task.taskIdentifier)];
 const BOOL accept = request && !request.cancelled && ++request.redirects <= 5 &&
  [@[@"https", @"http"] containsObject:redirect.URL.scheme.lowercaseString];
 completion(accept ? redirect : nil);
}
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
 SlateFaviconRequest* request = self.active[@(task.taskIdentifier)];
 if (!request) return;
 NSData* png = (!error && !request.cancelled) ? SmallIcon(request.bytes) : nil;
 request.bytes = nil; request.task = nil;
 [self.active removeObjectForKey:@(task.taskIdentifier)];
 if (png && !request.privateIcon) [self storeIcon:png key:request.url.absoluteString];
 void (^completion)(NSData*) = request.completion;
 request.completion = nil;
 if (png && completion) completion(png);
 [self pump];
}
@end
