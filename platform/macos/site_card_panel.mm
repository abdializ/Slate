#import "platform/macos/site_card_panel.h"
#import "platform/macos/plate_components.h"
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <SecurityInterface/SFCertificatePanel.h>

@interface SlateDelegate : NSObject
@property int zoomPercent;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)resetZoom:(id)sender;
- (void)printPage:(id)sender;
- (void)sharePage:(id)sender;
@end

static const CGFloat kMenuRowHeight = 26.0;
static const CGFloat kMenuSeparatorHeight = 11.0;
static const CGFloat kMenuPadVertical = 7.0;
static const CGFloat kMenuInsetHorizontal = 6.0;
static const CGFloat kMenuTextInset = 16.0;
static const CGFloat kMenuTrailingInset = 16.0;
static const CGFloat kMenuRuleInset = 14.0;
static const CGFloat kMenuCornerRadius = 14.0;
static const CGFloat kMenuCardWidth = 260.0;

static NSColor* MenuSelectionColor(NSAppearance* appearance) {
  NSColor* accent = [NSColor.controlAccentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: NSColor.systemBlueColor;
  BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  return dark ? [accent blendedColorWithFraction:0.18 ofColor:NSColor.blackColor]
              : [accent blendedColorWithFraction:0.32 ofColor:NSColor.whiteColor];
}

static NSString* CleanSiteHost(NSURL* url) {
  if (!url) return @"";
  if (url.isFileURL) return @"Local File";
  NSString* host = url.host;
  if (host.length) {
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    return host;
  }
  return url.scheme.length ? url.scheme : url.absoluteString;
}

#pragma mark - SlateSiteCardRowView

@interface SlateSiteCardRowView : NSView
@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy) NSString* keyEquivalent;
@property (nonatomic, strong) NSImage* leadingImage;
@property (nonatomic, strong) NSColor* imageColor;
@property (nonatomic, assign) BOOL hasSubmenu;
@property (nonatomic, assign) BOOL isBackRow;
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, strong) NSTrackingArea* trackingArea;
@end

@implementation SlateSiteCardRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
  }
  return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_trackingArea) [self removeTrackingArea:_trackingArea];
  _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                               options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                 owner:self
                                              userInfo:nil];
  [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent*)event {
  _hovered = YES;
  [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent*)event {
  _hovered = NO;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent*)event {
  if (_actionBlock) {
    _actionBlock();
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if (_hovered) {
    NSRect pillRect = NSInsetRect(self.bounds, kMenuInsetHorizontal, 1.0);
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:7.0 yRadius:7.0];
    [MenuSelectionColor(self.effectiveAppearance) setFill];
    [path fill];
  }

  CGFloat startX = kMenuTextInset;

  if (_isBackRow) {
    NSImage* chevron = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:nil];
    if (chevron) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold];
      chevron = [chevron imageWithSymbolConfiguration:cfg];
      NSRect imgRect = NSMakeRect(startX - 2, (NSHeight(self.bounds) - 12)/2.0, 10, 12);
      [chevron drawInRect:imgRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:_hovered ? 1.0 : 0.7];
      startX += 14;
    }
  } else if (_leadingImage) {
    NSRect imgRect = NSMakeRect(startX, (NSHeight(self.bounds) - 15)/2.0, 15, 15);
    NSColor* tint = _hovered ? NSColor.whiteColor : (_imageColor ?: [SlatePalette ink]);
    NSImage* img = _leadingImage;
    if (@available(macOS 12.0, *)) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithHierarchicalColor:tint];
      img = [img imageWithSymbolConfiguration:cfg] ?: img;
      [img drawInRect:imgRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    } else {
      [img drawInRect:imgRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:_hovered ? 1.0 : 0.85];
    }
    startX += 24;
  }

  // Draw title
  if (_title.length) {
    NSDictionary* attrs = @{
      NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: _hovered ? NSColor.whiteColor : [SlatePalette ink]
    };
    NSRect titleRect = NSMakeRect(startX, (NSHeight(self.bounds) - 17)/2.0, NSWidth(self.bounds) - startX - 56, 17);
    [_title drawWithRect:titleRect options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin attributes:attrs];
  }

  // Draw key equivalent
  if (_keyEquivalent.length) {
    NSDictionary* keyAttrs = @{
      NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: _hovered ? [NSColor colorWithWhite:1.0 alpha:0.85] : [SlatePalette muted]
    };
    NSSize keySize = [_keyEquivalent sizeWithAttributes:keyAttrs];
    NSRect keyRect = NSMakeRect(NSWidth(self.bounds) - kMenuTrailingInset - keySize.width, (NSHeight(self.bounds) - keySize.height)/2.0, keySize.width, keySize.height);
    [_keyEquivalent drawInRect:keyRect withAttributes:keyAttrs];
  }

  // Draw submenu chevron
  if (_hasSubmenu) {
    NSImage* chevron = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil];
    if (chevron) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold];
      chevron = [chevron imageWithSymbolConfiguration:cfg];
      NSRect chevRect = NSMakeRect(NSWidth(self.bounds) - kMenuTrailingInset - 8, (NSHeight(self.bounds) - 12)/2.0, 8, 12);
      [chevron drawInRect:chevRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:_hovered ? 1.0 : 0.5];
    }
  }
}

