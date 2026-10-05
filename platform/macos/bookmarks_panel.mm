#import "platform/macos/bookmarks_panel.h"
#import "platform/macos/plate_components.h"
#import "platform/macos/browser_importer.h"
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSPasteboardType const kBookmarkUTIType = @"slate.bookmark.id";

#pragma mark - Helper Functions for Browser Import

static NSArray<SlateBookmark*>* ParseChromiumChildren(NSArray* children) {
  if (![children isKindOfClass:[NSArray class]]) return @[];
  NSMutableArray<SlateBookmark*>* items = [NSMutableArray array];
  for (id child in children) {
    if (![child isKindOfClass:[NSDictionary class]]) continue;
    NSString* type = child[@"type"];
    NSString* name = child[@"name"] ?: @"";
    if ([type isEqualToString:@"url"]) {
      NSString* url = child[@"url"];
      if (url.length && ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])) {
        [items addObject:[SlateBookmark siteWithTitle:name url:url]];
      }
    } else if ([type isEqualToString:@"folder"]) {
      NSArray* subKids = child[@"children"];
      NSArray<SlateBookmark*>* parsedSub = ParseChromiumChildren(subKids);
      [items addObject:[SlateBookmark folderWithTitle:name children:parsedSub]];
    }
  }
  return items;
}

static NSArray<SlateBookmark*>* ImportChromiumBookmarksFromPath(NSString* path) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @[];
  NSData* data = [NSData dataWithContentsOfFile:path];
  if (!data) return @[];
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![json isKindOfClass:[NSDictionary class]]) return @[];
  NSDictionary* roots = json[@"roots"];
  if (![roots isKindOfClass:[NSDictionary class]]) return @[];

  NSMutableArray<SlateBookmark*>* result = [NSMutableArray array];
  if (roots[@"bookmark_bar"]) {
    NSArray* kids = roots[@"bookmark_bar"][@"children"];
    [result addObjectsFromArray:ParseChromiumChildren(kids)];
  }
  if (roots[@"other"]) {
    NSArray* kids = roots[@"other"][@"children"];
    [result addObjectsFromArray:ParseChromiumChildren(kids)];
  }
  return result;
}

static NSArray<SlateBookmark*>* ParseSafariChildren(NSArray* children) {
  if (![children isKindOfClass:[NSArray class]]) return @[];
  NSMutableArray<SlateBookmark*>* items = [NSMutableArray array];
  for (id child in children) {
    if (![child isKindOfClass:[NSDictionary class]]) continue;
    NSString* type = child[@"WebBookmarkType"];
    if ([type isEqualToString:@"WebBookmarkTypeLeaf"]) {
      NSString* title = child[@"URIDictionary"][@"title"] ?: child[@"Title"] ?: @"";
      NSString* url = child[@"URLString"];
      if (url.length && ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])) {
        [items addObject:[SlateBookmark siteWithTitle:title url:url]];
      }
    } else if ([type isEqualToString:@"WebBookmarkTypeList"]) {
      NSString* title = child[@"Title"] ?: @"Folder";
      NSArray* subKids = child[@"Children"];
      NSArray<SlateBookmark*>* parsed = ParseSafariChildren(subKids);
      [items addObject:[SlateBookmark folderWithTitle:title children:parsed]];
    }
  }
  return items;
}

static NSArray<SlateBookmark*>* ImportSafariBookmarksFromPath(NSString* path) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @[];
  NSDictionary* plist = [NSDictionary dictionaryWithContentsOfFile:path];
  if (!plist) return @[];
  NSArray* children = plist[@"Children"];
  return ParseSafariChildren(children);
}

#pragma mark - Monogram / Favicon Mark Helper

static NSImage* MakeMark(NSString* letter, NSString* host, CGFloat size) {
  NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
  [img lockFocus];
  NSBezierPath* bg = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size, size) xRadius:3 yRadius:3];
  [[SlatePalette wash] setFill];
  [bg fill];

  NSString* ch = letter.length ? [letter substringToIndex:1].uppercaseString : @"•";
  NSDictionary* attrs = @{
    NSFontAttributeName: [NSFont systemFontOfSize:size * 0.65 weight:NSFontWeightMedium],
    NSForegroundColorAttributeName: [SlatePalette muted]
  };
  NSSize strSize = [ch sizeWithAttributes:attrs];
  NSRect strRect = NSMakeRect((size - strSize.width) / 2.0, (size - strSize.height) / 2.0, strSize.width, strSize.height);
  [ch drawInRect:strRect withAttributes:attrs];
  [img unlockFocus];
  return img;
}

#pragma mark - SlateFootRowButton

