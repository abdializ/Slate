#import "app_updater.h"
// File purpose: Implements the native settings pages and their connection to browser
// preferences/actions.

#import "platform/macos/settings_panel.h"
#import "platform/macos/passwords_panel.h"
#import "SlatePasswords-Swift.h"
#import "SlateSearch-Swift.h"
#import "spaces_manager.h"
#import "platform/macos/import_dialog.h"
#import "platform/macos/download_manager.h"
#import "platform/macos/specs_panel.h"
#import "platform/macos/privacy_security.h"
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
  NSRect b = NSInsetRect(self.bounds, 2, 2);
  NSBezierPath* circle = [NSBezierPath bezierPathWithOvalInRect:b];
  [self.swatchColor setFill];
  [circle fill];

  if (_isSelectedSwatch) {
    [[NSColor whiteColor] setStroke];
    NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(b, 2.5, 2.5)];
    ring.lineWidth = 2.0;
    [ring stroke];

    // Inner checkmark
    NSImage* check = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
    if (check) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightBold];
      check = [check imageWithSymbolConfiguration:cfg];
      NSRect checkRect = NSMakeRect((NSWidth(b) - 12)/2.0 + b.origin.x, (NSHeight(b) - 12)/2.0 + b.origin.y, 12, 12);
      [check drawInRect:checkRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }
  } else {
    [[NSColor colorWithWhite:0 alpha:0.12] setStroke];
    circle.lineWidth = 1.0;
    [circle stroke];
  }
}
@end

@interface SlateSettingsPanel ()
@property (nonatomic, strong) NSView* railView;
@property (nonatomic, strong) NSView* containerView;
@property (nonatomic, copy) NSString* currentPage;
@property (nonatomic, strong) NSMutableArray<NSButton*>* railButtons;
@property (nonatomic, strong) NSMutableArray<SlateThemeSwatchButton*>* swatchButtons;
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
@property (nonatomic, strong) NSTextField* downloadPathLabel;
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
  NSRect contentRect = NSMakeRect(0, 0, 660, 500);
  NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
  if (self = [super initWithContentRect:contentRect styleMask:style backing:NSBackingStoreBuffered defer:NO]) {
    self.title = @"Settings";
    self.minSize = NSMakeSize(600, 440);
    self.releasedWhenClosed = NO;
    self.hidesOnDeactivate = NO;
    _currentPage = @"appearance";
    _railButtons = [NSMutableArray array];
    _swatchButtons = [NSMutableArray array];
    [self setupLayout];
  }
  return self;
}

