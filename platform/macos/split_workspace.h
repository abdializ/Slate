// File purpose: Stores active and parked split groups (2–4 panes), divider shares,
// magnetic snap bounds, and pane-selection rules.
// This is layout state over existing tab IDs; it does not own or create page views.

#pragma once

#include "core/browser_engine.h"
#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>

namespace slate {

enum class SplitSide { Left, Right };
enum class SplitOpenAction { ShowExisting, PairWithBase, UnavailableTarget };

struct SplitPair {
 static constexpr size_t kMaxPanes = 4;

 TabId left = 0;
 TabId right = 0;
 double ratio = 0.5;
 SplitSide active = SplitSide::Left;

 // Multi-pane representation (2..4 panes in display order, sizes summing to 1.0).
 std::vector<TabId> tabs;
 std::vector<double> sizes;
 TabId focused = 0;

 SplitPair() = default;
 SplitPair(TabId l, TabId r, double rat = 0.5, SplitSide act = SplitSide::Left)
  : left(l), right(r), ratio(rat), active(act),
    tabs({l, r}), sizes(clamp_sizes({rat, 1.0 - rat})),
    focused(act == SplitSide::Right ? r : l) {}
 SplitPair(std::vector<TabId> pane_tabs, std::vector<double> pane_sizes = {}, TabId foc = 0)
  : tabs(std::move(pane_tabs)), focused(foc) {
  if (tabs.size() > kMaxPanes) tabs.resize(kMaxPanes);
  sizes = pane_sizes.size() == tabs.size() ? clamp_sizes(pane_sizes) : even_sizes(tabs.size());
  if (!contains(focused) && !tabs.empty()) focused = tabs.front();
  sync_legacy();
 }

 static double least_share(size_t count) { return count <= 2 ? 0.2 : 0.1; }

 static std::vector<double> even_sizes(size_t count) {
  if (count == 0) return {};
  return std::vector<double>(count, 1.0 / static_cast<double>(count));
 }

 static std::vector<double> clamp_sizes(const std::vector<double>& input) {
  if (input.empty()) return {};
  if (input.size() == 1) return {1.0};
  if (input.size() == 2) {
   double first = (std::isfinite(input[0]) && input[0] > 0.0) ? input[0] : 0.5;
   first = std::clamp(first, 0.2, 0.8);
   return {first, 1.0 - first};
  }
  std::vector<double> shares(input.size());
  double total = 0.0;
  for (size_t i = 0; i < input.size(); ++i) {
   shares[i] = (std::isfinite(input[i]) && input[i] > 0.0) ? input[i] : 1.0;
   total += shares[i];
  }
  if (total <= 0.0) return even_sizes(input.size());
  for (double& s : shares) s /= total;
  const double least = least_share(shares.size());
  double shortage = 0.0;
  double spare = 0.0;
  for (double s : shares) {
   if (s < least) shortage += (least - s);
   else spare += (s - least);
  }
  if (shortage > 0.0 && spare > 0.0) {
   for (double& s : shares) {
    if (s < least) s = least;
    else s -= ((s - least) / spare) * shortage;
   }
  }
  return shares;
 }

 void sync_legacy() {
  if (tabs.size() >= 2) {
   left = tabs.front();
   right = tabs.back();
   ratio = sizes.empty() ? 0.5 : sizes.front();
   active = (focused == right && tabs.size() == 2) ? SplitSide::Right : SplitSide::Left;
  } else {
   left = 0;
   right = 0;
   ratio = 0.5;
   active = SplitSide::Left;
  }
 }

 bool valid() const { return tabs.size() >= 2; }
 bool is_full() const { return tabs.size() >= kMaxPanes; }

 bool contains(TabId id) const {
  if (!id) return false;
  if (!tabs.empty()) {
   return std::find(tabs.begin(), tabs.end(), id) != tabs.end();
  }
  return left == id || right == id;
 }

 int index_of(TabId id) const {
  for (size_t i = 0; i < tabs.size(); ++i) {
   if (tabs[i] == id) return static_cast<int>(i);
  }
  return -1;
 }

 TabId partner_of(TabId id) const {
  const int idx = index_of(id);
  if (idx < 0 || tabs.size() < 2) return 0;
  return (static_cast<size_t>(idx + 1) < tabs.size()) ? tabs[idx + 1] : tabs[idx - 1];
 }

