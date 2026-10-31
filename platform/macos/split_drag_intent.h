// Passive split targeting used by the tab's existing drag gesture.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>

namespace slate {
class SplitDragIntent {
 public:
  static constexpr double band = 120.0;
  static constexpr double band_share = 0.24;
  static constexpr double slack = 20.0;
  static constexpr double settle = 6.0;
  static constexpr double still = 0.09;
  // Used by native verification callers as the stationary recheck interval.
  static constexpr double hold_seconds = still;
  static double edge_band(double width) { return std::max(band,width*band_share); }
  static int edge_side(double width, double x, int shown=0) {
    if(width<=0 || x<0 || x>width) return 0;
    const double edge=edge_band(width);
    if(x<=edge+(shown==1 ? slack : 0)) return 1;
    if(x>=width-edge-(shown==2 ? slack : 0)) return 2;
    return 0;
  }
  bool update(std::uint64_t source, std::uint64_t target, int zone, int side,
              double x, double y, double now) {
    if(!source || !target || !side) { reset(); return false; }
    if(source!=source_ || target!=target_ || zone!=zone_ || side!=side_ || now<last_) {
      reset(); source_=source; target_=target; zone_=zone; side_=side; entered_=now;
    }
    last_=now;
    trail_.push_back({x,y,now});
    while(!trail_.empty() && now-trail_.front().at>0.5) trail_.pop_front();
    if(armed_) return true;
    if(now-entered_+1e-9<still) return false;
    // Motion within the last 90 ms must fit inside the six-point settling radius.
    // A stationary timer recheck needs no additional mouse event to reveal it.
    for(const auto& sample:trail_)
      if(now-sample.at<=still+1e-9 && std::hypot(sample.x-x,sample.y-y)>=settle) return false;
    armed_=true;
    return true;
  }
  void reset() {
    source_=target_=0; zone_=side_=0; armed_=false; entered_=last_=0; trail_.clear();
  }
 private:
  struct Sample { double x,y,at; };
  std::deque<Sample> trail_;
  std::uint64_t source_=0,target_=0;
  int zone_=0,side_=0;
  double entered_=0,last_=0;
  bool armed_=false;
};
} // namespace slate
