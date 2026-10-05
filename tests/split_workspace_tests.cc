#include "platform/macos/split_workspace.h"
#include <cassert>
#include <cmath>

int main() {
 slate::WorkspaceLayout workspace;
 assert(!workspace.split());
 workspace.open(10,20,slate::SplitSide::Right);
 assert(workspace.split() && workspace.left==10 && workspace.right==20);
 assert(workspace.active_tab()==20);
 assert(workspace.visible_for(10) && workspace.visible_for(20));
 assert(!workspace.visible_for(30));

 // Focusing an already visible pane must not replace the other pane.
 workspace.select(10);
 assert(workspace.left==10 && workspace.right==20 && workspace.active_tab()==10);
 workspace.select(30);
 assert(workspace.left==10 && workspace.right==20 && workspace.active_tab()==10);
 assert(!workspace.visible_for(30));
 workspace.select(20);
 assert(workspace.active_tab()==20 && workspace.visible_for(20));
 workspace.select(30);
 assert(workspace.left==10 && workspace.right==20 && workspace.active_tab()==20);

 workspace.ratio=0.65;
 workspace.swap();
 assert(workspace.left==20 && workspace.right==10);
 assert(workspace.active_tab()==20 && std::abs(workspace.ratio-0.35)<0.001);
 assert(workspace.remove(30)==0 && workspace.split());
 assert(workspace.remove(10)==20 && !workspace.split());

 workspace.open(1,2,slate::SplitSide::Left);
 assert(workspace.left==2 && workspace.right==1 && workspace.active_tab()==2);
 workspace.ratio=0.1;
 assert(workspace.clamped_ratio(1200)>=0.29);
 workspace.ratio=0.9;
 assert(workspace.clamped_ratio(1200)<=0.71);
 assert(workspace.clamped_ratio(500)>0.30 && workspace.clamped_ratio(500)<0.70);

 // Opening a second pair preserves the first, including its divider and side.
 workspace.ratio=0.62;
 workspace.open(3,4,slate::SplitSide::Right);
 assert(workspace.pairs().size()==2);
 assert(workspace.visible_for(4) && !workspace.visible_for(2));
 assert(workspace.same_pair(1,2) && workspace.same_pair(3,4));
 workspace.ratio=0.38;
 workspace.select(1);
 assert(workspace.visible_for(1) && workspace.left==2 && workspace.right==1);
 assert(std::abs(workspace.ratio-0.62)<0.001);
 workspace.select(5);
 assert(!workspace.visible_for(5) && workspace.pairs().size()==2);
 workspace.select(3);
 assert(workspace.visible_for(3) && workspace.active_tab()==3);
 assert(std::abs(workspace.ratio-0.38)<0.001);

 // Removing one pair cannot destroy the other; no tab may join two pairs.
 assert(workspace.remove(2)==1 && workspace.pairs().size()==1);
 assert(!workspace.member(1) && workspace.same_pair(3,4));
 workspace.open(1,6,slate::SplitSide::Right);
 assert(workspace.pairs().size()==2);
 workspace.replace(4,slate::SplitSide::Right);
 assert(workspace.pairs().size()==1 && workspace.same_pair(1,4));
 assert(!workspace.member(3) && !workspace.member(6));
 workspace.clear_all();
 assert(!workspace.split() && workspace.pairs().empty());

 // Starting another split while the first is visible must create a new pair,
 // not replace a side of the existing pair.
 slate::WorkspaceLayout multiple;
 multiple.open(1,2,slate::SplitSide::Right);
 assert(multiple.open_action(4,3)==slate::SplitOpenAction::PairWithBase);
 multiple.open(3,4,slate::SplitSide::Right);
 assert(multiple.pairs().size()==2 && multiple.same_pair(1,2) && multiple.same_pair(3,4));
 assert(multiple.open_action(5,4)==slate::SplitOpenAction::UnavailableTarget);
 assert(multiple.open_action(5,0)==slate::SplitOpenAction::UnavailableTarget);
 assert(multiple.open_action(5,5)==slate::SplitOpenAction::UnavailableTarget);
 assert(multiple.open_action(5,6)==slate::SplitOpenAction::PairWithBase);
 multiple.open(6,5,slate::SplitSide::Right);
 assert(multiple.pairs().size()==3 && multiple.same_pair(1,2) &&
        multiple.same_pair(3,4) && multiple.same_pair(6,5));
 assert(!multiple.open(2,7,slate::SplitSide::Right));
 assert(!multiple.open(7,4,slate::SplitSide::Right));
 assert(multiple.pairs().size()==3 && multiple.same_pair(1,2) &&
        multiple.same_pair(3,4) && multiple.same_pair(6,5));
 assert(multiple.open_action(2,5)==slate::SplitOpenAction::ShowExisting);
 multiple.select(2);
 assert(multiple.visible_for(2) && multiple.pairs().size()==3);

 // Filling an intentionally empty pane changes only that pair.
 slate::WorkspaceLayout placeholders;
 assert(placeholders.open(10,11,slate::SplitSide::Right));
 assert(placeholders.open(20,21,slate::SplitSide::Right));
 placeholders.replace(22,slate::SplitSide::Right);
 assert(placeholders.same_pair(20,22) && placeholders.same_pair(10,11));
 assert(!placeholders.member(21) && placeholders.pairs().size()==2);
}
