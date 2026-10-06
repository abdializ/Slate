#import "platform/macos/favicon_loader.h"
#import <AppKit/AppKit.h>
#include <cassert>
#include <functional>
#include <iostream>

static NSData* icon;
static NSInteger starts=0, current=0, peak=0;
@interface IconProtocol : NSURLProtocol
@property(nonatomic) BOOL counted;
@end
@implementation IconProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest*)request { return [request.URL.host isEqualToString:@"icons.test"]; }
+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request { return request; }
- (void)startLoading {
 self.counted=YES; starts++; current++; peak=MAX(peak,current);
 NSString* path=self.request.URL.path;
 NSDictionary* headers=[path isEqualToString:@"/declared-big"] ? @{@"Content-Length":@"999999"} : @{};
 NSHTTPURLResponse* response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
 [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
 if ([path hasPrefix:@"/slow"]) return;
 if ([path isEqualToString:@"/chunked-big"]) {
  NSData* chunk=[NSMutableData dataWithLength:64*1024];
  for(int i=0;i<6;i++) [self.client URLProtocol:self didLoadData:chunk];
 } else [self.client URLProtocol:self didLoadData:icon];
 [self.client URLProtocolDidFinishLoading:self];
 if(self.counted) { self.counted=NO; current--; }
}
- (void)stopLoading { if(self.counted) { self.counted=NO; current--; } }
@end
static void waitUntil(const char* stage, BOOL (^done)(void)) {
 NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:6];
 while(!done() && deadline.timeIntervalSinceNow>0)
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
 if(!done()) std::cerr << "Timeout: " << stage << "\n";
 assert(done());
}
int main() {
 @autoreleasepool {
  NSBitmapImageRep* large=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:512 pixelsHigh:512 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  memset(large.bitmapData,127,large.bytesPerRow*large.pixelsHigh);
  icon=[large representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  __weak SlateFaviconLoader* weak=nil;
  @autoreleasepool {
  NSURLSessionConfiguration* cfg=[NSURLSessionConfiguration ephemeralSessionConfiguration]; cfg.protocolClasses=@[IconProtocol.class];
  SlateFaviconLoader* loader=[[SlateFaviconLoader alloc] initWithConfiguration:cfg];
  __block NSData* result=nil;
  [loader loadURL:[NSURL URLWithString:@"https://icons.test/icon"] private:NO completion:^(NSData* data) { result=data; }];
  waitUntil("icon result", ^BOOL {return result!=nil;});
  NSBitmapImageRep* small=[NSBitmapImageRep imageRepWithData:result];
  assert(small.pixelsWide==64 && small.pixelsHigh==64);
  std::cout<<"512px icon decoded storage: "<<large.bytesPerRow*large.pixelsHigh<<" -> "<<small.bytesPerRow*small.pixelsHigh<<" bytes\n";
  NSInteger before=starts; result=nil;
  [loader loadURL:[NSURL URLWithString:@"https://icons.test/icon"] private:NO completion:^(NSData* data){result=data;}];
  waitUntil("icon result", ^BOOL {return result!=nil;}); assert(starts==before);
  result=nil;
  [loader loadURL:[NSURL URLWithString:@"https://icons.test/icon"] private:YES completion:^(NSData* data){result=data;}];
  waitUntil("icon result", ^BOOL {return result!=nil;}); assert(starts==before+1);
  [loader trimCache]; result=nil;
  [loader loadURL:[NSURL URLWithString:@"https://icons.test/icon"] private:NO completion:^(NSData* data){result=data;}];
  waitUntil("icon result", ^BOOL {return result!=nil;}); assert(starts==before+2);
  __block int invalidResults=0;
  const NSInteger validStarts=starts;
  for(NSURL* url in @[[NSURL URLWithString:@"file:///tmp/icon.png"],[NSURL URLWithString:@"data:image/png;base64,AAAA"]])
   [loader loadURL:url private:NO completion:^(NSData*){invalidResults++;}];
  [loader loadURL:nil private:NO completion:^(NSData*){invalidResults++;}];
  assert(starts==validStarts && invalidResults==0);
  for(NSString* path in @[@"declared-big",@"chunked-big"])
   [loader loadURL:[NSURL URLWithString:[@"https://icons.test/" stringByAppendingString:path]] private:NO completion:^(NSData*){invalidResults++;}];
  waitUntil("active tasks complete", ^BOOL {return [[loader valueForKey:@"active"] count]==0;}); assert(invalidResults==0);
  result=nil;
  SlateFaviconRequest* cached=[loader loadURL:[NSURL URLWithString:@"https://icons.test/icon"] private:NO completion:^(NSData* data){result=data;}];
  [cached cancel];
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; assert(!result);
  // Distinct incompressible thumbnails exercise the byte cap as well as LRU eviction.
  NSBitmapImageRep* noisy=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:64 pixelsHigh:64 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  uint32_t random=1234567;
  for(NSInteger i=0;i<noisy.bytesPerRow*noisy.pixelsHigh;i++) { random^=random<<13; random^=random>>17; random^=random<<5; noisy.bitmapData[i]=random&255; }
  icon=[noisy representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  for(int i=0;i<140;i++) {
   result=nil;
   [loader loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://icons.test/lru/%d",i]] private:NO completion:^(NSData* data){result=data;}];
   waitUntil("cache fill", ^BOOL {return result!=nil;});
   assert([[loader valueForKey:@"cache"] count]<=128);
   assert([[loader valueForKey:@"cachedBytes"] unsignedIntegerValue]<=2*1024*1024);
  }
  before=starts; result=nil;
  [loader loadURL:[NSURL URLWithString:@"https://icons.test/lru/0"] private:NO completion:^(NSData* data){result=data;}];
  waitUntil("evicted icon reloaded", ^BOOL {return result!=nil;}); assert(starts==before+1);
  NSMutableArray<SlateFaviconRequest*>* tokens=[NSMutableArray array];
  before=starts;
  for(int i=0;i<150;i++)
   [tokens addObject:[loader loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://icons.test/slow/%d",i]] private:NO completion:^(NSData*){invalidResults++;}]];
  waitUntil("four active downloads", ^BOOL {return starts>=before+4;});
  assert(starts==before+4 && peak<=4);
  assert([[loader valueForKey:@"pending"] count]<=128);
  for(SlateFaviconRequest* request in tokens) [request cancel];
  waitUntil("active tasks complete", ^BOOL {return [[loader valueForKey:@"active"] count]==0;});
  assert(invalidResults==0); assert([[loader valueForKey:@"pending"] count]==0);
  weak=loader;
  [loader invalidate]; loader=nil;
  }
  waitUntil("loader released", ^BOOL {return weak==nil;});
  std::cout<<"Favicon limits, cache isolation, pressure eviction, cancellation, queue bound, and service teardown passed\n";
 }
}
