// File purpose: Declares JSON persistence of tab metadata and groups for lazy session restoration.

#pragma once
#include "core/resource_controller.h"
#include <memory>
namespace slate {
// Slate note: The factory chooses a local session path; no engine/page snapshot is exposed by this API.
std::unique_ptr<SessionStore> make_session_store(const std::string& path);
}
