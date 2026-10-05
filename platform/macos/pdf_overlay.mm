#import "platform/macos/pdf_overlay.h"
#import "platform/macos/download_manager.h"
#import "platform/macos/downloads_panel.h"
#import "platform/macos/plate_components.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

@interface PDFView (SlateAnchorScale)
- (void)setScaleFactor:(CGFloat)scale anchorPoint:(NSPoint)anchorPoint;
@end

static char kPDFOverlayHUDKey;
static char kPDFTrackingAreaKey;
static char kPDFMouseMonitorKey;

@implementation SlatePDFOverlay

+ (PDFView*)findPDFViewInView:(NSView*)view {
 if (!view) return nil;
 if ([view isKindOfClass:[PDFView class]]) {
  return (PDFView*)view;
 }
 for (NSView* sub in view.subviews) {
  PDFView* found = [self findPDFViewInView:sub];
  if (found) return found;
 }
 return nil;
}

+ (BOOL)isPDFWebView:(WKWebView*)webView {
 if (!webView || !webView.URL) return NO;
 NSString* path = webView.URL.path.lowercaseString;
 if ([path hasSuffix:@".pdf"]) return YES;
 PDFView* pdfView = [self findPDFViewInView:webView];
 return pdfView != nil;
}

+ (void)checkAndConfigureForWebView:(WKWebView*)webView {
 if (!webView) return;
 
 PDFView* pdfView = [self findPDFViewInView:webView];
 if (!pdfView) {
  // Check again slightly delayed as WebKit instantiates the PDF plugin asynchronously
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
   PDFView* retryView = [self findPDFViewInView:webView];
   if (retryView) [self configurePDFView:retryView forWebView:webView];
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.40 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
   PDFView* retryView2 = [self findPDFViewInView:webView];
   if (retryView2) [self configurePDFView:retryView2 forWebView:webView];
  });
  return;
 }
 
 [self configurePDFView:pdfView forWebView:webView];
}

+ (void)configureScrollViewsInView:(NSView*)view {
 if (!view) return;
 if ([view isKindOfClass:[NSScrollView class]]) {
  NSScrollView* sv = (NSScrollView*)view;
  sv.hasHorizontalScroller = YES;
  sv.hasVerticalScroller = YES;
  sv.autohidesScrollers = YES;
  sv.horizontalScrollElasticity = NSScrollElasticityAllowed;
  sv.verticalScrollElasticity = NSScrollElasticityAllowed;
  sv.allowsMagnification = YES;
 }
 for (NSView* sub in view.subviews) {
  [self configureScrollViewsInView:sub];
 }
}

