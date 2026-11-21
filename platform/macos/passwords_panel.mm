// File purpose: Implements the native searchable Slate Passwords vault with Touch ID / macOS
// authentication, built-in strong password generator, strength meter, inline add/edit, and import.

#import "platform/macos/passwords_panel.h"
#import "platform/macos/browser_importer.h"
#import "platform/macos/plate_components.h"
#import <LocalAuthentication/LocalAuthentication.h>
#include <cstdlib>
#include <memory>

static NSString* SlateGenerateStrongPassword(void) {
 static NSString* const kLower = @"abcdefghijkmnopqrstuvwxyz";
 static NSString* const kUpper = @"ABCDEFGHJKLMNPQRSTUVWXYZ";
 static NSString* const kDigits = @"23456789";
 NSString* const all = [[kLower stringByAppendingString:kUpper] stringByAppendingString:kDigits];
 auto pick = [](NSString* pool) -> unichar {
  return [pool characterAtIndex:arc4random_uniform((uint32_t)pool.length)];
 };
 NSMutableArray<NSString*>* chars = [NSMutableArray arrayWithCapacity:16];
 [chars addObject:[NSString stringWithFormat:@"%C", pick(kUpper)]];
 [chars addObject:[NSString stringWithFormat:@"%C", pick(kLower)]];
 [chars addObject:[NSString stringWithFormat:@"%C", pick(kDigits)]];
 [chars addObject:[NSString stringWithFormat:@"%C", pick(kDigits)]];
 while (chars.count < 16) {
  [chars addObject:[NSString stringWithFormat:@"%C", pick(all)]];
 }
 for (NSInteger i = (NSInteger)chars.count - 1; i > 0; --i) {
  NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
  [chars exchangeObjectAtIndex:(NSUInteger)i withObjectAtIndex:j];
 }
 NSMutableString* out = [NSMutableString stringWithCapacity:19];
 for (NSUInteger i = 0; i < 16; ++i) {
  if (i > 0 && (i % 4) == 0) [out appendString:@"-"];
  [out appendString:chars[i]];
 }
 return out;
}

static NSColor* SlateSiteBadgeColor(NSString* host) {
 NSUInteger h = host.hash;
 CGFloat hue = ((h >> 4) & 0xFF) / 255.0;
 return [NSColor colorWithHue:hue saturation:0.42 brightness:0.62 alpha:1.0];
}

static void SlateEvaluatePasswordStrength(NSString* password, NSString** outLabel, NSColor** outColor, CGFloat* outRatio) {
 NSUInteger len = password.length;
 if (len == 0) {
  *outLabel = @"";
  *outColor = NSColor.clearColor;
  *outRatio = 0;
  return;
 }
 BOOL hasLower = [password rangeOfCharacterFromSet:NSCharacterSet.lowercaseLetterCharacterSet].location != NSNotFound;
 BOOL hasUpper = [password rangeOfCharacterFromSet:NSCharacterSet.uppercaseLetterCharacterSet].location != NSNotFound;
 BOOL hasDigit = [password rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
 BOOL hasSymbol = [password rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet].invertedSet].location != NSNotFound;
 int score = (hasLower ? 1 : 0) + (hasUpper ? 1 : 0) + (hasDigit ? 1 : 0) + (hasSymbol ? 1 : 0);
 if (len >= 14 && score >= 3) {
  *outLabel = @"Strong";
  *outColor = NSColor.systemGreenColor;
  *outRatio = 1.0;
 } else if (len >= 10 && score >= 2) {
  *outLabel = @"Good";
  *outColor = NSColor.systemTealColor;
  *outRatio = 0.72;
 } else if (len >= 7) {
  *outLabel = @"Fair";
  *outColor = NSColor.systemOrangeColor;
  *outRatio = 0.45;
 } else {
  *outLabel = @"Weak";
  *outColor = NSColor.systemRedColor;
  *outRatio = 0.22;
 }
}

