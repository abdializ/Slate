#include "network_engine.h"
#include <algorithm>
#include <cctype>
#include <sstream>
namespace slate {
namespace {
std::string lower_copy(std::string_view value) {
 std::string out(value);
 std::transform(out.begin(),out.end(),out.begin(),
  [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
 return out;
}
std::string_view trim_view(std::string_view value) {
 size_t begin=0, end=value.size();
 while(begin<end && std::isspace(static_cast<unsigned char>(value[begin]))) ++begin;
 while(end>begin && std::isspace(static_cast<unsigned char>(value[end-1]))) --end;
 return value.substr(begin,end-begin);
}
bool host_matches(std::string_view host, std::string_view pattern) {
 if(pattern.empty()) return true;
 if(host==pattern) return true;
 if(host.size()>pattern.size()+1 && host[host.size()-pattern.size()-1]=='.' &&
    host.ends_with(pattern)) return true;
 return false;
}
std::string site_key(std::string_view host) {
 if(host.empty()) return {};
 size_t dot=host.rfind('.');
 if(dot==std::string_view::npos || dot==0) return std::string(host);
 size_t prev=host.rfind('.',dot-1);
 if(prev==std::string_view::npos) return std::string(host);
 return std::string(host.substr(prev+1));
}
struct UrlParts {
 std::string host;
 std::string path;
 std::string spec;
};
UrlParts parse_url(std::string_view url) {
 UrlParts out;
 out.spec=lower_copy(url);
 const auto scheme=out.spec.find("://");
 std::string rest=scheme==std::string::npos ? out.spec : out.spec.substr(scheme+3);
 const auto slash=rest.find('/');
 const auto hostport=slash==std::string::npos ? rest : rest.substr(0,slash);
 const auto colon=hostport.find(':');
 out.host=colon==std::string::npos ? hostport : hostport.substr(0,colon);
 out.path=slash==std::string::npos ? "/" : rest.substr(slash);
 if(out.path.empty()) out.path="/";
 return out;
}
bool is_separator(char c) {
 return !(std::isalnum(static_cast<unsigned char>(c)) || c=='_' || c=='-' || c=='.' || c=='%');
}
bool path_matches(std::string_view path, std::string_view pattern) {
 if(pattern.empty() || pattern=="^" || pattern=="*") return true;
 std::string_view p=pattern;
 if(!p.empty() && p.front()=='^') p.remove_prefix(1);
 size_t i=0, j=0;
 while(i<=path.size() && j<pattern.size()) {
  if(pattern[j]=='*') {
   ++j;
   if(j==pattern.size()) return true;
   while(i<=path.size()) {
    if(path_matches(path.substr(i), pattern.substr(j))) return true;
    ++i;
   }
   return false;
  }
  if(pattern[j]=='^') {
   if(i==path.size() || is_separator(path[i])) { ++j; if(i<path.size()) ++i; continue; }
   return false;
  }
  if(i==path.size() || path[i]!=pattern[j]) return false;
  ++i; ++j;
 }
 while(j<pattern.size() && (pattern[j]=='*' || pattern[j]=='^')) ++j;
 return j==pattern.size();
}
uint32_t type_bit(std::string_view token) {
 if(token=="script") return static_cast<uint32_t>(ResourceKind::Script);
 if(token=="image") return static_cast<uint32_t>(ResourceKind::Image);
 if(token=="stylesheet") return static_cast<uint32_t>(ResourceKind::Stylesheet);
 if(token=="font") return static_cast<uint32_t>(ResourceKind::Font);
 if(token=="media") return static_cast<uint32_t>(ResourceKind::Media);
 if(token=="xmlhttprequest" || token=="xhr") return static_cast<uint32_t>(ResourceKind::Xhr);
 if(token=="subdocument") return static_cast<uint32_t>(ResourceKind::Subdocument);
 if(token=="websocket") return static_cast<uint32_t>(ResourceKind::Websocket);
 if(token=="ping") return static_cast<uint32_t>(ResourceKind::Ping);
 if(token=="document") return static_cast<uint32_t>(ResourceKind::Document);
 if(token=="other" || token=="object" || token=="object-subrequest")
  return static_cast<uint32_t>(ResourceKind::Other);
 return 0;
}
bool skip_option(std::string_view token) {
 return token=="popup" || token=="elemhide" || token=="generichide" ||
        token=="genericblock" || token=="csp" || token.starts_with("csp=") ||
        token.starts_with("redirect") || token.starts_with("rewrite") ||
        token.starts_with("removeparam") || token=="match-case" ||
        token=="important" || token=="empty" || token=="mp4";
}
std::string longest_token(std::string_view text) {
 std::string best, cur;
 auto flush=[&] {
  if(cur.size()>=4 && cur.size()>best.size()) best=cur;
  cur.clear();
 };
 for(unsigned char c:text) {
  if(std::isalnum(c) || c=='_' || c=='-') cur.push_back(static_cast<char>(std::tolower(c)));
  else flush();
 }
 flush();
 return best;
}
void collect_tokens(std::string_view text, std::vector<std::string>& out) {
 std::string cur;
 auto flush=[&] {
  if(cur.size()>=4) out.push_back(cur);
  cur.clear();
 };
 for(unsigned char c:text) {
  if(std::isalnum(c) || c=='_' || c=='-') cur.push_back(static_cast<char>(std::tolower(c)));
  else flush();
 }
 flush();
}
}

FilterEngine FilterEngine::parse(std::string_view rules) {
 FilterEngine engine;
 std::string text(rules);
 std::istringstream stream(text);
 std::string line;
 while(std::getline(stream,line)) {
  auto raw=trim_view(line);
  if(raw.empty() || raw[0]=='!' || raw[0]=='[' || raw[0]=='#') { ++engine.skipped_count_; continue; }
  if(raw.find("##")!=std::string_view::npos || raw.find("#@#")!=std::string_view::npos ||
     raw.find("#?#")!=std::string_view::npos || raw.find("#$#")!=std::string_view::npos) {
   ++engine.skipped_count_; continue;
  }
  if(raw[0]=='/' && !raw.starts_with("//")) {
   auto filter=raw;
   if(const auto dollar=filter.find('$'); dollar!=std::string_view::npos) filter=filter.substr(0,dollar);
   if(filter.size()>=3 && filter.front()=='/' && filter.back()=='/') {
    bool meta=false;
    for(size_t i=1;i+1<filter.size();++i) {
     const char c=filter[i];
     if(c=='\\' || c=='(' || c==')' || c=='[' || c==']' || c=='{' || c=='}' ||
        c=='|' || c=='^' || c=='.' || c=='+' || c=='?') { meta=true; break; }
    }
    if(meta) { ++engine.skipped_count_; continue; }
   }
  }
  Rule rule;
  if(raw.starts_with("@@")) { rule.exception=true; raw.remove_prefix(2); }
  std::string body(raw);
  std::string options;
  const auto dollar=body.find('$');
  if(dollar!=std::string::npos) { options=body.substr(dollar+1); body=body.substr(0,dollar); }
  bool skip=false;
  uint32_t include_types=0, exclude_types=0;
  if(!options.empty()) {
   std::istringstream opt(options);
   std::string token;
   while(std::getline(opt,token,',')) {
    token=lower_copy(token);
    if(skip_option(token) || token=="document") { skip=true; break; }
    if(token=="third-party") { rule.third_party_only=true; continue; }
    if(token=="~third-party") { rule.first_party_only=true; continue; }
    if(token.starts_with("domain=")) {
     std::istringstream domains(token.substr(7));
     std::string domain;
     while(std::getline(domains,domain,'|')) {
      if(domain.empty()) continue;
      if(domain[0]=='~') rule.exclude_domains.push_back(domain.substr(1));
      else rule.include_domains.push_back(domain);
     }
     continue;
    }
    bool neg=token.starts_with("~");
    auto bit=type_bit(neg ? std::string_view(token).substr(1) : token);
    if(!bit) continue;
    if(neg) exclude_types|=bit; else include_types|=bit;
   }
  }
  if(skip) { ++engine.skipped_count_; continue; }
  if(include_types) rule.types=include_types;
  if(exclude_types) rule.types&=~exclude_types;
  if(!rule.types) { ++engine.skipped_count_; continue; }
  if(body.starts_with("||")) {
   body=body.substr(2);
   const auto cut=body.find_first_of("/^?");
   rule.host=lower_copy(cut==std::string::npos ? body : body.substr(0,cut));
   if(!rule.host.empty() && rule.host.front()=='*' && rule.host.size()>2 && rule.host[1]=='.')
    rule.host=rule.host.substr(2);
   if(cut!=std::string::npos) rule.path=lower_copy(body.substr(cut));
  } else if(body.starts_with("|http://") || body.starts_with("|https://")) {
   auto parts=parse_url(body.substr(1));
   rule.host=parts.host;
   rule.path=parts.path;
  } else {
   rule.path=lower_copy(body);
  }
  if(rule.host.empty() && rule.path.empty()) { ++engine.skipped_count_; continue; }
  rule.raw=std::string(trim_view(line));
  const auto id=static_cast<uint32_t>(engine.rules_.size());
  if(rule.host.empty()) {
   auto token=longest_token(rule.path);
   if(token.empty()) engine.generic_.push_back(id);
   else engine.token_index_[token].push_back(id);
  } else engine.host_index_[rule.host].push_back(id);
  if(rule.exception) ++engine.exception_count_; else ++engine.block_count_;
  engine.rules_.push_back(std::move(rule));
 }
 return engine;
}

FilterDecision FilterEngine::classify(const FilterRequest& request) const {
 const auto url=parse_url(request.url);
 const auto source=parse_url(request.source_url);
 if(url.host.empty()) return {};
 const bool third=source.host.empty() ? true : site_key(url.host)!=site_key(source.host);
 const uint32_t bit=static_cast<uint32_t>(request.kind);
 std::vector<uint32_t> candidates=generic_;
 std::string host=url.host;
 while(true) {
  if(auto it=host_index_.find(host); it!=host_index_.end())
   candidates.insert(candidates.end(),it->second.begin(),it->second.end());
  const auto dot=host.find('.');
  if(dot==std::string::npos) break;
  host=host.substr(dot+1);
 }
 std::vector<std::string> tokens;
 collect_tokens(url.path, tokens);
 collect_tokens(url.host, tokens);
 for(const auto& token:tokens) {
  if(auto it=token_index_.find(token); it!=token_index_.end())
   candidates.insert(candidates.end(),it->second.begin(),it->second.end());
 }
 const FilterDecision* block=nullptr;
 const FilterDecision* allow=nullptr;
 static thread_local FilterDecision block_store, allow_store;
 for(uint32_t id:candidates) {
  const auto& rule=rules_[id];
  if(!(rule.types & bit)) continue;
  if(rule.third_party_only && !third) continue;
  if(rule.first_party_only && third) continue;
  if(!rule.host.empty() && !host_matches(url.host,rule.host)) continue;
  if(!path_matches(url.path, rule.path) && !path_matches(url.spec, rule.path)) {
   if(!(rule.host.empty() && url.path.find(rule.path)!=std::string::npos)) continue;
  }
  if(!rule.include_domains.empty()) {
   bool ok=false;
   for(const auto& domain:rule.include_domains) if(host_matches(source.host,domain)) { ok=true; break; }
   if(!ok) continue;
  }
  bool excluded=false;
  for(const auto& domain:rule.exclude_domains) if(host_matches(source.host,domain)) { excluded=true; break; }
  if(excluded) continue;
  if(rule.exception) {
   allow_store={FilterAction::Allow, rule.raw};
   allow=&allow_store;
  } else {
   block_store={FilterAction::Block, rule.raw};
   block=&block_store;
  }
 }
 if(allow) return *allow;
 if(block) return *block;
 return {};
}
}