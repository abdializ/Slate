#include "core/library.h"
#include "core/tab_model.h"
#include <cstdlib>
#include <iostream>
using namespace slate;
void check(bool condition) { if(!condition) std::abort(); }
int main() {
 BookmarkList list;
 const auto a=list.add("https://example.com/a","Alpha");
 const auto b=list.add("https://example.com/b","Beta");
 check(list.items().size()==2 && list.find(a) && list.find_url("https://example.com/b")->title=="Beta");
 check(list.add("https://example.com/a","Alpha renamed")==a);
 check(list.items().size()==2 && list.find(a)->title=="Alpha renamed");
 check(list.remove(b) && !list.find(b) && list.items().size()==1);
 bool bad=false;
 try { list.add("javascript:alert(1)","x"); } catch(...) { bad=true; }
 check(bad);

 TabModel model;
 model.add("https://one.example");
 model.add("https://two.example");
 const auto work=model.add_group("Work");
 check(model.groups().size()==1 && model.find_group(work));
 check(model.set_tab_group(1,work) && model.find(1)->group_id==work);
 check(!model.set_tab_group(1,"missing"));
 check(model.set_group_collapsed(work,true) && model.find_group(work)->collapsed);
 check(model.rename_group(work,"Office") && model.find_group(work)->title=="Office");
 TabModel restored(model.tabs(), model.groups());
 check(restored.find(1)->group_id==work && restored.find_group(work)->title=="Office");
 check(restored.remove_group(work) && restored.find(1)->group_id.empty() && restored.groups().empty());
 std::cout << "Bookmarks and tab groups passed\n";
}