@interface SlateFootRowButton : NSButton
@property (nonatomic, copy) void (^clickHandler)(void);
@property (nonatomic, strong) NSTrackingArea* trackingArea;
@end

@implementation SlateFootRowButton
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) [self removeTrackingArea:self.trackingArea];
  self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent*)event {
  self.layer.backgroundColor = [SlatePalette wash].CGColor;
}

- (void)mouseExited:(NSEvent*)event {
  self.layer.backgroundColor = [NSColor clearColor].CGColor;
}

- (void)handleClick {
  if (self.clickHandler) self.clickHandler();
}
@end

#pragma mark - SlateBookmarkRowView

@interface SlateBookmarkRowView : NSView
@property (nonatomic, strong) SlateBookmark* node;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, assign) BOOL isOpen;
@property (nonatomic, assign) BOOL isHovered;
@property (nonatomic, assign) BOOL isTargetedForDrop;

@property (nonatomic, copy) void (^onToggleOpen)(void);
@property (nonatomic, copy) void (^onOpenURL)(NSURL* url);
@property (nonatomic, copy) void (^onMoveNode)(NSString* nodeId, NSString* folderId);
@property (nonatomic, copy) void (^onRemoveNode)(NSString* nodeId);

@property (nonatomic, strong) NSImageView* chevronView;
@property (nonatomic, strong) NSImageView* iconView;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSTextField* countBadge;
@property (nonatomic, strong) NSTrackingArea* trackingArea;
@end

@implementation SlateBookmarkRowView

- (instancetype)initWithNode:(SlateBookmark*)node
                       depth:(NSInteger)depth
                      isOpen:(BOOL)isOpen {
  self = [super initWithFrame:NSMakeRect(0, 0, 260, 28)];
  if (self) {
    _node = node;
    _depth = depth;
    _isOpen = isOpen;

    self.wantsLayer = YES;
    self.layer.cornerRadius = 8.0;
    if (@available(macOS 11.0, *)) {
      self.layer.cornerCurve = kCACornerCurveContinuous;
    }

    CGFloat x = (CGFloat)depth * 18.0 + 10.0;
    CGFloat y = (28.0 - 15.0) / 2.0;

    if (node.isFolder) {
      _chevronView = [[NSImageView alloc] initWithFrame:NSMakeRect(x, y + 2, 10, 11)];
      NSImage* chev = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil];
      if (chev) {
        NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightSemibold];
        _chevronView.image = [chev imageWithSymbolConfiguration:cfg];
      }
      _chevronView.contentTintColor = [SlatePalette faint];
      if (isOpen) {
        _chevronView.frameCenterRotation = -90.0; // Point downward
      }
      [self addSubview:_chevronView];
      x += 14.0;

      _iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(x, y, 15, 15)];
      NSImage* fImg = [NSImage imageWithSystemSymbolName:@"folder.fill" accessibilityDescription:@"Folder"];
      if (fImg) {
        NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular];
        _iconView.image = [fImg imageWithSymbolConfiguration:cfg];
      }
      _iconView.contentTintColor = [SlatePalette muted];
      [self addSubview:_iconView];
      x += 21.0;
    } else {
      x += 12.0;
      _iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(x, y, 15, 15)];
      NSString* host = node.host ?: @"";
      NSString* letter = host.length ? [host substringToIndex:1] : (node.title.length ? [node.title substringToIndex:1] : @"•");
      _iconView.image = MakeMark(letter, host, 15.0);
      [self addSubview:_iconView];
      x += 21.0;
    }

    _titleLabel = [NSTextField labelWithString:node.title ?: @"Untitled"];
    _titleLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    _titleLabel.textColor = [SlatePalette ink];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.frame = NSMakeRect(x, 5, MAX(60, NSWidth(self.bounds) - x - 40), 18);
    _titleLabel.autoresizingMask = NSViewWidthSizable;
    [self addSubview:_titleLabel];

    if (node.isFolder && node.children.count) {
      NSUInteger totalKids = [SlateBookmarks countNodes:node.children];
      if (totalKids > 0) {
        _countBadge = [NSTextField labelWithString:[NSString stringWithFormat:@"%lu", (unsigned long)totalKids]];
        _countBadge.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
        _countBadge.textColor = [SlatePalette faint];
        _countBadge.alignment = NSTextAlignmentRight;
        _countBadge.frame = NSMakeRect(NSWidth(self.bounds) - 36, 5, 26, 18);
        _countBadge.autoresizingMask = NSViewMinXMargin;
        [self addSubview:_countBadge];
      }
    }

    [self registerForDraggedTypes:@[NSPasteboardTypeString, kBookmarkUTIType]];
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
  _isHovered = YES;
  [self updateBackground];
}

