// File purpose: Implements the native dialog for selecting a source browser or export file and
// importing bookmarks, history, and passwords safely inside App Sandbox.

#import "platform/macos/import_dialog.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSMutableSet<SlateImportDialog*>* ActiveImportDialogs(void) {
  static NSMutableSet<SlateImportDialog*>* active = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    active = [NSMutableSet set];
  });
  return active;
}

@interface SlateImportDialog () <NSWindowDelegate>
@property (nonatomic, weak) NSWindow* parentWindow;
@property (nonatomic, assign) slate::BookmarkList* bookmarks;
@property (nonatomic, assign) slate::CredentialStore* credentials;
@property (nonatomic, copy) void (^completionBlock)(slate::ImportSummary, const std::vector<slate::HistoryItem>&);

@property (nonatomic, strong) NSPopUpButton* sourcePopup;
@property (nonatomic, strong) NSButton* bookmarksCheck;
@property (nonatomic, strong) NSButton* historyCheck;
@property (nonatomic, strong) NSButton* passwordsCheck;
@property (nonatomic, strong) NSProgressIndicator* spinner;
@property (nonatomic, strong) NSButton* importButton;
@property (nonatomic, strong) NSButton* cancelButton;
@property (nonatomic, strong) NSTextField* statusText;
@property (nonatomic, strong) NSTextField* hintText;
@property (nonatomic, assign) BOOL dismissed;
@end

@implementation SlateImportDialog

+ (void)showModalForWindow:(NSWindow*)parentWindow
                 bookmarks:(slate::BookmarkList*)bookmarks
           credentialStore:(slate::CredentialStore*)credentials
                onComplete:(void (^)(slate::ImportSummary, const std::vector<slate::HistoryItem>&))completion {
  SlateImportDialog* controller = [[SlateImportDialog alloc] init];
  controller.parentWindow = parentWindow;
  controller.bookmarks = bookmarks;
  controller.credentials = credentials;
  controller.completionBlock = completion;
  [ActiveImportDialogs() addObject:controller];
  [controller buildAndShow];
}

