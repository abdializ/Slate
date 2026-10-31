#include "platform/macos/split_drag_intent.h"
#include <cassert>
int main() {
 using Intent=slate::SplitDragIntent;
 assert(Intent::edge_band(400)==120);
 assert(Intent::edge_band(1000)==240);
 assert(Intent::edge_side(1000,240)==1);
 assert(Intent::edge_side(1000,241)==0);
 assert(Intent::edge_side(1000,259,1)==1); // Shown side retains 20 points of slack.
 assert(Intent::edge_side(1000,261,1)==0);
 assert(Intent::edge_side(1000,741,2)==2);
 assert(Intent::edge_side(1000,500)==0);
 assert(Intent::edge_side(1000,-1,1)==0);
 Intent intent;
 const auto move=[&](int side,double x,double y,double t) { return intent.update(2,1,1,side,x,y,t); };
 assert(!move(1,100,100,0));
 assert(!move(1,110,100,0.04));
 assert(!move(1,120,100,0.08));
 assert(!move(1,125,100,0.10)); // Crossing an edge band is not a split.
 assert(move(1,125,100,0.20)); // Stationary recheck reveals the preview.
 assert(move(1,160,110,0.21)); // Once shown, movement inside that band is fine.
 assert(!move(2,900,100,0.22)); // The opposite side must settle independently.
 assert(!move(2,902,102,0.26));
 assert(move(2,902,102,0.32)); // Small hand jitter is tolerated.
 assert(!move(0,500,100,0.33)); // Leaving the band dismisses the preview.
 assert(!move(2,900,100,0.34));
 assert(!move(2,900,100,0.40));
 assert(move(2,900,100,0.44));
 intent.reset();
 assert(!move(2,900,100,10));
 assert(!intent.update(3,1,1,2,900,100,11));
 assert(!intent.update(3,4,1,2,900,100,12));
 assert(intent.update(3,4,1,2,900,100,12.10));
 assert(!intent.update(3,4,1,2,900,100,1)); // Time reset cannot inherit a preview.
}
