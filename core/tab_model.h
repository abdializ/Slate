#pragma once
#include "resource_controller.h"
#include <map>
#include <set>
namespace slate {
enum class CloseReason { Discard, Remove, Shutdown };
// UI-thread logical state only. No native views, engine objects or CEF headers.
class TabModel {
 public:
 explicit TabModel(std::vector<Tab> restored = {}, std::vector<TabGroup> groups = {});
 const std::vector<Tab>& tabs() const { return tabs_; }
 const std::vector<TabGroup>& groups() const { return groups_; }
 const Tab* find(TabId id) const;
 const TabGroup* find_group(const std::string& id) const;
 TabId selected() const;
 TabId add(std::string url, bool incognito = false);
 bool select(TabId id);
 void opened(TabId id);
 void update(TabId id, std::optional<std::string> url, std::optional<std::string> title);
 void protect(TabId id, bool value);
 void set_pip_active(TabId id, bool active);
 void pin(TabId id, bool value);
 std::string add_group(std::string title);
 bool rename_group(const std::string& id, std::string title);
 bool remove_group(const std::string& id);
 bool set_tab_group(TabId id, std::string group_id);
 void reorder_tabs(const std::vector<TabId>& order);
 bool move_tab_before(TabId id, TabId before_id);
 bool set_group_collapsed(const std::string& id, bool collapsed);
 void observe(TabId id, const ProtectionSignals& signals);
 void note_interaction(TabId id);
 void refresh_protection();
 bool live(TabId id) const { return live_.contains(id); }
 bool closing(TabId id) const { return closing_.contains(id); }
 std::optional<CloseReason> close_reason(TabId id) const {
  const auto it=closing_.find(id);
  return it==closing_.end() ? std::nullopt : std::optional<CloseReason>(it->second);
 }
 bool begin_close(TabId id, CloseReason reason);
 void cancel_close(TabId id);
 void closed(TabId id);
 private:
 Tab* mutable_tab(TabId id);
 TabGroup* mutable_group(const std::string& id);
 std::vector<Tab> tabs_;
 std::vector<TabGroup> groups_;
 std::set<TabId> live_;
 std::map<TabId,CloseReason> closing_;
 TabId next_id_ = 1;
 unsigned long long next_group_ = 1;
};
}
