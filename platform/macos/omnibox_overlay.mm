// File purpose: Implements the address/search field card, inline completion, and its centered page
// overlay.

#import "omnibox_overlay.h"
#import <QuartzCore/QuartzCore.h>

// MARK: - SlateOmniboxCard

@interface SlateOmniboxCard () {
  BOOL _refused;
  NSVisualEffectView* _materialView;
  NSButton* _siteChip;
}
@end

@implementation SlateOmniboxCard

- (instancetype)initWithDelegate:(id<SlateOmniboxDelegate>)delegate {
  self = [super initWithFrame:NSMakeRect(0, 0, kFieldWidth, kFieldHeight)];
  if (!self) return nil;

  _delegate = delegate;
  _refused = NO;
  _customDarkSet = NO;
  _isDarkTheme = NO;

  self.wantsLayer = YES;
  self.layer.cornerRadius = kCornerRadius;
  if (@available(macOS 11.0, *)) {
    self.layer.cornerCurve = kCACornerCurveContinuous;
  }
  self.layer.borderWidth = 1.0;
  _materialView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
  _materialView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  _materialView.material = NSVisualEffectMaterialContentBackground;
  _materialView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
  _materialView.state = NSVisualEffectStateFollowsWindowActiveState;
  _materialView.wantsLayer = YES;
  _materialView.layer.cornerRadius = kCornerRadius;
  _materialView.layer.masksToBounds = YES;
  [self addSubview:_materialView positioned:NSWindowBelow relativeTo:nil];

  // Field inside the card: 24pt high, centered vertically with 24pt horizontal padding
  _field = [[NSTextField alloc] initWithFrame:NSMakeRect(24, round((kFieldHeight - 24) / 2.0), kFieldWidth - 48, 24)];
  _field.delegate = self;
  _field.bordered = NO;
  _field.drawsBackground = NO;
  _field.focusRingType = NSFocusRingTypeNone;
  _field.font = [NSFont systemFontOfSize:15.5 weight:NSFontWeightRegular];
  _field.lineBreakMode = NSLineBreakByTruncatingTail;
  _field.cell.usesSingleLineMode = YES;
  _field.cell.wraps = NO;
  [self addSubview:_field];

  _siteChip = [NSButton buttonWithTitle:@"" target:self action:@selector(removeSite:)];
  _siteChip.bordered = NO;
  _siteChip.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  _siteChip.hidden = YES;
  _siteChip.toolTip = @"Remove site search";
  [self addSubview:_siteChip];
  [self applyTheme];
  return self;
}

- (void)setSearchSite:(NSDictionary<NSString*,NSString*>*)site {
  _searchSite = [site copy];
  _siteChip.title = site ? [NSString stringWithFormat:@"%@ ×", site[@"name"]] : @"";
  _siteChip.hidden = site == nil;
  _field.placeholderString = site ? [@"Search " stringByAppendingString:site[@"host"]] : @"Search or enter address";
  self.needsLayout = YES;
}
- (void)activateSite:(NSDictionary<NSString*,NSString*>*)site {
  self.searchSite = site;
  self.suggestedSite = nil;
  self.field.stringValue = @"";
  [self.delegate hideSuggestions];
  [self.window makeFirstResponder:self.field];
}
- (void)removeSite:(id)sender {
  self.searchSite = nil;
  [self.delegate hideSuggestions];
  [self.window makeFirstResponder:self.field];
}
- (void)setIsDarkTheme:(BOOL)isDarkTheme {
  _isDarkTheme = isDarkTheme;
  _customDarkSet = YES;
  [self applyTheme];
}

- (void)setPlaceholder:(NSString*)placeholder {
  _placeholder = [placeholder copy];
  [self applyTheme];
}

- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  [self applyTheme];
}

