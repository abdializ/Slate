// File purpose: Implements high-alert privacy/security settings, tracking-parameter stripping,
// HTTPS-Only upgrades, WebRTC IP-leak blocking, and native macOS Network.framework Incognito VPN/Proxy tunneling.

#import "platform/macos/privacy_security.h"
#import <Network/Network.h>
#import <Security/Security.h>

static NSString* const kStrictKey = @"slate.privacy.strictTracking";
static NSString* const kHttpsOnlyKey = @"slate.privacy.httpsOnly";
static NSString* const kWebRTCBlockKey = @"slate.privacy.blockWebRTCIncognito";
static NSString* const kProxyModeKey = @"slate.privacy.incognitoProxy.mode";
static NSString* const kProxyHostKey = @"slate.privacy.incognitoProxy.host";
static NSString* const kProxyPortKey = @"slate.privacy.incognitoProxy.port";
static NSString* const kProxyUserKey = @"slate.privacy.incognitoProxy.username";
static NSString* const kProxyFailClosedKey = @"slate.privacy.incognitoProxy.failClosed";
static NSString* const kProxyKeychainService = @"dev.slate.browser.incognito-proxy";
static NSString* const kProxyKeychainAccount = @"incognito-proxy-password";

@implementation SlatePrivacySecurity

+ (BOOL)boolForKey:(NSString*)key defaultValue:(BOOL)fallback {
  NSUserDefaults* ud = NSUserDefaults.standardUserDefaults;
  if ([ud objectForKey:key] == nil) return fallback;
  return [ud boolForKey:key];
}

+ (BOOL)strictTrackingProtectionEnabled { return [self boolForKey:kStrictKey defaultValue:YES]; }
+ (void)setStrictTrackingProtectionEnabled:(BOOL)enabled { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kStrictKey]; }

+ (BOOL)httpsOnlyEnabled { return [self boolForKey:kHttpsOnlyKey defaultValue:YES]; }
+ (void)setHttpsOnlyEnabled:(BOOL)enabled { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kHttpsOnlyKey]; }

+ (BOOL)blockWebRTCInIncognito { return [self boolForKey:kWebRTCBlockKey defaultValue:YES]; }
+ (void)setBlockWebRTCInIncognito:(BOOL)enabled { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kWebRTCBlockKey]; }

+ (SlateProxyMode)incognitoProxyMode {
  return (SlateProxyMode)[NSUserDefaults.standardUserDefaults integerForKey:kProxyModeKey];
}
+ (void)setIncognitoProxyMode:(SlateProxyMode)mode {
  [NSUserDefaults.standardUserDefaults setInteger:mode forKey:kProxyModeKey];
}

+ (NSString*)incognitoProxyHost {
  if ([self incognitoProxyMode] == SlateProxyModeTor) return @"127.0.0.1";
  return [NSUserDefaults.standardUserDefaults stringForKey:kProxyHostKey] ?: @"";
}
+ (void)setIncognitoProxyHost:(NSString*)host {
  NSString* clean = [host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  [NSUserDefaults.standardUserDefaults setObject:clean forKey:kProxyHostKey];
}

+ (NSInteger)incognitoProxyPort {
  if ([self incognitoProxyMode] == SlateProxyModeTor) return 9050;
  return [NSUserDefaults.standardUserDefaults integerForKey:kProxyPortKey];
}
+ (void)setIncognitoProxyPort:(NSInteger)port {
  [NSUserDefaults.standardUserDefaults setInteger:MAX(0, MIN(65535, port)) forKey:kProxyPortKey];
}

+ (NSString*)incognitoProxyUsername {
  return [NSUserDefaults.standardUserDefaults stringForKey:kProxyUserKey] ?: @"";
}
+ (void)setIncognitoProxyUsername:(NSString*)username {
  NSString* clean = [username stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
  [NSUserDefaults.standardUserDefaults setObject:clean forKey:kProxyUserKey];
}

+ (NSString*)incognitoProxyPassword {
  NSDictionary* query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: kProxyKeychainService,
    (__bridge id)kSecAttrAccount: kProxyKeychainAccount,
    (__bridge id)kSecReturnData: @YES,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
  };
  CFTypeRef out = nullptr;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &out) == errSecSuccess && out) {
    NSData* data = (__bridge_transfer NSData*)out;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  }
  return @"";
}

