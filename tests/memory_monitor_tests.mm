#import <Foundation/Foundation.h>
#include "platform/macos/memory_monitor.h"
#include <cstdlib>
#include <iostream>
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
 monitor.reset(); const int before=callbacks;
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
 if(callbacks!=before) std::abort();
 std::cout << "Native memory sampling and monitor cancellation passed\n";
}}
