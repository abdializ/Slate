#pragma once
#include "filtering/network_engine.h"
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>
namespace slate {
enum class ShieldMode { Standard, Strict, Off };
struct ShieldPageStats {
 uint64_t blocked=0;
 std::string last_rule;
};
class ShieldController {
 public:
  static ShieldController from_list_files(const std::vector<std::string>& paths);
  static ShieldController from_rules(std::string_view rules);
  FilterDecision classify(const FilterRequest& request) const;
  void set_mode(ShieldMode mode);
  ShieldMode mode() const;
  void pause_site(std::string_view host);
  void resume_site(std::string_view host);
  bool site_paused(std::string_view host) const;
  void note_block(std::string_view page_host, std::string_view rule);
  void reset_page(std::string_view page_host);
  ShieldPageStats page_stats(std::string_view page_host) const;
  size_t block_rules() const;
  size_t exception_rules() const;
 private:
  std::shared_ptr<const FilterEngine> engine_;
  mutable std::unique_ptr<std::mutex> mutex_=std::make_unique<std::mutex>();
  ShieldMode mode_=ShieldMode::Standard;
  std::unordered_set<std::string> paused_;
  std::unordered_map<std::string,ShieldPageStats> pages_;
};
std::string host_from_url(std::string_view url);
}