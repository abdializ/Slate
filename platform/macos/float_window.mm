#import "float_window.h"
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#include <algorithm>

// ─── Private: Panel ─────────────────────────────────────────────────────────

@interface SlateFloatPanel : NSPanel
@end

// ─── Private: Line ──────────────────────────────────────────────────────────

/// How far through, along the bottom edge. Interactive scrubber line.
@interface SlateFloatLine : NSView
@property (nonatomic) double through;
@property (nonatomic) BOOL hovering;
@end

@implementation SlateFloatLine
- (void)setThrough:(double)through {
 _through = through;
 self.needsDisplay = YES;
}
- (void)setHovering:(BOOL)hovering {
 if (_hovering != hovering) {
  _hovering = hovering;
  self.needsDisplay = YES;
 }
}
- (void)drawRect:(NSRect)dirty {
 const CGFloat h = self.bounds.size.height;
 const CGFloat barH = _hovering ? 5.0 : 3.0;
 const NSRect barRect = NSMakeRect(0, (h - barH) / 2.0, self.bounds.size.width, barH);

 [[NSColor colorWithWhite:1 alpha:0.25] setFill];
 [[NSBezierPath bezierPathWithRoundedRect:barRect xRadius:barH/2.0 yRadius:barH/2.0] fill];

 const CGFloat filledW = self.bounds.size.width * std::max(0.0, std::min(1.0, _through));
 const NSRect filledRect = NSMakeRect(0, (h - barH) / 2.0, filledW, barH);
 [[NSColor colorWithWhite:1 alpha:0.92] setFill];
 [[NSBezierPath bezierPathWithRoundedRect:filledRect xRadius:barH/2.0 yRadius:barH/2.0] fill];

 if (_hovering && filledW > 0) {
  const CGFloat knobR = 5.0;
  const NSRect knobRect = NSMakeRect(filledW - knobR, (h / 2.0) - knobR, knobR * 2.0, knobR * 2.0);
  [[NSColor whiteColor] setFill];
  [[NSBezierPath bezierPathWithOvalInRect:knobRect] fill];
 }
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

// ─── Private: Controls ──────────────────────────────────────────────────────

@interface SlateFloatControls : NSView {
 NSButton* _closeBtn;
 NSButton* _backBtn;
 NSButton* _pauseBtn;
 NSButton* _rewindBtn;
 NSButton* _forwardBtn;
 CAGradientLayer* _scrim;
 SlateFloatLine* _line;
 BOOL _near;
 BOOL _scrubbing;
 // Moving
 NSPoint _grab;
 NSRect _origin;
 BOOL _stretching;
 // Flick
 CGVector _swipe;
 BOOL _flicked;
 NSDate* _lastWheelFlick;
 // Glide
 NSTimer* _glideTimer;
 NSPoint _glideFrom;
 NSPoint _glideTo;
 CFTimeInterval _glideStart;
 // Pinch
 CGFloat _pinching;
}
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onReturn)(void);
@property (nonatomic, copy) void (^onPlayPause)(void);
@property (nonatomic, copy) void (^onSkip)(double);
@property (nonatomic, copy) void (^onSeek)(double);
@property (nonatomic) BOOL playing;
@property (nonatomic) double progress;
@property (nonatomic, readonly) BOOL isScrubbing;
- (void)pressedClose;
- (void)pressedReturn;
- (void)pressedRewind;
- (void)pressedForward;
- (void)pressedPause;
@end

@implementation SlateFloatControls

