#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <algorithm>

// Normal pages join the solid toolbar with a small bleed. The New Tab
// gradient needs a flush lower edge so the tab does not paint over the plate.
static inline CGPathRef CreateActiveBrowserTabPath(CGRect bounds, bool flipped,
                                                 bool joinsToolbar = true) {
 const CGFloat w=CGRectGetWidth(bounds);
 const CGFloat h=CGRectGetHeight(bounds);
 const CGFloat radius=std::min(14.0, std::min(w/4.0, h/2.0));
 const CGFloat shoulder=std::min(18.0, w/4.0);
 const CGFloat depth=std::min(10.0, h/3.0);
 const CGFloat base=joinsToolbar ? -2.0 : 0.0;
 const CGFloat k=0.5522847498;
 CGMutablePathRef path=CGPathCreateMutable();
 CGPathMoveToPoint(path, nullptr, -shoulder, base);
 CGPathAddCurveToPoint(path, nullptr, -shoulder*0.45, base, 0, depth*0.35, 0, depth);
 CGPathAddLineToPoint(path, nullptr, 0, h-radius);
 CGPathAddCurveToPoint(path, nullptr, 0, h-radius*(1-k), radius*(1-k), h, radius, h);
 CGPathAddLineToPoint(path, nullptr, w-radius, h);
 CGPathAddCurveToPoint(path, nullptr, w-radius*(1-k), h, w, h-radius*(1-k), w, h-radius);
 CGPathAddLineToPoint(path, nullptr, w, depth);
 CGPathAddCurveToPoint(path, nullptr, w, depth*0.35, w+shoulder*0.45, base, w+shoulder, base);
 CGPathCloseSubpath(path);
 if(!flipped) return path;
 CGAffineTransform mirror=CGAffineTransformMake(1, 0, 0, -1, 0, h);
 CGPathRef reflected=CGPathCreateCopyByTransformingPath(path, &mirror);
 CGPathRelease(path);
 return reflected;
}