@end

#pragma mark - SlateSiteCardZoomRowView

@interface SlateSiteCardZoomRowView : NSView
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSButton* minusButton;
@property (nonatomic, strong) NSButton* percentButton;
@property (nonatomic, strong) NSButton* plusButton;
@property (nonatomic, copy) void (^onZoomIn)(void);
@property (nonatomic, copy) void (^onZoomOut)(void);
@property (nonatomic, copy) void (^onZoomReset)(void);
- (void)updateZoomPercent:(int)percent;
@end

@implementation SlateSiteCardZoomRowView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _titleLabel = [NSTextField labelWithString:@"Zoom"];
    _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    _titleLabel.textColor = [SlatePalette ink];
    _titleLabel.frame = NSMakeRect(kMenuTextInset, (NSHeight(frameRect) - 17)/2.0, 60, 17);
    [self addSubview:_titleLabel];

    CGFloat rx = kMenuCardWidth - kMenuTrailingInset;

    _plusButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Zoom In"]
                                     target:self action:@selector(plusClicked:)];
    _plusButton.bordered = NO;
    _plusButton.bezelStyle = NSBezelStyleRegularSquare;
    _plusButton.wantsLayer = YES;
    _plusButton.layer.cornerRadius = 10.0;
    _plusButton.contentTintColor = [SlatePalette muted];
    _plusButton.frame = NSMakeRect(rx - 22, (NSHeight(frameRect) - 20)/2.0, 22, 20);
    _plusButton.toolTip = @"Zoom In   ⌘+";
    [self addSubview:_plusButton];
    rx -= 26;

    _percentButton = [NSButton buttonWithTitle:@"100%" target:self action:@selector(percentClicked:)];
    _percentButton.bordered = NO;
    _percentButton.bezelStyle = NSBezelStyleRegularSquare;
    _percentButton.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightMedium];
    _percentButton.contentTintColor = [SlatePalette ink];
    _percentButton.wantsLayer = YES;
    _percentButton.layer.cornerRadius = 10.0;
    if (@available(macOS 11.0, *)) {
      _percentButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _percentButton.layer.backgroundColor = [SlatePalette wash].CGColor;
    _percentButton.layer.borderWidth = 0.5;
    _percentButton.layer.borderColor = [SlatePalette hairline].CGColor;
    _percentButton.frame = NSMakeRect(rx - 46, (NSHeight(frameRect) - 20)/2.0, 46, 20);
    _percentButton.toolTip = @"Actual Size   ⌘0";
    [self addSubview:_percentButton];
    rx -= 50;

    _minusButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Zoom Out"]
                                      target:self action:@selector(minusClicked:)];
    _minusButton.bordered = NO;
    _minusButton.bezelStyle = NSBezelStyleRegularSquare;
    _minusButton.wantsLayer = YES;
    _minusButton.layer.cornerRadius = 10.0;
    _minusButton.contentTintColor = [SlatePalette muted];
    _minusButton.frame = NSMakeRect(rx - 22, (NSHeight(frameRect) - 20)/2.0, 22, 20);
    _minusButton.toolTip = @"Zoom Out   ⌘-";
    [self addSubview:_minusButton];
  }
  return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }

- (void)updateZoomPercent:(int)percent {
  _percentButton.title = [NSString stringWithFormat:@"%d%%", percent];
}

- (void)plusClicked:(id)sender {
  if (_onZoomIn) _onZoomIn();
}

