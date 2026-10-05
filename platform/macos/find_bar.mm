#import "find_bar.h"
#import "pdf_overlay.h"
#import <PDFKit/PDFKit.h>
#import <QuartzCore/QuartzCore.h>

@interface SlateFindSearchField : NSTextField
@property (nonatomic, weak) SlateFindBar* findBar;
@end

@implementation SlateFindSearchField

- (BOOL)performKeyEquivalent:(NSEvent*)event {
  if (event.keyCode == 53) { // Escape
    [self.findBar hideAnimated];
    return YES;
  }
  if (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
    if (event.modifierFlags & NSEventModifierFlagShift) {
      [self.findBar findPrevious];
    } else {
      [self.findBar findNext];
    }
    return YES;
  }
  return [super performKeyEquivalent:event];
}

- (BOOL)textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(cancelOperation:)) {
    [self.findBar hideAnimated];
    return YES;
  }
  if (commandSelector == @selector(insertNewline:)) {
    [self.findBar findNext];
    return YES;
  }
  if (commandSelector == @selector(insertBacktab:) || commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
    [self.findBar findPrevious];
    return YES;
  }
  return NO;
}

@end

@interface SlateFindBar ()
@property (nonatomic, strong) NSLayoutConstraint* trailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint* topConstraint;
@property (nonatomic, strong) NSArray<PDFSelection*>* pdfSelections;
@end

@implementation SlateFindBar

- (instancetype)initWithOwner:(SlateDelegate*)owner {
  self = [super initWithFrame:NSMakeRect(0, 0, 350, 38)];
  if (self) {
    _owner = owner;
    _currentMatchIndex = 0;
    _totalMatches = 0;
    _lastQuery = @"";
    _isVisible = NO;

    self.material = NSVisualEffectMaterialPopover;
    self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.state = NSVisualEffectStateActive;
    self.wantsLayer = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.cornerRadius = 10.0;
    self.layer.masksToBounds = NO;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.4].CGColor;
    
    // Shadow
    self.shadow = [[NSShadow alloc] init];
    self.layer.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, -3);
    self.layer.shadowRadius = 8.0;
    self.layer.shadowOpacity = 1.0;

    self.translatesAutoresizingMaskIntoConstraints = NO;

    [self setupSubviews];
  }
  return self;
}

