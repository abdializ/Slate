#pragma once

#include "core/browser_engine.h"
#include <algorithm>
#include <optional>
#include <vector>

namespace slate {

enum class SplitSide { Left, Right };
enum class SplitOpenAction { ShowExisting, PairWithBase, UnavailableTarget };

struct SplitPair {
 TabId left = 0;
 TabId right = 0;
 double ratio = 0.5;
 SplitSide active = SplitSide::Left;
 bool contains(TabId id) const { return id && (left == id || right == id); }
};

// Split pairs only reference existing tabs. The selected pair is kept in the
// foreground fields; parked pairs retain membership and divider positions.
struct WorkspaceLayout {
 TabId left = 0;
 TabId right = 0;
 double ratio = 0.5;
 SplitSide active = SplitSide::Left;
 std::vector<SplitPair> parked;

 bool split() const { return left && right && left != right; }
 bool contains(TabId id) const { return split() && (left == id || right == id); }
 bool visible_for(TabId selected) const { return contains(selected); }
 bool member(TabId id) const { return pair_for(id).has_value(); }
 TabId active_tab() const { return active == SplitSide::Left ? left : right; }

 std::optional<SplitPair> pair_for(TabId id) const {
  if(contains(id)) return SplitPair{left,right,ratio,active};
  for(const auto& pair:parked) if(pair.contains(id)) return pair;
  return std::nullopt;
 }
 bool same_pair(TabId a, TabId b) const {
  const auto pair=pair_for(a);
  return pair && pair->contains(b);
 }
 SplitOpenAction open_action(TabId source, TabId base) const {
  if(member(source)) return SplitOpenAction::ShowExisting;
  if(!base || base==source || member(base)) return SplitOpenAction::UnavailableTarget;
  return SplitOpenAction::PairWithBase;
 }
 std::vector<SplitPair> pairs() const {
  auto result=parked;
  if(split()) result.push_back({left,right,ratio,active});
  return result;
 }

 bool open(TabId base, TabId added, SplitSide side) {
  // Creating a split never steals either page from an existing split. Pane
  // replacement is a separate, explicit operation.
  if(!base || !added || base == added || member(base) || member(added)) return false;
  if(split()) parked.push_back({left,right,ratio,active});
  left = side == SplitSide::Left ? added : base;
  right = side == SplitSide::Right ? added : base;
  active = side;
  ratio = 0.5;
  return true;
 }

 // Only an explicit split action replaces one pane of the foreground pair.
 void replace(TabId id, SplitSide side) {
  if(!split() || !id) return;
  const TabId target=side==SplitSide::Left ? left : right;
  const TabId opposite=side==SplitSide::Left ? right : left;
  if(id==opposite) { swap(); active=side; return; }
  if(id!=target) {
   drop_pair_containing(id);
   if(side==SplitSide::Left) left=id;
   else right=id;
  }
  active=side;
 }

 void select(TabId id) {
  if(!id) return;
  if(!contains(id)) {
   for(size_t i=0;i<parked.size();++i) if(parked[i].contains(id)) {
    const SplitPair previous{left,right,ratio,active};
    const SplitPair incoming=parked[i];
    parked[i]=previous;
    left=incoming.left; right=incoming.right;
    ratio=incoming.ratio; active=incoming.active;
    break;
   }
  }
  if(id == left) active = SplitSide::Left;
  else if(id == right) active = SplitSide::Right;
 }

 TabId remove(TabId id) {
  if(!id) return 0;
  if(contains(id)) {
   const TabId survivor=id==left ? right : left;
   clear();
   return survivor;
  }
  for(auto it=parked.begin();it!=parked.end();++it) if(it->contains(id)) {
   const TabId survivor=id==it->left ? it->right : it->left;
   parked.erase(it);
   return survivor;
  }
  return 0;
 }

 // Exit the current pair; older pairs remain available.
 void clear() {
  if(parked.empty()) {
   left=right=0; ratio=0.5; active=SplitSide::Left;
  } else {
   const SplitPair next=parked.back();
   parked.pop_back();
   left=next.left; right=next.right;
   ratio=next.ratio; active=next.active;
  }
 }
 void clear_all() {
  parked.clear();
  left=right=0; ratio=0.5; active=SplitSide::Left;
 }
 void swap() {
  if(!split()) return;
  std::swap(left, right);
  active = active == SplitSide::Left ? SplitSide::Right : SplitSide::Left;
  ratio = 1.0 - ratio;
 }

 double clamped_ratio(double width) const {
  if(width <= 0) return 0.5;
  const double minimum = std::min(360.0, std::max(160.0, width * 0.35));
  const double edge = std::min(0.5, minimum / width);
  return std::clamp(ratio, edge, 1.0 - edge);
 }

private:
 void drop_pair_containing(TabId id) {
  if(contains(id)) {
   left=right=0; ratio=0.5; active=SplitSide::Left;
   return;
  }
  std::erase_if(parked,[id](const SplitPair& pair){ return pair.contains(id); });
 }
};

} // namespace slate
