#include "navigation.h"
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <string>
namespace slate {
namespace {
std::string trim(std::string_view raw) {
 size_t begin=0, end=raw.size();
 while(begin<end && std::isspace(static_cast<unsigned char>(raw[begin]))) ++begin;
 while(end>begin && std::isspace(static_cast<unsigned char>(raw[end-1]))) --end;
 return std::string(raw.substr(begin,end-begin));
}
std::string lower(std::string value) {
 std::transform(value.begin(),value.end(),value.begin(),
  [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
 return value;
}
std::string percent_encode(std::string_view value) {
 std::string out;
 out.reserve(value.size()*3);
 for(unsigned char c:value) {
  if(std::isalnum(c) || c=='-' || c=='_' || c=='.' || c=='~') out.push_back(static_cast<char>(c));
  else {
   char buf[4];
   std::snprintf(buf,sizeof(buf),"%%%02X",c);
   out.append(buf,3);
  }
 }
 return out;
}
bool has_space(std::string_view value) {
 return std::any_of(value.begin(),value.end(),
  [](unsigned char c) { return std::isspace(c); });
}
bool looks_like_ipv4(std::string_view host) {
 int parts=0, digits=0, value=0;
 for(size_t i=0;i<=host.size();++i) {
  if(i==host.size() || host[i]=='.') {
   if(digits==0 || value>255) return false;
   ++parts; digits=0; value=0;
  } else if(std::isdigit(static_cast<unsigned char>(host[i]))) {
   value=value*10+(host[i]-'0'); ++digits;
   if(digits>3) return false;
  } else return false;
 }
 return parts==4;
}
bool looks_like_host(std::string_view host) {
 if(host.empty() || host.size()>253) return false;
 if(lower(std::string(host))=="localhost") return true;
 if(looks_like_ipv4(host)) return true;
 if(host.find('.')==std::string_view::npos) return false;
 if(host.front()=='.' || host.back()=='.') return false;
 bool label=false, letter=false;
 for(unsigned char c:host) {
  if(std::isalnum(c)) { label=true; if(std::isalpha(c)) letter=true; }
  else if(c=='-' || c=='.') { if(!label && c=='.') return false; if(c=='.') label=false; }
  else return false;
 }
 return label && letter;
}
std::string google_search(std::string_view query) {
 return "https://www.google.com/search?q="+percent_encode(query);
}
NavigationDecision ok(InputKind kind, std::string url) { return {kind,std::move(url)}; }
}
NavigationDecision resolve_address_bar(std::string_view raw) {
 const std::string text=trim(raw);
 if(text.empty()) return {};
 const std::string lowered=lower(text);
 if(text=="about:blank") return ok(InputKind::Url,text);
 if(lowered.starts_with("javascript:") || lowered.starts_with("data:") ||
    lowered.starts_with("file:") || lowered.starts_with("vbscript:") ||
    lowered.starts_with("blob:") || lowered.starts_with("about:"))
  return {};
 if(lowered.starts_with("https://") || lowered.starts_with("http://")) {
  const auto scheme_end=text.find("://");
  const auto rest=text.substr(scheme_end+3);
  const auto host=rest.substr(0,rest.find_first_of("/?#:"));
  if(host.empty()) return {};
  return ok(InputKind::Url,text);
 }
 if(has_space(text)) return ok(InputKind::Search,google_search(text));
 std::string host=text;
 std::string suffix;
 const auto cut=text.find_first_of("/?#:");
 if(cut!=std::string::npos) {
  host=text.substr(0,cut);
  suffix=text.substr(cut);
 }
 if(looks_like_host(host) || lower(host)=="localhost") {
  const bool local=lower(host)=="localhost" || looks_like_ipv4(host);
  return ok(InputKind::Url,(local?"http://":"https://")+text);
 }
 return ok(InputKind::Search,google_search(text));
}
}
