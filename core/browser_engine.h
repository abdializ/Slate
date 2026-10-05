#pragma once
#include <cstdint>
#include <string>
namespace slate {
using TabId = uint64_t;
// UI-thread interface. CEF types must never cross this boundary.
class BrowserEngine {
 public:
  virtual ~BrowserEngine() = default;
  virtual void navigate(const std::string& url) = 0;
  virtual void back() = 0;
  virtual void forward() = 0;
  virtual void reload() = 0;
  virtual void reload_ignore_cache() = 0;
  virtual void focus() = 0; // Give keyboard focus to this tab’s document.
  virtual void blur() = 0;
  virtual void execute_script(const std::string& source) = 0;
  virtual void inspect_protection() = 0; // Async; unknown until a fresh response.
  virtual void host_geometry_changed() = 0; // Screen metrics after native layout/resize.
  virtual void set_zoom(double level) = 0;
  virtual void set_high_refresh_rate(bool fast) { (void)fast; }
  virtual void set_occluded(bool occluded) { (void)occluded; } // Drop compositor tiles; keep the renderer.
  virtual void trim_memory() {} // Re-release GPU tiles under pressure; does not unload.
  virtual void stop() {}
  virtual void fill_credentials(const std::string& username, const std::string& password) { (void)username; (void)password; }
  virtual void close() = 0; // Asynchronous; implementation owns close handshake.
};
}