- (void)setupSubviews {
  // 1. Search Icon
  NSImageView* searchIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
  searchIcon.translatesAutoresizingMaskIntoConstraints = NO;
  searchIcon.imageScaling = NSImageScaleProportionallyDown;
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
    searchIcon.image = [[NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"Find"] imageWithSymbolConfiguration:cfg];
  }
  searchIcon.contentTintColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.75];
  [self addSubview:searchIcon];

  // 2. Search Text Field
  SlateFindSearchField* field = [[SlateFindSearchField alloc] initWithFrame:NSZeroRect];
  field.findBar = self;
  field.translatesAutoresizingMaskIntoConstraints = NO;
  field.bordered = NO;
  field.drawsBackground = NO;
  field.focusRingType = NSFocusRingTypeNone;
  field.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
  field.placeholderString = @"Find on Page";
  field.delegate = self;
  _searchField = field;
  [self addSubview:_searchField];

  // 3. Match Count Label
  _countLabel = [NSTextField labelWithString:@""];
  _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _countLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightMedium];
  _countLabel.textColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.85];
  _countLabel.alignment = NSTextAlignmentRight;
  _countLabel.maximumNumberOfLines = 1;
  [self addSubview:_countLabel];

  // 4. Separator
  NSBox* sep = [[NSBox alloc] initWithFrame:NSZeroRect];
  sep.boxType = NSBoxSeparator;
  sep.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:sep];

  // 5. Previous Button (Up chevron)
  _prevButton = [NSButton buttonWithTitle:@"" target:self action:@selector(prevButtonClicked:)];
  _prevButton.translatesAutoresizingMaskIntoConstraints = NO;
  _prevButton.bordered = NO;
  _prevButton.bezelStyle = NSBezelStyleInline;
  _prevButton.imagePosition = NSImageOnly;
  _prevButton.toolTip = @"Previous Match (⇧Enter or ⇧⌘G)";
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10.5 weight:NSFontWeightSemibold];
    _prevButton.image = [[NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:@"Previous Match"] imageWithSymbolConfiguration:cfg];
  }
  _prevButton.contentTintColor = NSColor.secondaryLabelColor;
  [self addSubview:_prevButton];

  // 6. Next Button (Down chevron)
  _nextButton = [NSButton buttonWithTitle:@"" target:self action:@selector(nextButtonClicked:)];
  _nextButton.translatesAutoresizingMaskIntoConstraints = NO;
  _nextButton.bordered = NO;
  _nextButton.bezelStyle = NSBezelStyleInline;
  _nextButton.imagePosition = NSImageOnly;
  _nextButton.toolTip = @"Next Match (Enter or ⌘G)";
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:10.5 weight:NSFontWeightSemibold];
    _nextButton.image = [[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Next Match"] imageWithSymbolConfiguration:cfg];
  }
  _nextButton.contentTintColor = NSColor.secondaryLabelColor;
  [self addSubview:_nextButton];

  // 7. Close Button
  _closeButton = [NSButton buttonWithTitle:@"" target:self action:@selector(closeButtonClicked:)];
  _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
  _closeButton.bordered = NO;
  _closeButton.bezelStyle = NSBezelStyleInline;
  _closeButton.imagePosition = NSImageOnly;
  _closeButton.toolTip = @"Done (Esc)";
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:9.5 weight:NSFontWeightBold];
    _closeButton.image = [[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Done"] imageWithSymbolConfiguration:cfg];
  }
  _closeButton.contentTintColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.8];
  [self addSubview:_closeButton];

  // Auto Layout Constraints
  [NSLayoutConstraint activateConstraints:@[
    [self.widthAnchor constraintEqualToConstant:350],
    [self.heightAnchor constraintEqualToConstant:38],

    [searchIcon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:11],
    [searchIcon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [searchIcon.widthAnchor constraintEqualToConstant:14],
    [searchIcon.heightAnchor constraintEqualToConstant:14],

    [_searchField.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:7],
    [_searchField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_searchField.trailingAnchor constraintEqualToAnchor:_countLabel.leadingAnchor constant:-6],

    [_countLabel.trailingAnchor constraintEqualToAnchor:sep.leadingAnchor constant:-8],
    [_countLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_countLabel.widthAnchor constraintGreaterThanOrEqualToConstant:20],

    [sep.trailingAnchor constraintEqualToAnchor:_prevButton.leadingAnchor constant:-5],
    [sep.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [sep.heightAnchor constraintEqualToConstant:18],
    [sep.widthAnchor constraintEqualToConstant:1],

    [_prevButton.trailingAnchor constraintEqualToAnchor:_nextButton.leadingAnchor constant:-2],
    [_prevButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_prevButton.widthAnchor constraintEqualToConstant:20],
    [_prevButton.heightAnchor constraintEqualToConstant:20],

    [_nextButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-6],
    [_nextButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_nextButton.widthAnchor constraintEqualToConstant:20],
    [_nextButton.heightAnchor constraintEqualToConstant:20],

    [_closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
    [_closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [_closeButton.widthAnchor constraintEqualToConstant:18],
    [_closeButton.heightAnchor constraintEqualToConstant:18]
  ]];
}

- (void)prevButtonClicked:(id)sender {
  [self findPrevious];
}

- (void)nextButtonClicked:(id)sender {
  [self findNext];
}

- (void)closeButtonClicked:(id)sender {
  [self hideAnimated];
}

- (void)controlTextDidChange:(NSNotification*)note {
  [self performSearchWithQuery:_searchField.stringValue];
}

- (void)showInView:(NSView*)containerView initialQuery:(NSString*)query {
  if (!containerView) return;

  if (self.superview != containerView) {
    [self removeFromSuperview];
    [containerView addSubview:self positioned:NSWindowAbove relativeTo:nil];

    [NSLayoutConstraint activateConstraints:@[
      [self.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-18],
      [self.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:12]
    ]];
  }

  self.alphaValue = 0.0;
  self.hidden = NO;
  _isVisible = YES;

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.16;
    ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    self.animator.alphaValue = 1.0;
  }];

  if (query.length > 0) {
    _searchField.stringValue = query;
  } else if (_lastQuery.length > 0 && _searchField.stringValue.length == 0) {
    _searchField.stringValue = _lastQuery;
  }

  [self.window makeFirstResponder:_searchField];
  if (_searchField.stringValue.length > 0) {
    [_searchField selectText:nil];
    [self performSearchWithQuery:_searchField.stringValue];
  } else {
    [self updateCountLabelWithCurrent:0 total:0];
  }
}

- (void)hideAnimated {
  if (!_isVisible) return;
  _isVisible = NO;

  [self clearHighlights];

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.14;
    ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    self.animator.alphaValue = 0.0;
  } completionHandler:^{
    if (!self->_isVisible) {
      self.hidden = YES;
    }
  }];

  // Restore focus to active web view
  if (self.targetWebView) {
    [self.window makeFirstResponder:self.targetWebView];
  }
}

