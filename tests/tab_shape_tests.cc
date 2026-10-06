#include "platform/macos/active_browser_tab_shape.h"
#include <cassert>
#include <cmath>
#include <cstdio>

int main() {
 for(CGFloat width : {30.0, 48.0, 110.0, 154.0, 180.0, 360.0}) {
  const CGFloat height=38.0;
  const CGFloat shoulder=std::min(18.0, width/4.0);
  CGPathRef path=CreateActiveBrowserTabPath(CGRectMake(0, 0, width, height), false);
  CGPathRef flipped=CreateActiveBrowserTabPath(CGRectMake(0, 0, width, height), true);
  CGRect bounds=CGPathGetBoundingBox(path);
  assert(std::abs(CGRectGetMinX(bounds)+shoulder)<0.01);
  assert(std::abs(CGRectGetMaxX(bounds)-width-shoulder)<0.01);
  assert(CGRectGetMinY(bounds)<0 && CGRectGetMaxY(bounds)==height);
  for(CGFloat y : {-1.0, 1.0, 5.0, 10.0, 20.0, 30.0, 37.0}) {
   for(CGFloat x=-shoulder+0.25; x<width/2; x+=0.5) {
    const bool left=CGPathContainsPoint(path, nullptr, CGPointMake(x, y), false);
    const bool right=CGPathContainsPoint(path, nullptr, CGPointMake(width-x, y), false);
    const bool reflected=CGPathContainsPoint(flipped, nullptr, CGPointMake(x, height-y), false);
    assert(left==right && left==reflected);
   }
  }
  assert(CGPathContainsPoint(path, nullptr, CGPointMake(width/2, -1), false));
  assert(CGPathContainsPoint(path, nullptr, CGPointMake(9, height/2), false));
  assert(CGPathContainsPoint(path, nullptr, CGPointMake(width-9, height/2), false));
  // New Tab must never paint into the toolbar in either coordinate system.
  for(bool isFlipped : {false, true}) {
   CGPathRef home=CreateActiveBrowserTabPath(CGRectMake(0,0,width,height),isFlipped,false);
   CGRect homeBounds=CGPathGetPathBoundingBox(home);
   assert(std::abs(CGRectGetMinY(homeBounds))<0.01);
   assert(std::abs(CGRectGetMaxY(homeBounds)-height)<0.01);
   assert(CGPathContainsPoint(home,nullptr,CGPointMake(width/2,height/2),false));
   for(CGFloat x=-shoulder; x<=width+shoulder; x+=0.5) {
    assert(!CGPathContainsPoint(home,nullptr,CGPointMake(x,-1),false));
    assert(!CGPathContainsPoint(home,nullptr,CGPointMake(x,height+1),false));
   }
   CGPathRelease(home);
  }
  CGPathRelease(flipped);
  CGPathRelease(path);
 }
 puts("normal tab shoulders are symmetric; New Tab never paints outside the tab row");
}
