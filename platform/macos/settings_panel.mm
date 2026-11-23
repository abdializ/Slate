#import "app_updater.h"
// File purpose: Implements the native minimalist settings window and its connection to browser
// preferences and actions.

#import "platform/macos/settings_panel.h"
#import "platform/macos/passwords_panel.h"
#import "SlatePasswords-Swift.h"
#import "SlateSearch-Swift.h"
#import "spaces_manager.h"
#import "platform/macos/import_dialog.h"
#import "platform/macos/download_manager.h"
#import "platform/macos/specs_panel.h"
#import "platform/macos/privacy_security.h"
#import "platform/macos/extensions_manager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "engine/webkit_shields.h"
#include <algorithm>
#import <QuartzCore/QuartzCore.h>

@interface SlateDelegate : NSObject
@property(strong) SlateSpacesManager* spacesManager;
@property BOOL verticalTabs;
@property BOOL tabsCollapsed;
@property BOOL showBookmarksBar;
@property BOOL pages120Hz;
@property int themeMode;
@property int tabStyle;
@property (copy) NSString* accentId;
@property (copy) NSString* accentHex;
@property (copy) NSString* accentHex2;
@property (strong) NSWindow* window;

- (void)toggleVerticalTabs:(id)sender;
- (void)toggleTabsReveal:(id)sender;
- (void)toggleBookmarksBar:(id)sender;
- (void)togglePages120Hz:(id)sender;
- (void)toggleShields:(id)sender;
- (void)resumeAdBlockSite:(NSString*)site;
- (IBAction)showPasswordsPanel:(id)sender;
- (IBAction)showImportBrowserData:(id)sender;
- (void)applyTabStyle;
- (void)applyPlateChrome;
- (void)persistUiPrefs;
- (void)rebuildAccentMenu;
- (void)refresh;
@end

#pragma mark - Minimalist UI Primitives

@interface SlateSettingsFlippedView : NSView
@end
@implementation SlateSettingsFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface SlateSettingsHairline : NSView
@end
@implementation SlateSettingsHairline
- (instancetype)initWithFrame:(NSRect)frameRect {
  if (self = [super initWithFrame:frameRect]) {
    self.wantsLayer = YES;
  }
  return self;
}
- (void)updateLayer {
  self.layer.backgroundColor = [NSColor.separatorColor colorWithAlphaComponent:0.42].CGColor;
}
- (BOOL)wantsUpdateLayer { return YES; }
@end

@interface SlateSettingsCard : NSView
@end
@implementation SlateSettingsCard
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frameRect {
  if (self = [super initWithFrame:frameRect]) {
    self.wantsLayer = YES;
    self.layer.cornerRadius = 11.0;
    if (@available(macOS 11.0, *)) {
      self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.borderWidth = 1.0;
  }
  return self;
}
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
  BOOL dark = [self.effectiveAppearance.name containsString:@"Dark"];
  self.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:dark ? 0.045 : 0.026].CGColor;
  self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:dark ? 0.45 : 0.35].CGColor;
}
@end

@interface SlateQuietButton : NSButton
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, assign) BOOL primary;
@end
@implementation SlateQuietButton
- (instancetype)initWithFrame:(NSRect)frameRect title:(NSString*)title target:(id)target action:(SEL)action primary:(BOOL)primary {
  if (self = [super initWithFrame:frameRect]) {
    _primary = primary;
    self.title = title ?: @"";
    self.target = target;
    self.action = action;
    self.bordered = NO;
    self.bezelStyle = NSBezelStyleRegularSquare;
    self.font = [NSFont systemFontOfSize:12 weight:primary ? NSFontWeightMedium : NSFontWeightRegular];
    self.wantsLayer = YES;
    self.layer.cornerRadius = 7.0;
    if (@available(macOS 11.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0;
    [self syncStyle];
  }
  return self;
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  for (NSTrackingArea* a in [self.trackingAreas copy]) [self removeTrackingArea:a];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                       owner:self
                                                    userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event { _hovered = YES; [self syncStyle]; }
- (void)mouseExited:(NSEvent*)event { _hovered = NO; [self syncStyle]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; [self syncStyle]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self syncStyle]; }
- (void)syncStyle {
  [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
    CGFloat alpha = self.enabled ? 1.0 : 0.45;
    if (_primary) {
      NSColor* bg = [NSColor.labelColor colorWithAlphaComponent:_hovered ? 0.88 : 0.96];
      self.layer.backgroundColor = [bg colorWithAlphaComponent:bg.alphaComponent * alpha].CGColor;
      self.layer.borderColor = NSColor.clearColor.CGColor;
      NSColor* fg = [NSColor.windowBackgroundColor colorWithAlphaComponent:alpha];
      self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: fg
      }];
    } else {
      CGFloat fill = _hovered ? 0.085 : 0.04;
      self.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:fill].CGColor;
      self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.55].CGColor;
      NSColor* fg = [NSColor.labelColor colorWithAlphaComponent:alpha];
      self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: fg
      }];
    }
  }];
}
@end

@interface SlateSettingsRailButton : NSButton
@property (nonatomic, assign) BOOL selectedItem;
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, copy) NSString* iconName;
@property (nonatomic, copy) NSString* itemTitle;
@end
@implementation SlateSettingsRailButton
- (instancetype)initWithFrame:(NSRect)frameRect pageId:(NSString*)pageId title:(NSString*)title icon:(NSString*)icon {
  if (self = [super initWithFrame:frameRect]) {
    self.identifier = pageId;
    _itemTitle = [title copy];
    _iconName = [icon copy];
    self.bordered = NO;
    self.bezelStyle = NSBezelStyleInline;
    self.alignment = NSTextAlignmentLeft;
    self.imagePosition = NSImageLeading;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 8.0;
    if (@available(macOS 11.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
    [self syncStyle];
  }
  return self;
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  for (NSTrackingArea* a in [self.trackingAreas copy]) [self removeTrackingArea:a];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                       owner:self
                                                    userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event { _hovered = YES; [self syncStyle]; }
- (void)mouseExited:(NSEvent*)event { _hovered = NO; [self syncStyle]; }
- (void)setSelectedItem:(BOOL)selectedItem { _selectedItem = selectedItem; [self syncStyle]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self syncStyle]; }
- (void)syncStyle {
  [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
    NSImage* sym = [NSImage imageWithSystemSymbolName:_iconName accessibilityDescription:nil];
    if (sym) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12.5
                                                                                        weight:_selectedItem ? NSFontWeightMedium : NSFontWeightRegular];
      self.image = [sym imageWithSymbolConfiguration:cfg];
    }
    NSColor* ink = _selectedItem ? NSColor.labelColor : NSColor.secondaryLabelColor;
    self.contentTintColor = ink;
    NSFont* font = [NSFont systemFontOfSize:13 weight:_selectedItem ? NSFontWeightMedium : NSFontWeightRegular];
    self.attributedTitle = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@", _itemTitle ?: @""]
                                                           attributes:@{
      NSFontAttributeName: font,
      NSForegroundColorAttributeName: ink
    }];
    if (_selectedItem) {
      self.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.085].CGColor;
    } else if (_hovered) {
      self.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.04].CGColor;
    } else {
      self.layer.backgroundColor = NSColor.clearColor.CGColor;
    }
  }];
}
@end

@interface SlateThemeSwatchButton : NSButton
@property (nonatomic, copy) NSString* accentKey;
@property (nonatomic, copy) NSString* accentTitle;
@property (nonatomic, strong) NSColor* swatchColor;
@property (nonatomic, assign) BOOL isSelectedSwatch;
@end

@implementation SlateThemeSwatchButton
- (instancetype)initWithFrame:(NSRect)frameRect key:(NSString*)key title:(NSString*)title color:(NSColor*)color {
  if (self = [super initWithFrame:frameRect]) {
    _accentKey = [key copy];
    _accentTitle = [title copy];
    _swatchColor = color;
    self.bordered = NO;
    self.bezelStyle = NSBezelStyleRegularSquare;
    self.title = @"";
    self.toolTip = title;
    self.wantsLayer = YES;
  }
  return self;
}
- (void)setIsSelectedSwatch:(BOOL)sel {
  _isSelectedSwatch = sel;
  [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  NSRect outer = NSInsetRect(self.bounds, 1.5, 1.5);
  if (_isSelectedSwatch) {
    [[NSColor.labelColor colorWithAlphaComponent:0.65] setStroke];
    NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:outer];
    ring.lineWidth = 1.5;
    [ring stroke];
  }
  NSRect dot = NSInsetRect(outer, _isSelectedSwatch ? 3.5 : 2.0, _isSelectedSwatch ? 3.5 : 2.0);
  NSBezierPath* circle = [NSBezierPath bezierPathWithOvalInRect:dot];
  [self.swatchColor setFill];
  [circle fill];
  [[NSColor.labelColor colorWithAlphaComponent:0.12] setStroke];
  circle.lineWidth = 0.75;
  [circle stroke];
}
@end

#pragma mark - Settings Panel

