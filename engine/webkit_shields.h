#pragma once
#import <WebKit/WebKit.h>
#include <mutex>
#include <string>
#include <vector>

namespace slate {

class WebKitShields {
 public:
  static WebKitShields& Shared();

  // Load and compile rules (or retrieve cached compiled rules)
  void Initialize(const std::vector<std::string>& rule_file_paths);

  // Attach compiled content rules and scripts to a WKUserContentController
  void ApplyToUserContentController(WKUserContentController* controller, bool incognito = false);

  // Toggle shields mode
  void InjectStreamingProtection(WKWebView* webView) const;
  void SetEnabled(bool enabled);
  bool IsEnabled() const { return enabled_; }
  bool HasCompiledRules() const { return rule_list_ != nil; }
  size_t CompiledRuleCount() const { return compiled_rule_count_; }
  void SetSiteEnabled(const std::string& host, bool enabled);
  bool IsSiteEnabled(const std::string& host) const;
  std::vector<std::string> DisabledSites() const;
  void UpdateControllerForURL(WKUserContentController* controller, NSURL* url);
  bool IsAdOrTrackerHost(NSString* host) const;

 private:
  WebKitShields();
  ~WebKitShields() = default;

  void CompileRules(const std::vector<std::string>& rule_file_paths);
  void BroadcastRuleList();

  bool enabled_ = true;
  std::mutex mutex_;
  WKContentRuleListStore* __strong store_ = nil;
  WKContentRuleList* __strong rule_list_ = nil;
  size_t compiled_rule_count_ = 0;
  NSString* __strong rule_identifier_ = nil;
  NSHashTable* __strong registered_controllers_ = nil;
  NSMapTable* __strong controller_hosts_ = nil;
  NSMutableSet<NSString*>* __strong disabled_sites_ = nil;
  WKUserScript* __strong stealth_script_ = nil;
};

} // namespace slate
