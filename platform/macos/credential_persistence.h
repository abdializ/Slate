// File purpose: Declares Keychain-backed password persistence and reads of older saved-vault
// formats.

#pragma once
#include "core/credential_store.h"
#include <memory>
#include <string>

namespace slate {

// Slate note: The path identifies a profile-specific Keychain vault and the optional legacy file to read.
std::unique_ptr<CredentialStore> load_credentials(const std::string& path);
void save_credentials(const std::string& path, const CredentialStore& store);

} // namespace slate
