// File purpose: Implements the bridge between the C++ BrowserEngine interface and native WKWebView
// pages.

#import "engine/webkit_engine.h"
#import "engine/webkit_shields.h"
#import "engine/swipe_navigation.h"
#import "platform/macos/privacy_security.h"
#import "platform/macos/extensions_manager.h"
#include "engine/page_theme_js.h"
#include "engine/image_download_js.h"
#include "engine/extension_shims_js.h"
#include "engine/memory_optimizer_js.h"
#include "engine/pip_state.h"
#import "platform/macos/download_manager.h"
#import "platform/macos/form_relay.h"
#import "platform/macos/pdf_overlay.h"
#import "platform/macos/favicon_loader.h"
#import "SlatePasswords-Swift.h"
#import <WebKit/WebKit.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <chrono>



// Match WebKit's genuine macOS Safari User-Agent to the installed Safari version
// so TLS/JA4, HTTP/2, JavaScriptCore, and User-Agent are 100% consistent across
// all pages, iframes (e.g. Cloudflare Turnstile), and Web Workers.
static NSString* SlateSafariApplicationName() {
  static NSString* appName;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString* version = nil;
    for (NSString* path in @[
      @"/System/Cryptexes/App/System/Applications/Safari.app",
      @"/Applications/Safari.app"
    ]) {
      NSBundle* bundle = [NSBundle bundleWithPath:path];
      NSString* v = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
      if (v.length) {
        version = v;
        break;
      }
    }
    if (!version.length) {
      NSURL* safariURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Safari"];
      version = safariURL ? [[NSBundle bundleWithURL:safariURL] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] : nil;
    }
    appName = [NSString stringWithFormat:@"Version/%@ Safari/605.1.15", version.length ? version : @"18.0"];
  });
  return appName;
}

@interface SlateWebNavigationDelegate : NSObject <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler> {
  slate::PiPState pipState_;
}
@property (nonatomic, assign) slate::EngineEvents* events;
@property (nonatomic, weak) WKWebView* webView;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSDictionary*>* mediaFrames;
@property (nonatomic, assign) BOOL incognito;
@property (nonatomic, assign) BOOL pageThemeReported;
@property (nonatomic, strong) NSURL* imageMenuURL;
@property (nonatomic, strong) SlateFaviconRequest* faviconRequest;
@property (nonatomic) NSUInteger navigationGeneration;
@property (nonatomic, copy) NSURL* typedFileURL;
@end

@implementation SlateWebNavigationDelegate

- (void)startImageDownloadToDirectory:(NSString*)directory filename:(NSString*)filename {
  WKWebView* webView = self.webView;
  NSURL* imageURL = self.imageMenuURL;
  if (!webView || !imageURL) return;
  NSURLRequest* request = [NSURLRequest requestWithURL:imageURL];
  if (@available(macOS 11.3, *)) {
    [webView startDownloadUsingRequest:request completionHandler:^(WKDownload* download) {
      if (!download) return;
      SlateDownloadManager* manager = [SlateDownloadManager sharedManager];
      [manager registerDownload:download forWebView:webView
             requestedFilename:filename inDirectory:directory];
      download.delegate = manager;
    }];
  }
}

- (void)saveImage:(id)sender {
  [self startImageDownloadToDirectory:nil filename:nil];
}

- (void)copyImageAddress:(id)sender {
  if (!self.imageMenuURL) return;
  NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard clearContents];
  [pasteboard setString:self.imageMenuURL.absoluteString forType:NSPasteboardTypeString];
}

- (void)saveImageAs:(id)sender {
  WKWebView* webView = self.webView;
  NSURL* imageURL = self.imageMenuURL;
  if (!webView || !imageURL) return;
  NSSavePanel* panel = [NSSavePanel savePanel];
  panel.nameFieldStringValue = imageURL.lastPathComponent.pathExtension.length
    ? imageURL.lastPathComponent : @"image";
  panel.directoryURL = [NSURL fileURLWithPath:[SlateDownloadManager sharedManager].downloadsDirectory isDirectory:YES];
  __weak SlateWebNavigationDelegate* weakSelf = self;
  [panel beginSheetModalForWindow:webView.window completionHandler:^(NSModalResponse result) {
    SlateWebNavigationDelegate* strongSelf = weakSelf;
    if (result != NSModalResponseOK || !strongSelf || !panel.URL.isFileURL ||
        ![strongSelf.imageMenuURL isEqual:imageURL]) return;
    [strongSelf startImageDownloadToDirectory:panel.URL.URLByDeletingLastPathComponent.path
                                    filename:panel.URL.lastPathComponent];
  }];
}

