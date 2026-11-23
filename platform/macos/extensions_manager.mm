// File purpose: Implements Slate's native macOS WKWebExtension manager, CRX3/CRX2/ZIP/unpacked
// Chrome extension installer, and WKWebExtensionWindow/WKWebExtensionTab adapters.

#import "platform/macos/extensions_manager.h"
#include "engine/extension_shims_js.h"
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>

NSNotificationName const SlateExtensionsDidChangeNotification = @"SlateExtensionsDidChangeNotification";

@implementation SlateExtensionRecord
@end

#pragma mark - Tab & Window Adapters (macOS 15.4+)

API_AVAILABLE(macos(15.4))
@interface SlateExtensionWindowAdapter : NSObject <WKWebExtensionWindow>
@property (nonatomic, weak) SlateExtensionsManager* manager;
@end

API_AVAILABLE(macos(15.4))
@interface SlateExtensionTabAdapter : NSObject <WKWebExtensionTab>
@property (nonatomic, weak) SlateExtensionsManager* manager;
@property (nonatomic, assign) uint64_t tabId;
@end

@interface SlateExtAuthPanel : NSPanel <WKNavigationDelegate, NSWindowDelegate>
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, copy) void (^completion)(NSString* _Nullable redirectURL, NSString* _Nullable error);
@property (nonatomic, assign) BOOL finished;
@end

@implementation SlateExtAuthPanel
- (instancetype)initWithURL:(NSURL*)url completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  NSRect rect = NSMakeRect(0, 0, 520, 660);
  NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
  if (self = [super initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:NO]) {
    self.title = @"Sign In";
    self.releasedWhenClosed = NO;
    self.delegate = self;
    _completion = [completion copy];
    WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
    cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    _webView = [[WKWebView alloc] initWithFrame:self.contentView.bounds configuration:cfg];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    [self.contentView addSubview:_webView];
    if (url) [_webView loadRequest:[NSURLRequest requestWithURL:url]];
  }
  return self;
}
- (void)finishWithURL:(NSString*)redirectURL error:(NSString*)err {
  if (_finished) return;
  _finished = YES;
  auto cb = _completion;
  _completion = nil;
  [self orderOut:nil];
  if (cb) cb(redirectURL, err);
}
- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  [self finishWithURL:nil error:@"User cancelled authentication."];
}
- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  (void)webView;
  NSURL* u = action.request.URL;
  if (u && [u.host.lowercaseString hasSuffix:@".chromiumapp.org"]) {
    decisionHandler(WKNavigationActionPolicyCancel);
    [self finishWithURL:u.absoluteString error:nil];
    return;
  }
  decisionHandler(WKNavigationActionPolicyAllow);
}
@end

@interface SlateExtensionsManager () <WKWebExtensionControllerDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) NSMutableArray<SlateExtensionRecord*>* mutableExtensions;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, id>* tabAdapters;
@property (nonatomic, strong) NSMutableDictionary<NSString*, WKWebView*>* offscreenWebViews;
@property (nonatomic, strong) NSPanel* sidePanelWindow;
@property (nonatomic, strong) WKWebView* sidePanelWebView;
@property (nonatomic, strong) SlateExtAuthPanel* activeAuthPanel;
@property (nonatomic, strong) id windowAdapter;
@property (nonatomic, strong) id webExtensionController;
@property (nonatomic, weak) NSView* pendingPopupAnchor;
@property (nonatomic, assign) BOOL started;
- (id<WKWebExtensionTab>)adapterForTabId:(uint64_t)tabId API_AVAILABLE(macos(15.4));
- (id<WKWebExtensionWindow>)mainWindowAdapter API_AVAILABLE(macos(15.4));
@end

API_AVAILABLE(macos(15.4))
@implementation SlateExtensionWindowAdapter

- (NSArray<id<WKWebExtensionTab>>*)tabsForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  id<SlateExtensionHostDelegate> host = self.manager.hostDelegate;
  if (!host) return @[];
  NSArray<NSNumber*>* ids = [host extensionHostTabIds];
  NSMutableArray<id<WKWebExtensionTab>>* out = [NSMutableArray arrayWithCapacity:ids.count];
  for (NSNumber* num in ids) {
    id<WKWebExtensionTab> adapter = [self.manager adapterForTabId:num.unsignedLongLongValue];
    if (adapter) [out addObject:adapter];
  }
  return out;
}

- (nullable id<WKWebExtensionTab>)activeTabForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  id<SlateExtensionHostDelegate> host = self.manager.hostDelegate;
  if (!host) return nil;
  uint64_t sel = [host extensionHostSelectedTabId];
  return sel ? [self.manager adapterForTabId:sel] : nil;
}

- (WKWebExtensionWindowType)windowTypeForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return WKWebExtensionWindowTypeNormal;
}

- (WKWebExtensionWindowState)windowStateForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  NSWindow* win = [self.manager.hostDelegate extensionHostWindow];
  if (!win) return WKWebExtensionWindowStateNormal;
  if (win.miniaturized) return WKWebExtensionWindowStateMinimized;
  if ((win.styleMask & NSWindowStyleMaskFullScreen) != 0) return WKWebExtensionWindowStateFullscreen;
  if (win.zoomed) return WKWebExtensionWindowStateMaximized;
  return WKWebExtensionWindowStateNormal;
}

- (BOOL)isPrivateForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  id<SlateExtensionHostDelegate> host = self.manager.hostDelegate;
  if (!host) return NO;
  uint64_t sel = [host extensionHostSelectedTabId];
  return sel ? [host extensionHostIsIncognitoTabId:sel] : NO;
}

- (CGRect)frameForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  NSWindow* win = [self.manager.hostDelegate extensionHostWindow];
  return win ? win.frame : CGRectMake(0, 0, 1280, 800);
}

- (void)focusForWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  NSWindow* win = [self.manager.hostDelegate extensionHostWindow];
  [win makeKeyAndOrderFront:nil];
  if (completionHandler) completionHandler(nil);
}

@end

API_AVAILABLE(macos(15.4))
@implementation SlateExtensionTabAdapter

- (nullable id<WKWebExtensionWindow>)windowForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager mainWindowAdapter];
}

- (NSUInteger)indexInWindowForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  NSArray<NSNumber*>* ids = [self.manager.hostDelegate extensionHostTabIds];
  NSUInteger idx = [ids indexOfObject:@(self.tabId)];
  return idx == NSNotFound ? 0 : idx;
}

- (nullable WKWebView*)webViewForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
}

