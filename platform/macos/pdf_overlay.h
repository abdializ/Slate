// File purpose: Declares PDF detection and a native HUD for page navigation, zoom, printing, and
// saving.

#pragma once

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <PDFKit/PDFKit.h>

@class SlatePDFOverlayHUD;

// Slate note: The helper locates a PDFKit view inside a WebKit page and manages its native controls.
@interface SlatePDFOverlay : NSObject
+ (PDFView*)findPDFViewInView:(NSView*)view;
+ (BOOL)isPDFWebView:(WKWebView*)webView;
+ (void)checkAndConfigureForWebView:(WKWebView*)webView;
+ (void)removeOverlayFromWebView:(WKWebView*)webView;
@end

@interface SlatePDFOverlayHUD : NSVisualEffectView
@property (nonatomic, weak) WKWebView* webView;
@property (nonatomic, weak) PDFView* pdfView;
@property (nonatomic, strong) NSTextField* pageLabel;
@property (nonatomic, strong) NSButton* prevButton;
@property (nonatomic, strong) NSButton* nextButton;
@property (nonatomic, strong) NSButton* zoomOutButton;
@property (nonatomic, strong) NSButton* zoomInButton;
@property (nonatomic, strong) NSButton* fitButton;
@property (nonatomic, strong) NSButton* previewButton;
@property (nonatomic, strong) NSButton* downloadButton;
@property (nonatomic, strong) NSButton* printButton;
@property (nonatomic, strong) NSTrackingArea* trackingArea;
@property (nonatomic, assign) BOOL isHovered;

- (instancetype)initWithWebView:(WKWebView*)webView pdfView:(PDFView*)pdfView;
- (void)updatePageInfo;
- (void)showHUDAnimated;
- (void)hideHUDAnimated;
- (void)handleMouseMoveInContainer;
@end
