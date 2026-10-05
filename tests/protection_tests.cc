#include "core/tab_model.h"
#include <cstdlib>
#include <iostream>
using namespace slate;
void check(bool value) { if(!value) std::abort(); }
int main() {
 const auto now=std::chrono::steady_clock::now();
 Tab tab{1,"https://example.com","Example",Lifecycle::Warm};
 ResourceController controller;
 auto target=[&](MemorySample sample) {
  auto changes=controller.evaluate({tab},sample,now);
  return changes.empty() ? tab.state : changes.front().target;
 };
 check(target({Pressure::Critical,0,true})==Lifecycle::Protected);
 ProtectionSignals clean;
 clean.document_generation=1; clean.observed=true; clean.loading=false;
 clean.uncertain=false; clean.observed_at=now;
 tab.protection=clean;
 check(target({Pressure::Critical,0,true})==Lifecycle::Discarded);
 check(target({})==Lifecycle::Protected); // Unknown system pressure cannot discard.
 for(bool ProtectionSignals::*flag : {&ProtectionSignals::loading,&ProtectionSignals::uncertain,
  &ProtectionSignals::form_controls,&ProtectionSignals::media_elements,&ProtectionSignals::capture,
  &ProtectionSignals::media_permission_requested,&ProtectionSignals::download,&ProtectionSignals::dialog}) {
  tab.protection=clean; tab.protection.*flag=true;
  check(target({Pressure::Critical,0,true})==Lifecycle::Protected);
 }
 tab.protection=clean; tab.page_interacted=true;
 check(target({Pressure::Critical,0,true})==Lifecycle::Protected);
 tab.page_interacted=false; tab.protection.observed_at=now-std::chrono::seconds(30);
 check(target({Pressure::Critical,0,true})==Lifecycle::Protected);
 tab.protection.observed_at=now+std::chrono::seconds(1);
 check(target({Pressure::Critical,0,true})==Lifecycle::Protected);
 tab.state=Lifecycle::Discarded; tab.selected=true;
 check(controller.evaluate({tab},{Pressure::Critical,0,true},now).empty());
 TabModel model;
 auto id=model.add("https://example.com"); model.opened(id); model.observe(id,clean);
 model.note_interaction(id); check(model.find(id)->page_interacted);
 model.observe(id,clean); check(model.find(id)->page_interacted); // Poll must not clear interaction.
 clean.document_generation=2; model.observe(id,clean); check(!model.find(id)->page_interacted);
 auto stale=clean; stale.document_generation=1; stale.form_controls=true;
 model.observe(id,stale); check(!model.find(id)->protection.form_controls);
 model.begin_close(id,CloseReason::Discard); model.closed(id);
 check(!model.find(id)->protection.observed && model.find(id)->protection.document_generation==0);
 model.opened(id); clean.document_generation=1; model.observe(id,clean);
 check(model.find(id)->protection.observed); // New renderer starts its own generation counter.
 model.protect(id,true);
 TabModel restored(model.tabs());
 check(restored.find(id)->protected_content && !restored.find(id)->protection.observed);
 std::cout << "Protection reasons, stale signals, navigation generations and fail-closed policy passed\n";
}
