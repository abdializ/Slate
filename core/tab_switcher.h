// Gesture-local tab order. This state owns no pages or native views.
#pragma once
#include "browser_engine.h"
#include <algorithm>
#include <vector>

namespace slate {
class TabSwitcherState {
 public:
 enum class Direction { Left, Right, Up, Down };
 std::vector<TabId> recent, cards, moons;
 TabId home=0, selected=0;
 bool moons_lead=false;
 bool active() const { return home!=0; }
 int moon_columns() const { return (static_cast<int>(moons.size())+2)/3; }
 int moons_per_column() const { return moons.empty() ? 0 : (static_cast<int>(moons.size())+moon_columns()-1)/moon_columns(); }
 void left(TabId id, const std::vector<TabId>& alive) {
  std::erase_if(recent,[&](TabId item){ return item==id || !contains(alive,item); });
  if(id && contains(alive,id)) recent.insert(recent.begin(),id);
  if(recent.size()>10) recent.resize(10);
 }
 std::vector<TabId> ordered(const std::vector<TabId>& row, TabId current, size_t limit=10) const {
  std::vector<TabId> result;
  auto add=[&](TabId id) { if(result.size()<limit && contains(row,id) && !contains(result,id)) result.push_back(id); };
  add(current);
  for(auto id:recent) add(id);
  for(auto id:row) add(id);
  return result;
 }
 std::vector<TabId> ring() const {
  auto result=moons_lead ? moons : cards;
  const auto& tail=moons_lead ? cards : moons;
  result.insert(result.end(),tail.begin(),tail.end());
  return result;
 }
 bool begin(const std::vector<TabId>& row, const std::vector<TabId>& windows, TabId current, bool from_moon, bool backwards) {
  cancel();
  cards=ordered(row,from_moon ? 0 : current);
  for(auto id:ordered(windows,from_moon ? current : 0,9)) if(!contains(cards,id)) moons.push_back(id);
  moons_lead=from_moon;
  const auto all=ring();
  if(all.size()<2 || all.front()!=current) { cancel(); return false; }
  home=current;
  selected=backwards ? all.back() : all[1];
  return true;
 }
 void step(bool backwards) {
  const auto all=ring();
  const auto it=std::find(all.begin(),all.end(),selected);
  if(!active() || it==all.end()) return;
  const auto index=static_cast<size_t>(it-all.begin());
  selected=all[(index+all.size()+(backwards ? -1 : 1))%all.size()];
 }
 void move(Direction direction) {
  if(!active()) return;
  if(direction==Direction::Left || direction==Direction::Right) return step(direction==Direction::Left);
  const bool moon=contains(moons,selected);
  const auto& list=moon ? moons : cards;
  const auto it=std::find(list.begin(),list.end(),selected);
  if(it==list.end()) return;
  const int index=static_cast<int>(it-list.begin());
  int next=index+(direction==Direction::Up ? -1 : 1)*(moon ? 1 : 5);
  if(!moon && direction==Direction::Down && index<5 && list.size()>5)
   next=std::min(next,static_cast<int>(list.size())-1);
  if(next<0 || next>=static_cast<int>(list.size())) return;
  if(moon && next/moons_per_column()!=index/moons_per_column()) return;
  selected=list[next];
 }
 bool pick(TabId id) { if(!contains(ring(),id)) return false; selected=id; return true; }
 void remove(TabId id) {
  if(!active()) return;
  if(id==home) { cancel(); return; }
  const auto before=ring();
  const auto it=std::find(before.begin(),before.end(),id);
  if(it==before.end()) return;
  const TabId successor=before[(static_cast<size_t>(it-before.begin())+1)%before.size()];
  std::erase(cards,id); std::erase(moons,id); std::erase(recent,id);
  if(ring().size()<2) cancel();
  else if(selected==id) selected=successor;
 }
 void cancel() { cards.clear(); moons.clear(); home=selected=0; moons_lead=false; }
 static bool contains(const std::vector<TabId>& values, TabId id) { return std::find(values.begin(),values.end(),id)!=values.end(); }
};
}
