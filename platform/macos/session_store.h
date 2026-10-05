#pragma once
#include "core/resource_controller.h"
#include <memory>
namespace slate {
std::unique_ptr<SessionStore> make_session_store(const std::string& path);
}
