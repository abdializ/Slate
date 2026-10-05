#import "platform/macos/plate_components.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - SlatePalette Implementation

@implementation SlatePalette

+ (NSColor*)ground {
  if (@available(macOS 10.15, *)) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* appearance) {
      BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
      return dark ? [NSColor colorWithCalibratedRed:0.13 green:0.14 blue:0.16 alpha:0.98]
                  : [NSColor colorWithCalibratedRed:0.96 green:0.96 blue:0.97 alpha:0.98];
    }];
  }
  return [NSColor windowBackgroundColor];
}

+ (NSColor*)hairline {
  if (@available(macOS 10.15, *)) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* appearance) {
      BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
      return dark ? [NSColor colorWithWhite:1.0 alpha:0.10]
                  : [NSColor colorWithWhite:0.0 alpha:0.10];
    }];
  }
  return [NSColor separatorColor];
}

+ (NSColor*)ink {
  return [NSColor labelColor];
}

+ (NSColor*)muted {
  return [NSColor secondaryLabelColor];
}

+ (NSColor*)faint {
  return [NSColor tertiaryLabelColor];
}

+ (NSColor*)wash {
  if (@available(macOS 10.15, *)) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* appearance) {
      BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
      return dark ? [NSColor colorWithWhite:1.0 alpha:0.08]
                  : [NSColor colorWithWhite:0.0 alpha:0.06];
    }];
  }
  return [NSColor colorWithWhite:0.5 alpha:0.12];
}

+ (NSColor*)accent {
  return [NSColor.controlAccentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: [NSColor systemBlueColor];
}

@end

#pragma mark - SlatePlateDoorButton Implementation

@interface SlatePlateDoorButton ()
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, strong) NSTrackingArea* trackingArea;
@end

@implementation SlatePlateDoorButton

+ (instancetype)doorWithAction:(void(^)(void))action {
  SlatePlateDoorButton* btn = [[SlatePlateDoorButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
  btn.actionBlock = action;
  return btn;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.bordered = NO;
    self.bezelStyle = NSBezelStyleRegularSquare;
    self.wantsLayer = YES;
    self.layer.cornerRadius = frameRect.size.width / 2.0;
    self.toolTip = @"Done   esc";
    self.target = self;
    self.action = @selector(clicked:);

    NSImage* xmark = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"];
    if (xmark) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightBold];
      self.image = [xmark imageWithSymbolConfiguration:cfg];
    }
    self.contentTintColor = [SlatePalette muted];
  }
  return self;
}

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
  self.contentTintColor = [SlatePalette ink];
  self.layer.backgroundColor = [SlatePalette wash].CGColor;
  [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent*)event {
  _hovered = NO;
  self.contentTintColor = [SlatePalette muted];
  self.layer.backgroundColor = [NSColor clearColor].CGColor;
  [self setNeedsDisplay:YES];
}

- (void)clicked:(id)sender {
  if (_actionBlock) _actionBlock();
}

@end

#pragma mark - SlateRuleView Implementation

@implementation SlateRuleView