@interface SlateSettingsPanel ()
@property (nonatomic, strong) NSVisualEffectView* railView;
@property (nonatomic, strong) NSView* containerView;
@property (nonatomic, copy) NSString* currentPage;
@property (nonatomic, strong) NSMutableArray<SlateSettingsRailButton*>* railButtons;
@property (nonatomic, strong) NSMutableArray<SlateThemeSwatchButton*>* swatchButtons;
@property (nonatomic, strong) NSTextField* activeAccentLabel;
@property (nonatomic, strong) NSSegmentedControl* appearanceSegment;
@property (nonatomic, strong) NSSegmentedControl* tabStyleSegment;
@property (nonatomic, strong) NSSwitch* switch120Hz;
@property (nonatomic, strong) NSSwitch* switchVerticalTabs;
@property (nonatomic, strong) NSSwitch* switchCollapseTabs;
@property (nonatomic, strong) NSSwitch* switchBookmarks;
@property (nonatomic, strong) NSSwitch* switchShields;
@property (nonatomic, strong) NSSwitch* switchStrictPrivacy;
@property (nonatomic, strong) NSSwitch* switchHttpsOnly;
@property (nonatomic, strong) NSSwitch* switchWebRTCBlock;
@property (nonatomic, strong) NSPopUpButton* vpnModePopup;
@property (nonatomic, strong) NSTextField* vpnHostField;
@property (nonatomic, strong) NSTextField* vpnPortField;
@property (nonatomic, strong) NSTextField* vpnUserField;
@property (nonatomic, strong) NSSecureTextField* vpnPassField;
@property (nonatomic, strong) NSButton* vpnFailClosedCheck;
@property (nonatomic, strong) NSTextField* vpnStatusLabel;
@property (nonatomic, strong) NSView* vpnStatusDot;
@property (nonatomic, strong) NSTextField* downloadPathLabel;
@property (nonatomic, strong) NSTextField* storeInstallField;
@property (nonatomic, strong) NSTextField* storeInstallStatus;
@end

@implementation SlateSettingsPanel

static SlateSettingsPanel* s_sharedSettingsPanel = nil;

+ (instancetype)sharedPanel {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_sharedSettingsPanel = [[SlateSettingsPanel alloc] init];
  });
  return s_sharedSettingsPanel;
}

- (instancetype)init {
  NSRect contentRect = NSMakeRect(0, 0, 740, 540);
  NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
  if (self = [super initWithContentRect:contentRect styleMask:style backing:NSBackingStoreBuffered defer:NO]) {
    self.title = @"Settings";
    self.titlebarAppearsTransparent = YES;
    self.titleVisibility = NSWindowTitleHidden;
    self.backgroundColor = NSColor.windowBackgroundColor;
    self.minSize = NSMakeSize(660, 480);
    self.releasedWhenClosed = NO;
    self.hidesOnDeactivate = NO;
    _currentPage = @"appearance";
    _railButtons = [NSMutableArray array];
    _swatchButtons = [NSMutableArray array];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(extensionsDidChange:) name:SlateExtensionsDidChangeNotification object:nil];
    [self setupLayout];
  }
  return self;
}

- (void)setupLayout {
  NSView* root = self.contentView;
  root.wantsLayer = YES;

  _railView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 188, 540)];
  _railView.translatesAutoresizingMaskIntoConstraints = NO;
  _railView.material = NSVisualEffectMaterialSidebar;
  _railView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
  _railView.state = NSVisualEffectStateFollowsWindowActiveState;
  [root addSubview:_railView];

  SlateSettingsHairline* divider = [[SlateSettingsHairline alloc] initWithFrame:NSZeroRect];
  divider.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:divider];

  _containerView = [[NSView alloc] initWithFrame:NSMakeRect(189, 0, 551, 540)];
  _containerView.translatesAutoresizingMaskIntoConstraints = NO;
  _containerView.wantsLayer = YES;
  [root addSubview:_containerView];

  [NSLayoutConstraint activateConstraints:@[
    [_railView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [_railView.topAnchor constraintEqualToAnchor:root.topAnchor],
    [_railView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    [_railView.widthAnchor constraintEqualToConstant:188],

    [divider.leadingAnchor constraintEqualToAnchor:_railView.trailingAnchor],
    [divider.topAnchor constraintEqualToAnchor:root.topAnchor],
    [divider.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    [divider.widthAnchor constraintEqualToConstant:1],

    [_containerView.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
    [_containerView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    [_containerView.topAnchor constraintEqualToAnchor:root.topAnchor],
    [_containerView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
  ]];

  [self setupRail];
  [self renderCurrentPage];
}

- (void)setupRail {
  for (NSView* v in [_railView.subviews copy]) [v removeFromSuperview];
  [_railButtons removeAllObjects];

  SlateSettingsFlippedView* railDoc = [[SlateSettingsFlippedView alloc] initWithFrame:_railView.bounds];
  railDoc.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [_railView addSubview:railDoc];

  NSTextField* caption = [NSTextField labelWithString:@"SETTINGS"];
  caption.attributedStringValue = [[NSAttributedString alloc] initWithString:@"SETTINGS" attributes:@{
    NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
    NSForegroundColorAttributeName: NSColor.tertiaryLabelColor,
    NSKernAttributeName: @1.1
  }];
  caption.frame = NSMakeRect(18, 48, 150, 14);
  [railDoc addSubview:caption];

  NSArray<NSDictionary*>* items = @[
    @{@"id":@"appearance", @"title":@"Appearance", @"icon":@"circle.lefthalf.filled"},
    @{@"id":@"search",     @"title":@"Search",     @"icon":@"magnifyingglass"},
    @{@"id":@"general",    @"title":@"General",    @"icon":@"slider.horizontal.3"},
    @{@"id":@"tabs",       @"title":@"Tabs",       @"icon":@"rectangle.split.3x1"},
    @{@"id":@"downloads",  @"title":@"Downloads",  @"icon":@"arrow.down.circle"},
    @{@"id":@"passwords",  @"title":@"Passwords",  @"icon":@"key"},
    @{@"id":@"privacy",    @"title":@"Privacy",    @"icon":@"shield"},
    @{@"id":@"extensions", @"title":@"Extensions", @"icon":@"puzzlepiece.extension"},
    @{@"id":@"about",      @"title":@"About",      @"icon":@"info.circle"}
  ];

  CGFloat y = 72;
  for (NSDictionary* it in items) {
    SlateSettingsRailButton* btn = [[SlateSettingsRailButton alloc] initWithFrame:NSMakeRect(10, y, 168, 30)
                                                                           pageId:it[@"id"]
                                                                            title:it[@"title"]
                                                                             icon:it[@"icon"]];
    btn.target = self;
    btn.action = @selector(railButtonClicked:);
    [railDoc addSubview:btn];
    [_railButtons addObject:btn];
    y += 33;
  }

  [self updateRailSelection];
}

- (void)updateRailSelection {
  for (SlateSettingsRailButton* b in _railButtons) {
    b.selectedItem = [b.identifier isEqualToString:_currentPage];
  }
}

- (void)railButtonClicked:(SlateSettingsRailButton*)sender {
  if ([_currentPage isEqualToString:sender.identifier]) return;
  _currentPage = sender.identifier;
  [self updateRailSelection];
  [self renderCurrentPage];
}

- (void)showForSlateDelegate:(SlateDelegate*)delegate {
  [self showForSlateDelegate:delegate selectedPage:@"appearance"];
}

- (void)showForSlateDelegate:(SlateDelegate*)delegate selectedPage:(NSString*)page {
  self.slateDelegate = delegate;
  if (page.length) _currentPage = page;
  [self updateRailSelection];
  [self renderCurrentPage];
  [self updateFromDelegate];
  [self center];
  [self makeKeyAndOrderFront:nil];
}

- (void)updateFromDelegate {
  if (!self.slateDelegate) return;

  if (_appearanceSegment) {
    _appearanceSegment.selectedSegment = MAX(0, MIN(2, self.slateDelegate.themeMode));
  }
  if (_tabStyleSegment) {
    _tabStyleSegment.selectedSegment = (self.slateDelegate.tabStyle == 1) ? 1 : 0;
  }
  [self updateSwatches];

  if (_switch120Hz) _switch120Hz.state = self.slateDelegate.pages120Hz ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchVerticalTabs) _switchVerticalTabs.state = self.slateDelegate.verticalTabs ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchCollapseTabs) _switchCollapseTabs.state = self.slateDelegate.tabsCollapsed ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchBookmarks) _switchBookmarks.state = self.slateDelegate.showBookmarksBar ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchShields) _switchShields.state = slate::WebKitShields::Shared().IsEnabled() ? NSControlStateValueOn : NSControlStateValueOff;

  if (_downloadPathLabel) {
    NSString* dir = [SlateDownloadManager sharedManager].downloadsDirectory ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    _downloadPathLabel.stringValue = [dir stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
  }
}

- (void)updateSwatches {
  NSString* currentAccent = self.slateDelegate.accentId ?: @"slate";
  NSString* activeName = @"Custom";
  for (SlateThemeSwatchButton* b in _swatchButtons) {
    BOOL match = [b.accentKey isEqualToString:currentAccent];
    [b setIsSelectedSwatch:match];
    if (match) activeName = b.accentTitle;
  }
  if (_activeAccentLabel) {
    _activeAccentLabel.stringValue = activeName;
  }
}

#pragma mark - Page Canvas Helpers

- (SlateSettingsFlippedView*)makePageCanvasWithScroll:(NSScrollView**)outScroll {
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:_containerView.bounds];
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  scroll.drawsBackground = NO;
  scroll.borderType = NSNoBorder;
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  CGFloat w = MAX(480.0, NSWidth(_containerView.bounds));
  SlateSettingsFlippedView* doc = [[SlateSettingsFlippedView alloc] initWithFrame:NSMakeRect(0, 0, w, NSHeight(_containerView.bounds))];
  doc.autoresizingMask = NSViewWidthSizable;
  scroll.documentView = doc;
  [_containerView addSubview:scroll];
  if (outScroll) *outScroll = scroll;
  return doc;
}

- (void)finishCanvas:(SlateSettingsFlippedView*)doc scroll:(NSScrollView*)scroll contentHeight:(CGFloat)h {
  CGFloat finalH = MAX(NSHeight(_containerView.bounds), h + 32.0);
  NSRect f = doc.frame;
  f.size.height = finalH;
  doc.frame = f;
  [scroll.contentView scrollToPoint:NSMakePoint(0, 0)];
  [scroll reflectScrolledClipView:scroll.contentView];
}

- (CGFloat)addPageHeaderTo:(NSView*)doc title:(NSString*)title subtitle:(NSString*)subtitle {
  NSTextField* h = [NSTextField labelWithString:title];
  h.font = [NSFont systemFontOfSize:19 weight:NSFontWeightSemibold];
  h.textColor = NSColor.labelColor;
  h.frame = NSMakeRect(32, 34, NSWidth(doc.bounds) - 64, 24);
  h.autoresizingMask = NSViewWidthSizable;
  [doc addSubview:h];

  if (subtitle.length) {
    NSTextField* s = [NSTextField labelWithString:subtitle];
    s.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    s.textColor = NSColor.secondaryLabelColor;
    s.frame = NSMakeRect(32, 60, NSWidth(doc.bounds) - 64, 16);
    s.autoresizingMask = NSViewWidthSizable;
    [doc addSubview:s];
    return 94.0;
  }
  return 74.0;
}

- (CGFloat)addSectionCaptionTo:(NSView*)doc y:(CGFloat)y text:(NSString*)text {
  NSTextField* cap = [NSTextField labelWithString:text];
  cap.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
  cap.textColor = NSColor.secondaryLabelColor;
  cap.frame = NSMakeRect(34, y, NSWidth(doc.bounds) - 68, 15);
  cap.autoresizingMask = NSViewWidthSizable;
  [doc addSubview:cap];
  return y + 22.0;
}

- (SlateSettingsCard*)addCardTo:(NSView*)doc y:(CGFloat)y height:(CGFloat)h {
  SlateSettingsCard* card = [[SlateSettingsCard alloc] initWithFrame:NSMakeRect(32, y, NSWidth(doc.bounds) - 64, h)];
  card.autoresizingMask = NSViewWidthSizable;
  [doc addSubview:card];
  return card;
}

- (void)addDividerToCard:(SlateSettingsCard*)card y:(CGFloat)y {
  SlateSettingsHairline* line = [[SlateSettingsHairline alloc] initWithFrame:NSMakeRect(16, y, NSWidth(card.bounds) - 32, 1)];
  line.autoresizingMask = NSViewWidthSizable;
  [card addSubview:line];
}

- (NSSwitch*)addSwitchRowToCard:(SlateSettingsCard*)card y:(CGFloat)y title:(NSString*)title subtitle:(NSString*)sub on:(BOOL)on action:(SEL)action {
  CGFloat w = NSWidth(card.bounds);
  NSTextField* t = [NSTextField labelWithString:title];
  t.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  t.textColor = NSColor.labelColor;
  t.frame = NSMakeRect(16, y + 10, w - 82, 17);
  t.autoresizingMask = NSViewWidthSizable;
  [card addSubview:t];

  NSTextField* s = [NSTextField labelWithString:sub];
  s.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
  s.textColor = NSColor.secondaryLabelColor;
  s.lineBreakMode = NSLineBreakByTruncatingTail;
  s.frame = NSMakeRect(16, y + 29, w - 82, 15);
  s.autoresizingMask = NSViewWidthSizable;
  [card addSubview:s];

  NSSwitch* sw = [[NSSwitch alloc] initWithFrame:NSMakeRect(w - 52, y + 16, 36, 22)];
  sw.controlSize = NSControlSizeSmall;
  sw.state = on ? NSControlStateValueOn : NSControlStateValueOff;
  sw.target = self;
  sw.action = action;
  sw.autoresizingMask = NSViewMinXMargin;
  [card addSubview:sw];
  return sw;
}

- (SlateQuietButton*)addActionRowToCard:(SlateSettingsCard*)card y:(CGFloat)y title:(NSString*)title subtitle:(NSString*)sub buttonTitle:(NSString*)btnTitle buttonWidth:(CGFloat)btnW action:(SEL)action subtitleOut:(NSTextField**)subOut {
  CGFloat w = NSWidth(card.bounds);
  NSTextField* t = [NSTextField labelWithString:title];
  t.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  t.textColor = NSColor.labelColor;
  t.frame = NSMakeRect(16, y + 10, w - btnW - 44, 17);
  t.autoresizingMask = NSViewWidthSizable;
  [card addSubview:t];

  NSTextField* s = [NSTextField labelWithString:sub];
  s.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
  s.textColor = NSColor.secondaryLabelColor;
  s.lineBreakMode = NSLineBreakByTruncatingMiddle;
  s.frame = NSMakeRect(16, y + 29, w - btnW - 44, 15);
  s.autoresizingMask = NSViewWidthSizable;
  [card addSubview:s];
  if (subOut) *subOut = s;

  SlateQuietButton* btn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(w - btnW - 16, y + 14, btnW, 26)
                                                            title:btnTitle
                                                           target:self
                                                           action:action
                                                          primary:NO];
  btn.autoresizingMask = NSViewMinXMargin;
  [card addSubview:btn];
  return btn;
}

