#include "tab_model.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
namespace slate {
TabModel::TabModel(std::vector<Tab> restored, std::vector<TabGroup> groups)
 : tabs_(std::move(restored)), groups_(std::move(groups)) {
 std::set<TabId> ids;
 bool selected_seen=false;
 if(tabs_.size()>500) throw std::runtime_error("Too many saved tabs");
 if(groups_.size()>50) throw std::runtime_error("Too many tab groups");
 std::set<std::string> group_ids;
 for(auto& group:groups_) {
  if(group.id.empty() || group.title.size()>128 || !group_ids.insert(group.id).second)
   throw std::runtime_error("Invalid tab group");
  try { next_group_=std::max(next_group_,std::stoull(group.id)+1); } catch(...) {
   throw std::runtime_error("Invalid tab group");
  }
 }
 for(auto& tab: tabs_) {
  if(!tab.id || tab.id==std::numeric_limits<TabId>::max() || !ids.insert(tab.id).second)
   throw std::runtime_error("Invalid or duplicate tab ID");
  next_id_=std::max(next_id_,tab.id+1);
  tab.state=Lifecycle::Discarded;
  tab.protection={}; tab.page_interacted=false;
  tab.last_used=std::chrono::steady_clock::now();
  if(!tab.group_id.empty() && !group_ids.contains(tab.group_id)) tab.group_id.clear();
  if(tab.selected && !selected_seen) selected_seen=true;
  else tab.selected=false;
 }
 if(!selected_seen && !tabs_.empty()) tabs_.front().selected=true;
}
const Tab* TabModel::find(TabId id) const {
 for(const auto& tab:tabs_) if(tab.id==id) return &tab;
 return nullptr;
}
const TabGroup* TabModel::find_group(const std::string& id) const {
 for(const auto& group:groups_) if(group.id==id) return &group;
 return nullptr;
}
Tab* TabModel::mutable_tab(TabId id) { return const_cast<Tab*>(find(id)); }
TabGroup* TabModel::mutable_group(const std::string& id) { return const_cast<TabGroup*>(find_group(id)); }
TabId TabModel::selected() const {
 for(const auto& tab:tabs_) if(tab.selected) return tab.id;
 return 0;
}
TabId TabModel::add(std::string url, bool incognito) {
 if(tabs_.size()>=500 || next_id_==std::numeric_limits<TabId>::max())
  throw std::runtime_error("Tab limit reached");
 const TabId id=next_id_++;
 Tab tab{id,std::move(url),"New tab"};
 tab.incognito=incognito;
 tabs_.push_back(std::move(tab));
 select(id);
 return id;
}
bool TabModel::select(TabId id) {
 if(!find(id) || closing(id)) return false;
 for(auto& tab:tabs_) {
  tab.selected=tab.id==id;
  if(tab.selected) tab.last_used=std::chrono::steady_clock::now();
  if(!live(tab.id)) tab.state=Lifecycle::Discarded;
  else tab.state=tab.selected ? Lifecycle::Active :
    (tab.is_protected(std::chrono::steady_clock::now()) ? Lifecycle::Protected : Lifecycle::Warm);
 }
 return true;
}
void TabModel::opened(TabId id) {
 if(auto* tab=mutable_tab(id)) {
  live_.insert(id);
  tab->state=tab->selected ? Lifecycle::Active :
    (tab->is_protected(std::chrono::steady_clock::now()) ? Lifecycle::Protected : Lifecycle::Warm);
 }
}
void TabModel::update(TabId id,std::optional<std::string> url,std::optional<std::string> title) {
 if(auto* tab=mutable_tab(id)) {
  if(url) tab->url=std::move(*url);
  if(title) tab->title=std::move(*title);
 }
}
void TabModel::protect(TabId id,bool value) {
 if(auto* tab=mutable_tab(id); tab && !closing(id)) {
  tab->protected_content=value;
  if(live(id) && !tab->selected) tab->state=tab->is_protected(std::chrono::steady_clock::now()) ? Lifecycle::Protected : Lifecycle::Warm;
 }
}
void TabModel::set_pip_active(TabId id,bool active) {
 if(auto* tab=mutable_tab(id); tab && !closing(id)) {
  tab->pip_active=active;
  refresh_protection();
 }
}
void TabModel::pin(TabId id,bool value) {
 if(auto* tab=mutable_tab(id); tab && !closing(id)) tab->pinned=value;
}
std::string TabModel::add_group(std::string title) {
 if(groups_.size()>=50) throw std::runtime_error("Group limit reached");
 while(!title.empty() && (title.front()==' ' || title.back()==' ')) {
  if(title.front()==' ') title.erase(title.begin());
  else title.pop_back();
 }
 if(title.empty()) title="Group";
 if(title.size()>128) title.resize(128);
 TabGroup group{std::to_string(next_group_++),std::move(title),false};
 groups_.push_back(group);
 return group.id;
}
bool TabModel::rename_group(const std::string& id, std::string title) {
 auto* group=mutable_group(id);
 if(!group) return false;
 while(!title.empty() && (title.front()==' ' || title.back()==' ')) {
  if(title.front()==' ') title.erase(title.begin());
  else title.pop_back();
 }
 if(title.empty()) return false;
 if(title.size()>128) title.resize(128);
 group->title=std::move(title);
 return true;
}
bool TabModel::remove_group(const std::string& id) {
 const auto it=std::find_if(groups_.begin(),groups_.end(),[&](const TabGroup& group){ return group.id==id; });
 if(it==groups_.end()) return false;
 for(auto& tab:tabs_) if(tab.group_id==id) tab.group_id.clear();
 groups_.erase(it);
 return true;
}
bool TabModel::set_tab_group(TabId id, std::string group_id) {
 auto* tab=mutable_tab(id);
 if(!tab || closing(id)) return false;
 if(!group_id.empty() && !find_group(group_id)) return false;
 tab->group_id=std::move(group_id);
 return true;
}
void TabModel::reorder_tabs(const std::vector<TabId>& order) {
 std::map<TabId, size_t> pos;
 for(size_t i=0; i<order.size(); ++i) pos[order[i]] = i;
 std::stable_sort(tabs_.begin(), tabs_.end(), [&pos](const Tab& a, const Tab& b) {
  auto itA = pos.find(a.id);
  auto itB = pos.find(b.id);
  size_t posA = itA != pos.end() ? itA->second : std::numeric_limits<size_t>::max();
  size_t posB = itB != pos.end() ? itB->second : std::numeric_limits<size_t>::max();
  return posA < posB;
 });
}
bool TabModel::move_tab_before(TabId id, TabId before_id) {
 auto it = std::find_if(tabs_.begin(), tabs_.end(), [id](const Tab& t){ return t.id == id; });
 if (it == tabs_.end()) return false;
 Tab extracted = std::move(*it);
 tabs_.erase(it);
 if (before_id) {
  auto insert_it = std::find_if(tabs_.begin(), tabs_.end(), [before_id](const Tab& t){ return t.id == before_id; });
  if (insert_it != tabs_.end()) {
   tabs_.insert(insert_it, std::move(extracted));
   return true;
  }
 }
 tabs_.push_back(std::move(extracted));
 return true;
}
bool TabModel::set_group_collapsed(const std::string& id, bool collapsed) {
 auto* group=mutable_group(id);
 if(!group) return false;
 group->collapsed=collapsed;
 return true;
}
void TabModel::observe(TabId id,const ProtectionSignals& signals) {
 if(auto* tab=mutable_tab(id)) {
  if(signals.document_generation<tab->protection.document_generation) return;
  if(signals.document_generation!=tab->protection.document_generation) tab->page_interacted=false;
  tab->protection=signals;
  refresh_protection();
 }
}
void TabModel::note_interaction(TabId id) {
 if(auto* tab=mutable_tab(id)) { tab->page_interacted=true; refresh_protection(); }
}
void TabModel::refresh_protection() {
 const auto now=std::chrono::steady_clock::now();
 for(auto& tab:tabs_) if(live(tab.id) && !closing(tab.id))
  tab.state=tab.selected ? Lifecycle::Active : tab.is_protected(now) ? Lifecycle::Protected : Lifecycle::Warm;
}
bool TabModel::begin_close(TabId id,CloseReason reason) {
 const auto* tab=find(id);
 if(!tab || closing(id) || (reason==CloseReason::Discard && tab->protected_content)) return false;
 closing_[id]=reason;
 return true;
}
void TabModel::cancel_close(TabId id) { closing_.erase(id); }
void TabModel::closed(TabId id) {
 const auto pending=closing_.find(id);
 const auto reason=pending==closing_.end() ? CloseReason::Discard : pending->second;
 closing_.erase(id); live_.erase(id);
 if(reason==CloseReason::Remove) {
  const bool was_selected=selected()==id;
  const auto it=std::find_if(tabs_.begin(),tabs_.end(),[id](const auto& tab){return tab.id==id;});
  if(it==tabs_.end()) return;
  const auto index=static_cast<size_t>(it-tabs_.begin());
  tabs_.erase(it);
  if(was_selected && !tabs_.empty()) {
   for(size_t offset=0;offset<tabs_.size();++offset) {
    const auto candidate=tabs_[(std::min(index,tabs_.size()-1)+offset)%tabs_.size()].id;
    if(select(candidate)) break;
   }
  }
 } else if(auto* tab=mutable_tab(id)) {
  tab->state=Lifecycle::Discarded;
  tab->protection={}; tab->page_interacted=false;
 }
 if(!selected()) for(const auto& tab:tabs_) if(select(tab.id)) break;
}
}
