// File purpose: Implements temporary zoom feedback and the download-arrival visual effect.

#import "interaction_feedback.h"
#import <QuartzCore/QuartzCore.h>
#include <cmath>

@implementation SlateZoomIndicator {
 NSTextField* _value;
 NSButton* _reset;
 NSImageView* _icon;
 NSTimer* _dismissTimer;
 int _percent;
}
- (instancetype)init {
 if((self=[super initWithFrame:NSMakeRect(0,0,160,46)])) {
  self.material=NSVisualEffectMaterialPopover;
  self.blendingMode=NSVisualEffectBlendingModeWithinWindow;
  self.state=NSVisualEffectStateActive;
  self.wantsLayer=YES;
  self.layer.cornerRadius=14;
  self.layer.borderWidth=0.5;
  self.layer.borderColor=[NSColor.separatorColor colorWithAlphaComponent:0.6].CGColor;
  self.layer.shadowColor=NSColor.blackColor.CGColor;
  self.layer.shadowOpacity=0.14;
  self.layer.shadowRadius=10;
  self.layer.shadowOffset=CGSizeMake(0,-3);
  _icon=[[NSImageView alloc] initWithFrame:NSMakeRect(14,13,20,20)];
  _icon.contentTintColor=NSColor.secondaryLabelColor;
  [self addSubview:_icon];
  _value=[NSTextField labelWithString:@"100%"];
  _value.frame=NSMakeRect(44,12,67,23);
  _value.font=[NSFont monospacedDigitSystemFontOfSize:17 weight:NSFontWeightSemibold];
  _value.textColor=NSColor.labelColor;
  [self addSubview:_value];
  _reset=[[NSButton alloc] initWithFrame:NSMakeRect(117,9,30,28)];
  _reset.bordered=NO;
  _reset.image=[NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:@"Reset zoom to 100 percent"];
  _reset.contentTintColor=NSColor.secondaryLabelColor;
  _reset.toolTip=@"Reset zoom · ⌘0";
  _reset.accessibilityLabel=@"Reset zoom to 100 percent";
  [self addSubview:_reset];
 }
 return self;
}
- (int)percent { return _percent; }
- (void)showPercent:(int)percent inView:(NSView*)host target:(id)target action:(SEL)action {
 [_dismissTimer invalidate];
 const BOOL entering=self.superview!=host;
 [self.layer removeAllAnimations];
 _percent=percent;
 _value.stringValue=[NSString stringWithFormat:@"%d%%",percent];
 _value.accessibilityLabel=[NSString stringWithFormat:@"Page zoom %d percent",percent];
 _icon.image=[NSImage imageWithSystemSymbolName:percent<100 ? @"minus.magnifyingglass" : @"plus.magnifyingglass" accessibilityDescription:@"Page zoom"];
 _reset.target=target; _reset.action=action;
 const CGFloat inset=12;
 const CGFloat x=MAX(inset,NSWidth(host.bounds)-NSWidth(self.frame)-inset);
 const CGFloat y=host.isFlipped ? inset : MAX(inset,NSHeight(host.bounds)-NSHeight(self.frame)-inset);
 self.frame=NSMakeRect(x,y,160,46);
 self.autoresizingMask=NSViewMinXMargin | (host.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin);
 if(entering) {
  [self removeFromSuperview];
  [host addSubview:self positioned:NSWindowAbove relativeTo:nil];
  CABasicAnimation* fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
  fade.fromValue=@0; fade.toValue=@1; fade.duration=0.16;
  [self.layer addAnimation:fade forKey:@"appear"];
  if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
   CABasicAnimation* scale=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
   scale.fromValue=@0.94; scale.toValue=@1; scale.duration=0.18;
   scale.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
   [self.layer addAnimation:scale forKey:@"settle"];
  }
 }
 NSAccessibilityPostNotificationWithUserInfo(NSApp,NSAccessibilityAnnouncementRequestedNotification,
  @{NSAccessibilityAnnouncementKey:_value.accessibilityLabel,NSAccessibilityPriorityKey:@(NSAccessibilityPriorityLow)});
 __weak SlateZoomIndicator* weakSelf=self;
 _dismissTimer=[NSTimer timerWithTimeInterval:2.0 repeats:NO block:^(NSTimer* timer) { [weakSelf dismiss]; }];
 [NSRunLoop.mainRunLoop addTimer:_dismissTimer forMode:NSRunLoopCommonModes];
}
- (void)dismiss {
 [_dismissTimer invalidate]; _dismissTimer=nil;
 [self.layer removeAllAnimations];
 [self removeFromSuperview];
}
- (void)dealloc { [_dismissTimer invalidate]; }
@end

static CABasicAnimation* FadeOut(CFTimeInterval begin, CFTimeInterval duration) {
 CABasicAnimation* fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
 fade.fromValue=@1; fade.toValue=@0; fade.beginTime=begin; fade.duration=duration;
 fade.fillMode=kCAFillModeForwards; fade.removedOnCompletion=NO;
 return fade;
}