- (void)syncWithWebView:(WKWebView*)webView {
  _targetWebView = webView;
  if (_isVisible && _searchField.stringValue.length > 0) {
    [self performSearchWithQuery:_searchField.stringValue];
  }
}

- (void)updateCountLabelWithCurrent:(NSInteger)current total:(NSInteger)total {
  _currentMatchIndex = current;
  _totalMatches = total;

  if (_searchField.stringValue.length == 0) {
    _countLabel.stringValue = @"";
    _countLabel.textColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.85];
    _prevButton.enabled = NO;
    _nextButton.enabled = NO;
    return;
  }

  if (total == 0) {
    _countLabel.stringValue = @"0 of 0";
    _countLabel.textColor = [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.35 alpha:1.0]; // Soft red
    _prevButton.enabled = NO;
    _nextButton.enabled = NO;
  } else {
    _countLabel.stringValue = [NSString stringWithFormat:@"%ld of %ld", (long)current, (long)total];
    _countLabel.textColor = [NSColor.secondaryLabelColor colorWithAlphaComponent:0.85];
    _prevButton.enabled = YES;
    _nextButton.enabled = YES;
  }
}

#pragma mark - Search Execution

- (void)performSearchWithQuery:(NSString*)query {
  _lastQuery = query ?: @"";
  WKWebView* webView = _targetWebView;
  if (!webView) return;

  // 1. PDFKit Search
  PDFView* pdfView = [SlatePDFOverlay findPDFViewInView:webView];
  if (pdfView && pdfView.document) {
    if (query.length == 0) {
      pdfView.highlightedSelections = @[];
      _pdfSelections = @[];
      [self updateCountLabelWithCurrent:0 total:0];
      return;
    }

    NSArray<PDFSelection*>* matches = [pdfView.document findString:query withOptions:NSCaseInsensitiveSearch];
    _pdfSelections = matches;
    pdfView.highlightedSelections = matches;

    if (matches.count > 0) {
      pdfView.currentSelection = matches.firstObject;
      [pdfView scrollSelectionToVisible:nil];
      [self updateCountLabelWithCurrent:1 total:matches.count];
    } else {
      [self updateCountLabelWithCurrent:0 total:0];
    }
    return;
  }

  // 2. Web DOM Search
  if (query.length == 0) {
    [self clearHighlights];
    [self updateCountLabelWithCurrent:0 total:0];
    return;
  }

  // Escape query for JS string
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:@[query] options:0 error:nil];
  NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
  NSString* queryArg = [jsonStr substringWithRange:NSMakeRange(1, jsonStr.length - 2)];

  NSString* js = [NSString stringWithFormat:
    @"(function() {"
    @"  window.__slateFind = window.__slateFind || {"
    @"    matches: [],"
    @"    currentIndex: -1,"
    @"    currentQuery: '',"
    @"    clear: function() {"
    @"      var marks = document.querySelectorAll('mark.__slate_find_mark');"
    @"      for (var i = 0; i < marks.length; i++) {"
    @"        var m = marks[i];"
    @"        var parent = m.parentNode;"
    @"        if (parent) {"
    @"          parent.replaceChild(document.createTextNode(m.textContent), m);"
    @"          parent.normalize();"
    @"        }"
    @"      }"
    @"      var style = document.getElementById('__slate_find_style');"
    @"      if (style) style.remove();"
    @"      this.matches = [];"
    @"      this.currentIndex = -1;"
    @"      this.currentQuery = '';"
    @"    },"
    @"    ensureStyle: function() {"
    @"      if (!document.getElementById('__slate_find_style')) {"
    @"        var s = document.createElement('style');"
    @"        s.id = '__slate_find_style';"
    @"        s.textContent = '"
    @"          mark.__slate_find_mark {"
    @"            background-color: rgba(255, 224, 102, 0.65) !important;"
    @"            color: inherit !important;"
    @"            border-radius: 2px !important;"
    @"            padding: 0 1px !important;"
    @"            box-shadow: 0 0 0 1px rgba(220, 180, 0, 0.4) !important;"
    @"            transition: background-color 0.1s ease !important;"
    @"          }"
    @"          mark.__slate_find_mark.__slate_find_active {"
    @"            background-color: #ff9500 !important;"
    @"            color: #000000 !important;"
    @"            box-shadow: 0 0 0 2px rgba(255, 149, 0, 0.7), 0 0 8px rgba(255, 149, 0, 0.5) !important;"
    @"            outline: 1.5px solid #cc6600 !important;"
    @"            font-weight: 500 !important;"
    @"          }';"
    @"        document.head.appendChild(s);"
    @"      }"
    @"    },"
    @"    search: function(query) {"
    @"      this.clear();"
    @"      if (!query || query.trim() === '') return { total: 0, current: 0 };"
    @"      this.currentQuery = query;"
    @"      this.ensureStyle();"
    @"      var walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {"
    @"        acceptNode: function(node) {"
    @"          if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;"
    @"          var tag = node.parentNode ? node.parentNode.tagName : '';"
    @"          if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'INPUT', 'SELECT'].indexOf(tag) !== -1) return NodeFilter.FILTER_REJECT;"
    @"          return NodeFilter.FILTER_ACCEPT;"
    @"        }"
    @"      });"
    @"      var textNodes = [];"
    @"      var n;"
    @"      while ((n = walker.nextNode())) textNodes.push(n);"
    @"      var regex = new RegExp(query.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'), 'gi');"
    @"      var allMarks = [];"
    @"      for (var j = 0; j < textNodes.length; j++) {"
    @"        var node = textNodes[j];"
    @"        var text = node.nodeValue;"
    @"        var match;"
    @"        var matchIndices = [];"
    @"        while ((match = regex.exec(text)) !== null) {"
    @"          matchIndices.push({ index: match.index, length: match[0].length, text: match[0] });"
    @"          if (matchIndices.length > 500) break;"
    @"        }"
    @"        if (matchIndices.length > 0) {"
    @"          var frag = document.createDocumentFragment();"
    @"          var lastIdx = 0;"
    @"          for (var k = 0; k < matchIndices.length; k++) {"
    @"            var m = matchIndices[k];"
    @"            if (m.index > lastIdx) {"
    @"              frag.appendChild(document.createTextNode(text.substring(lastIdx, m.index)));"
    @"            }"
    @"            var mark = document.createElement('mark');"
    @"            mark.className = '__slate_find_mark';"
    @"            mark.textContent = text.substring(m.index, m.index + m.length);"
    @"            frag.appendChild(mark);"
    @"            allMarks.push(mark);"
    @"            lastIdx = m.index + m.length;"
    @"          }"
    @"          if (lastIdx < text.length) {"
    @"            frag.appendChild(document.createTextNode(text.substring(lastIdx)));"
    @"          }"
    @"          if (node.parentNode) {"
    @"            node.parentNode.replaceChild(frag, node);"
    @"          }"
    @"        }"
    @"        if (allMarks.length >= 2000) break;"
    @"      }"
    @"      this.matches = allMarks;"
    @"      if (this.matches.length > 0) {"
    @"        this.currentIndex = 0;"
    @"        this.updateActive();"
    @"      }"
    @"      return { total: this.matches.length, current: this.matches.length > 0 ? this.currentIndex + 1 : 0 };"
    @"    },"
    @"    updateActive: function() {"
    @"      for (var i = 0; i < this.matches.length; i++) {"
    @"        if (i === this.currentIndex) {"
    @"          this.matches[i].classList.add('__slate_find_active');"
    @"          this.matches[i].scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });"
    @"        } else {"
    @"          this.matches[i].classList.remove('__slate_find_active');"
    @"        }"
    @"      }"
    @"    },"
    @"    next: function() {"
    @"      if (this.matches.length === 0) return { total: 0, current: 0 };"
    @"      this.currentIndex = (this.currentIndex + 1) %% this.matches.length;"
    @"      this.updateActive();"
    @"      return { total: this.matches.length, current: this.currentIndex + 1 };"
    @"    },"
    @"    prev: function() {"
    @"      if (this.matches.length === 0) return { total: 0, current: 0 };"
    @"      this.currentIndex = (this.currentIndex - 1 + this.matches.length) %% this.matches.length;"
    @"      this.updateActive();"
    @"      return { total: this.matches.length, current: this.currentIndex + 1 };"
    @"    }"
    @"  };"
    @"  return window.__slateFind.search(%@);"
    @"})();", queryArg];

  __weak typeof(self) weakSelf = self;
  [webView evaluateJavaScript:js completionHandler:^(id result, NSError* error) {
    if (!error && [result isKindOfClass:[NSDictionary class]]) {
      NSDictionary* dict = (NSDictionary*)result;
      NSInteger total = [dict[@"total"] integerValue];
      NSInteger current = [dict[@"current"] integerValue];
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateCountLabelWithCurrent:current total:total];
      });
    }
  }];
}