- (nullable NSString*)titleForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostTitleForTabId:self.tabId];
}

- (nullable NSURL*)urlForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostURLForTabId:self.tabId];
}

- (BOOL)isLoadingCompleteForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return ![self.manager.hostDelegate extensionHostIsLoadingTabId:self.tabId];
}

- (BOOL)isPinnedForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostIsPinnedTabId:self.tabId];
}

- (BOOL)isPlayingAudioForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostIsAudibleTabId:self.tabId];
}

- (BOOL)isMutedForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostIsMutedTabId:self.tabId];
}

- (void)setMuted:(BOOL)muted forWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  [self.manager.hostDelegate extensionHostToggleMuteTabId:self.tabId muted:muted];
  if (completionHandler) completionHandler(nil);
}

- (CGSize)sizeForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  return wv ? wv.bounds.size : CGSizeMake(1200, 760);
}

- (double)zoomFactorForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  return wv ? wv.pageZoom : 1.0;
}

- (void)setZoomFactor:(double)zoomFactor forWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  if (wv) wv.pageZoom = zoomFactor;
  if (completionHandler) completionHandler(nil);
}

- (void)loadURL:(NSURL*)url forWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  if (wv && url) [wv loadRequest:[NSURLRequest requestWithURL:url]];
  if (completionHandler) completionHandler(nil);
}

- (void)reloadFromOrigin:(BOOL)fromOrigin forWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  if (wv) {
    if (fromOrigin) [wv reloadFromOrigin];
    else [wv reload];
  }
  if (completionHandler) completionHandler(nil);
}

- (void)goBackForWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  if (wv && wv.canGoBack) [wv goBack];
  if (completionHandler) completionHandler(nil);
}

- (void)goForwardForWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  WKWebView* wv = [self.manager.hostDelegate extensionHostWebViewForTabId:self.tabId];
  if (wv && wv.canGoForward) [wv goForward];
  if (completionHandler) completionHandler(nil);
}

- (void)activateForWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  [self.manager.hostDelegate extensionHostActivateTabId:self.tabId];
  if (completionHandler) completionHandler(nil);
}

- (BOOL)isSelectedForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return [self.manager.hostDelegate extensionHostSelectedTabId] == self.tabId;
}

- (void)closeForWebExtensionContext:(WKWebExtensionContext*)context completionHandler:(void (^)(NSError* _Nullable))completionHandler {
  (void)context;
  [self.manager.hostDelegate extensionHostCloseTabId:self.tabId];
  if (completionHandler) completionHandler(nil);
}

- (BOOL)shouldGrantPermissionsOnUserGestureForWebExtensionContext:(WKWebExtensionContext*)context {
  (void)context;
  return YES;
}

@end

#pragma mark - Manager Implementation

@implementation SlateExtensionsManager

+ (instancetype)sharedManager {
  static SlateExtensionsManager* s_mgr = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_mgr = [[SlateExtensionsManager alloc] init];
  });
  return s_mgr;
}

+ (BOOL)isSupported {
  if (@available(macOS 15.4, *)) {
    return NSClassFromString(@"WKWebExtensionController") != nil;
  }
  return NO;
}

+ (BOOL)isValidChromeStoreId:(NSString*)s {
  if (s.length != 32) return NO;
  for (NSUInteger i = 0; i < 32; ++i) {
    unichar c = [s characterAtIndex:i];
    if (c < 'a' || c > 'p') return NO;
  }
  return YES;
}

+ (NSString*)chromeStoreExtensionIdFromURL:(NSURL*)url {
  if (!url) return nil;
  NSString* host = url.host.lowercaseString;
  BOOL isStore = [host isEqualToString:@"chromewebstore.google.com"] ||
                 [host isEqualToString:@"chrome.google.com"];
  if (!isStore) return nil;
  NSArray<NSString*>* parts = url.pathComponents;
  for (NSInteger i = (NSInteger)parts.count - 1; i >= 0; --i) {
    NSString* seg = parts[(NSUInteger)i].lowercaseString;
    if ([self isValidChromeStoreId:seg]) return seg;
  }
  return nil;
}

+ (NSString*)chromeStoreExtensionIdFromInput:(NSString*)input {
  if (!input.length) return nil;
  NSString* trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if ([self isValidChromeStoreId:trimmed.lowercaseString]) {
    return trimmed.lowercaseString;
  }
  NSURL* url = [NSURL URLWithString:trimmed];
  if (!url || !url.scheme.length) {
    url = [NSURL URLWithString:[@"https://" stringByAppendingString:trimmed]];
  }
  return [self chromeStoreExtensionIdFromURL:url];
}

- (instancetype)init {
  if (self = [super init]) {
    _mutableExtensions = [NSMutableArray array];
    _tabAdapters = [NSMutableDictionary dictionary];
    _offscreenWebViews = [NSMutableDictionary dictionary];
    if (@available(macOS 15.4, *)) {
      if (NSClassFromString(@"WKWebExtensionController")) {
        WKWebExtensionControllerConfiguration* cfg = [WKWebExtensionControllerConfiguration defaultConfiguration];
        WKWebExtensionController* ctrl = [[WKWebExtensionController alloc] initWithConfiguration:cfg];
        ctrl.delegate = self;
        _webExtensionController = ctrl;

        SlateExtensionWindowAdapter* winAdapter = [[SlateExtensionWindowAdapter alloc] init];
        winAdapter.manager = self;
        _windowAdapter = winAdapter;
      }
    }
  }
  return self;
}

- (NSArray<SlateExtensionRecord*>*)extensions {
  return [_mutableExtensions copy];
}

- (WKWebExtensionController*)controller API_AVAILABLE(macos(15.4)) {
  return (WKWebExtensionController*)_webExtensionController;
}

- (id<WKWebExtensionWindow>)mainWindowAdapter API_AVAILABLE(macos(15.4)) {
  return (id<WKWebExtensionWindow>)_windowAdapter;
}

- (id<WKWebExtensionTab>)adapterForTabId:(uint64_t)tabId API_AVAILABLE(macos(15.4)) {
  NSNumber* key = @(tabId);
  SlateExtensionTabAdapter* adapter = _tabAdapters[key];
  if (!adapter) {
    adapter = [[SlateExtensionTabAdapter alloc] init];
    adapter.manager = self;
    adapter.tabId = tabId;
    _tabAdapters[key] = adapter;
  }
  return adapter;
}

#pragma mark - Storage Paths & Registry

