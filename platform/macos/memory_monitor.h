#pragma once
#include "core/resource_controller.h"
#include <functional>
#include <memory>
namespace slate {
MemorySample sample_memory(Pressure pressure);
class MemoryMonitor {
 public:
 virtual ~MemoryMonitor()=default;
};
// Main-queue callbacks, initial sample plus 10-second refresh and immediate OS
// pressure notifications. Destruction cancels both sources.
std::unique_ptr<MemoryMonitor> monitor_memory(std::function<void(MemorySample)> callback);
}
