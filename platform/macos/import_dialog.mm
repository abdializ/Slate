#import "platform/macos/import_dialog.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SlateImportDialog ()
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
  [controller buildAndShow];
}

- (void)buildAndShow {
  NSRect frame = NSMakeRect(0, 0, 440, 280);
  NSWindow* sheet = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
  sheet.title = @"Import Browser Data";
  self.window = sheet;

  NSView* content = sheet.contentView;

  // Header Icon & Title
  NSTextField* titleLabel = [NSTextField labelWithString:@"Import Bookmarks and History"];
  titleLabel.font = [NSFont boldSystemFontOfSize:14];
  titleLabel.frame = NSMakeRect(24, 235, 390, 22);
  [content addSubview:titleLabel];

  NSTextField* descLabel = [NSTextField labelWithString:@"Select a browser to transfer your favorites, browsing history, and data into Slate:"];
  descLabel.font = [NSFont systemFontOfSize:12];
  descLabel.textColor = NSColor.secondaryLabelColor;
  descLabel.frame = NSMakeRect(24, 195, 390, 32);
  [content addSubview:descLabel];

  // Browser Selection
  NSTextField* fromLabel = [NSTextField labelWithString:@"From:"];
  fromLabel.frame = NSMakeRect(24, 160, 50, 20);
  [content addSubview:fromLabel];

  self.sourcePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(75, 158, 340, 26) pullsDown:NO];
  [self.sourcePopup removeAllItems];

  BOOL hasDia = slate::BrowserImporter::HasDiaInstalled();
  BOOL hasChrome = slate::BrowserImporter::HasChromeInstalled();

  if (hasDia) [self.sourcePopup addItemWithTitle:@"Dia (Detected)"];
  if (hasChrome) [self.sourcePopup addItemWithTitle:@"Google Chrome"];
  [self.sourcePopup addItemWithTitle:@"Passwords CSV File…"];

  [self.sourcePopup selectItemAtIndex:0];
  [content addSubview:self.sourcePopup];

  // Checkboxes
  self.bookmarksCheck = [NSButton checkboxWithTitle:@"Favorites / Bookmarks" target:nil action:nil];
  self.bookmarksCheck.state = NSControlStateValueOn;
  self.bookmarksCheck.frame = NSMakeRect(40, 120, 200, 20);
  [content addSubview:self.bookmarksCheck];

  self.historyCheck = [NSButton checkboxWithTitle:@"Browsing History" target:nil action:nil];
  self.historyCheck.state = NSControlStateValueOn;
  self.historyCheck.frame = NSMakeRect(40, 95, 200, 20);
  [content addSubview:self.historyCheck];

  self.passwordsCheck = [NSButton checkboxWithTitle:@"Saved Passwords" target:nil action:nil];
  self.passwordsCheck.state = NSControlStateValueOff;
  self.passwordsCheck.frame = NSMakeRect(40, 70, 200, 20);
  [content addSubview:self.passwordsCheck];

  // Status & Spinner
  self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 24, 18, 18)];
  self.spinner.style = NSProgressIndicatorStyleSpinning;
  self.spinner.displayedWhenStopped = NO;
  [content addSubview:self.spinner];

  self.statusText = [NSTextField labelWithString:@""];
  self.statusText.frame = NSMakeRect(48, 24, 200, 18);
  self.statusText.textColor = NSColor.secondaryLabelColor;
  [content addSubview:self.statusText];

  // Buttons
  self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(onCancel:)];
  self.cancelButton.frame = NSMakeRect(255, 18, 80, 28);
  self.cancelButton.keyEquivalent = @"\e";
  [content addSubview:self.cancelButton];

  self.importButton = [NSButton buttonWithTitle:@"Import" target:self action:@selector(onImport:)];
  self.importButton.frame = NSMakeRect(340, 18, 80, 28);
  self.importButton.keyEquivalent = @"\r";
  [content addSubview:self.importButton];

  [self.parentWindow beginSheet:sheet completionHandler:nil];
}

- (void)onCancel:(id)sender {
  [self.parentWindow endSheet:self.window];
}

- (void)onImport:(id)sender {
  NSString* selected = self.sourcePopup.titleOfSelectedItem;
  BOOL importBookmarks = (self.bookmarksCheck.state == NSControlStateValueOn);
  BOOL importHistory = (self.historyCheck.state == NSControlStateValueOn);

  if ([selected isEqualToString:@"Passwords CSV File…"]) {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"csv"]];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
      if (result == NSModalResponseOK && panel.URL && self.credentials) {
        size_t count = slate::BrowserImporter::ImportPasswordsCsv(panel.URL.path.UTF8String, *self.credentials);
        slate::ImportSummary summary;
        summary.passwords_imported = count;
        std::vector<slate::HistoryItem> emptyHist;
        if (self.completionBlock) self.completionBlock(summary, emptyHist);
        [self.parentWindow endSheet:self.window];
      }
    }];
    return;
  }

  [self.spinner startAnimation:nil];
  self.statusText.stringValue = @"Importing…";
  self.importButton.enabled = NO;
  self.cancelButton.enabled = NO;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    slate::ImportSummary summary;
    std::vector<slate::HistoryItem> history;

    if ([selected containsString:@"Dia"] && self.bookmarks) {
      summary = slate::BrowserImporter::ImportFromDia(importBookmarks, importHistory, *self.bookmarks, history);
    } else if ([selected containsString:@"Chrome"] && self.bookmarks) {
      summary = slate::BrowserImporter::ImportFromChrome(importBookmarks, importHistory, *self.bookmarks, history);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [self.spinner stopAnimation:nil];
      self.statusText.stringValue = @"Done!";

      if (self.completionBlock) {
        self.completionBlock(summary, history);
      }
      [self.parentWindow endSheet:self.window];
    });
  });
}

@end