- (NSString*)extensionsRootDirectory {
  NSArray<NSString*>* dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
  NSString* base = dirs.firstObject ?: NSTemporaryDirectory();
  NSString* dir = [[base stringByAppendingPathComponent:@"Slate"] stringByAppendingPathComponent:@"Extensions"];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  return dir;
}

- (NSString*)registryPath {
  return [[self extensionsRootDirectory] stringByAppendingPathComponent:@"registry.json"];
}

- (void)saveRegistry {
  NSMutableArray* rows = [NSMutableArray arrayWithCapacity:_mutableExtensions.count];
  for (SlateExtensionRecord* rec in _mutableExtensions) {
    [rows addObject:@{
      @"id": rec.identifier ?: @"",
      @"name": rec.name ?: @"Extension",
      @"version": rec.version ?: @"",
      @"summary": rec.summary ?: @"",
      @"path": rec.directoryPath ?: @"",
      @"sidePanelPath": rec.sidePanelPath ?: @"",
      @"enabled": @(rec.enabled),
      @"allowInPrivate": @(rec.allowInPrivate)
    }];
  }
  NSData* data = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:nil];
  if (data) [data writeToFile:[self registryPath] atomically:YES];
}

- (void)postDidChange {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSNotificationCenter defaultCenter] postNotificationName:SlateExtensionsDidChangeNotification object:self];
  });
}

#pragma mark - Startup & Lifecycle

- (void)startIfNeeded {
  if (_started) return;
  _started = YES;
  if (![SlateExtensionsManager isSupported]) return;

  NSData* data = [NSData dataWithContentsOfFile:[self registryPath]];
  if (!data) return;
  NSArray* rows = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![rows isKindOfClass:[NSArray class]]) return;

  NSFileManager* fm = [NSFileManager defaultManager];
  for (NSDictionary* row in rows) {
    if (![row isKindOfClass:[NSDictionary class]]) continue;
    NSString* path = row[@"path"];
    if (![path isKindOfClass:[NSString class]] || ![fm fileExistsAtPath:path]) continue;

    SlateExtensionRecord* rec = [[SlateExtensionRecord alloc] init];
    rec.identifier = row[@"id"] ?: NSUUID.UUID.UUIDString;
    rec.name = row[@"name"] ?: @"Extension";
    rec.version = row[@"version"] ?: @"";
    rec.summary = row[@"summary"] ?: @"";
    rec.directoryPath = path;
    NSString* sp = row[@"sidePanelPath"];
    rec.sidePanelPath = ([sp isKindOfClass:[NSString class]] && sp.length) ? sp : nil;
    rec.enabled = [row[@"enabled"] boolValue];
    rec.allowInPrivate = [row[@"allowInPrivate"] boolValue];
    [_mutableExtensions addObject:rec];

    if (rec.enabled) {
      [self loadRecordIntoController:rec completion:nil];
    }
  }
}

- (void)notifyWindowOpened {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    if (ctrl && _windowAdapter) [ctrl didOpenWindow:_windowAdapter];
  }
}

- (void)notifyWindowFocused {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    if (ctrl && _windowAdapter) [ctrl didFocusWindow:_windowAdapter];
  }
}

- (void)notifyTabOpened:(uint64_t)tabId {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    if (ctrl && tabId) [ctrl didOpenTab:[self adapterForTabId:tabId]];
  }
}

- (void)notifyTabClosed:(uint64_t)tabId {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    NSNumber* key = @(tabId);
    id<WKWebExtensionTab> adapter = _tabAdapters[key];
    if (ctrl && adapter) {
      [ctrl didCloseTab:adapter windowIsClosing:NO];
    }
    [_tabAdapters removeObjectForKey:key];
  }
}

- (void)notifyTabActivated:(uint64_t)tabId previousTabId:(uint64_t)previousTabId {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    if (!ctrl || !tabId) return;
    id<WKWebExtensionTab> prev = previousTabId ? _tabAdapters[@(previousTabId)] : nil;
    [ctrl didActivateTab:[self adapterForTabId:tabId] previousActiveTab:prev];
  }
}

- (void)notifyTabPropertiesChanged:(uint64_t)tabId {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    if (!ctrl || !tabId) return;
    [ctrl didChangeTabProperties:(WKWebExtensionTabChangedPropertiesURL | WKWebExtensionTabChangedPropertiesTitle | WKWebExtensionTabChangedPropertiesLoading)
                          forTab:[self adapterForTabId:tabId]];
  }
}

#pragma mark - Loading Into WKWebExtensionController

- (void)grantRequestedPermissionsOnContext:(WKWebExtensionContext*)ctx API_AVAILABLE(macos(15.4)) {
  WKWebExtension* ext = ctx.webExtension;
  for (WKWebExtensionPermission perm in ext.requestedPermissions) {
    [ctx setPermissionStatus:WKWebExtensionContextPermissionStatusGrantedExplicitly forPermission:perm];
  }
  for (WKWebExtensionMatchPattern* pattern in ext.requestedPermissionMatchPatterns) {
    [ctx setPermissionStatus:WKWebExtensionContextPermissionStatusGrantedExplicitly forMatchPattern:pattern];
  }
}

- (void)loadRecordIntoController:(SlateExtensionRecord*)rec
                      completion:(void (^)(NSError* _Nullable error))completion {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    if (!ctrl) {
      NSError* err = [NSError errorWithDomain:@"SlateExtensions" code:1 userInfo:@{NSLocalizedDescriptionKey: @"WebExtensions require macOS 15.4 or later."}];
      if (completion) completion(err);
      return;
    }
    NSURL* dirURL = [NSURL fileURLWithPath:rec.directoryPath isDirectory:YES];
    [WKWebExtension extensionWithResourceBaseURL:dirURL completionHandler:^(WKWebExtension* _Nullable extension, NSError* _Nullable error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!extension || error) {
          rec.loadError = error.localizedDescription ?: @"Invalid Chrome extension manifest.";
          rec.enabled = NO;
          [self saveRegistry];
          [self postDidChange];
          if (completion) completion(error);
          return;
        }
        rec.loadError = nil;
        rec.name = extension.displayName.length ? extension.displayName : (rec.name.length ? rec.name : @"Extension");
        rec.version = extension.displayVersion ?: extension.version ?: @"";
        rec.summary = extension.displayDescription ?: @"";
        rec.hasOptionsPage = extension.hasOptionsPage;
        rec.icon = [extension iconForSize:CGSizeMake(32, 32)] ?: [extension actionIconForSize:CGSizeMake(32, 32)];
        rec.webExtension = extension;

        WKWebExtensionContext* ctx = [WKWebExtensionContext contextForExtension:extension];
        ctx.uniqueIdentifier = rec.identifier;
        ctx.hasAccessToPrivateData = rec.allowInPrivate;
        [self grantRequestedPermissionsOnContext:ctx];

        NSError* loadErr = nil;
        BOOL ok = [ctrl loadExtensionContext:ctx error:&loadErr];
        if (!ok) {
          rec.loadError = loadErr.localizedDescription ?: @"Failed to load extension context.";
          rec.enabled = NO;
          [self saveRegistry];
          [self postDidChange];
          if (completion) completion(loadErr);
          return;
        }
        rec.webExtensionContext = ctx;
        if (extension.hasBackgroundContent) {
          [ctx loadBackgroundContentWithCompletionHandler:^(NSError* _Nullable bgErr) {
            if (bgErr) {
              fprintf(stderr, "SLATE_EXT_BG_WARN id=%s err=%s\n", rec.identifier.UTF8String, bgErr.localizedDescription.UTF8String);
            }
          }];
        }
        [self saveRegistry];
        [self postDidChange];
        if (completion) completion(nil);
      });
    }];
  } else {
    NSError* err = [NSError errorWithDomain:@"SlateExtensions" code:1 userInfo:@{NSLocalizedDescriptionKey: @"WebExtensions require macOS 15.4 or later."}];
    if (completion) completion(err);
  }
}