- (NSArray<NSDictionary*>*)sourceEntries {
  NSString* home = [NSString stringWithUTF8String:slate::BrowserImporter::GetRealHomeDirectory().c_str()];
  return @[
    @{@"id":@"chrome", @"title":@"Google Chrome", @"kind":@"profile",
      @"service":@"Chrome Safe Storage", @"account":@"Chrome",
      @"path":[home stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/Default"]},
    @{@"id":@"dia", @"title":@"Dia", @"kind":@"profile",
      @"service":@"Dia Safe Storage", @"account":@"Dia",
      @"path":[home stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data/Default"]},
    @{@"id":@"arc", @"title":@"Arc", @"kind":@"profile",
      @"service":@"Arc Safe Storage", @"account":@"Arc",
      @"path":[home stringByAppendingPathComponent:@"Library/Application Support/Arc/User Data/Default"]},
    @{@"id":@"brave", @"title":@"Brave", @"kind":@"profile",
      @"service":@"Brave Safe Storage", @"account":@"Brave",
      @"path":[home stringByAppendingPathComponent:@"Library/Application Support/BraveSoftware/Brave-Browser/Default"]},
    @{@"id":@"edge", @"title":@"Microsoft Edge", @"kind":@"profile",
      @"service":@"Microsoft Edge Safe Storage", @"account":@"Microsoft Edge",
      @"path":[home stringByAppendingPathComponent:@"Library/Application Support/Microsoft Edge/Default"]},
    @{@"id":@"html", @"title":@"Bookmarks HTML File (Safari / Firefox / Any)…", @"kind":@"html",
      @"path":[home stringByAppendingPathComponent:@"Downloads"]},
    @{@"id":@"csv", @"title":@"Passwords CSV File (Chrome / Safari / 1Password)…", @"kind":@"csv",
      @"path":[home stringByAppendingPathComponent:@"Downloads"]}
  ];
}

- (void)buildAndShow {
  NSRect frame = NSMakeRect(0, 0, 480, 324);
  NSWindow* sheet = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  sheet.title = @"Import Browser Data";
  sheet.delegate = self;
  sheet.releasedWhenClosed = NO;
  self.window = sheet;

  NSView* content = sheet.contentView;

  NSTextField* titleLabel = [NSTextField labelWithString:@"Import into Slate"];
  titleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  titleLabel.frame = NSMakeRect(24, 278, 432, 22);
  [content addSubview:titleLabel];

  NSTextField* descLabel = [NSTextField wrappingLabelWithString:@"Bring your bookmarks, browsing history, and saved passwords from another browser."];
  descLabel.font = [NSFont systemFontOfSize:12];
  descLabel.textColor = NSColor.secondaryLabelColor;
  descLabel.frame = NSMakeRect(24, 242, 432, 30);
  [content addSubview:descLabel];

  NSTextField* fromLabel = [NSTextField labelWithString:@"Source:"];
  fromLabel.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
  fromLabel.frame = NSMakeRect(24, 204, 56, 20);
  [content addSubview:fromLabel];

  self.sourcePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(84, 200, 372, 26) pullsDown:NO];
  [self.sourcePopup removeAllItems];
  for (NSDictionary* entry in [self sourceEntries]) {
    [self.sourcePopup addItemWithTitle:entry[@"title"]];
  }
  self.sourcePopup.target = self;
  self.sourcePopup.action = @selector(sourceChanged:);
  [self.sourcePopup selectItemAtIndex:0];
  [content addSubview:self.sourcePopup];

  self.bookmarksCheck = [NSButton checkboxWithTitle:@"Bookmarks / Favorites" target:nil action:nil];
  self.bookmarksCheck.state = NSControlStateValueOn;
  self.bookmarksCheck.frame = NSMakeRect(86, 164, 220, 20);
  [content addSubview:self.bookmarksCheck];

  self.historyCheck = [NSButton checkboxWithTitle:@"Browsing History" target:nil action:nil];
  self.historyCheck.state = NSControlStateValueOn;
  self.historyCheck.frame = NSMakeRect(86, 138, 220, 20);
  [content addSubview:self.historyCheck];

  self.passwordsCheck = [NSButton checkboxWithTitle:@"Saved Passwords" target:nil action:nil];
  self.passwordsCheck.state = NSControlStateValueOn;
  self.passwordsCheck.frame = NSMakeRect(86, 112, 220, 20);
  [content addSubview:self.passwordsCheck];

  self.hintText = [NSTextField wrappingLabelWithString:@""];
  self.hintText.font = [NSFont systemFontOfSize:11];
  self.hintText.textColor = NSColor.secondaryLabelColor;
  self.hintText.frame = NSMakeRect(24, 58, 432, 44);
  [content addSubview:self.hintText];

  self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 22, 16, 16)];
  self.spinner.style = NSProgressIndicatorStyleSpinning;
  self.spinner.controlSize = NSControlSizeSmall;
  self.spinner.displayedWhenStopped = NO;
  [content addSubview:self.spinner];

  self.statusText = [NSTextField labelWithString:@""];
  self.statusText.font = [NSFont systemFontOfSize:11.5];
  self.statusText.frame = NSMakeRect(46, 21, 220, 18);
  self.statusText.textColor = NSColor.secondaryLabelColor;
  [content addSubview:self.statusText];

  self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(onCancel:)];
  self.cancelButton.frame = NSMakeRect(274, 16, 86, 30);
  self.cancelButton.keyEquivalent = @"\e";
  [content addSubview:self.cancelButton];

  self.importButton = [NSButton buttonWithTitle:@"Choose Folder…" target:self action:@selector(onImport:)];
  self.importButton.frame = NSMakeRect(366, 16, 94, 30);
  self.importButton.keyEquivalent = @"\r";
  self.importButton.bezelStyle = NSBezelStyleRounded;
  [content addSubview:self.importButton];

  [self sourceChanged:nil];

  if (self.parentWindow) {
    [self.parentWindow beginSheet:sheet completionHandler:^(NSModalResponse returnCode) {
      (void)returnCode;
      [ActiveImportDialogs() removeObject:self];
    }];
  } else {
    [sheet center];
    [sheet makeKeyAndOrderFront:nil];
  }
}

- (NSDictionary*)selectedEntry {
  NSArray<NSDictionary*>* entries = [self sourceEntries];
  NSInteger idx = self.sourcePopup.indexOfSelectedItem;
  if (idx < 0 || (NSUInteger)idx >= entries.count) return entries.firstObject;
  return entries[(NSUInteger)idx];
}

- (void)sourceChanged:(id)sender {
  NSDictionary* entry = [self selectedEntry];
  NSString* kind = entry[@"kind"];
  BOOL isProfile = [kind isEqualToString:@"profile"];
  self.bookmarksCheck.enabled = isProfile;
  self.historyCheck.enabled = isProfile;
  self.passwordsCheck.enabled = isProfile;
  self.bookmarksCheck.hidden = !isProfile;
  self.historyCheck.hidden = !isProfile;
  self.passwordsCheck.hidden = !isProfile;
  if (isProfile) {
    self.importButton.title = @"Import…";
    self.hintText.stringValue = [NSString stringWithFormat:@"Confirm your %@ profile folder when prompted. For Saved Passwords, click Allow on macOS’s Keychain prompt for “%@”.", entry[@"title"], entry[@"service"]];
  } else if ([kind isEqualToString:@"html"]) {
    self.importButton.title = @"Choose HTML…";
    self.hintText.stringValue = @"Select an exported bookmarks.html file from Safari, Chrome, Firefox, Arc, or Brave.";
  } else {
    self.importButton.title = @"Choose CSV…";
    self.hintText.stringValue = @"Select a passwords .csv export from Chrome, Safari, 1Password, Bitwarden, Brave, or Edge.";
  }
}

