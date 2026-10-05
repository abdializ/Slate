#pragma once
#include <chrono>
#include <optional>
#include <string>
#include <vector>
#include "browser_engine.h"
#include "protection.h"
namespace slate {
enum class Lifecycle { Active, Warm, Cold, Discarded, Protected };
enum class Pressure { Normal, Warning, Critical };
struct Tab {
 TabId id;
 std::string url;
 std::string title;
 Lifecycle state = Lifecycle::Discarded;
 bool selected = false;
 bool protected_content = false; // User-selected Keep loaded preference.
 std::chrono::steady_clock::time_point last_used = std::chrono::steady_clock::now();
 ProtectionSignals protection;
 bool page_interacted = false; // Sticky until a new document commits.
 bool pinned = false; // Sidebar placement only; independent of Keep loaded.
 std::string group_id; // Empty means ungrouped.
 bool incognito = false; // Isolated in-memory untrackable mode.
 bool pip_active = false; // Native Picture-in-Picture active for this tab.
 bool is_protected(std::chrono::steady_clock::time_point now) const {
  return protected_content || pip_active || page_interacted || protection.blocks_discard(now);
 }
 std::string protection_reason(std::chrono::steady_clock::time_point now) const {
  if(protected_content) return "Keep loaded";
  if(pip_active) return "Picture-in-Picture active";
  if(page_interacted) return "Page interaction; work may be unsaved";
  return protection.reason(now);
 }
};
struct TabGroup {
 std::string id;
 std::string title;
 bool collapsed = false;
};
struct MemorySample {
 Pressure pressure = Pressure::Normal;
 uint64_t browser_footprint_bytes = 0; // Browser process only; NOT total Chromium memory.
 bool pressure_known = false;
};
struct Transition { TabId id; Lifecycle target; };
// Pure policy: suggests transitions, never calls an engine or mutates tabs.
class ResourceController {
 public:
 std::vector<Transition> evaluate(const std::vector<Tab>& tabs, MemorySample memory,
                                 std::chrono::steady_clock::time_point now) const;
};
class SessionStore {
 public:
 virtual ~SessionStore() = default;
 virtual std::vector<Tab> load() = 0;
 virtual void save(const std::vector<Tab>& tabs) = 0;
 virtual std::vector<TabGroup> last_groups() const { return {}; }
 virtual void save(const std::vector<Tab>& tabs, const std::vector<TabGroup>& groups) { save(tabs); (void)groups; }
};
}