#pragma mark - Page Routing

- (void)renderCurrentPage {
  for (NSView* v in [_containerView.subviews copy]) [v removeFromSuperview];
  [_swatchButtons removeAllObjects];
  _activeAccentLabel = nil;
  _appearanceSegment = nil;
  _tabStyleSegment = nil;
  _switch120Hz = nil;
  _switchVerticalTabs = nil;
  _switchCollapseTabs = nil;
  _switchBookmarks = nil;
  _switchShields = nil;
  _switchStrictPrivacy = nil;
  _switchHttpsOnly = nil;
  _switchWebRTCBlock = nil;
  _vpnModePopup = nil;
  _vpnHostField = nil;
  _vpnPortField = nil;
  _vpnUserField = nil;
  _vpnPassField = nil;
  _vpnFailClosedCheck = nil;
  _vpnStatusLabel = nil;
  _vpnStatusDot = nil;
  _downloadPathLabel = nil;

  if ([_currentPage isEqualToString:@"appearance"]) {
    [self renderAppearancePage];
  } else if ([_currentPage isEqualToString:@"search"]) {
    NSView* search = [SlateSearchServices settingsViewWithProfile:self.slateDelegate.spacesManager.currentSpaceId ?: @"default"];
    search.frame = NSInsetRect(_containerView.bounds, 8, 12);
    search.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_containerView addSubview:search];
  } else if ([_currentPage isEqualToString:@"general"]) {
    [self renderGeneralPage];
  } else if ([_currentPage isEqualToString:@"tabs"]) {
    [self renderTabsPage];
  } else if ([_currentPage isEqualToString:@"downloads"]) {
    [self renderDownloadsPage];
  } else if ([_currentPage isEqualToString:@"passwords"]) {
    [self renderPasswordsPage];
  } else if ([_currentPage isEqualToString:@"privacy"]) {
    [self renderPrivacyPage];
  } else if ([_currentPage isEqualToString:@"extensions"]) {
    [self renderExtensionsPage];
  } else if ([_currentPage isEqualToString:@"about"]) {
    [self renderAboutPage];
  }
  [self updateFromDelegate];
}

#pragma mark - Appearance Page

