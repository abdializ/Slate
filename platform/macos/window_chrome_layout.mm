#import "window_chrome_layout.h"
#include <cmath>
#include <algorithm>

void SlateApplyWindowControlClearance(NSLayoutConstraint* plateFromTraffic,
 NSLayoutConstraint* navigationLeading, BOOL sharesToolbar,
 CGFloat trafficRightEdge, CGFloat plateInset) {
 const CGFloat safeLeading=trafficRightEdge>0 ? std::ceil(trafficRightEdge+16) : 0;
 // Retain this measurement for a revealed narrow icon rail, but never use it
 // as a full-height page constraint when the sidebar is hidden.
 if(std::abs(plateFromTraffic.constant-safeLeading)>0.5) plateFromTraffic.constant=safeLeading;
 plateFromTraffic.active=NO;
 const CGFloat leading=sharesToolbar && trafficRightEdge>0
  ? std::max<CGFloat>(16,safeLeading-plateInset) : 16;
 if(std::abs(navigationLeading.constant-leading)>0.5) navigationLeading.constant=leading;
}