+ (void)setIncognitoProxyPassword:(NSString*)password {
  NSDictionary* baseQuery = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: kProxyKeychainService,
    (__bridge id)kSecAttrAccount: kProxyKeychainAccount,
  };
  SecItemDelete((__bridge CFDictionaryRef)baseQuery);
  if (!password.length) return;
  NSData* data = [password dataUsingEncoding:NSUTF8StringEncoding];
  if (!data.length) return;
  NSMutableDictionary* add = [baseQuery mutableCopy];
  add[(__bridge id)kSecValueData] = data;
  SecItemAdd((__bridge CFDictionaryRef)add, nullptr);
}

+ (BOOL)incognitoProxyFailClosed { return [self boolForKey:kProxyFailClosedKey defaultValue:YES]; }
+ (void)setIncognitoProxyFailClosed:(BOOL)failClosed { [NSUserDefaults.standardUserDefaults setBool:failClosed forKey:kProxyFailClosedKey]; }

+ (BOOL)isIncognitoTunnelActive {
  SlateProxyMode mode = [self incognitoProxyMode];
  if (mode == SlateProxyModeOff) return NO;
  if (mode == SlateProxyModeTor) return YES;
  NSString* host = [self incognitoProxyHost];
  NSInteger port = [self incognitoProxyPort];
  return host.length > 0 && port > 0 && port <= 65535;
}

+ (void)applyIncognitoProxyToDataStore:(WKWebsiteDataStore*)store {
  if (!store) return;
  if (@available(macOS 14.0, *)) {
    if (![self isIncognitoTunnelActive]) {
      store.proxyConfigurations = @[];
      return;
    }
    SlateProxyMode mode = [self incognitoProxyMode];
    NSString* host = [self incognitoProxyHost];
    NSInteger port = [self incognitoProxyPort];
    NSString* portStr = [NSString stringWithFormat:@"%ld", (long)port];
    nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, portStr.UTF8String);
    if (!endpoint) return;

    nw_proxy_config_t config = nullptr;
    if (mode == SlateProxyModeHTTP) {
      config = nw_proxy_config_create_http_connect(endpoint, nullptr);
    } else {
      config = nw_proxy_config_create_socksv5(endpoint);
    }
    if (!config) return;

    NSString* user = [self incognitoProxyUsername];
    if (mode != SlateProxyModeTor && user.length > 0) {
      NSString* pass = [self incognitoProxyPassword];
      nw_proxy_config_set_username_and_password(config, user.UTF8String, pass.UTF8String);
    }
    nw_proxy_config_set_failover_allowed(config, ![self incognitoProxyFailClosed]);
    // Keep localhost/.local direct so local dev servers still resolve.
    nw_proxy_config_add_excluded_domain(config, "localhost");
    nw_proxy_config_add_excluded_domain(config, "127.0.0.1");
    nw_proxy_config_add_excluded_domain(config, "::1");
    nw_proxy_config_add_excluded_domain(config, "local");

    store.proxyConfigurations = @[config];
  }
}

+ (NSURL*)sanitizedURLForNavigation:(NSURL*)url {
  if (!url) return url;
  NSURLComponents* comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
  if (!comps || !comps.host.length) return url;
  NSString* scheme = comps.scheme.lowercaseString;
  NSString* host = comps.host.lowercaseString;
  BOOL isLocal = [host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] ||
                 [host isEqualToString:@"::1"] || [host hasSuffix:@".local"];

  BOOL changed = NO;
  if ([self httpsOnlyEnabled] && [scheme isEqualToString:@"http"] && !isLocal) {
    comps.scheme = @"https";
    changed = YES;
  }

  if ([self strictTrackingProtectionEnabled] && comps.queryItems.count > 0) {
    static NSSet<NSString*>* kTrackingParams = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      kTrackingParams = [NSSet setWithArray:@[
        @"fbclid", @"gclid", @"gbraid", @"wbraid", @"dclid", @"msclkid", @"yclid",
        @"twclid", @"ttclid", @"igshid", @"mc_cid", @"mc_eid", @"_hsenc", @"_hsmi",
        @"ref_src", @"ref_url", @"si", @"s_cid", @"oly_anon_id", @"oly_enc_id",
        @"vero_id", @"mkt_tok", @"_openstat", @"wickedid", @"rb_clickid"
      ]];
    });
    NSMutableArray<NSURLQueryItem*>* kept = [NSMutableArray arrayWithCapacity:comps.queryItems.count];
    for (NSURLQueryItem* item in comps.queryItems) {
      NSString* lower = item.name.lowercaseString;
      if ([lower hasPrefix:@"utm_"] || [kTrackingParams containsObject:lower]) {
        changed = YES;
        continue;
      }
      [kept addObject:item];
    }
    if (changed) {
      comps.queryItems = kept.count ? kept : nil;
    }
  }
  return changed ? (comps.URL ?: url) : url;
}

