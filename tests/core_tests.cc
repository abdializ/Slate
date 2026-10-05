#include "core/resource_controller.h"
#include <cstdlib>
#include <iostream>
using namespace slate;
void check(bool condition) { if (!condition) std::abort(); }
int main() {
 auto now = std::chrono::steady_clock::now();
 std::vector<Tab> tabs{{1,"https://example.com","",Lifecycle::Active,true,false,now},
 {2,"https://example.org","",Lifecycle::Warm,false,true,now},
 {3,"https://example.net","",Lifecycle::Warm,false,false,now},
 {4,"https://example.edu","",Lifecycle::Discarded,false,false,now}};
 for(auto& tab:tabs) { tab.protection.observed=true; tab.protection.loading=false;
  tab.protection.uncertain=false; tab.protection.observed_at=now; }
 ResourceController controller;
 auto changes = controller.evaluate(tabs,{Pressure::Critical,0,true},now);
 check(changes.size()==2);
 check(changes[0].id==2 && changes[0].target==Lifecycle::Protected);
 check(changes[1].id==3 && changes[1].target==Lifecycle::Discarded);
 tabs[2].last_used=now-std::chrono::minutes(4);
 changes=controller.evaluate(tabs,{Pressure::Normal,0,true},now);
 check(changes[1].target==Lifecycle::Cold);
 tabs[2].last_used=now-std::chrono::minutes(16);
 changes=controller.evaluate(tabs,{Pressure::Normal,0,true},now);
 check(changes[1].target==Lifecycle::Discarded);
 check(tabs[2].state==Lifecycle::Warm); // Policy is side-effect free.
 tabs[1].selected=true; tabs[1].state=Lifecycle::Protected;
 changes=controller.evaluate(tabs,{Pressure::Critical,0,true},now);
 check(changes[0].id==2 && changes[0].target==Lifecycle::Active);
 tabs[1].selected=false;
 tabs[2].last_used=now;
 changes=controller.evaluate(tabs,{Pressure::Warning,0,true},now);
 check(changes.size()==1 && changes[0].id==3 && changes[0].target==Lifecycle::Cold);
 tabs[2].state=Lifecycle::Cold;
 changes=controller.evaluate(tabs,{Pressure::Normal,0,true},now);
 check(changes.size()==1 && changes[0].target==Lifecycle::Warm);
 // Picture-in-Picture active tabs MUST be immune to discard under Critical pressure
 tabs[2].pip_active=true;
 tabs[2].last_used=now-std::chrono::hours(1);
 changes=controller.evaluate(tabs,{Pressure::Critical,0,true},now);
 bool tab3_discarded=false;
 for(const auto& c : changes) {
  if(c.id==3 && c.target==Lifecycle::Discarded) tab3_discarded=true;
  if(c.id==3) check(c.target==Lifecycle::Protected);
 }
 check(!tab3_discarded);
 check(controller.evaluate({}, {}, now).empty());
 std::cout << "Resource policy invariants passed\n";
}