- (instancetype)initWithFrame:(NSRect)frame {
 self = [super initWithFrame:frame];
 if (!self) return nil;
 self.wantsLayer = YES;

 // A wash at the top and bottom, so white buttons hold against a
 // bright frame of film without covering it.
 _scrim = [CAGradientLayer layer];
 _scrim.colors = @[
  (__bridge id)[NSColor colorWithWhite:0 alpha:0.45].CGColor,
  (__bridge id)[NSColor colorWithWhite:0 alpha:0].CGColor,
  (__bridge id)[NSColor colorWithWhite:0 alpha:0].CGColor,
  (__bridge id)[NSColor colorWithWhite:0 alpha:0.55].CGColor,
 ];
 _scrim.locations = @[@0, @0.28, @0.66, @1];
 _scrim.opacity = 0;
 [self.layer addSublayer:_scrim];

 _closeBtn = [self makeButton:@"xmark" size:11 round:15 action:@selector(pressedClose)];
 _closeBtn.toolTip = @"Close (Esc)";
 _backBtn = [self makeButton:@"arrow.up.forward" size:12 round:15 action:@selector(pressedReturn)];
 _backBtn.toolTip = @"Return to Tab (Return)";
 _rewindBtn = [self makeButton:@"gobackward.15" size:15 round:19 action:@selector(pressedRewind)];
 _rewindBtn.toolTip = @"Rewind 15s (←)";
 _pauseBtn = [self makeButton:@"pause.fill" size:17 round:25 action:@selector(pressedPause)];
 _pauseBtn.toolTip = @"Play / Pause (Space)";
 _forwardBtn = [self makeButton:@"goforward.15" size:15 round:19 action:@selector(pressedForward)];
 _forwardBtn.toolTip = @"Forward 15s (→)";

 _line = [[SlateFloatLine alloc] init];
 _line.alphaValue = 0;
 [self addSubview:_line];

 for (NSButton* b in [self allButtons]) b.alphaValue = 0;

 _lastWheelFlick = [NSDate distantPast];
 _playing = YES;

 return self;
}

- (BOOL)isScrubbing { return _scrubbing; }

- (NSArray<NSButton*>*)allButtons {
 return @[_closeBtn, _backBtn, _rewindBtn, _pauseBtn, _forwardBtn];
}

- (NSButton*)makeButton:(NSString*)symbol size:(CGFloat)size round:(CGFloat)round action:(SEL)action {
 NSButton* button = [[NSButton alloc] init];
 button.image = [self glyph:symbol size:size];
 button.bordered = NO;
 button.bezelStyle = NSBezelStyleRegularSquare;
 button.imagePosition = NSImageOnly;
 button.target = self;
 button.action = action;
 button.wantsLayer = YES;
 button.layer.backgroundColor = [NSColor colorWithWhite:0.1 alpha:0.60].CGColor;
 button.layer.cornerRadius = round;
 button.layer.borderWidth = 0.5;
 button.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.18].CGColor;
 [self addSubview:button];
 return button;
}

- (NSImage*)glyph:(NSString*)name size:(CGFloat)size {
 NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
 if (!image) return nil;
 NSImageSymbolConfiguration* cfg =
  [NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightMedium];
 NSImageSymbolConfiguration* palette =
  [NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor]];
 cfg = [cfg configurationByApplyingConfiguration:palette];
 return [image imageWithSymbolConfiguration:cfg];
}

- (void)setPlaying:(BOOL)playing {
 _playing = playing;
 _pauseBtn.image = [self glyph:(playing ? @"pause.fill" : @"play.fill") size:17];
}

- (void)setProgress:(double)progress {
 _progress = progress;
 _line.through = progress;
}

- (void)layout {
 [super layout];
 [CATransaction begin];
 [CATransaction setDisableActions:YES];
 _scrim.frame = self.bounds;
 [CATransaction commit];

 CGFloat w = self.bounds.size.width;
 CGFloat h = self.bounds.size.height;

 _closeBtn.frame = NSMakeRect(14, h - 44, 30, 30);
 _backBtn.frame = NSMakeRect(w - 44, h - 44, 30, 30);

 CGFloat middle = h / 2.0 - 25;
 _pauseBtn.frame = NSMakeRect(w / 2.0 - 25, middle, 50, 50);
 _rewindBtn.frame = NSMakeRect(w / 2.0 - 25 - 54, middle + 6, 38, 38);
 _forwardBtn.frame = NSMakeRect(w / 2.0 + 25 + 16, middle + 6, 38, 38);

 _line.frame = NSMakeRect(0, 0, w, 14);
}

- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 for (NSTrackingArea* area in self.trackingAreas) {
  [self removeTrackingArea:area];
 }
 NSTrackingArea* area = [[NSTrackingArea alloc]
  initWithRect:self.bounds
       options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect
         owner:self
      userInfo:nil];
 [self addTrackingArea:area];
}

- (BOOL)atProgressBar:(NSPoint)inside {
 return inside.y >= 0 && inside.y <= 16;
}