- (void)unloadRecordFromController:(SlateExtensionRecord*)rec {
  if (@available(macOS 15.4, *)) {
    WKWebExtensionController* ctrl = self.controller;
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (ctrl && ctx) {
      [ctrl unloadExtensionContext:ctx error:nil];
    }
    if (rec.identifier.length) {
      WKWebView* off = _offscreenWebViews[rec.identifier];
      if (off) {
        [off loadHTMLString:@"" baseURL:nil];
        [_offscreenWebViews removeObjectForKey:rec.identifier];
      }
    }
    rec.webExtensionContext = nil;
    rec.badgeText = nil;
  }
}

#pragma mark - Manifest Normalization & CRX3/CRX2/ZIP Unpacking

- (NSString*)normalizeManifestAtDirectory:(NSString*)dirPath {
  NSString* manifestPath = [dirPath stringByAppendingPathComponent:@"manifest.json"];
  NSData* data = [NSData dataWithContentsOfFile:manifestPath];
  if (!data) return nil;
  id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
  if (![obj isKindOfClass:[NSMutableDictionary class]]) return nil;
  NSMutableDictionary* manifest = (NSMutableDictionary*)obj;

  NSString* sidePanelPath = nil;
  NSDictionary* sp = [manifest[@"side_panel"] isKindOfClass:[NSDictionary class]] ? manifest[@"side_panel"] : nil;
  if ([sp[@"default_path"] isKindOfClass:[NSString class]] && [sp[@"default_path"] length]) {
    sidePanelPath = [sp[@"default_path"] copy];
  }

  // Strip Chrome-only manifest keys that WebKit rejects or does not use.
  for (NSString* k in @[@"update_url", @"key", @"differential_fingerprint",
                        @"minimum_chrome_version", @"cross_origin_embedder_policy",
                        @"cross_origin_opener_policy"]) {
    [manifest removeObjectForKey:k];
  }
  if ([manifest[@"manifest_version"] integerValue] == 3 &&
      [manifest[@"background"] isKindOfClass:[NSMutableDictionary class]]) {
    [manifest[@"background"] removeObjectForKey:@"persistent"];
  }

  NSData* out = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
  if (out) [out writeToFile:manifestPath atomically:YES];
  return sidePanelPath;
}

- (NSString*)findManifestDirectoryUnder:(NSString*)root {
  NSFileManager* fm = [NSFileManager defaultManager];
  if ([fm fileExistsAtPath:[root stringByAppendingPathComponent:@"manifest.json"]]) {
    return root;
  }
  NSArray<NSString*>* items = [fm contentsOfDirectoryAtPath:root error:nil];
  for (NSString* item in items) {
    if ([item hasPrefix:@"."] || [item isEqualToString:@"__MACOSX"]) continue;
    NSString* sub = [root stringByAppendingPathComponent:item];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:sub isDirectory:&isDir] && isDir &&
        [fm fileExistsAtPath:[sub stringByAppendingPathComponent:@"manifest.json"]]) {
      return sub;
    }
  }
  return nil;
}