- (void)showImageMenuForURL:(NSURL*)imageURL {
  WKWebView* webView = self.webView;
  if (!webView.window) return;
  self.imageMenuURL = imageURL;
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Image"];
  NSMenuItem* save = [[NSMenuItem alloc] initWithTitle:@"Save Image" action:@selector(saveImage:) keyEquivalent:@""];
  save.target = self;
  [menu addItem:save];
  NSMenuItem* saveAs = [[NSMenuItem alloc] initWithTitle:@"Save Image As…" action:@selector(saveImageAs:) keyEquivalent:@""];
  saveAs.target = self;
  [menu addItem:saveAs];
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem* copyAddress = [[NSMenuItem alloc] initWithTitle:@"Copy Image Address" action:@selector(copyImageAddress:) keyEquivalent:@""];
  copyAddress.target = self;
  [menu addItem:copyAddress];
  NSPoint windowPoint = [webView.window convertPointFromScreen:[NSEvent mouseLocation]];
  NSPoint viewPoint = [webView convertPoint:windowPoint fromView:nil];
  [menu popUpMenuPositioningItem:nil atLocation:viewPoint inView:webView];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
  [SlatePasswordServices.shared navigating:webView];
  [self.faviconRequest cancel];
  self.faviconRequest = nil;
  ++self.navigationGeneration;
  [self.mediaFrames removeAllObjects];
  pipState_.clear_frames();
  self.pageThemeReported = NO;
  if (self.events && self.events->theme_color_changed) self.events->theme_color_changed("");
  fprintf(stderr, "SLATE_NAV_START url=%s\n", webView.URL.absoluteString.UTF8String ?: "nil");
  NSAppearance* curApp = NSApp.effectiveAppearance;
  const BOOL isDarkApp = [curApp.name isEqualToString:NSAppearanceNameDarkAqua] ||
    [[curApp bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  NSColor* webBg = isDarkApp ? [NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0] : [NSColor colorWithCalibratedRed:0.97 green:0.96 blue:0.95 alpha:1.0];
  if (@available(macOS 12.0, *)) {
    webView.underPageBackgroundColor = webBg;
  }
  webView.layer.backgroundColor = webBg.CGColor;
  if (self.events && self.events->loading_changed) {
    self.events->loading_changed(true, 0.1);
  }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
  [SlatePasswordServices.shared navigated:webView];
  fprintf(stderr, "SLATE_NAV_COMMIT url=%s\n", webView.URL.absoluteString.UTF8String ?: "nil");
  slate::WebKitShields::Shared().InjectStreamingProtection(webView);
  dispatch_async(dispatch_get_main_queue(), ^{
    [SlatePDFOverlay checkAndConfigureForWebView:webView];
  });
  if (self.events) {
    if (self.events->address_changed && webView.URL) {
      self.events->address_changed(webView.URL.absoluteString.UTF8String ?: "");
    }
    if (self.events->navigation_changed) {
      self.events->navigation_changed(webView.canGoBack, webView.canGoForward);
    }
    if (self.events->loading_changed) {
      self.events->loading_changed(true, webView.estimatedProgress);
    }
    if (self.events->sign_in_settled) {
      self.events->sign_in_settled(true);
    }
  }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  fprintf(stderr, "SLATE_NAV_FINISH url=%s title=%s\n",
          webView.URL.absoluteString.UTF8String ?: "nil",
          webView.title.UTF8String ?: "nil");
  slate::WebKitShields::Shared().InjectStreamingProtection(webView);
  dispatch_async(dispatch_get_main_queue(), ^{
    [SlatePDFOverlay checkAndConfigureForWebView:webView];
  });
  if (self.events) {
    if (self.events->loading_changed) {
      self.events->loading_changed(false, 1.0);
    }
    if (self.events->title_changed && webView.title) {
      self.events->title_changed(webView.title.UTF8String ?: "");
    }
    if (self.events->address_changed && webView.URL) {
      self.events->address_changed(webView.URL.absoluteString.UTF8String ?: "");
    }
    if (self.events->navigation_changed) {
      self.events->navigation_changed(webView.canGoBack, webView.canGoForward);
    }
    if (self.events->protection_changed) {
      slate::ProtectionSignals signals;
      signals.observed = true;
      signals.loading = false;
      signals.uncertain = false;
      signals.observed_at = std::chrono::steady_clock::now();
      self.events->protection_changed(signals);
    }
    if (self.events->favicon_changed && webView.URL && ![webView.URL.absoluteString isEqualToString:@"about:blank"]) {
      NSString* js = @"(function() {"
        "var link = document.querySelector(\"link[rel*='icon']\");"
        "if (link && link.href) return link.href;"
        "return window.location.origin + '/favicon.ico';"
      "})()";
      __weak SlateWebNavigationDelegate* weakNav = self;
      const NSUInteger generation = self.navigationGeneration;
      [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        SlateWebNavigationDelegate* nav = weakNav;
        if (!nav || !nav.events || nav.navigationGeneration != generation || error) return;
        if (![result isKindOfClass:NSString.class] || ![(NSString*)result length]) return;
        [nav.faviconRequest cancel];
        nav.faviconRequest = [[SlateFaviconLoader sharedLoader] loadURL:[NSURL URLWithString:result]
          private:nav.incognito completion:^(NSData* png) {
            SlateWebNavigationDelegate* current = weakNav;
            if (!current || !current.events || current.navigationGeneration != generation) return;
            if (current.events->favicon_changed)
              current.events->favicon_changed(std::string((const char*)png.bytes, png.length));
          }];
      }];
    }
  }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  fprintf(stderr, "SLATE_NAV_FAIL url=%s error=%s\n",
          webView.URL.absoluteString.UTF8String ?: "nil",
          error.localizedDescription.UTF8String ?: "unknown");
  if (self.events && self.events->loading_changed) {
    self.events->loading_changed(false, 0.0);
  }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  fprintf(stderr, "SLATE_NAV_FAIL_PROVISIONAL url=%s domain=%s code=%ld desc=%s userinfo=%s\n",
          webView.URL.absoluteString.UTF8String ?: "nil",
          error.domain.UTF8String ?: "nil",
          (long)error.code,
          error.localizedDescription.UTF8String ?: "nil",
          error.userInfo.description.UTF8String ?: "nil");
  if (self.events && self.events->loading_changed) {
    self.events->loading_changed(false, 0.0);
  }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL* targetUrl = navigationAction.request.URL;
  NSString* urlStr = targetUrl.absoluteString;
  NSString* scheme = targetUrl.scheme.lowercaseString;
  fprintf(stderr, "SLATE_NAV_DECIDE_POLICY targetFrame=%p url=%s\n",
          navigationAction.targetFrame, urlStr.UTF8String ?: "nil");
  if (navigationAction.shouldPerformDownload) {
    fprintf(stderr, "SLATE_DOWNLOAD_ACTION url=%s\n", urlStr.UTF8String ?: "nil");
    decisionHandler(WKNavigationActionPolicyDownload);
    return;
  }

  // Security: Disallow remote web content from navigating to local file:// resources
  if (targetUrl.isFileURL) {
    if (!webView.URL.isFileURL && !(navigationAction.targetFrame.isMainFrame && [targetUrl isEqual:self.typedFileURL])) {
      fprintf(stderr, "SLATE_BLOCKED_LOCAL_FILE_NAV url=%s\n", urlStr.UTF8String ?: "nil");
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    }
  }

  if(navigationAction.targetFrame.isMainFrame) self.typedFileURL=nil;

  // Security: Disallow dangerous / malicious schemes
  if ([scheme isEqualToString:@"javascript"] ||
      [scheme isEqualToString:@"applescript"] ||
      [scheme isEqualToString:@"terminal"] ||
      [scheme isEqualToString:@"vbscript"] ||
      [scheme isEqualToString:@"diskcopy"]) {
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }

  // Security: Handle safe external schemes only when explicitly activated by user click
  if ([scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"tel"]) {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
      [[NSWorkspace sharedWorkspace] openURL:targetUrl];
    }
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }

  // Security: Disallow arbitrary unknown external application schemes from web content
  if (![scheme isEqualToString:@"http"] &&
      ![scheme isEqualToString:@"https"] &&
      ![scheme isEqualToString:@"about"] &&
      ![scheme isEqualToString:@"blob"] &&
      ![scheme isEqualToString:@"data"] &&
      ![scheme isEqualToString:@"webkit-extension"] &&
      ![scheme isEqualToString:@"safari-web-extension"] &&
      ![scheme isEqualToString:@"chrome-extension"] &&
      !targetUrl.isFileURL) {
    fprintf(stderr, "SLATE_BLOCKED_EXTERNAL_SCHEME scheme=%s url=%s\n",
            scheme.UTF8String ?: "nil", urlStr.UTF8String ?: "nil");
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }

  // Ad & Tracker Blocking: Cancel navigation for third-party ad iframes when shields are active
  if (navigationAction.targetFrame != nil && !navigationAction.targetFrame.isMainFrame) {
    if (slate::WebKitShields::Shared().IsEnabledForIncognito(self.incognito)) {
      NSString* reqHost = targetUrl.host.lowercaseString;
      if (slate::WebKitShields::Shared().IsAdOrTrackerHost(reqHost)) {
        fprintf(stderr, "SLATE_BLOCKED_AD_SUBFRAME url=%s\n", urlStr.UTF8String ?: "nil");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
      }
    }
  }

  if (navigationAction.targetFrame != nil && navigationAction.targetFrame.isMainFrame) {
    slate::WebKitShields::Shared().UpdateControllerForURL(webView.configuration.userContentController, targetUrl);
  }

  decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
  if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)navigationResponse.response;
    NSString *disposition = [httpResponse valueForHTTPHeaderField:@"Content-Disposition"];
    if (disposition && [disposition localizedCaseInsensitiveContainsString:@"attachment"]) {
      fprintf(stderr, "SLATE_DOWNLOAD_ATTACHMENT url=%s disposition=%s\n",
              navigationResponse.response.URL.absoluteString.UTF8String ?: "nil",
              disposition.UTF8String ?: "nil");
      decisionHandler(WKNavigationResponsePolicyDownload);
      return;
    }
  }
  NSString* mime = navigationResponse.response.MIMEType.lowercaseString;
  if ([mime isEqualToString:@"application/pdf"] || [mime isEqualToString:@"text/pdf"] || [navigationResponse.response.URL.path.lowercaseString hasSuffix:@".pdf"]) {
    decisionHandler(WKNavigationResponsePolicyAllow);
    return;
  }
  if (!navigationResponse.canShowMIMEType) {
    fprintf(stderr, "SLATE_DOWNLOAD_MIME url=%s mime=%s\n",
            navigationResponse.response.URL.absoluteString.UTF8String ?: "nil",
            navigationResponse.response.MIMEType.UTF8String ?: "nil");
    decisionHandler(WKNavigationResponsePolicyDownload);
    return;
  }
  decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)attachDownload:(WKDownload *)download forWebView:(WKWebView *)webView source:(const char *)source {
  if (!download) return;
  fprintf(stderr, "SLATE_DOWNLOAD_STARTED %s url=%s\n",
          source ?: "unknown",
          download.originalRequest.URL.absoluteString.UTF8String ?: "nil");
  SlateDownloadManager *manager = [SlateDownloadManager sharedManager];
  // Register BEFORE assigning delegate so decideDestinationUsingResponse: always finds the item
  // even when WebKit invokes the delegate synchronously upon assignment.
  [manager registerDownload:download forWebView:webView];
  download.delegate = manager;
  if (self.events && self.events->protection_changed) {
    slate::ProtectionSignals signals;
    signals.observed = true;
    signals.loading = false;
    signals.download = true;
    signals.uncertain = false;
    signals.observed_at = std::chrono::steady_clock::now();
    self.events->protection_changed(signals);
  }
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download {
  (void)navigationResponse;
  [self attachDownload:download forWebView:webView source:"response"];
}

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download {
  (void)navigationAction;
  [self attachDownload:download forWebView:webView source:"action"];
}

// Private WebKit delegate hook for "Download Linked File" from the native context menu.
- (void)_webView:(WKWebView *)webView contextMenuDidCreateDownload:(WKDownload *)download {
  [self attachDownload:download forWebView:webView source:"context_menu"];
}


// WKUIDelegate: Handle window.open popups
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
  NSURL* url = navigationAction.request.URL;
  NSString* urlStr = url.absoluteString;
  fprintf(stderr, "SLATE_CREATE_WEBVIEW targetFrame=%p url=%s navType=%ld download=%d\n",
          navigationAction.targetFrame,
          urlStr.UTF8String ?: "nil",
          (long)navigationAction.navigationType,
          navigationAction.shouldPerformDownload ? 1 : 0);

  if (navigationAction.shouldPerformDownload) {
    if (@available(macOS 11.3, *)) {
      __weak SlateWebNavigationDelegate* weakSelf = self;
      [webView startDownloadUsingRequest:navigationAction.request completionHandler:^(WKDownload *download) {
        [weakSelf attachDownload:download forWebView:webView source:"popup_action"];
      }];
      return nil;
    }
  }

  // Block ad-network popups & popunders when Slate Shields is active on the opener page.
  {
    const bool isIncog = !webView.configuration.websiteDataStore.isPersistent;
    const std::string openerHost = webView.URL.host ? webView.URL.host.UTF8String : "";
    auto& shields = slate::WebKitShields::Shared();
    if (shields.IsEnabledForIncognito(isIncog) && (openerHost.empty() || shields.IsSiteEnabled(openerHost))) {
      NSString* targetHost = url.host.lowercaseString ?: @"";
      NSString* targetPath = url.path ?: @"";
      const BOOL isNovaPromoRedirect =
          ([targetHost isEqualToString:@"novahd.cc"] || [targetHost hasSuffix:@".novahd.cc"]) &&
          [targetPath hasPrefix:@"/r/"];
      if (isNovaPromoRedirect || (targetHost.length && shields.IsAdOrTrackerHost(targetHost))) {
        fprintf(stderr, "SLATE_SHIELD_BLOCKED_POPUP url=%s\n", urlStr.UTF8String ?: "nil");
        return nil;
      }
    }
  }

  // Return the actual tab-owned view so WebKit retains window.opener, POST
  // requests, and script-populated about:blank windows.
  if (self.events && self.events->create_popup_tab) {
    return (__bridge WKWebView*)self.events->create_popup_tab(
        (__bridge void*)configuration, urlStr.UTF8String ?: "about:blank");
  }
  return nil;
}

- (void)webViewDidClose:(WKWebView *)webView {
  if (self.events && self.events->popup_close_requested) {
    self.events->popup_close_requested();
  }
}

// WKUIDelegate: Handle media capture permissions (mic/camera for Wispr Flow, Zoom, Canvas)
- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
  initiatedByFrame:(WKFrameInfo *)frame
              type:(WKMediaCaptureType)type
   decisionHandler:(void (^)(WKPermissionDecision))decisionHandler API_AVAILABLE(macos(12.0)) {
  decisionHandler(WKPermissionDecisionPrompt);
}

// WKUIDelegate: Handle JavaScript dialogs so SPAs do not hang
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
  initiatedByFrame:(WKFrameInfo *)frame
 completionHandler:(void (^)(void))completionHandler {
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = message;
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  completionHandler();
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
  initiatedByFrame:(WKFrameInfo *)frame
 completionHandler:(void (^)(BOOL result))completionHandler {
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = message;
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  completionHandler([alert runModal] == NSAlertFirstButtonReturn);
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
       defaultText:(NSString *)defaultText
  initiatedByFrame:(WKFrameInfo *)frame
 completionHandler:(void (^)(NSString *result))completionHandler {
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = prompt;
  NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
  input.stringValue = defaultText ?: @"";
  alert.accessoryView = input;
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] == NSAlertFirstButtonReturn) {
    completionHandler(input.stringValue);
  } else {
    completionHandler(nil);
  }
}

