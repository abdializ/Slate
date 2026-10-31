// File purpose: Checks that native memory callbacks arrive and stop after monitor destruction.
// Tests document the behavior they assert; they do not change production browser behavior.

#import <Foundation/Foundation.h>
#include "platform/macos/memory_monitor.h"
#include <cstdlib>
#include <iostream>
// Slate note: Run the synthetic scenarios below; failed assertions/checks terminate the executable so
// CTest can report a failure.
int main() { @autoreleasepool {
 int callbacks=0;
 auto monitor=slate::monitor_memory([&](slate::MemorySample sample) {
  ++callbacks;
  if(sample.browser_footprint_bytes==0) std::abort();
 });
 NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:2];
 while(callbacks==0 && deadline.timeIntervalSinceNow>0)
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 if(callbacks==0) std::abort();
 // Slate note: Destroy the monitor, then verify that queued work cannot call the released observer.
 monitor.reset(); const int before=callbacks;
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
 if(callbacks!=before) std::abort();
 std::cout << "Native memory sampling and monitor cancellation passed\n";
}}