@implementation SlateDownloadArrival
- (NSView*)hitTest:(NSPoint)point { return nil; }
- (BOOL)isAccessibilityElement { return NO; }
// Slate note: Reuse one bounded arrival effect per window so a burst of downloads does not accumulate
// overlays.
+ (void)playInWindow:(NSWindow*)window fromView:(NSView*)source toIcon:(NSView*)icon {
 NSView* root=window.contentView;
 if(!root || !source || !icon || icon.hidden || icon.window!=window) return;
 // Burst downloads reuse one bounded effect per window, never accumulate overlays.
 for(NSView* previous in [root.subviews copy]) if([previous isKindOfClass:self]) {
  [previous.layer removeAllAnimations]; [previous removeFromSuperview];
 }
 SlateDownloadArrival* overlay=[[self alloc] initWithFrame:root.bounds];
 overlay.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 overlay.wantsLayer=YES;
 [root addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
 NSPoint end=[overlay convertPoint:NSMakePoint(NSMidX(icon.bounds),NSMidY(icon.bounds)) fromView:icon];
 NSPoint start=[overlay convertPoint:NSMakePoint(NSMidX(source.bounds),NSHeight(source.bounds)*0.65) fromView:source];
 NSEvent* event=NSApp.currentEvent;
 if(event.window==window && (event.type==NSEventTypeLeftMouseDown || event.type==NSEventTypeLeftMouseUp)) {
  NSPoint click=[source convertPoint:event.locationInWindow fromView:nil];
  if(NSPointInRect(click,source.bounds)) start=[overlay convertPoint:click fromView:source];
 }
 const BOOL reduced=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
 const CFTimeInterval now=CACurrentMediaTime(), arrival=now+(reduced ? 0 : 0.62);
 NSColor* accent=NSColor.controlAccentColor;
 CAShapeLayer* halo=[CAShapeLayer layer];
 CGPathRef haloPath=CGPathCreateWithEllipseInRect(CGRectMake(-13,-13,26,26),nil);
 halo.path=haloPath; CGPathRelease(haloPath);
 halo.position=end; halo.fillColor=[accent colorWithAlphaComponent:0.13].CGColor;
 halo.strokeColor=[accent colorWithAlphaComponent:0.85].CGColor;
 halo.lineWidth=1.5; halo.opacity=0;
 [overlay.layer addSublayer:halo];
 [halo addAnimation:FadeOut(arrival,reduced ? 0.4 : 0.32) forKey:@"glow"];
 if(!reduced) {
  CABasicAnimation* expand=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
  expand.fromValue=@0.6; expand.toValue=@1.7; expand.beginTime=arrival; expand.duration=0.32;
  expand.fillMode=kCAFillModeBoth; expand.removedOnCompletion=NO;
  [halo addAnimation:expand forKey:@"expand"];
  CGMutablePathRef path=CGPathCreateMutable();
  CGPathMoveToPoint(path,nil,start.x,start.y);
  CGPathAddCurveToPoint(path,nil,start.x+(end.x-start.x)*0.3,start.y+60,
                      end.x-40,end.y-50,end.x,end.y);
  CAShapeLayer* trail=[CAShapeLayer layer];
  trail.path=path; trail.fillColor=nil; trail.strokeColor=[accent colorWithAlphaComponent:0.45].CGColor;
  trail.lineWidth=2; trail.lineCap=kCALineCapRound; trail.strokeStart=1; trail.strokeEnd=1;
  trail.shadowColor=accent.CGColor; trail.shadowRadius=6; trail.shadowOpacity=0.7;
  [overlay.layer addSublayer:trail];
  for(NSString* key in @[@"strokeStart",@"strokeEnd"]) {
   CAKeyframeAnimation* stroke=[CAKeyframeAnimation animationWithKeyPath:key];
   stroke.values=[key isEqual:@"strokeStart"] ? @[@0,@0,@0.84,@1] : @[@0,@0.22,@1,@1];
   stroke.keyTimes=@[@0,@0.2,@0.88,@1]; stroke.duration=0.7;
   stroke.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
   [trail addAnimation:stroke forKey:key];
  }
  CALayer* comet=[CALayer layer];
  comet.bounds=CGRectMake(0,0,8,8); comet.cornerRadius=4;
  comet.backgroundColor=NSColor.whiteColor.CGColor; comet.position=end; comet.opacity=0;
  comet.shadowColor=accent.CGColor; comet.shadowRadius=9; comet.shadowOpacity=1; comet.shadowOffset=CGSizeZero;
  [overlay.layer addSublayer:comet];
  CAKeyframeAnimation* flight=[CAKeyframeAnimation animationWithKeyPath:@"position"];
  flight.path=path; flight.duration=0.62;
  flight.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  [comet addAnimation:flight forKey:@"flight"];
  CAKeyframeAnimation* light=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
  light.values=@[@0,@1,@1,@0]; light.keyTimes=@[@0,@0.1,@0.88,@1]; light.duration=0.7;
  [comet addAnimation:light forKey:@"light"];
  CGPathRelease(path);
  for(int i=0;i<6;++i) {
   CALayer* spark=[CALayer layer]; spark.bounds=CGRectMake(0,0,3,3); spark.cornerRadius=1.5;
   spark.position=end; spark.backgroundColor=accent.CGColor; spark.opacity=0;
   [overlay.layer addSublayer:spark];
   const double angle=i*2*M_PI/6;
   CABasicAnimation* drift=[CABasicAnimation animationWithKeyPath:@"position"];
   drift.fromValue=[NSValue valueWithPoint:end];
   drift.toValue=[NSValue valueWithPoint:NSMakePoint(end.x+cos(angle)*21,end.y+sin(angle)*21)];
   drift.beginTime=arrival; drift.duration=0.28; drift.fillMode=kCAFillModeBoth; drift.removedOnCompletion=NO;
   [spark addAnimation:drift forKey:@"spark"];
   [spark addAnimation:FadeOut(arrival,0.28) forKey:@"fade"];
  }
 }
 __weak SlateDownloadArrival* weakOverlay=overlay;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((reduced ? 0.45 : 1.0)*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
  [weakOverlay.layer removeAllAnimations]; [weakOverlay removeFromSuperview];
 });
}
@end
