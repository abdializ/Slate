// File purpose: Implements custom edge-disc back/forward trackpad swipe navigation, JS horizontal
// scroll arbitration, hold-to-pick history list scrubbing, and mouse side-button navigation.

#import "engine/swipe_navigation.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <cmath>

NSString* const kSlateSwipeScrollMessageName = @"slateSwipeScroll";

NSString* SlateSwipeWatchScript(void) {
  return @"(function () {\n"
          "  if (window.__slateSwipe) return;\n"
          "  window.__slateSwipe = true;\n"
          "  var was = null, said = 0;\n"
          "  var moved = new WeakMap(), at = new WeakMap();\n"
          "  function mark(el) {\n"
          "    var root = el === document.documentElement, vv = window.visualViewport;\n"
          "    var x = root ? (vv ? vv.pageLeft : window.scrollX) : el.scrollLeft;\n"
          "    var max = root ? document.documentElement.scrollWidth - (vv ? vv.width : window.innerWidth) : el.scrollWidth - el.clientWidth;\n"
          "    x = Math.max(0, Math.min(Math.max(0, max), x));\n"
          "    if (at.has(el) && Math.abs(at.get(el) - x) < 1) return;\n"
          "    at.set(el, x);\n"
          "    moved.set(el, Date.now());\n"
          "  }\n"
          "  window.addEventListener('scroll', function (e) {\n"
          "    var t = e.target;\n"
          "    mark(t === document || t === document.body ? document.documentElement : t);\n"
          "  }, { passive: true, capture: true });\n"
          "  if (window.visualViewport) {\n"
          "    window.visualViewport.addEventListener('scroll', function () { mark(document.documentElement); }, { passive: true });\n"
          "  }\n"
          "  var edges = [];\n"
          "  function rootCanScroll() {\n"
          "    var html = getComputedStyle(document.documentElement).overflowX;\n"
          "    var body = document.body ? getComputedStyle(document.body).overflowX : 'visible';\n"
          "    var effective = html === 'visible' ? body : html;\n"
          "    return effective !== 'hidden' && effective !== 'clip';\n"
          "  }\n"
          "  function taken(e) {\n"
          "    var el = e.target;\n"
          "    if (el && el.nodeType !== 1) el = el.parentElement;\n"
          "    while (el) {\n"
          "      var root = el === document.documentElement || el === document.body;\n"
          "      var can, left, max;\n"
          "      var vv = window.visualViewport;\n"
          "      if (root && vv && vv.scale > 1.01) {\n"
          "        can = true;\n"
          "        left = vv.pageLeft;\n"
          "        max = (rootCanScroll() ? document.documentElement.scrollWidth : document.documentElement.clientWidth) - vv.width;\n"
          "      } else if (root) {\n"
          "        can = rootCanScroll();\n"
          "        left = window.scrollX || 0;\n"
          "        max = document.documentElement.scrollWidth - window.innerWidth;\n"
          "      } else {\n"
          "        var ox = getComputedStyle(el).overflowX;\n"
          "        can = ox === 'auto' || ox === 'scroll';\n"
          "        left = el.scrollLeft;\n"
          "        max = el.scrollWidth - el.clientWidth;\n"
          "      }\n"
          "      if (can && max > 1) {\n"
          "        if (e.deltaX > 0 ? left < max - 1 : left > 1) return true;\n"
          "        edges.push(root ? document.documentElement : el);\n"
          "      }\n"
          "      el = el.parentElement;\n"
          "    }\n"
          "    return false;\n"
          "  }\n"
          "  function resting(list) {\n"
          "    var now = Date.now();\n"
          "    return list.every(function (el) { return now - (moved.get(el) || 0) > 400; });\n"
          "  }\n"
          "  function say(t) {\n"
          "    var now = Date.now();\n"
          "    if (t === was && now - said < 100) return;\n"
          "    was = t; said = now;\n"
          "    try {\n"
          "      window.webkit.messageHandlers.slateSwipeScroll.postMessage({ side: t ? 'taken' : 'free' });\n"
          "    } catch (_) {}\n"
          "  }\n"
          "  window.addEventListener('wheel', function (e) {\n"
          "    if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;\n"
          "    edges = [];\n"
          "    if (taken(e)) return say(true);\n"
          "    var those = edges;\n"
          "    setTimeout(function () { say(e.defaultPrevented || !resting(those)); }, 50);\n"
          "  }, { passive: true, capture: true });\n"
          "})();\n";
}