- (void)dismissAndFinishWithSummary:(slate::ImportSummary)summary history:(std::vector<slate::HistoryItem>)history notify:(BOOL)notify {
  if (self.dismissed) return;
  self.dismissed = YES;
  void (^cb)(slate::ImportSummary, const std::vector<slate::HistoryItem>&) = self.completionBlock;
  self.completionBlock = nil;
  NSWindow* parent = self.parentWindow;
  NSWindow* sheet = self.window;
  if (parent && sheet && sheet.isSheet) {
    [parent endSheet:sheet returnCode:notify ? NSModalResponseOK : NSModalResponseCancel];
    if (notify && cb) {
      dispatch_async(dispatch_get_main_queue(), ^{
        cb(summary, history);
      });
    }
  } else {
    [sheet close];
    [ActiveImportDialogs() removeObject:self];
    if (notify && cb) cb(summary, history);
  }
}

- (BOOL)windowShouldClose:(NSWindow*)sender {
  (void)sender;
  [self dismissAndFinishWithSummary:slate::ImportSummary{} history:{} notify:NO];
  return NO;
}

- (void)onCancel:(id)sender {
  (void)sender;
  [self dismissAndFinishWithSummary:slate::ImportSummary{} history:{} notify:NO];
}

- (void)onImport:(id)sender {
  (void)sender;
  NSDictionary* entry = [self selectedEntry];
  NSString* kind = entry[@"kind"];
  NSString* defaultPath = entry[@"path"];

  if ([kind isEqualToString:@"csv"]) {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeCommaSeparatedText];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.message = @"Choose your exported passwords CSV file";
    if (defaultPath.length) panel.directoryURL = [NSURL fileURLWithPath:defaultPath];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
      if (result != NSModalResponseOK || !panel.URL || !self.credentials) return;
      NSURL* url = panel.URL;
      BOOL accessed = [url startAccessingSecurityScopedResource];
      size_t count = slate::BrowserImporter::ImportPasswordsCsv(url.path.UTF8String, *self.credentials);
      if (accessed) [url stopAccessingSecurityScopedResource];
      slate::ImportSummary summary;
      summary.passwords_imported = count;
      [self dismissAndFinishWithSummary:summary history:{} notify:YES];
    }];
    return;
  }

  if ([kind isEqualToString:@"html"]) {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeHTML];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.message = @"Choose your exported bookmarks HTML file";
    if (defaultPath.length) panel.directoryURL = [NSURL fileURLWithPath:defaultPath];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
      if (result != NSModalResponseOK || !panel.URL || !self.bookmarks) return;
      NSURL* url = panel.URL;
      BOOL accessed = [url startAccessingSecurityScopedResource];
      size_t count = slate::BrowserImporter::ImportHtmlBookmarks(url.path.UTF8String, *self.bookmarks);
      if (accessed) [url stopAccessingSecurityScopedResource];
      slate::ImportSummary summary;
      summary.bookmarks_imported = count;
      [self dismissAndFinishWithSummary:summary history:{} notify:YES];
    }];
    return;
  }

  BOOL importBookmarks = (self.bookmarksCheck.state == NSControlStateValueOn);
  BOOL importHistory = (self.historyCheck.state == NSControlStateValueOn);
  BOOL importPasswords = (self.passwordsCheck.state == NSControlStateValueOn);
  if (!importBookmarks && !importHistory && !importPasswords) {
    self.statusText.stringValue = @"Select at least one category to import.";
    return;
  }

  NSString* service = entry[@"service"] ?: @"";
  NSString* account = entry[@"account"] ?: @"";

  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"Import";
  panel.message = [NSString stringWithFormat:@"Confirm your %@ profile folder (Default) to grant read access", entry[@"title"]];
  if (defaultPath.length) panel.directoryURL = [NSURL fileURLWithPath:defaultPath];

  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result != NSModalResponseOK || !panel.URL || !self.bookmarks) return;
    NSURL* folderURL = panel.URL;
    [self.spinner startAnimation:nil];
    self.statusText.stringValue = @"Importing…";
    self.importButton.enabled = NO;
    self.cancelButton.enabled = NO;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      BOOL accessed = [folderURL startAccessingSecurityScopedResource];
      std::vector<slate::HistoryItem> history;
      slate::ImportSummary summary = slate::BrowserImporter::ImportChromiumProfile(
          folderURL.path.UTF8String, importBookmarks, importHistory, *self.bookmarks, history);
      if (importPasswords && self.credentials && service.length && account.length) {
        std::string passErr;
        summary.passwords_imported = slate::BrowserImporter::ImportChromiumPasswords(
            folderURL.path.UTF8String, service.UTF8String, account.UTF8String, *self.credentials, &passErr);
        if (!passErr.empty() && summary.passwords_imported == 0) {
          summary.error_message = passErr;
        }
      }
      if (accessed) [folderURL stopAccessingSecurityScopedResource];

      dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimation:nil];
        [self dismissAndFinishWithSummary:summary history:std::move(history) notify:YES];
      });
    });
  }];
}

@end
