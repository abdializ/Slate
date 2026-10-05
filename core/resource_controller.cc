#include "resource_controller.h"
namespace slate {
std::vector<Transition> ResourceController::evaluate(const std::vector<Tab>& tabs,
 MemorySample memory, std::chrono::steady_clock::time_point now) const {
 std::vector<Transition> result;
 for (const auto& tab : tabs) {
  auto next = tab.state;
  const auto idle = now - tab.last_used;
  if (tab.state == Lifecycle::Discarded) continue; // Never resurrect from policy.
  if (tab.selected) next = Lifecycle::Active;
  else if (tab.is_protected(now) || !memory.pressure_known) next = Lifecycle::Protected;
  else if (memory.pressure == Pressure::Critical || idle >= std::chrono::minutes(15)) next = Lifecycle::Discarded;
  else if (memory.pressure == Pressure::Warning || idle >= std::chrono::minutes(3)) next = Lifecycle::Cold;
  else next = Lifecycle::Warm;
  if (next != tab.state) result.push_back({tab.id, next});
 }
 return result;
}
}