@interface SlatePasswordGroundView : NSView
@end
@implementation SlatePasswordGroundView
- (void)drawRect:(NSRect)rect { [[SlatePalette ground] setFill]; NSRectFill(rect); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end

@interface SlatePasswordsPanel () <NSTextFieldDelegate>
@property(nonatomic, assign) slate::CredentialStore* store;
@property(nonatomic, copy) dispatch_block_t onSaveBlock;
@property(nonatomic, strong) NSSearchField* searchField;
@property(nonatomic, strong) NSTableView* tableView;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, strong) NSTextField* countBadge;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* rows;
@property(nonatomic, copy) NSString* expandedSite;
@property(nonatomic, copy) NSString* revealedId;
@property(nonatomic, copy) NSString* editingId;
@property(nonatomic, strong) NSTimer* concealTimer;
@property(nonatomic, strong) LAContext* authentication;
@property(nonatomic) NSUInteger requestGeneration;
@property(nonatomic, strong) NSScrollView* scroll;
@property(nonatomic, strong) NSView* addForm;
@property(nonatomic, strong) NSButton* addButton;
@property(nonatomic, strong) NSButton* removeShown;
@property(nonatomic, strong) NSTextField* addSite;
@property(nonatomic, strong) NSTextField* addUser;
@property(nonatomic, strong) NSSecureTextField* addSecret;
@property(nonatomic, strong) NSView* strengthTrack;
@property(nonatomic, strong) NSView* strengthFill;
@property(nonatomic, strong) NSTextField* strengthLabel;
@end

@implementation SlatePasswordsPanel
+ (void)openApplePasswords {
 NSURL* app=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Passwords"];
 if(!app) {
  NSAlert* alert=[NSAlert new]; alert.messageText=@"Apple Passwords is unavailable";
  alert.informativeText=@"The Passwords app could not be found on this Mac."; [alert runModal]; return;
 }
 [NSWorkspace.sharedWorkspace openApplicationAtURL:app configuration:[NSWorkspaceOpenConfiguration configuration]
  completionHandler:^(NSRunningApplication* application,NSError* error){
   if(error) dispatch_async(dispatch_get_main_queue(), ^{
    NSAlert* alert=[NSAlert new]; alert.messageText=@"Apple Passwords could not be opened"; [alert runModal];
   });
  }];
}
- (void)openApplePasswords:(id)sender { [SlatePasswordsPanel openApplePasswords]; }

+ (instancetype)sharedPanel {
 static SlatePasswordsPanel* panel;
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  panel=[[self alloc] initWithContentRect:NSMakeRect(0,0,760,540)
   styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
   backing:NSBackingStoreBuffered defer:NO];
  panel.title=@"Passwords";
  panel.titleVisibility=NSWindowTitleHidden;
  panel.titlebarAppearsTransparent=YES;
  panel.releasedWhenClosed=NO;
  [panel setupUI];
 });
 return panel;
}