- (void)renderAppearancePage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"Appearance" subtitle:@"Quiet chrome, adaptive light & dark modes, and subtle accents."];

  // Mode Card
  y = [self addSectionCaptionTo:doc y:y text:@"Theme"];
  SlateSettingsCard* modeCard = [self addCardTo:doc y:y height:58];
  CGFloat cw = NSWidth(modeCard.bounds);

  NSTextField* modeTitle = [NSTextField labelWithString:@"Appearance Mode"];
  modeTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  modeTitle.frame = NSMakeRect(16, 11, cw - 240, 17);
  modeTitle.autoresizingMask = NSViewWidthSizable;
  [modeCard addSubview:modeTitle];

  NSTextField* modeSub = [NSTextField labelWithString:@"Match macOS or lock to Light or Dark"];
  modeSub.font = [NSFont systemFontOfSize:11.5];
  modeSub.textColor = NSColor.secondaryLabelColor;
  modeSub.frame = NSMakeRect(16, 30, cw - 240, 15);
  modeSub.autoresizingMask = NSViewWidthSizable;
  [modeCard addSubview:modeSub];

  _appearanceSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"System", @"Light", @"Dark"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(appearanceSegmentChanged:)];
  _appearanceSegment.controlSize = NSControlSizeSmall;
  _appearanceSegment.frame = NSMakeRect(cw - 210, 17, 194, 24);
  _appearanceSegment.autoresizingMask = NSViewMinXMargin;
  [modeCard addSubview:_appearanceSegment];

  // Accent Swatches Card
  y += 58 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Accent"];
  SlateSettingsCard* accentCard = [self addCardTo:doc y:y height:102];
  cw = NSWidth(accentCard.bounds);

  NSTextField* accentTitle = [NSTextField labelWithString:@"Browser Tint"];
  accentTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  accentTitle.frame = NSMakeRect(16, 12, 160, 17);
  [accentCard addSubview:accentTitle];

  _activeAccentLabel = [NSTextField labelWithString:@"Slate"];
  _activeAccentLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
  _activeAccentLabel.textColor = NSColor.secondaryLabelColor;
  _activeAccentLabel.alignment = NSTextAlignmentRight;
  _activeAccentLabel.frame = NSMakeRect(cw - 140, 13, 124, 15);
  _activeAccentLabel.autoresizingMask = NSViewMinXMargin;
  [accentCard addSubview:_activeAccentLabel];

  NSArray* palette = @[
    @{@"id":@"slate",    @"title":@"Slate",      @"color":[NSColor colorWithSRGBRed:0.39 green:0.45 blue:0.55 alpha:1]},
    @{@"id":@"graphite", @"title":@"Graphite",   @"color":[NSColor colorWithSRGBRed:0.32 green:0.32 blue:0.36 alpha:1]},
    @{@"id":@"sand",     @"title":@"Warm Stone", @"color":[NSColor colorWithSRGBRed:0.66 green:0.60 blue:0.52 alpha:1]},
    @{@"id":@"sky",      @"title":@"Mist Blue",  @"color":[NSColor colorWithSRGBRed:0.29 green:0.51 blue:0.72 alpha:1]},
    @{@"id":@"sage",     @"title":@"Eucalyptus", @"color":[NSColor colorWithSRGBRed:0.36 green:0.55 blue:0.45 alpha:1]},
    @{@"id":@"rose",     @"title":@"Blush",      @"color":[NSColor colorWithSRGBRed:0.72 green:0.42 blue:0.49 alpha:1]},
    @{@"id":@"mauve",    @"title":@"Iris",       @"color":[NSColor colorWithSRGBRed:0.49 green:0.42 blue:0.62 alpha:1]},
    @{@"id":@"coral",    @"title":@"Terracotta", @"color":[NSColor colorWithSRGBRed:0.76 green:0.45 blue:0.38 alpha:1]},
    @{@"id":@"peach",    @"title":@"Apricot",    @"color":[NSColor colorWithSRGBRed:0.79 green:0.54 blue:0.39 alpha:1]},
    @{@"id":@"marigold", @"title":@"Ochre",      @"color":[NSColor colorWithSRGBRed:0.77 green:0.64 blue:0.33 alpha:1]}
  ];

  CGFloat sx = 16;
  for (NSDictionary* item in palette) {
    SlateThemeSwatchButton* b = [[SlateThemeSwatchButton alloc] initWithFrame:NSMakeRect(sx, 48, 28, 28)
                                                                          key:item[@"id"]
                                                                        title:item[@"title"]
                                                                        color:item[@"color"]];
    b.target = self;
    b.action = @selector(swatchClicked:);
    [accentCard addSubview:b];
    [_swatchButtons addObject:b];
    sx += 34;
  }

  SlateQuietButton* customBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(cw - 92, 49, 76, 26)
                                                                  title:@"Custom…"
                                                                 target:self
                                                                 action:@selector(chooseCustomColor:)
                                                                primary:NO];
  customBtn.autoresizingMask = NSViewMinXMargin;
  [accentCard addSubview:customBtn];

  [self finishCanvas:doc scroll:scroll contentHeight:y + 102];
}

- (void)appearanceSegmentChanged:(NSSegmentedControl*)sender {
  if (!self.slateDelegate) return;
  self.slateDelegate.themeMode = (int)sender.selectedSegment;
  [self.slateDelegate applyPlateChrome];
  [self.slateDelegate persistUiPrefs];
}

- (void)swatchClicked:(SlateThemeSwatchButton*)sender {
  if (!self.slateDelegate) return;
  self.slateDelegate.accentId = sender.accentKey;
  self.slateDelegate.accentHex = @"";
  self.slateDelegate.accentHex2 = @"";
  [self.slateDelegate applyPlateChrome];
  [self.slateDelegate persistUiPrefs];
  [self.slateDelegate rebuildAccentMenu];
  [self updateSwatches];
}

- (void)chooseCustomColor:(id)sender {
  NSColorPanel* panel = [NSColorPanel sharedColorPanel];
  panel.target = self;
  panel.action = @selector(customColorChanged:);
  [panel makeKeyAndOrderFront:nil];
}

- (void)customColorChanged:(NSColorPanel*)panel {
  if (!self.slateDelegate) return;
  NSColor* col = [panel.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: panel.color;
  NSString* hex = [NSString stringWithFormat:@"#%02X%02X%02X",
                   (int)(col.redComponent * 255),
                   (int)(col.greenComponent * 255),
                   (int)(col.blueComponent * 255)];
  self.slateDelegate.accentId = @"custom";
  self.slateDelegate.accentHex = hex;
  [self.slateDelegate applyPlateChrome];
  [self.slateDelegate persistUiPrefs];
  [self.slateDelegate rebuildAccentMenu];
  [self updateSwatches];
}

#pragma mark - General Page

- (void)renderGeneralPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"General" subtitle:@"Performance and system defaults."];

  y = [self addSectionCaptionTo:doc y:y text:@"Browser"];
  SlateSettingsCard* card = [self addCardTo:doc y:y height:111];
  _switch120Hz = [self addSwitchRowToCard:card y:0
                                    title:@"Pages at 120 Hz"
                                 subtitle:@"Render scrolling and animations up to 120 fps on ProMotion displays"
                                       on:self.slateDelegate.pages120Hz
                                   action:@selector(toggle120HzClicked:)];
  [self addDividerToCard:card y:55];
  [self addActionRowToCard:card y:56
                     title:@"Default Web Browser"
                  subtitle:@"Open web links from other apps in Slate"
               buttonTitle:@"Set Default"
               buttonWidth:92
                    action:@selector(makeDefaultClicked:)
               subtitleOut:nil];

  [self finishCanvas:doc scroll:scroll contentHeight:y + 111];
}

- (void)toggle120HzClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate togglePages120Hz:sender];
}

- (void)makeDefaultClicked:(id)sender {
  CFStringRef bundleId = (__bridge CFStringRef)[[NSBundle mainBundle] bundleIdentifier];
  if (bundleId) {
    LSSetDefaultHandlerForURLScheme(CFSTR("http"), bundleId);
    LSSetDefaultHandlerForURLScheme(CFSTR("https"), bundleId);
  }
}

#pragma mark - Tabs Page

- (void)renderTabsPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"Tabs" subtitle:@"Layout, sidebar behavior, and bookmarks bar."];

  y = [self addSectionCaptionTo:doc y:y text:@"Style"];
  SlateSettingsCard* styleCard = [self addCardTo:doc y:y height:58];
  CGFloat cw = NSWidth(styleCard.bounds);

  NSTextField* stTitle = [NSTextField labelWithString:@"Tab Shape"];
  stTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  stTitle.frame = NSMakeRect(16, 11, cw - 230, 17);
  stTitle.autoresizingMask = NSViewWidthSizable;
  [styleCard addSubview:stTitle];

  NSTextField* stSub = [NSTextField labelWithString:@"Floating capsules or classic tabs"];
  stSub.font = [NSFont systemFontOfSize:11.5];
  stSub.textColor = NSColor.secondaryLabelColor;
  stSub.frame = NSMakeRect(16, 30, cw - 230, 15);
  stSub.autoresizingMask = NSViewWidthSizable;
  [styleCard addSubview:stSub];

  _tabStyleSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Pill", @"Regular"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self
                                                             action:@selector(tabStyleSegmentChanged:)];
  _tabStyleSegment.controlSize = NSControlSizeSmall;
  _tabStyleSegment.frame = NSMakeRect(cw - 166, 17, 150, 24);
  _tabStyleSegment.autoresizingMask = NSViewMinXMargin;
  [styleCard addSubview:_tabStyleSegment];

  y += 58 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Layout"];
  SlateSettingsCard* layoutCard = [self addCardTo:doc y:y height:167];
  _switchVerticalTabs = [self addSwitchRowToCard:layoutCard y:0
                                           title:@"Sidebar Tabs"
                                        subtitle:@"Show tabs vertically along the left edge (⇧⌘S)"
                                              on:self.slateDelegate.verticalTabs
                                          action:@selector(toggleVerticalTabsClicked:)];
  [self addDividerToCard:layoutCard y:55];
  _switchCollapseTabs = [self addSwitchRowToCard:layoutCard y:56
                                           title:@"Fold Tabs Away"
                                        subtitle:@"Hide the tab strip until you hover the edge (⌘S)"
                                              on:self.slateDelegate.tabsCollapsed
                                          action:@selector(toggleCollapseTabsClicked:)];
  [self addDividerToCard:layoutCard y:111];
  _switchBookmarks = [self addSwitchRowToCard:layoutCard y:112
                                        title:@"Bookmarks Bar"
                                     subtitle:@"Show bookmarks below the address bar (⇧⌘B)"
                                           on:self.slateDelegate.showBookmarksBar
                                       action:@selector(toggleBookmarksClicked:)];

  [self finishCanvas:doc scroll:scroll contentHeight:y + 167];
}