- (void)applyTheme {
  NSColor* ink = self.inkColor;
  BOOL isDark = NO;
  if (_customDarkSet) {
    isDark = _isDarkTheme;
  } else if (self.effectiveAppearance) {
    isDark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  }
  if (!ink) ink = NSColor.labelColor;
  NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
  const BOOL contrast = workspace.accessibilityDisplayShouldIncreaseContrast;
  self.layer.backgroundColor = nil;
  self.layer.borderWidth = contrast ? 1.0 : 0.5;
  self.layer.borderColor = _refused
    ? [NSColor colorWithCalibratedRed:0.92 green:0.26 blue:0.26 alpha:0.65].CGColor
    : [[NSColor labelColor] colorWithAlphaComponent:contrast ? 0.25 : 0.10].CGColor;
  self.layer.shadowColor = NSColor.blackColor.CGColor;
  self.layer.shadowRadius = 8.0;
  self.layer.shadowOffset = CGSizeMake(0, -3);
  self.layer.shadowOpacity = 0.06;

  _field.textColor = ink;
  NSString* p = self.searchSite ? [@"Search " stringByAppendingString:self.searchSite[@"host"]] : (_placeholder.length ? _placeholder : @"Search or enter address");
  NSColor* placeholderColor = isDark ? [NSColor colorWithWhite:0.75 alpha:0.55] : [NSColor colorWithWhite:0.38 alpha:0.65];
  _field.placeholderAttributedString = [[NSAttributedString alloc] initWithString:p
    attributes:@{
      NSFontAttributeName: [NSFont systemFontOfSize:15.5 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: placeholderColor
    }];

}

- (void)layout {
  [super layout];
  const CGFloat w = NSWidth(self.bounds);
  const CGFloat h = NSHeight(self.bounds);
  const CGFloat radius = round(h / 2.0);
  self.layer.cornerRadius = radius;
  if (@available(macOS 11.0, *)) {
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _materialView.layer.cornerCurve = kCACornerCurveContinuous;
  }
  _materialView.layer.cornerRadius = radius;
  CGFloat chipWidth = _searchSite ? MIN(160, [_siteChip.title sizeWithAttributes:@{NSFontAttributeName:_siteChip.font}].width + 18) : 0;
  _siteChip.frame = NSMakeRect(20, round((h-26)/2), chipWidth, 26);
  _field.frame = NSMakeRect(24 + chipWidth, round((h - 24.0) / 2.0), MAX(40, w - 48 - chipWidth), 24);

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  CGPathRef path = CGPathCreateWithRoundedRect(self.bounds, radius, radius, NULL);
  self.layer.shadowPath = path;
  CGPathRelease(path);
  [CATransaction commit];
}

- (NSView*)hitTest:(NSPoint)point {
  NSPoint local = [self convertPoint:point fromView:self.superview];
  if (!NSPointInRect(local, self.bounds) || self.hidden) return nil;
  if (!_siteChip.hidden && NSPointInRect(local, _siteChip.frame)) return _siteChip;
  return self.field;
}

- (void)mouseDown:(NSEvent*)event {
  [self.window makeFirstResponder:self.field];
  [self.field selectText:nil];
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }

- (void)shake {
  _refused = YES;
  NSColor* alertRed = [NSColor colorWithCalibratedRed:0.92 green:0.26 blue:0.26 alpha:0.35];
  self.layer.borderColor = alertRed.CGColor;

  CAKeyframeAnimation* anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
  anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
  anim.duration = 0.50;
  anim.values = @[ @(0), @(-10), @(10), @(-8), @(8), @(-5), @(5), @(-2), @(2), @(0) ];
  [self.layer addAnimation:anim forKey:@"shake"];
}

// MARK: - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification*)note {
  if (_refused) {
    _refused = NO;
    NSColor* ink = NSColor.labelColor;
    self.layer.borderColor = [ink colorWithAlphaComponent:0.14].CGColor;
  }

  NSString* text = _field.stringValue;

  if (self.delegate) {
    if ([self.delegate respondsToSelector:@selector(showSuggestionsForCard:query:)]) {
      [self.delegate showSuggestionsForCard:self query:text];
    } else if ([self.delegate respondsToSelector:@selector(showSuggestionsForOverlay:)]) {
      [self.delegate showSuggestionsForOverlay:text];
    }
  }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(insertTab:) && self.suggestedSite && !self.searchSite) {
    [self activateSite:self.suggestedSite]; return YES;
  }
  if (commandSelector == @selector(deleteBackward:) && self.searchSite && self.field.stringValue.length == 0) {
    [self removeSite:nil]; return YES;
  }
  if (commandSelector == @selector(insertNewline:)) {
    if (self.delegate) {
      if ([self.delegate respondsToSelector:@selector(submitOmniboxCard:)]) {
        [self.delegate submitOmniboxCard:self];
      }
    }
    return YES;
  }
  if (commandSelector == @selector(moveDown:)) {
    if (self.delegate) {
      [self.delegate moveSuggestionDelta:1];
    }
    return YES;
  }
  if (commandSelector == @selector(moveUp:)) {
    if (self.delegate) {
      [self.delegate moveSuggestionDelta:-1];
    }
    return YES;
  }
  if (commandSelector == @selector(deleteBackward:) || commandSelector == @selector(deleteForward:)) {
    return NO;
  }
  if (commandSelector == @selector(cancelOperation:)) {
    if (self.searchSite) { [self removeSite:nil]; return YES; }
    if (self.delegate) {
      [self.delegate hideSuggestions];
    }
    if ([self.superview isKindOfClass:[SlateOmniboxOverlay class]]) {
      [(SlateOmniboxOverlay*)self.superview dismiss];
    } else {
      _field.stringValue = @"";
    }
    return YES;
  }
  return NO;
}

