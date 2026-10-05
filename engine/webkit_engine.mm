#import "engine/webkit_engine.h"
#import "engine/webkit_shields.h"
#include "engine/page_theme_js.h"
#include "engine/image_download_js.h"
#include "engine/pip_state.h"
#import "platform/macos/download_manager.h"
#import "platform/macos/form_relay.h"
#import "platform/macos/pdf_overlay.h"
#import <WebKit/WebKit.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <chrono>



static NSString* const kSlateSafariUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";
static NSString* const kSlateChromeUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";

static BOOL IsStreamingOrDrmHost(NSString* host) {
  if (!host.length) return NO;
  NSString* h = host.lowercaseString;
  static NSArray<NSString*>* s_streamingDomains = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_streamingDomains = @[
      // Authentication & Identity Providers (Clean native Safari identity avoids botguard / security blocks)
      @"google.com", @"accounts.google.com", @"gstatic.com", @"googleusercontent.com", @"googleapis.com",
      @"apple.com", @"icloud.com", @"appleid.apple.com",
      @"microsoft.com", @"live.com", @"login.microsoftonline.com", @"office.com",
      @"x.com", @"twitter.com", @"twimg.com",
      // Streaming / DRM (Requires pure Safari for FairPlay DRM)
      @"max.com", @"hbomax.com", @"hbo.com", @"discomax.com", @"h264.io", @"warnermediacdn.com", @"warnermedia.com", @"wbd.com",
      @"netflix.com", @"nflxvideo.net", @"nflximg.net", @"nflxext.com",
      @"disneyplus.com", @"bamgrid.com", @"disney-plus.net",
      @"hulu.com", @"hulustream.com",
      @"peacocktv.com",
      @"paramountplus.com",
      @"primevideo.com", @"amazon.com", @"amazonvideo.com", @"aiv-cdn.net",
      @"spotify.com",
      @"crunchyroll.com",
      @"tubitv.com",
      @"pluto.tv",
      @"fubo.tv",
      @"sling.com",
      @"starz.com",
      @"mgmplus.com",
      @"directv.com",
      @"sho.com", @"showtime.com",
      // Video streaming & Livestreaming (Requires native Safari UA & clean environment)
      @"youtube.com", @"youtu.be", @"ytimg.com", @"googlevideo.com",
      @"twitch.tv", @"kick.com"
    ];
  });
  for (NSString* domain in s_streamingDomains) {
    if ([h isEqualToString:domain] || [h hasSuffix:[@"." stringByAppendingString:domain]]) {
      return YES;
    }
  }
  return NO;
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
      [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (!weakNav || !weakNav.events || !weakNav.events->favicon_changed) return;
        if ([result isKindOfClass:[NSString class]] && [(NSString*)result length] > 0) {
          NSURL* iconUrl = [NSURL URLWithString:(NSString*)result];
          if (iconUrl && iconUrl.scheme.length > 0) {
            NSURLSessionConfiguration* cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            cfg.timeoutIntervalForRequest = 4.0;
            NSURLSession* session = [NSURLSession sessionWithConfiguration:cfg];
            [[session dataTaskWithURL:iconUrl completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
              if (data.length > 0 && !err) {
                NSImage* img = [[NSImage alloc] initWithData:data];
                if (img) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                    if (weakNav && weakNav.events && weakNav.events->favicon_changed) {
                      weakNav.events->favicon_changed(std::string((const char*)data.bytes, data.length));
                    }
                  });
                }
              }
            }] resume];
          }
        }
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
    if (!webView.URL.isFileURL) {
      fprintf(stderr, "SLATE_BLOCKED_LOCAL_FILE_NAV url=%s\n", urlStr.UTF8String ?: "nil");
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    }
  }

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
      !targetUrl.isFileURL) {
    fprintf(stderr, "SLATE_BLOCKED_EXTERNAL_SCHEME scheme=%s url=%s\n",
            scheme.UTF8String ?: "nil", urlStr.UTF8String ?: "nil");
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }

  // Ad & Tracker Blocking: Cancel navigation for third-party ad iframes when shields are active
  if (navigationAction.targetFrame != nil && !navigationAction.targetFrame.isMainFrame) {
    if (slate::WebKitShields::Shared().IsEnabled()) {
      NSString* reqHost = targetUrl.host.lowercaseString;
      if (slate::WebKitShields::Shared().IsAdOrTrackerHost(reqHost)) {
        fprintf(stderr, "SLATE_BLOCKED_AD_SUBFRAME url=%s\n", urlStr.UTF8String ?: "nil");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
      }
    }
  }

  // Dynamically switch User-Agent to Safari on streaming/DRM domains to unlock Apple FairPlay.
  // Strictly guard this to genuine main-frame navigations so tracking beacons, iframes,
  // or popups (targetFrame == nil) do not inadvertently reset the main webView to Chrome.
  if (navigationAction.targetFrame != nil && navigationAction.targetFrame.isMainFrame) {
    slate::WebKitShields::Shared().UpdateControllerForURL(webView.configuration.userContentController, targetUrl);
    if (targetUrl && targetUrl.host.length) {
      NSString* desiredUa = IsStreamingOrDrmHost(targetUrl.host) ? kSlateSafariUserAgent : kSlateChromeUserAgent;
      if (![webView.customUserAgent isEqualToString:desiredUa]) {
        webView.customUserAgent = desiredUa;
        fprintf(stderr, "SLATE_UA_SWITCH host=%s ua=%s\n", targetUrl.host.UTF8String, desiredUa == kSlateSafariUserAgent ? "Safari (FairPlay DRM)" : "Chrome");
      }
    }
  }

  decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
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
  if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)navigationResponse.response;
    NSString *disposition = httpResponse.allHeaderFields[@"Content-Disposition"] ?: httpResponse.allHeaderFields[@"content-disposition"];
    if (disposition && [disposition localizedCaseInsensitiveContainsString:@"attachment"]) {
      fprintf(stderr, "SLATE_DOWNLOAD_ATTACHMENT url=%s disposition=%s\n",
              navigationResponse.response.URL.absoluteString.UTF8String ?: "nil",
              disposition.UTF8String ?: "nil");
      decisionHandler(WKNavigationResponsePolicyDownload);
      return;
    }
  }
  decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download {
  (void)navigationResponse;
  fprintf(stderr, "SLATE_DOWNLOAD_STARTED response url=%s\n",
          download.originalRequest.URL.absoluteString.UTF8String ?: "nil");
  download.delegate = [SlateDownloadManager sharedManager];
  [[SlateDownloadManager sharedManager] registerDownload:download forWebView:webView];
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

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download {
  (void)navigationAction;
  fprintf(stderr, "SLATE_DOWNLOAD_STARTED action url=%s\n",
          download.originalRequest.URL.absoluteString.UTF8String ?: "nil");
  download.delegate = [SlateDownloadManager sharedManager];
  [[SlateDownloadManager sharedManager] registerDownload:download forWebView:webView];
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


// WKUIDelegate: Handle window.open popups
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
  NSURL* url = navigationAction.request.URL;
  NSString* urlStr = url.absoluteString;
  fprintf(stderr, "SLATE_CREATE_WEBVIEW targetFrame=%p url=%s navType=%ld\n",
          navigationAction.targetFrame,
          urlStr.UTF8String ?: "nil",
          (long)navigationAction.navigationType);

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

class WebKitEngine final : public BrowserEngine {
 public:
  WebKitEngine(void* native_view, EngineEvents events, const std::string& url, ShieldController* shields, bool incognito, void* website_data_store = nullptr, void* popup_configuration = nullptr)
      : events_(std::move(events)), incognito_(incognito) {
    NSView* parent = (__bridge NSView*)native_view;

    WKWebViewConfiguration* config = popup_configuration
        ? (__bridge WKWebViewConfiguration*)popup_configuration
        : [[WKWebViewConfiguration alloc] init];
    // Each tab owns its message handlers; retain WebKit's related-page configuration.
    if (popup_configuration) config.userContentController = [[WKUserContentController alloc] init];
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
      config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    } else if (website_data_store) {
      config.websiteDataStore = (__bridge WKWebsiteDataStore*)website_data_store;
    } else {
      config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
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
    [SlateFrameRate applyToPreferences:config.preferences];

    // Attach shields (ad blocking, stream ad defusers, and anti-fingerprinting)
    WebKitShields::Shared().ApplyToUserContentController(config.userContentController, incognito_);

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
    if (!SlateFormRelay.passkeysOffered) {
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
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateMedia"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateTheme"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateImageDownload"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slatePiP"];
      [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:[SlateFormRelay messageName]];
      if (!incognito_) {
        [config.userContentController addScriptMessageHandler:delegate_ contentWorld:[WKContentWorld defaultClientWorld] name:@"slateAutofill"];
      }
    } else {
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

    NSRect frame = parent.bounds;
    web_view_ = [[WKWebView alloc] initWithFrame:frame configuration:config];
    web_view_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    web_view_.allowsMagnification = YES;
    web_view_.magnification = 1.0;
    web_view_.allowsBackForwardNavigationGestures = YES;
    web_view_.navigationDelegate = delegate_;
    web_view_.UIDelegate = delegate_;
    delegate_.webView = web_view_;

    // Anti-Flashbang: Configure WebKit backing canvas to prevent white flashes
    @try {
      [web_view_ setValue:@NO forKey:@"drawsBackground"];
    } @catch (id ex) {}
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

    // Initialize custom User-Agent: Safari on streaming/DRM domains to enable FairPlay, Chrome for desktop web compatibility elsewhere
    NSString* initHost = nil;
    if (!url.empty() && url != "about:blank") {
      NSURL* initialUrl = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
      initHost = initialUrl.host;
    }
    web_view_.customUserAgent = (initHost && IsStreamingOrDrmHost(initHost)) ? kSlateSafariUserAgent : kSlateChromeUserAgent;

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
      if (nsUrl.host.length) {
        NSString* desiredUa = IsStreamingOrDrmHost(nsUrl.host) ? kSlateSafariUserAgent : kSlateChromeUserAgent;
        if (![web_view_.customUserAgent isEqualToString:desiredUa]) {
          web_view_.customUserAgent = desiredUa;
        }
      }
      if (nsUrl.isFileURL) {
        NSURL* readAccess = [nsUrl URLByDeletingLastPathComponent];
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
    if (!web_view_ || incognito_) return;
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
    NSString* js = [SlateFormRelay fillScriptWithUser:uStr password:pStr];

    if (@available(macOS 11.0, *)) {
      [web_view_ evaluateJavaScript:js inFrame:nil inContentWorld:[WKContentWorld defaultClientWorld] completionHandler:nil];
    } else {
      [web_view_ evaluateJavaScript:js completionHandler:nil];
    }
    fprintf(stderr, "SLATE_AUTOFILL_FILLED origin=%s user=%s\n", url.absoluteString.UTF8String ?: "", username.c_str());
  }

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

  void stop() override {
    if (web_view_) [web_view_ stopLoading];
  }

  void close() override {
    if (!closed_) {
      closed_ = true;
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
          [web_view_ closeAllMediaPresentationsWithCompletionHandler:nil];
        }
        if (@available(macOS 11.0, *)) {
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateMedia" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateTheme" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateImageDownload" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slatePiP" contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:[SlateFormRelay messageName] contentWorld:[WKContentWorld defaultClientWorld]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateAutofill" contentWorld:[WKContentWorld defaultClientWorld]];
        } else {
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateMedia"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateTheme"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateImageDownload"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slatePiP"];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:[SlateFormRelay messageName]];
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateAutofill"];
        }
        [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"omidJsSessionService"];
        if (getenv("SLATE_DEBUG_CONSOLE")) {
          [web_view_.configuration.userContentController removeScriptMessageHandlerForName:@"slateConsole"];
        }
        [web_view_ stopLoading];
        [web_view_ removeFromSuperview];
        web_view_.navigationDelegate = nil;
        web_view_.UIDelegate = nil;
        web_view_ = nil;
      }

      if (events_.close_ready) events_.close_ready();
      if (events_.closed) events_.closed();
    }
  }

 private:
  EngineEvents events_;
  WKWebView* __strong web_view_ = nil;
  SlateWebNavigationDelegate* __strong delegate_ = nil;
  bool incognito_ = false;
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