- (void)tabStyleSegmentChanged:(NSSegmentedControl*)sender {
  if (!self.slateDelegate) return;
  self.slateDelegate.tabStyle = (int)sender.selectedSegment;
  if ([self.slateDelegate respondsToSelector:@selector(applyTabStyle)]) {
    [self.slateDelegate applyTabStyle];
  }
  [self.slateDelegate persistUiPrefs];
}

- (void)toggleVerticalTabsClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate toggleVerticalTabs:sender];
}
- (void)toggleCollapseTabsClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate toggleTabsReveal:sender];
}
- (void)toggleBookmarksClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate toggleBookmarksBar:sender];
}

#pragma mark - Downloads Page

- (void)renderDownloadsPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"Downloads" subtitle:@"Where Slate saves downloaded files."];

  y = [self addSectionCaptionTo:doc y:y text:@"Destination"];
  SlateSettingsCard* card = [self addCardTo:doc y:y height:56];
  NSTextField* pathSub = nil;
  [self addActionRowToCard:card y:0
                     title:@"Download Folder"
                  subtitle:@"~/Downloads"
               buttonTitle:@"Change…"
               buttonWidth:84
                    action:@selector(changeDownloadFolder:)
               subtitleOut:&pathSub];
  _downloadPathLabel = pathSub;

  [self finishCanvas:doc scroll:scroll contentHeight:y + 56];
}

- (void)changeDownloadFolder:(id)sender {
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.canCreateDirectories = YES;
  panel.prompt = @"Select";
  [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK && panel.URL.path.length) {
      [SlateDownloadManager sharedManager].downloadsDirectory = panel.URL.path;
      [self updateFromDelegate];
    }
  }];
}

#pragma mark - Passwords Page

- (void)renderPasswordsPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"Passwords" subtitle:@"Encrypted locally in your macOS Keychain."];

  y = [self addSectionCaptionTo:doc y:y text:@"Vault"];
  SlateSettingsCard* card = [self addCardTo:doc y:y height:111];
  [self addActionRowToCard:card y:0
                     title:@"Saved Passwords"
                  subtitle:@"View, edit, and generate strong passwords"
               buttonTitle:@"Open Vault"
               buttonWidth:94
                    action:@selector(openPasswordsClicked:)
               subtitleOut:nil];
  [self addDividerToCard:card y:55];
  [self addActionRowToCard:card y:56
                     title:@"Import Browser Data"
                  subtitle:@"Import logins, bookmarks, and history from other browsers"
               buttonTitle:@"Import…"
               buttonWidth:84
                    action:@selector(importDataClicked:)
               subtitleOut:nil];

  y += 111 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Autofill"];
  SlateSettingsCard* servicesCard = [self addCardTo:doc y:y height:228];
  NSView* services = [SlatePasswordServices.shared settingsView];
  services.frame = NSMakeRect(8, 6, NSWidth(servicesCard.bounds) - 16, 216);
  services.autoresizingMask = NSViewWidthSizable;
  [servicesCard addSubview:services];

  [self finishCanvas:doc scroll:scroll contentHeight:y + 228];
}

- (void)openPasswordsClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate showPasswordsPanel:sender];
}
- (void)importDataClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate showImportBrowserData:sender];
}

#pragma mark - Privacy Page

- (void)renderPrivacyPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"Privacy" subtitle:@"Content blocking, tracking defense, and private network routing."];

  // Protection Card
  y = [self addSectionCaptionTo:doc y:y text:@"Protection"];
  SlateSettingsCard* shieldCard = [self addCardTo:doc y:y height:223];
  _switchShields = [self addSwitchRowToCard:shieldCard y:0
                                      title:@"Ad & Tracker Blocker"
                                   subtitle:@"Native WebKit filter (EasyList, EasyPrivacy, and Slate rules)"
                                         on:slate::WebKitShields::Shared().IsEnabled()
                                     action:@selector(toggleShieldsClicked:)];
  [self addDividerToCard:shieldCard y:55];
  _switchStrictPrivacy = [self addSwitchRowToCard:shieldCard y:56
                                            title:@"Strict Tracking Protection"
                                         subtitle:@"Strip URL tracking parameters and send GPC & Do Not Track"
                                               on:[SlatePrivacySecurity strictTrackingProtectionEnabled]
                                           action:@selector(toggleStrictPrivacyClicked:)];
  [self addDividerToCard:shieldCard y:111];
  _switchHttpsOnly = [self addSwitchRowToCard:shieldCard y:112
                                        title:@"HTTPS-Only Mode"
                                     subtitle:@"Upgrade insecure http:// requests to https:// automatically"
                                           on:[SlatePrivacySecurity httpsOnlyEnabled]
                                       action:@selector(toggleHttpsOnlyClicked:)];
  [self addDividerToCard:shieldCard y:167];
  _switchWebRTCBlock = [self addSwitchRowToCard:shieldCard y:168
                                          title:@"Block WebRTC IP Leaks in Incognito"
                                       subtitle:@"Disable RTCPeerConnection in Private tabs"
                                             on:[SlatePrivacySecurity blockWebRTCInIncognito]
                                         action:@selector(toggleWebRTCBlockClicked:)];

  // Incognito VPN / Proxy Tunnel Card
  y += 223 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Incognito Tunnel"];
  SlateSettingsCard* vpnCard = [self addCardTo:doc y:y height:234];
  CGFloat cw = NSWidth(vpnCard.bounds);

  NSTextField* vpnTitle = [NSTextField labelWithString:@"VPN / Proxy Routing"];
  vpnTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  vpnTitle.frame = NSMakeRect(16, 12, cw - 32, 17);
  vpnTitle.autoresizingMask = NSViewWidthSizable;
  [vpnCard addSubview:vpnTitle];

  NSTextField* vpnSub = [NSTextField labelWithString:@"Route Private tabs through Tor or a SOCKS5 / HTTP proxy"];
  vpnSub.font = [NSFont systemFontOfSize:11.5];
  vpnSub.textColor = NSColor.secondaryLabelColor;
  vpnSub.frame = NSMakeRect(16, 30, cw - 32, 15);
  vpnSub.autoresizingMask = NSViewWidthSizable;
  [vpnCard addSubview:vpnSub];

  NSPopUpButton* modePop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 54, cw - 32, 25) pullsDown:NO];
  modePop.controlSize = NSControlSizeSmall;
  modePop.autoresizingMask = NSViewWidthSizable;
  [modePop addItemsWithTitles:@[
    @"Off (Direct)",
    @"Tor Local Tunnel (SOCKS5 127.0.0.1:9050)",
    @"Custom SOCKS5 VPN / Proxy",
    @"Custom HTTP CONNECT Proxy"
  ]];
  [modePop selectItemAtIndex:(NSInteger)[SlatePrivacySecurity incognitoProxyMode]];
  modePop.target = self;
  modePop.action = @selector(vpnModeChanged:);
  self.vpnModePopup = modePop;
  [vpnCard addSubview:modePop];

  self.vpnHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 88, cw - 134, 24)];
  self.vpnHostField.controlSize = NSControlSizeSmall;
  self.vpnHostField.font = [NSFont systemFontOfSize:12];
  self.vpnHostField.placeholderString = @"Host (e.g. 10.64.0.1)";
  self.vpnHostField.stringValue = [SlatePrivacySecurity incognitoProxyHost];
  self.vpnHostField.autoresizingMask = NSViewWidthSizable;
  [vpnCard addSubview:self.vpnHostField];

  self.vpnPortField = [[NSTextField alloc] initWithFrame:NSMakeRect(cw - 110, 88, 94, 24)];
  self.vpnPortField.controlSize = NSControlSizeSmall;
  self.vpnPortField.font = [NSFont systemFontOfSize:12];
  self.vpnPortField.placeholderString = @"Port";
  NSInteger portVal = [SlatePrivacySecurity incognitoProxyPort];
  self.vpnPortField.stringValue = portVal > 0 ? [NSString stringWithFormat:@"%ld", (long)portVal] : @"";
  self.vpnPortField.autoresizingMask = NSViewMinXMargin;
  [vpnCard addSubview:self.vpnPortField];

  CGFloat half = floor((cw - 40) / 2.0);
  self.vpnUserField = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 120, half, 24)];
  self.vpnUserField.controlSize = NSControlSizeSmall;
  self.vpnUserField.font = [NSFont systemFontOfSize:12];
  self.vpnUserField.placeholderString = @"Username (optional)";
  self.vpnUserField.stringValue = [SlatePrivacySecurity incognitoProxyUsername];
  self.vpnUserField.autoresizingMask = NSViewWidthSizable | NSViewMaxXMargin;
  [vpnCard addSubview:self.vpnUserField];

  self.vpnPassField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(24 + half, 120, cw - 40 - half, 24)];
  self.vpnPassField.controlSize = NSControlSizeSmall;
  self.vpnPassField.font = [NSFont systemFontOfSize:12];
  self.vpnPassField.placeholderString = @"Password (Keychain)";
  self.vpnPassField.stringValue = [SlatePrivacySecurity incognitoProxyPassword];
  self.vpnPassField.autoresizingMask = NSViewWidthSizable | NSViewMinXMargin;
  [vpnCard addSubview:self.vpnPassField];

  self.vpnFailClosedCheck = [NSButton checkboxWithTitle:@"Kill Switch: block Incognito if tunnel is unreachable" target:nil action:nil];
  self.vpnFailClosedCheck.controlSize = NSControlSizeSmall;
  self.vpnFailClosedCheck.state = [SlatePrivacySecurity incognitoProxyFailClosed] ? NSControlStateValueOn : NSControlStateValueOff;
  self.vpnFailClosedCheck.font = [NSFont systemFontOfSize:11.5];
  self.vpnFailClosedCheck.frame = NSMakeRect(16, 152, cw - 32, 18);
  self.vpnFailClosedCheck.autoresizingMask = NSViewWidthSizable;
  [vpnCard addSubview:self.vpnFailClosedCheck];

  SlateQuietButton* saveVpn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(16, 180, 92, 26)
                                                                title:@"Save"
                                                               target:self
                                                               action:@selector(saveVpnClicked:)
                                                              primary:YES];
  [vpnCard addSubview:saveVpn];

  SlateQuietButton* testVpn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(116, 180, 96, 26)
                                                                title:@"Test Tunnel"
                                                               target:self
                                                               action:@selector(testVpnClicked:)
                                                              primary:NO];
  [vpnCard addSubview:testVpn];

  BOOL tunnelOn = [SlatePrivacySecurity isIncognitoTunnelActive];
  self.vpnStatusDot = [[NSView alloc] initWithFrame:NSMakeRect(18, 214, 6, 6)];
  self.vpnStatusDot.wantsLayer = YES;
  self.vpnStatusDot.layer.cornerRadius = 3;
  self.vpnStatusDot.layer.backgroundColor = (tunnelOn ? NSColor.labelColor : NSColor.tertiaryLabelColor).CGColor;
  [vpnCard addSubview:self.vpnStatusDot];

  self.vpnStatusLabel = [NSTextField labelWithString:tunnelOn ? @"Active on new Incognito tabs" : @"Tunnel off"];
  self.vpnStatusLabel.font = [NSFont systemFontOfSize:11];
  self.vpnStatusLabel.textColor = NSColor.secondaryLabelColor;
  self.vpnStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.vpnStatusLabel.frame = NSMakeRect(30, 210, cw - 46, 14);
  self.vpnStatusLabel.autoresizingMask = NSViewWidthSizable;
  [vpnCard addSubview:self.vpnStatusLabel];
  [self updateVpnFieldStates];

  // Allowed Sites Card
  auto sites = slate::WebKitShields::Shared().DisabledSites();
  std::sort(sites.begin(), sites.end());
  y += 234 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Allowed Sites"];
  CGFloat sitesH = sites.empty() ? 48.0 : (CGFloat)(sites.size() * 44.0);
  SlateSettingsCard* sitesCard = [self addCardTo:doc y:y height:sitesH];
  cw = NSWidth(sitesCard.bounds);
  if (sites.empty()) {
    NSTextField* empty = [NSTextField labelWithString:@"No exceptions — all sites are protected."];
    empty.font = [NSFont systemFontOfSize:12];
    empty.textColor = NSColor.secondaryLabelColor;
    empty.frame = NSMakeRect(16, 16, cw - 32, 16);
    empty.autoresizingMask = NSViewWidthSizable;
    [sitesCard addSubview:empty];
  } else {
    CGFloat ry = 0;
    for (size_t i = 0; i < sites.size(); ++i) {
      NSString* name = [NSString stringWithUTF8String:sites[i].c_str()];
      NSTextField* label = [NSTextField labelWithString:name];
      label.font = [NSFont systemFontOfSize:12.5];
      label.frame = NSMakeRect(16, ry + 14, cw - 110, 16);
      label.lineBreakMode = NSLineBreakByTruncatingMiddle;
      label.autoresizingMask = NSViewWidthSizable;
      [sitesCard addSubview:label];

      SlateQuietButton* remove = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(cw - 84, ry + 9, 68, 26)
                                                                   title:@"Remove"
                                                                  target:self
                                                                  action:@selector(removeAllowedSiteClicked:)
                                                                 primary:NO];
      remove.identifier = name;
      remove.autoresizingMask = NSViewMinXMargin;
      [sitesCard addSubview:remove];
      if (i + 1 < sites.size()) [self addDividerToCard:sitesCard y:ry + 43];
      ry += 44;
    }
  }

  [self finishCanvas:doc scroll:scroll contentHeight:y + sitesH];
}