NSString* SlateSwipeHeardScript(void) {
  return @"await new Promise(function (done) { setTimeout(done, 80); }); return true;";
}

@interface SlateSwipeStop : NSObject
@property(nonatomic, copy) NSString* title;
@property(nonatomic, strong) NSURL* url;
@end

@implementation SlateSwipeStop
@end

@interface SlateSwipePull : NSObject
@property(nonatomic) BOOL back;
@property(nonatomic) CGFloat travel;
@property(nonatomic) BOOL armed;
@property(nonatomic) BOOL going;
@property(nonatomic, copy, nullable) NSArray<SlateSwipeStop*>* stops;
@property(nonatomic) NSInteger picked;
@end

@implementation SlateSwipePull
@end

// MARK: - Floating Edge Disc & History List Overlay

@interface SlateSwipeOverlayView : NSView
@property(nonatomic, strong, nullable) SlateSwipePull* pull;
@property(nonatomic, strong) NSView* discView;
@property(nonatomic, strong) CAShapeLayer* ringLayer;
@property(nonatomic, strong) NSImageView* arrowView;
@property(nonatomic, strong) NSView* listCard;
@property(nonatomic, strong) NSMutableArray<NSView*>* listRows;
@property(nonatomic, strong) NSMutableArray<NSTextField*>* listLabels;
@property(nonatomic) BOOL listBuiltForBack;
@property(nonatomic) NSUInteger listBuiltCount;
@end

static constexpr CGFloat kDiscSize = 52.0;
static constexpr CGFloat kListWidth = 240.0;
static constexpr CGFloat kListRowHeight = 28.0;
static constexpr CGFloat kListRowGap = 2.0;
static constexpr CGFloat kListPitch = kListRowHeight + kListRowGap;
static constexpr CGFloat kListPad = 5.0;
static constexpr CGFloat kSwipeArm = 70.0;

@implementation SlateSwipeOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    self.layer.masksToBounds = NO;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.hidden = YES;

    _discView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kDiscSize, kDiscSize)];
    _discView.wantsLayer = YES;
    _discView.layer.cornerRadius = kDiscSize / 2.0;
    _discView.layer.masksToBounds = NO;
    _discView.layer.borderWidth = 1.0;
    _discView.layer.shadowColor = NSColor.blackColor.CGColor;
    _discView.layer.shadowOpacity = 0.16f;
    _discView.layer.shadowRadius = 14.0;
    _discView.layer.shadowOffset = CGSizeMake(0, -5);
    _discView.alphaValue = 0.0;
    [self addSubview:_discView];

    _ringLayer = [CAShapeLayer layer];
    _ringLayer.fillColor = NSColor.clearColor.CGColor;
    _ringLayer.lineWidth = 1.75;
    _ringLayer.lineCap = kCALineCapRound;
    _ringLayer.strokeStart = 0.0;
    _ringLayer.strokeEnd = 0.0;
    CGFloat radius = (kDiscSize / 2.0) - 1.25;
    CGMutablePathRef ringPath = CGPathCreateMutable();
    // In non-flipped AppKit CALayer coordinates, +Y is up, so start at top (+pi/2) clockwise.
    CGPathAddArc(ringPath, NULL, kDiscSize / 2.0, kDiscSize / 2.0, radius, M_PI_2, M_PI_2 - 2.0 * M_PI, true);
    _ringLayer.path = ringPath;
    CGPathRelease(ringPath);
    [_discView.layer addSublayer:_ringLayer];

    _arrowView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, kDiscSize, kDiscSize)];
    _arrowView.imageAlignment = NSImageAlignCenter;
    _arrowView.imageScaling = NSImageScaleNone;
    [_discView addSubview:_arrowView];

    _listCard = [[NSView alloc] initWithFrame:NSZeroRect];
    _listCard.wantsLayer = YES;
    _listCard.layer.cornerRadius = 12.0;
    if (@available(macOS 11.0, *)) {
      _listCard.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _listCard.layer.borderWidth = 1.0;
    _listCard.layer.shadowColor = NSColor.blackColor.CGColor;
    _listCard.layer.shadowOpacity = 0.18f;
    _listCard.layer.shadowRadius = 18.0;
    _listCard.layer.shadowOffset = CGSizeMake(0, -6);
    _listCard.hidden = YES;
    _listCard.alphaValue = 0.0;
    [self addSubview:_listCard];

    _listRows = [NSMutableArray array];
    _listLabels = [NSMutableArray array];
  }
  return self;
}

- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

- (BOOL)isDark {
  NSAppearance* app = self.effectiveAppearance ?: NSApp.effectiveAppearance;
  return [[app bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]]
      isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSColor*)groundColor {
  return [self isDark]
      ? [NSColor colorWithCalibratedRed:0.15 green:0.15 blue:0.16 alpha:0.96]
      : [NSColor colorWithCalibratedRed:0.99 green:0.99 blue:0.99 alpha:0.97];
}

- (NSColor*)hairlineColor {
  return [self isDark]
      ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.14]
      : [NSColor colorWithCalibratedWhite:0.0 alpha:0.10];
}

- (NSColor*)inkColor {
  return [self isDark]
      ? [NSColor colorWithCalibratedWhite:0.96 alpha:1.0]
      : [NSColor colorWithCalibratedWhite:0.10 alpha:1.0];
}

- (void)rebuildListRowsForStops:(NSArray<SlateSwipeStop*>*)stops {
  for (NSView* v in self.listRows) [v removeFromSuperview];
  [self.listRows removeAllObjects];
  [self.listLabels removeAllObjects];

  NSUInteger count = stops.count;
  CGFloat totalHeight = kListPad * 2.0 + count * kListRowHeight + (count > 0 ? (count - 1) * kListRowGap : 0);
  self.listCard.frame = NSMakeRect(0, 0, kListWidth, totalHeight);

  NSImage* globe = nil;
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular];
    globe = [[NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:@""] imageWithSymbolConfiguration:cfg];
  }

  for (NSUInteger i = 0; i < count; ++i) {
    SlateSwipeStop* stop = stops[i];
    // Top-to-bottom ordering in non-flipped AppKit coordinates.
    CGFloat y = totalHeight - kListPad - (i + 1) * kListRowHeight - i * kListRowGap;
    NSView* row = [[NSView alloc] initWithFrame:NSMakeRect(kListPad, y, kListWidth - kListPad * 2.0, kListRowHeight)];
    row.wantsLayer = YES;
    row.layer.cornerRadius = 7.0;
    if (@available(macOS 11.0, *)) {
      row.layer.cornerCurve = kCACornerCurveContinuous;
    }

    NSImageView* iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(9, (kListRowHeight - 14) / 2.0, 14, 14)];
    iconView.image = globe;
    iconView.contentTintColor = [[self inkColor] colorWithAlphaComponent:0.55];
    [row addSubview:iconView];

    NSString* text = stop.title.length > 0 ? stop.title : (stop.url.host.length > 0 ? stop.url.host : stop.url.absoluteString);
    NSTextField* label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    label.frame = NSMakeRect(31, (kListRowHeight - 16) / 2.0, kListWidth - kListPad * 2.0 - 40, 16);
    [row addSubview:label];

    [self.listCard addSubview:row];
    [self.listRows addObject:row];
    [self.listLabels addObject:label];
  }
}