 bool insert_pane(TabId tab, TabId neighbour = 0, bool before = false) {
  if (!tab || is_full() || contains(tab)) return false;
  size_t pos = tabs.size();
  const int idx = neighbour ? index_of(neighbour) : -1;
  if (idx >= 0) pos = before ? static_cast<size_t>(idx) : static_cast<size_t>(idx + 1);
  tabs.insert(tabs.begin() + static_cast<std::ptrdiff_t>(pos), tab);
  sizes = even_sizes(tabs.size());
  focused = tab;
  sync_legacy();
  return true;
 }

 bool remove_pane(TabId tab) {
  const int idx = index_of(tab);
  if (idx < 0) return tabs.size() >= 2;
  const TabId next_focus = partner_of(tab);
  tabs.erase(tabs.begin() + idx);
  if (static_cast<size_t>(idx) < sizes.size()) sizes.erase(sizes.begin() + idx);
  if (sizes.size() != tabs.size()) sizes = even_sizes(tabs.size());
  else sizes = clamp_sizes(sizes);
  if (focused == tab) focused = next_focus;
  sync_legacy();
  return tabs.size() >= 2;
 }
};

// Split groups only reference existing tabs. The selected split is kept in the
// foreground fields; parked splits retain membership, order, and divider positions.
struct WorkspaceLayout {
 static constexpr size_t kMaxPanes = SplitPair::kMaxPanes;
 static constexpr double kMinPaneWidth = 250.0;

 TabId left = 0;
 TabId right = 0;
 double ratio = 0.5;
 SplitSide active = SplitSide::Left;

 std::vector<TabId> active_tabs_list;
 std::vector<double> active_sizes_list;
 TabId active_focused_tab = 0;
 std::vector<SplitPair> parked;

 bool split() const {
  if (active_tabs_list.size() >= 2) return true;
  return left && right && left != right;
 }
 size_t pane_count() const {
  if (active_tabs_list.size() >= 2) return active_tabs_list.size();
  return (left && right && left != right) ? 2 : 0;
 }
 bool is_full() const { return pane_count() >= kMaxPanes; }
 bool contains(TabId id) const {
  if (!id || !split()) return false;
  if (active_tabs_list.size() >= 2) {
   return std::find(active_tabs_list.begin(), active_tabs_list.end(), id) != active_tabs_list.end();
  }
  return left == id || right == id;
 }
 bool visible_for(TabId selected) const { return contains(selected); }
 bool member(TabId id) const { return pair_for(id).has_value(); }

 TabId active_tab() const {
  if (active_tabs_list.size() >= 2) {
   if (active_focused_tab && contains(active_focused_tab)) return active_focused_tab;
   return active == SplitSide::Right ? right : left;
  }
  return active == SplitSide::Left ? left : right;
 }

 const std::vector<TabId>& active_tabs() const { return active_tabs_list; }

 std::vector<double> active_sizes() const {
  if (active_tabs_list.size() == 2 && active_sizes_list.size() == 2) {
   // Respect direct mutations to `ratio` by callers/tests.
   if (std::abs(active_sizes_list[0] - ratio) > 1e-9) {
    return SplitPair::clamp_sizes({ratio, 1.0 - ratio});
   }
  }
  if (active_sizes_list.size() == active_tabs_list.size() && !active_sizes_list.empty()) {
   return active_sizes_list;
  }
  return SplitPair::even_sizes(active_tabs_list.size());
 }

 int pane_index(TabId id) const {
  for (size_t i = 0; i < active_tabs_list.size(); ++i) {
   if (active_tabs_list[i] == id) return static_cast<int>(i);
  }
  return -1;
 }

 SplitPair foreground_pair() const {
  SplitPair p;
  if (active_tabs_list.size() >= 2) {
   p.tabs = active_tabs_list;
   p.sizes = active_sizes();
   p.focused = active_tab();
   p.sync_legacy();
   if (active_tabs_list.size() == 2) p.ratio = ratio;
  } else if (left && right && left != right) {
   p = SplitPair(left, right, ratio, active);
  }
  return p;
 }

 std::optional<SplitPair> pair_for(TabId id) const {
  if (contains(id)) return foreground_pair();
  for (const auto& pair : parked) if (pair.contains(id)) return pair;
  return std::nullopt;
 }

 bool same_pair(TabId a, TabId b) const {
  const auto pair = pair_for(a);
  return pair && pair->contains(b);
 }

 SplitOpenAction open_action(TabId source, TabId base) const {
  if (member(source)) return SplitOpenAction::ShowExisting;
  if (!base || base == source || member(base)) return SplitOpenAction::UnavailableTarget;
  return SplitOpenAction::PairWithBase;
 }