- (void)mouseMoved:(NSEvent *)event {
 NSPoint inside = [self convertPoint:event.locationInWindow fromView:nil];
 _line.hovering = [self atProgressBar:inside];
}

- (void)mouseEntered:(NSEvent *)event { [self fadeTo:1]; }
- (void)mouseExited:(NSEvent *)event {
 _line.hovering = NO;
 [self fadeTo:0];
}

- (void)fadeTo:(CGFloat)value {
 _near = value > 0;
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
  ctx.duration = 0.16;
  for (NSButton* b in [self allButtons]) b.animator.alphaValue = value;
  _line.animator.alphaValue = value;
 }];
 [CATransaction begin];
 [CATransaction setAnimationDuration:0.16];
 _scrim.opacity = (float)value;
 [CATransaction commit];
}

/// Everything reaches this layer.
- (NSView *)hitTest:(NSPoint)point {
 NSPoint inside = [self convertPoint:point fromView:self.superview];
 if (_near) {
  for (NSButton* b in [self allButtons]) {
   if (NSPointInRect(inside, b.frame)) return b;
  }
  if ([self atProgressBar:inside]) return self;
 }
 return self;
}

// MARK: - Moving and sizing

- (BOOL)atCorner:(NSPoint)point {
 return point.x > NSMaxX(self.bounds) - 22 && point.y < NSMinY(self.bounds) + 22;
}

- (void)resetCursorRects {
 [self addCursorRect:NSMakeRect(NSMaxX(self.bounds) - 22, NSMinY(self.bounds), 22, 22)
              cursor:[NSCursor crosshairCursor]];
}

- (void)mouseDown:(NSEvent *)event {
 if (!self.window) return;
 [self stopGlide];
 NSPoint inside = [self convertPoint:event.locationInWindow fromView:nil];

 // Scrub bar interaction
 if ([self atProgressBar:inside]) {
  _scrubbing = YES;
  _line.hovering = YES;
  double ratio = std::max(0.0, std::min(1.0, (double)inside.x / (double)self.bounds.size.width));
  _progress = ratio;
  _line.through = ratio;
  if (_onSeek) _onSeek(ratio);
  return;
 }

 // Double click to toggle size
 if (event.clickCount == 2 && ![self atCorner:inside]) {
  NSRect was = self.window.frame;
  CGFloat targetW = (was.size.width < 550) ? 660.0 : 440.0;
  [self resizeTo:targetW from:was around:[NSEvent mouseLocation] useAnchor:YES];
  return;
 }

 _grab = [NSEvent mouseLocation];
 _origin = self.window.frame;
 _stretching = [self atCorner:inside];
}

- (void)mouseDragged:(NSEvent *)event {
 if (!self.window) return;
 if (_scrubbing) {
  NSPoint inside = [self convertPoint:event.locationInWindow fromView:nil];
  double ratio = std::max(0.0, std::min(1.0, (double)inside.x / (double)self.bounds.size.width));
  _progress = ratio;
  _line.through = ratio;
  if (_onSeek) _onSeek(ratio);
  return;
 }

 NSPoint now = [NSEvent mouseLocation];
 CGFloat dx = now.x - _grab.x;
 CGFloat dy = now.y - _grab.y;

 if (!_stretching) {
  [self.window setFrameOrigin:NSMakePoint(_origin.origin.x + dx, _origin.origin.y + dy)];
  return;
 }
 [self resizeTo:_origin.size.width + dx from:_origin around:NSZeroPoint useAnchor:NO];
}

- (void)mouseUp:(NSEvent *)event {
 if (_scrubbing) {
  _scrubbing = NO;
  NSPoint inside = [self convertPoint:event.locationInWindow fromView:nil];
  double ratio = std::max(0.0, std::min(1.0, (double)inside.x / (double)self.bounds.size.width));
  _progress = ratio;
  _line.through = ratio;
  if (_onSeek) _onSeek(ratio);
  return;
 }
}