- (NSData*)extractZipPayloadFromArchiveData:(NSData*)rawData error:(NSError**)outError {
  if (rawData.length < 16) {
    if (outError) *outError = [NSError errorWithDomain:@"SlateExtensions" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Extension archive is too small or corrupt."}];
    return nil;
  }
  const uint8_t* bytes = (const uint8_t*)rawData.bytes;
  // Plain ZIP ("PK\x03\x04")
  if (bytes[0] == 'P' && bytes[1] == 'K' && bytes[2] == 0x03 && bytes[3] == 0x04) {
    return rawData;
  }
  // Chrome CRX ("Cr24")
  if (bytes[0] == 'C' && bytes[1] == 'r' && bytes[2] == '2' && bytes[3] == '4') {
    uint32_t version = (uint32_t)bytes[4] | ((uint32_t)bytes[5] << 8) | ((uint32_t)bytes[6] << 16) | ((uint32_t)bytes[7] << 24);
    NSUInteger zipOffset = 0;
    if (version == 3) {
      uint32_t headerLen = (uint32_t)bytes[8] | ((uint32_t)bytes[9] << 8) | ((uint32_t)bytes[10] << 16) | ((uint32_t)bytes[11] << 24);
      zipOffset = 12 + (NSUInteger)headerLen;
    } else if (version == 2) {
      uint32_t pubLen = (uint32_t)bytes[8] | ((uint32_t)bytes[9] << 8) | ((uint32_t)bytes[10] << 16) | ((uint32_t)bytes[11] << 24);
      uint32_t sigLen = (uint32_t)bytes[12] | ((uint32_t)bytes[13] << 8) | ((uint32_t)bytes[14] << 16) | ((uint32_t)bytes[15] << 24);
      zipOffset = 16 + (NSUInteger)pubLen + (NSUInteger)sigLen;
    }
    if (zipOffset > 0 && zipOffset < rawData.length) {
      return [rawData subdataWithRange:NSMakeRange(zipOffset, rawData.length - zipOffset)];
    }
  }
  if (outError) *outError = [NSError errorWithDomain:@"SlateExtensions" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported archive format. Choose a Chrome .crx or .zip extension."}];
  return nil;
}

- (void)installFromUnpackedDirectory:(NSURL*)dirURL
                          completion:(void (^)(SlateExtensionRecord* _Nullable, NSError* _Nullable))completion {
  [self installFromUnpackedDirectory:dirURL preferredId:nil completion:completion];
}

- (void)installFromUnpackedDirectory:(NSURL*)dirURL
                         preferredId:(NSString* _Nullable)preferredId
                          completion:(void (^)(SlateExtensionRecord* _Nullable, NSError* _Nullable))completion {
  if (!dirURL) return;
  NSString* manifestDir = [self findManifestDirectoryUnder:dirURL.path];
  if (!manifestDir) {
    NSError* err = [NSError errorWithDomain:@"SlateExtensions" code:4 userInfo:@{NSLocalizedDescriptionKey: @"No manifest.json found in the selected folder."}];
    if (completion) completion(nil, err);
    return;
  }
  NSString* extId = preferredId.length ? preferredId.lowercaseString : NSUUID.UUID.UUIDString.lowercaseString;
  // Replace existing installation with same Chrome Web Store ID cleanly.
  SlateExtensionRecord* existing = [self recordForId:extId];
  BOOL prevAllowPrivate = existing ? existing.allowInPrivate : NO;
  if (existing) {
    [self unloadRecordFromController:existing];
    [_mutableExtensions removeObject:existing];
  }
  NSString* destDir = [[self extensionsRootDirectory] stringByAppendingPathComponent:extId];
  NSError* copyErr = nil;
  NSFileManager* fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:destDir error:nil];
  if (![fm copyItemAtPath:manifestDir toPath:destDir error:&copyErr]) {
    if (completion) completion(nil, copyErr);
    return;
  }
  NSString* sidePanelPath = [self normalizeManifestAtDirectory:destDir];

  SlateExtensionRecord* rec = [[SlateExtensionRecord alloc] init];
  rec.identifier = extId;
  rec.name = dirURL.lastPathComponent ?: @"Extension";
  rec.version = @"";
  rec.summary = @"";
  rec.directoryPath = destDir;
  rec.sidePanelPath = sidePanelPath;
  rec.enabled = YES;
  rec.allowInPrivate = prevAllowPrivate;
  [_mutableExtensions addObject:rec];
  [self saveRegistry];

  [self loadRecordIntoController:rec completion:^(NSError* _Nullable error) {
    if (error) {
      [_mutableExtensions removeObject:rec];
      [fm removeItemAtPath:destDir error:nil];
      [self saveRegistry];
      [self postDidChange];
      if (completion) completion(nil, error);
      return;
    }
    if (completion) completion(rec, nil);
  }];
}

- (void)installFromArchiveURL:(NSURL*)archiveURL
                   completion:(void (^)(SlateExtensionRecord* _Nullable, NSError* _Nullable))completion {
  [self installFromArchiveURL:archiveURL preferredId:nil completion:completion];
}

- (void)installFromArchiveURL:(NSURL*)archiveURL
                  preferredId:(NSString* _Nullable)preferredId
                   completion:(void (^)(SlateExtensionRecord* _Nullable, NSError* _Nullable))completion {
  if (!archiveURL) return;
  NSError* readErr = nil;
  NSData* raw = [NSData dataWithContentsOfURL:archiveURL options:0 error:&readErr];
  if (!raw) {
    if (completion) completion(nil, readErr);
    return;
  }
  NSError* parseErr = nil;
  NSData* zipData = [self extractZipPayloadFromArchiveData:raw error:&parseErr];
  if (!zipData) {
    if (completion) completion(nil, parseErr);
    return;
  }

  NSString* stageRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"slate-ext-stage-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  NSString* zipFile = [stageRoot stringByAppendingPathComponent:@"payload.zip"];
  NSString* unpackDir = [stageRoot stringByAppendingPathComponent:@"unpacked"];
  NSFileManager* fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath:unpackDir withIntermediateDirectories:YES attributes:nil error:nil];
  [zipData writeToFile:zipFile atomically:YES];

  NSTask* task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
  task.arguments = @[@"-xk", zipFile, unpackDir];
  NSError* launchErr = nil;
  BOOL ok = [task launchAndReturnError:&launchErr];
  if (ok) [task waitUntilExit];
  if (!ok || task.terminationStatus != 0) {
    [fm removeItemAtPath:stageRoot error:nil];
    NSError* err = launchErr ?: [NSError errorWithDomain:@"SlateExtensions" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to unpack extension archive."}];
    if (completion) completion(nil, err);
    return;
  }

  [self installFromUnpackedDirectory:[NSURL fileURLWithPath:unpackDir isDirectory:YES] preferredId:preferredId completion:^(SlateExtensionRecord* _Nullable rec, NSError* _Nullable err) {
    [fm removeItemAtPath:stageRoot error:nil];
    if (completion) completion(rec, err);
  }];
}

- (BOOL)isExtensionInstalled:(NSString*)identifier {
  if (!identifier.length) return NO;
  return [self recordForId:identifier.lowercaseString] != nil;
}

- (void)installFromChromeWebStoreId:(NSString*)storeId
                         completion:(void (^)(SlateExtensionRecord* _Nullable, NSError* _Nullable))completion {
  NSString* cleanId = [SlateExtensionsManager chromeStoreExtensionIdFromInput:storeId];
  if (!cleanId.length) {
    NSError* err = [NSError errorWithDomain:@"SlateExtensions" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Invalid Chrome Web Store URL or extension ID."}];
    if (completion) completion(nil, err);
    return;
  }
  NSString* urlStr = [NSString stringWithFormat:
    @"https://clients2.google.com/service/update2/crx?response=redirect&prodversion=134.0.6998.165&acceptformat=crx2,crx3&x=id%%3D%@%%26installsource%%3Dondemand%%26uc",
    cleanId];
  NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
  req.timeoutInterval = 30.0;
  [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
     forHTTPHeaderField:@"User-Agent"];

  NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSHTTPURLResponse* http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse*)response : nil;
      if (error || !data.length || (http && http.statusCode != 200)) {
        NSString* msg = error.localizedDescription ?: [NSString stringWithFormat:@"Chrome Web Store returned HTTP %ld (extension may be private or unavailable).", (long)(http ? http.statusCode : 0)];
        NSError* dlErr = [NSError errorWithDomain:@"SlateExtensions" code:7 userInfo:@{NSLocalizedDescriptionKey: msg}];
        if (completion) completion(nil, dlErr);
        return;
      }
      NSString* tmpCrx = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"slate-store-%@.crx", cleanId]];
      [data writeToFile:tmpCrx atomically:YES];
      [self installFromArchiveURL:[NSURL fileURLWithPath:tmpCrx] preferredId:cleanId completion:^(SlateExtensionRecord* _Nullable rec, NSError* _Nullable installErr) {
        [[NSFileManager defaultManager] removeItemAtPath:tmpCrx error:nil];
        if (completion) completion(rec, installErr);
      }];
    });
  }];
  [task resume];
}