 std::vector<SplitPair> pairs() const {
  auto result = parked;
  if (split()) result.push_back(foreground_pair());
  return result;
 }

 bool open(TabId base, TabId added, SplitSide side) {
  if (!base || !added || base == added || member(base) || member(added)) return false;
  if (split()) parked.push_back(foreground_pair());
  const TabId l = side == SplitSide::Left ? added : base;
  const TabId r = side == SplitSide::Right ? added : base;
  active_tabs_list = {l, r};
  active_sizes_list = {0.5, 0.5};
  active_focused_tab = added;
  left = l;
  right = r;
  active = side;
  ratio = 0.5;
  return true;
 }

 bool open_group(const std::vector<TabId>& tabs, const std::vector<double>& sizes = {}, TabId focused = 0) {
  if (tabs.size() < 2 || tabs.size() > kMaxPanes) return false;
  for (size_t i = 0; i < tabs.size(); ++i) {
   if (!tabs[i] || member(tabs[i])) return false;
   for (size_t j = i + 1; j < tabs.size(); ++j) if (tabs[i] == tabs[j]) return false;
  }
  if (split()) parked.push_back(foreground_pair());
  active_tabs_list = tabs;
  active_sizes_list = (sizes.size() == tabs.size()) ? SplitPair::clamp_sizes(sizes) : SplitPair::even_sizes(tabs.size());
  active_focused_tab = (focused && contains(focused)) ? focused : tabs.front();
  sync_legacy_from_active();
  return true;
 }

 // Insert a 3rd or 4th pane into the foreground split (or beside a specific pane).
 bool add_pane(TabId added, TabId neighbour = 0, bool before = false) {
  if (!split() || !added || is_full() || member(added)) return false;
  SplitPair fg = foreground_pair();
  if (!fg.insert_pane(added, neighbour, before)) return false;
  load_foreground(fg);
  return true;
 }

 // Replace a specific tab inside the foreground split (e.g., filling a blank pane).
 bool replace_tab(TabId target, TabId replacement) {
  if (!split() || !target || !replacement || !contains(target)) return false;
  if (target == replacement) { active_focused_tab = replacement; sync_legacy_from_active(); return true; }
  if (contains(replacement)) {
   // Swap positions within the same split.
   const int a = pane_index(target);
   const int b = pane_index(replacement);
   if (a >= 0 && b >= 0) {
    std::swap(active_tabs_list[a], active_tabs_list[b]);
    active_focused_tab = replacement;
    sync_legacy_from_active();
   }
   return true;
  }
  drop_pair_containing(replacement);
  const int idx = pane_index(target);
  if (idx < 0) return false;
  active_tabs_list[idx] = replacement;
  active_focused_tab = replacement;
  sync_legacy_from_active();
  return true;
 }

 // Legacy 2-pane replace helper.
 void replace(TabId id, SplitSide side) {
  if (!split() || !id) return;
  const TabId target = side == SplitSide::Left ? left : right;
  const TabId opposite = side == SplitSide::Left ? right : left;
  if (active_tabs_list.size() == 2 && id == opposite) { swap(); active = side; active_focused_tab = id; return; }
  replace_tab(target, id);
  active = side;
 }

 void select(TabId id) {
  if (!id) return;
  if (!contains(id)) {
   for (size_t i = 0; i < parked.size(); ++i) if (parked[i].contains(id)) {
    const SplitPair previous = foreground_pair();
    const SplitPair incoming = parked[i];
    if (previous.valid()) parked[i] = previous;
    else parked.erase(parked.begin() + static_cast<std::ptrdiff_t>(i));
    load_foreground(incoming);
    break;
   }
  }
  if (contains(id)) {
   active_focused_tab = id;
   if (id == left) active = SplitSide::Left;
   else if (id == right) active = SplitSide::Right;
  }
 }

 void set_sizes(const std::vector<double>& sizes) {
  if (!split() || sizes.size() != active_tabs_list.size()) return;
  active_sizes_list = SplitPair::clamp_sizes(sizes);
  ratio = active_sizes_list.front();
 }

 void even() {
  if (!split()) return;
  active_sizes_list = SplitPair::even_sizes(active_tabs_list.size());
  ratio = active_sizes_list.front();
 }