/// Two fingers on the trackpad move the window. There is nothing to
/// scroll here — the window holds one picture — so the gesture is free
/// to mean the thing you actually want it to mean.
- (void)scrollWheel:(NSEvent *)event {
 if (!self.window) return;
 if (event.momentumPhase != 0) return;
 if (SlateFloat.flicks) { [self flickWheel:event]; return; }

 CGFloat dx = event.scrollingDeltaX;
 CGFloat dy = event.scrollingDeltaY;
 if (dx == 0 && dy == 0) return;

 NSPoint spot = self.window.frame.origin;
 [self.window setFrameOrigin:NSMakePoint(spot.x + dx, spot.y - dy)];

 NSScreen* ground = NSScreen.screens.firstObject;
 if (!ground) return;
 NSPoint mouse = [NSEvent mouseLocation];
 CGWarpMouseCursorPosition(CGPointMake(
  mouse.x + dx,
  ground.frame.size.height - (mouse.y - dy)
 ));
 CGAssociateMouseAndMouseCursorPosition(1);
}

- (void)flickWheel:(NSEvent*)event {
 CGFloat sign = event.isDirectionInvertedFromDevice ? 1 : -1;
 CGVector step = CGVectorMake(sign * event.scrollingDeltaX, -sign * event.scrollingDeltaY);

 if (event.phase == 0) {
  if ([[NSDate date] timeIntervalSinceDate:_lastWheelFlick] > 0.4 && (step.dx != 0 || step.dy != 0)) {
   _lastWheelFlick = [NSDate date];
   [self flick:step];
  }
  return;
 }
 if (event.phase & NSEventPhaseBegan) {
  _swipe = CGVectorMake(0, 0);
  _flicked = NO;
 }
 _swipe.dx += step.dx;
 _swipe.dy += step.dy;
 BOOL lifted = (event.phase & NSEventPhaseEnded) || (event.phase & NSEventPhaseCancelled);
 CGFloat length = hypot(_swipe.dx, _swipe.dy);
 if (!_flicked && (length > 120 || (lifted && length > 20))) {
  _flicked = YES;
  [self flick:_swipe];
 }
 if (lifted) {
  _swipe = CGVectorMake(0, 0);
  _flicked = NO;
 }
}

- (void)flick:(CGVector)way {
 if (!self.window) return;
 NSRect area = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
 NSPoint target = [SlateFloat cornerForFrame:self.window.frame inArea:area toward:way margin:12];
 if (NSEqualPoints(target, self.window.frame.origin)) return;
 [self glideTo:target];
}

- (void)glideTo:(NSPoint)target {
 if (!self.window) return;
 _glideFrom = self.window.frame.origin;
 _glideTo = target;
 _glideStart = CACurrentMediaTime();
 if (!_glideTimer) {
  _glideTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/120.0
                                                target:self
                                              selector:@selector(glideStep)
                                              userInfo:nil
                                               repeats:YES];
 }
}

- (void)glideStep {
 if (!self.window) { [self stopGlide]; return; }
 CGFloat t = (CGFloat)(CACurrentMediaTime() - _glideStart);
 CGFloat omega = 15;
 BOOL done = t > 0.6;
 CGFloat p = done ? 1 : 1 - (1 + omega * t) * exp(-omega * t);
 [self.window setFrameOrigin:NSMakePoint(
  _glideFrom.x + (_glideTo.x - _glideFrom.x) * p,
  _glideFrom.y + (_glideTo.y - _glideFrom.y) * p
 )];
 if (done) [self stopGlide];
}

- (void)stopGlide {
 [_glideTimer invalidate];
 _glideTimer = nil;
}

/// A pinch sizes it about the pointer: whatever is under your fingers
/// stays under your fingers, and the rest grows away from it.
- (void)magnifyWithEvent:(NSEvent *)event {
 if (!self.window) return;
 if (event.phase == NSEventPhaseBegan) _pinching = 0;
 _pinching += event.magnification;
 if (fabs(_pinching) <= 0.02) return;
 CGFloat by = _pinching;
 _pinching = 0;
 [self resizeTo:self.window.frame.size.width * (1 + by)
           from:self.window.frame
         around:[NSEvent mouseLocation]
      useAnchor:YES];
}