#pragma mark - Controls & Actions

- (SlateExtensionRecord*)recordForId:(NSString*)identifier {
  for (SlateExtensionRecord* rec in _mutableExtensions) {
    if ([rec.identifier isEqualToString:identifier]) return rec;
  }
  return nil;
}

- (void)setExtensionId:(NSString*)identifier enabled:(BOOL)enabled {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec || rec.enabled == enabled) return;
  rec.enabled = enabled;
  if (enabled) {
    [self loadRecordIntoController:rec completion:nil];
  } else {
    [self unloadRecordFromController:rec];
    [self saveRegistry];
    [self postDidChange];
  }
}

- (void)setExtensionId:(NSString*)identifier allowInPrivate:(BOOL)allowInPrivate {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec) return;
  rec.allowInPrivate = allowInPrivate;
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (ctx) ctx.hasAccessToPrivateData = allowInPrivate;
  }
  [self saveRegistry];
  [self postDidChange];
}

- (void)removeExtensionId:(NSString*)identifier {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec) return;
  [self unloadRecordFromController:rec];
  if (rec.directoryPath.length) {
    [[NSFileManager defaultManager] removeItemAtPath:rec.directoryPath error:nil];
  }
  [_mutableExtensions removeObject:rec];
  [self saveRegistry];
  [self postDidChange];
}

- (void)openOptionsPageForExtensionId:(NSString*)identifier {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec) return;
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (ctx && ctx.optionsPageURL) {
      [self.hostDelegate extensionHostOpenURL:ctx.optionsPageURL incognito:NO activate:YES];
    }
  }
}

- (WKWebViewConfiguration*)makeExtensionShimWebViewConfiguration {
  WKWebViewConfiguration* cfg = [[WKWebViewConfiguration alloc] init];
  cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
  if (@available(macOS 15.4, *)) {
    if (self.controller) cfg.webExtensionController = self.controller;
  }
  NSString* shimJs = [NSString stringWithUTF8String:slate::kExtensionShimsJs];
  WKUserScript* script = [[WKUserScript alloc] initWithSource:shimJs
                                                injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                             forMainFrameOnly:NO];
  [cfg.userContentController addUserScript:script];
  [cfg.userContentController addScriptMessageHandler:self name:@"slateExtShim"];
  return cfg;
}

- (void)openSidePanelForExtensionId:(NSString*)identifier path:(NSString*)overridePath {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec || !rec.enabled) return;
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (!ctx || !ctx.baseURL) return;
    NSString* relPath = overridePath.length ? overridePath : rec.sidePanelPath;
    if (!relPath.length) return;
    while ([relPath hasPrefix:@"/"]) relPath = [relPath substringFromIndex:1];
    NSURL* panelURL = [ctx.baseURL URLByAppendingPathComponent:relPath];
    if (!panelURL) return;

    if (!_sidePanelWindow) {
      NSRect rect = NSMakeRect(0, 0, 380, 680);
      NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
      _sidePanelWindow = [[NSPanel alloc] initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:NO];
      _sidePanelWindow.releasedWhenClosed = NO;
      _sidePanelWindow.hidesOnDeactivate = NO;
      _sidePanelWindow.minSize = NSMakeSize(300, 420);
      _sidePanelWebView = [[WKWebView alloc] initWithFrame:_sidePanelWindow.contentView.bounds
                                             configuration:[self makeExtensionShimWebViewConfiguration]];
      _sidePanelWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
      [_sidePanelWindow.contentView addSubview:_sidePanelWebView];
    }
    _sidePanelWindow.title = rec.name ?: @"Side Panel";
    [_sidePanelWebView loadRequest:[NSURLRequest requestWithURL:panelURL]];

    NSWindow* hostWin = [self.hostDelegate extensionHostWindow];
    if (hostWin) {
      NSRect hf = hostWin.frame;
      NSRect pf = _sidePanelWindow.frame;
      pf.origin.x = NSMaxX(hf) - NSWidth(pf) - 18;
      pf.origin.y = NSMaxY(hf) - NSHeight(pf) - 56;
      [_sidePanelWindow setFrame:pf display:YES];
    } else {
      [_sidePanelWindow center];
    }
    [_sidePanelWindow makeKeyAndOrderFront:nil];
  }
}

- (SlateExtensionRecord*)recordForExtensionOrigin:(NSString*)origin {
  if (!origin.length) return nil;
  if (@available(macOS 15.4, *)) {
    NSURL* u = [NSURL URLWithString:origin];
    if (u && self.controller) {
      WKWebExtensionContext* ctx = [self.controller extensionContextForURL:u];
      if (ctx) return [self recordForId:ctx.uniqueIdentifier];
    }
  }
  return nil;
}

- (void)replyShimToWebView:(WKWebView*)webView reqId:(NSString*)reqId result:(id)result error:(NSString*)error {
  if (!webView || !reqId.length) return;
  NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithObject:reqId forKey:@"reqId"];
  if (error.length) payload[@"error"] = error;
  else if (result) payload[@"result"] = result;
  NSData* json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  NSString* jsonStr = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
  NSString* js = [NSString stringWithFormat:@"window.__slateExtShimReply && window.__slateExtShimReply(%@);", jsonStr];
  dispatch_async(dispatch_get_main_queue(), ^{
    [webView evaluateJavaScript:js completionHandler:nil];
  });
}

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message {
  (void)userContentController;
  if ([message.name isEqualToString:@"slateExtShim"] && [message.body isKindOfClass:[NSDictionary class]]) {
    [self handleShimMessage:(NSDictionary*)message.body fromWebView:message.webView];
  }
}

