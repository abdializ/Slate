// File purpose: Declares native application footprint sampling and cancellable system memory-
// pressure observations.

#pragma once
#include "core/resource_controller.h"
#include <functional>
#include <memory>
namespace slate {
MemorySample sample_memory(Pressure pressure);
// Slate note: Destroying the monitor stops observation; the callback receives main-process footprint and
// pressure information.
class MemoryMonitor {
 public:
 virtual ~MemoryMonitor()=default;
};
// Main-queue callbacks, initial sample plus 10-second refresh and immediate OS
// pressure notifications. Destruction cancels both sources.
std::unique_ptr<MemoryMonitor> monitor_memory(std::function<void(MemorySample)> callback);
}
