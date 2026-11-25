// File purpose: Implements native application footprint sampling and cancellable system memory-
// pressure observations.

#include "memory_monitor.h"
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <malloc/malloc.h>
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
// Slate note: Use dispatch pressure events and a periodic sampler on the main queue; shutdown cancels both
// sources.
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
   dispatch_source_set_timer(timer_,dispatch_time(DISPATCH_TIME_NOW,0),60*NSEC_PER_SEC,15*NSEC_PER_SEC);
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

void trim_process_memory(bool force) {
 static dispatch_queue_t trim_queue = nullptr;
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  trim_queue = dispatch_queue_create("dev.slate.browser.memory-trim", DISPATCH_QUEUE_SERIAL);
 });
 dispatch_async(trim_queue, ^{
  static uint64_t last_after_trim = 0;
  constexpr uint64_t kMarginBytes = 48ULL * 1024ULL * 1024ULL;
  auto current_footprint = []() -> uint64_t {
   task_vm_info_data_t info{};
   mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
   if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS) {
    return info.phys_footprint;
   }
   return 0;
  };
  const uint64_t before = current_footprint();
  if (!force && last_after_trim > 0 && before <= last_after_trim + kMarginBytes) return;
  malloc_zone_pressure_relief(nullptr, 0);
  last_after_trim = current_footprint();
 });
}
}