+ (NSString*)hardeningScriptForIncognito:(BOOL)incognito {
  BOOL strict = [self strictTrackingProtectionEnabled];
  BOOL blockRTC = incognito && [self blockWebRTCInIncognito];
  if (!strict && !blockRTC) return @"";

  NSMutableString* js = [NSMutableString stringWithString:
    @"(function(){'use strict';"
     "try{var h=(location&&location.hostname||'').toLowerCase();"
     "if(h==='challenges.cloudflare.com'||h.endsWith('.cloudflare.com')||h==='hcaptcha.com'||h.endsWith('.hcaptcha.com')||"
     "h==='recaptcha.net'||h.endsWith('.recaptcha.net')||h.endsWith('.arkoselabs.com')||h.endsWith('.funcaptcha.com'))return;}catch(e){}"
     "var sym=Symbol.for('__slateHardening');if(window[sym])return;window[sym]=true;"];
  if (strict) {
    [js appendString:
     @"try{if(window.Navigator&&Navigator.prototype){"
      "if(!('globalPrivacyControl' in Navigator.prototype))Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:function(){return true;},configurable:true,enumerable:true});"
      "if(!('doNotTrack' in Navigator.prototype))Object.defineProperty(Navigator.prototype,'doNotTrack',{get:function(){return '1';},configurable:true,enumerable:true});"
      "}}catch(e){}"];
  }
  if (blockRTC) {
    // Prevent STUN/ICE WebRTC real-IP leaks in Incognito mode.
    [js appendString:
     @"try{"
      "const blocked=function(){throw new DOMException('WebRTC is disabled in Slate Incognito to prevent IP leaks','NotAllowedError');};"
      "Object.defineProperty(window,'RTCPeerConnection',{value:blocked,configurable:false,writable:false});"
      "Object.defineProperty(window,'webkitRTCPeerConnection',{value:blocked,configurable:false,writable:false});"
      "if(navigator.mediaDevices&&navigator.mediaDevices.enumerateDevices){"
      "  navigator.mediaDevices.enumerateDevices=()=>Promise.resolve([]);"
      "}"
      "}catch(e){}"];
  }
  [js appendString:@"})();"];
  return js;
}

+ (void)testIncognitoTunnelWithCompletion:(void (^)(BOOL reachable, NSString* message))completion {
  if (!completion) return;
  if (![self isIncognitoTunnelActive]) {
    completion(NO, @"Tunnel is Off or missing host/port.");
    return;
  }
  NSString* host = [self incognitoProxyHost];
  NSInteger port = [self incognitoProxyPort];
  NSString* portStr = [NSString stringWithFormat:@"%ld", (long)port];
  nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, portStr.UTF8String);
  nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
  nw_connection_t conn = nw_connection_create(endpoint, params);
  __block BOOL finished = NO;
  dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

  void (^finish)(BOOL, NSString*) = ^(BOOL ok, NSString* msg) {
    if (finished) return;
    finished = YES;
    nw_connection_cancel(conn);
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(ok, msg);
    });
  };

  nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t state, nw_error_t error) {
    if (state == nw_connection_state_ready) {
      finish(YES, [NSString stringWithFormat:@"Connected to %@:%ld", host, (long)port]);
    } else if (state == nw_connection_state_failed || state == nw_connection_state_waiting) {
      finish(NO, [NSString stringWithFormat:@"Could not reach %@:%ld — check that your VPN/Tor proxy is running.", host, (long)port]);
    }
  });
  nw_connection_set_queue(conn, q);
  nw_connection_start(conn);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), q, ^{
    finish(NO, [NSString stringWithFormat:@"Timed out connecting to %@:%ld", host, (long)port]);
  });
}

@end
