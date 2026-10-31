#import "tab_switcher.h"
#include "core/tab_switcher.h"
#include <map>
#include <string>

@implementation SlateTabPreview
@end

@class SlateSwitcherSurface;
@interface SlateSwitcherCard : NSButton
@property(strong) SlateTabPreview* model;
@property(weak) SlateTabSwitcher* switcher;
@property BOOL picked;
@end
@interface SlateTabSwitcher () {
 std::map<std::string,slate::TabSwitcherState> histories;
 std::string spaceKey;
 NSUInteger generation;
}
@property(weak) NSWindow* host;
@property(strong) SlateSwitcherSurface* surface;
@property(strong) NSMutableDictionary<NSNumber*,SlateSwitcherCard*>* buttons;
@property(strong) NSMutableDictionary<NSNumber*,NSDictionary*>* previews;
@property(strong) NSMutableDictionary<NSNumber*,NSUUID*>* requests;
@property(strong) id resignObserver;
@property(strong) NSView* selection;
@property NSPoint pointerRest;
@property BOOL pointerMoved;
- (slate::TabSwitcherState&)state;
- (NSImage*)previewFor:(slate::TabId)identifier;
- (void)show;
- (void)rebuild;
- (void)requestPreview:(slate::TabId)identifier;
- (void)selectCard:(SlateSwitcherCard*)button;
- (void)hover:(NSEvent*)event;
- (void)commit;
@end
@interface SlateSwitcherSurface : NSView
@property(weak) SlateTabSwitcher* switcher;
@property NSRect gridPanel;
@property NSRect moonPanel;
@property BOOL moonSelected;
@property(strong) NSTrackingArea* tracking;
@end

namespace {
std::vector<slate::TabId> IDs(NSArray<NSNumber*>* values) {
 std::vector<slate::TabId> result;
 for(NSNumber* value in values) result.push_back(value.unsignedLongLongValue);
 return result;
}
NSColor* Ground(NSView* view) {
 BOOL dark=[[view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]] isEqual:NSAppearanceNameDarkAqua];
 return [NSColor colorWithCalibratedWhite:dark ? 0.12 : 0.985 alpha:1];
}
void RoundedFill(NSRect rect, CGFloat radius, NSColor* color) {
 [color setFill]; [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}
void DrawTabPicture(NSImage* image, NSImage* icon, NSRect rect, CGFloat mark) {
 [NSGraphicsContext saveGraphicsState];
 [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] addClip];
 RoundedFill(rect,5,[NSColor.labelColor colorWithAlphaComponent:0.045]);
 if(image && image.size.width>0 && image.size.height>0) {
  CGFloat scale=MAX(NSWidth(rect)/image.size.width,NSHeight(rect)/image.size.height);
  NSSize size=NSMakeSize(image.size.width*scale,image.size.height*scale);
  // Top-align a tall page preview, as a browser page is presented on screen.
  NSRect target=NSMakeRect(NSMidX(rect)-size.width/2,NSMinY(rect),size.width,size.height);
  [image drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
 } else if(icon) {
  [icon drawInRect:NSMakeRect(NSMidX(rect)-mark/2,NSMidY(rect)-mark/2,mark,mark) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
 }
 [NSGraphicsContext restoreGraphicsState];
}
}

@implementation SlateSwitcherCard
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
 if(self.picked && self.model.moon) RoundedFill(self.bounds,8,[NSColor.labelColor colorWithAlphaComponent:0.065]);
 const BOOL moon=self.model.moon;
 CGFloat inset=moon ? 6 : 8;
 CGFloat pictureHeight=NSHeight(self.bounds)-(moon ? 29 : 39);
 NSRect picture=NSMakeRect(inset,inset,NSWidth(self.bounds)-2*inset,MAX(4,pictureHeight));
 if(moon) {
  RoundedFill(picture,4,[NSColor.labelColor colorWithAlphaComponent:0.12]);
  picture.origin.y+=5; picture.size.height-=5;
 }
 if(self.model.partner) {
  CGFloat side=(NSWidth(picture)-2)/2;
  NSRect left=picture; left.size.width=side;
  NSRect right=left; right.origin.x+=side+2;
  DrawTabPicture([self.switcher previewFor:self.model.identifier],self.model.icon,left,22);
  SlateTabPreview* partner=[self.switcher.owner switcherTab:self.model.partner];
  DrawTabPicture([self.switcher previewFor:self.model.partner],partner.icon,right,22);
 } else DrawTabPicture([self.switcher previewFor:self.model.identifier],self.model.icon,picture,moon ? 18 : 26);
 CGFloat y=NSMaxY(picture)+(moon ? 5 : 7);
 CGFloat x=inset;
 if(!moon) {
  [self.model.icon drawInRect:NSMakeRect(x,y,13,13) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
  x+=19;
 }
 CGFloat tail=self.model.muted ? 16 : 0;
 NSMutableParagraphStyle* style=[NSMutableParagraphStyle new];
 style.lineBreakMode=NSLineBreakByTruncatingTail;
 [self.model.title drawInRect:NSMakeRect(x,y-1,MAX(0,NSWidth(self.bounds)-inset-x-tail),16)
  withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:moon ? 10.5 : 11.5],NSForegroundColorAttributeName:NSColor.labelColor,NSParagraphStyleAttributeName:style}];
 if(self.model.muted) {
  NSImage* symbol=[NSImage imageWithSystemSymbolName:@"speaker.slash.fill" accessibilityDescription:@"Muted"];
  symbol=[symbol imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.secondaryLabelColor]]];
  [symbol drawInRect:NSMakeRect(NSWidth(self.bounds)-inset-12,y+1,11,11) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.6 respectFlipped:YES hints:nil];
 }
}
@end

