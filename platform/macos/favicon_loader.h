// File purpose: Declares bounded, cancellable icon requests, thumbnail decoding, and an in-memory
// cache.

#pragma once
#import <Foundation/Foundation.h>

// Slate note: The returned request token lets navigation or tab closure cancel work owned by that tab.
@interface SlateFaviconRequest : NSObject
- (void)cancel;
@end

// Main-thread service. No persistent cache, cookies, or credential storage.
@interface SlateFaviconLoader : NSObject <NSURLSessionDataDelegate>
+ (instancetype)sharedLoader;
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration*)configuration;
- (SlateFaviconRequest*)loadURL:(NSURL*)url private:(BOOL)isPrivate
                    completion:(void (^)(NSData* png))completion;
- (void)trimCache;
- (void)invalidate; // Shutdown/testing; the shared service lives for the application.
@end