+ (instancetype)ruleWithInset:(CGFloat)inset {
  SlateRuleView* rule = [[SlateRuleView alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
  rule.inset = inset;
  return rule;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _inset = 14.0;
  }
  return self;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  NSRect lineRect = NSMakeRect(_inset, 0, NSWidth(self.bounds) - _inset, 1);
  [[SlatePalette hairline] setFill];
  NSRectFill(lineRect);
}

@end

#pragma mark - SlateCaptionLabel Implementation

@implementation SlateCaptionLabel

+ (instancetype)captionWithText:(NSString*)text {
  SlateCaptionLabel* label = [SlateCaptionLabel labelWithString:text ?: @""];
  label.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
  label.textColor = [SlatePalette muted];
  return label;
}

@end

#pragma mark - SlateNothingView Implementation

@implementation SlateNothingView

+ (instancetype)nothingWithText:(NSString*)text {
  SlateNothingView* label = [SlateNothingView labelWithString:text ?: @""];
  label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
  label.textColor = [SlatePalette muted];
  return label;
}

@end

@interface SlateQuickButton () {
  NSTrackingArea* _trackingArea;
}
@end

#pragma mark - SlateQuickButton Implementation

@implementation SlateQuickButton

+ (instancetype)quickWithTitle:(NSString*)title action:(void(^)(void))action {
  return [self quickWithTitle:title tint:nil action:action];
}

+ (instancetype)quickWithTitle:(NSString*)title tint:(NSColor*)tint action:(void(^)(void))action {
  SlateQuickButton* btn = [[SlateQuickButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 22)];
  btn.title = title ?: @"";
  btn.tintColor = tint ?: [SlatePalette ink];
  btn.actionBlock = action;
  return btn;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.bordered = NO;
    self.bezelStyle = NSBezelStyleRegularSquare;
    self.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    self.wantsLayer = YES;
    self.layer.cornerRadius = 11.0;
    if (@available(macOS 11.0, *)) {
      self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.target = self;
    self.action = @selector(clicked:);
    [self updateStyle];
  }
  return self;
}

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
  self.layer.backgroundColor = [SlatePalette faint].CGColor;
  [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent*)event {
  self.layer.backgroundColor = [SlatePalette wash].CGColor;
  [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString*)title {
  [super setTitle:title];
  [self updateLayout];
}

- (void)setTintColor:(NSColor*)tintColor {
  _tintColor = tintColor;
  [self updateStyle];
}

- (void)updateStyle {
  self.contentTintColor = _tintColor ?: [SlatePalette ink];
  self.layer.backgroundColor = [SlatePalette wash].CGColor;
  [self updateLayout];
}

- (void)updateLayout {
  NSDictionary* attrs = @{ NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:11.5] };
  NSSize textSize = [self.title sizeWithAttributes:attrs];
  CGFloat width = MAX(36.0, textSize.width + 18.0);
  NSRect f = self.frame;
  f.size.width = width;
  f.size.height = 22.0;
  self.frame = f;
  self.layer.cornerRadius = 11.0;
}

- (void)clicked:(id)sender {
  if (_actionBlock) {
    _actionBlock();
  } else if (self.action && self.target && self.target != self) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

@end


#pragma mark - SlateHuntField Implementation

@interface SlateHuntField ()
@property (nonatomic, strong) NSImageView* searchIcon;
@property (nonatomic, strong) NSButton* clearButton;
@end

@implementation SlateHuntField

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _prompt = @"Search";
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10.0;
    if (@available(macOS 11.0, *)) {
      self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.backgroundColor = [SlatePalette wash].CGColor;

    // Search Icon
    NSImage* mag = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil];
    if (mag) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightMedium];
      mag = [mag imageWithSymbolConfiguration:cfg];
    }
    _searchIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, (NSHeight(frameRect) - 14)/2.0, 14, 14)];
    _searchIcon.image = mag;
    _searchIcon.contentTintColor = [SlatePalette muted];
    [self addSubview:_searchIcon];

    // Text field
    _textField = [[NSTextField alloc] initWithFrame:NSMakeRect(30, (NSHeight(frameRect) - 18)/2.0, NSWidth(frameRect) - 54, 18)];
    _textField.bordered = NO;
    _textField.drawsBackground = NO;
    _textField.focusRingType = NSFocusRingTypeNone;
    _textField.font = [NSFont systemFontOfSize:13];
    _textField.textColor = [SlatePalette ink];
    _textField.placeholderString = _prompt;
    _textField.delegate = self;
    [self addSubview:_textField];

    // Clear button
    _clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth(frameRect) - 22, (NSHeight(frameRect) - 14)/2.0, 14, 14)];
    _clearButton.bordered = NO;
    _clearButton.bezelStyle = NSBezelStyleRegularSquare;
    NSImage* xcircle = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Clear"];
    if (xcircle) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular];
      _clearButton.image = [xcircle imageWithSymbolConfiguration:cfg];
    }
    _clearButton.contentTintColor = [SlatePalette faint];
    _clearButton.target = self;
    _clearButton.action = @selector(clearClicked:);
    _clearButton.hidden = YES;
    [self addSubview:_clearButton];
  }
  return self;
}

