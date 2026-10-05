#pragma once
#include "core/credential_store.h"
#include <memory>
#include <string>

namespace slate {

std::unique_ptr<CredentialStore> load_credentials(const std::string& path);
void save_credentials(const std::string& path, const CredentialStore& store);

} // namespace slate