- (void)handleShimMessage:(NSDictionary*)body fromWebView:(WKWebView*)webView {
  NSString* reqId = [body[@"reqId"] isKindOfClass:[NSString class]] ? body[@"reqId"] : @"";
  NSString* op = [body[@"op"] isKindOfClass:[NSString class]] ? body[@"op"] : @"";
  NSString* extOrigin = [body[@"extOrigin"] isKindOfClass:[NSString class]] ? body[@"extOrigin"] : @"";
  NSDictionary* params = [body[@"params"] isKindOfClass:[NSDictionary class]] ? body[@"params"] : @{};
  SlateExtensionRecord* rec = [self recordForExtensionOrigin:extOrigin];

  if ([op isEqualToString:@"offscreen.create"]) {
    if (!rec) { [self replyShimToWebView:webView reqId:reqId result:nil error:@"Extension context not found"]; return; }
    NSString* relUrl = [params[@"url"] isKindOfClass:[NSString class]] ? params[@"url"] : @"";
    if (!relUrl.length) { [self replyShimToWebView:webView reqId:reqId result:nil error:@"Missing offscreen url"]; return; }
    if (@available(macOS 15.4, *)) {
      WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
      while ([relUrl hasPrefix:@"/"]) relUrl = [relUrl substringFromIndex:1];
      NSURL* fullURL = [ctx.baseURL URLByAppendingPathComponent:relUrl];
      WKWebView* off = _offscreenWebViews[rec.identifier];
      if (!off) {
        off = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)
                                 configuration:[self makeExtensionShimWebViewConfiguration]];
        _offscreenWebViews[rec.identifier] = off;
      }
      if (fullURL) [off loadRequest:[NSURLRequest requestWithURL:fullURL]];
      [self replyShimToWebView:webView reqId:reqId result:@YES error:nil];
      return;
    }
  } else if ([op isEqualToString:@"offscreen.close"]) {
    if (rec && _offscreenWebViews[rec.identifier]) {
      [_offscreenWebViews[rec.identifier] loadHTMLString:@"" baseURL:nil];
      [_offscreenWebViews removeObjectForKey:rec.identifier];
    }
    [self replyShimToWebView:webView reqId:reqId result:@YES error:nil];
    return;
  } else if ([op isEqualToString:@"offscreen.has"]) {
    BOOL has = (rec != nil) && (_offscreenWebViews[rec.identifier] != nil);
    [self replyShimToWebView:webView reqId:reqId result:@(has) error:nil];
    return;
  } else if ([op isEqualToString:@"sidePanel.open"]) {
    if (rec) {
      NSString* path = [params[@"path"] isKindOfClass:[NSString class]] ? params[@"path"] : nil;
      [self openSidePanelForExtensionId:rec.identifier path:path];
    }
    [self replyShimToWebView:webView reqId:reqId result:@YES error:nil];
    return;
  } else if ([op isEqualToString:@"sidePanel.setOptions"]) {
    if (rec && [params[@"path"] isKindOfClass:[NSString class]] && [params[@"path"] length]) {
      rec.sidePanelPath = params[@"path"];
      [self saveRegistry];
    }
    [self replyShimToWebView:webView reqId:reqId result:@YES error:nil];
    return;
  } else if ([op isEqualToString:@"identity.launchWebAuthFlow"]) {
    NSString* authUrlStr = [params[@"url"] isKindOfClass:[NSString class]] ? params[@"url"] : @"";
    NSURL* authURL = [NSURL URLWithString:authUrlStr];
    if (!authURL) {
      [self replyShimToWebView:webView reqId:reqId result:nil error:@"Invalid auth URL"];
      return;
    }
    __weak SlateExtensionsManager* weakSelf = self;
    __weak WKWebView* weakWeb = webView;
    _activeAuthPanel = [[SlateExtAuthPanel alloc] initWithURL:authURL completion:^(NSString* _Nullable redirectURL, NSString* _Nullable err) {
      SlateExtensionsManager* strongSelf = weakSelf;
      if (strongSelf) strongSelf.activeAuthPanel = nil;
      [strongSelf replyShimToWebView:weakWeb reqId:reqId result:redirectURL error:err];
    }];
    [_activeAuthPanel center];
    [_activeAuthPanel makeKeyAndOrderFront:nil];
    return;
  } else if ([op isEqualToString:@"notifications.create"]) {
    NSString* nid = [params[@"id"] isKindOfClass:[NSString class]] ? params[@"id"] : @"slate_notif";
    NSDictionary* opts = [params[@"options"] isKindOfClass:[NSDictionary class]] ? params[@"options"] : @{};
    NSString* title = [opts[@"title"] isKindOfClass:[NSString class]] ? opts[@"title"] : (rec.name ?: @"Slate");
    NSString* message = [opts[@"message"] isKindOfClass:[NSString class]] ? opts[@"message"] : @"";
    if (@available(macOS 10.14, *)) {
      UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
      [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound) completionHandler:^(BOOL granted, NSError* error) {
        (void)error;
        if (!granted) return;
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body = message;
        UNNotificationRequest* req = [UNNotificationRequest requestWithIdentifier:nid content:content trigger:nil];
        [center addNotificationRequest:req withCompletionHandler:nil];
      }];
    }
    [self replyShimToWebView:webView reqId:reqId result:nid error:nil];
    return;
  }
  [self replyShimToWebView:webView reqId:reqId result:nil error:@"Unsupported extension shim operation"];
}

- (void)performActionForExtensionId:(NSString*)identifier anchorView:(NSView*)anchorView {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec || !rec.enabled) return;
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (!ctx) return;
    _pendingPopupAnchor = anchorView;
    uint64_t sel = [self.hostDelegate extensionHostSelectedTabId];
    id<WKWebExtensionTab> tab = sel ? [self adapterForTabId:sel] : nil;
    [ctx performActionForTab:tab];
  }
}

- (NSImage*)actionIconForExtensionId:(NSString*)identifier size:(CGSize)size {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec) return nil;
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (ctx) {
      uint64_t sel = [self.hostDelegate extensionHostSelectedTabId];
      id<WKWebExtensionTab> tab = sel ? [self adapterForTabId:sel] : nil;
      WKWebExtensionAction* action = [ctx actionForTab:tab];
      NSImage* img = [action iconForSize:size];
      if (img) return img;
    }
  }
  return rec.icon;
}

- (NSString*)actionBadgeForExtensionId:(NSString*)identifier {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec) return nil;
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (ctx) {
      uint64_t sel = [self.hostDelegate extensionHostSelectedTabId];
      id<WKWebExtensionTab> tab = sel ? [self adapterForTabId:sel] : nil;
      WKWebExtensionAction* action = [ctx actionForTab:tab];
      if (action.badgeText.length) return action.badgeText;
    }
  }
  return rec.badgeText;
}