- (void)setupLayout {
  NSView* root = self.contentView;
  root.wantsLayer = YES;

  // Left rail (sidebar)
  _railView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 168, 500)];
  _railView.translatesAutoresizingMaskIntoConstraints = NO;
  _railView.wantsLayer = YES;
  _railView.layer.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.06].CGColor;
  [root addSubview:_railView];

  // Right container
  _containerView = [[NSView alloc] initWithFrame:NSMakeRect(168, 0, 492, 500)];
  _containerView.translatesAutoresizingMaskIntoConstraints = NO;
  _containerView.wantsLayer = YES;
  [root addSubview:_containerView];

  [NSLayoutConstraint activateConstraints:@[
    [_railView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [_railView.topAnchor constraintEqualToAnchor:root.topAnchor],
    [_railView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    [_railView.widthAnchor constraintEqualToConstant:168],

    [_containerView.leadingAnchor constraintEqualToAnchor:_railView.trailingAnchor],
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

  NSTextField* header = [NSTextField labelWithString:@"Settings"];
  header.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  header.textColor = [NSColor labelColor];
  header.frame = NSMakeRect(16, 458, 136, 22);
  header.autoresizingMask = NSViewMinYMargin;
  [_railView addSubview:header];

  NSArray<NSDictionary*>* items = @[
    @{@"id":@"appearance", @"title":@"Appearance", @"icon":@"paintbrush"},
    @{@"id":@"search", @"title":@"Search", @"icon":@"magnifyingglass"},
    @{@"id":@"general",    @"title":@"General",    @"icon":@"macwindow"},
    @{@"id":@"tabs",       @"title":@"Tabs",       @"icon":@"rectangle.split.3x1"},
    @{@"id":@"downloads",  @"title":@"Downloads",  @"icon":@"arrow.down.circle"},
    @{@"id":@"passwords",  @"title":@"Passwords",  @"icon":@"key"},
    @{@"id":@"privacy",    @"title":@"Privacy",    @"icon":@"hand.raised"},
    @{@"id":@"about",      @"title":@"About",      @"icon":@"info.circle"}
  ];

  CGFloat y = 416;
  for (NSDictionary* it in items) {
    NSString* pageId = it[@"id"];
    NSString* title = it[@"title"];
    NSString* iconName = it[@"icon"];

    NSButton* btn = [[NSButton alloc] initWithFrame:NSMakeRect(10, y, 148, 30)];
    btn.autoresizingMask = NSViewMinYMargin;
    btn.bezelStyle = NSBezelStyleInline;
    btn.bordered = NO;
    btn.alignment = NSTextAlignmentLeft;
    btn.imagePosition = NSImageLeading;
    btn.wantsLayer = YES;
    btn.layer.cornerRadius = 6.0;

    NSImage* sym = [NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil];
    if (sym) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
      btn.image = [sym imageWithSymbolConfiguration:cfg];
    }
    btn.title = [NSString stringWithFormat:@"  %@", title];
    btn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    btn.target = self;
    btn.action = @selector(railButtonClicked:);
    btn.identifier = pageId;

    [_railView addSubview:btn];
    [_railButtons addObject:btn];
    y -= 34;
  }

  [self updateRailSelection];
}

- (void)updateRailSelection {
  for (NSButton* b in _railButtons) {
    BOOL on = [b.identifier isEqualToString:_currentPage];
    b.font = [NSFont systemFontOfSize:13 weight:on ? NSFontWeightSemibold : NSFontWeightRegular];
    b.contentTintColor = on ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    b.layer.backgroundColor = on ? [NSColor colorWithWhite:0.5 alpha:0.18].CGColor : [NSColor clearColor].CGColor;
  }
}

- (void)railButtonClicked:(NSButton*)sender {
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

// Slate note: Refresh visible settings from the browser state so reopening the panel reflects current
// preferences.
- (void)updateFromDelegate {
  if (!self.slateDelegate) return;

  // Appearance
  if (_appearanceSegment) {
    _appearanceSegment.selectedSegment = MAX(0, MIN(2, self.slateDelegate.themeMode));
  }
  if (_tabStyleSegment) {
    _tabStyleSegment.selectedSegment = (self.slateDelegate.tabStyle == 1) ? 1 : 0;
  }
  [self updateSwatches];

  // Switches
  if (_switch120Hz) _switch120Hz.state = self.slateDelegate.pages120Hz ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchVerticalTabs) _switchVerticalTabs.state = self.slateDelegate.verticalTabs ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchCollapseTabs) _switchCollapseTabs.state = self.slateDelegate.tabsCollapsed ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchBookmarks) _switchBookmarks.state = self.slateDelegate.showBookmarksBar ? NSControlStateValueOn : NSControlStateValueOff;
  if (_switchShields) _switchShields.state = slate::WebKitShields::Shared().IsEnabled() ? NSControlStateValueOn : NSControlStateValueOff;

  // Downloads path
  if (_downloadPathLabel) {
    NSString* dir = [SlateDownloadManager sharedManager].downloadsDirectory ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    _downloadPathLabel.stringValue = [dir stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"];
  }
}

- (void)updateSwatches {
  NSString* currentAccent = self.slateDelegate.accentId ?: @"slate";
  for (SlateThemeSwatchButton* b in _swatchButtons) {
    [b setIsSelectedSwatch:[b.accentKey isEqualToString:currentAccent]];
  }
}

#pragma mark - Page Rendering

- (void)renderCurrentPage {
  for (NSView* v in [_containerView.subviews copy]) [v removeFromSuperview];
  [_swatchButtons removeAllObjects];
  _appearanceSegment = nil;
  _tabStyleSegment = nil;
  _switch120Hz = nil;
  _switchVerticalTabs = nil;
  _switchCollapseTabs = nil;
  _switchBookmarks = nil;
  _switchShields = nil;
  _downloadPathLabel = nil;

  if ([_currentPage isEqualToString:@"appearance"]) {
    [self renderAppearancePage];
  } else if ([_currentPage isEqualToString:@"search"]) {
    NSView* search=[SlateSearchServices settingsViewWithProfile:self.slateDelegate.spacesManager.currentSpaceId ?: @"default"];
    search.frame=_containerView.bounds;
    search.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
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
  } else if ([_currentPage isEqualToString:@"about"]) {
    [self renderAboutPage];
  }
  [self updateFromDelegate];
}

#pragma mark - Appearance Page (Simpler Themes)

- (void)renderAppearancePage {
  CGFloat top = 456;

  NSTextField* title = [NSTextField labelWithString:@"Appearance & Themes"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(24, top, 300, 24);
  title.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:title];

  // Card 1: Theme Mode (System, Light, Dark)
  top -= 48;
  NSTextField* modeLabel = [NSTextField labelWithString:@"Mode"];
  modeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  modeLabel.frame = NSMakeRect(24, top, 200, 18);
  modeLabel.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:modeLabel];

  NSTextField* modeSub = [NSTextField labelWithString:@"Follow your Mac's system setting, or lock to Light or Dark"];
  modeSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  modeSub.textColor = [NSColor secondaryLabelColor];
  modeSub.frame = NSMakeRect(24, top - 18, 420, 16);
  modeSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:modeSub];

  _appearanceSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"System", @"Light", @"Dark"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(appearanceSegmentChanged:)];
  _appearanceSegment.frame = NSMakeRect(24, top - 52, 240, 26);
  _appearanceSegment.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_appearanceSegment];

  // Card 2: Accent Theme Swatches
  top -= 96;
  NSTextField* themeLabel = [NSTextField labelWithString:@"Theme Color"];
  themeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  themeLabel.frame = NSMakeRect(24, top, 200, 18);
  themeLabel.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:themeLabel];

  NSTextField* themeSub = [NSTextField labelWithString:@"Pick a color for browser chrome, tabs, and buttons"];
  themeSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  themeSub.textColor = [NSColor secondaryLabelColor];
  themeSub.frame = NSMakeRect(24, top - 18, 420, 16);
  themeSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:themeSub];

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

  CGFloat sx = 24;
  CGFloat sy = top - 58;
  for (NSDictionary* item in palette) {
    SlateThemeSwatchButton* b = [[SlateThemeSwatchButton alloc] initWithFrame:NSMakeRect(sx, sy, 32, 32)
                                                                          key:item[@"id"]
                                                                        title:item[@"title"]
                                                                        color:item[@"color"]];
    b.target = self;
    b.action = @selector(swatchClicked:);
    b.autoresizingMask = NSViewMinYMargin;
    [_containerView addSubview:b];
    [_swatchButtons addObject:b];
    sx += 40;
    if (sx > 400) {
      sx = 24;
      sy -= 38;
    }
  }

  // Custom Color button
  NSButton* customColorBtn = [NSButton buttonWithTitle:@"Custom Color…" target:self action:@selector(chooseCustomColor:)];
  customColorBtn.bezelStyle = NSBezelStyleRounded;
  customColorBtn.frame = NSMakeRect(24, sy - 44, 130, 28);
  customColorBtn.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:customColorBtn];
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
  CGFloat top = 456;

  NSTextField* title = [NSTextField labelWithString:@"General"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(24, top, 300, 24);
  title.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:title];

  // 120Hz Row
  top -= 50;
  NSTextField* hzTitle = [NSTextField labelWithString:@"Pages at 120 Hz"];
  hzTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  hzTitle.frame = NSMakeRect(24, top, 250, 18);
  hzTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:hzTitle];

  NSTextField* hzSub = [NSTextField labelWithString:@"Render animations and scrolling at up to 120 fps on ProMotion displays"];
  hzSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  hzSub.textColor = [NSColor secondaryLabelColor];
  hzSub.frame = NSMakeRect(24, top - 18, 380, 16);
  hzSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:hzSub];

  _switch120Hz = [[NSSwitch alloc] initWithFrame:NSMakeRect(420, top - 10, 40, 22)];
  _switch120Hz.target = self;
  _switch120Hz.action = @selector(toggle120HzClicked:);
  _switch120Hz.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_switch120Hz];

  // Default browser
  top -= 60;
  NSTextField* defTitle = [NSTextField labelWithString:@"Default Web Browser"];
  defTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  defTitle.frame = NSMakeRect(24, top, 250, 18);
  defTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:defTitle];

  NSTextField* defSub = [NSTextField labelWithString:@"Make Slate the default app for opening web links"];
  defSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  defSub.textColor = [NSColor secondaryLabelColor];
  defSub.frame = NSMakeRect(24, top - 18, 380, 16);
  defSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:defSub];

  NSButton* makeDefaultBtn = [NSButton buttonWithTitle:@"Set as Default" target:self action:@selector(makeDefaultClicked:)];
  makeDefaultBtn.bezelStyle = NSBezelStyleRounded;
  makeDefaultBtn.frame = NSMakeRect(380, top - 12, 100, 28);
  makeDefaultBtn.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:makeDefaultBtn];
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
  CGFloat top = 456;

  NSTextField* title = [NSTextField labelWithString:@"Tabs"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(24, top, 300, 24);
  title.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:title];

  // Tab Style: Pill Tabs vs Regular Tabs
  top -= 48;
  NSTextField* styleTitle = [NSTextField labelWithString:@"Tab Style"];
  styleTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  styleTitle.frame = NSMakeRect(24, top, 250, 18);
  styleTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:styleTitle];

  NSTextField* styleSub = [NSTextField labelWithString:@"Choose between floating pill capsules (default) or classic rounded tabs"];
  styleSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  styleSub.textColor = [NSColor secondaryLabelColor];
  styleSub.frame = NSMakeRect(24, top - 18, 420, 16);
  styleSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:styleSub];

  _tabStyleSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Pill Tabs", @"Regular Tabs"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self
                                                             action:@selector(tabStyleSegmentChanged:)];
  _tabStyleSegment.frame = NSMakeRect(24, top - 52, 220, 26);
  _tabStyleSegment.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_tabStyleSegment];

  // Vertical tabs
  top -= 92;
  NSTextField* vertTitle = [NSTextField labelWithString:@"Tabs in a Sidebar"];
  vertTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  vertTitle.frame = NSMakeRect(24, top, 250, 18);
  vertTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:vertTitle];

  NSTextField* vertSub = [NSTextField labelWithString:@"Show tabs vertically down the left edge instead of across the top (⇧⌘S)"];
  vertSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  vertSub.textColor = [NSColor secondaryLabelColor];
  vertSub.frame = NSMakeRect(24, top - 18, 380, 16);
  vertSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:vertSub];

  _switchVerticalTabs = [[NSSwitch alloc] initWithFrame:NSMakeRect(420, top - 10, 40, 22)];
  _switchVerticalTabs.target = self;
  _switchVerticalTabs.action = @selector(toggleVerticalTabsClicked:);
  _switchVerticalTabs.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_switchVerticalTabs];

  // Collapse tabs
  top -= 60;
  NSTextField* colTitle = [NSTextField labelWithString:@"Fold Tabs Away"];
  colTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  colTitle.frame = NSMakeRect(24, top, 250, 18);
  colTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:colTitle];

  NSTextField* colSub = [NSTextField labelWithString:@"Hide the tab strip for a distraction-free, full-window view (⌘S)"];
  colSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  colSub.textColor = [NSColor secondaryLabelColor];
  colSub.frame = NSMakeRect(24, top - 18, 380, 16);
  colSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:colSub];

  _switchCollapseTabs = [[NSSwitch alloc] initWithFrame:NSMakeRect(420, top - 10, 40, 22)];
  _switchCollapseTabs.target = self;
  _switchCollapseTabs.action = @selector(toggleCollapseTabsClicked:);
  _switchCollapseTabs.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_switchCollapseTabs];

  // Bookmarks bar
  top -= 60;
  NSTextField* bmkTitle = [NSTextField labelWithString:@"Show Bookmarks Bar"];
  bmkTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  bmkTitle.frame = NSMakeRect(24, top, 250, 18);
  bmkTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:bmkTitle];

  NSTextField* bmkSub = [NSTextField labelWithString:@"Always show your bookmarks bar underneath the address bar (⇧⌘B)"];
  bmkSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  bmkSub.textColor = [NSColor secondaryLabelColor];
  bmkSub.frame = NSMakeRect(24, top - 18, 380, 16);
  bmkSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:bmkSub];

  _switchBookmarks = [[NSSwitch alloc] initWithFrame:NSMakeRect(420, top - 10, 40, 22)];
  _switchBookmarks.target = self;
  _switchBookmarks.action = @selector(toggleBookmarksClicked:);
  _switchBookmarks.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_switchBookmarks];
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
  CGFloat top = 456;

  NSTextField* title = [NSTextField labelWithString:@"Downloads"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(24, top, 300, 24);
  title.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:title];

  top -= 50;
  NSTextField* locTitle = [NSTextField labelWithString:@"Download Location"];
  locTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  locTitle.frame = NSMakeRect(24, top, 250, 18);
  locTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:locTitle];

  _downloadPathLabel = [NSTextField labelWithString:@"~/Downloads"];
  _downloadPathLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  _downloadPathLabel.textColor = [NSColor secondaryLabelColor];
  _downloadPathLabel.frame = NSMakeRect(24, top - 18, 330, 16);
  _downloadPathLabel.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:_downloadPathLabel];

  NSButton* changeBtn = [NSButton buttonWithTitle:@"Change Folder…" target:self action:@selector(changeDownloadFolder:)];
  changeBtn.bezelStyle = NSBezelStyleRounded;
  changeBtn.frame = NSMakeRect(360, top - 12, 115, 28);
  changeBtn.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:changeBtn];
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
  CGFloat top = 456;

  NSTextField* title = [NSTextField labelWithString:@"Passwords"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(24, top, 300, 24);
  title.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:title];

  top -= 50;
  NSTextField* passTitle = [NSTextField labelWithString:@"Saved Passwords"];
  passTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  passTitle.frame = NSMakeRect(24, top, 250, 18);
  passTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:passTitle];

  NSTextField* passSub = [NSTextField labelWithString:@"Manage logins, usernames, and passwords saved securely in Slate"];
  passSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  passSub.textColor = [NSColor secondaryLabelColor];
  passSub.frame = NSMakeRect(24, top - 18, 330, 16);
  passSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:passSub];

  NSButton* openPassBtn = [NSButton buttonWithTitle:@"Open Passwords" target:self action:@selector(openPasswordsClicked:)];
  openPassBtn.bezelStyle = NSBezelStyleRounded;
  openPassBtn.frame = NSMakeRect(350, top - 12, 125, 28);
  openPassBtn.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:openPassBtn];

  top -= 60;
  NSTextField* impTitle = [NSTextField labelWithString:@"Import Passwords"];
  impTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  impTitle.frame = NSMakeRect(24, top, 250, 18);
  impTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:impTitle];

  NSTextField* impSub = [NSTextField labelWithString:@"Import logins and history from Chrome, Safari, Arc, or Brave"];
  impSub.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  impSub.textColor = [NSColor secondaryLabelColor];
  impSub.frame = NSMakeRect(24, top - 18, 330, 16);
  impSub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:impSub];

  NSButton* impBtn = [NSButton buttonWithTitle:@"Import Data…" target:self action:@selector(importDataClicked:)];
  impBtn.bezelStyle = NSBezelStyleRounded;
  impBtn.frame = NSMakeRect(350, top - 12, 125, 28);
  impBtn.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:impBtn];
  NSView* services=[SlatePasswordServices.shared settingsView];
  services.frame=NSMakeRect(20,48,450,218);
  services.autoresizingMask=NSViewMinYMargin;
  [_containerView addSubview:services];
}