- (void)mouseExited:(NSEvent*)event {
  _isHovered = NO;
  [self updateBackground];
}

- (void)updateBackground {
  if (_isTargetedForDrop) {
    self.layer.backgroundColor = [SlatePalette faint].CGColor;
  } else if (_isHovered) {
    self.layer.backgroundColor = [SlatePalette wash].CGColor;
  } else {
    self.layer.backgroundColor = [NSColor clearColor].CGColor;
  }
}

- (void)mouseDown:(NSEvent*)event {
  if (event.clickCount == 1) {
    if (_node.isFolder) {
      if (_onToggleOpen) _onToggleOpen();
    } else {
      if (_onOpenURL && _node.url.length) {
        NSURL* u = [NSURL URLWithString:_node.url];
        if (u) _onOpenURL(u);
      }
    }
  }
}

- (NSMenu*)menuForEvent:(NSEvent*)event {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Bookmark"];
  __weak typeof(self) weakSelf = self;

  if (!_node.isFolder && _node.url.length) {
    NSMenuItem* openItem = [menu addItemWithTitle:@"Open" action:@selector(openAction:) keyEquivalent:@""];
    openItem.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
  }

  NSMenuItem* moveMenu = [menu addItemWithTitle:@"Move to" action:nil keyEquivalent:@""];
  NSMenu* moveSubmenu = [[NSMenu alloc] initWithTitle:@"Move to"];

  NSMenuItem* topLevel = [moveSubmenu addItemWithTitle:@"Top Level" action:@selector(moveToFolderAction:) keyEquivalent:@""];
  topLevel.target = self;
  topLevel.representedObject = @"";

  NSArray<NSDictionary*>* allFolders = [SlateBookmarks foldersForNodes:[SlateBookmarks sharedStore].roots depth:0];
  NSMutableArray<NSDictionary*>* validTargets = [NSMutableArray array];
  for (NSDictionary* dict in allFolders) {
    SlateBookmark* fNode = dict[@"node"];
    if (![SlateBookmarks node:_node holdsIdentifier:fNode.identifier]) {
      [validTargets addObject:dict];
    }
  }

  if (validTargets.count) {
    [moveSubmenu addItem:[NSMenuItem separatorItem]];
    for (NSDictionary* dict in validTargets) {
      SlateBookmark* fNode = dict[@"node"];
      NSInteger d = [dict[@"depth"] integerValue];
      NSString* indent = [@"" stringByPaddingToLength:d * 3 withString:@" " startingAtIndex:0];
      NSString* itemTitle = [NSString stringWithFormat:@"%@%@", indent, fNode.title];
      NSMenuItem* fItem = [moveSubmenu addItemWithTitle:itemTitle action:@selector(moveToFolderAction:) keyEquivalent:@""];
      fItem.target = self;
      fItem.representedObject = fNode.identifier;
    }
  }
  moveMenu.submenu = moveSubmenu;

  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem* removeItem = [menu addItemWithTitle:@"Remove" action:@selector(removeAction:) keyEquivalent:@""];
  removeItem.target = self;

  return menu;
}

- (void)openAction:(id)sender {
  if (!_node.isFolder && _node.url.length && _onOpenURL) {
    NSURL* u = [NSURL URLWithString:_node.url];
    if (u) _onOpenURL(u);
  }
}

- (void)moveToFolderAction:(NSMenuItem*)item {
  NSString* folderId = [item.representedObject isKindOfClass:[NSString class]] ? item.representedObject : nil;
  if (!folderId.length) folderId = nil;
  if (_onMoveNode) _onMoveNode(_node.identifier, folderId);
}

- (void)removeAction:(id)sender {
  if (_onRemoveNode) _onRemoveNode(_node.identifier);
}

#pragma mark - Drag Source

- (void)mouseDragged:(NSEvent*)event {
  NSPasteboardItem* pbItem = [[NSPasteboardItem alloc] init];
  [pbItem setString:_node.identifier forType:NSPasteboardTypeString];
  [pbItem setString:_node.identifier forType:kBookmarkUTIType];

  NSDraggingItem* dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];
  [dragItem setDraggingFrame:self.bounds contents:[self bitmapImageRepForCachingDisplayInRect:self.bounds]];

  [self beginDraggingSessionWithItems:@[dragItem] event:event source:(id<NSDraggingSource>)self.superview];
}