- (void)setPrompt:(NSString*)prompt {
  _prompt = [prompt copy];
  _textField.placeholderString = _prompt;
}

- (NSString*)text {
  return _textField.stringValue ?: @"";
}

- (void)setText:(NSString*)text {
  _textField.stringValue = text ?: @"";
  _clearButton.hidden = (text.length == 0);
}

- (void)focus {
  [self.window makeFirstResponder:_textField];
}

- (void)clearClicked:(id)sender {
  _textField.stringValue = @"";
  _clearButton.hidden = YES;
  if (_onTextChanged) _onTextChanged(@"");
}

- (void)controlTextDidChange:(NSNotification*)obj {
  _clearButton.hidden = (_textField.stringValue.length == 0);
  if (_onTextChanged) _onTextChanged(_textField.stringValue);
}

@end

#pragma mark - SlateLineView Implementation

@implementation SlateLineView

- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail control:(NSView*)control {
  return [self initWithTitle:title detail:detail control:control width:300.0];
}

- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail control:(NSView*)control width:(CGFloat)width {
  CGFloat lineH = detail.length ? 54.0 : 42.0;
  self = [super initWithFrame:NSMakeRect(0, 0, width, lineH)];
  if (self) {
    self.wantsLayer = YES;

    _controlView = control;
    if (control) {
      CGFloat cx = width - 14.0 - NSWidth(control.bounds);
      CGFloat cy = (lineH - NSHeight(control.bounds)) / 2.0;
      control.frame = NSMakeRect(cx, cy, NSWidth(control.bounds), NSHeight(control.bounds));
      control.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin;
      [self addSubview:control];
    }

    CGFloat textWidth = width - 28.0 - (control ? (NSWidth(control.bounds) + 16.0) : 0.0);

    if (detail.length) {
      _titleLabel = [NSTextField labelWithString:title ?: @""];
      _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
      _titleLabel.textColor = [SlatePalette ink];
      _titleLabel.frame = NSMakeRect(14, lineH - 25, textWidth, 18);
      [self addSubview:_titleLabel];

      _detailLabel = [NSTextField wrappingLabelWithString:detail];
      _detailLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
      _detailLabel.textColor = [SlatePalette muted];
      _detailLabel.frame = NSMakeRect(14, 8, textWidth, 24);
      [self addSubview:_detailLabel];
    } else {
      _titleLabel = [NSTextField labelWithString:title ?: @""];
      _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
      _titleLabel.textColor = [SlatePalette ink];
      _titleLabel.frame = NSMakeRect(14, (lineH - 18)/2.0, textWidth, 18);
      [self addSubview:_titleLabel];
    }
  }
  return self;
}

@end

#pragma mark - SlateCardView Implementation

@interface SlateCardView ()
@property (nonatomic, strong) NSMutableArray<SlateLineView*>* cardLines;
@end

@implementation SlateCardView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layer.cornerRadius = 11.0;
    if (@available(macOS 11.0, *)) {
      self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [SlatePalette hairline].CGColor;
    self.layer.backgroundColor = [SlatePalette ground].CGColor;
    _cardLines = [NSMutableArray array];
  }
  return self;
}

- (void)setLines:(NSArray<SlateLineView*>*)lines {
  for (NSView* v in [self.subviews copy]) [v removeFromSuperview];
  [_cardLines removeAllObjects];
  for (SlateLineView* line in lines) {
    [self addLine:line];
  }
}

- (void)addLine:(SlateLineView*)line {
  if (!line) return;
  [_cardLines addObject:line];
  [self layoutLines];
}