+ (void)configurePDFView:(PDFView*)pdfView forWebView:(WKWebView*)webView {
 if (!pdfView || !webView) return;
 
 // Configure Safari-like PDF presentation
 pdfView.autoScales = YES;
 pdfView.displayMode = kPDFDisplaySinglePageContinuous;
 pdfView.displaysPageBreaks = YES;
 pdfView.pageBreakMargins = NSEdgeInsetsMake(8, 0, 8, 0);
 pdfView.backgroundColor = [NSColor colorWithCalibratedRed:0.18 green:0.18 blue:0.20 alpha:1.0];
 if ([pdfView respondsToSelector:@selector(setMinScaleFactor:)]) {
  pdfView.minScaleFactor = 0.1;
 }
 if ([pdfView respondsToSelector:@selector(setMaxScaleFactor:)]) {
  pdfView.maxScaleFactor = 10.0;
 }
 [self configureScrollViewsInView:pdfView];
 [pdfView layoutDocumentView];
 [pdfView setNeedsDisplay:YES];
 
 // Check if HUD already attached
 SlatePDFOverlayHUD* existingHUD = objc_getAssociatedObject(webView, &kPDFOverlayHUDKey);
 if (existingHUD && existingHUD.superview == webView) {
  [existingHUD updatePageInfo];
  return;
 }
 
 // Create and attach HUD
 SlatePDFOverlayHUD* hud = [[SlatePDFOverlayHUD alloc] initWithWebView:webView pdfView:pdfView];
 objc_setAssociatedObject(webView, &kPDFOverlayHUDKey, hud, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [webView addSubview:hud];
 
 [NSLayoutConstraint activateConstraints:@[
  [hud.centerXAnchor constraintEqualToAnchor:webView.centerXAnchor],
  [hud.bottomAnchor constraintEqualToAnchor:webView.bottomAnchor constant:-20],
  [hud.heightAnchor constraintEqualToConstant:38],
  [hud.widthAnchor constraintEqualToConstant:360]
 ]];
 
 [hud updatePageInfo];
 [hud showHUDAnimated];
 
 // Add mouse tracking and trackpad pinch / smart-magnify gesture monitor to container
 id existingMonitor = objc_getAssociatedObject(webView, &kPDFMouseMonitorKey);
 if (existingMonitor) {
  [NSEvent removeMonitor:existingMonitor];
 }
 __weak WKWebView* weakWebView = webView;
 __weak SlatePDFOverlayHUD* weakHUD = hud;
 NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskMagnify | NSEventMaskSmartMagnify;
 id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
  if (!weakWebView || !weakHUD) return event;
  if (event.window == weakWebView.window) {
   NSPoint loc = [weakWebView convertPoint:event.locationInWindow fromView:nil];
   if (NSPointInRect(loc, weakWebView.bounds)) {
    if (event.type == NSEventTypeMouseMoved) {
     [weakHUD handleMouseMoveInContainer];
    } else if (event.type == NSEventTypeMagnify) {
     PDFView* pv = weakHUD.pdfView;
     if (pv && pv.document) {
      CGFloat mag = event.magnification;
      pv.autoScales = NO;
      CGFloat curScale = pv.scaleFactor;
      CGFloat newScale = curScale * (1.0 + mag);
      CGFloat minScale = pv.minScaleFactor > 0.05 ? pv.minScaleFactor : 0.1;
      CGFloat maxScale = pv.maxScaleFactor < 20.0 ? pv.maxScaleFactor : 10.0;
      newScale = fmax(minScale, fmin(maxScale, newScale));
      NSPoint pt = [pv convertPoint:event.locationInWindow fromView:nil];
      if ([pv respondsToSelector:@selector(setScaleFactor:anchorPoint:)]) {
       [pv setScaleFactor:newScale anchorPoint:pt];
      } else {
       pv.scaleFactor = newScale;
      }
      [weakHUD updatePageInfo];
      [weakHUD showHUDAnimated];
      return nil;
     }
    } else if (event.type == NSEventTypeSmartMagnify) {
     PDFView* pv = weakHUD.pdfView;
     if (pv && pv.document) {
      CGFloat fitScale = pv.scaleFactorForSizeToFit;
      if (fitScale <= 0.001) fitScale = 1.0;
      if (fabs(pv.scaleFactor - fitScale) > 0.05 && !pv.autoScales) {
       pv.autoScales = YES;
       [pv layoutDocumentView];
      } else {
       pv.autoScales = NO;
       CGFloat targetScale = fitScale * 1.8;
       NSPoint pt = [pv convertPoint:event.locationInWindow fromView:nil];
       if ([pv respondsToSelector:@selector(setScaleFactor:anchorPoint:)]) {
        [pv setScaleFactor:targetScale anchorPoint:pt];
       } else {
        pv.scaleFactor = targetScale;
       }
      }
      [weakHUD updatePageInfo];
      [weakHUD showHUDAnimated];
      return nil;
     }
    }
   }
  }
  return event;
 }];
 objc_setAssociatedObject(webView, &kPDFMouseMonitorKey, monitor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)removeOverlayFromWebView:(WKWebView*)webView {
 if (!webView) return;
 SlatePDFOverlayHUD* hud = objc_getAssociatedObject(webView, &kPDFOverlayHUDKey);
 if (hud) {
  [hud removeFromSuperview];
  objc_setAssociatedObject(webView, &kPDFOverlayHUDKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 }
 id monitor = objc_getAssociatedObject(webView, &kPDFMouseMonitorKey);
 if (monitor) {
  [NSEvent removeMonitor:monitor];
  objc_setAssociatedObject(webView, &kPDFMouseMonitorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 }
}

@end

@implementation SlatePDFOverlayHUD

- (instancetype)initWithWebView:(WKWebView*)webView pdfView:(PDFView*)pdfView {
 self = [super initWithFrame:NSMakeRect(0, 0, 360, 38)];
 if (self) {
  _webView = webView;
  _pdfView = pdfView;
  
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.wantsLayer = YES;
  self.material = NSVisualEffectMaterialHUDWindow;
  self.state = NSVisualEffectStateActive;
  self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
  self.layer.cornerRadius = 19.0;
  if (@available(macOS 11.0, *)) {
   self.layer.cornerCurve = kCACornerCurveContinuous;
  }
  self.layer.masksToBounds = YES;
  self.layer.borderWidth = 0.5;
  self.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.18].CGColor;
  
  self.shadow = [[NSShadow alloc] init];
  self.shadow.shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.45];
  self.shadow.shadowBlurRadius = 12.0;
  self.shadow.shadowOffset = NSMakeSize(0, -3);
  
  [self setupButtons];
  [self setupTrackingArea];
  
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPageChanged:) name:PDFViewPageChangedNotification object:pdfView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onScaleChanged:) name:PDFViewScaleChangedNotification object:pdfView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDocumentChanged:) name:PDFViewDocumentChangedNotification object:pdfView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPageChanged:) name:PDFViewVisiblePagesChangedNotification object:pdfView];
 }
 return self;
}

