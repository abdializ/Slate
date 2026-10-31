// File purpose: Implements the native searchable password manager and authentication-gated
// password actions.

#import "platform/macos/passwords_panel.h"
#import "platform/macos/browser_importer.h"
#import "platform/macos/plate_components.h"
#import <LocalAuthentication/LocalAuthentication.h>
#include <memory>


@interface SlatePasswordGroundView : NSView
@end
@implementation SlatePasswordGroundView
- (void)drawRect:(NSRect)rect { [[SlatePalette ground] setFill]; NSRectFill(rect); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end

@interface SlatePasswordsPanel ()
@property(nonatomic, assign) slate::CredentialStore* store;
@property(nonatomic, copy) dispatch_block_t onSaveBlock;
@property(nonatomic, strong) NSSearchField* searchField;
@property(nonatomic, strong) NSTableView* tableView;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* rows;
@property(nonatomic, copy) NSString* expandedSite;
@property(nonatomic, copy) NSString* revealedId;
@property(nonatomic, strong) NSTimer* concealTimer;
@property(nonatomic, strong) LAContext* authentication;
@property(nonatomic) NSUInteger requestGeneration;
@property(nonatomic,strong) NSScrollView* scroll;
@property(nonatomic,strong) NSView* addForm;
@property(nonatomic,strong) NSButton* addButton;
@property(nonatomic,strong) NSButton* removeShown;
@property(nonatomic,strong) NSTextField* addSite;
@property(nonatomic,strong) NSTextField* addUser;
@property(nonatomic,strong) NSSecureTextField* addSecret;
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
  panel=[[self alloc] initWithContentRect:NSMakeRect(0,0,680,470)
   styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
   backing:NSBackingStoreBuffered defer:NO];
  panel.title=@"Passwords";
  panel.releasedWhenClosed=NO;
  [panel setupUI];
 });
 return panel;
}
- (void)setupUI {
 self.minSize=NSMakeSize(640,350);
 self.rows=[NSMutableArray array];
 self.backgroundColor=[SlatePalette ground];
 self.contentView=[[SlatePasswordGroundView alloc] initWithFrame:self.contentView.bounds];
 NSView* content=self.contentView;
 self.searchField=[[NSSearchField alloc] initWithFrame:NSMakeRect(20,420,540,30)];
 self.searchField.placeholderString=@"Search sites and accounts";
 self.searchField.target=self; self.searchField.action=@selector(searchChanged:);
 self.searchField.sendsSearchStringImmediately=YES;
 self.searchField.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 [content addSubview:self.searchField];
 NSButton* add=[SlateQuickButton quickWithTitle:@"Add" action:nil];add.target=self;add.action=@selector(addPassword:);
 self.addButton=add;
 add.frame=NSMakeRect(580,420,80,30); add.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;
 [content addSubview:add];
 NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(20,90,640,315)];
 self.scroll=scroll;
 scroll.hasVerticalScroller=YES; scroll.borderType=NSNoBorder;
 scroll.wantsLayer=YES;scroll.layer.cornerRadius=12;scroll.layer.borderWidth=1;
 scroll.layer.borderColor=[SlatePalette hairline].CGColor;
 scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
 self.tableView=[[NSTableView alloc] initWithFrame:scroll.bounds];
 self.tableView.delegate=self; self.tableView.dataSource=self;
 self.tableView.headerView=nil; self.tableView.rowHeight=40;
 self.tableView.backgroundColor=[SlatePalette ground];
 self.tableView.selectionHighlightStyle=NSTableViewSelectionHighlightStyleNone;
 NSTableColumn* column=[[NSTableColumn alloc] initWithIdentifier:@"account"];
 column.width=620; column.resizingMask=NSTableColumnAutoresizingMask;
 [self.tableView addTableColumn:column];
 self.tableView.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
 scroll.documentView=self.tableView; [content addSubview:scroll];
 NSButton* bring=[SlateQuickButton quickWithTitle:@"Bring in…" action:nil];bring.target=self;bring.action=@selector(bringIn:);
 bring.frame=NSMakeRect(20,40,85,28); [content addSubview:bring];
 NSButton* import=[SlateQuickButton quickWithTitle:@"File…" action:nil];import.target=self;import.action=@selector(importCSV:);
 import.frame=NSMakeRect(110,40,70,28); [content addSubview:import];
 NSButton* apple=[SlateQuickButton quickWithTitle:@"Open Apple Passwords" action:nil];apple.target=self;apple.action=@selector(openApplePasswords:);
 apple.frame=NSMakeRect(185,40,170,28); [content addSubview:apple];
 self.statusLabel=[NSTextField labelWithString:@""];
 self.removeShown=[SlateQuickButton quickWithTitle:@"Remove All…" action:nil];self.removeShown.target=self;self.removeShown.action=@selector(removeShownPasswords:);
 self.removeShown.frame=NSMakeRect(535,40,125,28);self.removeShown.autoresizingMask=NSViewMinXMargin;[content addSubview:self.removeShown];
 self.statusLabel.frame=NSMakeRect(325,66,335,20);
 self.statusLabel.alignment=NSTextAlignmentRight;
 self.statusLabel.textColor=NSColor.secondaryLabelColor;
 self.statusLabel.autoresizingMask=NSViewWidthSizable;
 [content addSubview:self.statusLabel];
 NSTextField* note=[NSTextField labelWithString:@"Show and Copy require macOS verification. Shown passwords hide after 15 seconds."];
 note.font=[NSFont systemFontOfSize:11]; note.textColor=NSColor.secondaryLabelColor;
 note.frame=NSMakeRect(20,14,640,18); note.autoresizingMask=NSViewWidthSizable;
 [content addSubview:note];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conceal:) name:NSWindowDidResignKeyNotification object:self];
 [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conceal:) name:NSApplicationDidResignActiveNotification object:nil];
}
- (void)conceal:(id)sender {
 [self.concealTimer invalidate]; self.concealTimer=nil; self.revealedId=nil;
 [self.tableView reloadData];
}
- (void)cancelAuthentication {
 ++self.requestGeneration; [self.authentication invalidate]; self.authentication=nil;
 [self conceal:nil];
}
- (void)close { if(self.addForm)[self addPassword:nil]; [self cancelAuthentication]; [super close]; }
- (void)orderOut:(id)sender { if(self.addForm)[self addPassword:nil]; [self cancelAuthentication]; [super orderOut:sender]; }
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
  // Rows retain identifiers and display metadata, never copies of secrets.
  [sites[host] addObject:@{@"id":@(item.id.c_str()), @"user":@(item.username.c_str()), @"site":host}];
 }
 for(NSString* host in [[sites allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
  NSArray* accounts=[sites[host] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* a,NSDictionary* b){return [a[@"user"] localizedCaseInsensitiveCompare:b[@"user"]];}];
  [self.rows addObject:@{@"site":host,@"count":@(accounts.count)}];
  if([host isEqualToString:self.expandedSite]) [self.rows addObjectsFromArray:accounts];
 }
 const size_t count=self.store->items().size();
 const auto shown=self.store->search(self.searchField.stringValue.UTF8String ?: "");
 self.removeShown.hidden=shown.empty();
 self.removeShown.title=self.searchField.stringValue.length ? [NSString stringWithFormat:@"Remove %zu…",shown.size()] : @"Remove All…";
 self.statusLabel.stringValue=count ? [NSString stringWithFormat:@"%zu saved password%@",count,count==1?@"":@"s"] : @"Nothing saved yet. Add a password or import a CSV file.";
 if(count && !self.rows.count) self.statusLabel.stringValue=@"No matching sites or accounts.";
 [self.tableView reloadData];
}
- (void)searchChanged:(id)sender { [self cancelAuthentication]; [self reloadItems]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return self.rows.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
 NSDictionary* item=self.rows[row];
 NSTableCellView* cell=[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,column.width,40)];
 NSString* identifier=item[@"id"];
 if(!identifier) {
  NSString* title=[NSString stringWithFormat:@"%@  %@   ·   %@ account%@",[item[@"site"] isEqualToString:self.expandedSite]?@"▾":@"▸",item[@"site"],item[@"count"],[item[@"count"] integerValue]==1?@"":@"s"];
  NSButton* site=[NSButton buttonWithTitle:title target:self action:@selector(toggleSite:)];
  site.bordered=NO; site.alignment=NSTextAlignmentLeft;
  site.frame=NSMakeRect(8,4,column.width-16,32); site.autoresizingMask=NSViewWidthSizable;
  site.identifier=item[@"site"]; [cell addSubview:site]; return cell;
 }
 NSTextField* user=[NSTextField labelWithString:[item[@"user"] length]?item[@"user"]:@"No username"];
 user.frame=NSMakeRect(30,12,180,18); user.lineBreakMode=NSLineBreakByTruncatingMiddle;
 user.selectable=YES;user.font=[NSFont systemFontOfSize:12]; [cell addSubview:user];
 NSString* value=@"••••••••••";
 if([self.revealedId isEqualToString:identifier] && self.store) {
  auto credential=self.store->find_by_id(identifier.UTF8String);
  if(credential) value=@(credential->password.c_str());
 }
 NSTextField* secret=[NSTextField labelWithString:value];
 secret.selectable=YES;secret.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
 secret.frame=NSMakeRect(218,12,MAX(60,column.width-418),18);
 secret.autoresizingMask=NSViewWidthSizable; secret.lineBreakMode=NSLineBreakByTruncatingTail;
 [cell addSubview:secret];
  NSArray* titles=@[[self.revealedId isEqualToString:identifier]?@"Hide":@"Show",@"Copy",@"Remove"];
  SEL actions[]={@selector(reveal:),@selector(copyPassword:),@selector(removePassword:)};
  for(NSUInteger i=0;i<3;i++) {
   NSColor* tint = (i == 2) ? [NSColor systemRedColor] : [SlatePalette ink];
   SlateQuickButton* button=[SlateQuickButton quickWithTitle:titles[i] tint:tint action:nil];
   button.target=self; button.action=actions[i]; button.identifier=identifier;
   button.frame=NSMakeRect(column.width-196+i*64,9,60,22);
   button.autoresizingMask=NSViewMinXMargin; [cell addSubview:button];
  }
  return cell;
}
- (void)toggleSite:(NSButton*)sender {
 [self cancelAuthentication];
 self.expandedSite=[self.expandedSite isEqualToString:sender.identifier]?nil:sender.identifier;
 [self reloadItems];
}
// Slate note: Authenticate with macOS and reject late results when the panel/request state changed before
// completion.
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
   if(!success || !panel.visible || !NSApp.isActive || !panel.store) return;
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
  weakSelf.statusLabel.stringValue=@"Copied. Clipboard clears after 30 seconds if unchanged.";
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
   if(pasteboard.changeCount==change) [pasteboard clearContents];
  });
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
- (void)addPassword:(id)sender {
 [self cancelAuthentication];
 if(self.addForm) {
  self.addSecret.stringValue=@"";[self.addForm removeFromSuperview];self.addForm=nil;
  self.addSite=nil;self.addUser=nil;self.addSecret=nil;
  self.addButton.title=@"Add";self.scroll.frame=NSMakeRect(20,90,self.contentView.bounds.size.width-40,self.contentView.bounds.size.height-155);return;
 }
 self.addButton.title=@"Cancel";
 CGFloat width=self.contentView.bounds.size.width-40;
 NSView* form=[[NSView alloc] initWithFrame:NSMakeRect(20,self.contentView.bounds.size.height-154,width,94)];
 form.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
 form.wantsLayer=YES;form.layer.cornerRadius=12;form.layer.borderWidth=1;form.layer.borderColor=[SlatePalette hairline].CGColor;
 self.addForm=form;[self.contentView addSubview:form];
 self.addSite=[[NSTextField alloc] initWithFrame:NSMakeRect(12,55,(width-36)/2,26)];self.addSite.placeholderString=@"Site";
 self.addUser=[[NSTextField alloc] initWithFrame:NSMakeRect((width+12)/2,55,(width-36)/2,26)];self.addUser.placeholderString=@"Username";
 self.addSecret=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(12,14,width-106,26)];self.addSecret.placeholderString=@"Password";
 self.addSecret.target=self;self.addSecret.action=@selector(saveAddedPassword:);
 NSButton* save=[SlateQuickButton quickWithTitle:@"Save" action:nil];save.target=self;save.action=@selector(saveAddedPassword:);save.frame=NSMakeRect(width-82,12,70,30);
 for(NSView* field in @[self.addSite,self.addUser,self.addSecret,save]) [form addSubview:field];
 self.scroll.frame=NSMakeRect(20,90,width,self.contentView.bounds.size.height-255);
 [self makeFirstResponder:self.addSite];
}
- (void)saveAddedPassword:(id)sender {
 if(!self.store || !self.addForm) return;
 NSString* input=[self.addSite.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 NSURLComponents* url=[NSURLComponents componentsWithString:[input containsString:@"://"]?input:[@"https://" stringByAppendingString:input]];
 if(!url.host.length || ![@[@"https",@"http"] containsObject:url.scheme.lowercaseString] || url.user || url.password || !self.addSecret.stringValue.length) {
  self.statusLabel.stringValue=@"Enter a valid website and a password.";return;
 }
 url.path=@"";url.query=nil;url.fragment=nil;
 slate::Credential credential;credential.origin=url.string.UTF8String;
 credential.username=[self.addUser.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].UTF8String;
 credential.password=self.addSecret.stringValue.UTF8String;
 self.store->save(std::move(credential));self.addSecret.stringValue=@"";
 if(self.onSaveBlock)self.onSaveBlock();[self addPassword:nil];[self reloadItems];
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