- (void)openPasswordsClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate showPasswordsPanel:sender];
}

- (void)importDataClicked:(id)sender {
  if (self.slateDelegate) [self.slateDelegate showImportBrowserData:sender];
}

#pragma mark - Privacy Page

- (void)renderPrivacyPage {
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:_containerView.bounds];
  scroll.hasVerticalScroller = YES;
  scroll.drawsBackground = NO;
  scroll.borderType = NSNoBorder;
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  auto sites = slate::WebKitShields::Shared().DisabledSites();
  std::sort(sites.begin(), sites.end());
  CGFloat docH = MAX(NSHeight(_containerView.bounds), 660.0 + sites.size() * 30.0);
  NSView* doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(_containerView.bounds), docH)];
  scroll.documentView = doc;
  [_containerView addSubview:scroll];

  CGFloat y = docH - 36;
  NSTextField* title = [NSTextField labelWithString:@"Privacy & Security"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(24, y, 320, 24);
  [doc addSubview:title];

  auto addToggleRow = ^(CGFloat rowY, NSString* heading, NSString* sub, BOOL on, SEL action, NSSwitch** outSwitch) {
    NSTextField* h = [NSTextField labelWithString:heading];
    h.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    h.frame = NSMakeRect(24, rowY, 370, 18);
    [doc addSubview:h];

    NSTextField* s = [NSTextField labelWithString:sub];
    s.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    s.textColor = NSColor.secondaryLabelColor;
    s.frame = NSMakeRect(24, rowY - 17, 380, 15);
    [doc addSubview:s];

    NSSwitch* sw = [[NSSwitch alloc] initWithFrame:NSMakeRect(420, rowY - 9, 40, 22)];
    sw.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    sw.target = self;
    sw.action = action;
    [doc addSubview:sw];
    if (outSwitch) *outSwitch = sw;
  };

  y -= 44;
  NSSwitch* s1 = nil;
  addToggleRow(y, @"Ad & Tracker Blocker (High Alert)",
               @"Native WebKit filter (EasyList + EasyPrivacy + Slate rules)",
               slate::WebKitShields::Shared().IsEnabled(),
               @selector(toggleShieldsClicked:), &s1);
  self.switchShields = s1;

  y -= 48;
  NSSwitch* s2 = nil;
  addToggleRow(y, @"Strict Tracking & Fingerprint Protection",
               @"Strip utm/fbclid/gclid trackers, send Global Privacy Control & DNT",
               [SlatePrivacySecurity strictTrackingProtectionEnabled],
               @selector(toggleStrictPrivacyClicked:), &s2);
  self.switchStrictPrivacy = s2;

  y -= 48;
  NSSwitch* s3 = nil;
  addToggleRow(y, @"HTTPS-Only Mode",
               @"Automatically upgrade insecure http:// connections to https://",
               [SlatePrivacySecurity httpsOnlyEnabled],
               @selector(toggleHttpsOnlyClicked:), &s3);
  self.switchHttpsOnly = s3;

  y -= 48;
  NSSwitch* s4 = nil;
  addToggleRow(y, @"Block WebRTC IP Leaks in Incognito",
               @"Disable RTCPeerConnection in Private tabs to prevent real-IP leaks",
               [SlatePrivacySecurity blockWebRTCInIncognito],
               @selector(toggleWebRTCBlockClicked:), &s4);
  self.switchWebRTCBlock = s4;

  // Incognito VPN / Proxy Tunnel Card
  y -= 36;
  NSView* vpnCard = [[NSView alloc] initWithFrame:NSMakeRect(24, y - 246, 438, 246)];
  vpnCard.wantsLayer = YES;
  vpnCard.layer.cornerRadius = 11;
  if (@available(macOS 11.0, *)) vpnCard.layer.cornerCurve = kCACornerCurveContinuous;
  vpnCard.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.04].CGColor;
  vpnCard.layer.borderWidth = 1;
  vpnCard.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.5].CGColor;
  [doc addSubview:vpnCard];

  NSTextField* vpnTitle = [NSTextField labelWithString:@"Incognito VPN / Proxy Tunnel"];
  vpnTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  vpnTitle.frame = NSMakeRect(14, 214, 300, 18);
  [vpnCard addSubview:vpnTitle];

  NSTextField* vpnSub = [NSTextField labelWithString:@"Route all Private tabs through Tor or your VPN’s SOCKS5 / HTTP proxy"];
  vpnSub.font = [NSFont systemFontOfSize:11];
  vpnSub.textColor = NSColor.secondaryLabelColor;
  vpnSub.frame = NSMakeRect(14, 196, 410, 15);
  [vpnCard addSubview:vpnSub];

  NSPopUpButton* modePop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(14, 162, 410, 26) pullsDown:NO];
  [modePop addItemsWithTitles:@[
    @"Off (Direct)",
    @"Tor Local Tunnel (SOCKS5 127.0.0.1:9050)",
    @"Custom SOCKS5 VPN / Proxy (Mullvad, Proton, SSH…)",
    @"Custom HTTP CONNECT Proxy"
  ]];
  [modePop selectItemAtIndex:(NSInteger)[SlatePrivacySecurity incognitoProxyMode]];
  modePop.target = self;
  modePop.action = @selector(vpnModeChanged:);
  self.vpnModePopup = modePop;
  [vpnCard addSubview:modePop];

  self.vpnHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 128, 294, 24)];
  self.vpnHostField.placeholderString = @"Host (e.g. 10.64.0.1 or us-nyc.socks5.mullvad.net)";
  self.vpnHostField.stringValue = [SlatePrivacySecurity incognitoProxyHost];
  [vpnCard addSubview:self.vpnHostField];

  self.vpnPortField = [[NSTextField alloc] initWithFrame:NSMakeRect(316, 128, 108, 24)];
  self.vpnPortField.placeholderString = @"Port (1080)";
  NSInteger portVal = [SlatePrivacySecurity incognitoProxyPort];
  self.vpnPortField.stringValue = portVal > 0 ? [NSString stringWithFormat:@"%ld", (long)portVal] : @"";
  [vpnCard addSubview:self.vpnPortField];

  self.vpnUserField = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 96, 200, 24)];
  self.vpnUserField.placeholderString = @"Username (optional)";
  self.vpnUserField.stringValue = [SlatePrivacySecurity incognitoProxyUsername];
  [vpnCard addSubview:self.vpnUserField];

  self.vpnPassField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(222, 96, 202, 24)];
  self.vpnPassField.placeholderString = @"Password (Keychain)";
  self.vpnPassField.stringValue = [SlatePrivacySecurity incognitoProxyPassword];
  [vpnCard addSubview:self.vpnPassField];

  self.vpnFailClosedCheck = [NSButton checkboxWithTitle:@"Kill Switch: block Incognito if tunnel is unreachable" target:nil action:nil];
  self.vpnFailClosedCheck.state = [SlatePrivacySecurity incognitoProxyFailClosed] ? NSControlStateValueOn : NSControlStateValueOff;
  self.vpnFailClosedCheck.font = [NSFont systemFontOfSize:11.5];
  self.vpnFailClosedCheck.frame = NSMakeRect(14, 66, 410, 20);
  [vpnCard addSubview:self.vpnFailClosedCheck];

  NSButton* saveVpn = [NSButton buttonWithTitle:@"Save Tunnel" target:self action:@selector(saveVpnClicked:)];
  saveVpn.frame = NSMakeRect(14, 34, 106, 26);
  [vpnCard addSubview:saveVpn];

  NSButton* testVpn = [NSButton buttonWithTitle:@"Test Tunnel" target:self action:@selector(testVpnClicked:)];
  testVpn.frame = NSMakeRect(126, 34, 100, 26);
  [vpnCard addSubview:testVpn];

  self.vpnStatusLabel = [NSTextField labelWithString:[SlatePrivacySecurity isIncognitoTunnelActive] ? @"Active for new Incognito tabs" : @"Tunnel off"];
  self.vpnStatusLabel.font = [NSFont systemFontOfSize:11];
  self.vpnStatusLabel.textColor = [SlatePrivacySecurity isIncognitoTunnelActive] ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
  self.vpnStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.vpnStatusLabel.frame = NSMakeRect(14, 10, 410, 16);
  [vpnCard addSubview:self.vpnStatusLabel];
  [self updateVpnFieldStates];

  // Allowed Sites
  y -= 274;
  NSTextField* allowedTitle = [NSTextField labelWithString:@"Allowed Sites (Ad Blocker Paused)"];
  allowedTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  allowedTitle.frame = NSMakeRect(24, y, 320, 20);
  [doc addSubview:allowedTitle];

  y -= 26;
  if (sites.empty()) {
    NSTextField* empty = [NSTextField labelWithString:@"No allowed sites — all sites protected at maximum level."];
    empty.font = [NSFont systemFontOfSize:11.5];
    empty.textColor = NSColor.secondaryLabelColor;
    empty.frame = NSMakeRect(24, y, 420, 18);
    [doc addSubview:empty];
  } else {
    for (const auto& site : sites) {
      NSString* name = [NSString stringWithUTF8String:site.c_str()];
      NSTextField* label = [NSTextField labelWithString:name];
      label.frame = NSMakeRect(24, y, 330, 18);
      label.lineBreakMode = NSLineBreakByTruncatingMiddle;
      [doc addSubview:label];
      NSButton* remove = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeAllowedSiteClicked:)];
      remove.identifier = name;
      remove.frame = NSMakeRect(368, y - 4, 82, 26);
      [doc addSubview:remove];
      y -= 30;
    }
  }

  [scroll.contentView scrollToPoint:NSMakePoint(0, MAX(0, docH - NSHeight(scroll.contentView.bounds)))];
  [scroll reflectScrolledClipView:scroll.contentView];
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
  self.vpnStatusLabel.stringValue = active ? @"Saved — active on new Incognito tabs" : (mode == SlateProxyModeOff ? @"Tunnel off" : @"Enter valid host & port");
  self.vpnStatusLabel.textColor = active ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
}