- (void)dealloc {
 [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupTrackingArea {
 _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                owner:self userInfo:nil];
 [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
 (void)event;
 self.isHovered = YES;
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideHUDAnimated) object:nil];
 [self showHUDAnimated];
}

- (void)mouseExited:(NSEvent *)event {
 (void)event;
 self.isHovered = NO;
 [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideHUDAnimated) object:nil];
 [self performSelector:@selector(hideHUDAnimated) withObject:nil afterDelay:2.5];
}

- (void)handleMouseMoveInContainer {
 [self showHUDAnimated];
 if (!self.isHovered) {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideHUDAnimated) object:nil];
  [self performSelector:@selector(hideHUDAnimated) withObject:nil afterDelay:3.0];
 }
}

- (void)showHUDAnimated {
 if (self.alphaValue > 0.95) return;
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
  ctx.duration = 0.16;
  ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
  self.animator.alphaValue = 1.0;
 }];
}

- (void)hideHUDAnimated {
 if (self.isHovered) return;
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
  ctx.duration = 0.25;
  ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
  self.animator.alphaValue = 0.0;
 }];
}

- (NSButton*)makeHUDButtonWithSymbol:(NSString*)symbolName action:(SEL)action tooltip:(NSString*)tooltip {
 NSButton* btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 26, 26)];
 btn.bezelStyle = NSBezelStyleInline;
 btn.bordered = NO;
 btn.target = self;
 btn.action = action;
 btn.toolTip = tooltip;
 btn.wantsLayer = YES;
 btn.layer.cornerRadius = 6.0;
 if (@available(macOS 11.0, *)) {
  NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
  btn.image = [[NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip] imageWithSymbolConfiguration:cfg];
 }
 btn.contentTintColor = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
 return btn;
}

- (NSView*)makeSeparator {
 NSBox* sep = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 1, 18)];
 sep.boxType = NSBoxCustom;
 sep.borderWidth = 0;
 sep.fillColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.18];
 return sep;
}