- (void)updateWithPull:(nullable SlateSwipePull*)pull {
  SlateSwipePull* previous = self.pull;
  self.pull = pull;

  if (!pull) {
    if (!previous) {
      self.hidden = YES;
      return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
      ctx.duration = 0.16;
      ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
      self.discView.animator.alphaValue = 0.0;
      self.listCard.animator.alphaValue = 0.0;
    } completionHandler:^{
      if (!self.pull) {
        self.hidden = YES;
        self.listCard.hidden = YES;
      }
    }];
    return;
  }

  self.hidden = NO;
  NSColor* ground = [self groundColor];
  NSColor* hairline = [self hairlineColor];
  NSColor* ink = [self inkColor];

  CGFloat reach = 150.0 * (1.0 - std::exp(-pull.travel / 110.0));
  CGFloat grown = MIN(1.0, pull.travel / kSwipeArm);
  CGFloat boundsW = NSWidth(self.bounds);
  CGFloat boundsH = NSHeight(self.bounds);

  if (pull.stops.count >= 2) {
    BOOL needsRebuild = self.listCard.hidden || self.listBuiltForBack != pull.back || self.listBuiltCount != pull.stops.count;
    if (needsRebuild) {
      [self rebuildListRowsForStops:pull.stops];
      self.listBuiltForBack = pull.back;
      self.listBuiltCount = pull.stops.count;
    }
    self.discView.alphaValue = 0.0;
    self.listCard.hidden = NO;
    self.listCard.layer.backgroundColor = ground.CGColor;
    self.listCard.layer.borderColor = hairline.CGColor;

    NSUInteger count = pull.stops.count;
    for (NSUInteger i = 0; i < count && i < self.listRows.count; ++i) {
      BOOL selected = ((NSInteger)i == pull.picked);
      self.listRows[i].layer.backgroundColor = selected ? [ink colorWithAlphaComponent:0.11].CGColor : NSColor.clearColor.CGColor;
      self.listLabels[i].textColor = selected ? ink : [ink colorWithAlphaComponent:0.72];
    }

    CGFloat insetX = 10.0 + reach * 0.2;
    CGFloat x = pull.back ? insetX : (boundsW - kListWidth - insetX);
    CGFloat cardH = NSHeight(self.listCard.frame);
    // Keep the picked row vertically centered in the view.
    CGFloat pickedOffsetFromCenter = ((CGFloat)pull.picked - ((CGFloat)count - 1.0) / 2.0) * kListPitch;
    CGFloat y = (boundsH - cardH) / 2.0 + pickedOffsetFromCenter;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
      ctx.duration = pull.going ? 0.22 : (needsRebuild ? 0.14 : 0.12);
      ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
      self.listCard.animator.frame = NSMakeRect(round(x), round(y), kListWidth, cardH);
      self.listCard.animator.alphaValue = pull.going ? 0.0 : 1.0;
    } completionHandler:nil];
    return;
  }

  // Disc mode
  self.listCard.hidden = YES;
  self.listCard.alphaValue = 0.0;

  self.discView.layer.backgroundColor = ground.CGColor;
  self.discView.layer.borderColor = hairline.CGColor;

  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightSemibold];
    NSString* sym = pull.back ? @"arrow.left" : @"arrow.right";
    self.arrowView.image = [[NSImage imageWithSystemSymbolName:sym accessibilityDescription:@""] imageWithSymbolConfiguration:cfg];
  }
  self.arrowView.contentTintColor = [ink colorWithAlphaComponent:0.40 + 0.60 * grown];

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.ringLayer.strokeColor = ink.CGColor;
  self.ringLayer.strokeEnd = grown;
  [CATransaction commit];

  CGFloat scale = pull.going ? 1.08 : (0.86 + 0.14 * grown);
  CGFloat insetX = 10.0 + reach * 0.2 + (pull.going ? 12.0 : 0.0);
  CGFloat x = pull.back ? insetX : (boundsW - kDiscSize - insetX);
  CGFloat y = (boundsH - kDiscSize) / 2.0;

  if (pull.going) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
      ctx.duration = 0.22;
      ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
      self.discView.animator.frame = NSMakeRect(round(x), round(y), kDiscSize, kDiscSize);
      self.discView.animator.alphaValue = 0.0;
    } completionHandler:nil];
  } else {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.discView.frame = NSMakeRect(round(x), round(y), kDiscSize, kDiscSize);
    self.discView.layer.anchorPoint = CGPointMake(0.5, 0.5);
    self.discView.layer.position = CGPointMake(NSMidX(self.discView.frame), NSMidY(self.discView.frame));
    self.discView.layer.transform = CATransform3DMakeScale(scale, scale, 1.0);
    [CATransaction commit];
    if (self.discView.alphaValue < 0.99) {
      [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
        ctx.duration = 0.12;
        self.discView.animator.alphaValue = 1.0;
      } completionHandler:nil];
    }
  }
}

@end

// MARK: - SlateSwipeWebView

typedef NS_ENUM(NSInteger, SlateSwipeAxis) {
  SlateSwipeAxisNone = 0,
  SlateSwipeAxisAcross = 1,
  SlateSwipeAxisDown = 2,
};

static constexpr CGFloat kSwipeShow = 6.0;
static constexpr CGFloat kSwipeFlick = 30.0;
static constexpr NSTimeInterval kSwipeFlickTime = 0.25;
static constexpr NSTimeInterval kSwipeHoldTime = 0.45;
static constexpr CGFloat kSwipeListStep = 22.0;

