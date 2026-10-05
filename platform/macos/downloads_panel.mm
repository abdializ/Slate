#import "platform/macos/downloads_panel.h"
#import "platform/macos/plate_components.h"
#import <QuartzCore/QuartzCore.h>

static NSImage* DownloadSymbol(NSString* name, NSString* label) {
 return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:label]
  imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
}
@interface SlateDownloadRowView : NSTableCellView
@property(strong) SlateDownloadItem* item;
@property(strong) NSImageView* fileImage;
@property(strong) NSTextField* filenameLabel;
@property(strong) NSTextField* sourceLabel;
@property(strong) NSTextField* detailLabel;
@property(strong) NSProgressIndicator* meter;
@property(strong) NSButton* primary;
@property(strong) NSButton* secondary;
- (void)configureWithItem:(SlateDownloadItem*)item ink:(NSColor*)ink muted:(NSColor*)muted;
@end
@implementation SlateDownloadRowView
- (instancetype)initWithFrame:(NSRect)frame {
 if((self=[super initWithFrame:frame])) {
  self.fileImage=[[NSImageView alloc] init]; self.fileImage.imageScaling=NSImageScaleProportionallyUpOrDown;
  self.filenameLabel=[NSTextField labelWithString:@""]; self.filenameLabel.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  self.filenameLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
  self.sourceLabel=[NSTextField labelWithString:@""]; self.sourceLabel.font=[NSFont systemFontOfSize:10.5];
  self.detailLabel=[NSTextField labelWithString:@""]; self.detailLabel.font=[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
  self.detailLabel.lineBreakMode=NSLineBreakByTruncatingTail;
  self.meter=[[NSProgressIndicator alloc] init]; self.meter.style=NSProgressIndicatorStyleBar;
  self.meter.minValue=0; self.meter.maxValue=1; self.meter.controlSize=NSControlSizeMini;
  self.primary=[NSButton buttonWithTitle:@"" target:self action:@selector(primaryAction:)];
  self.secondary=[NSButton buttonWithTitle:@"" target:self action:@selector(secondaryAction:)];
  for(NSButton* button in @[self.primary,self.secondary]) { button.bordered=NO; button.bezelStyle=NSBezelStyleInline; }
  for(NSView* view in @[self.fileImage,self.filenameLabel,self.sourceLabel,self.detailLabel,self.meter,self.primary,self.secondary]) [self addSubview:view];
 }
 return self;
}
- (void)layout {
 [super layout]; CGFloat w=NSWidth(self.bounds);
 self.fileImage.frame=NSMakeRect(14,24,36,36);
 self.filenameLabel.frame=NSMakeRect(64,53,MAX(40,w-144),18);
 self.sourceLabel.frame=NSMakeRect(64,36,MAX(40,w-144),15);
 self.detailLabel.frame=NSMakeRect(64,19,MAX(40,w-144),15);
 self.meter.frame=NSMakeRect(64,9,MAX(40,w-144),4);
 self.primary.frame=NSMakeRect(w-72,28,28,28); self.secondary.frame=NSMakeRect(w-38,28,28,28);
}
- (void)configureWithItem:(SlateDownloadItem*)item ink:(NSColor*)ink muted:(NSColor*)muted {
 BOOL changed=self.item!=item; self.item=item;
 if(changed) self.fileImage.image=item.fileIcon;
 self.filenameLabel.stringValue=item.filename ?: @"Download";
 self.filenameLabel.textColor=ink ?: NSColor.labelColor;
 NSString* origin=item.originalURL.host ?: @"Website";
 if([item.originalURL.scheme.lowercaseString isEqualToString:@"http"]) origin=[origin stringByAppendingString:@" · HTTP"];
 self.sourceLabel.stringValue=[NSString stringWithFormat:@"%@%@",origin,item.privateDownload ? @" · Private" : @""];
 self.sourceLabel.textColor=muted ?: NSColor.secondaryLabelColor;
 self.detailLabel.stringValue=item.state==SlateDownloadStateCompleted && !item.fileAvailable ? @"File moved or removed" : item.formattedStatus;
 self.detailLabel.textColor=item.state==SlateDownloadStateFailed ? NSColor.systemRedColor : (muted ?: NSColor.secondaryLabelColor);
 BOOL transferring=item.state==SlateDownloadStateInProgress;
 self.meter.hidden=!(transferring || item.state==SlateDownloadStatePaused || item.state==SlateDownloadStateFinishing);
 BOOL unknown=transferring && item.totalBytes<=0;
 if(self.meter.indeterminate!=unknown) self.meter.indeterminate=unknown;
 if(unknown) [self.meter startAnimation:nil]; else { [self.meter stopAnimation:nil]; self.meter.doubleValue=MAX(0,MIN(1,item.progress)); }
 NSString* action=transferring ? @"Pause download" : item.canResume ? @"Resume download" : @"Show in Finder";
 NSString* symbol=transferring ? @"pause.circle" : item.canResume ? @"play.circle" : @"folder";
 self.primary.image=DownloadSymbol(symbol,action); self.primary.toolTip=action; self.primary.accessibilityLabel=action;
 self.primary.enabled=transferring || item.canResume || item.fileAvailable;
 BOOL stoppable=transferring || item.state==SlateDownloadStatePaused;
 self.secondary.image=DownloadSymbol(stoppable ? @"xmark.circle" : @"ellipsis",stoppable ? @"Cancel download" : @"Download options");
 self.secondary.toolTip=stoppable ? @"Cancel download" : @"Download options";
 self.secondary.accessibilityLabel=self.secondary.toolTip;
 self.primary.contentTintColor=NSColor.controlAccentColor; self.secondary.contentTintColor=NSColor.secondaryLabelColor;
 self.toolTip=[NSString stringWithFormat:@"%@\n%@",self.filenameLabel.stringValue,self.detailLabel.stringValue];
 [self setNeedsLayout:YES];
}
- (void)primaryAction:(id)sender {
 if(self.item.state==SlateDownloadStateInProgress) [self.item pause];
 else if(self.item.canResume) [self.item resume];
 else [self.item showInFinder];
}
- (void)secondaryAction:(id)sender {
 if(self.item.state==SlateDownloadStateInProgress || self.item.state==SlateDownloadStatePaused) [self.item cancel];
 else [[self menuForEvent:NSApp.currentEvent] popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(self.secondary.frame),NSMinY(self.secondary.frame)) inView:self];
}
- (void)mouseDown:(NSEvent*)event {
 if(event.clickCount==2) [self.item openFile]; else [super mouseDown:event];
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
 NSMenu* menu=[[NSMenu alloc] initWithTitle:@"Download"];
 menu.autoenablesItems=NO;
 for(NSArray* entry in @[@[@"Open",NSStringFromSelector(@selector(open:))],@[@"Show in Finder",NSStringFromSelector(@selector(reveal:))]]) {
  NSMenuItem* action=[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
  action.target=self; action.enabled=self.item.fileAvailable;
 }
 NSMenuItem* copy=[menu addItemWithTitle:@"Copy download link" action:@selector(copyLink:) keyEquivalent:@""]; copy.target=self; copy.enabled=self.item.originalURL!=nil;
 [menu addItem:NSMenuItem.separatorItem];
 NSMenuItem* remove=[menu addItemWithTitle:@"Remove from history" action:@selector(remove:) keyEquivalent:@""]; remove.target=self;
 remove.enabled=self.item.state!=SlateDownloadStateInProgress && self.item.state!=SlateDownloadStatePaused && self.item.state!=SlateDownloadStateFinishing;
 return menu;
}
- (void)open:(id)sender { [self.item openFile]; }
- (void)reveal:(id)sender { [self.item showInFinder]; }
- (void)copyLink:(id)sender { [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:self.item.originalURL.absoluteString forType:NSPasteboardTypeString]; }
- (void)remove:(id)sender { [SlateDownloadManager.sharedManager removeItem:self.item]; }
@end

@implementation SlateDownloadButton {
 NSTrackingArea* _trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
 self = [super initWithFrame:frameRect];
 if (self) {
  self.wantsLayer = YES;
  self.toolTip = @"Downloads (⌘J)";
  self.accessibilityRole=NSAccessibilityButtonRole;
  self.accessibilityLabel=@"Downloads";
  [self updateStatus];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDownloadsChanged:) name:SlateDownloadsChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDownloadProgress:) name:SlateDownloadProgressNotification object:nil];
 }
 return self;
}

