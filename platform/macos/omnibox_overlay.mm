// Native adaptation of Omnibox.swift, AddressField, Breath and Motion from the
// user's AllOmniboxFeatures.swift. No per-frame application timer is used.
#import "omnibox_overlay.h"
#import <QuartzCore/QuartzCore.h>

static BOOL Dark(NSAppearance* appearance) { return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua]; }
NSColor* SlateOmniboxGround(NSAppearance* appearance) { return [NSColor colorWithWhite:Dark(appearance)?0.11:1 alpha:1]; }
NSColor* SlateOmniboxInk(NSAppearance* appearance) { return [NSColor colorWithWhite:Dark(appearance)?0.93:0.09 alpha:1]; }
NSColor* SlateOmniboxHairline(NSAppearance* appearance) { return [NSColor colorWithWhite:Dark(appearance)?0.20:0.91 alpha:1]; }
BOOL SlateOmniboxReducedMotion(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }
static BOOL LightMotion(void) {
 return [NSUserDefaults.standardUserDefaults boolForKey:@"motion.light"] &&
  (NSProcessInfo.processInfo.lowPowerModeEnabled || NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious);
}

@interface SlateOmniboxField : NSTextField
@property(copy) dispatch_block_t arrived;
@end
@implementation SlateOmniboxField
- (BOOL)performKeyEquivalent:(NSEvent*)event {
 if((event.keyCode==36 || event.keyCode==76) && (event.modifierFlags & NSEventModifierFlagCommand)) {
  id<NSTextFieldDelegate> delegate=self.delegate;
  if([delegate respondsToSelector:@selector(control:textView:doCommandBySelector:)])
   return [delegate control:self textView:(NSTextView*)self.currentEditor doCommandBySelector:@selector(insertNewline:)];
 }
 return [super performKeyEquivalent:event];
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if(self.window && self.arrived) { dispatch_block_t action=self.arrived; self.arrived=nil; action(); } }
@end