@implementation SlateSwipeWebView {
  SlateSwipeOverlayView* _overlay;
  CGFloat _sideways;
  CGFloat _gatheredX;
  CGFloat _gatheredY;
  SlateSwipeAxis _axis;
  BOOL _back;
  NSNumber* _free; // nil = unknown, @YES = free, @NO = taken
  NSDate* _asked;
  BOOL _spent;
  BOOL _refused;
  NSDate* _lastTaken;
  BOOL _armedNow;
  BOOL _showing;
  BOOL _going;
  BOOL _went;
  NSUInteger _pulls;
  dispatch_block_t _holdingBlock;
  NSArray<SlateSwipeStop*>* _stops;
  NSArray<WKBackForwardListItem*>* _items;
  NSInteger _picked;
  CGFloat _climbed;
}

- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration*)configuration {
  self = [super initWithFrame:frame configuration:configuration];
  if (self) {
    self.allowsBackForwardNavigationGestures = NO;
    _overlay = [[SlateSwipeOverlayView alloc] initWithFrame:self.bounds];
    [self addSubview:_overlay];
    [self calmHorizontalRubberBanding];
  }
  return self;
}

- (void)calmHorizontalRubberBanding {
  SEL sel = NSSelectorFromString(@"_setRubberBandingEnabled:");
  if (![self respondsToSelector:sel]) return;
  // _WKRectEdge bitmask: Left=1<<0, Top=1<<1, Right=1<<2, Bottom=1<<3.
  // Keep vertical bounce; only allow horizontal bounce when pinched in.
  const NSUInteger left = 1u << 0;
  const NSUInteger top = 1u << 1;
  const NSUInteger right = 1u << 2;
  const NSUInteger bottom = 1u << 3;
  const NSUInteger sides = (self.magnification > 1.0) ? (left | right) : 0u;
  const NSUInteger mask = sides | top | bottom;
  ((void (*)(id, SEL, NSUInteger))objc_msgSend)(self, sel, mask);
}

- (void)waitForNextPresentationWithin:(NSTimeInterval)timeout completion:(dispatch_block_t)completion {
  if (!completion) return;
  __block BOOL done = NO;
  dispatch_block_t once = ^{
    if (done) return;
    done = YES;
    completion();
  };
  SEL sel = NSSelectorFromString(@"_doAfterNextPresentationUpdate:");
  if (![self respondsToSelector:sel]) {
    once();
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    once();
  });
  dispatch_block_t cb = ^{
    dispatch_async(dispatch_get_main_queue(), once);
  };
  ((void (*)(id, SEL, dispatch_block_t))objc_msgSend)(self, sel, cb);
}

// Mouse side buttons 3 (Back) and 4 (Forward)
- (void)otherMouseDown:(NSEvent*)event {
  if (event.buttonNumber == 3 && self.canGoBack) {
    if (self.onWillNavigate) self.onWillNavigate();
    [self goBack];
    return;
  }
  if (event.buttonNumber == 4 && self.canGoForward) {
    if (self.onWillNavigate) self.onWillNavigate();
    [self goForward];
    return;
  }
  [super otherMouseDown:event];
}

// Logi Options+ and 3-finger swipe events
- (void)swipeWithEvent:(NSEvent*)event {
  if (event.deltaX > 0 && self.canGoBack) {
    if (self.onWillNavigate) self.onWillNavigate();
    [self goBack];
    return;
  }
  if (event.deltaX < 0 && self.canGoForward) {
    if (self.onWillNavigate) self.onWillNavigate();
    [self goForward];
    return;
  }
  [super swipeWithEvent:event];
}

- (void)settlePull:(nullable SlateSwipePull*)pull {
  _showing = (pull != nil);
  if (_overlay.superview == self) {
    // Keep overlay above any dynamically added WebKit subviews.
    [self addSubview:_overlay positioned:NSWindowAbove relativeTo:nil];
  }
  [_overlay updateWithPull:pull];
}

- (CGFloat)currentTravel {
  return MAX(0.0, _back ? _sideways : -_sideways);
}

- (void)cancelHolding {
  if (_holdingBlock) {
    dispatch_block_cancel(_holdingBlock);
    _holdingBlock = nil;
  }
}

