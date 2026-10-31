// File purpose: Reads the current application process physical footprint using the Mach task API.

#include "memory_monitor.h"
#include <mach/mach.h>
namespace slate {
// Slate note: phys_footprint covers this process only; separate WebKit content/network processes require
// separate whole-browser attribution.
MemorySample sample_memory(Pressure pressure) {
 task_vm_info_data_t info{};
 mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
 const auto status = task_info(mach_task_self(), TASK_VM_INFO,
 reinterpret_cast<task_info_t>(&info), &count);
 return {pressure, status == KERN_SUCCESS ? info.phys_footprint : 0, true};
}
}
