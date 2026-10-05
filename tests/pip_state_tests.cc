#include "engine/pip_state.h"
#include <cassert>
int main() {
 slate::PiPState state;
 assert(!state.active());
 assert(state.frame("show",true) && state.active());
 assert(!state.frame("ad",false) && state.active());
 assert(!state.remove_frame("ad") && state.active());
 assert(state.remove_frame("show") && !state.active());
 state.frame("show",true);
 state.native(true);
 state.remove_frame("show");
 state.frame("new-ad-frame",false);
 assert(state.active()); // DOM rebuilds cannot contradict native PiP.
 state.native(false);
 assert(!state.active());
 state.frame("stale-show",true);
 assert(!state.active()); // Stale DOM cannot resurrect a closed native window.
 state.native(true);
 state.clear_frames();
 assert(state.active());
 state.native(false);
 assert(!state.active());
}