- (void)resizeTo:(CGFloat)width from:(NSRect)was around:(NSPoint)anchor useAnchor:(BOOL)useAnchor {
 if (!self.window || was.size.width <= 0) return;
 CGFloat limit = (NSScreen.mainScreen.visibleFrame.size.width ?: 1600);
 CGFloat wide = MIN(MAX(self.window.minSize.width, width), limit * 0.85);
 CGFloat tall = wide * was.size.height / was.size.width;

 NSPoint spot;
 if (useAnchor) {
  CGFloat across = (anchor.x - NSMinX(was)) / was.size.width;
  CGFloat up = (anchor.y - NSMinY(was)) / was.size.height;
  spot = NSMakePoint(anchor.x - across * wide, anchor.y - up * tall);
 } else {
  spot = NSMakePoint(NSMinX(was), NSMaxY(was) - tall);
 }
 [self.window setFrame:NSMakeRect(spot.x, spot.y, wide, tall) display:NO];
}

- (void)pressedClose { if (_onClose) _onClose(); }
- (void)pressedReturn { if (_onReturn) _onReturn(); }
- (void)pressedRewind { if (_onSkip) _onSkip(-15); }
- (void)pressedForward { if (_onSkip) _onSkip(15); }
- (void)pressedPause {
 _playing = !_playing;
 _pauseBtn.image = [self glyph:(_playing ? @"pause.fill" : @"play.fill") size:17];
 if (_onPlayPause) _onPlayPause();
}

@end

// ─── Private: Panel Implementation ─────────────────────────────────────────

@implementation SlateFloatPanel
- (BOOL)canBecomeKey { return YES; }
- (BOOL)canBecomeMain { return NO; }

- (void)keyDown:(NSEvent *)event {
 SlateFloatControls* controls = nil;
 for (NSView* v in self.contentView.subviews) {
  if ([v isKindOfClass:[SlateFloatControls class]]) {
   controls = (SlateFloatControls*)v;
   break;
  }
 }
 if (controls) {
  switch (event.keyCode) {
   case 49: // Space
    [controls pressedPause];
    return;
   case 123: // Left Arrow
    [controls pressedRewind];
    return;
   case 124: // Right Arrow
    [controls pressedForward];
    return;
   case 53: // Escape
    [controls pressedClose];
    return;
   case 36: // Return
    [controls pressedReturn];
    return;
   default:
    break;
  }
 }
 [super keyDown:event];
}
@end

// ─── Known Players ──────────────────────────────────────────────────────────

typedef struct { const char* host; const char* path; } KnownSite;
static const KnownSite kSites[] = {
 {"youtube.com", NULL}, {"youtu.be", NULL}, {"netflix.com", NULL},
 {"primevideo.com", NULL}, {"amazon.com", "/gp/video"}, {"amazon.fr", "/gp/video"},
 {"amazon.co.uk", "/gp/video"}, {"amazon.de", "/gp/video"},
 {"disneyplus.com", NULL}, {"tv.apple.com", NULL}, {"twitch.tv", NULL},
 {"kick.com", NULL},
 {"vimeo.com", NULL}, {"dailymotion.com", NULL}, {"max.com", NULL}, {"hbomax.com", NULL},
 {"canalplus.com", NULL}, {"mycanal.fr", NULL}, {"arte.tv", NULL}, {"france.tv", NULL},
 {"tf1.fr", NULL}, {"6play.fr", NULL}, {"crunchyroll.com", NULL}, {"plex.tv", NULL},
 {"peacocktv.com", NULL}, {"hulu.com", NULL}, {"paramountplus.com", NULL},
 {"molotov.tv", NULL}, {"ocs.fr", NULL}, {"mubi.com", NULL}, {"criterionchannel.com", NULL},
 {"ted.com", NULL}, {"nebula.tv", NULL}, {"curiositystream.com", NULL},
};

@implementation SlateKnownPlayers

+ (BOOL)knowsURL:(NSURL *)url {
 if (!url) return NO;
 NSString* host = url.host.lowercaseString;
 NSString* path = url.path.lowercaseString;
 if (!host) return NO;

 for (size_t i = 0; i < sizeof(kSites) / sizeof(kSites[0]); i++) {
  NSString* siteHost = @(kSites[i].host);
  if (![host isEqualToString:siteHost] && ![host hasSuffix:[@"." stringByAppendingString:siteHost]])
   continue;
  if (!kSites[i].path) return YES;
  if ([path hasPrefix:@(kSites[i].path)]) return YES;
 }
 return NO;
}

@end