- (void)setupButtons {
 NSStackView* stack = [[NSStackView alloc] initWithFrame:self.bounds];
 stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
 stack.alignment = NSLayoutAttributeCenterY;
 stack.spacing = 4.0;
 stack.edgeInsets = NSEdgeInsetsMake(0, 10, 0, 10);
 stack.translatesAutoresizingMaskIntoConstraints = NO;
 [self addSubview:stack];
 
 [NSLayoutConstraint activateConstraints:@[
  [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
  [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
  [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
  [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
 ]];
 
 // 1. Page Navigation
 _prevButton = [self makeHUDButtonWithSymbol:@"chevron.left" action:@selector(prevPageClicked:) tooltip:@"Previous Page (↑)"];
 _nextButton = [self makeHUDButtonWithSymbol:@"chevron.right" action:@selector(nextPageClicked:) tooltip:@"Next Page (↓)"];
 
 _pageLabel = [NSTextField labelWithString:@"1 / 1"];
 _pageLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightMedium];
 _pageLabel.textColor = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
 _pageLabel.alignment = NSTextAlignmentCenter;
 [_pageLabel.widthAnchor constraintEqualToConstant:58].active = YES;
 
 [stack addArrangedSubview:_prevButton];
 [stack addArrangedSubview:_pageLabel];
 [stack addArrangedSubview:_nextButton];
 
 [stack addArrangedSubview:[self makeSeparator]];
 
 // 2. Zoom Controls
 _zoomOutButton = [self makeHUDButtonWithSymbol:@"minus" action:@selector(zoomOutClicked:) tooltip:@"Zoom Out (⌘-)"];
 _fitButton = [self makeHUDButtonWithSymbol:@"arrow.up.left.and.down.right.and.arrow.up.right.and.down.left" action:@selector(fitClicked:) tooltip:@"Fit to Window / Actual Size (⌘0)"];
 _zoomInButton = [self makeHUDButtonWithSymbol:@"plus" action:@selector(zoomInClicked:) tooltip:@"Zoom In (⌘+)"];
 
 [stack addArrangedSubview:_zoomOutButton];
 [stack addArrangedSubview:_fitButton];
 [stack addArrangedSubview:_zoomInButton];
 
 [stack addArrangedSubview:[self makeSeparator]];
 
 // 3. Action Tools
 _previewButton = [self makeHUDButtonWithSymbol:@"arrow.up.forward.app" action:@selector(openInPreviewClicked:) tooltip:@"Open in Preview"];
 _downloadButton = [self makeHUDButtonWithSymbol:@"arrow.down.circle" action:@selector(downloadClicked:) tooltip:@"Download PDF (⌘S)"];
 _printButton = [self makeHUDButtonWithSymbol:@"printer" action:@selector(printClicked:) tooltip:@"Print PDF… (⌘P)"];
 
 [stack addArrangedSubview:_previewButton];
 [stack addArrangedSubview:_downloadButton];
 [stack addArrangedSubview:_printButton];
}

- (void)onPageChanged:(NSNotification*)note {
 (void)note;
 [self updatePageInfo];
}

- (void)onScaleChanged:(NSNotification*)note {
 (void)note;
 [self updatePageInfo];
}

- (void)onDocumentChanged:(NSNotification*)note {
 (void)note;
 [self updatePageInfo];
}

- (void)updatePageInfo {
 if (!_pdfView || !_pdfView.document) return;
 
 PDFDocument* doc = _pdfView.document;
 NSUInteger total = doc.pageCount;
 PDFPage* current = _pdfView.currentPage;
 NSUInteger idx = current ? [doc indexForPage:current] + 1 : 1;
 
 _pageLabel.stringValue = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)idx, (unsigned long)total];
 _prevButton.enabled = [self.pdfView canGoToPreviousPage];
 _nextButton.enabled = [self.pdfView canGoToNextPage];
}

- (void)prevPageClicked:(id)sender {
 (void)sender;
 if ([_pdfView canGoToPreviousPage]) {
  [_pdfView goToPreviousPage:nil];
  [self updatePageInfo];
 }
}

- (void)nextPageClicked:(id)sender {
 (void)sender;
 if ([_pdfView canGoToNextPage]) {
  [_pdfView goToNextPage:nil];
  [self updatePageInfo];
 }
}

- (void)zoomOutClicked:(id)sender {
 (void)sender;
 _pdfView.autoScales = NO;
 [_pdfView zoomOut:nil];
}

- (void)zoomInClicked:(id)sender {
 (void)sender;
 _pdfView.autoScales = NO;
 [_pdfView zoomIn:nil];
}

- (void)fitClicked:(id)sender {
 (void)sender;
 _pdfView.autoScales = !_pdfView.autoScales;
 if (!_pdfView.autoScales) {
  _pdfView.scaleFactor = 1.0;
 }
 [_pdfView layoutDocumentView];
}

- (void)openInPreviewClicked:(id)sender {
 (void)sender;
 if (!_pdfView || !_pdfView.document) return;
 
 PDFDocument* doc = _pdfView.document;
 NSData* pdfData = [doc dataRepresentation];
 if (!pdfData.length) return;
 
 NSString* fileName = doc.documentURL.lastPathComponent ?: @"document.pdf";
 if (![fileName.lowercaseString hasSuffix:@".pdf"]) fileName = [fileName stringByAppendingString:@".pdf"];
 
 NSString* tempDir = NSTemporaryDirectory();
 NSString* tempPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"Slate-Preview-%lu-%@", (unsigned long)time(NULL), fileName]];
 
 if ([pdfData writeToFile:tempPath atomically:YES]) {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:tempPath]];
 }
}

- (void)downloadClicked:(id)sender {
 (void)sender;
 if (!_pdfView || !_pdfView.document) return;
 
 PDFDocument* doc = _pdfView.document;
 NSData* pdfData = [doc dataRepresentation];
 if (!pdfData.length) return;
 
 NSString* fileName = doc.documentURL.lastPathComponent ?: (_webView.URL.lastPathComponent ?: @"document.pdf");
 if (![fileName.lowercaseString hasSuffix:@".pdf"]) fileName = [fileName stringByAppendingString:@".pdf"];
 
 NSString* destDir = [SlateDownloadManager sharedManager].downloadsDirectory;
 NSURL* destURL = [SlateDownloadManager uniqueDestinationURLForFilename:fileName inDirectory:destDir];
 
 if ([pdfData writeToURL:destURL atomically:YES]) {
  // Reveal in downloads panel
  NSView* btn = nil;
  for (NSWindow* win in [NSApp windows]) {
   id del = win.delegate;
   if (win == _webView.window && [del respondsToSelector:NSSelectorFromString(@"downloadButton")]) {
    btn = [del valueForKey:@"downloadButton"];
    break;
   }
  }
  if (btn) {
   [[SlateDownloadsPanel sharedPanel] showForButton:btn inWindow:_webView.window];
  }
 }
}

- (void)printClicked:(id)sender {
 (void)sender;
 if (!_pdfView) return;
 NSPrintInfo* printInfo = [NSPrintInfo sharedPrintInfo];
 [printInfo setHorizontalPagination:NSPrintingPaginationModeFit];
 [printInfo setVerticalPagination:NSPrintingPaginationModeClip];
 [_pdfView printWithInfo:printInfo autoRotate:YES];
}

@end