#pragma mark - Drag Destination (Folder)

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  if (!_node.isFolder) return NSDragOperationNone;
  NSPasteboard* pb = [sender draggingPasteboard];
  NSString* draggedId = [pb stringForType:kBookmarkUTIType] ?: [pb stringForType:NSPasteboardTypeString];
  if (!draggedId.length || [draggedId isEqualToString:_node.identifier]) return NSDragOperationNone;

  SlateBookmark* draggedNode = [[SlateBookmarks sharedStore] findNodeWithIdentifier:draggedId];
  if (draggedNode && [SlateBookmarks node:draggedNode holdsIdentifier:_node.identifier]) {
    return NSDragOperationNone; // Cannot drop folder into its own descendant
  }

  _isTargetedForDrop = YES;
  [self updateBackground];
  return NSDragOperationMove;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  _isTargetedForDrop = NO;
  [self updateBackground];
}

- (BOOL)prepareForDropOperation:(id<NSDraggingInfo>)sender {
  return _node.isFolder;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  if (!_node.isFolder) return NO;
  _isTargetedForDrop = NO;
  [self updateBackground];

  NSPasteboard* pb = [sender draggingPasteboard];
  NSString* draggedId = [pb stringForType:kBookmarkUTIType] ?: [pb stringForType:NSPasteboardTypeString];
  if (!draggedId.length) return NO;

  if (_onMoveNode) {
    _onMoveNode(draggedId, _node.identifier);
    return YES;
  }
  return NO;
}

@end

#pragma mark - SlateBookmarkOutlineView Implementation

@interface SlateBookmarkOutlineView ()
@property (nonatomic, strong) NSMutableSet<NSString*>* expandedNodeIDs;
@property (nonatomic, strong) NSView* containerView;
@property (nonatomic, assign) BOOL isTargetedForRootDrop;
@end

@implementation SlateBookmarkOutlineView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _expandedNodeIDs = [NSMutableSet set];
    self.wantsLayer = YES;
    _containerView = [[NSView alloc] initWithFrame:self.bounds];
    _containerView.autoresizingMask = NSViewWidthSizable;
    [self addSubview:_containerView];

    [self registerForDraggedTypes:@[NSPasteboardTypeString, kBookmarkUTIType]];
    [self reloadData];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadData)
                                                 name:SlateBookmarksChangedNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
  return YES;
}

- (void)reloadData {
  for (NSView* v in [_containerView.subviews copy]) [v removeFromSuperview];

  __block CGFloat y = 2.0;
  CGFloat width = NSWidth(self.bounds);
  SlateBookmarks* store = [SlateBookmarks sharedStore];

  __weak typeof(self) weakSelf = self;

  void (^renderNodes)(NSArray<SlateBookmark*>*, NSInteger);
  __block void (^weakRender)(NSArray<SlateBookmark*>*, NSInteger);

  weakRender = renderNodes = ^(NSArray<SlateBookmark*>* nodes, NSInteger depth) {
    for (SlateBookmark* node in nodes) {
      BOOL isOpen = [weakSelf.expandedNodeIDs containsObject:node.identifier];
      SlateBookmarkRowView* row = [[SlateBookmarkRowView alloc] initWithNode:node
                                                                       depth:depth
                                                                      isOpen:isOpen];
      row.frame = NSMakeRect(4, y, width - 8, 28);
      row.autoresizingMask = NSViewWidthSizable;

      row.onToggleOpen = ^{
        if ([weakSelf.expandedNodeIDs containsObject:node.identifier]) {
          [weakSelf.expandedNodeIDs removeObject:node.identifier];
        } else {
          [weakSelf.expandedNodeIDs addObject:node.identifier];
        }
        [weakSelf reloadData];
      };

      row.onOpenURL = ^(NSURL* u) {
        if (weakSelf.onOpenURL) weakSelf.onOpenURL(u);
      };

      row.onMoveNode = ^(NSString* nId, NSString* fId) {
        [[SlateBookmarks sharedStore] moveWithIdentifier:nId intoFolderWithIdentifier:fId];
        if (weakSelf.onStructureChanged) weakSelf.onStructureChanged();
      };

      row.onRemoveNode = ^(NSString* nId) {
        [[SlateBookmarks sharedStore] removeWithIdentifier:nId];
        if (weakSelf.onStructureChanged) weakSelf.onStructureChanged();
      };

      [weakSelf.containerView addSubview:row];
      y += 29.0;

      if (node.isFolder && isOpen) {
        if (node.children.count) {
          weakRender(node.children, depth + 1);
        } else {
          // Render Empty state
          CGFloat x = (CGFloat)(depth + 1) * 18.0 + 26.0;
          NSTextField* emptyLabel = [NSTextField labelWithString:@"Empty"];
          emptyLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
          emptyLabel.textColor = [SlatePalette faint];
          emptyLabel.frame = NSMakeRect(x, y + 4, width - x - 10, 18);
          [weakSelf.containerView addSubview:emptyLabel];
          y += 24.0;
        }
      }
    }
  };

  renderNodes(store.roots, 0);

  y += 4.0;
  NSRect f = self.frame;
  f.size.height = y;
  self.frame = f;
  _containerView.frame = NSMakeRect(0, 0, width, y);
}

