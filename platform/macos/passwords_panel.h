#import <Cocoa/Cocoa.h>
#include "core/credential_store.h"

@interface SlatePasswordsPanel : NSPanel <NSTableViewDataSource, NSTableViewDelegate>

+ (instancetype)sharedPanel;
+ (void)openApplePasswords;
- (void)showForCredentialStore:(slate::CredentialStore*)store onSave:(dispatch_block_t)onSave;

@end