// ─── Isolate ────────────────────────────────────────────────────────────────

@implementation SlateIsolate

+ (NSString *)on {
 return @R"JS(
(function () {
  var videos = document.querySelectorAll('video');
  var best = null, area = 0;
  for (var i = 0; i < videos.length; i++) {
    var v = videos[i];
    if (v.paused || v.ended || v.readyState < 2) continue;
    var box = v.getBoundingClientRect();
    if (box.width < 160 || box.height < 90 ||
        v.closest('[class*="video-ad"], [id*="player-ads"], [data-ad]')) continue;
    if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
  }
  if (!best && videos.length > 0) {
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (v.closest && v.closest('[class*="video-ad"], [id*="player-ads"], [data-ad]')) continue;
      var box = v.getBoundingClientRect();
      if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
    }
    if (!best) best = videos[0];
  }
  if (!best) return 'none';

  best.setAttribute('data-office-float', '');
  var sheet = document.getElementById('office-float');
  if (!sheet) {
    sheet = document.createElement('style');
    sheet.id = 'office-float';
    (document.head || document.documentElement).appendChild(sheet);
  }
  sheet.textContent = [
    'html.office-floating, html.office-floating body {',
    'background:#000 !important; overflow:hidden !important; margin:0 !important}',
    'html.office-floating body > * { visibility:hidden !important }',
    'html.office-floating [data-office-float] {',
    'visibility:visible !important; position:fixed !important;',
    'left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;',
    'width:100vw !important; height:100vh !important;',
    'max-width:none !important; max-height:none !important;',
    'object-fit:contain !important; z-index:2147483647 !important}',
    'html.office-floating body :has([data-office-float]) {',
    'overflow:visible !important}',
    'html.office-floating [data-office-float]::-webkit-media-controls {',
    'display:none !important}'
  ].join('');
  document.documentElement.classList.add('office-floating');

  if (window.__officeFloatObserver) window.__officeFloatObserver.disconnect();
  if (window.__officeFloatPlayHandler)
    document.removeEventListener('play', window.__officeFloatPlayHandler, true);
  function reattach() {
    if (document.querySelector('video[data-office-float]')) return;
    var candidates = document.querySelectorAll('video');
    var next = null, largest = 0;
    for (var j = 0; j < candidates.length; j++) {
      var one = candidates[j];
      if (one.ended) continue;
      var box = one.getBoundingClientRect();
      if (one.closest && one.closest('[class*="video-ad"], [id*="player-ads"], [data-ad]')) continue;
      if (!one.paused && one.readyState >= 2) {
        if (box.width * box.height >= largest) { largest = box.width * box.height; next = one; }
      } else if (!next && box.width * box.height >= largest) {
        largest = box.width * box.height; next = one;
      }
    }
    if (!next && candidates.length > 0) next = candidates[0];
    if (next) next.setAttribute('data-office-float', '');
  }
  window.__officeFloatPlayHandler = reattach;
  document.addEventListener('play', reattach, true);
  window.__officeFloatObserver = new MutationObserver(reattach);
  window.__officeFloatObserver.observe(document.body || document.documentElement,
    {childList:true, subtree:true});

  return 'floating';
})();
)JS";
}

+ (NSString *)off {
 return @R"JS(
(function () {
  try {
    var out = document.querySelector('video[data-office-float]')
      || document.querySelector('video');
    if (out) {
      if (out.webkitPresentationMode === 'picture-in-picture') {
        out.webkitSetPresentationMode('inline');
      }
      if (document.pictureInPictureElement && document.exitPictureInPicture) {
        document.exitPictureInPicture();
      }
    }
  } catch (e) {}

  if (window.__officeFloatObserver) window.__officeFloatObserver.disconnect();
  window.__officeFloatObserver = null;
  if (window.__officeFloatPlayHandler)
    document.removeEventListener('play', window.__officeFloatPlayHandler, true);
  window.__officeFloatPlayHandler = null;
  document.documentElement.classList.remove('office-floating');
  var sheet = document.getElementById('office-float');
  if (sheet) sheet.textContent = '';
  var video = document.querySelector('[data-office-float]');
  if (video) video.removeAttribute('data-office-float');
  return 'landed';
})();
)JS";
}