#pragma mark - Root Drop Destination

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  _isTargetedForRootDrop = YES;
  return NSDragOperationMove;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  _isTargetedForRootDrop = NO;
}

- (BOOL)prepareForDropOperation:(id<NSDraggingInfo>)sender {
  return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  _isTargetedForRootDrop = NO;
  NSPasteboard* pb = [sender draggingPasteboard];
  NSString* draggedId = [pb stringForType:kBookmarkUTIType] ?: [pb stringForType:NSPasteboardTypeString];
  if (!draggedId.length) return NO;

  [[SlateBookmarks sharedStore] moveWithIdentifier:draggedId intoFolderWithIdentifier:nil];
  if (self.onStructureChanged) self.onStructureChanged();
  return YES;
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
  return NSDragOperationMove;
}

@end

#pragma mark - SlateBookmarksDropdown Implementation

@interface SlateBookmarksDropdown ()
@property (nonatomic, strong) NSVisualEffectView* glassView;
@property (nonatomic, strong) NSScrollView* scrollView;
@property (nonatomic, strong) SlateBookmarkOutlineView* outlineView;
@property (nonatomic, strong) NSTextField* emptyLabel;
@property (nonatomic, strong) NSView* footerView;
@property (nonatomic, strong) id mouseMonitor;
@property (nonatomic, weak) NSView* currentAnchor;
@end

@implementation SlateBookmarksDropdown

+ (instancetype)sharedDropdown {
  static SlateBookmarksDropdown* s_dropdown = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_dropdown = [[SlateBookmarksDropdown alloc] init];
  });
  return s_dropdown;
}

+ (BOOL)isShown {
  return [SlateBookmarksDropdown sharedDropdown].isVisible;
}

+ (void)hide {
  [[SlateBookmarksDropdown sharedDropdown] hideDropdown];
}

- (instancetype)init {
  self = [super initWithContentRect:NSMakeRect(0, 0, 280, 200)
                          styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                            backing:NSBackingStoreBuffered
                              defer:NO];
  if (self) {
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = YES;
    self.level = NSPopUpMenuWindowLevel;
    self.hidesOnDeactivate = YES;
    self.releasedWhenClosed = NO;

    _glassView = [[NSVisualEffectView alloc] initWithFrame:self.contentView.bounds];
    _glassView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _glassView.material = NSVisualEffectMaterialMenu;
    _glassView.state = NSVisualEffectStateActive;
    _glassView.wantsLayer = YES;
    _glassView.layer.cornerRadius = 14.0;
    if (@available(macOS 11.0, *)) {
      _glassView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _glassView.layer.masksToBounds = YES;
    _glassView.layer.borderWidth = 0.5;
    _glassView.layer.borderColor = [SlatePalette hairline].CGColor;
    self.contentView = _glassView;

    [self setupContent];
  }
  return self;
}

- (void)setupContent {
  for (NSView* v in [_glassView.subviews copy]) [v removeFromSuperview];

  SlateBookmarks* store = [SlateBookmarks sharedStore];
  CGFloat width = 280.0;
  CGFloat bodyHeight = 0;

  if (store.isEmpty) {
    bodyHeight = 44.0;
    _emptyLabel = [NSTextField labelWithString:@"No bookmarks yet"];
    _emptyLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
    _emptyLabel.textColor = [SlatePalette muted];
    _emptyLabel.frame = NSMakeRect(14, 14, width - 28, 20);
  } else {
    _outlineView = [[SlateBookmarkOutlineView alloc] initWithFrame:NSMakeRect(0, 0, width - 12, 100)];
    __weak typeof(self) weakSelf = self;
    _outlineView.onOpenURL = ^(NSURL* url) {
      [weakSelf hideDropdown];
      if ([weakSelf.owner respondsToSelector:@selector(openHomeAddress:)]) {
        [weakSelf.owner openHomeAddress:url.absoluteString];
      }
    };
    _outlineView.onStructureChanged = ^{
      [weakSelf refresh];
    };

    bodyHeight = MIN(320.0, MAX(60.0, NSHeight(_outlineView.frame)));
    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(6, 68, width - 12, bodyHeight)];
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.documentView = _outlineView;
  }

  CGFloat footHeight = 64.0;
  CGFloat totalHeight = bodyHeight + 1.0 + footHeight + 12.0;

  if (store.isEmpty) {
    _emptyLabel.frame = NSMakeRect(14, footHeight + 14, width - 28, 20);
    [_glassView addSubview:_emptyLabel];
  } else {
    _scrollView.frame = NSMakeRect(6, footHeight + 6, width - 12, bodyHeight);
    [_glassView addSubview:_scrollView];
  }

  // Divider
  NSBox* div = [[NSBox alloc] initWithFrame:NSMakeRect(0, footHeight, width, 1)];
  div.boxType = NSBoxSeparator;
  [_glassView addSubview:div];

  // Foot Actions
  _footerView = [[NSView alloc] initWithFrame:NSMakeRect(6, 4, width - 12, footHeight - 6)];
  __weak typeof(self) weakSelf = self;

  // 1. Add / Remove Bookmark
  NSView* footRow1 = [self makeFootRowWithSymbol:@"bookmark" title:@"Add This Page" action:^{
    [weakSelf hideDropdown];
    if ([weakSelf.owner respondsToSelector:@selector(toggleBookmark:)]) {
      [weakSelf.owner toggleBookmark:nil];
    }
  }];
  footRow1.frame = NSMakeRect(0, 28, width - 12, 26);
  [_footerView addSubview:footRow1];

  // 2. Manage Bookmarks...
  NSView* footRow2 = [self makeFootRowWithSymbol:nil title:@"Manage Bookmarks…" action:^{
    [weakSelf hideDropdown];
    [[SlateBookmarksPanel sharedPanel] showBookmarksManager];
  }];
  footRow2.frame = NSMakeRect(0, 2, width - 12, 26);
  [_footerView addSubview:footRow2];

  [_glassView addSubview:_footerView];

  NSRect f = self.frame;
  f.size.width = width;
  f.size.height = totalHeight;
  [self setFrame:f display:YES];
}