@end

// MARK: - SlateOmniboxOverlay

@implementation SlateOmniboxOverlay

- (instancetype)initWithDelegate:(id<SlateOmniboxDelegate>)delegate {
  self = [super initWithFrame:NSZeroRect];
  if (!self) return nil;

  _delegate = delegate;
  self.wantsLayer = YES;
  self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  // Backdrop: 0.74 opacity scrim covering the page
  _backdrop = [[NSView alloc] initWithFrame:NSZeroRect];
  _backdrop.wantsLayer = YES;
  _backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self addSubview:_backdrop];

  // Click on backdrop to dismiss
  NSClickGestureRecognizer* click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(backdropClicked:)];
  [_backdrop addGestureRecognizer:click];

  // Center omnibox card
  _card = [[SlateOmniboxCard alloc] initWithDelegate:delegate];
  [self addSubview:_card];

  [self applyTheme];
  return self;
}

- (NSTextField*)field {
  return _card.field;
}

- (NSView*)fieldCard {
  return _card;
}

- (BOOL)isShowing {
  return self.superview != nil && !self.hidden;
}

- (void)applyTheme {
  NSColor* ground = [NSColor windowBackgroundColor];
  _backdrop.layer.backgroundColor = [ground colorWithAlphaComponent:0.74].CGColor;
  [_card applyTheme];
}

- (void)layout {
  [super layout];
  _backdrop.frame = self.bounds;

  // Centered horizontally, lifted 30pt above center (60pt air below center)
  const CGFloat w = NSWidth(self.bounds);
  const CGFloat h = NSHeight(self.bounds);
  const CGFloat cardX = round((w - kFieldWidth) / 2.0);
  const CGFloat cardY = round((h - kFieldHeight) / 2.0) + 30.0;
  _card.frame = NSMakeRect(cardX, cardY, kFieldWidth, kFieldHeight);
}

- (void)showOver:(NSView*)container initialText:(NSString*)text {
  self.card.searchSite = nil; self.card.suggestedSite = nil;
  if (self.superview != container) {
    self.frame = container.bounds;
    [container addSubview:self positioned:NSWindowAbove relativeTo:nil];
  }

  [self applyTheme];
  self.alphaValue = 0.0;
  self.hidden = NO;

  NSString* query = text ?: @"";
  if ([query isEqualToString:@"about:blank"]) query = @"";
  _card.field.stringValue = query;

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.16;
    ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    self.animator.alphaValue = 1.0;
  } completionHandler:^{
    [self.window makeFirstResponder:self.card.field];
    if (query.length > 0) {
      [self.card.field selectText:nil];
    }
    if (self.delegate) {
      if ([self.delegate respondsToSelector:@selector(showSuggestionsForCard:query:)]) {
        [self.delegate showSuggestionsForCard:self.card query:query];
      } else if ([self.delegate respondsToSelector:@selector(showSuggestionsForOverlay:)]) {
        [self.delegate showSuggestionsForOverlay:query];
      }
    }
  }];
}

- (void)dismiss {
  if (self.delegate) {
    [self.delegate hideSuggestions];
  }

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.14;
    ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    self.animator.alphaValue = 0.0;
  } completionHandler:^{
    self.hidden = YES;
    [self removeFromSuperview];
    if (self.delegate && [self.delegate respondsToSelector:@selector(omniboxOverlayDidDismiss:)]) {
      [self.delegate omniboxOverlayDidDismiss:self];
    }
  }];
}

- (void)backdropClicked:(id)sender {
  [self dismiss];
}

- (void)shake {
  [_card shake];
}

@end
