#pragma once
#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>
namespace slate {
enum class ResourceKind : uint32_t {
 Document=1u<<0, Subdocument=1u<<1, Script=1u<<2, Image=1u<<3, Stylesheet=1u<<4,
 Font=1u<<5, Media=1u<<6, Xhr=1u<<7, Websocket=1u<<8, Ping=1u<<9, Other=1u<<10
};
constexpr uint32_t kAllResourceKinds = 0xFFFFFFFFu;
enum class FilterAction { Allow, Block };
struct FilterRequest {
 std::string url;
 std::string source_url;
 ResourceKind kind=ResourceKind::Other;
};
struct FilterDecision {
 FilterAction action=FilterAction::Allow;
 std::string matched_rule;
};
class FilterEngine {
 public:
  static FilterEngine parse(std::string_view rules);
  FilterDecision classify(const FilterRequest& request) const;
  size_t block_rules() const { return block_count_; }
  size_t exception_rules() const { return exception_count_; }
  size_t skipped_rules() const { return skipped_count_; }
 private:
  struct Rule {
   bool exception=false;
   bool third_party_only=false;
   bool first_party_only=false;
   uint32_t types=kAllResourceKinds;
   std::string host;   // lowercase, empty = generic
   std::string path;   // lowercase pattern after host, may include *
   std::string raw;
   std::vector<std::string> include_domains;
   std::vector<std::string> exclude_domains;
  };
  std::vector<Rule> rules_;
  std::unordered_map<std::string,std::vector<uint32_t>> host_index_;
  std::unordered_map<std::string,std::vector<uint32_t>> token_index_;
  std::vector<uint32_t> generic_;
  size_t block_count_=0, exception_count_=0, skipped_count_=0;
};
}