- (NSView*)makeFootRowWithSymbol:(NSString*)symbol title:(NSString*)title action:(void(^)(void))action {
  SlateFootRowButton* btn = [[SlateFootRowButton alloc] initWithFrame:NSMakeRect(0, 0, 268, 26)];
  btn.bordered = NO;
  btn.bezelStyle = NSBezelStyleRegularSquare;
  btn.alignment = NSTextAlignmentLeft;
  btn.title = [NSString stringWithFormat:@"   %@", title];
  btn.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular];
  btn.contentTintColor = [SlatePalette ink];
  btn.wantsLayer = YES;
  btn.layer.cornerRadius = 6.0;
  if (@available(macOS 11.0, *)) {
    btn.layer.cornerCurve = kCACornerCurveContinuous;
  }

  if (symbol.length) {
    NSImage* sym = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    if (sym) {
      NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular];
      btn.image = [sym imageWithSymbolConfiguration:cfg];
      btn.imagePosition = NSImageLeading;
    }
  }

  btn.target = btn;
  btn.action = @selector(handleClick);
  btn.clickHandler = action;
  return btn;
}

- (void)refresh {
  [self setupContent];
  if (_currentAnchor) {
    [self updatePositionForAnchor:_currentAnchor];
  }
}

- (void)updatePositionForAnchor:(NSView*)anchor {
  NSRect anchorScreen = [anchor.window convertRectToScreen:[anchor convertRect:anchor.bounds toView:nil]];
  CGFloat width = NSWidth(self.frame);
  CGFloat height = NSHeight(self.frame);

  CGFloat x = anchorScreen.origin.x - (width - anchorScreen.size.width) / 2.0;
  CGFloat y = anchorScreen.origin.y - height - 6.0;

  NSRect screenFrame = anchor.window.screen ? anchor.window.screen.visibleFrame : NSScreen.mainScreen.visibleFrame;
  x = MAX(screenFrame.origin.x + 8.0, MIN(x, NSMaxX(screenFrame) - width - 8.0));
  y = MAX(screenFrame.origin.y + 8.0, y);

  [self setFrame:NSMakeRect(x, y, width, height) display:YES];
}

- (void)showForAnchor:(NSView*)anchor inWindow:(NSWindow*)window {
  _currentAnchor = anchor;
  if (!anchor || !window) return;

  [self refresh];
  [self updatePositionForAnchor:anchor];

  if (self.parentWindow != window) {
    [window addChildWindow:self ordered:NSWindowAbove];
  }
  [self orderFront:nil];

  if (_mouseMonitor) {
    [NSEvent removeMonitor:_mouseMonitor];
    _mouseMonitor = nil;
  }

  __weak typeof(self) weakSelf = self;
  _mouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                                        handler:^NSEvent*(NSEvent* event) {
    if (!weakSelf || !weakSelf.isVisible) return event;
    if (event.window == weakSelf) return event;
    if (event.window == anchor.window) {
      NSPoint loc = [anchor convertPoint:event.locationInWindow fromView:nil];
      if (NSPointInRect(loc, anchor.bounds)) return event;
    }
    [weakSelf hideDropdown];
    return event;
  }];
}

