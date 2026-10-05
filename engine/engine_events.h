#pragma once
#include "core/protection.h"
#include "core/shields.h"
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace slate {

struct EngineEvents {
  std::function<void(ProtectionSignals)> protection_changed;
  std::function<void(std::string)> address_changed;
  std::function<void(std::string)> title_changed;
  std::function<void(std::string)> favicon_changed; // PNG bytes from the page icon.
  std::function<void(std::string)> theme_color_changed; // "#rrggbb" or empty.
  std::function<void(std::string, std::string)> resource_blocked; // rule, url
  std::function<void(bool, bool)> navigation_changed;
  std::function<void(bool, bool, bool, bool, std::string)> media_ui_changed; // audible, video_playing, has_video, user_started, primary frame
  std::function<void(int width, int height, std::string quality, bool hdr)> media_quality_changed;
  std::function<void(bool)> pip_changed; // native picture-in-picture active state changed
  std::function<void(bool, double)> loading_changed; // loading, progress 0..1
  std::function<void()> close_ready;
  std::function<void()> close_cancelled;
  // Synchronously return a tab-owned WKWebView using WebKit's supplied configuration.
  std::function<void*(void*, std::string)> create_popup_tab;
  std::function<void()> popup_close_requested;
  std::function<void(std::function<void(bool)>)> confirm_leave;
  std::function<void()> closed;
  std::function<std::vector<std::pair<std::string, std::string>>(std::string)> credential_autofill_query;
  std::function<void(std::string, std::string, std::string)> credential_save_requested;
  std::function<void()> sign_in_found;
  std::function<void(std::string origin, std::string user, std::string pass)> sign_in_submitted;
  std::function<void(bool navigated)> sign_in_settled;
  std::function<void(bool typing, double x, double y, double w, double h, bool has_rect)> focus_changed;
  std::function<void(bool on)> fullscreen_changed;
};

} // namespace slate