- (void)layoutLines {
  for (NSView* v in [self.subviews copy]) [v removeFromSuperview];

  CGFloat totalH = 0;
  for (NSInteger i = 0; i < (NSInteger)_cardLines.count; i++) {
    totalH += NSHeight(_cardLines[i].bounds);
    if (i < (NSInteger)_cardLines.count - 1) totalH += 1.0;
  }

  NSRect f = self.frame;
  f.size.height = totalH;
  self.frame = f;

  CGFloat y = totalH;
  for (NSInteger i = 0; i < (NSInteger)_cardLines.count; i++) {
    SlateLineView* line = _cardLines[i];
    CGFloat lh = NSHeight(line.bounds);
    y -= lh;
    line.frame = NSMakeRect(0, y, NSWidth(self.bounds), lh);
    line.autoresizingMask = NSViewWidthSizable;
    [self addSubview:line];

    if (i < (NSInteger)_cardLines.count - 1) {
      y -= 1.0;
      SlateRuleView* rule = [SlateRuleView ruleWithInset:14.0];
      rule.frame = NSMakeRect(0, y, NSWidth(self.bounds), 1.0);
      rule.autoresizingMask = NSViewWidthSizable;
      [self addSubview:rule];
    }
  }
}

@end

#pragma mark - SlatePlateView Implementation

@implementation SlatePlateView

- (instancetype)initWithTitle:(NSString*)title width:(CGFloat)width close:(void(^)(void))close {
  NSRect frame = NSMakeRect(0, 0, width, 400);
  self = [super initWithFrame:frame];
  if (self) {
    _onClose = [close copy];
    self.wantsLayer = YES;
    self.layer.cornerRadius = 16.0;
    if (@available(macOS 11.0, *)) {
      self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [SlatePalette hairline].CGColor;
    self.layer.backgroundColor = [SlatePalette ground].CGColor;

    // Title label
    _titleLabel = [NSTextField labelWithString:title ?: @""];
    _titleLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    _titleLabel.textColor = [SlatePalette ink];
    _titleLabel.frame = NSMakeRect(22, NSHeight(frame) - 42, width - 80, 24);
    _titleLabel.autoresizingMask = NSViewMinYMargin;
    [self addSubview:_titleLabel];

    // Door close button
    __weak typeof(self) weakSelf = self;
    _doorButton = [SlatePlateDoorButton doorWithAction:^{
      if (weakSelf.onClose) weakSelf.onClose();
    }];
    _doorButton.frame = NSMakeRect(width - 22 - 24, NSHeight(frame) - 42, 24, 24);
    _doorButton.autoresizingMask = NSViewMinYMargin | NSViewMinXMargin;
    [self addSubview:_doorButton];

    // Content container
    _contentArea = [[NSView alloc] initWithFrame:NSMakeRect(22, 20, width - 44, NSHeight(frame) - 76)];
    _contentArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_contentArea];
  }
  return self;
}

- (void)setContent:(NSView*)contentView {
  for (NSView* v in [_contentArea.subviews copy]) [v removeFromSuperview];
  if (contentView) {
    contentView.frame = _contentArea.bounds;
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_contentArea addSubview:contentView];
  }
}

- (void)setFoot:(NSView*)footView {
  _footArea = footView;
  // If foot view is set, layout foot area at bottom
  if (footView) {
    CGFloat footH = NSHeight(footView.bounds);
    NSRect footRect = NSMakeRect(22, 14, NSWidth(self.bounds) - 44, footH);
    footView.frame = footRect;
    footView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self addSubview:footView];

    SlateRuleView* footRule = [SlateRuleView ruleWithInset:0];
    footRule.frame = NSMakeRect(0, 14 + footH + 6, NSWidth(self.bounds), 1);
    footRule.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self addSubview:footRule];

    // Adjust content area
    NSRect ca = _contentArea.frame;
    ca.origin.y = 14 + footH + 12;
    ca.size.height = NSHeight(self.bounds) - ca.origin.y - 54;
    _contentArea.frame = ca;
  }
}

@end