- (void)toggleForAnchor:(NSView*)anchor inWindow:(NSWindow*)window {
  if (self.isVisible) {
    [self hideDropdown];
  } else {
    [self showForAnchor:anchor inWindow:window];
  }
}

- (void)hideDropdown {
  if (!self.isVisible) return;
  if (_mouseMonitor) {
    [NSEvent removeMonitor:_mouseMonitor];
    _mouseMonitor = nil;
  }
  if (self.parentWindow) {
    [self.parentWindow removeChildWindow:self];
  }
  [self orderOut:nil];
}

- (void)cancelOperation:(id)sender {
  [self hideDropdown];
}

@end

#pragma mark - SlateBookmarksPanel Implementation

@interface SlateBookmarksPanel ()
@property (nonatomic, strong) SlatePlateView* plateView;
@property (nonatomic, strong) SlateCardView* cardView;
@property (nonatomic, strong) SlateBookmarkOutlineView* outlineView;
@property (nonatomic, strong) NSScrollView* scrollView;
@property (nonatomic, strong) NSTextField* countLabel;
@end

@implementation SlateBookmarksPanel

+ (instancetype)sharedPanel {
  static SlateBookmarksPanel* s_panel = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_panel = [[SlateBookmarksPanel alloc] initWithContentRect:NSMakeRect(0, 0, 600, 480)
                                                     styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    s_panel.title = @"Bookmarks";
    s_panel.releasedWhenClosed = NO;
    [s_panel setupPlateUI];
  });
  return s_panel;
}

+ (BOOL)isShown {
  return [SlateBookmarksPanel sharedPanel].isVisible;
}

- (void)setupPlateUI {
  self.minSize = NSMakeSize(500, 360);
  __weak typeof(self) weakSelf = self;

  _plateView = [[SlatePlateView alloc] initWithTitle:@"Bookmarks" width:600 close:^{
    [weakSelf hidePanel];
  }];
  _plateView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  _plateView.frame = self.contentView.bounds;
  [self.contentView addSubview:_plateView];

  [self refresh];
}

- (void)refresh {
  SlateBookmarks* store = [SlateBookmarks sharedStore];
  __weak typeof(self) weakSelf = self;

  // Content Area
  _cardView = [[SlateCardView alloc] initWithFrame:NSMakeRect(0, 0, 560, 320)];
  _cardView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  if (store.isEmpty) {
    SlateNothingView* nothing = [SlateNothingView nothingWithText:@"Nothing kept yet. Add this page with ⇧⌘B, or bring yours in below."];
    nothing.frame = NSMakeRect(20, 140, 520, 30);
    nothing.alignment = NSTextAlignmentCenter;
    [_cardView addSubview:nothing];
  } else {
    _outlineView = [[SlateBookmarkOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 550, 300)];
    _outlineView.onOpenURL = ^(NSURL* url) {
      [weakSelf hidePanel];
      if ([weakSelf.owner respondsToSelector:@selector(openHomeAddress:)]) {
        [weakSelf.owner openHomeAddress:url.absoluteString];
      }
    };
    _outlineView.onStructureChanged = ^{
      [weakSelf refresh];
    };

    _scrollView = [[NSScrollView alloc] initWithFrame:_cardView.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.documentView = _outlineView;
    [_cardView addSubview:_scrollView];
  }
  [_plateView setContent:_cardView];

  // Foot Area
  NSView* footView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 32)];
  footView.autoresizingMask = NSViewWidthSizable;

  CGFloat x = 6.0;
  NSTextField* bringLabel = [SlateCaptionLabel captionWithText:@"Bring in from"];
  bringLabel.frame = NSMakeRect(x, 7, 85, 18);
  [footView addSubview:bringLabel];
  x += 92.0;

  // Chrome Pill
  if (slate::BrowserImporter::HasChromeInstalled()) {
    SlateQuickButton* chromePill = [SlateQuickButton quickWithTitle:@"Google Chrome" action:^{
      NSString* path = [NSString stringWithUTF8String:slate::BrowserImporter::GetChromeProfilePath().c_str()];
      NSString* bPath = [path stringByAppendingPathComponent:@"Bookmarks"];
      NSArray<SlateBookmark*>* imported = ImportChromiumBookmarksFromPath(bPath);
      [[SlateBookmarks sharedStore] takeNodes:imported fromBrowserNamed:@"Google Chrome"];
      [weakSelf refresh];
    }];
    chromePill.frame = NSMakeRect(x, 5, NSWidth(chromePill.frame), 22);
    [footView addSubview:chromePill];
    x += NSWidth(chromePill.frame) + 8.0;
  }

  // Safari Pill
  if (slate::BrowserImporter::HasSafariInstalled()) {
    SlateQuickButton* safariPill = [SlateQuickButton quickWithTitle:@"Safari" action:^{
      NSString* home = NSHomeDirectory();
      NSString* bPath = [home stringByAppendingPathComponent:@"Library/Safari/Bookmarks.plist"];
      NSArray<SlateBookmark*>* imported = ImportSafariBookmarksFromPath(bPath);
      [[SlateBookmarks sharedStore] takeNodes:imported fromBrowserNamed:@"Safari"];
      [weakSelf refresh];
    }];
    safariPill.frame = NSMakeRect(x, 5, NSWidth(safariPill.frame), 22);
    [footView addSubview:safariPill];
    x += NSWidth(safariPill.frame) + 8.0;
  }

  // Total Count Label on Right
  NSUInteger total = store.count;
  NSString* countStr = (total == 1) ? @"1 bookmark" : [NSString stringWithFormat:@"%lu bookmarks", (unsigned long)total];
  _countLabel = [SlateCaptionLabel captionWithText:countStr];
  _countLabel.alignment = NSTextAlignmentRight;
  _countLabel.frame = NSMakeRect(NSWidth(footView.bounds) - 130, 7, 120, 18);
  _countLabel.autoresizingMask = NSViewMinXMargin;
  [footView addSubview:_countLabel];

  [_plateView setFoot:footView];
}