@implementation SlateSwitcherSurface
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if(self.tracking) [self removeTrackingArea:self.tracking];
 self.tracking=[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil];
 [self addTrackingArea:self.tracking];
}
- (void)mouseMoved:(NSEvent*)event { [self.switcher hover:event]; }
- (void)layout { [super layout]; [self.switcher rebuild]; }
- (void)drawRect:(NSRect)dirty {
 [[NSColor.blackColor colorWithAlphaComponent:0.12] setFill]; NSRectFillUsingOperation(self.bounds,NSCompositingOperationSourceOver);
 for(NSValue* value in @[[NSValue valueWithRect:self.gridPanel],[NSValue valueWithRect:self.moonPanel]]) {
  NSRect panel=value.rectValue; if(NSIsEmptyRect(panel)) continue;
  NSShadow* shadow=[NSShadow new]; shadow.shadowColor=[NSColor.blackColor colorWithAlphaComponent:0.12]; shadow.shadowBlurRadius=20; shadow.shadowOffset=NSMakeSize(0,-5);
  [NSGraphicsContext saveGraphicsState]; [shadow set]; RoundedFill(panel,12,Ground(self)); [NSGraphicsContext restoreGraphicsState];
  NSBezierPath* path=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(panel,0.5,0.5) xRadius:12 yRadius:12];
  [[NSColor.labelColor colorWithAlphaComponent:0.10] setStroke]; path.lineWidth=1; [path stroke];
 }
 if(!NSIsEmptyRect(self.gridPanel)) {
  NSString* legend=self.moonSelected ? @"⌃W  Close     ⌃R  Reload     ⌃M  Mute     ⌃O  Move to main window" : @"⌃W  Close     ⌃R  Reload     ⌃M  Mute";
  [legend drawInRect:NSMakeRect(NSMinX(self.gridPanel)+14,NSMaxY(self.gridPanel)-25,NSWidth(self.gridPanel)-28,15)
   withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10.5],NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
 }
}
@end