- (void)scrollWheel:(NSEvent*)event {
  if (event.phase == NSEventPhaseMayBegin || event.phase == NSEventPhaseBegan) {
    _went = NO;
    [self calmHorizontalRubberBanding];
  }
  if (_went && event.momentumPhase != NSEventPhaseNone) {
    return;
  }
  if (!_stops || event.phase == NSEventPhaseEnded || event.phase == NSEventPhaseCancelled) {
    [super scrollWheel:event];
  }
  if (event.momentumPhase != NSEventPhaseNone) return;
  if (![NSEvent isSwipeTrackingFromScrollEventsEnabled]) return;

  switch (event.phase) {
    case NSEventPhaseMayBegin:
    case NSEventPhaseBegan: {
      _sideways = 0;
      _gatheredX = 0;
      _gatheredY = 0;
      _axis = SlateSwipeAxisNone;
      _free = nil;
      _asked = nil;
      _spent = NO;
      _refused = (_lastTaken && [[NSDate date] timeIntervalSinceDate:_lastTaken] < 0.15);
      _armedNow = NO;
      _showing = NO;
      [self cancelHolding];
      _stops = nil;
      _items = nil;
      _pulls += 1;
      if (_going) {
        _going = NO;
        [self settlePull:nil];
      }
      break;
    }
    case NSEventPhaseChanged: {
      if (_spent) return;
      if (_axis == SlateSwipeAxisNone) {
        _gatheredX += fabs(event.scrollingDeltaX);
        _gatheredY += fabs(event.scrollingDeltaY);
        _sideways += event.scrollingDeltaX;
        if (_gatheredX + _gatheredY <= 6.0) return;
        _axis = (_gatheredX > _gatheredY * 1.3) ? SlateSwipeAxisAcross : SlateSwipeAxisDown;
        if (_axis == SlateSwipeAxisDown) {
          _spent = YES;
          return;
        }
        _back = (_sideways > 0);
        if (_refused || (_back ? !self.canGoBack : !self.canGoForward)) {
          _spent = YES;
          return;
        }
        _asked = [NSDate date];
        [self tellOverlay];
        return;
      }
      _sideways += event.scrollingDeltaX;
      if (_stops) {
        [self climbListWithEvent:event];
      }
      [self tellOverlay];
      break;
    }
    case NSEventPhaseEnded: {
      [self releaseGesture];
      break;
    }
    case NSEventPhaseCancelled: {
      _spent = YES;
      [self cancelHolding];
      [self settlePull:nil];
      break;
    }
    default:
      break;
  }
}

- (void)handleSwipeScrollAnswerFree:(BOOL)isFree {
  if (!isFree) {
    _lastTaken = [NSDate date];
    if (_axis != SlateSwipeAxisDown) {
      _refused = YES;
    }
  }
  if (_axis == SlateSwipeAxisDown || _spent) return;
  if (!isFree) {
    _free = @NO;
    _spent = YES;
    [self cancelHolding];
    [self settlePull:nil];
    return;
  }
  if (_free != nil) return;
  _free = @YES;
  [self tellOverlay];
}

- (void)tellOverlay {
  if (!_free && _asked && [[NSDate date] timeIntervalSinceDate:_asked] > 0.18) {
    // Pages that cannot answer (PDFs, error pages, about:blank) still allow swiping.
    _free = @YES;
  }
  if (!_free || !_free.boolValue) return;

  CGFloat travel = [self currentTravel];
  if (travel < kSwipeShow) {
    if (_showing) [self settlePull:nil];
    return;
  }

  BOOL armed = (travel >= kSwipeArm);
  if (!_stops && armed != _armedNow) {
    [self cancelHolding];
    if (armed) {
      __weak SlateSwipeWebView* weakSelf = self;
      _holdingBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        [weakSelf openHistoryList];
      });
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSwipeHoldTime * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), _holdingBlock);
    }
    [[NSHapticFeedbackManager defaultPerformer]
        performFeedbackPattern:(armed ? NSHapticFeedbackPatternLevelChange : NSHapticFeedbackPatternAlignment)
               performanceTime:NSHapticFeedbackPerformanceTimeNow];
  }
  _armedNow = armed;

  SlateSwipePull* pull = [[SlateSwipePull alloc] init];
  pull.back = _back;
  pull.travel = travel;
  pull.armed = armed;
  pull.going = NO;
  pull.stops = _stops;
  pull.picked = _picked;
  [self settlePull:pull];
}

