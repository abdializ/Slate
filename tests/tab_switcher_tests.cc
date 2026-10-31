#include "core/tab_switcher.h"
#include <cassert>
using slate::TabSwitcherState;
int main() {
 TabSwitcherState s;
 const std::vector<slate::TabId> row{1,2,3,4,5,6,7,8,9,10,11,12};
 s.left(3,row); s.left(2,row);
 assert(s.begin(row,{},1,false,false));
 assert(s.cards.size()==10 && s.selected==2);
 const auto fixed=s.ring();
 s.step(false); assert(s.selected==3 && s.ring()==fixed);
 s.step(true); assert(s.selected==2);
 s.cancel(); assert(!s.active() && s.recent.front()==2);
 assert(s.begin(row,{20,21,22,23},1,false,true));
 assert(s.selected==23 && s.moon_columns()==2 && s.moons_per_column()==2);
 s.move(TabSwitcherState::Direction::Up); assert(s.selected==22);
 s.move(TabSwitcherState::Direction::Up); assert(s.selected==22);
 s.step(false); assert(s.selected==23);
 s.step(false); assert(s.selected==1);
 s.pick(2); s.move(TabSwitcherState::Direction::Down); assert(s.selected==7);
 s.move(TabSwitcherState::Direction::Up); assert(s.selected==2);
 s.remove(2); assert(s.selected==3 && !TabSwitcherState::contains(s.cards,2));
 s.remove(1); assert(!s.active());
 assert(s.begin({1,2},{20,21,22},21,true,false));
 assert(s.ring().front()==21 && s.selected==20);
 s.cancel();
 assert(s.begin({1,2,3,4,5,6},{},1,false,false));
 s.pick(5); s.move(TabSwitcherState::Direction::Down); assert(s.selected==6);
 s.cancel();
 assert(!s.begin({1},{},1,false,false));
 assert(!s.begin({1,2},{},99,false,false));
 assert(s.begin({1},{20},1,false,false)); s.remove(20); assert(!s.active());
 s.left(999,{1,2}); assert(!TabSwitcherState::contains(s.recent,999));
 assert(s.begin({1,1,2},{2,20,20},1,false,false));
 assert((s.ring()==std::vector<slate::TabId>{1,2,20}));
}