- (void)updateVpnFieldStates {
  SlateProxyMode mode = (SlateProxyMode)self.vpnModePopup.indexOfSelectedItem;
  BOOL custom = (mode == SlateProxyModeSOCKS5 || mode == SlateProxyModeHTTP);
  self.vpnHostField.enabled = custom;
  self.vpnPortField.enabled = custom;
  self.vpnUserField.enabled = custom;
  self.vpnPassField.enabled = custom;
  self.vpnFailClosedCheck.enabled = (mode != SlateProxyModeOff);
  if (mode == SlateProxyModeTor) {
    self.vpnHostField.stringValue = @"127.0.0.1";
    self.vpnPortField.stringValue = @"9050";
  }
}

- (void)vpnModeChanged:(id)sender {
  (void)sender;
  [self updateVpnFieldStates];
}

- (void)saveVpnClicked:(id)sender {
  (void)sender;
  SlateProxyMode mode = (SlateProxyMode)self.vpnModePopup.indexOfSelectedItem;
  [SlatePrivacySecurity setIncognitoProxyMode:mode];
  if (mode == SlateProxyModeSOCKS5 || mode == SlateProxyModeHTTP) {
    [SlatePrivacySecurity setIncognitoProxyHost:self.vpnHostField.stringValue];
    [SlatePrivacySecurity setIncognitoProxyPort:self.vpnPortField.integerValue];
    [SlatePrivacySecurity setIncognitoProxyUsername:self.vpnUserField.stringValue];
    [SlatePrivacySecurity setIncognitoProxyPassword:self.vpnPassField.stringValue];
  } else if (mode == SlateProxyModeOff) {
    [SlatePrivacySecurity setIncognitoProxyPassword:@""];
  }
  [SlatePrivacySecurity setIncognitoProxyFailClosed:(self.vpnFailClosedCheck.state == NSControlStateValueOn)];
  BOOL active = [SlatePrivacySecurity isIncognitoTunnelActive];
  self.vpnStatusLabel.stringValue = active ? @"Saved — active on new Incognito tabs" : (mode == SlateProxyModeOff ? @"Tunnel off" : @"Enter a valid host and port");
  self.vpnStatusDot.layer.backgroundColor = (active ? NSColor.labelColor : NSColor.tertiaryLabelColor).CGColor;
}

- (void)testVpnClicked:(id)sender {
  [self saveVpnClicked:sender];
  self.vpnStatusLabel.stringValue = @"Testing tunnel…";
  __weak SlateSettingsPanel* weakSelf = self;
  [SlatePrivacySecurity testIncognitoTunnelWithCompletion:^(BOOL reachable, NSString* message) {
    SlateSettingsPanel* strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.vpnStatusLabel) return;
    strongSelf.vpnStatusLabel.stringValue = message;
    strongSelf.vpnStatusDot.layer.backgroundColor = (reachable ? NSColor.labelColor : NSColor.tertiaryLabelColor).CGColor;
  }];
}

- (void)toggleStrictPrivacyClicked:(NSSwitch*)sender {
  [SlatePrivacySecurity setStrictTrackingProtectionEnabled:(sender.state == NSControlStateValueOn)];
}
- (void)toggleHttpsOnlyClicked:(NSSwitch*)sender {
  [SlatePrivacySecurity setHttpsOnlyEnabled:(sender.state == NSControlStateValueOn)];
}
- (void)toggleWebRTCBlockClicked:(NSSwitch*)sender {
  [SlatePrivacySecurity setBlockWebRTCInIncognito:(sender.state == NSControlStateValueOn)];
}
- (void)removeAllowedSiteClicked:(NSButton*)sender {
  [self.slateDelegate resumeAdBlockSite:sender.identifier];
  [self renderCurrentPage];
}
- (void)toggleShieldsClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate toggleShields:sender];
}

#pragma mark - Extensions Page

- (void)extensionsDidChange:(NSNotification*)note {
  (void)note;
  if ([_currentPage isEqualToString:@"extensions"] && self.isVisible) {
    [self renderCurrentPage];
  }
}