- (void)openHistoryList {
  _holdingBlock = nil;
  if (_spent || !_armedNow || _stops) return;

  NSArray<WKBackForwardListItem*>* raw = _back ? self.backForwardList.backList : self.backForwardList.forwardList;
  if (raw.count < 2) return;

  NSArray<WKBackForwardListItem*>* slice = nil;
  if (_back) {
    NSUInteger len = MIN((NSUInteger)8, raw.count);
    slice = [raw subarrayWithRange:NSMakeRange(raw.count - len, len)];
  } else {
    NSUInteger len = MIN((NSUInteger)8, raw.count);
    slice = [raw subarrayWithRange:NSMakeRange(0, len)];
  }
  _items = slice;
  NSMutableArray<SlateSwipeStop*>* stops = [NSMutableArray arrayWithCapacity:slice.count];
  for (WKBackForwardListItem* item in slice) {
    SlateSwipeStop* stop = [[SlateSwipeStop alloc] init];
    stop.title = item.title ?: @"";
    stop.url = item.URL;
    [stops addObject:stop];
  }
  _stops = stops;
  _picked = _back ? ((NSInteger)slice.count - 1) : 0;
  _climbed = 0;

  [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternLevelChange
                                                     performanceTime:NSHapticFeedbackPerformanceTimeNow];
  [self tellOverlay];
}

- (void)climbListWithEvent:(NSEvent*)event {
  if (!_stops.count) return;
  CGFloat sign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0;
  _climbed += -sign * event.scrollingDeltaY;
  BOOL moved = NO;
  while (_climbed >= kSwipeListStep && _picked < (NSInteger)_stops.count - 1) {
    _picked += 1;
    _climbed -= kSwipeListStep;
    moved = YES;
  }
  while (_climbed <= -kSwipeListStep && _picked > 0) {
    _picked -= 1;
    _climbed += kSwipeListStep;
    moved = YES;
  }
  _climbed = MAX(-kSwipeListStep, MIN(kSwipeListStep, _climbed));
  if (moved) {
    [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternAlignment
                                                       performanceTime:NSHapticFeedbackPerformanceTimeNow];
  }
}

- (void)releaseGesture {
  BOOL wasSpent = _spent;
  _spent = YES;
  [self cancelHolding];

  CGFloat travel = [self currentTravel];
  BOOL flicked = !wasSpent && _free.boolValue && travel >= kSwipeFlick &&
      (_asked && [[NSDate date] timeIntervalSinceDate:_asked] <= kSwipeFlickTime);
  if (wasSpent || !_free.boolValue || (!_armedNow && !flicked && !_stops)) {
    [self settlePull:nil];
    return;
  }

  _went = YES;
  NSUInteger gesture = _pulls;
  __weak SlateSwipeWebView* weakSelf = self;
  [self waitUntilPageHeard:^{
    SlateSwipeWebView* strongSelf = weakSelf;
    if (!strongSelf || strongSelf->_pulls != gesture) return;
    if (strongSelf->_refused) {
      strongSelf->_went = NO;
      [strongSelf settlePull:nil];
      return;
    }
    [strongSelf commitNavigation];
  }];
}

- (void)commitNavigation {
  _going = YES;
  SlateSwipePull* pull = [[SlateSwipePull alloc] init];
  pull.back = _back;
  pull.travel = [self currentTravel];
  pull.armed = YES;
  pull.going = YES;
  pull.stops = _stops;
  pull.picked = _picked;
  [self settlePull:pull];

  if (self.onWillNavigate) self.onWillNavigate();

  if (_stops && _picked >= 0 && _picked < (NSInteger)_items.count) {
    WKBackForwardListItem* item = _items[_picked];
    [self goToBackForwardListItem:item];
  } else if (_back) {
    [self goBack];
  } else {
    [self goForward];
  }

  _pulls += 1;
  NSUInteger mine = _pulls;
  __weak SlateSwipeWebView* weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.32 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    SlateSwipeWebView* strongSelf = weakSelf;
    if (!strongSelf || strongSelf->_pulls != mine) return;
    strongSelf->_going = NO;
    [strongSelf settlePull:nil];
  });
}

- (void)waitUntilPageHeard:(dispatch_block_t)then {
  __block BOOL done = NO;
  dispatch_block_t finish = ^{
    if (done) return;
    done = YES;
    then();
  };
  if (@available(macOS 11.0, *)) {
    [self callAsyncJavaScript:SlateSwipeHeardScript()
                    arguments:@{}
                      inFrame:nil
               inContentWorld:[WKContentWorld defaultClientWorld]
            completionHandler:^(id _Nullable result, NSError* _Nullable error) {
              (void)result;
              (void)error;
              dispatch_async(dispatch_get_main_queue(), finish);
            }];
  } else {
    finish();
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), finish);
}

@end