- (void)setupUI {
 self.minSize=NSMakeSize(660,420);
 self.rows=[NSMutableArray array];
 self.backgroundColor=[SlatePalette ground];
 self.contentView=[[SlatePasswordGroundView alloc] initWithFrame:self.contentView.bounds];
 NSView* content=self.contentView;
 const CGFloat W = content.bounds.size.width;
 const CGFloat H = content.bounds.size.height;

 // Header: Key icon + Title + Count Pill
 NSImageView* emblem = [[NSImageView alloc] initWithFrame:NSMakeRect(22, H - 56, 22, 22)];
 if (@available(macOS 11.0, *)) {
  NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold];
  emblem.image = [[NSImage imageWithSystemSymbolName:@"key.fill" accessibilityDescription:@"Passwords"] imageWithSymbolConfiguration:cfg];
 }
 emblem.contentTintColor = NSColor.controlAccentColor;
 emblem.autoresizingMask = NSViewMinYMargin;
 [content addSubview:emblem];

 NSTextField* heading = [NSTextField labelWithString:@"Passwords"];
 heading.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
 heading.textColor = [SlatePalette ink];
 heading.frame = NSMakeRect(50, H - 57, 120, 24);
 heading.autoresizingMask = NSViewMinYMargin;
 [content addSubview:heading];

 self.countBadge = [NSTextField labelWithString:@""];
 self.countBadge.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
 self.countBadge.textColor = NSColor.secondaryLabelColor;
 self.countBadge.frame = NSMakeRect(160, H - 54, 140, 18);
 self.countBadge.autoresizingMask = NSViewMinYMargin;
 [content addSubview:self.countBadge];

 // Search + Add row
 self.searchField=[[NSSearchField alloc] initWithFrame:NSMakeRect(20, H - 98, W - 134, 30)];
 self.searchField.placeholderString=@"Search websites or usernames";
 self.searchField.target=self; self.searchField.action=@selector(searchChanged:);
 self.searchField.sendsSearchStringImmediately=YES;
 self.searchField.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 [content addSubview:self.searchField];

 NSButton* add=[SlateQuickButton quickWithTitle:@"+ Add" action:nil];
 add.target=self; add.action=@selector(addPassword:);
 self.addButton=add;
 add.frame=NSMakeRect(W - 104, H - 98, 84, 30);
 add.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;
 [content addSubview:add];

 // Vault List Card
 NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 84, W - 40, H - 194)];
 self.scroll=scroll;
 scroll.hasVerticalScroller=YES; scroll.borderType=NSNoBorder;
 scroll.drawsBackground=NO;
 scroll.wantsLayer=YES;
 scroll.layer.cornerRadius=12;
 if (@available(macOS 11.0, *)) scroll.layer.cornerCurve=kCACornerCurveContinuous;
 scroll.layer.borderWidth=1;
 scroll.layer.borderColor=[SlatePalette hairline].CGColor;
 scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;

 self.tableView=[[NSTableView alloc] initWithFrame:scroll.bounds];
 self.tableView.delegate=self; self.tableView.dataSource=self;
 self.tableView.headerView=nil;
 self.tableView.rowHeight=44;
 self.tableView.intercellSpacing=NSMakeSize(0, 2);
 self.tableView.backgroundColor=[SlatePalette ground];
 self.tableView.selectionHighlightStyle=NSTableViewSelectionHighlightStyleNone;
 NSTableColumn* column=[[NSTableColumn alloc] initWithIdentifier:@"account"];
 column.width=W - 44; column.resizingMask=NSTableColumnAutoresizingMask;
 [self.tableView addTableColumn:column];
 self.tableView.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
 scroll.documentView=self.tableView;
 [content addSubview:scroll];

 // Footer Actions
 NSButton* bring=[SlateQuickButton quickWithTitle:@"Import from Browser…" action:nil];
 bring.target=self; bring.action=@selector(bringIn:);
 bring.frame=NSMakeRect(20, 38, 152, 28);
 [content addSubview:bring];

 NSButton* import=[SlateQuickButton quickWithTitle:@"Import CSV…" action:nil];
 import.target=self; import.action=@selector(importCSV:);
 import.frame=NSMakeRect(180, 38, 102, 28);
 [content addSubview:import];

 self.removeShown=[SlateQuickButton quickWithTitle:@"Remove All…" tint:NSColor.systemRedColor action:nil];
 self.removeShown.target=self; self.removeShown.action=@selector(removeShownPasswords:);
 self.removeShown.frame=NSMakeRect(W - 140, 38, 120, 28);
 self.removeShown.autoresizingMask=NSViewMinXMargin;
 [content addSubview:self.removeShown];

 self.statusLabel=[NSTextField labelWithString:@""];
 self.statusLabel.font=[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
 self.statusLabel.frame=NSMakeRect(292, 43, W - 444, 18);
 self.statusLabel.alignment=NSTextAlignmentCenter;
 self.statusLabel.textColor=NSColor.secondaryLabelColor;
 self.statusLabel.autoresizingMask=NSViewWidthSizable;
 [content addSubview:self.statusLabel];

 NSTextField* note=[NSTextField labelWithString:@"Stored locally in your encrypted macOS Keychain. Show, Copy, and Edit require Touch ID or macOS authentication."];
 note.font=[NSFont systemFontOfSize:11]; note.textColor=NSColor.tertiaryLabelColor;
 note.frame=NSMakeRect(20, 12, W - 40, 16); note.autoresizingMask=NSViewWidthSizable;
 [content addSubview:note];

 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conceal:) name:NSWindowDidResignKeyNotification object:self];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conceal:) name:NSApplicationDidResignActiveNotification object:nil];
}

- (void)conceal:(id)sender {
 if(self.authentication) return;
 [self.concealTimer invalidate]; self.concealTimer=nil; self.revealedId=nil;
 [self.tableView reloadData];
}
- (void)cancelAuthentication {
 ++self.requestGeneration; [self.authentication invalidate]; self.authentication=nil;
 [self conceal:nil];
}
- (void)close { if(self.addForm)[self closeAddForm]; [self cancelAuthentication]; [super close]; }
- (void)orderOut:(id)sender { if(self.addForm)[self closeAddForm]; [self cancelAuthentication]; [super orderOut:sender]; }

