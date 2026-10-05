#include "shields.h"
#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
namespace slate {
namespace {
std::string lower_host(std::string_view value) {
 std::string out(value);
 std::transform(out.begin(),out.end(),out.begin(),
  [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
 return out;
}
std::string policy_host(std::string_view value) {
 auto host=lower_host(value);
 if(host.rfind("www.",0)==0) host.erase(0,4);
 return host;
}
}
std::string host_from_url(std::string_view url) {
 const auto scheme=url.find("://");
 std::string_view rest=scheme==std::string_view::npos ? url : url.substr(scheme+3);
 const auto slash=rest.find('/');
 std::string_view hostport=slash==std::string_view::npos ? rest : rest.substr(0,slash);
 const auto colon=hostport.find(':');
 return lower_host(colon==std::string_view::npos ? hostport : hostport.substr(0,colon));
}
ShieldController ShieldController::from_rules(std::string_view rules) {
 ShieldController controller;
 controller.engine_=std::make_shared<FilterEngine>(FilterEngine::parse(rules));
 return controller;
}
ShieldController ShieldController::from_list_files(const std::vector<std::string>& paths) {
 std::ostringstream joined;
 for(const auto& path:paths) {
  std::ifstream in(path);
  if(!in) continue;
  joined << in.rdbuf() << '\n';
 }
 return from_rules(joined.str());
}
FilterDecision ShieldController::classify(const FilterRequest& request) const {
 if(request.kind==ResourceKind::Document) return {};
 const auto page=host_from_url(request.source_url.empty() ? request.url : request.source_url);
 std::shared_ptr<const FilterEngine> engine;
 {
  std::lock_guard lock(*mutex_);
  if(mode_==ShieldMode::Off || !engine_) return {};
  if(paused_.contains(policy_host(page))) return {};
  engine=engine_;
 }
 return engine->classify(request);
}
void ShieldController::set_mode(ShieldMode mode) {
 std::lock_guard lock(*mutex_);
 mode_=mode;
}
ShieldMode ShieldController::mode() const {
 std::lock_guard lock(*mutex_);
 return mode_;
}
void ShieldController::pause_site(std::string_view host) {
 std::lock_guard lock(*mutex_);
 paused_.insert(policy_host(host));
}
void ShieldController::resume_site(std::string_view host) {
 std::lock_guard lock(*mutex_);
 paused_.erase(policy_host(host));
}
bool ShieldController::site_paused(std::string_view host) const {
 std::lock_guard lock(*mutex_);
 return paused_.contains(policy_host(host));
}
void ShieldController::note_block(std::string_view page_host, std::string_view rule) {
 std::lock_guard lock(*mutex_);
 if(mode_==ShieldMode::Off || paused_.contains(policy_host(page_host))) return;
 auto& stats=pages_[lower_host(page_host)];
 stats.blocked+=1;
 stats.last_rule=std::string(rule);
}
void ShieldController::reset_page(std::string_view page_host) {
 std::lock_guard lock(*mutex_);
 pages_.erase(lower_host(page_host));
}
ShieldPageStats ShieldController::page_stats(std::string_view page_host) const {
 std::lock_guard lock(*mutex_);
 if(auto it=pages_.find(lower_host(page_host)); it!=pages_.end()) return it->second;
 return {};
}
size_t ShieldController::block_rules() const {
 return engine_ ? engine_->block_rules() : 0;
}
size_t ShieldController::exception_rules() const {
 return engine_ ? engine_->exception_rules() : 0;
}
}
