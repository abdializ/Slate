// File purpose: Declares the native searchable password manager and authentication-gated password
// actions.

#import <Cocoa/Cocoa.h>
#include "core/credential_store.h"

// Slate note: The panel borrows a C++ credential store and requests persistence through its supplied save
// callback.
@interface SlatePasswordsPanel : NSPanel <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic,copy) dispatch_block_t onImportBlock;

+ (instancetype)sharedPanel;
+ (void)openApplePasswords;
- (void)showForCredentialStore:(slate::CredentialStore*)store onSave:(dispatch_block_t)onSave;
- (void)prepareForCredentialStore:(slate::CredentialStore*)store onSave:(dispatch_block_t)onSave;

@end