- (void)showForCredentialStore:(slate::CredentialStore*)store onSave:(dispatch_block_t)onSave {
 [self prepareForCredentialStore:store onSave:onSave];
 [self center]; [self makeKeyAndOrderFront:nil];
 [self makeFirstResponder:self.searchField];
}
- (void)prepareForCredentialStore:(slate::CredentialStore*)store onSave:(dispatch_block_t)onSave {
 [self cancelAuthentication]; self.store=store; self.onSaveBlock=onSave;
 [self.contentView setNeedsDisplay:YES];
 [self reloadItems];
}

- (void)reloadItems {
 [self.rows removeAllObjects];
 if(!self.store) return;
 NSMutableDictionary<NSString*,NSMutableArray*>* sites=[NSMutableDictionary dictionary];
 for(const auto& item:self.store->search(self.searchField.stringValue.UTF8String ?: "")) {
  NSString* origin=[NSString stringWithUTF8String:item.origin.c_str()];
  NSString* host=[NSURLComponents componentsWithString:[origin containsString:@"://"] ? origin : [@"https://" stringByAppendingString:origin]].host.lowercaseString ?: origin;
  if(!sites[host]) sites[host]=[NSMutableArray array];
  [sites[host] addObject:@{@"id":@(item.id.c_str()), @"user":@(item.username.c_str()), @"site":host, @"origin":origin}];
 }
 for(NSString* host in [[sites allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
  NSArray* accounts=[sites[host] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* a,NSDictionary* b){
   return [a[@"user"] localizedCaseInsensitiveCompare:b[@"user"]];
  }];
  [self.rows addObject:@{@"site":host,@"count":@(accounts.count)}];
  if([host isEqualToString:self.expandedSite]) [self.rows addObjectsFromArray:accounts];
 }
 const size_t count=self.store->items().size();
 const auto shown=self.store->search(self.searchField.stringValue.UTF8String ?: "");
 self.removeShown.hidden=shown.empty();
 self.removeShown.title=self.searchField.stringValue.length ? [NSString stringWithFormat:@"Remove %zu…",shown.size()] : @"Remove All…";
 self.countBadge.stringValue=count ? [NSString stringWithFormat:@"%zu saved",count] : @"Empty";
 self.statusLabel.stringValue=count ? [NSString stringWithFormat:@"%zu saved password%@",count,count==1?@"":@"s"] : @"No passwords saved yet. Click + Add or import.";
 if(count && !self.rows.count) self.statusLabel.stringValue=@"No matching websites or usernames.";
 [self.tableView reloadData];
}

- (void)searchChanged:(id)sender { [self cancelAuthentication]; [self reloadItems]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return self.rows.count; }
- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
 if (row < 0 || (NSUInteger)row >= self.rows.count) return 44;
 return self.rows[(NSUInteger)row][@"id"] ? 56 : 44;
}

- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
 NSDictionary* item=self.rows[row];
 NSString* identifier=item[@"id"];
 const CGFloat width = MAX(420, column.width);

 if(!identifier) {
  NSTableCellView* cell=[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,width,44)];
  NSString* host = item[@"site"] ?: @"";
  const BOOL expanded = [host isEqualToString:self.expandedSite];
  const NSInteger acctCount = [item[@"count"] integerValue];

  // Site monogram badge
  NSView* badge = [[NSView alloc] initWithFrame:NSMakeRect(14, 9, 26, 26)];
  badge.wantsLayer = YES;
  badge.layer.cornerRadius = 7;
  if (@available(macOS 11.0, *)) badge.layer.cornerCurve = kCACornerCurveContinuous;
  badge.layer.backgroundColor = [SlateSiteBadgeColor(host) colorWithAlphaComponent:0.18].CGColor;
  NSString* initial = host.length ? [[host substringToIndex:1] uppercaseString] : @"•";
  NSTextField* letter = [NSTextField labelWithString:initial];
  letter.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
  letter.textColor = SlateSiteBadgeColor(host);
  letter.alignment = NSTextAlignmentCenter;
  letter.frame = NSMakeRect(0, 4, 26, 18);
  [badge addSubview:letter];
  [cell addSubview:badge];

  // Clickable transparent button spanning the row
  NSButton* hit = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, width, 44)];
  hit.bordered = NO; hit.title = @""; hit.target = self; hit.action = @selector(toggleSite:);
  hit.identifier = host; hit.autoresizingMask = NSViewWidthSizable;
  [cell addSubview:hit];

  NSTextField* domain = [NSTextField labelWithString:host];
  domain.font = [NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium];
  domain.textColor = [SlatePalette ink];
  domain.lineBreakMode = NSLineBreakByTruncatingTail;
  domain.frame = NSMakeRect(50, 13, MAX(120, width - 170), 18);
  domain.autoresizingMask = NSViewWidthSizable;
  [cell addSubview:domain];

  NSTextField* pill = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld account%@", (long)acctCount, acctCount==1?@"":@"s"]];
  pill.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
  pill.textColor = NSColor.secondaryLabelColor;
  pill.alignment = NSTextAlignmentRight;
  pill.frame = NSMakeRect(width - 122, 14, 86, 16);
  pill.autoresizingMask = NSViewMinXMargin;
  [cell addSubview:pill];

  NSImageView* chev = [[NSImageView alloc] initWithFrame:NSMakeRect(width - 28, 15, 14, 14)];
  if (@available(macOS 11.0, *)) {
   NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightSemibold];
   chev.image = [[NSImage imageWithSystemSymbolName:(expanded ? @"chevron.down" : @"chevron.right") accessibilityDescription:@""] imageWithSymbolConfiguration:cfg];
  }
  chev.contentTintColor = NSColor.tertiaryLabelColor;
  chev.autoresizingMask = NSViewMinXMargin;
  [cell addSubview:chev];

  NSView* sep = [[NSView alloc] initWithFrame:NSMakeRect(50, 0, width - 64, 1)];
  sep.wantsLayer = YES;
  sep.layer.backgroundColor = [[SlatePalette hairline] colorWithAlphaComponent:0.55].CGColor;
  sep.autoresizingMask = NSViewWidthSizable;
  [cell addSubview:sep];
  return cell;
 }

 // Expanded Account Card Row
 NSTableCellView* cell=[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,width,56)];
 NSView* card = [[NSView alloc] initWithFrame:NSMakeRect(22, 4, width - 36, 48)];
 card.wantsLayer = YES;
 card.layer.cornerRadius = 9;
 if (@available(macOS 11.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
 card.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.04].CGColor;
 card.layer.borderWidth = 1;
 card.layer.borderColor = [[SlatePalette hairline] colorWithAlphaComponent:0.6].CGColor;
 card.autoresizingMask = NSViewWidthSizable;
 [cell addSubview:card];

 const CGFloat cardW = NSWidth(card.frame);
 NSTextField* user=[NSTextField labelWithString:[item[@"user"] length]?item[@"user"]:@"No username"];
 user.frame=NSMakeRect(14, 24, MAX(120, cardW - 296), 17);
 user.lineBreakMode=NSLineBreakByTruncatingMiddle;
 user.selectable=YES;
 user.font=[NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
 user.textColor=[SlatePalette ink];
 user.autoresizingMask=NSViewWidthSizable;
 [card addSubview:user];

 NSString* value=@"••••••••••";
 const BOOL isRevealed = [self.revealedId isEqualToString:identifier];
 if(isRevealed && self.store) {
  auto credential=self.store->find_by_id(identifier.UTF8String);
  if(credential) value=@(credential->password.c_str());
 }
 NSTextField* secret=[NSTextField labelWithString:value];
 secret.selectable=YES;
 secret.font=[NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
 secret.textColor=isRevealed ? [SlatePalette ink] : NSColor.secondaryLabelColor;
 secret.frame=NSMakeRect(14, 7, MAX(120, cardW - 296), 16);
 secret.autoresizingMask=NSViewWidthSizable;
 secret.lineBreakMode=NSLineBreakByTruncatingTail;
 [card addSubview:secret];

 NSArray* titles=@[isRevealed ? @"Hide" : @"Show", @"Copy", @"Edit", @"Remove"];
 SEL actions[]={@selector(reveal:), @selector(copyPassword:), @selector(editPassword:), @selector(removePassword:)};
 CGFloat bx = cardW - 266;
 for(NSUInteger i=0; i<4; i++) {
  NSColor* tint = (i == 3) ? NSColor.systemRedColor : [SlatePalette ink];
  SlateQuickButton* button=[SlateQuickButton quickWithTitle:titles[i] tint:tint action:nil];
  button.target=self; button.action=actions[i]; button.identifier=identifier;
  CGFloat bw = (i == 3) ? 66 : 56;
  button.frame=NSMakeRect(bx, 12, bw, 24);
  button.autoresizingMask=NSViewMinXMargin;
  [card addSubview:button];
  bx += bw + 6;
 }
 return cell;
}

- (void)toggleSite:(NSButton*)sender {
 [self cancelAuthentication];
 self.expandedSite=[self.expandedSite isEqualToString:sender.identifier]?nil:sender.identifier;
 [self reloadItems];
}

- (void)authenticate:(NSString*)identifier reason:(NSString*)reason completion:(void (^)(NSString*))completion {
 if(!self.store || self.authentication) return;
 LAContext* context=[LAContext new]; NSError* error=nil;
 if(![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error]) {
  self.statusLabel.stringValue=@"macOS verification is unavailable. The password remains hidden."; return;
 }
 self.authentication=context; const NSUInteger generation=++self.requestGeneration;
 __weak SlatePasswordsPanel* weakSelf=self;
 [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:reason reply:^(BOOL success,NSError* failure){
  dispatch_async(dispatch_get_main_queue(), ^{
   SlatePasswordsPanel* panel=weakSelf;
   if(!panel || generation!=panel.requestGeneration) return;
   panel.authentication=nil;
   if(!success || !panel.visible || !panel.store) return;
   // Touch ID / LocalAuthentication briefly deactivates the app; reactivate before revealing/copying.
   [NSApp activateIgnoringOtherApps:YES];
   [panel makeKeyAndOrderFront:nil];
   auto credential=panel.store->find_by_id(identifier.UTF8String);
   if(credential) completion(@(credential->password.c_str()));
  });
 }];
}

- (void)reveal:(NSButton*)sender {
 NSString* identifier=[sender.identifier copy];
 if([self.revealedId isEqualToString:identifier]) { [self conceal:nil]; return; }
 __weak SlatePasswordsPanel* weakSelf=self;
 [self authenticate:identifier reason:@"Show this saved password in Slate" completion:^(NSString* password){
  SlatePasswordsPanel* panel=weakSelf; if(!panel) return;
  [panel conceal:nil]; panel.revealedId=identifier; [panel.tableView reloadData];
  panel.concealTimer=[NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer* timer){[weakSelf conceal:nil];}];
 }];
}

- (void)copyPassword:(NSButton*)sender {
 __weak SlatePasswordsPanel* weakSelf=self;
 [self authenticate:[sender.identifier copy] reason:@"Copy this saved password from Slate" completion:^(NSString* password){
  NSPasteboard* pasteboard=NSPasteboard.generalPasteboard;
  [pasteboard clearContents];
  [pasteboard setString:password forType:NSPasteboardTypeString];
  const NSInteger change=pasteboard.changeCount;
  weakSelf.statusLabel.stringValue=@"Password copied (auto-clears in 30s).";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
   if(pasteboard.changeCount==change) [pasteboard clearContents];
  });
 }];
}