// WKUIDelegate: Handle file upload dialogs (<input type="file"> for resumes, job applications, attachments)
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
   initiatedByFrame:(WKFrameInfo *)frame
  completionHandler:(void (^)(NSArray<NSURL *> * _Nullable URLs))completionHandler {
#if defined(SLATE_ENABLE_VERIFY)
  fprintf(stderr, "SLATE_OPEN_PANEL multiple=%d\n", parameters.allowsMultipleSelection ? 1 : 0);
#endif
  void (^runBlock)(void) = ^{
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    if (@available(macOS 10.13.4, *)) {
      openPanel.canChooseDirectories = parameters.allowsDirectories;
    }
    openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    openPanel.resolvesAliases = YES;
    openPanel.title = @"Choose File to Upload";
    openPanel.prompt = @"Upload";
    openPanel.message = parameters.allowsMultipleSelection ? @"Select files to upload:" : @"Select a file to upload:";

    NSWindow* window = webView.window ?: [NSApp keyWindow] ?: [NSApp mainWindow];
    if (window && !window.attachedSheet) {
      [openPanel beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
          completionHandler(openPanel.URLs);
        } else {
          completionHandler(nil);
        }
      }];
    } else {
      NSModalResponse returnCode = [openPanel runModal];
      if (returnCode == NSModalResponseOK) {
        completionHandler(openPanel.URLs);
      } else {
        completionHandler(nil);
      }
    }
  };

  if ([NSThread isMainThread]) {
    runBlock();
  } else {
    dispatch_async(dispatch_get_main_queue(), runBlock);
  }
}

#include "engine/autofill_js.h"
#include "engine/media_monitor_js.h"