@implementation SlateTabSwitcher
- (instancetype)init {
 if((self=[super init])) {
  _buttons=[NSMutableDictionary dictionary]; _previews=[NSMutableDictionary dictionary]; _requests=[NSMutableDictionary dictionary];
  __weak SlateTabSwitcher* weakSelf=self;
  _resignObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
   SlateTabSwitcher* self=weakSelf;
   if(self.active && note.object==self.host) {
#if defined(SLATE_ENABLE_VERIFY)
    fprintf(stderr,"SLATE_SWITCHER_RESIGN window=%ld\n",(long)self.host.windowNumber);
#endif
    [self cancel];
   }
  }];
 }
 return self;
}
- (void)dealloc { if(_resignObserver) [NSNotificationCenter.defaultCenter removeObserver:_resignObserver]; }
- (slate::TabSwitcherState&)state { return histories[spaceKey]; }
- (BOOL)active { return [self state].active(); }
- (BOOL)visible { return self.surface.superview!=nil; }
- (slate::TabId)selected { return [self state].selected; }
- (void)useSpace:(NSString*)space {
 std::string next=(space ?: @"default").UTF8String;
 if(next==spaceKey) return;
 [self cancel]; spaceKey=next;
 // IDs may be reused in another space. Images must never cross that boundary.
 [self.previews removeAllObjects]; [self.requests removeAllObjects];
}
- (void)prune {
 const auto& state=[self state];
 auto keep=state.recent;
 if(self.visible) {
  auto shown=state.ring(); keep.insert(keep.end(),shown.begin(),shown.end());
  for(auto id:shown) {
   SlateTabPreview* tab=[self.owner switcherTab:id]; if(tab.partner) keep.push_back(tab.partner);
  }
 }
 for(NSNumber* key in self.previews.allKeys) if(!slate::TabSwitcherState::contains(keep,key.unsignedLongLongValue)) [self.previews removeObjectForKey:key];
}
- (void)leftTab:(slate::TabId)identifier alive:(NSArray<NSNumber*>*)alive {
 [self state].left(identifier,IDs(alive));
 [self prune];
 [self requestPreview:identifier];
}
- (NSImage*)previewFor:(slate::TabId)identifier {
 NSDictionary* cached=self.previews[@(identifier)];
 SlateTabPreview* model=[self.owner switcherTab:identifier];
 return model && [cached[@"address"] isEqual:model.address] ? cached[@"image"] : nil;
}
- (void)requestPreview:(slate::TabId)identifier {
 SlateTabPreview* model=[self.owner switcherTab:identifier];
 if(!model || self.requests[@(identifier)]) return;
 NSString* address=model.address;
 NSUUID* request=NSUUID.UUID;
 self.requests[@(identifier)]=request;
 NSUInteger token=generation;
 __weak SlateTabSwitcher* weakSelf=self;
 [self.owner switcherPreview:identifier completion:^(NSImage* image) {
  SlateTabSwitcher* self=weakSelf;
  if(!self || self->generation!=token || self.requests[@(identifier)]!=request) return;
  [self.requests removeObjectForKey:@(identifier)];
  SlateTabPreview* current=[self.owner switcherTab:identifier];
  if(!image || !current || ![current.address isEqual:address]) return;
  self.previews[@(identifier)]=@{@"address":address,@"image":image};
  [self prune];
  [self rebuild];
 }];
}
- (void)beginInWindow:(NSWindow*)window cards:(NSArray<NSNumber*>*)cards moons:(NSArray<NSNumber*>*)moons current:(slate::TabId)current fromMoon:(BOOL)fromMoon backwards:(BOOL)backwards {
 if(self.active) { [self state].step(backwards); [self show]; [self updateSelection]; return; }
 if(!window || window.attachedSheet || ![self state].begin(IDs(cards),IDs(moons),current,fromMoon,backwards)) return;
#if defined(SLATE_ENABLE_VERIFY)
 fprintf(stderr,"SLATE_SWITCHER_BEGIN home=%llu window=%ld\n",(unsigned long long)current,(long)window.windowNumber);
#endif
 self.host=window; ++generation; [self.requests removeAllObjects];
 NSUInteger token=generation;
 __weak SlateTabSwitcher* weakSelf=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  SlateTabSwitcher* self=weakSelf;
  if(self && self->generation==token && self.active) [self show];
 });
}
- (void)show {
 if(!self.active || self.visible) return;
 self.surface=[[SlateSwitcherSurface alloc] initWithFrame:self.host.contentView.bounds];
 self.surface.switcher=self;
 self.surface.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 self.surface.appearance=self.host.contentView.effectiveAppearance;
 [self.host.contentView addSubview:self.surface positioned:NSWindowAbove relativeTo:nil];
 self.selection=[[NSView alloc] initWithFrame:NSZeroRect]; self.selection.wantsLayer=YES;
 self.selection.layer.cornerRadius=8;
 self.selection.layer.backgroundColor=[NSColor.labelColor colorWithAlphaComponent:0.065].CGColor;
 self.selection.hidden=YES;
 [self.surface addSubview:self.selection];
 self.pointerRest=self.host.mouseLocationOutsideOfEventStream; self.pointerMoved=NO;
 [self rebuild];
 auto shown=[self state].ring();
 // Start with the highlighted card; stagger snapshots so opening does not stall the window.
 std::stable_sort(shown.begin(),shown.end(),[&](auto a,auto b){ return a==self.selected && b!=self.selected; });
 NSUInteger token=generation;
 for(size_t i=0;i<shown.size();++i) {
  const auto identifier=shown[i];
  __weak SlateTabSwitcher* weakSelf=self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*0.04*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
   SlateTabSwitcher* self=weakSelf;
   if(!self || self->generation!=token || !self.visible) return;
   if(identifier==[self state].home || ![self previewFor:identifier]) [self requestPreview:identifier];
   SlateTabPreview* tab=[self.owner switcherTab:identifier];
   if(tab.partner && ![self previewFor:tab.partner]) [self requestPreview:tab.partner];
  });
 }
 NSAccessibilityPostNotification(self.surface,NSAccessibilityLayoutChangedNotification);
}
- (SlateSwitcherCard*)buttonFor:(slate::TabId)identifier {
 SlateSwitcherCard* button=self.buttons[@(identifier)];
 if(!button) {
  button=[[SlateSwitcherCard alloc] initWithFrame:NSZeroRect];
  button.switcher=self; button.target=self; button.action=@selector(selectCard:);
  button.bordered=NO; button.focusRingType=NSFocusRingTypeNone;
  self.buttons[@(identifier)]=button; [self.surface addSubview:button];
 }
 button.model=[self.owner switcherTab:identifier];
 button.toolTip=button.model.title;
 [button setAccessibilityLabel:[@"Switch to " stringByAppendingString:button.model.title ?: @"tab"]];
 return button;
}
- (void)rebuild {
 if(!self.visible) return;
 const auto& state=[self state];
 const CGFloat columns=MIN(5,state.cards.size());
 const int moonColumns=state.moon_columns(), per=state.moons_per_column();
 const CGFloat moonRoom=moonColumns ? 30+(moonColumns-1)*6 : 0;
 const CGFloat width=MIN(176,(NSWidth(self.surface.bounds)-64-MAX(0,columns-1)*8-moonRoom)/(MAX(1,columns)+0.62*moonColumns));
 const CGFloat pictureHeight=(width-16)*0.62, cardHeight=pictureHeight+39;
 const CGFloat gridWidth=columns ? columns*width+(columns-1)*8+24 : 0;
 const CGFloat gridHeight=columns ? ceil(state.cards.size()/5.0)*(cardHeight+8)-8+24+25 : 0;
 const CGFloat moonWidth=width*0.62;
 const CGFloat panelWidth=moonColumns ? moonColumns*moonWidth+(moonColumns-1)*6+16 : 0;
 const CGFloat totalWidth=gridWidth+(gridWidth && panelWidth ? 14 : 0)+panelWidth;
 const CGFloat startX=round((NSWidth(self.surface.bounds)-totalWidth)/2);
 const CGFloat centerY=round(NSHeight(self.surface.bounds)/2);
 self.surface.gridPanel=columns ? NSMakeRect(startX,centerY-gridHeight/2,gridWidth,gridHeight) : NSZeroRect;
 NSMutableSet<NSNumber*>* alive=[NSMutableSet set];
 for(size_t i=0;i<state.cards.size();++i) {
  auto id=state.cards[i]; [alive addObject:@(id)];
  SlateSwitcherCard* button=[self buttonFor:id]; button.model.moon=NO;
  button.frame=NSMakeRect(startX+12+(i%5)*(width+8),NSMinY(self.surface.gridPanel)+12+(i/5)*(cardHeight+8),width,cardHeight);
 }
 CGFloat moonHeight=0;
 for(int column=0;column<moonColumns;++column) {
  CGFloat height=0;
  for(int row=0;row<per;++row) {
   size_t i=column*per+row; if(i>=state.moons.size()) break;
   SlateTabPreview* model=[self.owner switcherTab:state.moons[i]];
   CGFloat scale=model.screens>0 ? 0.6+0.4*MIN(1,MAX(0,log2(model.screens)/4)) : 0.8;
   CGFloat side=moonWidth*scale;
   height+=(side-12)*0.62+29+6;
  }
  moonHeight=MAX(moonHeight,height-6+16);
 }
 self.surface.moonPanel=moonColumns ? NSMakeRect(startX+gridWidth+(gridWidth ? 14 : 0),centerY-moonHeight/2,panelWidth,moonHeight) : NSZeroRect;
 for(int column=0;column<moonColumns;++column) {
  std::vector<NSSize> sizes; CGFloat height=0;
  for(int row=0;row<per;++row) {
   size_t i=column*per+row; if(i>=state.moons.size()) break;
   auto id=state.moons[i]; [alive addObject:@(id)];
   SlateSwitcherCard* button=[self buttonFor:id]; button.model.moon=YES;
   CGFloat scale=button.model.screens>0 ? 0.6+0.4*MIN(1,MAX(0,log2(button.model.screens)/4)) : 0.8;
   CGFloat side=moonWidth*scale;
   sizes.push_back(NSMakeSize(side,(side-12)*0.62+29)); height+=sizes.back().height+6;
  }
  CGFloat y=centerY-(height-6)/2;
  for(size_t row=0;row<sizes.size();++row) {
   auto id=state.moons[column*per+row]; NSSize size=sizes[row];
   self.buttons[@(id)].frame=NSMakeRect(NSMinX(self.surface.moonPanel)+8+column*(moonWidth+6)+(moonWidth-size.width)/2,y,size.width,size.height);
   y+=size.height+6;
  }
 }
 for(NSNumber* key in self.buttons.allKeys) if(![alive containsObject:key]) { [self.buttons[key] removeFromSuperview]; [self.buttons removeObjectForKey:key]; }
 [self updateSelection];
}
- (void)updateSelection {
 SlateSwitcherCard* picked=self.buttons[@(self.selected)];
 BOOL grid=picked && !picked.model.moon;
 if(grid) {
  BOOL animate=!self.selection.hidden && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  self.selection.hidden=NO;
  if(animate) [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
   context.duration=0.14; [self.selection.animator setFrame:picked.frame];
  } completionHandler:nil];
  else self.selection.frame=picked.frame;
 } else self.selection.hidden=YES;
 for(NSNumber* key in self.buttons) {
  SlateSwitcherCard* button=self.buttons[key];
  button.picked=key.unsignedLongLongValue==self.selected;
  [button setAccessibilityValue:button.picked ? @"Selected" : @""];
  [button setNeedsDisplay:YES];
 }
 self.surface.moonSelected=slate::TabSwitcherState::contains([self state].moons,self.selected);
 [self.surface setNeedsDisplay:YES];
}
- (void)selectCard:(SlateSwitcherCard*)button { if([self state].pick(button.model.identifier)) [self commit]; }
- (slate::TabId)cardAt:(NSPoint)point {
 for(NSNumber* key in self.buttons) if(NSPointInRect(point,self.buttons[key].frame)) return key.unsignedLongLongValue;
 return 0;
}
- (void)hover:(NSEvent*)event {
 if(!self.visible || event.window!=self.host) return;
 if(!self.pointerMoved) {
  if(fabs(event.locationInWindow.x-self.pointerRest.x)+fabs(event.locationInWindow.y-self.pointerRest.y)<=2) return;
  self.pointerMoved=YES;
 }
 auto id=[self cardAt:[self.surface convertPoint:event.locationInWindow fromView:nil]];
 if(id && [self state].pick(id)) [self updateSelection];
}
- (BOOL)handleEvent:(NSEvent*)event {
 if(!self.active) return NO;
 if(event.window && event.window!=self.host) {
  if(event.type==NSEventTypeKeyDown || event.type==NSEventTypeLeftMouseDown || event.type==NSEventTypeRightMouseDown) [self cancel];
  return NO;
 }
 if(event.type==NSEventTypeFlagsChanged && !(event.modifierFlags&NSEventModifierFlagControl)) { [self commit]; return YES; }
 if(event.type==NSEventTypeKeyDown) {
  const auto flags=event.modifierFlags&NSEventModifierFlagDeviceIndependentFlagsMask;
  if(event.keyCode==53) { [self cancel]; return YES; }
  if(event.keyCode==36 || event.keyCode==76) { [self commit]; return YES; }
  if(event.keyCode==48 && (flags&NSEventModifierFlagControl) && !(flags&(NSEventModifierFlagCommand|NSEventModifierFlagOption))) {
   [self state].step(flags&NSEventModifierFlagShift); [self show]; [self updateSelection]; return YES;
  }
  using D=slate::TabSwitcherState::Direction;
  if(event.keyCode>=123 && event.keyCode<=126) {
   D directions[]={D::Left,D::Right,D::Down,D::Up};
   [self state].move(directions[event.keyCode-123]); [self show]; [self updateSelection]; return YES;
  }
  NSString* chars=event.charactersIgnoringModifiers.lowercaseString;
  if((flags&NSEventModifierFlagControl) && !(flags&(NSEventModifierFlagCommand|NSEventModifierFlagOption|NSEventModifierFlagShift)) && chars.length==1) {
   unichar key=[chars characterAtIndex:0];
   if(key=='w' || key=='r' || key=='m' || key=='o') {
    auto id=self.selected;
    if(key=='w') [self removeTab:id];
    if(key=='o') [self cancel];
    [self.owner switcherAction:key tab:id];
    if(self.active) [self rebuild];
    return YES;
   }
  }
  // Keep the gesture's keys out of the page below it.
  return YES;
 }
 if(self.visible && event.type==NSEventTypeMouseMoved) { [self hover:event]; return YES; }
 if(self.visible && (event.type==NSEventTypeLeftMouseDown || event.type==NSEventTypeRightMouseDown)) {
  NSPoint point=[self.surface convertPoint:event.locationInWindow fromView:nil];
  auto id=[self cardAt:point];
  if(id && [self state].pick(id)) [self commit];
  else if(!NSPointInRect(point,self.surface.gridPanel) && !NSPointInRect(point,self.surface.moonPanel)) [self cancel];
  return YES;
 }
 return NO;
}
- (void)commit {
 auto id=self.selected;
 [self cancel];
 if(id && [self.owner switcherTab:id]) [self.owner switcherPick:id];
}
- (void)removeTab:(slate::TabId)identifier {
 if(!self.active) return;
 [self state].remove(identifier);
 if(!self.active) [self cancel]; else [self rebuild];
}
- (void)cancel {
 ++generation; [self state].cancel();
 [self.surface removeFromSuperview]; self.surface=nil; self.selection=nil; self.host=nil;
 [self.buttons removeAllObjects]; [self.requests removeAllObjects]; [self prune];
}
@end
