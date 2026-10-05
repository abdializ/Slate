#include "memory_monitor.h"
#include <dispatch/dispatch.h>
#include <sys/sysctl.h>
#include <memory>
namespace slate {
namespace {
struct MonitorState {
 std::function<void(MemorySample)> callback;
 bool active=true;
 Pressure pressure=Pressure::Normal;
 bool known=false;
 void emit() {
  if(!active) return;
  auto sample=sample_memory(pressure); sample.pressure_known=known; callback(sample);
 }
};
class MacMemoryMonitor final : public MemoryMonitor {
 public:
 explicit MacMemoryMonitor(std::function<void(MemorySample)> callback) {
  state_=std::make_shared<MonitorState>(); state_->callback=std::move(callback);
  int level=0; size_t size=sizeof(level);
  if(sysctlbyname("kern.memorystatus_vm_pressure_level",&level,&size,nullptr,0)==0) {
   state_->known=level==DISPATCH_MEMORYPRESSURE_NORMAL || level==DISPATCH_MEMORYPRESSURE_WARN || level==DISPATCH_MEMORYPRESSURE_CRITICAL;
   state_->pressure=level==DISPATCH_MEMORYPRESSURE_CRITICAL ? Pressure::Critical : level==DISPATCH_MEMORYPRESSURE_WARN ? Pressure::Warning : Pressure::Normal;
  }
  const auto state=state_;
  pressure_=dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE,0,
   DISPATCH_MEMORYPRESSURE_NORMAL|DISPATCH_MEMORYPRESSURE_WARN|DISPATCH_MEMORYPRESSURE_CRITICAL,dispatch_get_main_queue());
  if(pressure_) {
   __weak dispatch_source_t weakSource=pressure_;
   dispatch_source_set_event_handler(pressure_, ^{
    dispatch_source_t source=weakSource;
    if(!source || !state->active) return;
    const auto flags=dispatch_source_get_data(source);
    state->known=true;
    state->pressure=(flags&DISPATCH_MEMORYPRESSURE_CRITICAL) ? Pressure::Critical :
      (flags&DISPATCH_MEMORYPRESSURE_WARN) ? Pressure::Warning : Pressure::Normal;
    state->emit();
   });
   dispatch_resume(pressure_);
  } else { state_->known=false; }
  timer_=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  if(timer_) {
   dispatch_source_set_timer(timer_,dispatch_time(DISPATCH_TIME_NOW,0),10*NSEC_PER_SEC,NSEC_PER_SEC);
   dispatch_source_set_event_handler(timer_, ^{ state->emit(); });
   dispatch_resume(timer_);
  }
 }
 ~MacMemoryMonitor() override {
  state_->active=false; state_->callback={};
  if(timer_) dispatch_source_cancel(timer_);
  if(pressure_) dispatch_source_cancel(pressure_);
 }
 private:
 std::shared_ptr<MonitorState> state_;
 dispatch_source_t pressure_=nullptr;
 dispatch_source_t timer_=nullptr;
};
}
std::unique_ptr<MemoryMonitor> monitor_memory(std::function<void(MemorySample)> callback) {
 return std::make_unique<MacMemoryMonitor>(std::move(callback));
}
}