 // Removes a tab from its split. For 3–4 pane splits, the remaining panes stay split;
 // for a 2-pane split, the split dissolves and the surviving tab ID is returned.
 TabId remove(TabId id) {
  if (!id) return 0;
  if (contains(id)) {
   SplitPair fg = foreground_pair();
   const TabId survivor = fg.partner_of(id);
   if (fg.remove_pane(id)) {
    load_foreground(fg);
    return survivor;
   }
   clear();
   return survivor;
  }
  for (auto it = parked.begin(); it != parked.end(); ++it) if (it->contains(id)) {
   const TabId survivor = it->partner_of(id);
   if (!it->remove_pane(id)) parked.erase(it);
   return survivor;
  }
  return 0;
 }

 // Exit the current split completely; older parked splits remain available.
 void clear() {
  if (parked.empty()) {
   active_tabs_list.clear();
   active_sizes_list.clear();
   active_focused_tab = 0;
   left = right = 0;
   ratio = 0.5;
   active = SplitSide::Left;
  } else {
   const SplitPair next = parked.back();
   parked.pop_back();
   load_foreground(next);
  }
 }

 void clear_all() {
  parked.clear();
  active_tabs_list.clear();
  active_sizes_list.clear();
  active_focused_tab = 0;
  left = right = 0;
  ratio = 0.5;
  active = SplitSide::Left;
 }

 void swap() {
  if (!split()) return;
  if (active_tabs_list.size() == 2) {
   std::swap(active_tabs_list[0], active_tabs_list[1]);
   active_sizes_list = {1.0 - ratio, ratio};
   std::swap(left, right);
   active = active == SplitSide::Left ? SplitSide::Right : SplitSide::Left;
   ratio = 1.0 - ratio;
   active_focused_tab = active == SplitSide::Left ? left : right;
   return;
  }
  std::reverse(active_tabs_list.begin(), active_tabs_list.end());
  std::reverse(active_sizes_list.begin(), active_sizes_list.end());
  sync_legacy_from_active();
 }

 bool collapsed_for_width(double width) const {
  if (!split() || width <= 0.0) return false;
  return width < static_cast<double>(pane_count()) * kMinPaneWidth;
 }

 double clamped_ratio(double width) const {
  if (width <= 0) return 0.5;
  const double minimum = std::min(360.0, std::max(160.0, width * 0.35));
  const double edge = std::min(0.5, minimum / width);
  return std::clamp(ratio, edge, 1.0 - edge);
 }

 std::vector<double> clamped_sizes(double width) const {
  const size_t n = pane_count();
  if (n == 0) return {};
  if (n == 2) {
   const double r = clamped_ratio(width);
   return {r, 1.0 - r};
  }
  return SplitPair::clamp_sizes(active_sizes());
 }

private:
 void sync_legacy_from_active() {
  if (active_tabs_list.size() >= 2) {
   left = active_tabs_list.front();
   right = active_tabs_list.back();
   if (active_sizes_list.size() != active_tabs_list.size()) {
    active_sizes_list = SplitPair::even_sizes(active_tabs_list.size());
   }
   ratio = active_sizes_list.front();
   active = (active_focused_tab == right && active_tabs_list.size() == 2) ? SplitSide::Right : SplitSide::Left;
  } else {
   left = right = 0;
   ratio = 0.5;
   active = SplitSide::Left;
  }
 }

 void load_foreground(const SplitPair& pair) {
  active_tabs_list = pair.tabs;
  active_sizes_list = pair.sizes.size() == pair.tabs.size()
   ? pair.sizes : SplitPair::even_sizes(pair.tabs.size());
  active_focused_tab = pair.focused;
  if (pair.tabs.size() == 2) {
   left = pair.left;
   right = pair.right;
   ratio = pair.ratio;
   active = pair.active;
   if (!active_focused_tab) active_focused_tab = active == SplitSide::Right ? right : left;
  } else {
   sync_legacy_from_active();
  }
 }

 void drop_pair_containing(TabId id) {
  if (contains(id)) {
   SplitPair fg = foreground_pair();
   if (fg.remove_pane(id)) load_foreground(fg);
   else {
    active_tabs_list.clear();
    active_sizes_list.clear();
    active_focused_tab = 0;
    left = right = 0;
    ratio = 0.5;
    active = SplitSide::Left;
   }
   return;
  }
  for (auto it = parked.begin(); it != parked.end(); ) {
   if (it->contains(id)) {
    if (!it->remove_pane(id)) it = parked.erase(it);
    else ++it;
   } else {
    ++it;
   }
  }
 }
};

} // namespace slate