- (void)minusClicked:(id)sender {
  if (_onZoomOut) _onZoomOut();
}

- (void)percentClicked:(id)sender {
  if (_onZoomReset) _onZoomReset();
}

@end

#pragma mark - SlateSiteCardPanel Implementation

@interface SlateSiteCardPanel ()
@property (nonatomic, strong) NSVisualEffectView* glassView;
@property (nonatomic, strong) NSView* containerView;
@property (nonatomic, weak) NSView* currentAnchor;
@property (nonatomic, strong) id mouseMonitor;
@property (nonatomic, assign) BOOL deeper;
@property (nonatomic, strong) NSNumber* certified; // nil = checking, @YES = ok, @NO = invalid
@end

@implementation SlateSiteCardPanel

+ (instancetype)sharedPanel {
  static SlateSiteCardPanel* s_panel = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_panel = [[SlateSiteCardPanel alloc] init];
  });
  return s_panel;
}

+ (BOOL)isShown {
  return [SlateSiteCardPanel sharedPanel].isVisible;
}

+ (void)hide {
  [[SlateSiteCardPanel sharedPanel] hidePanel];
}

- (instancetype)init {
  self = [super initWithContentRect:NSMakeRect(0, 0, kMenuCardWidth, 190)
                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                            backing:NSBackingStoreBuffered
                              defer:NO];
  if (self) {
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = YES;
    self.becomesKeyOnlyIfNeeded = YES;
    self.hidesOnDeactivate = YES;

    _glassView = [[NSVisualEffectView alloc] initWithFrame:self.contentView.bounds];
    _glassView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _glassView.material = NSVisualEffectMaterialMenu;
    _glassView.state = NSVisualEffectStateActive;
    _glassView.wantsLayer = YES;
    _glassView.layer.cornerRadius = kMenuCornerRadius;
    if (@available(macOS 11.0, *)) {
      _glassView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _glassView.layer.masksToBounds = YES;
    _glassView.layer.borderWidth = 0.5;

    _containerView = [[NSView alloc] initWithFrame:_glassView.bounds];
    _containerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_glassView addSubview:_containerView];

    self.contentView = _glassView;

    [self updateBorderColor];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(updateBorderColor)
                                                            name:@"AppleInterfaceThemeChangedNotification"
                                                          object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidResign:)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
  }
  return self;
}

- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }

- (void)appDidResign:(NSNotification*)note {
  [self hidePanel];
}

- (void)updateBorderColor {
  _glassView.layer.borderColor = [SlatePalette hairline].CGColor;
}

- (void)updateWithURL:(NSURL*)url trust:(SecTrustRef)trust secureContent:(BOOL)secure zoom:(int)zoom {
  BOOL urlChanged = ![_pageURL isEqual:url];
  _pageURL = url;
  _serverTrust = trust;
  _hasOnlySecureContent = secure;
  _currentZoomPercent = zoom;

  if (urlChanged) {
    _certified = nil;
  }

  [self certifyIfNeeded];
  [self renderContent];
}

- (void)updateZoomPercent:(int)percent {
  _currentZoomPercent = percent;
  for (NSView* v in _containerView.subviews) {
    if ([v isKindOfClass:[SlateSiteCardZoomRowView class]]) {
      [((SlateSiteCardZoomRowView*)v) updateZoomPercent:percent];
    }
  }
}

- (void)certifyIfNeeded {
  if (_certified == nil && _serverTrust) {
    SecTrustRef trust = _serverTrust;
    CFRetain(trust);
    __weak SlateSiteCardPanel* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      CFErrorRef err = NULL;
      bool ok = SecTrustEvaluateWithError(trust, &err);
      if (err) CFRelease(err);
      CFRelease(trust);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!weakSelf) return;
        weakSelf.certified = @(ok);
        if (weakSelf.isVisible) [weakSelf renderContent];
      });
    });
  }
}

- (CGFloat)calculatedHeight {
  if (_deeper) {
    return kMenuPadVertical + 44 + 22 + 56 + kMenuSeparatorHeight + (_serverTrust ? kMenuRowHeight : 0) + kMenuRowHeight + kMenuPadVertical;
  } else {
    return kMenuPadVertical + 44 + kMenuRowHeight + kMenuRowHeight + kMenuRowHeight + kMenuSeparatorHeight + kMenuRowHeight + kMenuRowHeight + kMenuPadVertical;
  }
}