- (NSString*)actionTooltipForExtensionId:(NSString*)identifier {
  SlateExtensionRecord* rec = [self recordForId:identifier];
  if (!rec) return @"Extension";
  if (@available(macOS 15.4, *)) {
    WKWebExtensionContext* ctx = (WKWebExtensionContext*)rec.webExtensionContext;
    if (ctx) {
      uint64_t sel = [self.hostDelegate extensionHostSelectedTabId];
      id<WKWebExtensionTab> tab = sel ? [self adapterForTabId:sel] : nil;
      WKWebExtensionAction* action = [ctx actionForTab:tab];
      if (action.label.length) return action.label;
    }
  }
  return rec.name ?: @"Extension";
}

#pragma mark - WKWebExtensionControllerDelegate

- (NSArray<id<WKWebExtensionWindow>>*)webExtensionController:(WKWebExtensionController*)controller
                               openWindowsForExtensionContext:(WKWebExtensionContext*)extensionContext API_AVAILABLE(macos(15.4)) {
  (void)controller; (void)extensionContext;
  return _windowAdapter ? @[_windowAdapter] : @[];
}

- (nullable id<WKWebExtensionWindow>)webExtensionController:(WKWebExtensionController*)controller
                            focusedWindowForExtensionContext:(WKWebExtensionContext*)extensionContext API_AVAILABLE(macos(15.4)) {
  (void)controller; (void)extensionContext;
  return _windowAdapter;
}

- (void)webExtensionController:(WKWebExtensionController*)controller
  openNewTabUsingConfiguration:(WKWebExtensionTabConfiguration*)configuration
           forExtensionContext:(WKWebExtensionContext*)extensionContext
             completionHandler:(void (^)(id<WKWebExtensionTab> _Nullable, NSError* _Nullable))completionHandler API_AVAILABLE(macos(15.4)) {
  (void)controller; (void)extensionContext;
  id<SlateExtensionHostDelegate> host = self.hostDelegate;
  if (!host) {
    if (completionHandler) completionHandler(nil, nil);
    return;
  }
  uint64_t newTabId = [host extensionHostOpenURL:configuration.url
                                       incognito:NO
                                        activate:configuration.shouldBeActive];
  id<WKWebExtensionTab> tab = newTabId ? [self adapterForTabId:newTabId] : nil;
  if (completionHandler) completionHandler(tab, nil);
}

- (void)webExtensionController:(WKWebExtensionController*)controller
openOptionsPageForExtensionContext:(WKWebExtensionContext*)extensionContext
             completionHandler:(void (^)(NSError* _Nullable))completionHandler API_AVAILABLE(macos(15.4)) {
  (void)controller;
  if (extensionContext.optionsPageURL && self.hostDelegate) {
    [self.hostDelegate extensionHostOpenURL:extensionContext.optionsPageURL incognito:NO activate:YES];
  }
  if (completionHandler) completionHandler(nil);
}

- (void)webExtensionController:(WKWebExtensionController*)controller
          promptForPermissions:(NSSet<WKWebExtensionPermission>*)permissions
                         inTab:(nullable id<WKWebExtensionTab>)tab
           forExtensionContext:(WKWebExtensionContext*)extensionContext
             completionHandler:(void (^)(NSSet<WKWebExtensionPermission>*, NSDate* _Nullable))completionHandler API_AVAILABLE(macos(15.4)) {
  (void)controller; (void)tab; (void)extensionContext;
  if (completionHandler) completionHandler(permissions, nil);
}

- (void)webExtensionController:(WKWebExtensionController*)controller
promptForPermissionToAccessURLs:(NSSet<NSURL*>*)urls
                         inTab:(nullable id<WKWebExtensionTab>)tab
           forExtensionContext:(WKWebExtensionContext*)extensionContext
             completionHandler:(void (^)(NSSet<NSURL*>*, NSDate* _Nullable))completionHandler API_AVAILABLE(macos(15.4)) {
  (void)controller; (void)tab; (void)extensionContext;
  if (completionHandler) completionHandler(urls, nil);
}

- (void)webExtensionController:(WKWebExtensionController*)controller
promptForPermissionMatchPatterns:(NSSet<WKWebExtensionMatchPattern*>*)matchPatterns
                         inTab:(nullable id<WKWebExtensionTab>)tab
           forExtensionContext:(WKWebExtensionContext*)extensionContext
             completionHandler:(void (^)(NSSet<WKWebExtensionMatchPattern*>*, NSDate* _Nullable))completionHandler API_AVAILABLE(macos(15.4)) {
  (void)controller; (void)tab; (void)extensionContext;
  if (completionHandler) completionHandler(matchPatterns, nil);
}

- (void)webExtensionController:(WKWebExtensionController*)controller
               didUpdateAction:(WKWebExtensionAction*)action
           forExtensionContext:(WKWebExtensionContext*)context API_AVAILABLE(macos(15.4)) {
  (void)controller;
  SlateExtensionRecord* rec = [self recordForId:context.uniqueIdentifier];
  if (rec) {
    rec.badgeText = action.badgeText;
    [self postDidChange];
  }
}

- (void)webExtensionController:(WKWebExtensionController*)controller
         presentPopupForAction:(WKWebExtensionAction*)action
           forExtensionContext:(WKWebExtensionContext*)context
             completionHandler:(void (^)(NSError* _Nullable))completionHandler API_AVAILABLE(macos(15.4)) {
  (void)controller;
  NSPopover* popover = action.popupPopover;
  WKWebView* popupWeb = action.popupWebView;
  if (popupWeb) {
    static char kShimAttachedKey;
    if (!objc_getAssociatedObject(popupWeb, &kShimAttachedKey)) {
      objc_setAssociatedObject(popupWeb, &kShimAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
      NSString* shimJs = [NSString stringWithUTF8String:slate::kExtensionShimsJs];
      WKUserScript* script = [[WKUserScript alloc] initWithSource:shimJs
                                                    injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                 forMainFrameOnly:NO];
      [popupWeb.configuration.userContentController addUserScript:script];
      @try { [popupWeb.configuration.userContentController addScriptMessageHandler:self name:@"slateExtShim"]; } @catch (id e) {}
      [popupWeb evaluateJavaScript:shimJs completionHandler:nil];
    }
  }
  NSView* anchor = _pendingPopupAnchor ?: [self.hostDelegate extensionHostAnchorViewForExtensionId:context.uniqueIdentifier];
  _pendingPopupAnchor = nil;
  if (!anchor) {
    anchor = [self.hostDelegate extensionHostWindow].contentView;
  }
  if (popover && anchor && anchor.window) {
    [popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
  }
  if (completionHandler) completionHandler(nil);
}

@end
