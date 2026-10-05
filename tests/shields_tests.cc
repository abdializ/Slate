#include "core/shields.h"
#include "filtering/network_engine.h"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <string>
#ifndef SLATE_SOURCE_DIR
#define SLATE_SOURCE_DIR "."
#endif
int main() {
 using namespace slate;
 const auto engine=FilterEngine::parse(R"(
||ads.example^
||tracker.example^$script
||doubleclick.net^
/ads/banner.png
@@||cdn.example^
@@||ads.example^$domain=allowed.example
||googlevideo.com^
@@||googlevideo.com^
)");
 auto blocked=engine.classify({.url="https://ads.example/pixel.gif",.source_url="https://news.example/",.kind=ResourceKind::Image});
 assert(blocked.action==FilterAction::Block);
 auto script=engine.classify({.url="https://tracker.example/ga.js",.source_url="https://news.example/",.kind=ResourceKind::Script});
 assert(script.action==FilterAction::Block);
 auto image_ok=engine.classify({.url="https://tracker.example/logo.png",.source_url="https://news.example/",.kind=ResourceKind::Image});
 assert(image_ok.action==FilterAction::Allow);
 auto path=engine.classify({.url="https://cdn.news.example/ads/banner.png",.source_url="https://news.example/",.kind=ResourceKind::Image});
 assert(path.action==FilterAction::Block);
 auto except=engine.classify({.url="https://cdn.example/ads.js",.source_url="https://news.example/",.kind=ResourceKind::Script});
 assert(except.action==FilterAction::Allow);
 auto allowed_site=engine.classify({.url="https://ads.example/pixel.gif",.source_url="https://allowed.example/",.kind=ResourceKind::Image});
 assert(allowed_site.action==FilterAction::Allow);
 auto first=engine.classify({.url="https://news.example/app.js",.source_url="https://news.example/",.kind=ResourceKind::Script});
 assert(first.action==FilterAction::Allow);
 auto media=engine.classify({.url="https://rr1.googlevideo.com/videoplayback",.source_url="https://www.youtube.com/watch?v=1",.kind=ResourceKind::Media});
 assert(media.action==FilterAction::Allow);
 auto shields=ShieldController::from_rules("||ads.example^\n");
 auto decision=shields.classify({.url="https://ads.example/x",.source_url="https://news.example/",.kind=ResourceKind::Image});
 assert(decision.action==FilterAction::Block);
 auto main=shields.classify({.url="https://ads.example/",.source_url="",.kind=ResourceKind::Document});
 assert(main.action==FilterAction::Allow);
 shields.pause_site("news.example");
 shields.note_block("news.example","paused rule");
 assert(shields.page_stats("news.example").blocked==0);
 auto paused=shields.classify({.url="https://ads.example/x",.source_url="https://news.example/",.kind=ResourceKind::Image});
 assert(paused.action==FilterAction::Allow);
 shields.resume_site("news.example");
 shields.set_mode(ShieldMode::Off);
 shields.note_block("news.example","disabled rule");
 assert(shields.page_stats("news.example").blocked==0);
 auto off=shields.classify({.url="https://ads.example/x",.source_url="https://news.example/",.kind=ResourceKind::Image});
 assert(off.action==FilterAction::Allow);
 shields.set_mode(ShieldMode::Standard);
 shields.note_block("news.example","||ads.example^");
 assert(shields.page_stats("news.example").blocked==1);
 shields.reset_page("news.example");
 assert(shields.page_stats("news.example").blocked==0);

 const std::string root=SLATE_SOURCE_DIR;
 auto lists=ShieldController::from_list_files({
  root+"/filtering/lists/easylist-network.txt",
  root+"/filtering/lists/easyprivacy-network.txt",
  root+"/filtering/lists/slate-network.txt",
  root+"/filtering/lists/compat.txt"
 });
 assert(lists.block_rules()>20000);
 assert(lists.exception_rules()>100);
 auto ad=lists.classify({.url="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js",
  .source_url="https://news.example/article",.kind=ResourceKind::Script});
 assert(ad.action==FilterAction::Block);
 auto pixel=lists.classify({.url="https://www.google-analytics.com/analytics.js",
  .source_url="https://news.example/article",.kind=ResourceKind::Script});
 assert(pixel.action==FilterAction::Block);
 auto article=lists.classify({.url="https://news.example/hero.jpg",
  .source_url="https://news.example/article",.kind=ResourceKind::Image});
 assert(article.action==FilterAction::Allow);
 auto yt=lists.classify({.url="https://rr5---sn-abc.googlevideo.com/videoplayback?id=1",
  .source_url="https://www.youtube.com/watch?v=jNQXAC9IVRw",.kind=ResourceKind::Media});
 assert(yt.action==FilterAction::Allow);
 const auto started=std::chrono::steady_clock::now();
 constexpr int kLookups=400;
 uint64_t hits=0;
 for(int i=0;i<kLookups;++i) {
  auto d=lists.classify({.url="https://pagead2.googlesyndication.com/pagead/ads?n="+std::to_string(i),
   .source_url="https://news.example/article",.kind=ResourceKind::Script});
  if(d.action==FilterAction::Block) ++hits;
 }
 const auto elapsed=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
 assert(hits==kLookups);
 assert(elapsed<80.0);
 std::fprintf(stderr,"SLATE_SHIELDS_TEST rules=%zu exceptions=%zu lookups=%d ms=%.2f\n",
  lists.block_rules(),lists.exception_rules(),kLookups,elapsed);
 return 0;
}
