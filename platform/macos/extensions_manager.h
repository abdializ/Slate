// File purpose: Native macOS WKWebExtension manager, CRX3/ZIP/unpacked Chrome extension
// installer, and tab/window adapter bridge for Slate.

#pragma once

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const SlateExtensionsDidChangeNotification;

@interface SlateExtensionRecord : NSObject
@property (nonatomic, copy) NSString* identifier;
@property (nonatomic, copy) NSString* name;
@property (nonatomic, copy) NSString* version;
@property (nonatomic, copy) NSString* summary;
@property (nonatomic, copy) NSString* directoryPath;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL allowInPrivate;
@property (nonatomic, assign) BOOL hasOptionsPage;
@property (nonatomic, copy, nullable) NSString* sidePanelPath;
@property (nonatomic, strong, nullable) NSImage* icon;
@property (nonatomic, copy, nullable) NSString* loadError;
@property (nonatomic, copy, nullable) NSString* badgeText;
@property (nonatomic, strong, nullable) id webExtension API_AVAILABLE(macos(15.4));
@property (nonatomic, strong, nullable) id webExtensionContext API_AVAILABLE(macos(15.4));
@end

@protocol SlateExtensionHostDelegate <NSObject>
- (NSWindow* _Nullable)extensionHostWindow;
- (NSArray<NSNumber*>*)extensionHostTabIds;
- (uint64_t)extensionHostSelectedTabId;
- (WKWebView* _Nullable)extensionHostWebViewForTabId:(uint64_t)tabId;
- (NSString* _Nullable)extensionHostTitleForTabId:(uint64_t)tabId;
- (NSURL* _Nullable)extensionHostURLForTabId:(uint64_t)tabId;
- (BOOL)extensionHostIsIncognitoTabId:(uint64_t)tabId;
- (BOOL)extensionHostIsLoadingTabId:(uint64_t)tabId;
- (BOOL)extensionHostIsMutedTabId:(uint64_t)tabId;
- (BOOL)extensionHostIsAudibleTabId:(uint64_t)tabId;
- (BOOL)extensionHostIsPinnedTabId:(uint64_t)tabId;
- (void)extensionHostActivateTabId:(uint64_t)tabId;
- (void)extensionHostCloseTabId:(uint64_t)tabId;
- (void)extensionHostToggleMuteTabId:(uint64_t)tabId muted:(BOOL)muted;
- (uint64_t)extensionHostOpenURL:(NSURL* _Nullable)url incognito:(BOOL)incognito activate:(BOOL)activate;
- (NSView* _Nullable)extensionHostAnchorViewForExtensionId:(NSString*)extensionId;
@end

@interface SlateExtensionsManager : NSObject

+ (instancetype)sharedManager;
+ (BOOL)isSupported;
+ (NSString* _Nullable)chromeStoreExtensionIdFromURL:(NSURL* _Nullable)url;
+ (NSString* _Nullable)chromeStoreExtensionIdFromInput:(NSString* _Nullable)input;

@property (nonatomic, weak, nullable) id<SlateExtensionHostDelegate> hostDelegate;
@property (nonatomic, assign, getter=isGlobalEnabled) BOOL globalEnabled;
@property (nonatomic, readonly) NSArray<SlateExtensionRecord*>* extensions;

// Returns WKWebExtensionController* on macOS 15.4+, nil on older macOS.
- (WKWebExtensionController* _Nullable)controller API_AVAILABLE(macos(15.4));

// Lifecycle bootstrap & browser tab/window notifications
- (void)startIfNeeded;
- (void)notifyWindowOpened;
- (void)notifyWindowFocused;
- (void)notifyTabOpened:(uint64_t)tabId;
- (void)notifyTabClosed:(uint64_t)tabId;
- (void)notifyTabActivated:(uint64_t)tabId previousTabId:(uint64_t)previousTabId;
- (void)notifyTabPropertiesChanged:(uint64_t)tabId;

// Installing & managing extensions
- (void)installFromUnpackedDirectory:(NSURL*)dirURL
                          completion:(void (^)(SlateExtensionRecord* _Nullable record, NSError* _Nullable error))completion;
- (void)installFromArchiveURL:(NSURL*)archiveURL
                   completion:(void (^)(SlateExtensionRecord* _Nullable record, NSError* _Nullable error))completion;
- (void)installFromChromeWebStoreId:(NSString*)storeId
                         completion:(void (^)(SlateExtensionRecord* _Nullable record, NSError* _Nullable error))completion;
- (BOOL)isExtensionInstalled:(NSString*)identifier;
- (void)setExtensionId:(NSString*)identifier enabled:(BOOL)enabled;
- (void)setExtensionId:(NSString*)identifier allowInPrivate:(BOOL)allowInPrivate;
- (void)removeExtensionId:(NSString*)identifier;
- (void)openOptionsPageForExtensionId:(NSString*)identifier;
- (void)openSidePanelForExtensionId:(NSString*)identifier path:(NSString* _Nullable)overridePath;
- (void)handleShimMessage:(NSDictionary*)body fromWebView:(WKWebView*)webView;

// Toolbar action invocation
- (void)performActionForExtensionId:(NSString*)identifier anchorView:(NSView* _Nullable)anchorView;
- (NSImage* _Nullable)actionIconForExtensionId:(NSString*)identifier size:(CGSize)size;
- (NSString* _Nullable)actionBadgeForExtensionId:(NSString*)identifier;
- (NSString* _Nullable)actionTooltipForExtensionId:(NSString*)identifier;

@end

NS_ASSUME_NONNULL_END