- (void)showBookmarksManager {
  [self refresh];
  [self center];
  [self makeKeyAndOrderFront:nil];
}

- (void)hidePanel {
  [self orderOut:nil];
}

@end

#pragma mark - SlateBookmarkMenu Implementation

@implementation SlateBookmarkMenu

+ (void)popUpFolder:(SlateBookmark*)folder forView:(NSView*)view owner:(id)owner {
  if (!folder || !folder.isFolder || !view) return;
  NSMenu* menu = [[NSMenu alloc] initWithTitle:folder.title ?: @"Bookmarks"];

  [self populateMenu:menu withChildren:folder.children owner:owner];

  if (menu.numberOfItems == 0) {
    NSMenuItem* emptyItem = [menu addItemWithTitle:@"Empty" action:nil keyEquivalent:@""];
    emptyItem.enabled = NO;
  }

  NSRect rect = view.bounds;
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMaxY(rect) + 2) inView:view];
}

+ (void)populateMenu:(NSMenu*)menu withChildren:(NSArray<SlateBookmark*>*)children owner:(id)owner {
  for (SlateBookmark* child in children) {
    if (child.isFolder) {
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:child.title ?: @"Folder" action:nil keyEquivalent:@""];
      NSMenu* sub = [[NSMenu alloc] initWithTitle:child.title ?: @"Folder"];
      [self populateMenu:sub withChildren:child.children owner:owner];
      if (sub.numberOfItems == 0) {
        NSMenuItem* emptyItem = [sub addItemWithTitle:@"Empty" action:nil keyEquivalent:@""];
        emptyItem.enabled = NO;
      }
      item.submenu = sub;
      [menu addItem:item];
    } else if (child.url.length) {
      NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:child.title ?: @"Untitled"
                                                    action:@selector(bookmarkMenuItemClicked:)
                                             keyEquivalent:@""];
      item.target = self;
      item.representedObject = @{ @"url": child.url, @"owner": owner ?: [NSNull null] };
      [menu addItem:item];
    }
  }
}

+ (void)bookmarkMenuItemClicked:(NSMenuItem*)item {
  NSDictionary* dict = item.representedObject;
  if (![dict isKindOfClass:[NSDictionary class]]) return;
  NSString* url = dict[@"url"];
  id owner = dict[@"owner"];
  if (url.length && owner != [NSNull null] && [owner respondsToSelector:@selector(openHomeAddress:)]) {
    [(id<SlateBookmarksOwner>)owner openHomeAddress:url];
  }
}

+ (void)populateMenu:(NSMenu*)menu withBookmarks:(SlateBookmarks*)store owner:(id)owner {
  if (!menu || !store) return;
  [self populateMenu:menu withChildren:store.roots owner:owner];
}

@end