- (void)dealloc {
 [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if (_trackingArea) [self removeTrackingArea:_trackingArea];
 _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                owner:self userInfo:nil];
 [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
 (void)event;
 self.hovered = YES;
 [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
 (void)event;
 self.hovered = NO;
 [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
 (void)event;
 [[SlateDownloadsPanel sharedPanel] toggleForButton:self inWindow:self.window];
}

- (BOOL)accessibilityPerformPress { [[SlateDownloadsPanel sharedPanel] toggleForButton:self inWindow:self.window]; return YES; }

- (void)onDownloadsChanged:(NSNotification*)note {
 (void)note;
 [self updateStatus];
}

- (void)onDownloadProgress:(NSNotification*)note {
 (void)note;
 [self updateStatus];
}

- (void)updateStatus {
 SlateDownloadManager* mgr = [SlateDownloadManager sharedManager];
 self.hasActiveDownloads = mgr.hasActiveDownloads;
 self.progress = mgr.overallProgress;
 self.accessibilityValue=mgr.hasActiveDownloads ? [NSString stringWithFormat:@"%lu active downloads",(unsigned long)mgr.activeDownloads.count] : @"No active downloads";
 [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
 (void)dirtyRect;
 const NSRect bounds = self.bounds;
 NSColor* ink = self.barInk ?: NSColor.labelColor;
 NSColor* muted = self.barMuted ?: [ink colorWithAlphaComponent:0.70];
 NSColor* activeColor = self.accentInk ?: ink;

 if (self.active || self.hovered) {
  NSBezierPath* bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5, 0.5) xRadius:5.0 yRadius:5.0];
  [[ink colorWithAlphaComponent:self.active ? 0.16 : 0.08] setFill];
  [bg fill];
 }

 const NSPoint center = NSMakePoint(round(bounds.size.width / 2.0), round(bounds.size.height / 2.0));
 const CGFloat radius = 8.5;

 if (self.hasActiveDownloads) {
  NSBezierPath* track = [NSBezierPath bezierPath];
  [track appendBezierPathWithArcWithCenter:center radius:radius startAngle:0 endAngle:360];
  track.lineWidth = 1.8;
  [[ink colorWithAlphaComponent:0.18] setStroke];
  [track stroke];

  CGFloat pct = MAX(0.02, MIN(1.0, self.progress));
  CGFloat startAngle = 90.0;
  CGFloat endAngle = startAngle - (pct * 360.0);
  NSBezierPath* prog = [NSBezierPath bezierPath];
  [prog appendBezierPathWithArcWithCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
  prog.lineWidth = 1.8;
  prog.lineCapStyle = NSLineCapStyleRound;
  [activeColor setStroke];
  [prog stroke];

  NSBezierPath* arrow = [NSBezierPath bezierPath];
  [arrow moveToPoint:NSMakePoint(center.x, center.y + 4.0)];
  [arrow lineToPoint:NSMakePoint(center.x, center.y - 3.0)];
  [arrow moveToPoint:NSMakePoint(center.x - 3.0, center.y - 0.5)];
  [arrow lineToPoint:NSMakePoint(center.x, center.y - 3.5)];
  [arrow lineToPoint:NSMakePoint(center.x + 3.0, center.y - 0.5)];
  arrow.lineWidth = 1.4;
  arrow.lineCapStyle = NSLineCapStyleRound;
  arrow.lineJoinStyle = NSLineJoinStyleRound;
  [activeColor setStroke];
  [arrow stroke];
 } else {
  if (@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:13.5 weight:NSFontWeightRegular];
   NSImage* baseSym = [[NSImage imageWithSystemSymbolName:@"arrow.down.to.line" accessibilityDescription:@"Downloads"] imageWithSymbolConfiguration:cfg]
    ?: [[NSImage imageWithSystemSymbolName:@"arrow.down.circle" accessibilityDescription:@"Downloads"] imageWithSymbolConfiguration:cfg];
   if (baseSym) {
    NSImage* sym = [baseSym copy];
    [sym lockFocus];
    [(self.hovered ? ink : muted) set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, sym.size.width, sym.size.height), NSCompositingOperationSourceAtop);
    [sym unlockFocus];
    NSRect imgRect = NSMakeRect(round((bounds.size.width - sym.size.width)/2.0),
                                round((bounds.size.height - sym.size.height)/2.0),
                                sym.size.width, sym.size.height);
    [sym drawInRect:imgRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    return;
   }
  }

  NSBezierPath* ring = [NSBezierPath bezierPath];
  [ring appendBezierPathWithArcWithCenter:center radius:radius startAngle:0 endAngle:360];
  ring.lineWidth = 1.4;
  [(self.hovered ? ink : muted) setStroke];
  [ring stroke];

  NSBezierPath* arrow = [NSBezierPath bezierPath];
  [arrow moveToPoint:NSMakePoint(center.x, center.y + 4.0)];
  [arrow lineToPoint:NSMakePoint(center.x, center.y - 3.0)];
  [arrow moveToPoint:NSMakePoint(center.x - 3.0, center.y - 0.5)];
  [arrow lineToPoint:NSMakePoint(center.x, center.y - 3.5)];
  [arrow lineToPoint:NSMakePoint(center.x + 3.0, center.y - 0.5)];
  arrow.lineWidth = 1.4;
  arrow.lineCapStyle = NSLineCapStyleRound;
  arrow.lineJoinStyle = NSLineJoinStyleRound;
  [(self.hovered ? ink : muted) setStroke];
  [arrow stroke];
 }
}

@end

@implementation SlateDownloadsPanel {
 NSVisualEffectView* _card;
 NSTextField* _title;
 NSTextField* _summary;
 NSSearchField* _search;
 NSSegmentedControl* _filter;
 NSButton* _clear;
 NSButton* _folder;
 NSScrollView* _scroll;
 NSTableView* _table;
 NSTextField* _empty;
 NSArray<SlateDownloadItem*>* _visibleItems;
 id _dismissMonitor;
 __weak NSView* _anchor;
}
+ (instancetype)sharedPanel {
 static SlateDownloadsPanel* panel;
 static dispatch_once_t once;
 dispatch_once(&once, ^{ panel=[[self alloc] initWithContentRect:NSMakeRect(0,0,460,520)
  styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO]; });
 return panel;
}
- (BOOL)canBecomeKeyWindow { return YES; }
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)mask backing:(NSBackingStoreType)backing defer:(BOOL)defer {
 if((self=[super initWithContentRect:rect styleMask:mask backing:backing defer:defer])) {
  self.opaque=NO; self.backgroundColor=NSColor.clearColor; self.hasShadow=YES;
  self.level=NSPopUpMenuWindowLevel; self.hidesOnDeactivate=YES; self.releasedWhenClosed=NO;
  self.collectionBehavior=NSWindowCollectionBehaviorFullScreenAuxiliary;
  self.accessibilityLabel=@"Downloads";
  _card=[[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0,0,460,520)];
  _card.material=NSVisualEffectMaterialPopover; _card.blendingMode=NSVisualEffectBlendingModeBehindWindow; _card.state=NSVisualEffectStateActive;
  _card.wantsLayer=YES; _card.layer.cornerRadius=16; _card.layer.cornerCurve=kCACornerCurveContinuous; _card.layer.masksToBounds=YES;
  _card.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; self.contentView=_card;
  _title=[NSTextField labelWithString:@"Downloads"]; _title.font=[NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
  _summary=[NSTextField labelWithString:@""]; _summary.font=[NSFont systemFontOfSize:11]; _summary.textColor=NSColor.secondaryLabelColor;
  _search=[[NSSearchField alloc] init]; _search.placeholderString=@"Search downloads"; _search.target=self; _search.action=@selector(searchChanged:);
  _search.sendsSearchStringImmediately=YES; _search.accessibilityLabel=@"Search downloads";
  _filter=[NSSegmentedControl segmentedControlWithLabels:@[@"All",@"Active",@"Finished"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(filterChanged:)];
  _filter.selectedSegment=0; _filter.segmentStyle=NSSegmentStyleSeparated;
  _clear=[NSButton buttonWithTitle:@"Clear history" target:self action:@selector(clearHistory:)]; _clear.bezelStyle=NSBezelStyleInline; _clear.bordered=NO;
  _clear.toolTip=@"Remove finished entries. Downloaded files stay in Finder.";
  _folder=[NSButton buttonWithTitle:@"Downloads folder" target:self action:@selector(openFolder:)]; _folder.bordered=NO; _folder.bezelStyle=NSBezelStyleInline;
  _folder.image=DownloadSymbol(@"folder",@"Downloads folder"); _folder.imagePosition=NSImageLeft;
  _scroll=[[NSScrollView alloc] init]; _scroll.drawsBackground=NO; _scroll.hasVerticalScroller=YES; _scroll.autohidesScrollers=YES;
  _table=[[NSTableView alloc] init]; _table.headerView=nil; _table.backgroundColor=NSColor.clearColor; _table.rowHeight=84; _table.intercellSpacing=NSMakeSize(0,2);
  _table.dataSource=self; _table.delegate=self; _table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle; _table.selectionHighlightStyle=NSTableViewSelectionHighlightStyleRegular;
  _table.target=self; _table.doubleAction=@selector(openSelected:);
  NSTableColumn* column=[[NSTableColumn alloc] initWithIdentifier:@"download"]; column.width=436; [_table addTableColumn:column]; _scroll.documentView=_table;
  _empty=[NSTextField wrappingLabelWithString:@"Downloads will appear here.\nSave a file from any website to get started."]; _empty.alignment=NSTextAlignmentCenter; _empty.textColor=NSColor.secondaryLabelColor; _empty.font=[NSFont systemFontOfSize:13];
  for(NSView* view in @[_title,_summary,_search,_filter,_scroll,_empty,_folder,_clear]) [_card addSubview:view];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDeactivated:) name:NSApplicationDidResignActiveNotification object:NSApp];
  for(NSString* name in @[SlateDownloadsChangedNotification,SlateDownloadProgressNotification]) [NSNotificationCenter.defaultCenter addObserver:self selector:name==SlateDownloadsChangedNotification ? @selector(downloadsChanged:) : @selector(progressChanged:) name:name object:nil];
 }
 return self;
}
- (void)layoutContents {
 CGFloat w=NSWidth(self.contentView.bounds),h=NSHeight(self.contentView.bounds);
 _title.frame=NSMakeRect(20,h-48,w-40,27); _summary.frame=NSMakeRect(20,h-67,w-40,16);
 _search.frame=NSMakeRect(20,h-104,w-40,28); _filter.frame=NSMakeRect(20,h-141,w-40,26);
 _scroll.frame=NSMakeRect(8,48,w-16,h-201); _empty.frame=NSMakeRect(34,h/2-35,w-68,70);
 _folder.frame=NSMakeRect(16,12,170,24); _clear.frame=NSMakeRect(w-134,12,116,24);
 _table.tableColumns.firstObject.width=w-32;
}
- (void)searchChanged:(id)sender { [self refreshList]; }
- (void)filterChanged:(id)sender { [self refreshList]; }
- (void)downloadsChanged:(NSNotification*)note { if(self.isVisible) [self refreshList]; }
- (void)progressChanged:(NSNotification*)note {
 if(!self.isVisible) return;
 for(NSInteger row=0;row<(NSInteger)_visibleItems.count;++row) {
  SlateDownloadRowView* view=[_table viewAtColumn:0 row:row makeIfNecessary:NO];
  if(view) [view configureWithItem:_visibleItems[row] ink:nil muted:nil];
 }
 [self updateSummary];
}
- (void)updateSummary {
 SlateDownloadManager* manager=SlateDownloadManager.sharedManager;
 NSUInteger active=manager.activeDownloads.count,paused=0;
 for(SlateDownloadItem* item in manager.items) if(item.state==SlateDownloadStatePaused) ++paused;
 _summary.stringValue=active ? [NSString stringWithFormat:@"%lu downloading%@",(unsigned long)active,paused ? [NSString stringWithFormat:@" · %lu paused",(unsigned long)paused] : @""] : paused ? [NSString stringWithFormat:@"%lu paused",(unsigned long)paused] : @"Your files, ready when you are";
}
- (void)refreshList {
 NSString* query=_search.stringValue;
 NSMutableArray* matches=[NSMutableArray array]; BOOL finished=NO;
 for(SlateDownloadItem* item in SlateDownloadManager.sharedManager.items) {
  BOOL active=item.state==SlateDownloadStateInProgress || item.state==SlateDownloadStatePaused || item.state==SlateDownloadStateFinishing;
  if(!active) finished=YES;
  if((_filter.selectedSegment==1 && !active) || (_filter.selectedSegment==2 && active)) continue;
  if(query.length && [item.filename rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location==NSNotFound && [(item.originalURL.host ?: @"") rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound) continue;
  [matches addObject:item];
 }
 [matches sortUsingComparator:^NSComparisonResult(SlateDownloadItem* a,SlateDownloadItem* b) {
  BOOL aa=a.state==SlateDownloadStateInProgress || a.state==SlateDownloadStatePaused || a.state==SlateDownloadStateFinishing;
  BOOL bb=b.state==SlateDownloadStateInProgress || b.state==SlateDownloadStatePaused || b.state==SlateDownloadStateFinishing;
  if(aa!=bb) return aa ? NSOrderedAscending : NSOrderedDescending;
  return [b.startDate compare:a.startDate];
 }];
 _visibleItems=matches; [_table reloadData]; _scroll.hidden=matches.count==0; _empty.hidden=matches.count>0;
 _empty.stringValue=query.length ? @"No matching downloads.\nTry a filename or website." : _filter.selectedSegment==1 ? @"Nothing downloading right now.\nNew downloads will appear here." : @"Downloads will appear here.\nSave a file from any website to get started.";
 _clear.enabled=finished; [self updateSummary]; [self layoutContents];
}
- (void)clearHistory:(id)sender { [SlateDownloadManager.sharedManager clearCompleted]; }
- (void)openFolder:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:SlateDownloadManager.sharedManager.downloadsDirectory]]; }
- (void)openSelected:(id)sender { NSInteger row=_table.selectedRow; if(row>=0 && row<(NSInteger)_visibleItems.count) [_visibleItems[row] openFile]; }
- (void)showForButton:(NSView*)anchor inWindow:(NSWindow*)window {
 if(!anchor || anchor.window!=window) return;
 _anchor=anchor; [self refreshList];
 NSRect target=[window convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
 NSRect screen=(window.screen ?: NSScreen.mainScreen).visibleFrame;
 CGFloat w=MIN(460,NSWidth(screen)-24),h=MIN(520,NSHeight(screen)-32);
 CGFloat x=MIN(MAX(NSMinX(screen)+12,NSMaxX(target)-w+4),NSMaxX(screen)-w-12);
 CGFloat y=MAX(NSMinY(screen)+12,MIN(NSMinY(target)-h-8,NSMaxY(screen)-h-12));
 [self setFrame:NSMakeRect(x,y,w,h) display:NO]; [self layoutContents];
 if(self.parentWindow!=window) { if(self.parentWindow) [self.parentWindow removeChildWindow:self]; [window addChildWindow:self ordered:NSWindowAbove]; }
 [self makeKeyAndOrderFront:nil];
 if([anchor isKindOfClass:SlateDownloadButton.class]) { ((SlateDownloadButton*)anchor).active=YES; [anchor setNeedsDisplay:YES]; }
 if(_dismissMonitor) [NSEvent removeMonitor:_dismissMonitor];
 __weak SlateDownloadsPanel* weak=self;
 _dismissMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^NSEvent*(NSEvent* event) {
  if(!weak.isVisible || event.window==weak) return event;
  if(event.window==anchor.window && NSPointInRect([anchor convertPoint:event.locationInWindow fromView:nil],anchor.bounds)) return event;
  [weak hidePanel]; return event;
 }];
}
- (void)toggleForButton:(NSView*)anchor inWindow:(NSWindow*)window { if(self.isVisible) [self hidePanel]; else [self showForButton:anchor inWindow:window]; }
- (void)hidePanel {
 if([_anchor isKindOfClass:SlateDownloadButton.class]) { ((SlateDownloadButton*)_anchor).active=NO; [_anchor setNeedsDisplay:YES]; }
 if(_dismissMonitor) { [NSEvent removeMonitor:_dismissMonitor]; _dismissMonitor=nil; }
 [self orderOut:nil]; if(self.parentWindow) [self.parentWindow removeChildWindow:self];
}
- (void)cancelOperation:(id)sender { [self hidePanel]; }
- (void)appDeactivated:(NSNotification*)note { [self hidePanel]; }
- (BOOL)performKeyEquivalent:(NSEvent*)event {
 if((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqualToString:@"f"]) return [self makeFirstResponder:_search];
 return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent*)event {
 if(event.keyCode==53) { [self hidePanel]; return; }
 if((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqualToString:@"f"]) { [self makeFirstResponder:_search]; return; }
 if(event.keyCode==36) { [self openSelected:nil]; return; }
 [super keyDown:event];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return _visibleItems.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
 if(row<0 || row>=(NSInteger)_visibleItems.count) return nil;
 SlateDownloadRowView* view=[table makeViewWithIdentifier:@"downloadRow" owner:self];
 if(!view) { view=[[SlateDownloadRowView alloc] initWithFrame:NSMakeRect(0,0,436,84)]; view.identifier=@"downloadRow"; }
 [view configureWithItem:_visibleItems[row] ink:nil muted:nil]; return view;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; if(_dismissMonitor) [NSEvent removeMonitor:_dismissMonitor]; }
@end
