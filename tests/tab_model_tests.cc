#include "core/tab_model.h"
#include <cstdlib>
#include <iostream>
using namespace slate;
void check(bool condition) { if(!condition) std::abort(); }
int main() {
 TabModel model;
 for(int i=0;i<20;++i) model.add("https://example.com/"+std::to_string(i));
 check(model.tabs().size()==20 && model.selected()==20);
 model.select(1); model.opened(1);
 model.select(2); model.opened(2);
 model.select(3); model.opened(3);
 ProtectionSignals clean; clean.observed=true; clean.loading=false; clean.uncertain=false;
 clean.observed_at=std::chrono::steady_clock::now();
 model.observe(1,clean); model.observe(2,clean); model.observe(3,clean);
 check(model.find(1)->state==Lifecycle::Warm && model.find(3)->state==Lifecycle::Active);
 model.protect(1,true);
 check(model.find(1)->state==Lifecycle::Protected);
 model.pin(1,true);
 check(model.find(1)->pinned);
 check(!model.begin_close(1,CloseReason::Discard));
 check(model.begin_close(2,CloseReason::Discard));
 check(model.live(2) && model.find(2)->state!=Lifecycle::Discarded);
 check(!model.select(2) && !model.begin_close(2,CloseReason::Remove));
 model.cancel_close(2); check(model.select(2) && model.live(2));
 check(model.begin_close(2,CloseReason::Discard)); model.closed(2);
 check(model.tabs().size()==20 && !model.live(2) && model.find(2)->state==Lifecycle::Discarded);
 check(model.select(2)); model.opened(2); check(model.live(2));
 TabModel restored(model.tabs());
 check(restored.tabs().size()==20 && restored.selected()==2);
 for(const auto& tab:restored.tabs()) check(!restored.live(tab.id) && tab.state==Lifecycle::Discarded);
 restored.opened(restored.selected());
 check(restored.live(2) && !restored.live(1) && restored.find(1)->protected_content && restored.find(1)->pinned);
 restored.begin_close(2,CloseReason::Remove); restored.closed(2);
 check(!restored.find(2) && restored.selected()==3 && restored.tabs().size()==19);
 const auto id=restored.add("about:blank"); check(id==21);
 // Remove unloaded records and keep selection valid.
 restored.begin_close(id,CloseReason::Remove); restored.closed(id);
 check(restored.selected()!=id && restored.find(restored.selected()));
 const auto grouped=restored.add("https://grouped.example");
 const auto gid=restored.add_group("Research");
 check(restored.set_tab_group(grouped,gid) && restored.find(grouped)->group_id==gid);
 TabModel concurrent;
 const auto a=concurrent.add("about:blank"); concurrent.opened(a);
 const auto b=concurrent.add("about:blank"); concurrent.opened(b);
 const auto c=concurrent.add("about:blank"); concurrent.opened(c);
 concurrent.begin_close(b,CloseReason::Remove);
 concurrent.begin_close(c,CloseReason::Remove);
 concurrent.closed(c);
 check(concurrent.selected()==a);
 concurrent.closed(b); check(concurrent.selected()==a);
 bool rejected=false;
 try { TabModel invalid({{1,"about:blank",""},{1,"about:blank",""}}); }
 catch(...) { rejected=true; }
 check(rejected);
 TabModel incog;
 const auto regular = incog.add("https://example.com");
 const auto stealth = incog.add("https://secret.com", true);
 check(!incog.find(regular)->incognito);
 check(incog.find(stealth)->incognito);
 check(incog.selected() == stealth);
 
 // Picture-in-Picture active tab protection
 TabModel pipModel;
 const auto p1 = pipModel.add("https://youtube.com/watch?v=123");
 const auto p2 = pipModel.add("https://example.com");
 pipModel.opened(p1);
 pipModel.opened(p2);
 pipModel.observe(p1, clean);
 pipModel.observe(p2, clean);
 check(pipModel.selected() == p2);
 check(pipModel.find(p1)->state == Lifecycle::Warm);
 pipModel.set_pip_active(p1, true);
 check(pipModel.find(p1)->pip_active);
 check(pipModel.find(p1)->state == Lifecycle::Protected);
 check(pipModel.find(p1)->is_protected(std::chrono::steady_clock::now()));
 pipModel.set_pip_active(p1, false);
 check(!pipModel.find(p1)->pip_active);
 check(pipModel.find(p1)->state == Lifecycle::Warm);

 std::cout << "Tab lifecycle, cancellation, 20-tab lazy restore, IDs, incognito and PiP passed\n";
}