- (void)renderExtensionsPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = [self addPageHeaderTo:doc title:@"Extensions" subtitle:@"Run Chrome WebExtensions natively on macOS WebKit."];

  if (![SlateExtensionsManager isSupported]) {
    SlateSettingsCard* unavail = [self addCardTo:doc y:y height:64];
    NSTextField* msg = [NSTextField wrappingLabelWithString:@"Native WebExtensions require macOS 15.4 or later."];
    msg.font = [NSFont systemFontOfSize:12.5];
    msg.textColor = NSColor.secondaryLabelColor;
    msg.frame = NSMakeRect(16, 22, NSWidth(unavail.bounds) - 32, 20);
    msg.autoresizingMask = NSViewWidthSizable;
    [unavail addSubview:msg];
    [self finishCanvas:doc scroll:scroll contentHeight:y + 64];
    return;
  }

  // Chrome Web Store Card
  y = [self addSectionCaptionTo:doc y:y text:@"Chrome Web Store"];
  SlateSettingsCard* storeCard = [self addCardTo:doc y:y height:114];
  CGFloat cw = NSWidth(storeCard.bounds);

  NSTextField* storeField = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 14, cw - 122, 26)];
  storeField.controlSize = NSControlSizeSmall;
  storeField.font = [NSFont systemFontOfSize:12];
  storeField.placeholderString = @"Paste Chrome Web Store URL or 32-char extension ID…";
  storeField.autoresizingMask = NSViewWidthSizable;
  self.storeInstallField = storeField;
  [storeCard addSubview:storeField];

  SlateQuietButton* storeInstallBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(cw - 98, 14, 82, 26)
                                                                        title:@"Install"
                                                                       target:self
                                                                       action:@selector(installFromStoreFieldClicked:)
                                                                      primary:YES];
  storeInstallBtn.autoresizingMask = NSViewMinXMargin;
  [storeCard addSubview:storeInstallBtn];

  NSTextField* storeStatus = [NSTextField labelWithString:@"Or browse chromewebstore.google.com and click “Add to Slate” on any extension."];
  storeStatus.font = [NSFont systemFontOfSize:11];
  storeStatus.textColor = NSColor.secondaryLabelColor;
  storeStatus.lineBreakMode = NSLineBreakByTruncatingTail;
  storeStatus.frame = NSMakeRect(16, 46, cw - 32, 15);
  storeStatus.autoresizingMask = NSViewWidthSizable;
  self.storeInstallStatus = storeStatus;
  [storeCard addSubview:storeStatus];

  [self addDividerToCard:storeCard y:68];

  SlateQuietButton* browseStoreBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(16, 78, 154, 26)
                                                                       title:@"Open Chrome Web Store"
                                                                      target:self
                                                                      action:@selector(openChromeWebStoreClicked:)
                                                                     primary:NO];
  [storeCard addSubview:browseStoreBtn];

  SlateQuietButton* crxBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(178, 78, 134, 26)
                                                               title:@"Install .crx / .zip…"
                                                              target:self
                                                              action:@selector(installExtensionArchiveClicked:)
                                                             primary:NO];
  [storeCard addSubview:crxBtn];

  SlateQuietButton* unpackedBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(320, 78, 120, 26)
                                                                    title:@"Load Unpacked…"
                                                                   target:self
                                                                   action:@selector(loadUnpackedExtensionClicked:)
                                                                  primary:NO];
  [storeCard addSubview:unpackedBtn];

  // Installed Extensions Card
  y += 114 + 20;
  NSArray<SlateExtensionRecord*>* list = [SlateExtensionsManager sharedManager].extensions;
  y = [self addSectionCaptionTo:doc y:y text:[NSString stringWithFormat:@"Installed (%lu)", (unsigned long)list.count]];

  if (list.count == 0) {
    SlateSettingsCard* emptyCard = [self addCardTo:doc y:y height:68];
    NSTextField* empty = [NSTextField wrappingLabelWithString:@"No extensions installed yet. Choose a Chrome .crx / .zip package or an unpacked extension folder containing manifest.json."];
    empty.font = [NSFont systemFontOfSize:12];
    empty.textColor = NSColor.secondaryLabelColor;
    empty.frame = NSMakeRect(16, 18, NSWidth(emptyCard.bounds) - 32, 34);
    empty.autoresizingMask = NSViewWidthSizable;
    [emptyCard addSubview:empty];
    [self finishCanvas:doc scroll:scroll contentHeight:y + 68];
    return;
  }

  const CGFloat rowH = 82.0;
  SlateSettingsCard* listCard = [self addCardTo:doc y:y height:list.count * rowH];
  cw = NSWidth(listCard.bounds);
  CGFloat ry = 0;
  for (NSUInteger i = 0; i < list.count; ++i) {
    SlateExtensionRecord* rec = list[i];

    NSImageView* iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(16, ry + 16, 28, 28)];
    iconView.image = rec.icon ?: [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:nil];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [listCard addSubview:iconView];

    NSString* headerStr = rec.version.length ? [NSString stringWithFormat:@"%@  %@", rec.name ?: @"Extension", rec.version] : (rec.name ?: @"Extension");
    NSTextField* nameField = [NSTextField labelWithString:headerStr];
    nameField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    nameField.textColor = NSColor.labelColor;
    nameField.lineBreakMode = NSLineBreakByTruncatingTail;
    nameField.frame = NSMakeRect(54, ry + 12, cw - 120, 17);
    nameField.autoresizingMask = NSViewWidthSizable;
    [listCard addSubview:nameField];

    NSString* descStr = rec.loadError.length ? rec.loadError : (rec.summary.length ? rec.summary : @"Chrome WebExtension");
    NSTextField* descField = [NSTextField labelWithString:descStr];
    descField.font = [NSFont systemFontOfSize:11.5];
    descField.textColor = NSColor.secondaryLabelColor;
    descField.lineBreakMode = NSLineBreakByTruncatingTail;
    descField.frame = NSMakeRect(54, ry + 30, cw - 120, 15);
    descField.autoresizingMask = NSViewWidthSizable;
    [listCard addSubview:descField];

    NSSwitch* sw = [[NSSwitch alloc] initWithFrame:NSMakeRect(cw - 52, ry + 16, 36, 22)];
    sw.controlSize = NSControlSizeSmall;
    sw.state = rec.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    sw.identifier = rec.identifier;
    sw.target = self;
    sw.action = @selector(toggleExtensionEnabled:);
    sw.autoresizingMask = NSViewMinXMargin;
    [listCard addSubview:sw];

    NSButton* privCheck = [NSButton checkboxWithTitle:@"Allow in Incognito" target:self action:@selector(toggleExtensionPrivate:)];
    privCheck.controlSize = NSControlSizeSmall;
    privCheck.font = [NSFont systemFontOfSize:11];
    privCheck.state = rec.allowInPrivate ? NSControlStateValueOn : NSControlStateValueOff;
    privCheck.identifier = rec.identifier;
    privCheck.frame = NSMakeRect(54, ry + 52, 140, 18);
    [listCard addSubview:privCheck];

    CGFloat btnX = cw - 76;
    SlateQuietButton* removeBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(btnX, ry + 49, 60, 22)
                                                                    title:@"Remove"
                                                                   target:self
                                                                   action:@selector(removeExtensionClicked:)
                                                                  primary:NO];
    removeBtn.identifier = rec.identifier;
    removeBtn.autoresizingMask = NSViewMinXMargin;
    [listCard addSubview:removeBtn];

    if (rec.hasOptionsPage && rec.enabled) {
      SlateQuietButton* optBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(btnX - 68, ry + 49, 62, 22)
                                                                   title:@"Options"
                                                                  target:self
                                                                  action:@selector(openExtensionOptions:)
                                                                 primary:NO];
      optBtn.identifier = rec.identifier;
      optBtn.autoresizingMask = NSViewMinXMargin;
      [listCard addSubview:optBtn];
    }

    if (i + 1 < list.count) [self addDividerToCard:listCard y:ry + rowH - 1];
    ry += rowH;
  }

  [self finishCanvas:doc scroll:scroll contentHeight:y + list.count * rowH];
}

- (void)showExtensionInstallError:(NSError*)error {
  if (!error) return;
  NSAlert* alert = [[NSAlert alloc] init];
  alert.messageText = @"Could not install extension";
  alert.informativeText = error.localizedDescription ?: @"Invalid Chrome extension package.";
  [alert addButtonWithTitle:@"OK"];
  [alert beginSheetModalForWindow:self completionHandler:nil];
}

- (void)installFromStoreFieldClicked:(id)sender {
  (void)sender;
  NSString* input = self.storeInstallField.stringValue ?: @"";
  NSString* storeId = [SlateExtensionsManager chromeStoreExtensionIdFromInput:input];
  if (!storeId.length) {
    self.storeInstallStatus.stringValue = @"Enter a valid Chrome Web Store URL or 32-character extension ID.";
    return;
  }
  self.storeInstallStatus.stringValue = @"Downloading from Chrome Web Store…";
  __weak SlateSettingsPanel* weakSelf = self;
  [[SlateExtensionsManager sharedManager] installFromChromeWebStoreId:storeId completion:^(SlateExtensionRecord* rec, NSError* err) {
    SlateSettingsPanel* strongSelf = weakSelf;
    if (!strongSelf) return;
    if (err || !rec) {
      strongSelf.storeInstallStatus.stringValue = err.localizedDescription ?: @"Could not install extension.";
    } else {
      strongSelf.storeInstallField.stringValue = @"";
      strongSelf.storeInstallStatus.stringValue = [NSString stringWithFormat:@"Installed %@", rec.name ?: @"extension"];
      [strongSelf renderCurrentPage];
    }
  }];
}

- (void)openChromeWebStoreClicked:(id)sender {
  (void)sender;
  id<SlateExtensionHostDelegate> host = [SlateExtensionsManager sharedManager].hostDelegate;
  if (host) {
    [host extensionHostOpenURL:[NSURL URLWithString:@"https://chromewebstore.google.com/"] incognito:NO activate:YES];
    [self.slateDelegate.window makeKeyAndOrderFront:nil];
  }
}