+ (NSString *)toggle {
 return @R"JS(
(function () {
  var video = document.querySelector('[data-office-float]')
    || document.querySelector('video');
  if (!video) return true;
  if (video.paused) { video.play(); } else { video.pause(); }
  return !video.paused;
})();
)JS";
}

+ (NSString *)where_ {
 return @R"JS(
(function () {
  var video = document.querySelector('[data-office-float]')
    || document.querySelector('video');
  if (!video || !video.duration || !isFinite(video.duration)) return [0, true];
  return [video.currentTime / video.duration, !video.paused];
})();
)JS";
}

+ (NSString *)skip:(double)seconds {
 return [NSString stringWithFormat:@R"JS(
(function () {
  var video = document.querySelector('[data-office-float]')
    || document.querySelector('video');
  if (!video) return false;
  video.currentTime = Math.max(0, video.currentTime + (%g));
  return true;
})();
)JS", seconds];
}

+ (NSString *)seek:(double)ratio {
 return [NSString stringWithFormat:@R"JS(
(function () {
  var video = document.querySelector('[data-office-float]')
    || document.querySelector('video');
  if (!video || !video.duration || !isFinite(video.duration)) return false;
  video.currentTime = Math.max(0, Math.min(video.duration, video.duration * (%g)));
  return true;
})();
)JS", ratio];
}

@end

// ─── Float ──────────────────────────────────────────────────────────────────

static BOOL sFlicks = NO;

@implementation SlateFloat {
 SlateFloatPanel* _panel;
 SlateFloatControls* _controls;
 __weak NSView* _page;
 NSTimer* _ticker;
 NSMutableArray<id>* _keeping;
}

+ (BOOL)flicks { return sFlicks; }
+ (void)setFlicks:(BOOL)value { sFlicks = value; }

+ (NSPoint)cornerForFrame:(NSRect)frame inArea:(NSRect)area toward:(CGVector)way margin:(CGFloat)margin {
 CGFloat left = area.origin.x + margin;
 CGFloat right = NSMaxX(area) - margin - frame.size.width;
 CGFloat bottom = area.origin.y + margin;
 CGFloat top = NSMaxY(area) - margin - frame.size.height;
 CGFloat across = fabs(way.dx), up = fabs(way.dy);
 CGFloat x = way.dx > 0 ? right : left;
 CGFloat y = way.dy > 0 ? top : bottom;
 if (MIN(across, up) >= 0.4 * MAX(across, up)) return NSMakePoint(x, y);
 if (across >= up) return NSMakePoint(x, NSMidY(frame) > NSMidY(area) ? top : bottom);
 return NSMakePoint(NSMidX(frame) > NSMidX(area) ? right : left, y);
}

+ (NSPoint)cornerForFrame:(NSRect)frame inArea:(NSRect)area toward:(CGVector)way {
 return [self cornerForFrame:frame inArea:area toward:way margin:12];
}

- (BOOL)showing { return _panel != nil; }