- (void)editPassword:(NSButton*)sender {
 NSString* identifier=[sender.identifier copy];
 if(!self.store || !identifier.length) return;
 __weak SlatePasswordsPanel* weakSelf=self;
 [self authenticate:identifier reason:@"Edit this saved password in Slate" completion:^(NSString* password){
  SlatePasswordsPanel* panel=weakSelf;
  if(!panel || !panel.store) return;
  auto cred = panel.store->find_by_id(identifier.UTF8String);
  if(!cred) return;
  if(panel.addForm) [panel closeAddForm];
  panel.editingId = identifier;
  [panel openAddFormWithSite:@(cred->origin.c_str()) user:@(cred->username.c_str()) secret:password];
 }];
}

- (void)removePassword:(NSButton*)sender {
 NSString* identifier=[sender.identifier copy];
 NSAlert* alert=[NSAlert new]; alert.messageText=@"Remove this saved password?";
 alert.informativeText=@"This removes it from Slate. The account on the website is not deleted.";
 [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Remove"];
 [alert beginSheetModalForWindow:self completionHandler:^(NSModalResponse response){
  if(response!=NSAlertSecondButtonReturn || !self.store) return;
  [self cancelAuthentication]; self.store->remove(identifier.UTF8String);
  if(self.onSaveBlock) self.onSaveBlock(); [self reloadItems];
 }];
}

- (void)closeAddForm {
 self.addSecret.stringValue=@"";
 [self.addForm removeFromSuperview];
 self.addForm=nil;
 self.addSite=nil; self.addUser=nil; self.addSecret=nil;
 self.strengthTrack=nil; self.strengthFill=nil; self.strengthLabel=nil;
 self.editingId=nil;
 self.addButton.title=@"+ Add";
 const CGFloat W = self.contentView.bounds.size.width;
 const CGFloat H = self.contentView.bounds.size.height;
 self.scroll.frame=NSMakeRect(20, 84, W - 40, H - 194);
}

- (void)openAddFormWithSite:(NSString*)site user:(NSString*)user secret:(NSString*)secret {
 self.addButton.title=@"Cancel";
 const CGFloat W = self.contentView.bounds.size.width;
 const CGFloat H = self.contentView.bounds.size.height;
 const CGFloat formW = W - 40;
 const CGFloat formH = 114;

 NSView* form=[[NSView alloc] initWithFrame:NSMakeRect(20, H - 108 - formH, formW, formH)];
 form.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 form.wantsLayer=YES;
 form.layer.cornerRadius=12;
 if (@available(macOS 11.0, *)) form.layer.cornerCurve=kCACornerCurveContinuous;
 form.layer.backgroundColor=[NSColor.labelColor colorWithAlphaComponent:0.035].CGColor;
 form.layer.borderWidth=1;
 form.layer.borderColor=[SlatePalette hairline].CGColor;
 self.addForm=form;
 [self.contentView addSubview:form];

 const CGFloat half = (formW - 36) / 2.0;
 self.addSite=[[NSTextField alloc] initWithFrame:NSMakeRect(12, 74, half, 26)];
 self.addSite.placeholderString=@"Website (e.g. github.com)";
 self.addSite.stringValue = site ?: @"";

 self.addUser=[[NSTextField alloc] initWithFrame:NSMakeRect(24 + half, 74, half, 26)];
 self.addUser.placeholderString=@"Username or email";
 self.addUser.stringValue = user ?: @"";

 self.addSecret=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(12, 36, formW - 216, 26)];
 self.addSecret.placeholderString=@"Password";
 self.addSecret.stringValue = secret ?: @"";
 self.addSecret.delegate = self;
 self.addSecret.target=self; self.addSecret.action=@selector(saveAddedPassword:);

 NSButton* gen=[SlateQuickButton quickWithTitle:@"Generate" action:nil];
 gen.target=self; gen.action=@selector(generateForAddForm:);
 gen.frame=NSMakeRect(formW - 196, 35, 92, 28);
 gen.autoresizingMask=NSViewMinXMargin;

 NSButton* save=[SlateQuickButton quickWithTitle:self.editingId ? @"Update" : @"Save" tint:NSColor.controlAccentColor action:nil];
 save.target=self; save.action=@selector(saveAddedPassword:);
 save.frame=NSMakeRect(formW - 96, 35, 84, 28);
 save.autoresizingMask=NSViewMinXMargin;

 self.strengthTrack=[[NSView alloc] initWithFrame:NSMakeRect(14, 13, 140, 5)];
 self.strengthTrack.wantsLayer=YES;
 self.strengthTrack.layer.cornerRadius=2.5;
 self.strengthTrack.layer.backgroundColor=[NSColor.labelColor colorWithAlphaComponent:0.08].CGColor;

 self.strengthFill=[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 5)];
 self.strengthFill.wantsLayer=YES;
 self.strengthFill.layer.cornerRadius=2.5;
 [self.strengthTrack addSubview:self.strengthFill];

 self.strengthLabel=[NSTextField labelWithString:@""];
 self.strengthLabel.font=[NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
 self.strengthLabel.frame=NSMakeRect(162, 8, 120, 15);

 for(NSView* field in @[self.addSite, self.addUser, self.addSecret, gen, save, self.strengthTrack, self.strengthLabel]) {
  [form addSubview:field];
 }
 [self updateStrengthUI];
 self.scroll.frame=NSMakeRect(20, 84, formW, H - 194 - formH - 12);
 [self makeFirstResponder:self.editingId ? self.addUser : self.addSite];
}

