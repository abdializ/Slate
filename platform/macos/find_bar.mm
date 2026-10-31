// Find controls use the supplied PageFind engine in a separate WebKit content
// world. HTML ranges are highlighted without inserting or replacing page nodes.
#import "find_bar.h"
#import "pdf_overlay.h"
#import "SlateSearch-Swift.h"
#import <PDFKit/PDFKit.h>
#import <QuartzCore/QuartzCore.h>

@interface SlateFindBar ()
@property(strong) SlatePageFinder* finder;
@property(strong) NSArray<PDFSelection*>* pdfSelections;
@property(strong) NSPopUpButton* options;
@property BOOL matchCase;
@property BOOL wholeWords;
@property BOOL wholeWordsAvailable;
@property NSUInteger request;
@end

@implementation SlateFindBar
- (instancetype)initWithOwner:(SlateDelegate*)owner {
 self=[super initWithFrame:NSMakeRect(0,0,360,38)];
 if(!self) return nil;
 _owner=owner; _lastQuery=@""; _finder=[SlatePageFinder new]; _wholeWordsAvailable=YES;
 self.material=NSVisualEffectMaterialPopover;
 self.blendingMode=NSVisualEffectBlendingModeWithinWindow;
 self.state=NSVisualEffectStateFollowsWindowActiveState;
 self.wantsLayer=YES; self.layer.cornerRadius=19;
 self.layer.cornerCurve=kCACornerCurveContinuous;
 self.layer.borderWidth=0.5; self.layer.borderColor=NSColor.separatorColor.CGColor;
 self.translatesAutoresizingMaskIntoConstraints=NO;
 _searchField=[[NSTextField alloc] initWithFrame:NSZeroRect];
 _searchField.bordered=NO; _searchField.drawsBackground=NO;
 _searchField.focusRingType=NSFocusRingTypeNone;
 _searchField.font=[NSFont systemFontOfSize:13];
 _searchField.placeholderString=@"Find on page";
 _searchField.delegate=self;
 _searchField.cell.usesSingleLineMode=YES;
 [_searchField setAccessibilityLabel:@"Find on page"];
 [self addSubview:_searchField];
 _countLabel=[NSTextField labelWithString:@""];
 _countLabel.font=[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
 _countLabel.alignment=NSTextAlignmentRight;
 [_countLabel setAccessibilityLabel:@"Match count"];
 [self addSubview:_countLabel];
 _options=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
 _options.bordered=NO;
 [_options addItemWithTitle:@""];
 _options.itemArray.firstObject.image=[NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:@"Find options"];
 _options.imagePosition=NSImageOnly;
 for(NSString* title in @[@"Match case",@"Whole words"]) {
  NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:title action:@selector(toggleOption:) keyEquivalent:@""];
  item.target=self; [_options.menu addItem:item];
 }
 _options.toolTip=@"Find options";
 [self addSubview:_options];
 _prevButton=[self button:@"chevron.up" label:@"Previous match (Shift-Return)" action:@selector(previous:)];
 _nextButton=[self button:@"chevron.down" label:@"Next match (Return)" action:@selector(next:)];
 _closeButton=[self button:@"xmark" label:@"Close Find (Escape)" action:@selector(close:)];
 [self updateCount:0 total:0 more:NO];
 return self;
}
- (NSButton*)button:(NSString*)symbol label:(NSString*)label action:(SEL)action {
 NSButton* button=[NSButton buttonWithTitle:@"" target:self action:action];
 button.bordered=NO;
 button.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
 button.toolTip=label;
 [button setAccessibilityLabel:label];
 [self addSubview:button]; return button;
}
- (void)layout {
 [super layout];
 CGFloat w=NSWidth(self.bounds), right=w-10;
 _closeButton.frame=NSMakeRect(right-20,9,20,20); right-=26;
 BOOL narrow=w<290;
 _prevButton.hidden=narrow; _nextButton.hidden=narrow;
 if(!narrow) {
  _nextButton.frame=NSMakeRect(right-20,9,20,20); right-=22;
  _prevButton.frame=NSMakeRect(right-20,9,20,20); right-=24;
 }
 _options.frame=NSMakeRect(right-24,7,24,24); right-=30;
 _countLabel.frame=NSMakeRect(right-82,11,82,17); right-=90;
 _searchField.frame=NSMakeRect(14,10,MAX(40,right-14),20);
}
- (BOOL)validateMenuItem:(NSMenuItem*)item {
 if(item.action==@selector(toggleOption:)) {
  BOOL whole=[item.title isEqual:@"Whole words"];
  item.state=(whole ? _wholeWords : _matchCase) ? NSControlStateValueOn : NSControlStateValueOff;
  return !whole || _wholeWordsAvailable;
 }
 return YES;
}
- (void)toggleOption:(NSMenuItem*)item {
 if([item.title isEqual:@"Match case"]) _matchCase=!_matchCase;
 else if(_wholeWordsAvailable) _wholeWords=!_wholeWords;
 [self performSearchWithQuery:_searchField.stringValue];
}
- (void)previous:(id)sender { [self findPrevious]; }
- (void)next:(id)sender { [self findNext]; }
- (void)close:(id)sender { [self hideAnimated]; }
- (void)controlTextDidChange:(NSNotification*)notification { [self performSearchWithQuery:_searchField.stringValue]; }
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)selector {
 if(selector==@selector(cancelOperation:)) { [self hideAnimated]; return YES; }
 if(selector==@selector(insertNewline:)) {
  if(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) [self findPrevious];
  else [self findNext];
  return YES;
 }
 if(selector==@selector(insertNewlineIgnoringFieldEditor:)) { [self findPrevious]; return YES; }
 return NO;
}
- (void)syncWithWebView:(WKWebView*)web {
 if(web==_targetWebView) return;
 [self clearHighlights];
 _targetWebView=web;
 if(_isVisible) [self performSearchWithQuery:_searchField.stringValue];
}
- (void)showInView:(NSView*)container initialQuery:(NSString*)query {
 if(self.superview!=container) {
  [self removeFromSuperview]; [container addSubview:self];
  NSLayoutConstraint* preferred=[self.widthAnchor constraintEqualToConstant:360]; preferred.priority=750;
  [NSLayoutConstraint activateConstraints:@[
   preferred,[self.widthAnchor constraintLessThanOrEqualToAnchor:container.widthAnchor constant:-24],
   [self.heightAnchor constraintEqualToConstant:38],
   [self.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
   [self.topAnchor constraintEqualToAnchor:container.topAnchor constant:12]]];
 }
 _isVisible=YES; self.hidden=NO;
 if(query.length) _searchField.stringValue=query;
 [self.window makeFirstResponder:_searchField]; [_searchField selectText:nil];
 [self performSearchWithQuery:_searchField.stringValue];
}
- (void)hideAnimated {
 _isVisible=NO; self.hidden=YES;
 [self clearHighlights];
 if(_targetWebView.window) [_targetWebView.window makeFirstResponder:_targetWebView];
}
- (void)updateCount:(NSInteger)current total:(NSInteger)total more:(BOOL)more {
 _currentMatchIndex=current; _totalMatches=total;
 _countLabel.stringValue=!_searchField.stringValue.length ? @"" : [NSString stringWithFormat:@"%ld of %ld%@",(long)current,(long)total,more ? @"+" : @""];
 _countLabel.textColor=total==0 && _searchField.stringValue.length ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
 _prevButton.enabled=total>0; _nextButton.enabled=total>0;
}
- (void)performSearchWithQuery:(NSString*)query {
 _lastQuery=query ?: @"";
 [self updateWithSteps:0];
}
- (void)updateWithSteps:(NSInteger)steps {
 WKWebView* web=_targetWebView;
 if(!web) return;
 NSUInteger mine=++_request;
 NSString* query=_lastQuery ?: @"";
 PDFView* pdf=[SlatePDFOverlay findPDFViewInView:web];
 if(pdf && pdf.document) {
  _wholeWordsAvailable=NO; _wholeWords=NO;
  if(!steps || !_pdfSelections) {
   _pdfSelections=query.length ? [pdf.document findString:query withOptions:_matchCase ? 0 : NSCaseInsensitiveSearch] : @[];
   pdf.highlightedSelections=_pdfSelections;
   _currentMatchIndex=_pdfSelections.count ? 1 : 0;
  } else if(_pdfSelections.count) {
   NSInteger total=_pdfSelections.count;
   _currentMatchIndex=((_currentMatchIndex-1+steps)%total+total)%total+1;
  }
  if(_pdfSelections.count) {
   pdf.currentSelection=_pdfSelections[_currentMatchIndex-1]; [pdf scrollSelectionToVisible:nil];
  }
  [self updateCount:_currentMatchIndex total:_pdfSelections.count more:NO];
  return;
 }
 __weak SlateFindBar* weakSelf=self;
 [_finder update:web query:query matchCase:_matchCase wholeWords:_wholeWords steps:steps completion:^(NSDictionary<NSString*,id>* result) {
  SlateFindBar* bar=weakSelf;
  if(!bar || mine!=bar.request || bar.targetWebView!=web || !bar.isVisible) return;
  bar.wholeWordsAvailable=[result[@"wholeWordsAvailable"] boolValue];
  if(!bar.wholeWordsAvailable && bar.wholeWords) { bar.wholeWords=NO; [bar updateWithSteps:0]; return; }
  if(![result[@"available"] boolValue]) {
   [bar updateCount:0 total:0 more:NO]; bar.countLabel.stringValue=@"Unavailable"; return;
  }
  NSInteger count=[result[@"count"] integerValue];
  if(count<0) {
   BOOL found=[result[@"found"] boolValue];
   bar.countLabel.stringValue=found ? @"Found" : @"No match";
   bar.nextButton.enabled=found; bar.prevButton.enabled=found; return;
  }
  [bar updateCount:[result[@"index"] integerValue] total:count more:[result[@"more"] boolValue]];
 }];
}
- (void)findNext { [self updateWithSteps:1]; }
- (void)findPrevious { [self updateWithSteps:-1]; }
- (void)clearHighlights {
 ++_request;
 if(!_targetWebView) return;
 [_finder clear:_targetWebView];
 PDFView* pdf=[SlatePDFOverlay findPDFViewInView:_targetWebView];
 pdf.highlightedSelections=@[];
 _pdfSelections=nil;
}
@end