- (void)renderContent {
  for (NSView* v in [_containerView.subviews copy]) [v removeFromSuperview];

  if (_deeper) {
    [self renderDeeperView];
  } else {
    [self renderFrontView];
  }
}

- (void)renderFrontView {
  CGFloat y = [self calculatedHeight] - kMenuPadVertical;
  __weak SlateSiteCardPanel* weakSelf = self;

  // Header: Clean Host with icon badge inside wash
  y -= 40;
  NSView* headerCard = [[NSView alloc] initWithFrame:NSMakeRect(kMenuInsetHorizontal, y, kMenuCardWidth - 2 * kMenuInsetHorizontal, 40)];
  headerCard.wantsLayer = YES;
  headerCard.layer.cornerRadius = 8.0;
  if (@available(macOS 11.0, *)) {
    headerCard.layer.cornerCurve = kCACornerCurveContinuous;
  }
  headerCard.layer.backgroundColor = [SlatePalette wash].CGColor;
  headerCard.layer.borderWidth = 0.5;
  headerCard.layer.borderColor = [SlatePalette hairline].CGColor;

  NSImageView* badgeIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 20, 20)];
  NSString* scheme = _pageURL.scheme.lowercaseString;
  BOOL isSecure = [scheme isEqualToString:@"https"] && (!_certified || [_certified boolValue]) && _hasOnlySecureContent;
  NSImage* hIcon = [NSImage imageWithSystemSymbolName:isSecure ? @"lock.shield.fill" : (([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) ? @"globe" : @"doc.text") accessibilityDescription:nil];
  badgeIcon.image = hIcon;
  badgeIcon.contentTintColor = isSecure ? [NSColor colorWithCalibratedRed:0.25 green:0.75 blue:0.40 alpha:1.0] : [SlatePalette muted];
  [headerCard addSubview:badgeIcon];

  NSTextField* hostLabel = [NSTextField labelWithString:CleanSiteHost(_pageURL)];
  hostLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  hostLabel.textColor = [SlatePalette ink];
  hostLabel.frame = NSMakeRect(36, 19, NSWidth(headerCard.bounds) - 46, 17);
  [headerCard addSubview:hostLabel];

  NSString* subText = [scheme isEqualToString:@"https"] ? @"Encrypted Connection" : ([scheme isEqualToString:@"http"] ? @"Unencrypted HTTP" : @"Local Resource");
  NSTextField* subLabel = [NSTextField labelWithString:subText];
  subLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
  subLabel.textColor = [SlatePalette muted];
  subLabel.frame = NSMakeRect(36, 4, NSWidth(headerCard.bounds) - 46, 14);
  [headerCard addSubview:subLabel];

  [_containerView addSubview:headerCard];
  y -= 4;

  // Safety Status Row
  y -= kMenuRowHeight;
  SlateSiteCardRowView* safetyRow = [[SlateSiteCardRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
  safetyRow.hasSubmenu = YES;

  if ([scheme isEqualToString:@"https"]) {
    if (_certified && ![_certified boolValue]) {
      safetyRow.leadingImage = [NSImage imageWithSystemSymbolName:@"lock.open" accessibilityDescription:@"Untrusted"];
      safetyRow.imageColor = [NSColor colorWithCalibratedRed:0.92 green:0.26 blue:0.26 alpha:1.0];
      safetyRow.title = @"Connection is not secure";
    } else if (!_hasOnlySecureContent) {
      safetyRow.leadingImage = [NSImage imageWithSystemSymbolName:@"lock.trianglebadge.exclamationmark" accessibilityDescription:@"Mixed Content"];
      safetyRow.imageColor = [NSColor colorWithCalibratedRed:0.95 green:0.60 blue:0.20 alpha:1.0];
      safetyRow.title = @"Parts of this page are not secure";
    } else {
      safetyRow.leadingImage = [NSImage imageWithSystemSymbolName:@"lock.fill" accessibilityDescription:@"Secure"];
      safetyRow.imageColor = [NSColor colorWithCalibratedRed:0.25 green:0.75 blue:0.40 alpha:1.0];
      safetyRow.title = @"Connection is secure";
    }
  } else if ([scheme isEqualToString:@"http"]) {
    safetyRow.leadingImage = [NSImage imageWithSystemSymbolName:@"lock.open" accessibilityDescription:@"Not Secure"];
    safetyRow.imageColor = [NSColor colorWithCalibratedRed:0.92 green:0.26 blue:0.26 alpha:1.0];
    safetyRow.title = @"Connection is not secure";
  } else {
    safetyRow.leadingImage = [NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:@"Local"];
    safetyRow.imageColor = [SlatePalette muted];
    safetyRow.title = @"Local or internal page";
  }

  safetyRow.actionBlock = ^{
    [weakSelf showDeeperViewAnimated:YES];
  };
  [_containerView addSubview:safetyRow];

  // Copy Address Row
  y -= kMenuRowHeight;
  SlateSiteCardRowView* copyRow = [[SlateSiteCardRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
  copyRow.leadingImage = [NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:@"Copy Address"];
  copyRow.imageColor = [SlatePalette muted];
  copyRow.title = @"Copy Address";
  copyRow.keyEquivalent = @"⇧⌘C";
  copyRow.actionBlock = ^{
    [weakSelf copyAddressAction];
  };
  [_containerView addSubview:copyRow];

  // Share Row
  y -= kMenuRowHeight;
  SlateSiteCardRowView* shareRow = [[SlateSiteCardRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
  shareRow.leadingImage = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:@"Share"];
  shareRow.imageColor = [SlatePalette muted];
  shareRow.title = @"Share…";
  shareRow.actionBlock = ^{
    [weakSelf sharePageAction];
  };
  [_containerView addSubview:shareRow];

  // Separator
  y -= kMenuSeparatorHeight;
  NSBox* sep = [[NSBox alloc] initWithFrame:NSMakeRect(kMenuRuleInset, y + 5, kMenuCardWidth - 2 * kMenuRuleInset, 1)];
  sep.boxType = NSBoxSeparator;
  [_containerView addSubview:sep];

  // Print Row
  y -= kMenuRowHeight;
  SlateSiteCardRowView* printRow = [[SlateSiteCardRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
  printRow.leadingImage = [NSImage imageWithSystemSymbolName:@"printer" accessibilityDescription:@"Print"];
  printRow.imageColor = [SlatePalette muted];
  printRow.title = @"Print…";
  printRow.keyEquivalent = @"⌘P";
  printRow.actionBlock = ^{
    [weakSelf printPageAction];
  };
  [_containerView addSubview:printRow];

  // Zoom Row
  y -= kMenuRowHeight;
  SlateSiteCardZoomRowView* zoomRow = [[SlateSiteCardZoomRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
  [zoomRow updateZoomPercent:_currentZoomPercent ?: 100];
  zoomRow.onZoomIn = ^{
    if ([weakSelf.owner respondsToSelector:@selector(zoomIn:)]) {
      [weakSelf.owner zoomIn:nil];
      [weakSelf updateZoomPercent:weakSelf.owner.zoomPercent];
    }
  };
  zoomRow.onZoomOut = ^{
    if ([weakSelf.owner respondsToSelector:@selector(zoomOut:)]) {
      [weakSelf.owner zoomOut:nil];
      [weakSelf updateZoomPercent:weakSelf.owner.zoomPercent];
    }
  };
  zoomRow.onZoomReset = ^{
    if ([weakSelf.owner respondsToSelector:@selector(resetZoom:)]) {
      [weakSelf.owner resetZoom:nil];
      [weakSelf updateZoomPercent:weakSelf.owner.zoomPercent];
    }
  };
  [_containerView addSubview:zoomRow];
}

- (void)renderDeeperView {
  CGFloat y = [self calculatedHeight] - kMenuPadVertical;
  __weak SlateSiteCardPanel* weakSelf = self;

  // Header: Clean Host with icon badge inside wash
  y -= 40;
  NSView* headerCard = [[NSView alloc] initWithFrame:NSMakeRect(kMenuInsetHorizontal, y, kMenuCardWidth - 2 * kMenuInsetHorizontal, 40)];
  headerCard.wantsLayer = YES;
  headerCard.layer.cornerRadius = 8.0;
  if (@available(macOS 11.0, *)) {
    headerCard.layer.cornerCurve = kCACornerCurveContinuous;
  }
  headerCard.layer.backgroundColor = [SlatePalette wash].CGColor;
  headerCard.layer.borderWidth = 0.5;
  headerCard.layer.borderColor = [SlatePalette hairline].CGColor;

  NSImageView* badgeIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 20, 20)];
  NSString* scheme = _pageURL.scheme.lowercaseString;
  BOOL isSecure = [scheme isEqualToString:@"https"] && (!_certified || [_certified boolValue]) && _hasOnlySecureContent;
  NSImage* hIcon = [NSImage imageWithSystemSymbolName:isSecure ? @"lock.shield.fill" : (([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) ? @"globe" : @"doc.text") accessibilityDescription:nil];
  badgeIcon.image = hIcon;
  badgeIcon.contentTintColor = isSecure ? [NSColor colorWithCalibratedRed:0.25 green:0.75 blue:0.40 alpha:1.0] : [SlatePalette muted];
  [headerCard addSubview:badgeIcon];

  NSTextField* hostLabel = [NSTextField labelWithString:CleanSiteHost(_pageURL)];
  hostLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  hostLabel.textColor = [SlatePalette ink];
  hostLabel.frame = NSMakeRect(36, 19, NSWidth(headerCard.bounds) - 46, 17);
  [headerCard addSubview:hostLabel];

  NSString* subText = [scheme isEqualToString:@"https"] ? @"Security Details" : @"Connection Details";
  NSTextField* subLabel = [NSTextField labelWithString:subText];
  subLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
  subLabel.textColor = [SlatePalette muted];
  subLabel.frame = NSMakeRect(36, 4, NSWidth(headerCard.bounds) - 46, 14);
  [headerCard addSubview:subLabel];

  [_containerView addSubview:headerCard];
  y -= 4;

  NSString* titleText = @"Connection is secure";
  NSString* detailText = @"Your information (for example, passwords or credit card numbers) is private when it is sent to this site.";

  if ([scheme isEqualToString:@"https"]) {
    if (_certified && ![_certified boolValue]) {
      titleText = @"Connection is not secure";
      detailText = @"This site's certificate isn't trusted by this Mac. Someone could be reading what you send.";
    } else if (!_hasOnlySecureContent) {
      titleText = @"Parts of this page are not secure";
      detailText = @"The page came privately, but some of what it shows was fetched over plain http, where anyone on the network could read or change it.";
    }
  } else if ([scheme isEqualToString:@"http"]) {
    titleText = @"Connection is not secure";
    detailText = @"Don't enter passwords or credit card numbers here: anything sent to this site can be read on the way.";
  } else {
    titleText = @"Local or internal page";
    detailText = @"This page is loaded from your local device or internal browser system.";
  }

  // Security Title
  y -= 22;
  NSTextField* titleLabel = [NSTextField labelWithString:titleText];
  titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  titleLabel.textColor = [SlatePalette ink];
  titleLabel.frame = NSMakeRect(kMenuTextInset, y, kMenuCardWidth - 2 * kMenuTextInset, 18);
  [_containerView addSubview:titleLabel];

  // Security Detail (multi-line)
  y -= 56;
  NSTextField* detailLabel = [NSTextField wrappingLabelWithString:detailText];
  detailLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  detailLabel.textColor = [SlatePalette muted];
  detailLabel.frame = NSMakeRect(kMenuTextInset, y, kMenuCardWidth - 2 * kMenuTextInset, 52);
  [_containerView addSubview:detailLabel];

  // Separator
  y -= kMenuSeparatorHeight;
  NSBox* sep = [[NSBox alloc] initWithFrame:NSMakeRect(kMenuRuleInset, y + 5, kMenuCardWidth - 2 * kMenuRuleInset, 1)];
  sep.boxType = NSBoxSeparator;
  [_containerView addSubview:sep];

  // Certificate row (if available)
  if (_serverTrust) {
    y -= kMenuRowHeight;
    SlateSiteCardRowView* certRow = [[SlateSiteCardRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
    certRow.leadingImage = [NSImage imageWithSystemSymbolName:@"checkmark.seal" accessibilityDescription:@"Certificate"];
    certRow.imageColor = [SlatePalette muted];
    certRow.title = (_certified && ![_certified boolValue]) ? @"Show Certificate (Not Valid)…" : @"Show Certificate…";
    certRow.actionBlock = ^{
      SecTrustRef trust = weakSelf.serverTrust;
      NSWindow* parent = weakSelf.parentWindow;
      [weakSelf hidePanel];
      if (trust && parent) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [[SFCertificatePanel sharedCertificatePanel] beginSheetForWindow:parent
                                                            modalDelegate:nil
                                                           didEndSelector:nil
                                                              contextInfo:nil
                                                                    trust:trust
                                                                showGroup:NO];
        });
      }
    };
    [_containerView addSubview:certRow];
  }

  // Back row
  y -= kMenuRowHeight;
  SlateSiteCardRowView* backRow = [[SlateSiteCardRowView alloc] initWithFrame:NSMakeRect(0, y, kMenuCardWidth, kMenuRowHeight)];
  backRow.isBackRow = YES;
  backRow.title = @"Back";
  backRow.actionBlock = ^{
    [weakSelf showFrontViewAnimated:YES];
  };
  [_containerView addSubview:backRow];
}

#pragma mark - Transitions & Actions

- (void)showDeeperViewAnimated:(BOOL)animated {
  _deeper = YES;
  [self resizeAndRenderAnimated:animated];
}

- (void)showFrontViewAnimated:(BOOL)animated {
  _deeper = NO;
  [self resizeAndRenderAnimated:animated];
}

- (void)resizeAndRenderAnimated:(BOOL)animated {
  CGFloat newHeight = [self calculatedHeight];
  NSRect frame = self.frame;
  frame.origin.y += (frame.size.height - newHeight);
  frame.size.height = newHeight;

  if (animated) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
      ctx.duration = 0.16;
      ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
      [self.animator setFrame:frame display:YES];
    } completionHandler:^{
      [self renderContent];
    }];
  } else {
    [self setFrame:frame display:YES];
    [self renderContent];
  }
}

- (void)copyAddressAction {
  if (_pageURL.absoluteString.length) {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:_pageURL.absoluteString forType:NSPasteboardTypeString];
  }
  [self hidePanel];
}

- (void)sharePageAction {
  [self hidePanel];
  if ([self.owner respondsToSelector:@selector(sharePage:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.owner sharePage:nil];
    });
  }
}

- (void)printPageAction {
  [self hidePanel];
  if ([self.owner respondsToSelector:@selector(printPage:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.owner printPage:nil];
    });
  }
}

#pragma mark - Presentation & Dismissal

- (void)showForAnchor:(NSView*)anchor inWindow:(NSWindow*)window {
  _currentAnchor = anchor;
  if (!anchor || !window) return;

  _deeper = NO;
  [self renderContent];

  CGFloat height = [self calculatedHeight];
  CGFloat width = kMenuCardWidth;

  NSRect anchorScreen = [anchor.window convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
  CGFloat x = anchorScreen.origin.x - 8.0;
  CGFloat y = anchorScreen.origin.y - height - 6.0;

  NSRect screenFrame = window.screen ? window.screen.visibleFrame : NSScreen.mainScreen.visibleFrame;
  x = MAX(screenFrame.origin.x + 8.0, MIN(x, NSMaxX(screenFrame) - width - 8.0));
  y = MAX(screenFrame.origin.y + 8.0, y);

  [self setFrame:NSMakeRect(x, y, width, height) display:YES];

  if (self.parentWindow != window) {
    if (self.parentWindow) [self.parentWindow removeChildWindow:self];
    [window addChildWindow:self ordered:NSWindowAbove];
  }
  [self orderFront:nil];

  if (_mouseMonitor) {
    [NSEvent removeMonitor:_mouseMonitor];
    _mouseMonitor = nil;
  }
  __weak SlateSiteCardPanel* weakSelf = self;
  _mouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                                        handler:^NSEvent*(NSEvent* event) {
    if (!weakSelf || !weakSelf.isVisible) return event;
    if (event.window == weakSelf) return event;
    if (weakSelf.currentAnchor && event.window == weakSelf.currentAnchor.window) {
      NSPoint loc = [weakSelf.currentAnchor convertPoint:event.locationInWindow fromView:nil];
      if (NSPointInRect(loc, weakSelf.currentAnchor.bounds)) return event;
    }
    [weakSelf hidePanel];
    return event;
  }];
}

- (void)toggleForAnchor:(NSView*)anchor inWindow:(NSWindow*)window {
  if (self.isVisible) {
    [self hidePanel];
  } else {
    [self showForAnchor:anchor inWindow:window];
  }
}

- (void)hidePanel {
  if (!self.isVisible) return;
  if (_mouseMonitor) {
    [NSEvent removeMonitor:_mouseMonitor];
    _mouseMonitor = nil;
  }
  if (self.parentWindow) {
    [self.parentWindow removeChildWindow:self];
  }
  [self orderOut:nil];
}

@end