- (void)updateStrengthUI {
 if(!self.addSecret || !self.strengthFill || !self.strengthLabel) return;
 NSString* label = @"";
 NSColor* color = NSColor.clearColor;
 CGFloat ratio = 0;
 SlateEvaluatePasswordStrength(self.addSecret.stringValue ?: @"", &label, &color, &ratio);
 self.strengthFill.frame = NSMakeRect(0, 0, round(140.0 * ratio), 5);
 self.strengthFill.layer.backgroundColor = color.CGColor;
 self.strengthLabel.stringValue = label;
 self.strengthLabel.textColor = color;
}

- (void)controlTextDidChange:(NSNotification*)obj {
 if(obj.object == self.addSecret) [self updateStrengthUI];
}

- (void)generateForAddForm:(id)sender {
 if(!self.addSecret) return;
 NSString* strong = SlateGenerateStrongPassword();
 self.addSecret.stringValue = strong;
 [self updateStrengthUI];
 NSPasteboard* pb = NSPasteboard.generalPasteboard;
 [pb clearContents];
 [pb setString:strong forType:NSPasteboardTypeString];
 self.statusLabel.stringValue = @"Generated strong password & copied to clipboard.";
}

- (void)addPassword:(id)sender {
 [self cancelAuthentication];
 if(self.addForm) {
  [self closeAddForm];
  return;
 }
 self.editingId = nil;
 [self openAddFormWithSite:@"" user:@"" secret:@""];
}

