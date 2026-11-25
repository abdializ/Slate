// File purpose: Implements native application footprint sampling and cancellable system memory-
// pressure observations.

#include "memory_monitor.h"
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <malloc/malloc.h>
#include <sys/sysctl.h>
#include <cstdio>
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
   dispatch_source_set_timer(timer_,dispatch_time(DISPATCH_TIME_NOW,0),30*NSEC_PER_SEC,10*NSEC_PER_SEC);
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
  dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
  trim_queue = dispatch_queue_create("dev.slate.browser.memory-trim", attr);
 });

 // All mutable state below is accessed strictly on the serial trim_queue.
 static uint64_t last_after_trim = 0;
 static uint64_t prev_settle_after = 0;
 static int stagnant_passes = 0;
 static bool settle_scheduled = false;

 static void (^run_trim)(bool, int) = nil;
 static dispatch_once_t block_once;
 dispatch_once(&block_once, ^{
  run_trim = [^(bool pass_force, int settle_depth) {
   constexpr uint64_t kMarginBytes = 32ULL * 1024ULL * 1024ULL;
   constexpr uint64_t kHighFootprintBytes = 140ULL * 1024ULL * 1024ULL;
   constexpr uint64_t kSettleFootprintBytes = 200ULL * 1024ULL * 1024ULL;
   constexpr int kMaxSettlePasses = 18; // Up to ~3 minutes during heavy DNR compilation.

   auto current_footprint = []() -> uint64_t {
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS) {
     return info.phys_footprint;
    }
    return 0;
   };

   const uint64_t before = current_footprint();
   const bool bloated = before > kHighFootprintBytes;
   if (!pass_force && !bloated && last_after_trim > 0 && before <= last_after_trim + kMarginBytes) {
    return;
   }

   // Purge all malloc zones (including xzone/DefaultMallocZone Malloc Large empty regions
   // left behind by WebKit declarativeNetRequest / ContentRuleList compilation).
   malloc_zone_pressure_relief(nullptr, 0);
   vm_address_t* zones = nullptr;
   unsigned zone_count = 0;
   if (malloc_get_all_zones(mach_task_self(), nullptr, &zones, &zone_count) == KERN_SUCCESS && zones) {
    for (unsigned i = 0; i < zone_count; ++i) {
     malloc_zone_t* z = reinterpret_cast<malloc_zone_t*>(zones[i]);
     if (z) malloc_zone_pressure_relief(z, 0);
    }
   }

   const uint64_t after = current_footprint();
   const uint64_t reclaimed = (before > after) ? (before - after) : 0;
   last_after_trim = after;
   if (reclaimed > (10ULL * 1024ULL * 1024ULL)) {
    fprintf(stderr, "SLATE_MALLOC_TRIM before=%.1fMB after=%.1fMB reclaimed=%.1fMB\n",
            before / (1024.0 * 1024.0), after / (1024.0 * 1024.0),
            reclaimed / (1024.0 * 1024.0));
   }

   // Self-terminating settle follow-up: if footprint is still elevated (>200 MB), an in-process
   // WebKit rule compilation is likely still running. Follow up every 10s (or 5s right after a big
   // reclaim) so pages return to macOS within seconds of completion, then stop completely at idle.
   if (after <= kSettleFootprintBytes) {
    stagnant_passes = 0;
    prev_settle_after = 0;
    return;
   }

   if (settle_depth > 0) {
    const bool big_reclaim = reclaimed >= (8ULL * 1024ULL * 1024ULL);
    const bool still_changing = prev_settle_after > 0 &&
                                (after > prev_settle_after + (16ULL * 1024ULL * 1024ULL) ||
                                 prev_settle_after > after + (16ULL * 1024ULL * 1024ULL));
    if (big_reclaim || still_changing) {
     stagnant_passes = 0;
    } else {
     ++stagnant_passes;
    }
   } else {
    stagnant_passes = 0;
   }
   prev_settle_after = after;

   if (!settle_scheduled && settle_depth < kMaxSettlePasses && stagnant_passes < 3) {
    settle_scheduled = true;
    const int delay_sec = (reclaimed >= (32ULL * 1024ULL * 1024ULL)) ? 5 : 10;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay_sec * NSEC_PER_SEC)), trim_queue, ^{
     settle_scheduled = false;
     run_trim(true, settle_depth + 1);
    });
   }
  } copy];
 });

 dispatch_async(trim_queue, ^{
  run_trim(force, 0);
 });
}
}
