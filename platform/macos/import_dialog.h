// File purpose: Declares the native dialog for selecting a source browser and categories to
// import.

#import <Cocoa/Cocoa.h>
#include "core/library.h"
#include "core/credential_store.h"
#include "platform/macos/browser_importer.h"

// Slate note: The dialog collects choices and reports them through a completion callback.
@interface SlateImportDialog : NSWindowController

+ (void)showModalForWindow:(NSWindow*)parentWindow
                 bookmarks:(slate::BookmarkList*)bookmarks
           credentialStore:(slate::CredentialStore*)credentials
                onComplete:(void (^)(slate::ImportSummary summary, const std::vector<slate::HistoryItem>& history))completion;

@end