@interface SlateOmniboxCard () {
 BOOL _refused, _deleting;
 NSString* _typed;
 NSString* _ending;
 CALayer* _surface;
 CALayer* _breath;
 NSButton* _siteChip;
 id _motionObserver;
}
@end
@implementation SlateOmniboxCard
- (instancetype)initWithDelegate:(id<SlateOmniboxDelegate>)delegate {
 self=[super initWithFrame:NSMakeRect(0,0,kFieldWidth,kFieldHeight)];
 if(!self) return nil;
 _delegate=delegate; _typed=@"";
 self.wantsLayer=YES; self.layer.masksToBounds=NO;
 _breath=[CALayer layer]; _breath.shadowOpacity=0.07; _breath.shadowRadius=26; _breath.shadowOffset=CGSizeZero;
 _surface=[CALayer layer]; _surface.cornerRadius=14; _surface.cornerCurve=kCACornerCurveContinuous;
 _surface.borderWidth=1; _surface.shadowOpacity=0.06; _surface.shadowRadius=24;
 _surface.shadowOffset=CGSizeMake(0,-8); _surface.shadowColor=NSColor.blackColor.CGColor;
 [self.layer addSublayer:_breath]; [self.layer addSublayer:_surface];
 _field=[[SlateOmniboxField alloc] initWithFrame:NSZeroRect];
 _field.delegate=self; _field.bordered=NO; _field.drawsBackground=NO;
 _field.focusRingType=NSFocusRingTypeNone; _field.font=[NSFont systemFontOfSize:15.5];
 _field.lineBreakMode=NSLineBreakByClipping;
 _field.cell.usesSingleLineMode=YES; _field.cell.wraps=NO; _field.cell.scrollable=YES;
 [_field setAccessibilityLabel:@"Address or search"];
 [self addSubview:_field];
 _siteChip=[NSButton buttonWithTitle:@"" target:self action:@selector(removeSite:)];
 _siteChip.bordered=NO; _siteChip.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
 _siteChip.image=[NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil];
 _siteChip.imagePosition=NSImageLeading; _siteChip.imageScaling=NSImageScaleProportionallyDown;
 _siteChip.wantsLayer=YES; _siteChip.layer.cornerRadius=7; _siteChip.hidden=YES;
 _siteChip.toolTip=@"Remove site search (Backspace in an empty field)";
 [self addSubview:_siteChip];
 __weak SlateOmniboxCard* weakSelf=self;
 _motionObserver=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) { [weakSelf applyTheme]; }];
 [self applyTheme]; return self;
}
- (void)dealloc { if(_motionObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_motionObserver]; }
- (NSString*)typedText { return _ending ? (_typed ?: @"") : self.field.stringValue; }
- (BOOL)hasCompletion { return _ending.length>0; }
- (void)setText:(NSString*)text selectAll:(BOOL)all {
 _typed=[text copy]; _ending=nil; _deleting=NO; _refused=NO;
 self.field.stringValue=text ?: @""; [self applyTheme];
 NSTextView* editor=(NSTextView*)self.field.currentEditor;
 if(editor) editor.selectedRange=all ? NSMakeRange(0,text.length) : NSMakeRange(text.length,0);
}
- (void)focusSelectingAll:(BOOL)all {
 if(!self.window) {
  __weak SlateOmniboxCard* weakSelf=self;
  ((SlateOmniboxField*)self.field).arrived=^{ dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf focusSelectingAll:all]; }); };
  return;
 }
 [self.window makeFirstResponder:self.field];
 NSTextView* editor=(NSTextView*)self.field.currentEditor;
 if(![editor isKindOfClass:NSTextView.class]) return;
 NSColor* ink=SlateOmniboxInk(self.effectiveAppearance);
 editor.selectedTextAttributes=@{NSBackgroundColorAttributeName:[ink colorWithAlphaComponent:0.12],NSForegroundColorAttributeName:ink};
 NSUInteger start=all ? 0 : self.typedText.length;
 editor.selectedRange=NSMakeRange(start,self.field.stringValue.length-start);
}
- (void)setSearchSite:(NSDictionary<NSString*,NSString*>*)site {
 _searchSite=[site copy]; _siteChip.hidden=site==nil;
 _siteChip.title=site[@"name"] ?: @"";
 [_siteChip setAccessibilityLabel:[@"Searching " stringByAppendingString:site[@"name"] ?: @""]];
 _ending=nil; [self applyTheme]; self.needsLayout=YES;
}
- (void)activateSite:(NSDictionary<NSString*,NSString*>*)site {
 self.searchSite=site; self.suggestedSite=nil; [self setText:@"" selectAll:NO];
 [self.delegate hideSuggestions]; [self focusSelectingAll:NO];
}
- (void)removeSite:(id)sender {
 self.searchSite=nil; [self.delegate showSuggestionsForCard:self query:self.typedText]; [self focusSelectingAll:NO];
}
- (void)setIsDarkTheme:(BOOL)dark { _isDarkTheme=dark; _customDarkSet=YES; [self applyTheme]; }
- (void)setPlaceholder:(NSString*)placeholder { _placeholder=[placeholder copy]; [self applyTheme]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self applyTheme]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self updateBreath]; }
- (void)viewDidHide { [super viewDidHide]; [self updateBreath]; }
- (void)viewDidUnhide { [super viewDidUnhide]; [self updateBreath]; }
- (void)applyTheme {
 if(!_surface) return;
 NSAppearance* appearance=self.effectiveAppearance;
 if(_customDarkSet) appearance=[NSAppearance appearanceNamed:_isDarkTheme ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
 NSColor* ink=SlateOmniboxInk(appearance);
 [CATransaction begin]; [CATransaction setDisableActions:YES];
 _surface.backgroundColor=SlateOmniboxGround(appearance).CGColor;
 _surface.borderColor=(_refused ? [NSColor.systemRedColor colorWithAlphaComponent:0.35] : SlateOmniboxHairline(appearance)).CGColor;
 _breath.shadowColor=ink.CGColor;
 _siteChip.layer.backgroundColor=[NSColor colorWithWhite:Dark(appearance)?0.175:0.937 alpha:1].CGColor;
 _siteChip.contentTintColor=ink;
 [CATransaction commit];
 self.field.textColor=ink;
 NSString* placeholder=_searchSite ? [@"Search " stringByAppendingString:_searchSite[@"name"]] : (_placeholder ?: @"Enter a web address");
 self.field.placeholderAttributedString=[[NSAttributedString alloc] initWithString:placeholder attributes:@{NSFontAttributeName:self.field.font,NSForegroundColorAttributeName:[ink colorWithAlphaComponent:0.30]}];
 [self updateBreath];
}
- (void)updateBreath {
 BOOL plays=self.window && !self.hiddenOrHasHiddenAncestor && !SlateOmniboxReducedMotion() && !LightMotion();
 if(!plays) { [_breath removeAnimationForKey:@"breath"]; return; }
 if([_breath animationForKey:@"breath"]) return;
 CABasicAnimation* scale=[CABasicAnimation animationWithKeyPath:@"transform.scale"]; scale.fromValue=@0.97; scale.toValue=@1.03;
 CABasicAnimation* fade=[CABasicAnimation animationWithKeyPath:@"opacity"]; fade.fromValue=@0.65; fade.toValue=@1;
 CAAnimationGroup* group=[CAAnimationGroup animation]; group.animations=@[scale,fade]; group.duration=2.6;
 group.autoreverses=YES; group.repeatCount=HUGE_VALF;
 group.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
 [_breath addAnimation:group forKey:@"breath"];
}
- (void)layout {
 [super layout]; CGFloat w=NSWidth(self.bounds),h=NSHeight(self.bounds);
 [CATransaction begin]; [CATransaction setDisableActions:YES];
 _surface.frame=self.bounds; _breath.bounds=self.bounds; _breath.position=CGPointMake(w/2,h/2);
 CGPathRef path=CGPathCreateWithRoundedRect(self.bounds,14,14,NULL);
 _surface.shadowPath=path; _breath.shadowPath=path; CGPathRelease(path);
 [CATransaction commit];
 CGFloat chip=_searchSite ? MIN(MAX(0,w-44-48),[_siteChip.title sizeWithAttributes:@{NSFontAttributeName:_siteChip.font}].width+34) : 0;
 _siteChip.frame=NSMakeRect(22,(h-22)/2,chip,22);
 CGFloat left=22+(chip>0 ? chip+8 : 0);
 self.field.frame=NSMakeRect(left,(h-22)/2,MAX(0,w-left-22),22);
}
- (NSView*)hitTest:(NSPoint)point {
 NSPoint local=[self convertPoint:point fromView:self.superview];
 if(self.hidden || !NSPointInRect(local,self.bounds)) return nil;
 return !_siteChip.hidden && NSPointInRect(local,_siteChip.frame) ? _siteChip : self.field;
}
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)shake {
 _refused=YES; [self applyTheme];
 if(SlateOmniboxReducedMotion()) return;
 CAKeyframeAnimation* motion=[CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
 NSMutableArray* points=[NSMutableArray array];
 for(int i=0;i<=30;i++) { double t=i/30.0; [points addObject:@(sin(t*M_PI*6)*7*(1-t))]; }
 motion.values=points; motion.duration=0.5; motion.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
 [self.layer addAnimation:motion forKey:@"refusal"];
}
- (void)controlTextDidChange:(NSNotification*)note {
 _refused=NO; [self applyTheme]; _typed=[self.field.stringValue copy]; _ending=nil;
 [self.delegate showSuggestionsForCard:self query:_typed];
 NSTextView* editor=(NSTextView*)self.field.currentEditor;
 BOOL marked=[editor isKindOfClass:NSTextView.class] && editor.hasMarkedText;
 if(!_deleting && !marked && !_searchSite && [self.delegate respondsToSelector:@selector(completionForCard:query:)]) {
  NSString* suffix=[self.delegate completionForCard:self query:_typed];
  if(suffix.length) {
   _ending=suffix; self.field.stringValue=[_typed stringByAppendingString:suffix];
   if(editor) editor.selectedRange=NSMakeRange(_typed.length,suffix.length);
  }
 }
 _deleting=NO;
}
- (BOOL)control:(NSControl*)control textView:(NSTextView*)editor doCommandBySelector:(SEL)command {
 if(command==@selector(insertTab:) && self.suggestedSite && !self.searchSite) { [self activateSite:self.suggestedSite]; return YES; }
 if((command==@selector(insertTab:) || command==@selector(moveRight:)) && _ending.length && NSMaxRange(editor.selectedRange)==editor.string.length) {
  [self setText:self.field.stringValue selectAll:NO]; return YES;
 }
 if(command==@selector(deleteBackward:) && self.searchSite && !self.field.stringValue.length) { [self removeSite:nil]; return YES; }
 if(command==@selector(deleteWordBackward:)) {
  _deleting=YES;
  if(_ending.length && editor.selectedRange.length && NSMaxRange(editor.selectedRange)==editor.string.length) {
   [editor delete:nil]; _deleting=YES; [editor deleteWordBackward:nil]; return YES;
  }
  return NO;
 }
 if(command==@selector(deleteBackward:) || command==@selector(deleteForward:) || command==@selector(deleteWordForward:)) { _deleting=YES; return NO; }
 if(command==@selector(insertNewline:)) { [self.delegate submitOmniboxCard:self]; return YES; }
 if(command==@selector(moveDown:)) { [self.delegate moveSuggestionDelta:1]; return YES; }
 if(command==@selector(moveUp:)) { [self.delegate moveSuggestionDelta:-1]; return YES; }
 if(command==@selector(cancelOperation:)) {
  if(self.searchSite) { [self removeSite:nil]; return YES; }
  [self.delegate hideSuggestions];
  if([self.superview isKindOfClass:SlateOmniboxOverlay.class]) [(SlateOmniboxOverlay*)self.superview dismiss];
  return YES;
 }
 return NO;
}
@end

@implementation SlateOmniboxStack
- (BOOL)isFlipped { return YES; }
@end

@interface SlateOmniboxRow () {
 NSTextField* _title;
 NSTextField* _detail;
 NSImageView* _icon;
 NSTextField* _key;
 NSView* _dot;
 dispatch_block_t _action;
 BOOL _hovering;
}
@end
@implementation SlateOmniboxRow
- (instancetype)initWithTitle:(NSString*)title detail:(NSString*)detail kind:(NSString*)kind image:(NSImage*)image action:(dispatch_block_t)action {
 self=[super initWithFrame:NSMakeRect(0,0,560,34)]; if(!self) return nil;
 _action=[action copy]; self.wantsLayer=YES; self.layer.cornerRadius=9; self.layer.cornerCurve=kCACornerCurveContinuous;
 self.translatesAutoresizingMaskIntoConstraints=NO; [self.heightAnchor constraintEqualToConstant:34].active=YES;
 _title=[NSTextField labelWithString:title ?: @""]; _title.font=[NSFont systemFontOfSize:13];
 _detail=[NSTextField labelWithString:detail ?: @""]; _detail.font=[NSFont systemFontOfSize:12];
 for(NSTextField* label in @[_title,_detail]) { label.lineBreakMode=NSLineBreakByTruncatingTail; [self addSubview:label]; }
 if([kind isEqual:@"open"]) {
  _dot=[[NSView alloc] initWithFrame:NSZeroRect]; _dot.wantsLayer=YES; _dot.layer.cornerRadius=2.5; [self addSubview:_dot];
 } else {
  NSString* symbol=[kind isEqual:@"bookmark"] ? @"bookmark" : [kind isEqual:@"command"] ? @"command" : ([kind isEqual:@"search"] || [kind isEqual:@"suggested"] || [kind isEqual:@"site"]) ? @"magnifyingglass" : nil;
  if(image || symbol) {
   _icon=[[NSImageView alloc] initWithFrame:NSZeroRect];
   _icon.image=image ?: [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightMedium]];
   _icon.imageScaling=NSImageScaleProportionallyDown; [self addSubview:_icon];
  }
 }
 if([kind isEqual:@"site"]) {
  _key=[NSTextField labelWithString:@"Tab"]; _key.font=[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]; _key.alignment=NSTextAlignmentCenter;
  _key.wantsLayer=YES; _key.layer.cornerRadius=5; _key.layer.borderWidth=1; [self addSubview:_key];
 }
 self.accessibilityElement=YES; self.accessibilityRole=NSAccessibilityButtonRole;
 self.accessibilityLabel=[NSString stringWithFormat:@"%@%@%@",title,detail.length ? @", " : @"",detail ?: @""];
 [self applyColors]; return self;
}
- (BOOL)hovering { return _hovering; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self applyColors]; }
- (void)applyColors {
 BOOL dark=Dark(self.effectiveAppearance); NSColor* ink=SlateOmniboxInk(self.effectiveAppearance);
 _title.textColor=ink; _detail.textColor=[NSColor colorWithWhite:dark?0.58:0.55 alpha:1];
 _icon.contentTintColor=_detail.textColor; _dot.layer.backgroundColor=[ink colorWithAlphaComponent:0.55].CGColor;
 _key.textColor=_detail.textColor; _key.layer.borderColor=SlateOmniboxHairline(self.effectiveAppearance).CGColor;
 self.layer.backgroundColor=(_highlighted ? [NSColor colorWithWhite:dark?0.175:0.937 alpha:1] : _hovering ? [NSColor colorWithWhite:dark?0.15:0.965 alpha:1] : NSColor.clearColor).CGColor;
}
- (void)setHighlighted:(BOOL)highlighted { _highlighted=highlighted; [self applyColors]; }
- (void)layout {
 [super layout]; CGFloat w=NSWidth(self.bounds),lead=12,right=w-12;
 if(_key) { _key.frame=NSMakeRect(right-30,8,30,18); right-=40; }
 if(_icon || _dot) { _icon.frame=NSMakeRect(lead,10,14,14); _dot.frame=NSMakeRect(lead+4.5,14.5,5,5); lead+=24; }
 CGFloat available=MAX(0,right-lead);
 CGFloat titleWidth=MIN([_title.stringValue sizeWithAttributes:@{NSFontAttributeName:_title.font}].width+10,_detail.stringValue.length ? available*0.65 : available);
 _title.frame=NSMakeRect(lead,9,titleWidth,17);
 _detail.frame=NSMakeRect(lead+titleWidth+10,9,MAX(0,available-titleWidth-10),17);
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas]; for(NSTrackingArea* area in self.trackingAreas) [self removeTrackingArea:area];
 [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent*)event { _hovering=YES; [self applyColors]; }