- (void)saveAddedPassword:(id)sender {
 if(!self.store || !self.addForm) return;
 NSString* input=[self.addSite.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 NSURLComponents* url=[NSURLComponents componentsWithString:[input containsString:@"://"]?input:[@"https://" stringByAppendingString:input]];
 if(!url.host.length || ![@[@"https",@"http"] containsObject:url.scheme.lowercaseString] || url.user || url.password || !self.addSecret.stringValue.length) {
  self.statusLabel.stringValue=@"Enter a valid website and a password."; return;
 }
 url.path=@""; url.query=nil; url.fragment=nil;
 if(self.editingId.length) {
  self.store->remove(self.editingId.UTF8String);
 }
 slate::Credential credential;
 credential.origin=url.string.UTF8String;
 credential.username=[self.addUser.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].UTF8String;
 credential.password=self.addSecret.stringValue.UTF8String;
 self.store->save(std::move(credential));
 self.addSecret.stringValue=@"";
 if(self.onSaveBlock) self.onSaveBlock();
 [self closeAddForm];
 [self reloadItems];
}

- (void)removeShownPasswords:(id)sender {
 if(!self.store) return;
 NSMutableArray<NSString*>* identifiers=[NSMutableArray array];
 for(const auto& item:self.store->search(self.searchField.stringValue.UTF8String ?: "")) [identifiers addObject:@(item.id.c_str())];
 if(!identifiers.count)return;
 NSAlert* alert=[NSAlert new];alert.messageText=[NSString stringWithFormat:@"Remove %lu saved password%@?",(unsigned long)identifiers.count,identifiers.count==1?@"":@"s"];
 alert.informativeText=@"Only the accounts in the current search will be removed from Slate.";
 [alert addButtonWithTitle:@"Cancel"];[alert addButtonWithTitle:@"Remove"];
 [alert beginSheetModalForWindow:self completionHandler:^(NSModalResponse response){
  if(response!=NSAlertSecondButtonReturn || !self.store)return;
  [self cancelAuthentication];
  for(NSString* identifier in identifiers) self.store->remove(identifier.UTF8String);
  if(self.onSaveBlock)self.onSaveBlock();[self reloadItems];
 }];
}

- (void)importCSV:(id)sender {
 NSOpenPanel* chooser=[NSOpenPanel openPanel]; chooser.canChooseDirectories=NO; chooser.allowsMultipleSelection=NO;
 chooser.title=@"Import passwords from a browser CSV export";
 [chooser beginSheetModalForWindow:self completionHandler:^(NSModalResponse response){
  if(response!=NSModalResponseOK || !self.store) return;
  NSString* path=chooser.URL.path;
  self.statusLabel.stringValue=@"Reading password file…";
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
   auto imported=std::make_shared<slate::CredentialStore>();
   const size_t count=slate::BrowserImporter::ImportPasswordsCsv(path.UTF8String,*imported);
   dispatch_async(dispatch_get_main_queue(), ^{
    if(!self.store) return;
    for(const auto& item:imported->items()) { auto value=item; value.id.clear(); self.store->save(std::move(value)); }
    if(count && self.onSaveBlock) self.onSaveBlock(); [self reloadItems];
    self.statusLabel.stringValue=[NSString stringWithFormat:@"Imported %zu passwords",count];
   });
  });
 }];
}

- (void)bringIn:(id)sender { if(self.onImportBlock) self.onImportBlock(); }
@end