// WKScriptMessageHandler: Handle media playing and audible updates from in-page media observer
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
  if ([message.name isEqualToString:@"slateExtShim"]) {
    if (message.webView != self.webView || ![message.body isKindOfClass:[NSDictionary class]]) return;
    [[SlateExtensionsManager sharedManager] handleShimMessage:(NSDictionary*)message.body fromWebView:self.webView];
    return;
  }

  if ([message.name isEqualToString:@"slateWebStore"]) {
    if (message.webView != self.webView || ![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary* dict = (NSDictionary*)message.body;
    NSString* op = [dict[@"op"] isKindOfClass:[NSString class]] ? dict[@"op"] : @"";
    NSString* extId = [dict[@"id"] isKindOfClass:[NSString class]] ? dict[@"id"] : @"";
    if (!extId.length) return;
    __weak WKWebView* weakWeb = self.webView;
    auto sendState = ^(NSString* state, NSString* msg) {
      WKWebView* wv = weakWeb;
      if (!wv) return;
      NSDictionary* payload = @{@"id": extId, @"state": state ?: @"", @"message": msg ?: @""};
      NSData* json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
      NSString* jsonStr = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
      NSString* js = [NSString stringWithFormat:@"window.__slateWebStoreUpdate && window.__slateWebStoreUpdate(%@);", jsonStr];
      if (@available(macOS 11.0, *)) {
        [wv evaluateJavaScript:js inFrame:nil inContentWorld:[WKContentWorld defaultClientWorld] completionHandler:nil];
      }
    };
    if ([op isEqualToString:@"query"]) {
      if (![SlateExtensionsManager sharedManager].globalEnabled) {
        sendState(@"disabled", @"");
        return;
      }
      BOOL installed = [[SlateExtensionsManager sharedManager] isExtensionInstalled:extId];
      sendState(installed ? @"installed" : @"ready", @"");
    } else if ([op isEqualToString:@"install"]) {
      sendState(@"installing", @"");
      [[SlateExtensionsManager sharedManager] installFromChromeWebStoreId:extId completion:^(SlateExtensionRecord* rec, NSError* err) {
        if (err || !rec) {
          sendState(@"error", err.localizedDescription ?: @"Install failed");
        } else {
          sendState(@"installed", rec.name ?: @"Installed");
        }
      }];
    } else if ([op isEqualToString:@"remove"]) {
      [[SlateExtensionsManager sharedManager] removeExtensionId:extId];
      sendState(@"ready", @"");
    }
    return;
  }

  if ([message.name isEqualToString:kSlateSwipeScrollMessageName]) {
    if (message.webView != self.webView || ![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary* dict = (NSDictionary*)message.body;
    NSString* side = [dict[@"side"] isKindOfClass:[NSString class]] ? dict[@"side"] : nil;
    if (side && [self.webView isKindOfClass:[SlateSwipeWebView class]]) {
      [(SlateSwipeWebView*)self.webView handleSwipeScrollAnswerFree:[side isEqualToString:@"free"]];
    }
    return;
  }
  if ([message.name isEqualToString:@"slateImageDownload"]) {
    if (message.webView != self.webView || ![message.body isKindOfClass:NSString.class]) return;
    NSString* source = (NSString*)message.body;
    if (source.length > 8192) return;
    NSURL* imageURL = [NSURL URLWithString:source];
    NSString* scheme = imageURL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return;
    if (!imageURL.host.length) return;
    [self showImageMenuForURL:imageURL];
  } else if ([message.name isEqualToString:@"slateTheme"]) {
    if (!message.frameInfo.isMainFrame || message.webView != self.webView || ![message.body isKindOfClass:[NSString class]]) return;
    NSString* value = (NSString*)message.body;
    if (value.length != 7 || [value characterAtIndex:0] != '#') return;
    NSCharacterSet* hexDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    if ([[value substringFromIndex:1] rangeOfCharacterFromSet:hexDigits.invertedSet].location != NSNotFound) return;
    self.pageThemeReported = YES;
    if (self.events && self.events->theme_color_changed) self.events->theme_color_changed(value.UTF8String);
  } else if ([message.name isEqualToString:@"slateMedia"] && [message.body isKindOfClass:[NSDictionary class]]) {
    NSDictionary* dict = (NSDictionary*)message.body;
    NSString* frameId = dict[@"frame_id"];
    if (![frameId isKindOfClass:NSString.class] || frameId.length > 80 ||
        [frameId rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet].invertedSet].location != NSNotFound) return;
    if (!self.mediaFrames) self.mediaFrames = [NSMutableDictionary dictionary];
    const bool pipChanged=[dict[@"removed"] boolValue]
      ? pipState_.remove_frame(frameId.UTF8String) : pipState_.frame(frameId.UTF8String,[dict[@"pip"] boolValue]);
    if(pipChanged && self.events && self.events->pip_changed) self.events->pip_changed(pipState_.active());
    if ([dict[@"removed"] boolValue]) [self.mediaFrames removeObjectForKey:frameId];
    else self.mediaFrames[frameId] = dict;
    BOOL audible = NO, video = NO, hasVideo = NO, userStarted = NO;
    int width = 0, height = 0;
    double bestScore = -1;
    NSString* primaryFrame = @"";
    for (NSString* candidateId in self.mediaFrames) {
      NSDictionary* frame = self.mediaFrames[candidateId];
      audible |= [frame[@"audible"] boolValue];
      video |= [frame[@"video"] boolValue];
      hasVideo |= [frame[@"has_video"] boolValue];
      userStarted |= [frame[@"user_started"] boolValue];
      if ([frame[@"candidate_score"] doubleValue] > bestScore && [frame[@"video"] boolValue]) {
        bestScore = [frame[@"candidate_score"] doubleValue];
        primaryFrame = candidateId;
        width = [frame[@"width"] intValue];
        height = [frame[@"height"] intValue];
      }
    }
    if (self.events && self.events->media_ui_changed) {
      self.events->media_ui_changed(audible, video, hasVideo, userStarted,
        primaryFrame.UTF8String ?: "");
    }
    if (self.events && self.events->media_quality_changed) {
      NSString* quality = height > 0 ? [NSString stringWithFormat:@"%dp", height] : @"";
      self.events->media_quality_changed(width, height, quality.UTF8String ?: "", NO);
    }
  } else if ([message.name isEqualToString:@"slatePiP"] && [message.body isKindOfClass:[NSDictionary class]]) {
    NSDictionary* dict = (NSDictionary*)message.body;
    NSString* frameId=dict[@"frame_id"];
    // Legacy/unidentified frame signals cannot override an active player.
    if(![frameId isKindOfClass:NSString.class] || !self.mediaFrames[frameId]) return;
    if(pipState_.frame(frameId.UTF8String,[dict[@"active"] boolValue]) && self.events && self.events->pip_changed)
      self.events->pip_changed(pipState_.active());
  } else if ([message.name isEqualToString:@"slateConsole"]) {
    NSString* text = [NSString stringWithFormat:@"%@", message.body];
    fprintf(stderr, "%s\n", text.UTF8String);
  } else if ([message.name isEqualToString:@"slateAutofill"] && [message.body isKindOfClass:[NSDictionary class]]) {
    if (self.incognito) return; // Strict privacy: never autofill or prompt to save in incognito
    // The page must not choose which site's passwords it requests.
    if (!message.frameInfo.isMainFrame || message.webView != self.webView) return;
    WKSecurityOrigin* caller = message.frameInfo.securityOrigin;
    if (![caller.protocol.lowercaseString isEqualToString:@"https"] || !caller.host.length) return;
    NSURLComponents* trusted = [NSURLComponents new];
    trusted.scheme = caller.protocol.lowercaseString;
    trusted.host = caller.host.lowercaseString;
    if (caller.port && caller.port != 443) trusted.port = @(caller.port);
    NSString* origin = trusted.string;
    NSURLComponents* current = [NSURLComponents componentsWithURL:self.webView.URL resolvingAgainstBaseURL:NO];
    if (![current.scheme.lowercaseString isEqualToString:trusted.scheme] ||
        ![current.host.lowercaseString isEqualToString:trusted.host] ||
        (current.port ? current.port.integerValue : 443) != (trusted.port ? trusted.port.integerValue : 443)) return;
    NSDictionary* dict = (NSDictionary*)message.body;
    NSString* action = [dict[@"action"] isKindOfClass:NSString.class] ? dict[@"action"] : @"";
    if ([action isEqualToString:@"save"] && self.events && self.events->credential_save_requested) {
      NSString* username = [dict[@"username"] isKindOfClass:NSString.class] ? dict[@"username"] : @"";
      NSString* password = [dict[@"password"] isKindOfClass:NSString.class] ? dict[@"password"] : @"";
      if (origin.length && password.length) {
        if ([SlatePasswordServices.shared consumedAppleFill:self.webView host:caller.host user:username password:password]) return;
        self.events->credential_save_requested(origin.UTF8String, username.UTF8String, password.UTF8String);
      }
    }
    // Security: Webpages cannot query credentials. Autofill requires explicit native authorization.
  } else if ([message.name isEqualToString:@"officeForms"] && [message.body isKindOfClass:[NSDictionary class]]) {
    NSDictionary* body = (NSDictionary*)message.body;
    NSString* kind = [body[@"kind"] isKindOfClass:[NSString class]] ? body[@"kind"] : @"";
    if ([kind isEqualToString:@"form"]) {
      if (self.events && self.events->sign_in_found) {
        self.events->sign_in_found();
      }
    } else if ([kind isEqualToString:@"submit"]) {
      if (self.incognito) return;
      WKSecurityOrigin* caller = message.frameInfo.securityOrigin;
      NSString* scheme = caller.protocol.lowercaseString;
      NSString* host = caller.host.lowercaseString;
      if (![scheme isEqualToString:@"https"] && ![host isEqualToString:@"localhost"] && ![host isEqualToString:@"127.0.0.1"]) return;
      NSString* portPart = (caller.port && caller.port != 443 && caller.port != 80) ? [NSString stringWithFormat:@":%ld", (long)caller.port] : @"";
      NSString* origin = [NSString stringWithFormat:@"%@://%@%@", scheme, host, portPart];
      NSString* user = [body[@"user"] isKindOfClass:[NSString class]] ? body[@"user"] : @"";
      NSString* pass = [body[@"password"] isKindOfClass:[NSString class]] ? body[@"password"] : @"";
      if (origin.length && pass.length) {
        if ([SlatePasswordServices.shared consumedAppleFill:self.webView host:host user:user password:pass]) return;
        if (self.events && self.events->sign_in_submitted) {
          self.events->sign_in_submitted(origin.UTF8String, user.UTF8String, pass.UTF8String);
        }
        if (self.events && self.events->credential_save_requested) {
          self.events->credential_save_requested(origin.UTF8String, user.UTF8String, pass.UTF8String);
        }
      }
    } else if ([kind isEqualToString:@"settled"]) {
      if (self.incognito) return;
      if (self.events && self.events->sign_in_settled) {
        self.events->sign_in_settled(false);
      }
    } else if ([kind isEqualToString:@"focus"]) {
      BOOL typing = [body[@"typing"] boolValue];
      NSDictionary* rect = [body[@"rect"] isKindOfClass:[NSDictionary class]] ? body[@"rect"] : nil;
      if (rect) {
        double x = [rect[@"x"] doubleValue];
        double y = [rect[@"y"] doubleValue];
        double w = [rect[@"w"] doubleValue];
        double h = [rect[@"h"] doubleValue];
        if (self.events && self.events->focus_changed) {
          self.events->focus_changed(typing, x, y, w, h, true);
        }
      } else {
        if (self.events && self.events->focus_changed) {
          self.events->focus_changed(typing, 0, 0, 0, 0, false);
        }
      }
    } else if ([kind isEqualToString:@"fullscreen"]) {
      BOOL on = [body[@"on"] boolValue];
      if (self.events && self.events->fullscreen_changed) {
        self.events->fullscreen_changed(on);
      }
    }
  } else if ([message.name isEqualToString:@"omidJsSessionService"]) {
    // Open Measurement (OMID) ad verification message safely handled
    return;
  }
}

- (void)_webView:(WKWebView *)webView hasVideoInPictureInPictureDidChange:(BOOL)inPictureInPicture {
  pipState_.native(inPictureInPicture);
  if (self.events && self.events->pip_changed) {
    self.events->pip_changed(inPictureInPicture);
  }
}

@end

@implementation SlateFrameRate

static BOOL sFast = NO;
static NSHashTable<WKPreferences*>* sChangedPrefs = nil;
static id sNear60Feature = nil;
static dispatch_once_t sFeatureToken;

+ (id)near60Feature {
  dispatch_once(&sFeatureToken, ^{
    sChangedPrefs = [NSHashTable weakObjectsHashTable];
    SEL listSel = NSSelectorFromString(@"_features");
    id cls = [WKPreferences class];
    if ([cls respondsToSelector:listSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      NSArray* features = [cls performSelector:listSel];
#pragma clang diagnostic pop
      for (id f in features) {
        if ([[f valueForKey:@"key"] isEqualToString:@"PreferPageRenderingUpdatesNear60FPSEnabled"]) {
          sNear60Feature = f;
          break;
        }
      }
    }
  });
  return sNear60Feature;
}

+ (BOOL)is120HzAvailable {
  return [self near60Feature] != nil;
}

+ (BOOL)isFast {
  return sFast;
}

+ (void)setFeatureValue:(BOOL)val inPreferences:(WKPreferences*)prefs {
  id feature = [self near60Feature];
  SEL setSel = NSSelectorFromString(@"_setEnabled:forFeature:");
  if (feature && [prefs respondsToSelector:setSel]) {
    typedef void (*SetterFn)(id, SEL, BOOL, id);
    SetterFn fn = (SetterFn)[prefs methodForSelector:setSel];
    fn(prefs, setSel, val, feature);
  }
}

+ (void)setFast:(BOOL)fast {
  if (sFast == fast) return;
  sFast = fast;
  id feature = [self near60Feature];
  if (!feature) return;

  if (sFast) {
    // New tabs and reloads will automatically apply high refresh rate
  } else {
    for (WKPreferences* p in [sChangedPrefs allObjects]) {
      [self setFeatureValue:YES inPreferences:p];
    }
    [sChangedPrefs removeAllObjects];
  }
}

+ (void)applyToPreferences:(WKPreferences*)prefs {
  if (!sFast || ![self near60Feature] || !prefs) return;
  [self setFeatureValue:NO inPreferences:prefs];
  [sChangedPrefs addObject:prefs];
}

+ (BOOL)prefersNear60:(WKPreferences*)prefs {
  id feature = [self near60Feature];
  SEL getSel = NSSelectorFromString(@"_isEnabledForFeature:");
  if (feature && [prefs respondsToSelector:getSel]) {
    typedef BOOL (*GetterFn)(id, SEL, id);
    GetterFn fn = (GetterFn)[prefs methodForSelector:getSel];
    return fn(prefs, getSel, feature);
  }
  return YES;
}

@end

namespace slate {


static WKProcessPool* GetSharedProcessPool(bool incognito) {
  static WKProcessPool* sharedPool = nil;
  static WKProcessPool* incognitoPool = nil;
  if (incognito) {
    if (!incognitoPool) incognitoPool = [[WKProcessPool alloc] init];
    return incognitoPool;
  } else {
    if (!sharedPool) sharedPool = [[WKProcessPool alloc] init];
    return sharedPool;
  }
}

class WebKitEngine final : public BrowserEngine {

 public:
  WebKitEngine(void* native_view, EngineEvents events, const std::string& url, ShieldController* shields, bool incognito, void* website_data_store = nullptr, void* popup_configuration = nullptr)
      : events_(std::move(events)), incognito_(incognito) {
    NSView* parent = (__bridge NSView*)native_view;

    // Slate note: Preserve a supplied popup configuration, or create one for a new page; storage and
    // injected scripts are configured before constructing the WKWebView.
    WKWebViewConfiguration* config = popup_configuration
        ? (__bridge WKWebViewConfiguration*)popup_configuration
        : [[WKWebViewConfiguration alloc] init];
    // Each tab owns its message handlers; retain WebKit's related-page configuration.
    if (popup_configuration) {
      config.userContentController = [[WKUserContentController alloc] init];
    } else {
      config.processPool = GetSharedProcessPool(incognito_);
    }
    config.applicationNameForUserAgent = SlateSafariApplicationName();
    if (@available(macOS 15.4, *)) {
      WKWebExtensionController* extCtrl = [SlateExtensionsManager sharedManager].controller;
      if (extCtrl) {
        config.webExtensionController = extCtrl;
      }
    }
    config.allowsAirPlayForMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAudio;

    if (@available(macOS 10.15, *)) {
      WKWebpagePreferences* prefs = [[WKWebpagePreferences alloc] init];
      prefs.allowsContentJavaScript = YES;
      prefs.preferredContentMode = WKContentModeDesktop;
      config.defaultWebpagePreferences = prefs;
      config.preferences.fraudulentWebsiteWarningEnabled = YES;
    }
    config.preferences.javaScriptCanOpenWindowsAutomatically = NO;

    if (popup_configuration) {
      // Preserve the opener's store, including its private or per-space session.
    } else if (incognito_) {
      WKWebsiteDataStore* privateStore = [WKWebsiteDataStore nonPersistentDataStore];
      [SlatePrivacySecurity applyIncognitoProxyToDataStore:privateStore];
      config.websiteDataStore = privateStore;
    } else if (website_data_store) {
      config.websiteDataStore = (__bridge WKWebsiteDataStore*)website_data_store;
    } else {
      config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    }
    if (@available(macOS 11.3, *)) {
      config.upgradeKnownHostsToHTTPS = [SlatePrivacySecurity httpsOnlyEnabled];
    }

    // Preferences for media & popups
    if (@available(macOS 12.3, *)) {
      config.preferences.elementFullscreenEnabled = YES;
      config.preferences.siteSpecificQuirksModeEnabled = YES;
    }
    @try {
      config.allowsAirPlayForMediaPlayback = YES;
      [config setValue:@YES forKey:@"allowsPictureInPictureMediaPlayback"];
    } @catch (id ex) {}
    @try {
      [config.preferences setValue:@YES forKey:@"allowsPictureInPictureMediaPlayback"];
      [config.preferences setValue:@YES forKey:@"fullScreenEnabled"];
    } @catch (id ex) {}
    SEL setPipSel = NSSelectorFromString(@"_setAllowsPictureInPictureMediaPlayback:");
    if ([config.preferences respondsToSelector:setPipSel]) {
      reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(config.preferences, setPipSel, YES);
    }
    SEL setFsSel = NSSelectorFromString(@"_setFullScreenEnabled:");
    if ([config.preferences respondsToSelector:setFsSel]) {
      reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(config.preferences, setFsSel, YES);
    }
    // Disable legacy macOS WebKit Backspace/Delete -> Go Back navigation so web apps and games
    // (e.g. Wordle) receive Backspace without accidentally navigating to the previous page.
    SEL setBackspaceNavSel = NSSelectorFromString(@"_setBackspaceKeyNavigationEnabled:");
    if ([config.preferences respondsToSelector:setBackspaceNavSel]) {
      reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(config.preferences, setBackspaceNavSel, NO);
    } else {
      @try {
        [config.preferences setValue:@NO forKey:@"backspaceKeyNavigationEnabled"];
      } @catch (id ex) {}
    }
    // macOS energy & battery optimization: match Safari's background tab suspension,
    // progressive hidden-tab DOM timer throttling, and low-power media audio/video buffering.
    if (@available(macOS 14.0, *)) {
      config.preferences.inactiveSchedulingPolicy = WKInactiveSchedulingPolicySuspend;
    }
    for (NSString* selName in @[
      @"_setDOMTimersThrottlingEnabled:",
      @"_setHiddenPageDOMTimerThrottlingEnabled:",
      @"_setHiddenPageDOMTimerThrottlingAutoIncreases:"
    ]) {
      SEL s = NSSelectorFromString(selName);
      if ([config.preferences respondsToSelector:s]) {
        reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(config.preferences, s, YES);
      }
    }
    [SlateFrameRate applyToPreferences:config.preferences];

    // Attach shields (ad blocking, stream ad defusers, and anti-fingerprinting)
    WebKitShields::Shared().ApplyToUserContentController(config.userContentController, incognito_);

    // Attach high-alert privacy hardening (GPC, DNT, and WebRTC IP-leak blocking in Incognito)
    NSString* hardeningJs = [SlatePrivacySecurity hardeningScriptForIncognito:incognito_];
    if (hardeningJs.length > 0) {
      WKUserScript* hardeningScript = [[WKUserScript alloc] initWithSource:hardeningJs
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                          forMainFrameOnly:NO];
      [config.userContentController addUserScript:hardeningScript];
    }

    // Anti-flashbang dark mode styling at document start
    NSString* antiFlashJs = @R"JS(
      (function() {
        try {
          const isDark = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
          if (isDark) {
            const style = document.createElement('style');
            style.id = '__slate_anti_flash__';
            style.textContent = `
              @media (prefers-color-scheme: dark) {
                html:not([data-slate-ready]) {
                  background-color: #121214 !important;
                  color-scheme: dark;
                }
              }
            `;
            if (document.documentElement) {
              document.documentElement.appendChild(style);
            }
            const cleanup = function() {
              const el = document.getElementById('__slate_anti_flash__');
              if (el) el.remove();
              if (document.documentElement) {
                document.documentElement.setAttribute('data-slate-ready', 'true');
              }
            };
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', cleanup, { once: true });
              window.addEventListener('load', cleanup, { once: true });
            } else {
              cleanup();
            }
          }
        } catch(e) {}
      })();
    )JS";
    WKUserScript* antiFlashScript = [[WKUserScript alloc] initWithSource:antiFlashJs
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:YES];
    [config.userContentController addUserScript:antiFlashScript];

    // Attach media monitoring script
    NSString* mediaMonitorJs = [NSString stringWithUTF8String:slate::kMediaMonitorJs];

    if (@available(macOS 11.0, *)) {
      WKUserScript* mediaScript = [[WKUserScript alloc] initWithSource:mediaMonitorJs
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                      forMainFrameOnly:NO
                                                        inContentWorld:[WKContentWorld defaultClientWorld]];
      [config.userContentController addUserScript:mediaScript];

      // Site-scoped idle memory optimizer (Kick/Twitch/YouTube chat DOM windowing, offscreen preview cleanup,
      // and hidden muted stream suspension). Default ON; user-configurable in Settings.
      NSNumber* memOptPref = [NSUserDefaults.standardUserDefaults objectForKey:@"SlateMemoryOptimizerEnabled"];
      if (!memOptPref || memOptPref.boolValue) {
        NSString* memOptJs = [NSString stringWithUTF8String:slate::kMemoryOptimizerJs];
        WKUserScript* memOptScript = [[WKUserScript alloc] initWithSource:memOptJs
                                                            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                         forMainFrameOnly:NO
                                                           inContentWorld:[WKContentWorld defaultClientWorld]];
        [config.userContentController addUserScript:memOptScript];
      }
    } else {
      WKUserScript* mediaScript = [[WKUserScript alloc] initWithSource:mediaMonitorJs
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                      forMainFrameOnly:NO];
      [config.userContentController addUserScript:mediaScript];
    }

    if (getenv("SLATE_DEBUG_CONSOLE")) {
      NSString* consoleCaptureJs = @R"JS(
        (function() {
          const send = (msg) => {
            try { window.webkit.messageHandlers.slateConsole.postMessage(msg); } catch(e){}
          };
          const origLog = console.log;
          console.log = function(...args) {
            send(args.join(' '));
            origLog.apply(console, args);
          };
          const origErr = console.error;
          console.error = function(...args) {
            send('ERROR: ' + args.join(' '));
            origErr.apply(console, args);
          };
          const origWarn = console.warn;
          console.warn = function(...args) {
            send('WARN: ' + args.join(' '));
            origWarn.apply(console, args);
          };
          window.addEventListener('error', function(e) {
            send('GLOBAL_ERR: ' + e.message + ' at ' + e.filename + ':' + e.lineno);
          }, true);
          window.addEventListener('unhandledrejection', function(e) {
            send('UNHANDLED_REJECTION: ' + (e.reason ? (e.reason.message || e.reason.stack || e.reason) : 'unknown'));
          });
          document.addEventListener('error', function(e) {
            if (e.target && (e.target.tagName === 'VIDEO' || e.target.tagName === 'AUDIO')) {
              var err = e.target.error;
              send('MEDIA_ELEMENT_ERR: ' + (err ? (err.code + ': ' + (err.message || '')) : 'unknown') + ' src=' + (e.target.src || e.target.currentSrc));
            }
          }, true);
          const origFetch = window.fetch;
          window.fetch = async function(...args) {
            try {
              const resp = await origFetch.apply(this, args);
              if (!resp.ok && resp.status >= 400) {
                const url = (args[0] && (args[0].url || args[0])) || '';
                const urlStr = typeof url === 'string' ? url : (url.href || '');
                send('FETCH_FAIL: status=' + resp.status + ' url=' + urlStr.substring(0, 160));
              }
              return resp;
            } catch(err) {
              const url = (args[0] && (args[0].url || args[0])) || '';
              const urlStr = typeof url === 'string' ? url : (url.href || '');
              send('FETCH_ERR: ' + err.message + ' url=' + urlStr.substring(0, 160));
              throw err;
            }
          };
        })();
      )JS";
      WKUserScript* consoleScript = [[WKUserScript alloc] initWithSource:consoleCaptureJs
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:NO];
      [config.userContentController addUserScript:consoleScript];
    }

    NSString* chromeCompatJs = @R"JS(
      (function() {
        try {
          var host = '';
          try {
            if (window.top && window.top.location && window.top.location.hostname) {
              host = window.top.location.hostname.toLowerCase();
            }
          } catch(e) {}
          if (!host && window.location && window.location.hostname) {
            host = window.location.hostname.toLowerCase();
          }
          if (!host && document.referrer) {
            try { host = (new URL(document.referrer)).hostname.toLowerCase(); } catch(e) {}
          }
          var streamingSuffixes = [
            'google.com', 'accounts.google.com', 'gstatic.com', 'googleusercontent.com', 'googleapis.com',
            'apple.com', 'icloud.com', 'appleid.apple.com',
            'microsoft.com', 'live.com', 'login.microsoftonline.com', 'office.com',
            'x.com', 'twitter.com', 'twimg.com',
            'max.com', 'hbomax.com', 'hbo.com', 'discomax.com', 'h264.io', 'warnermediacdn.com', 'warnermedia.com', 'wbd.com',
            'netflix.com', 'nflxvideo.net', 'nflximg.net', 'nflxext.com',
            'disneyplus.com', 'bamgrid.com', 'disney-plus.net',
            'hulu.com', 'hulustream.com',
            'peacocktv.com',
            'paramountplus.com',
            'primevideo.com', 'amazon.com', 'amazonvideo.com', 'aiv-cdn.net',
            'spotify.com',
            'crunchyroll.com',
            'tubitv.com',
            'pluto.tv',
            'fubo.tv',
            'sling.com',
            'starz.com',
            'mgmplus.com',
            'directv.com',
            'sho.com', 'showtime.com',
            'youtube.com', 'youtu.be', 'ytimg.com', 'googlevideo.com',
            'twitch.tv', 'kick.com'
          ];
          for (var i = 0; i < streamingSuffixes.length; i++) {
            var s = streamingSuffixes[i];
            if (host === s || host.endsWith('.' + s)) {
              return; // Keep pure Safari environment for FairPlay DRM and secure authentications
            }
          }
        } catch(e) {}

        if (typeof window.chrome === 'undefined') {
          window.chrome = {
            app: { isInstalled: false, InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' }, RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' } },
            runtime: {
              OnInstalledReason: { CHROME_UPDATE: 'chrome_update', INSTALL: 'install', SHARED_MODULE_UPDATE: 'shared_module_update', UPDATE: 'update' },
              PlatformArch: { ARM: 'arm', ARM64: 'arm64', MIPS: 'mips', MIPS64: 'mips64', X86_32: 'x86-32', X86_64: 'x86-64' },
              PlatformNaclArch: { ARM: 'arm', MIPS: 'mips', MIPS64: 'mips64', X86_32: 'x86-32', X86_64: 'x86-64' },
              PlatformOs: { ANDROID: 'android', CROS: 'cros', LINUX: 'linux', MAC: 'mac', OPENBSD: 'openbsd', WIN: 'win' },
              connect: function() {},
              sendMessage: function() {}
            },
            loadTimes: function() {
              var t = window.performance && window.performance.timing;
              var start = t ? t.navigationStart : Date.now();
              return {
                requestTime: start / 1000,
                startLoadTime: (t ? t.fetchStart : start) / 1000,
                commitLoadTime: (t ? t.responseStart : start) / 1000,
                finishDocumentLoadTime: (t ? t.domContentLoadedEventEnd : start) / 1000,
                finishLoadTime: (t ? t.loadEventEnd : start) / 1000,
                firstPaintTime: (t ? t.responseEnd : start) / 1000,
                firstPaintAfterLoadTime: 0,
                navigationType: 'Other'
              };
            },
            csi: function() { return { startE: Date.now(), onloadT: Date.now(), pageT: 0, tran: 0 }; }
          };
        }

        // Auto-activate lazy iframes only for sites requiring it (e.g. Wispr Flow sales forms using data-src)
        function activateLazyIframes() {
          try {
            if (host.indexOf('wisprflow') === -1) return;
            var iframes = document.querySelectorAll('iframe[data-src]');
            for (var i = 0; i < iframes.length; i++) {
              var frame = iframes[i];
              if (!frame.src || frame.src === 'about:blank' || frame.src === window.location.href) {
                frame.src = frame.getAttribute('data-src');
                frame.style.display = 'block';
              }
            }
          } catch(e) {}
        }
        if (host.indexOf('wisprflow') !== -1) {
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', activateLazyIframes);
          } else {
            activateLazyIframes();
          }
          setTimeout(activateLazyIframes, 1000);
        }
      })();
    )JS";
    WKUserScript* chromeScript = [[WKUserScript alloc] initWithSource:chromeCompatJs
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                      forMainFrameOnly:NO];
    [config.userContentController addUserScript:chromeScript];

    // Create delegate
    delegate_ = [[SlateWebNavigationDelegate alloc] init];
    delegate_.events = &events_;
    delegate_.incognito = incognito_;

    // Passkey suppression: when passkeys are not offered/entitled, hide PublicKeyCredential
    // so sites smoothly fall back to standard username/password forms.
    if (!SlatePasswordServices.passkeysAvailable) {
      NSString* passkeysJs = [SlateFormRelay withoutPasskeysScript];
      if (@available(macOS 11.0, *)) {
        WKUserScript* passkeyScript = [[WKUserScript alloc] initWithSource:passkeysJs
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                          forMainFrameOnly:NO
                                                            inContentWorld:[WKContentWorld pageWorld]];
        [config.userContentController addUserScript:passkeyScript];
      } else {
        WKUserScript* passkeyScript = [[WKUserScript alloc] initWithSource:passkeysJs
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                          forMainFrameOnly:NO];
        [config.userContentController addUserScript:passkeyScript];
      }
    }

    // Attach FormRelay script (sign-in detection, framework-safe autofill, typing & fullscreen tracking)
    NSString* formRelaySource = [SlateFormRelay formScript];
    if (@available(macOS 11.0, *)) {
      WKUserScript* formScript = [[WKUserScript alloc] initWithSource:formRelaySource
                                                        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                     forMainFrameOnly:NO
                                                       inContentWorld:[WKContentWorld defaultClientWorld]];
      [config.userContentController addUserScript:formScript];
    } else {
      WKUserScript* formScript = [[WKUserScript alloc] initWithSource:formRelaySource
                                                        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                     forMainFrameOnly:NO];
      [config.userContentController addUserScript:formScript];
    }

    // Attach legacy autofill script (disabled in incognito for zero footprint; main frame only)
    if (!incognito_) {
      NSString* autofillSource = [NSString stringWithUTF8String:slate::kAutofillJs];
      if (@available(macOS 11.0, *)) {
        WKUserScript* autofillScript = [[WKUserScript alloc] initWithSource:autofillSource
                                                              injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                           forMainFrameOnly:YES
                                                             inContentWorld:[WKContentWorld defaultClientWorld]];
        [config.userContentController addUserScript:autofillScript];
      } else {
        WKUserScript* autofillScript = [[WKUserScript alloc] initWithSource:autofillSource
                                                              injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                           forMainFrameOnly:YES];
        [config.userContentController addUserScript:autofillScript];
      }
    }

    NSString* pageThemeSource = [NSString stringWithUTF8String:kPageThemeJs];
    NSString* imageDownloadSource = [NSString stringWithUTF8String:kImageDownloadJs];
    if (@available(macOS 11.0, *)) {
      [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:imageDownloadSource
          injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO
          inContentWorld:[WKContentWorld defaultClientWorld]]];
    } else {
      [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:imageDownloadSource
          injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    }
    if (@available(macOS 11.0, *)) {
      WKUserScript* pageThemeScript = [[WKUserScript alloc] initWithSource:pageThemeSource
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                          forMainFrameOnly:YES
                                                            inContentWorld:[WKContentWorld defaultClientWorld]];
      [config.userContentController addUserScript:pageThemeScript];
    } else {
      WKUserScript* pageThemeScript = [[WKUserScript alloc] initWithSource:pageThemeSource
                                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                          forMainFrameOnly:YES];
      [config.userContentController addUserScript:pageThemeScript];
    }

    if (@available(macOS 11.0, *)) {
      WKUserScript* swipeScript = [[WKUserScript alloc] initWithSource:SlateSwipeWatchScript()
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                      forMainFrameOnly:NO
                                                        inContentWorld:[WKContentWorld defaultClientWorld]];
      [config.userContentController addUserScript:swipeScript];
      NSString* webStoreJs = @R"JS(
        (function() {
          const h = (location.hostname || '').toLowerCase();
          if (h !== 'chromewebstore.google.com' && h !== 'chrome.google.com') return;
          if (window.__slateWebStoreInit) return;
          window.__slateWebStoreInit = true;
          let bar = null, btn = null, subBtn = null, label = null, currentId = null;
          function extractId() {
            const parts = (location.pathname || '').split('/').filter(Boolean);
            for (let i = parts.length - 1; i >= 0; i--) {
              const s = parts[i].toLowerCase();
              if (/^[a-p]{32}$/.test(s)) return s;
            }
            return null;
          }
          function ensureBar() {
            if (bar && bar.isConnected) return bar;
            bar = document.createElement('div');
            bar.id = '__slate_cws_bar__';
            bar.style.cssText = 'position:fixed;right:20px;bottom:20px;z-index:2147483647;display:flex;align-items:center;gap:10px;padding:10px 14px;border-radius:12px;background:rgba(20,20,22,0.94);color:#f5f5f7;font:500 13px/1.2 -apple-system,BlinkMacSystemFont,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,0.32);border:1px solid rgba(255,255,255,0.12);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);';
            label = document.createElement('span');
            label.style.cssText = 'opacity:0.78;font-weight:400;font-size:12px;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
            label.textContent = 'Slate Extensions';
            btn = document.createElement('button');
            btn.type = 'button';
            btn.style.cssText = 'border:0;border-radius:8px;padding:6px 12px;background:#ffffff;color:#111113;font:600 12px/1 -apple-system,BlinkMacSystemFont,sans-serif;cursor:pointer;';
            btn.textContent = 'Add to Slate';
            btn.addEventListener('click', function() {
              if (!currentId || btn.disabled) return;
              try { window.webkit.messageHandlers.slateWebStore.postMessage({ op: 'install', id: currentId }); } catch (e) {}
            });
            subBtn = document.createElement('button');
            subBtn.type = 'button';
            subBtn.style.cssText = 'display:none;border:1px solid rgba(255,255,255,0.22);border-radius:8px;padding:6px 10px;background:transparent;color:#f5f5f7;font:500 12px/1 -apple-system,BlinkMacSystemFont,sans-serif;cursor:pointer;';
            subBtn.textContent = 'Remove';
            subBtn.addEventListener('click', function() {
              if (!currentId) return;
              try { window.webkit.messageHandlers.slateWebStore.postMessage({ op: 'remove', id: currentId }); } catch (e) {}
            });
            bar.appendChild(label);
            bar.appendChild(btn);
            bar.appendChild(subBtn);
            (document.body || document.documentElement).appendChild(bar);
            return bar;
          }
          window.__slateWebStoreUpdate = function(info) {
            if (!info || info.id !== currentId || !bar) return;
            if (info.state === 'disabled') {
              bar.style.display = 'none';
              return;
            }
            bar.style.display = 'flex';
            if (info.state === 'installing') {
              btn.disabled = true; btn.textContent = 'Installing…'; subBtn.style.display = 'none';
              label.textContent = 'Downloading from Chrome Web Store';
            } else if (info.state === 'installed') {
              btn.disabled = true; btn.textContent = 'Added to Slate'; subBtn.style.display = 'inline-block';
              label.textContent = info.message || 'Installed in Slate';
            } else if (info.state === 'error') {
              btn.disabled = false; btn.textContent = 'Retry'; subBtn.style.display = 'none';
              label.textContent = info.message || 'Install failed';
            } else {
              btn.disabled = false; btn.textContent = 'Add to Slate'; subBtn.style.display = 'none';
              label.textContent = 'Slate Extensions';
            }
          };
          function sync() {
            const id = extractId();
            if (!id) {
              currentId = null;
              if (bar) bar.style.display = 'none';
              return;
            }
            ensureBar();
            bar.style.display = 'flex';
            if (id !== currentId) {
              currentId = id;
              btn.disabled = false; btn.textContent = 'Add to Slate'; subBtn.style.display = 'none';
              label.textContent = 'Slate Extensions';
              try { window.webkit.messageHandlers.slateWebStore.postMessage({ op: 'query', id: currentId }); } catch (e) {}
            }
          }
          let lastHref = location.href;
          setInterval(function() {
            if (location.href !== lastHref) { lastHref = location.href; sync(); }
          }, 500);
          window.addEventListener('popstate', sync);
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', sync, { once: true });
          else sync();
        })();
      )JS";
      WKUserScript* webStoreScript = [[WKUserScript alloc] initWithSource:webStoreJs
                                                            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                         forMainFrameOnly:YES
                                                           inContentWorld:[WKContentWorld defaultClientWorld]];
      [config.userContentController addUserScript:webStoreScript];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateWebStore"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:kSlateSwipeScrollMessageName];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateMedia"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateTheme"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateImageDownload"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slatePiP"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:[SlateFormRelay messageName]];
      if (!incognito_) {
        [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateAutofill"];
      }
    } else {
      WKUserScript* swipeScript = [[WKUserScript alloc] initWithSource:SlateSwipeWatchScript()
                                                         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                      forMainFrameOnly:NO];
      [config.userContentController addUserScript:swipeScript];
      [config.userContentController addScriptMessageHandler:delegate_ name:kSlateSwipeScrollMessageName];
      [config.userContentController addScriptMessageHandler:delegate_ name:@"slateMedia"];
      [config.userContentController addScriptMessageHandler:delegate_ name:@"slateTheme"];
      [config.userContentController addScriptMessageHandler:delegate_ name:@"slateImageDownload"];
      [config.userContentController addScriptMessageHandler:delegate_ name:@"slatePiP"];
      [config.userContentController addScriptMessageHandler:delegate_ name:[SlateFormRelay messageName]];
      if (!incognito_) {
        [config.userContentController addScriptMessageHandler:delegate_ name:@"slateAutofill"];
      }
    }
    if (getenv("SLATE_DEBUG_CONSOLE")) {
      [config.userContentController addScriptMessageHandler:delegate_ name:@"slateConsole"];
    }
    [config.userContentController addScriptMessageHandler:delegate_ name:@"omidJsSessionService"];
    {
      NSString* extShimJs = [NSString stringWithUTF8String:slate::kExtensionShimsJs];
      WKUserScript* extShimScript = [[WKUserScript alloc] initWithSource:extShimJs
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:NO];
      [config.userContentController addUserScript:extShimScript];
      [config.userContentController addScriptMessageHandler:delegate_ name:@"slateExtShim"];
    }

    NSRect frame = parent.bounds;
    // Slate note: Construct the actual native page view after configuration; this is where a saved logical
    // tab becomes a rendering engine.
    SlateSwipeWebView* swipeWebView = [[SlateSwipeWebView alloc] initWithFrame:frame configuration:config];
    web_view_ = swipeWebView;
    web_view_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    web_view_.allowsMagnification = YES;
    web_view_.magnification = 1.0;
    web_view_.allowsBackForwardNavigationGestures = NO;
    web_view_.navigationDelegate = delegate_;
    web_view_.UIDelegate = delegate_;
    delegate_.webView = web_view_;
    __weak SlateSwipeWebView* weakSwipeView = swipeWebView;
    swipeWebView.onWillNavigate = ^{
      SlateSwipeWebView* strongView = weakSwipeView;
      if (!strongView) return;
      NSAppearance* cur = NSApp.effectiveAppearance;
      const BOOL dark = [cur.name isEqualToString:NSAppearanceNameDarkAqua] ||
        [[cur bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
      NSColor* bg = dark ? [NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0]
                         : [NSColor colorWithCalibratedRed:0.97 green:0.96 blue:0.95 alpha:1.0];
      if (@available(macOS 12.0, *)) strongView.underPageBackgroundColor = bg;
      strongView.layer.backgroundColor = bg.CGColor;
    };
    __weak SlateWebNavigationDelegate* passwordDelegate=delegate_;
    [SlatePasswordServices.shared configure:web_view_ privateTab:incognito_
      accounts:^NSArray<NSDictionary<NSString*,NSString*>*>*(NSURL* origin) {
        SlateWebNavigationDelegate* delegate=passwordDelegate;
        NSMutableArray* rows=[NSMutableArray array];
        if(delegate && !delegate.incognito && delegate.events && delegate.events->credential_accounts_query) {
          auto accounts=delegate.events->credential_accounts_query();
          if(!accounts) return nil;
          for(const auto& account:*accounts) {
            NSString* site=@(account.origin.c_str());
            if(![site containsString:@"://"])site=[@"https://" stringByAppendingString:site];
            [rows addObject:@{@"id":@(account.id.c_str()),@"user":@(account.username.c_str()),@"origin":site}];
          }
        }
        return rows;
      } unlock:^BOOL {
        SlateWebNavigationDelegate* delegate=passwordDelegate;
        return delegate && !delegate.incognito && delegate.events && delegate.events->credential_unlock_requested && delegate.events->credential_unlock_requested();
      } select:^NSDictionary<NSString*,NSString*>*(NSString* identifier,NSURL* origin) {
        SlateWebNavigationDelegate* delegate=passwordDelegate;
        if(!delegate || delegate.incognito || !delegate.events || !delegate.events->credential_selected_query) return nil;
        auto selected=delegate.events->credential_selected_query(identifier.UTF8String,origin.absoluteString.UTF8String);
        return selected ? @{@"user":@(selected->first.c_str()),@"password":@(selected->second.c_str())} : nil;
      }];

    // Keep WKWebView opaque (drawsBackground = YES) so hardware-accelerated video layers
    // (Twitch, YouTube, etc.) never flash the underlying window/layer background white during
    // re-compositing; use underPageBackgroundColor for initial/overscroll background instead.
    web_view_.wantsLayer = YES;

    NSAppearance* curApp = NSApp.effectiveAppearance;
    const BOOL isDarkApp = [curApp.name isEqualToString:NSAppearanceNameDarkAqua] ||
      [[curApp bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor* webBg = isDarkApp ? [NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0] : [NSColor colorWithCalibratedRed:0.97 green:0.96 blue:0.95 alpha:1.0];

    if (@available(macOS 12.0, *)) {
      web_view_.underPageBackgroundColor = webBg;
    }
    web_view_.layer.backgroundColor = webBg.CGColor;
    if (parent) {
      parent.wantsLayer = YES;
      parent.layer.backgroundColor = webBg.CGColor;
    }

    // Observe KVO properties
    [web_view_ addObserver:delegate_ forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    [web_view_ addObserver:delegate_ forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
    [web_view_ addObserver:delegate_ forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:nil];
    [web_view_ addObserver:delegate_ forKeyPath:@"canGoBack" options:NSKeyValueObservingOptionNew context:nil];
    [web_view_ addObserver:delegate_ forKeyPath:@"canGoForward" options:NSKeyValueObservingOptionNew context:nil];

    if (@available(macOS 12.0, *)) {
      [web_view_ addObserver:delegate_ forKeyPath:@"themeColor" options:NSKeyValueObservingOptionNew context:nil];
    }

    [parent addSubview:web_view_];

    if (!popup_configuration && !url.empty() && url != "about:blank") {
      navigate(url);
    }
  }

  ~WebKitEngine() override {
    close();
  }

  void sync_anti_flash_background() {
    if (!web_view_) return;
    NSAppearance* curApp = NSApp.effectiveAppearance;
    const BOOL isDarkApp = [curApp.name isEqualToString:NSAppearanceNameDarkAqua] ||
      [[curApp bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor* webBg = isDarkApp ? [NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.12 alpha:1.0] : [NSColor colorWithCalibratedRed:0.97 green:0.96 blue:0.95 alpha:1.0];
    if (@available(macOS 12.0, *)) {
      web_view_.underPageBackgroundColor = webBg;
    }
    web_view_.layer.backgroundColor = webBg.CGColor;
  }

  void navigate(const std::string& url) override {
    fprintf(stderr, "SLATE_ENGINE_NAVIGATE url=%s web_view_=%p\n", url.c_str(), (__bridge void*)web_view_);
    if (!web_view_) return;
    sync_anti_flash_background();
    if (url.empty() || url == "about:blank") {
      [web_view_ loadHTMLString:@"" baseURL:nil];
      return;
    }
    NSString* nsUrlStr = [NSString stringWithUTF8String:url.c_str()];
    NSURL* nsUrl = [NSURL URLWithString:nsUrlStr];
    if (!nsUrl || !nsUrl.scheme) {
      nsUrl = [NSURL URLWithString:[@"https://" stringByAppendingString:nsUrlStr]];
    }
    if (nsUrl) {
      if (!nsUrl.isFileURL) {
        nsUrl = [SlatePrivacySecurity sanitizedURLForNavigation:nsUrl];
      }
      if (nsUrl.isFileURL) {
        delegate_.typedFileURL=nsUrl;
        NSURL* readAccess = nsUrl;
        [web_view_ loadFileURL:nsUrl allowingReadAccessToURL:readAccess];
      } else {
        [web_view_ loadRequest:[NSURLRequest requestWithURL:nsUrl]];
      }
    }
  }

  void back() override {
    if (web_view_ && web_view_.canGoBack) {
      sync_anti_flash_background();
      [web_view_ goBack];
    }
  }

  void forward() override {
    if (web_view_ && web_view_.canGoForward) {
      sync_anti_flash_background();
      [web_view_ goForward];
    }
  }

  std::vector<HistoryStop> history_stops(bool back) override {
    std::vector<HistoryStop> stops;
    if (!web_view_) return stops;
    NSArray<WKBackForwardListItem*>* items = back ? web_view_.backForwardList.backList : web_view_.backForwardList.forwardList;
    if (!items.count) return stops;
    const NSUInteger maxStops = 12;
    if (back) {
      int idx = 0;
      for (NSInteger i = (NSInteger)items.count - 1; i >= 0 && stops.size() < maxStops; --i, ++idx) {
        WKBackForwardListItem* item = items[(NSUInteger)i];
        HistoryStop stop;
        stop.title = item.title.length ? item.title.UTF8String : (item.URL.host.length ? item.URL.host.UTF8String : "");
        stop.url = item.URL.absoluteString.length ? item.URL.absoluteString.UTF8String : "";
        stop.index = idx;
        stops.push_back(std::move(stop));
      }
    } else {
      for (NSUInteger i = 0; i < items.count && stops.size() < maxStops; ++i) {
        WKBackForwardListItem* item = items[i];
        HistoryStop stop;
        stop.title = item.title.length ? item.title.UTF8String : (item.URL.host.length ? item.URL.host.UTF8String : "");
        stop.url = item.URL.absoluteString.length ? item.URL.absoluteString.UTF8String : "";
        stop.index = (int)i;
        stops.push_back(std::move(stop));
      }
    }
    return stops;
  }

  void go_to_history_stop(bool back, int index) override {
    if (!web_view_ || index < 0) return;
    NSArray<WKBackForwardListItem*>* items = back ? web_view_.backForwardList.backList : web_view_.backForwardList.forwardList;
    if (!items.count) return;
    NSInteger target = back ? ((NSInteger)items.count - 1 - index) : (NSInteger)index;
    if (target < 0 || target >= (NSInteger)items.count) return;
    sync_anti_flash_background();
    [web_view_ goToBackForwardListItem:items[(NSUInteger)target]];
  }

  void wait_for_presentation(double timeout_seconds, std::function<void()> done) override {
    if (!done) return;
    if (web_view_ && [web_view_ isKindOfClass:[SlateSwipeWebView class]]) {
      auto sharedDone = std::make_shared<std::function<void()>>(std::move(done));
      [(SlateSwipeWebView*)web_view_ waitForNextPresentationWithin:timeout_seconds completion:^{
        if (sharedDone && *sharedDone) (*sharedDone)();
      }];
      return;
    }
    done();
  }

  void reload() override {
    if (web_view_) {
      sync_anti_flash_background();
      [web_view_ reload];
    }
  }

  void reload_ignore_cache() override {
    if (web_view_) {
      sync_anti_flash_background();
      [web_view_ reloadFromOrigin];
    }
  }

  void focus() override {
    if (web_view_ && web_view_.window) {
      [web_view_.window makeFirstResponder:web_view_];
    }
  }

  void blur() override {
    if (web_view_ && web_view_.window && web_view_.window.firstResponder == web_view_) {
      [web_view_.window makeFirstResponder:nil];
    }
  }

  void execute_script(const std::string& source) override {
    if (web_view_) {
      [web_view_ evaluateJavaScript:[NSString stringWithUTF8String:source.c_str()]
                  completionHandler:^(id result, NSError* error) {
        if (error) {
          fprintf(stderr, "SLATE_JS_ERROR: %s\n", error.localizedDescription.UTF8String);
        } else if (result) {
          fprintf(stderr, "SLATE_JS_RESULT: %s\n", [NSString stringWithFormat:@"%@", result].UTF8String);
        }
      }];
    }
  }

  void fill_credentials(const std::string& username, const std::string& password) override {
    if (!web_view_ || incognito_ || !SlatePasswordServices.autofillEnabled) return;
    NSURL* url = web_view_.URL;
    if (!url) return;
    NSString* scheme = url.scheme.lowercaseString;
    NSString* host = url.host.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![host isEqualToString:@"localhost"] && ![host isEqualToString:@"127.0.0.1"]) {
      fprintf(stderr, "SLATE_AUTOFILL_REJECT insecure origin: %s\n", url.absoluteString.UTF8String ?: "");
      return;
    }
    NSString* uStr = [NSString stringWithUTF8String:username.c_str()];
    NSString* pStr = [NSString stringWithUTF8String:password.c_str()];
    NSURLComponents* trusted=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    trusted.path=@"";trusted.query=nil;trusted.fragment=nil;
    if(trusted.port.integerValue==443) trusted.port=nil;
    NSData* data=[NSJSONSerialization dataWithJSONObject:@[trusted.string ?: @""] options:0 error:nil];
    NSString* encoded=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString* js=[NSString stringWithFormat:@"(()=>{if(location.origin!==%@ [0])return;%@})();",encoded,
      [SlateFormRelay fillScriptWithUser:uStr password:pStr]];

    if (@available(macOS 11.0, *)) {
      [web_view_ evaluateJavaScript:js inFrame:nil inContentWorld:[WKContentWorld defaultClientWorld] completionHandler:nil];
    } else {
      [web_view_ evaluateJavaScript:js completionHandler:nil];
    }
    fprintf(stderr, "SLATE_AUTOFILL_FILLED\n");
  }

  // Slate note: This adapter currently reports only a limited observation; it does not inspect all
  // DOM/application state. Automatic page destruction must not rely on it.
  void inspect_protection() override {
    if (events_.protection_changed && web_view_) {
      ProtectionSignals signals;
      signals.observed = true;
      signals.loading = false;
      signals.uncertain = false;
      signals.observed_at = std::chrono::steady_clock::now();
      events_.protection_changed(signals);
    }
  }

  void host_geometry_changed() override {
    if (web_view_) {
      if (web_view_.superview) {
        NSRect parentBounds = web_view_.superview.bounds;
        if (!NSEqualRects(web_view_.frame, parentBounds)) {
          web_view_.frame = parentBounds;
        }
      }
      [web_view_ setNeedsLayout:YES];
    }
  }

  void set_zoom(double level) override {
    if (@available(macOS 11.0, *)) {
      if (web_view_) {
        [SlatePasswordServices.shared close:web_view_];
        // Chromium zoom level: level = log(scale) / log(1.2).
        // For WebKit pageZoom, scale is linear (1.0 = 100%).
        double scale = std::pow(1.2, level);
        if (scale <= 0.01 || !std::isfinite(scale)) scale = 1.0;
        web_view_.pageZoom = scale;
      }
    }
  }

  void set_high_refresh_rate(bool fast) override {
    if (web_view_ && web_view_.configuration && web_view_.configuration.preferences) {
      [SlateFrameRate setFeatureValue:!fast inPreferences:web_view_.configuration.preferences];
    }
  }

  void set_occluded(bool occluded) override {
    if (occluded_ == occluded) return;
    occluded_ = occluded;
    if (occluded_ && web_view_) {
      // Drop suspended back/forward page snapshots when hidden to free SPA DOM/JS heaps.
      SEL clearBfcSel = NSSelectorFromString(@"_clearBackForwardCache");
      if ([web_view_ respondsToSelector:clearBfcSel]) {
        reinterpret_cast<void (*)(id, SEL)>(objc_msgSend)(web_view_, clearBfcSel);
      }
    }
  }

  void trim_memory() override {
    if (!web_view_ || closed_) return;
    SEL clearBfcSel = NSSelectorFromString(@"_clearBackForwardCache");
    if ([web_view_ respondsToSelector:clearBfcSel]) {
      reinterpret_cast<void (*)(id, SEL)>(objc_msgSend)(web_view_, clearBfcSel);
    }
    if (@available(macOS 11.0, *)) {
      [web_view_ evaluateJavaScript:@"if (typeof window.__slateTrimPageMemory === 'function') window.__slateTrimPageMemory();"
                           inFrame:nil
                    inContentWorld:[WKContentWorld defaultClientWorld]
                 completionHandler:nil];
    }
  }

  void stop() override {
    if (web_view_) [web_view_ stopLoading];
  }

  // Slate note: Release native handlers and page-owned work through the engine close path, then notify the
  // application.
  void close() override {
    if (!closed_) {
      closed_ = true;
      [delegate_.faviconRequest cancel];
      delegate_.faviconRequest = nil;
      delegate_.events = nullptr;
      delegate_.webView = nil;
      [delegate_.mediaFrames removeAllObjects];
      if (web_view_) {
        @try {
          [web_view_ removeObserver:delegate_ forKeyPath:@"estimatedProgress"];
          [web_view_ removeObserver:delegate_ forKeyPath:@"title"];
          [web_view_ removeObserver:delegate_ forKeyPath:@"URL"];
          [web_view_ removeObserver:delegate_ forKeyPath:@"canGoBack"];
          [web_view_ removeObserver:delegate_ forKeyPath:@"canGoForward"];
          if (@available(macOS 12.0, *)) {
            [web_view_ removeObserver:delegate_ forKeyPath:@"themeColor"];
          }
        } @catch(id e) {}

        if (@available(macOS 12.0, *)) {
          [web_view_ pauseAllMediaPlaybackWithCompletionHandler:nil];
          [web_view_ closeAllMediaPresentationsWithCompletionHandler:nil];
        }
        {
          SEL clearBfcSel = NSSelectorFromString(@"_clearBackForwardCache");
          if ([web_view_ respondsToSelector:clearBfcSel]) {
            reinterpret_cast<void (*)(id, SEL)>(objc_msgSend)(web_view_, clearBfcSel);
          }
        }
        if (@available(macOS 11.0, *)) {
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateWebStore" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:kSlateSwipeScrollMessageName contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateMedia" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateTheme" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateImageDownload" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slatePiP" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:[SlateFormRelay messageName] contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateAutofill" contentWorld:[WKContentWorld defaultClientWorld]];
        } else {
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:kSlateSwipeScrollMessageName];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateMedia"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateTheme"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateImageDownload"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slatePiP"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:[SlateFormRelay messageName]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateAutofill"];
        }
        [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"omidJsSessionService"];
        [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateExtShim"];
        if (getenv("SLATE_DEBUG_CONSOLE")) {
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateConsole"];
        }
        [web_view_ stopLoading];
        [web_view_.configuration.userContentController removeAllUserScripts];
        [web_view_.configuration.userContentController removeAllContentRuleLists];
        [web_view_ removeFromSuperview];
        web_view_.navigationDelegate = nil;
        web_view_.UIDelegate = nil;
        {
          SEL closeSel = NSSelectorFromString(@"_close");
          if ([web_view_ respondsToSelector:closeSel]) {
            reinterpret_cast<void (*)(id, SEL)>(objc_msgSend)(web_view_, closeSel);
          }
        }
        web_view_ = nil;
      }

      delegate_ = nil;
      if (events_.close_ready) events_.close_ready();
      if (events_.closed) events_.closed();
    }
  }

 private:
  EngineEvents events_;
  WKWebView* __strong web_view_ = nil;
  SlateWebNavigationDelegate* __strong delegate_ = nil;
  bool incognito_ = false;
  bool occluded_ = false;
  bool closed_ = false;
};

std::unique_ptr<BrowserEngine> make_webkit_engine(void* native_view, EngineEvents events,
                                                const std::string& url, ShieldController* shields,
                                                bool incognito, void* website_data_store, void* popup_configuration) {
  return std::make_unique<WebKitEngine>(native_view, std::move(events), url, shields, incognito, website_data_store, popup_configuration);
}

void PurgeIncognitoStorage() {
  NSSet* websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
  NSDate* epoch = [NSDate dateWithTimeIntervalSince1970:0];
  [[WKWebsiteDataStore nonPersistentDataStore] removeDataOfTypes:websiteDataTypes
                                                  modifiedSince:epoch
                                              completionHandler:^{}];
}

} // namespace slate

// Add KVO implementation for SlateWebNavigationDelegate
@implementation SlateWebNavigationDelegate (KVO)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
  if (!self.events || !self.webView) return;

  if ([keyPath isEqualToString:@"estimatedProgress"]) {
    if (self.events->loading_changed) {
      self.events->loading_changed(self.webView.loading, self.webView.estimatedProgress);
    }
  } else if ([keyPath isEqualToString:@"title"]) {
    if (self.events->title_changed && self.webView.title) {
      self.events->title_changed(self.webView.title.UTF8String ?: "");
    }
  } else if ([keyPath isEqualToString:@"URL"]) {
    if (self.events->address_changed && self.webView.URL) {
      self.events->address_changed(self.webView.URL.absoluteString.UTF8String ?: "");
    }
  } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"]) {
    if (self.events->navigation_changed) {
      self.events->navigation_changed(self.webView.canGoBack, self.webView.canGoForward);
    }
  } else if ([keyPath isEqualToString:@"themeColor"]) {
    if (@available(macOS 12.0, *)) {
      if (!self.pageThemeReported && self.events->theme_color_changed && self.webView.themeColor) {
        NSColor* color = self.webView.themeColor;
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
        char hex[10];
        snprintf(hex, sizeof(hex), "#%02x%02x%02x", (int)(r * 255.0), (int)(g * 255.0), (int)(b * 255.0));
        self.events->theme_color_changed(hex);
      }
    }
  }
}

@end
