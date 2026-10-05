#include "engine/floating_video_js.h"
#include <cassert>
#include <iostream>
#include <string>

int main() {
  std::cout << "Running floating video tests...\n";

  // Test KnownPlayers database
  assert(slate::KnownPlayers::knows("https://www.youtube.com/watch?v=dQw4w9WgXcQ"));
  assert(slate::KnownPlayers::knows("https://youtu.be/dQw4w9WgXcQ"));
  assert(slate::KnownPlayers::knows("https://netflix.com/browse"));
  assert(slate::KnownPlayers::knows("https://www.netflix.com/watch/12345"));
  assert(slate::KnownPlayers::knows("https://www.primevideo.com/detail/0XYZ"));
  assert(slate::KnownPlayers::knows("https://amazon.com/gp/video/storefront"));
  assert(slate::KnownPlayers::knows("https://www.amazon.de/gp/video/detail/B000"));
  assert(slate::KnownPlayers::knows("https://disneyplus.com/video/abc"));
  assert(slate::KnownPlayers::knows("https://tv.apple.com/show/ted-lasso"));
  assert(slate::KnownPlayers::knows("https://www.twitch.tv/streamer"));
  assert(slate::KnownPlayers::knows("https://vimeo.com/123456789"));
  assert(slate::KnownPlayers::knows("https://dailymotion.com/video/x12345"));
  assert(slate::KnownPlayers::knows("https://max.com/watch"));
  assert(slate::KnownPlayers::knows("https://hbomax.com/series/"));
  assert(slate::KnownPlayers::knows("https://crunchyroll.com/watch/abc"));
  assert(slate::KnownPlayers::knows("https://app.plex.tv/desktop"));

  // Reject non-streaming sites
  assert(!slate::KnownPlayers::knows("https://google.com/search?q=video"));
  assert(!slate::KnownPlayers::knows("https://github.com/torvalds/linux"));
  assert(!slate::KnownPlayers::knows("https://en.wikipedia.org/wiki/Main_Page"));
  assert(!slate::KnownPlayers::knows("https://amazon.com/dp/B00000000")); // Non-video Amazon page
  assert(!slate::KnownPlayers::knows(""));

  // Verify scripts are properly populated
  std::string isolateOn(slate::kFloatingVideoIsolateOn);
  assert(isolateOn.find("office-floating") != std::string::npos);
  assert(isolateOn.find("data-office-float") != std::string::npos);
  assert(isolateOn.find("__officeFloatObserver") != std::string::npos);
  assert(isolateOn.find("setInterval") == std::string::npos);
  assert(isolateOn.find("body :has([data-office-float])") != std::string::npos);
  assert(isolateOn.find("::-webkit-media-controls") != std::string::npos);

  std::string isolateOff(slate::kFloatingVideoOff);
  assert(isolateOff.find("office-floating") != std::string::npos);
  assert(isolateOff.find("__officeFloatObserver.disconnect()") != std::string::npos);
  assert(isolateOff.find("removeAttribute") != std::string::npos);
  assert(isolateOff.find("exitPictureInPicture") != std::string::npos);

  std::string skipFwd = slate::FloatingVideoSkipScript(15.0);
  assert(skipFwd.find("15.00") != std::string::npos);
  std::string skipBack = slate::FloatingVideoSkipScript(-15.0);
  assert(skipBack.find("-15.00") != std::string::npos);

  std::string seekScript = slate::FloatingVideoSeekScript(0.5);
  assert(seekScript.find("0.5000") != std::string::npos);

  std::cout << "All floating video tests passed!\n";
  return 0;
}