- (void)testVpnClicked:(id)sender {
  [self saveVpnClicked:sender];
  self.vpnStatusLabel.stringValue = @"Testing tunnel…";
  self.vpnStatusLabel.textColor = NSColor.secondaryLabelColor;
  __weak SlateSettingsPanel* weakSelf = self;
  [SlatePrivacySecurity testIncognitoTunnelWithCompletion:^(BOOL reachable, NSString* message) {
    SlateSettingsPanel* strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.vpnStatusLabel) return;
    strongSelf.vpnStatusLabel.stringValue = message;
    strongSelf.vpnStatusLabel.textColor = reachable ? NSColor.systemGreenColor : NSColor.systemRedColor;
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

#pragma mark - About Page

- (void)renderAboutPage {
  CGFloat top = 456;

  NSImageView* iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, top - 38, 54, 54)];
  NSImage* appIcon = [NSApp applicationIconImage] ?: [NSImage imageNamed:@"AppIcon"];
  if (!appIcon) {
    NSString* iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"png"];
    if (iconPath) {
      appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    }
  }
  iconView.image = appIcon;
  iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
  iconView.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:iconView];

  NSTextField* title = [NSTextField labelWithString:@"Slate Browser"];
  title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
  title.frame = NSMakeRect(90, top - 4, 300, 24);
  title.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:title];

  NSDictionary* info=NSBundle.mainBundle.infoDictionary;
  NSString* version=[NSString stringWithFormat:@"Version %@ (Build %@) — Apple Silicon",info[@"CFBundleShortVersionString"],info[@"CFBundleVersion"]];
  NSTextField* ver = [NSTextField labelWithString:version];
  ver.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  ver.textColor = [NSColor secondaryLabelColor];
  ver.frame = NSMakeRect(90, top - 24, 360, 18);
  ver.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:ver];

  NSTextField* sub = [NSTextField labelWithString:@"A native Mac browser, built for your browsing workspace"];
  sub.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
  sub.textColor = [NSColor tertiaryLabelColor];
  sub.frame = NSMakeRect(90, top - 42, 360, 18);
  sub.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:sub];

  SlateAppUpdater* updater=[SlateAppUpdater sharedUpdater];
  NSButton* check=[NSButton buttonWithTitle:@"Check for Updates…" target:updater action:@selector(checkForUpdates:)];
  check.bezelStyle=NSBezelStyleRounded;
  check.frame=NSMakeRect(24,top-88,170,28); check.autoresizingMask=NSViewMinYMargin;
  [check bind:NSEnabledBinding toObject:updater withKeyPath:@"canCheckForUpdates" options:nil];
  [_containerView addSubview:check];
  NSButton* automatic=[NSButton checkboxWithTitle:@"Automatically check for updates" target:self action:@selector(updateChecksChanged:)];
  automatic.state=updater.automaticallyChecksForUpdates ? NSControlStateValueOn : NSControlStateValueOff;
  automatic.frame=NSMakeRect(24,top-120,340,24); automatic.autoresizingMask=NSViewMinYMargin;
  [_containerView addSubview:automatic];
  NSButton* downloads=[NSButton checkboxWithTitle:@"Automatically download updates" target:self action:@selector(updateDownloadsChanged:)];
  downloads.state=updater.automaticallyDownloadsUpdates ? NSControlStateValueOn : NSControlStateValueOff;
  downloads.enabled=updater.automaticallyChecksForUpdates;
  downloads.frame=NSMakeRect(24,top-148,340,24); downloads.autoresizingMask=NSViewMinYMargin;
  [_containerView addSubview:downloads];
  NSTextField* updateNote=[NSTextField wrappingLabelWithString:updater.status];
  [updateNote bind:NSValueBinding toObject:updater withKeyPath:@"status" options:nil];
  updateNote.font=[NSFont systemFontOfSize:11]; updateNote.textColor=NSColor.secondaryLabelColor;
  updateNote.frame=NSMakeRect(24,top-187,430,32); updateNote.autoresizingMask=NSViewMinYMargin;
  [_containerView addSubview:updateNote];

  // Button to view hardware specs
  NSButton* specsBtn = [NSButton buttonWithTitle:@"View System Hardware Specs" target:self action:@selector(viewSpecsClicked:)];
  specsBtn.bezelStyle = NSBezelStyleRounded;
  specsBtn.frame = NSMakeRect(250, top - 88, 210, 28);
  specsBtn.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:specsBtn];

  // Keyboard Shortcuts Cheat Sheet
  top -= 220;
  NSTextField* scTitle = [NSTextField labelWithString:@"Keyboard Shortcuts"];
  scTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  scTitle.frame = NSMakeRect(24, top, 200, 18);
  scTitle.autoresizingMask = NSViewMinYMargin;
  [_containerView addSubview:scTitle];

  NSArray* shortcuts = @[
    @[@"⌘ T", @"New Tab"],
    @[@"⌘ W", @"Close Tab"],
    @[@"⌥ ⌘ P", @"Toggle Picture-in-Picture"],
    @[@"⌘ L", @"Focus Address Bar / Search"],
    @[@"⌘ 1–9", @"Switch to Tab by Index"],
    @[@"⇧ ⌘ S", @"Toggle Sidebar (Vertical Tabs)"],
    @[@"⌘ S", @"Fold / Unfold Tab Strip"],
    @[@"⇧ ⌘ B", @"Toggle Bookmarks Bar"],
    @[@"⌘ ,", @"Open Settings"]
  ];

  CGFloat sy = top - 24;
  for (NSArray* sc in shortcuts) {
    NSTextField* keyField = [NSTextField labelWithString:sc[0]];
    keyField.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightMedium];
    keyField.frame = NSMakeRect(24, sy, 80, 16);
    keyField.autoresizingMask = NSViewMinYMargin;
    [_containerView addSubview:keyField];

    NSTextField* descField = [NSTextField labelWithString:sc[1]];
    descField.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    descField.textColor = [NSColor secondaryLabelColor];
    descField.frame = NSMakeRect(110, sy, 320, 16);
    descField.autoresizingMask = NSViewMinYMargin;
    [_containerView addSubview:descField];

    sy -= 20;
  }
}

#if defined(SLATE_ENABLE_VERIFY)
- (void)prepareUpdaterVerification:(SlateDelegate*)delegate {
 self.slateDelegate=delegate; self.currentPage=@"about"; [self renderCurrentPage];
}
#endif
- (void)updateChecksChanged:(NSButton*)sender {
 [SlateAppUpdater sharedUpdater].automaticallyChecksForUpdates=sender.state==NSControlStateValueOn;
 [self renderCurrentPage];
}
- (void)updateDownloadsChanged:(NSButton*)sender {
 [SlateAppUpdater sharedUpdater].automaticallyDownloadsUpdates=sender.state==NSControlStateValueOn;
}
- (void)viewSpecsClicked:(id)sender {
  [[SlateSpecsPanel sharedPanel] showForWindow:self];
}

@end
