// File purpose: Centralized high-alert privacy/security settings, tracking parameter stripping,
// WebRTC leak protection, HTTPS-Only enforcement, and Incognito VPN/Proxy tunnel configuration.

#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SlateProxyMode) {
  SlateProxyModeOff = 0,
  SlateProxyModeTor = 1,
  SlateProxyModeSOCKS5 = 2,
  SlateProxyModeHTTP = 3,
};

@interface SlatePrivacySecurity : NSObject

+ (BOOL)strictTrackingProtectionEnabled;
+ (void)setStrictTrackingProtectionEnabled:(BOOL)enabled;

+ (BOOL)httpsOnlyEnabled;
+ (void)setHttpsOnlyEnabled:(BOOL)enabled;

+ (BOOL)blockWebRTCInIncognito;
+ (void)setBlockWebRTCInIncognito:(BOOL)enabled;

+ (SlateProxyMode)incognitoProxyMode;
+ (void)setIncognitoProxyMode:(SlateProxyMode)mode;

+ (NSString*)incognitoProxyHost;
+ (void)setIncognitoProxyHost:(NSString*)host;

+ (NSInteger)incognitoProxyPort;
+ (void)setIncognitoProxyPort:(NSInteger)port;

+ (NSString*)incognitoProxyUsername;
+ (void)setIncognitoProxyUsername:(NSString*)username;

+ (NSString*)incognitoProxyPassword;
+ (void)setIncognitoProxyPassword:(NSString*)password;

+ (BOOL)incognitoProxyFailClosed;
+ (void)setIncognitoProxyFailClosed:(BOOL)failClosed;

/// Returns YES when a valid Incognito VPN/proxy tunnel is configured and enabled.
+ (BOOL)isIncognitoTunnelActive;

/// Applies the configured Incognito VPN/proxy tunnel to a non-persistent WKWebsiteDataStore (macOS 14+).
+ (void)applyIncognitoProxyToDataStore:(WKWebsiteDataStore*)store;

/// Cleans tracking query parameters (utm_*, fbclid, gclid, etc.) and optionally upgrades http->https.
+ (NSURL*)sanitizedURLForNavigation:(NSURL*)url;

/// JavaScript injected at document start to enforce Global Privacy Control and block WebRTC IP leaks.
+ (NSString*)hardeningScriptForIncognito:(BOOL)incognito;

/// Tests TCP reachability of the configured Incognito VPN/proxy endpoint on a background queue.
+ (void)testIncognitoTunnelWithCompletion:(void (^)(BOOL reachable, NSString* message))completion;

@end

NS_ASSUME_NONNULL_END
#endif