- (void)mouseExited:(NSEvent*)event { _hovering=NO; [self applyColors]; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (void)mouseDown:(NSEvent*)event { if(_action) _action(); }
- (BOOL)accessibilityPerformPress { if(_action) _action(); return YES; }
@end

@implementation SlateOmniboxOverlay {
 NSUInteger _presentation;
}
- (instancetype)initWithDelegate:(id<SlateOmniboxDelegate>)delegate {
 self=[super initWithFrame:NSZeroRect]; if(!self) return nil;
 _delegate=delegate; self.wantsLayer=YES; self.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 _backdrop=[[NSView alloc] initWithFrame:NSZeroRect]; _backdrop.wantsLayer=YES;
 [_backdrop addGestureRecognizer:[[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(backdropClicked:)]];
 [self addSubview:_backdrop]; _card=[[SlateOmniboxCard alloc] initWithDelegate:delegate]; [self addSubview:_card];
 [self applyTheme]; return self;
}
- (NSTextField*)field { return _card.field; }
- (NSView*)fieldCard { return _card; }
- (BOOL)isShowing { return self.superview!=nil && !self.hidden; }
- (void)applyTheme { _backdrop.layer.backgroundColor=[SlateOmniboxGround(self.effectiveAppearance) colorWithAlphaComponent:0.74].CGColor; [_card applyTheme]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self applyTheme]; }
- (void)layout {
 [super layout]; _backdrop.frame=self.bounds;
 CGFloat width=MIN(kFieldWidth,MAX(0,NSWidth(self.bounds)-28));
 _card.frame=NSMakeRect(round((NSWidth(self.bounds)-width)/2),round((NSHeight(self.bounds)-kFieldHeight)/2)+30,width,kFieldHeight);
}
- (void)showOver:(NSView*)container initialText:(NSString*)text {
 ++_presentation; self.card.searchSite=nil; self.card.suggestedSite=nil;
 if(self.superview!=container) { self.frame=container.bounds; [container addSubview:self positioned:NSWindowAbove relativeTo:nil]; }
 self.hidden=NO; self.alphaValue=1;
 [_card setText:[text isEqual:@"about:blank"] ? @"" : (text ?: @"") selectAll:YES];
 [self applyTheme]; [self layoutSubtreeIfNeeded];
 [_card focusSelectingAll:YES];
 // Only the field scales. The page cover fades at its original edges.
 if(!SlateOmniboxReducedMotion()) {
  CABasicAnimation* fade=[CABasicAnimation animationWithKeyPath:@"opacity"]; fade.fromValue=@0; fade.toValue=@1; fade.duration=0.14;
  [_backdrop.layer addAnimation:fade forKey:@"arrival"];
  if(LightMotion()) { CABasicAnimation* scale=[CABasicAnimation animationWithKeyPath:@"transform.scale"]; scale.fromValue=@0.97; scale.toValue=@1; scale.duration=0.16; [_card.layer addAnimation:scale forKey:@"arrival"]; }
  else { CASpringAnimation* scale=[CASpringAnimation animationWithKeyPath:@"transform.scale"]; scale.fromValue=@0.97; scale.toValue=@1; scale.mass=1; scale.stiffness=341; scale.damping=30.3; scale.duration=scale.settlingDuration; [_card.layer addAnimation:scale forKey:@"arrival"]; }
 }
 [self.delegate showSuggestionsForCard:self.card query:self.card.typedText];
}
- (void)dismiss {
 NSUInteger mine=++_presentation; [self.delegate hideSuggestions];
 void (^finish)(void)=^{
  if(self->_presentation!=mine) return;
  self.hidden=YES; [self removeFromSuperview];
  if([self.delegate respondsToSelector:@selector(omniboxOverlayDidDismiss:)]) [self.delegate omniboxOverlayDidDismiss:self];
 };
 if(SlateOmniboxReducedMotion()) { finish(); return; }
 [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) { context.duration=0.14; self.animator.alphaValue=0; } completionHandler:finish];
}
- (void)backdropClicked:(id)sender { [self dismiss]; }
- (void)shake { [_card shake]; }
@end