- (void)lift:(NSView *)page {
 if (_panel) return;
 _page = page;

 NSSize size = NSMakeSize(440, 247);
 NSRect screen = (NSScreen.mainScreen.visibleFrame);
 NSRect spot = [SlateFloat remembered];
 if (NSIsEmptyRect(spot)) {
  spot = NSMakeRect(
   NSMaxX(screen) - size.width - 24,
   screen.origin.y + 24,
   size.width, size.height
  );
 }

 SlateFloatPanel* panel = [[SlateFloatPanel alloc]
  initWithContentRect:spot
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable | NSWindowStyleMaskNonactivatingPanel
              backing:NSBackingStoreBuffered
                defer:NO];
 panel.level = NSFloatingWindowLevel;
 panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
 panel.movableByWindowBackground = YES;
 panel.backgroundColor = NSColor.clearColor;
 panel.opaque = NO;
 panel.hasShadow = YES;
 panel.releasedWhenClosed = NO;
 panel.aspectRatio = size;
 panel.minSize = NSMakeSize(260, 146);

 // Remember position on resize-end and app-quit
 _keeping = [NSMutableArray array];
 __weak SlateFloatPanel* weakPanel = panel;
 void (^keep)(NSNotificationName, id) = ^(NSNotificationName name, id object) {
  id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:object queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
   SlateFloatPanel* p = weakPanel;
   if (p) [SlateFloat setRemembered:p.frame];
  }];
  [self->_keeping addObject:observer];
 };
 keep(NSWindowDidEndLiveResizeNotification, panel);
 keep(NSApplicationWillTerminateNotification, NSApp);

 NSView* ground = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
 ground.wantsLayer = YES;
 ground.layer.backgroundColor = NSColor.blackColor.CGColor;
 ground.layer.cornerRadius = 14;
 ground.layer.masksToBounds = YES;
 ground.layer.borderWidth = 0.5;
 ground.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.20].CGColor;
 if (@available(macOS 11.0, *)) {
  ground.layer.cornerCurve = kCACornerCurveContinuous;
 }

 // WebKit puts its own pinch recogniser on a web view, and a gesture
 // recogniser is consulted before the responder chain. With it left on,
 // every pinch aimed at this window went into zooming the page.
 if ([page isKindOfClass:[WKWebView class]]) {
  ((WKWebView*)page).allowsMagnification = NO;
 }

 [page removeFromSuperview];
 page.frame = ground.bounds;
 page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
 [ground addSubview:page];

 SlateFloatControls* controls = [[SlateFloatControls alloc] initWithFrame:ground.bounds];
 controls.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
 __weak SlateFloat* weakSelf = self;
 controls.onClose = ^{ if (weakSelf.onClose) weakSelf.onClose(); };
 controls.onReturn = ^{ if (weakSelf.onReturn) weakSelf.onReturn(); };
 controls.onPlayPause = ^{
  SlateFloat* s = weakSelf;
  if (s && s.onPlayPause) {
   s.onPlayPause(^(BOOL playing) {
    s->_controls.playing = playing;
   });
  }
 };
 controls.onSkip = ^(double seconds) {
  if (weakSelf.onSkip) weakSelf.onSkip(seconds);
 };
 controls.onSeek = ^(double ratio) {
  if (weakSelf.onSeek) weakSelf.onSeek(ratio);
 };
 [ground addSubview:controls];
 _controls = controls;

 panel.contentView = ground;
 panel.alphaValue = 0;
 [panel orderFrontRegardless];
 [panel.animator setAlphaValue:1.0];
 [panel invalidateShadow];
 _panel = panel;

 _ticker = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer* timer) {
  SlateFloat* s = weakSelf;
  if (!s) { [timer invalidate]; return; }

  // A window that no longer holds the page has nothing to show.
  // Something else took the page back.
  if (s->_page.superview != ground) {
   if (s.onClose) s.onClose();
   return;
  }

  if (s.onProgress) {
   s.onProgress(^(double through, BOOL playing) {
    if (!s->_controls.isScrubbing) {
     s->_controls.progress = through;
    }
    s->_controls.playing = playing;
   });
  }
 }];
}

/// The window's last place and size, kept across closing and quitting.
+ (NSRect)remembered {
 NSString* text = [NSUserDefaults.standardUserDefaults stringForKey:@"float.frame"];
 if (!text) return NSZeroRect;
 NSRect frame = NSRectFromString(text);
 if (frame.size.width <= 100) return NSZeroRect;
 for (NSScreen* screen in NSScreen.screens) {
  NSRect seen = NSIntersectionRect(screen.visibleFrame, frame);
  if (seen.size.width * seen.size.height > 0.6 * frame.size.width * frame.size.height) {
   return frame;
  }
 }
 return NSZeroRect;
}

+ (void)setRemembered:(NSRect)frame {
 [NSUserDefaults.standardUserDefaults setObject:NSStringFromRect(frame) forKey:@"float.frame"];
}

- (void)drop {
 if (!_panel) return;
 [SlateFloat setRemembered:_panel.frame];
 for (id observer in _keeping) {
  [NSNotificationCenter.defaultCenter removeObserver:observer];
 }
 [_keeping removeAllObjects];
 [_ticker invalidate];
 _ticker = nil;
 if ([_page isKindOfClass:[WKWebView class]]) {
  ((WKWebView*)_page).allowsMagnification = YES;
 }
 [_page removeFromSuperview];
 _page = nil;
 _controls = nil;
 [_panel orderOut:nil];
 [_panel close];
 _panel = nil;
}

@end