- (void)findNext {
  WKWebView* webView = _targetWebView;
  if (!webView) return;

  PDFView* pdfView = [SlatePDFOverlay findPDFViewInView:webView];
  if (pdfView && _pdfSelections.count > 0) {
    _currentMatchIndex = (_currentMatchIndex % _pdfSelections.count) + 1;
    pdfView.currentSelection = _pdfSelections[_currentMatchIndex - 1];
    [pdfView scrollSelectionToVisible:nil];
    [self updateCountLabelWithCurrent:_currentMatchIndex total:_pdfSelections.count];
    return;
  }

  NSString* js = @"window.__slateFind ? window.__slateFind.next() : { total: 0, current: 0 };";
  __weak typeof(self) weakSelf = self;
  [webView evaluateJavaScript:js completionHandler:^(id result, NSError* error) {
    if (!error && [result isKindOfClass:[NSDictionary class]]) {
      NSDictionary* dict = (NSDictionary*)result;
      NSInteger total = [dict[@"total"] integerValue];
      NSInteger current = [dict[@"current"] integerValue];
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateCountLabelWithCurrent:current total:total];
      });
    }
  }];
}

- (void)findPrevious {
  WKWebView* webView = _targetWebView;
  if (!webView) return;

  PDFView* pdfView = [SlatePDFOverlay findPDFViewInView:webView];
  if (pdfView && _pdfSelections.count > 0) {
    _currentMatchIndex = (_currentMatchIndex - 2 + _pdfSelections.count) % _pdfSelections.count + 1;
    pdfView.currentSelection = _pdfSelections[_currentMatchIndex - 1];
    [pdfView scrollSelectionToVisible:nil];
    [self updateCountLabelWithCurrent:_currentMatchIndex total:_pdfSelections.count];
    return;
  }

  NSString* js = @"window.__slateFind ? window.__slateFind.prev() : { total: 0, current: 0 };";
  __weak typeof(self) weakSelf = self;
  [webView evaluateJavaScript:js completionHandler:^(id result, NSError* error) {
    if (!error && [result isKindOfClass:[NSDictionary class]]) {
      NSDictionary* dict = (NSDictionary*)result;
      NSInteger total = [dict[@"total"] integerValue];
      NSInteger current = [dict[@"current"] integerValue];
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateCountLabelWithCurrent:current total:total];
      });
    }
  }];
}

- (void)clearHighlights {
  WKWebView* webView = _targetWebView;
  if (!webView) return;

  PDFView* pdfView = [SlatePDFOverlay findPDFViewInView:webView];
  if (pdfView) {
    pdfView.highlightedSelections = @[];
    _pdfSelections = @[];
    return;
  }

  NSString* js = @"if (window.__slateFind) { window.__slateFind.clear(); }";
  [webView evaluateJavaScript:js completionHandler:nil];
}

@end