- (void)installExtensionArchiveClicked:(id)sender {
  (void)sender;
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = NO;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"Install";
  if (@available(macOS 11.0, *)) {
    UTType* crxType = [UTType typeWithFilenameExtension:@"crx"];
    NSMutableArray<UTType*>* types = [NSMutableArray arrayWithObject:UTTypeZIP];
    if (crxType) [types addObject:crxType];
    panel.allowedContentTypes = types;
  }
  [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
    if (result != NSModalResponseOK || !panel.URL) return;
    [[SlateExtensionsManager sharedManager] installFromArchiveURL:panel.URL completion:^(SlateExtensionRecord* rec, NSError* err) {
      (void)rec;
      if (err) [self showExtensionInstallError:err];
      else [self renderCurrentPage];
    }];
  }];
}

- (void)loadUnpackedExtensionClicked:(id)sender {
  (void)sender;
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"Load";
  [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
    if (result != NSModalResponseOK || !panel.URL) return;
    [[SlateExtensionsManager sharedManager] installFromUnpackedDirectory:panel.URL completion:^(SlateExtensionRecord* rec, NSError* err) {
      (void)rec;
      if (err) [self showExtensionInstallError:err];
      else [self renderCurrentPage];
    }];
  }];
}

- (void)toggleExtensionEnabled:(NSSwitch*)sender {
  if (!sender.identifier.length) return;
  [[SlateExtensionsManager sharedManager] setExtensionId:sender.identifier enabled:(sender.state == NSControlStateValueOn)];
}

- (void)toggleExtensionPrivate:(NSButton*)sender {
  if (!sender.identifier.length) return;
  [[SlateExtensionsManager sharedManager] setExtensionId:sender.identifier allowInPrivate:(sender.state == NSControlStateValueOn)];
}

- (void)openExtensionOptions:(NSButton*)sender {
  if (!sender.identifier.length) return;
  [[SlateExtensionsManager sharedManager] openOptionsPageForExtensionId:sender.identifier];
}

- (void)removeExtensionClicked:(NSButton*)sender {
  if (!sender.identifier.length) return;
  [[SlateExtensionsManager sharedManager] removeExtensionId:sender.identifier];
  [self renderCurrentPage];
}

#pragma mark - About Page

- (void)renderAboutPage {
  NSScrollView* scroll = nil;
  SlateSettingsFlippedView* doc = [self makePageCanvasWithScroll:&scroll];
  CGFloat y = 32;

  // Brand Card
  SlateSettingsCard* hero = [self addCardTo:doc y:y height:82];
  CGFloat cw = NSWidth(hero.bounds);

  NSImageView* iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 17, 48, 48)];
  NSImage* appIcon = [NSApp applicationIconImage] ?: [NSImage imageNamed:@"AppIcon"];
  if (!appIcon) {
    NSString* iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"png"];
    if (iconPath) appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
  }
  iconView.image = appIcon;
  iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
  [hero addSubview:iconView];

  NSTextField* title = [NSTextField labelWithString:@"Slate"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
  title.frame = NSMakeRect(76, 17, cw - 200, 22);
  title.autoresizingMask = NSViewWidthSizable;
  [hero addSubview:title];

  NSDictionary* info = NSBundle.mainBundle.infoDictionary;
  NSString* version = [NSString stringWithFormat:@"Version %@ (%@) · Apple Silicon",
                       info[@"CFBundleShortVersionString"] ?: @"", info[@"CFBundleVersion"] ?: @""];
  NSTextField* ver = [NSTextField labelWithString:version];
  ver.font = [NSFont systemFontOfSize:12];
  ver.textColor = NSColor.secondaryLabelColor;
  ver.frame = NSMakeRect(76, 40, cw - 200, 16);
  ver.autoresizingMask = NSViewWidthSizable;
  [hero addSubview:ver];

  SlateQuietButton* specsBtn = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(cw - 116, 28, 100, 26)
                                                                 title:@"System Specs"
                                                                target:self
                                                                action:@selector(viewSpecsClicked:)
                                                               primary:NO];
  specsBtn.autoresizingMask = NSViewMinXMargin;
  [hero addSubview:specsBtn];

  // Updates Card
  y += 82 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Updates"];
  SlateSettingsCard* updCard = [self addCardTo:doc y:y height:146];
  cw = NSWidth(updCard.bounds);
  SlateAppUpdater* updater = [SlateAppUpdater sharedUpdater];

  NSTextField* updTitle = [NSTextField labelWithString:@"Software Updates"];
  updTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  updTitle.frame = NSMakeRect(16, 12, cw - 170, 17);
  updTitle.autoresizingMask = NSViewWidthSizable;
  [updCard addSubview:updTitle];

  NSTextField* updateNote = [NSTextField wrappingLabelWithString:updater.status ?: @""];
  [updateNote bind:NSValueBinding toObject:updater withKeyPath:@"status" options:nil];
  updateNote.font = [NSFont systemFontOfSize:11.5];
  updateNote.textColor = NSColor.secondaryLabelColor;
  updateNote.frame = NSMakeRect(16, 31, cw - 170, 30);
  updateNote.autoresizingMask = NSViewWidthSizable;
  [updCard addSubview:updateNote];

  SlateQuietButton* check = [[SlateQuietButton alloc] initWithFrame:NSMakeRect(cw - 146, 16, 130, 26)
                                                              title:@"Check for Updates…"
                                                             target:updater
                                                             action:@selector(checkForUpdates:)
                                                            primary:NO];
  check.autoresizingMask = NSViewMinXMargin;
  [check bind:NSEnabledBinding toObject:updater withKeyPath:@"canCheckForUpdates" options:nil];
  [updCard addSubview:check];

  [self addDividerToCard:updCard y:70];

  NSButton* automatic = [NSButton checkboxWithTitle:@"Automatically check for updates" target:self action:@selector(updateChecksChanged:)];
  automatic.controlSize = NSControlSizeSmall;
  automatic.font = [NSFont systemFontOfSize:12];
  automatic.state = updater.automaticallyChecksForUpdates ? NSControlStateValueOn : NSControlStateValueOff;
  automatic.frame = NSMakeRect(16, 84, cw - 32, 18);
  [updCard addSubview:automatic];

  NSButton* downloads = [NSButton checkboxWithTitle:@"Automatically download updates" target:self action:@selector(updateDownloadsChanged:)];
  downloads.controlSize = NSControlSizeSmall;
  downloads.font = [NSFont systemFontOfSize:12];
  downloads.state = updater.automaticallyDownloadsUpdates ? NSControlStateValueOn : NSControlStateValueOff;
  downloads.enabled = updater.automaticallyChecksForUpdates;
  downloads.frame = NSMakeRect(16, 110, cw - 32, 18);
  [updCard addSubview:downloads];

  // Keyboard Shortcuts Card
  y += 146 + 20;
  y = [self addSectionCaptionTo:doc y:y text:@"Shortcuts"];
  NSArray* shortcuts = @[
    @[@"⌘ T", @"New Tab"],
    @[@"⌘ W", @"Close Tab"],
    @[@"⌘ L", @"Focus Address Bar"],
    @[@"⌘ 1–9", @"Switch Tab"],
    @[@"⇧ ⌘ S", @"Toggle Sidebar Tabs"],
    @[@"⌘ S", @"Fold / Unfold Tab Strip"],
    @[@"⇧ ⌘ B", @"Toggle Bookmarks Bar"],
    @[@"⌥ ⌘ P", @"Picture-in-Picture"],
    @[@"⌘ ,", @"Open Settings"]
  ];
  CGFloat scH = shortcuts.count * 32.0;
  SlateSettingsCard* scCard = [self addCardTo:doc y:y height:scH];
  cw = NSWidth(scCard.bounds);
  CGFloat sy = 0;
  for (NSUInteger i = 0; i < shortcuts.count; ++i) {
    NSArray* sc = shortcuts[i];
    NSTextField* descField = [NSTextField labelWithString:sc[1]];
    descField.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    descField.textColor = NSColor.labelColor;
    descField.frame = NSMakeRect(16, sy + 8, cw - 110, 16);
    descField.autoresizingMask = NSViewWidthSizable;
    [scCard addSubview:descField];

    NSTextField* keyField = [NSTextField labelWithString:sc[0]];
    keyField.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightMedium];
    keyField.textColor = NSColor.secondaryLabelColor;
    keyField.alignment = NSTextAlignmentRight;
    keyField.frame = NSMakeRect(cw - 88, sy + 8, 72, 16);
    keyField.autoresizingMask = NSViewMinXMargin;
    [scCard addSubview:keyField];

    if (i + 1 < shortcuts.count) [self addDividerToCard:scCard y:sy + 31];
    sy += 32;
  }

  [self finishCanvas:doc scroll:scroll contentHeight:y + scH];
}

#if defined(SLATE_ENABLE_VERIFY)
- (void)prepareUpdaterVerification:(SlateDelegate*)delegate {
  self.slateDelegate = delegate;
  self.currentPage = @"about";
  [self renderCurrentPage];
}
#endif

- (void)updateChecksChanged:(NSButton*)sender {
  [SlateAppUpdater sharedUpdater].automaticallyChecksForUpdates = (sender.state == NSControlStateValueOn);
  [self renderCurrentPage];
}

- (void)updateDownloadsChanged:(NSButton*)sender {
  [SlateAppUpdater sharedUpdater].automaticallyDownloadsUpdates = (sender.state == NSControlStateValueOn);
}

- (void)viewSpecsClicked:(id)sender {
  [[SlateSpecsPanel sharedPanel] showForWindow:self];
}

@end
