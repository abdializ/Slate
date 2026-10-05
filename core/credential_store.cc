#include "core/credential_store.h"
#include <algorithm>
#include <chrono>

namespace slate {

namespace {

std::string normalize_host(const std::string& input) {
  if(input.empty() || input.find_first_of(" \t\r\n\\")!=std::string::npos) return {};
  std::string s=input;
  std::transform(s.begin(),s.end(),s.begin(),[](unsigned char c){return std::tolower(c);});
  std::string scheme="https";
  const auto protocol=s.find("://");
  if(protocol!=std::string::npos) { scheme=s.substr(0,protocol); s=s.substr(protocol+3); }
  if(scheme!="https" && scheme!="http") return {};
  s=s.substr(0,s.find_first_of("/?#"));
  if(s.empty() || s.find('@')!=std::string::npos) return {};
  const std::string defaultPort=scheme=="https" ? ":443" : ":80";
  if(s.ends_with(defaultPort)) s.resize(s.size()-defaultPort.size());
  return scheme+"://"+s;
}

int64_t current_timestamp() {
  return std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

} // namespace

CredentialStore::CredentialStore(std::vector<Credential> items)
    : items_(std::move(items)) {
  for (const auto& item : items_) {
    try {
      uint64_t val = std::stoull(item.id);
      if (val >= next_id_) next_id_ = val + 1;
    } catch (...) {}
  }
}

std::vector<Credential> CredentialStore::find_for_origin(const std::string& origin) const {
  std::string norm = normalize_host(origin);
  std::vector<Credential> results;
  for (const auto& item : items_) {
    std::string item_norm = normalize_host(item.origin);
    if (!norm.empty() && item_norm == norm) {
      results.push_back(item);
    }
  }
  return results;
}

std::optional<Credential> CredentialStore::find_by_id(const std::string& id) const {
  for (const auto& item : items_) {
    if (item.id == id) return item;
  }
  return std::nullopt;
}

std::string CredentialStore::save(Credential cred) {
  std::string norm = normalize_host(cred.origin);
  int64_t now = current_timestamp();

  for (auto& item : items_) {
    if (normalize_host(item.origin) == norm && item.username == cred.username) {
      item.password = cred.password;
      item.last_used_at = now;
      return item.id;
    }
  }

  if (cred.id.empty()) {
    cred.id = std::to_string(next_id_++);
  }
  if (cred.created_at == 0) cred.created_at = now;
  cred.last_used_at = now;
  std::string id = cred.id;
  items_.push_back(std::move(cred));
  return id;
}

bool CredentialStore::remove(const std::string& id) {
  auto it = std::remove_if(items_.begin(), items_.end(), [&](const Credential& c) {
    return c.id == id;
  });
  if (it != items_.end()) {
    items_.erase(it, items_.end());
    return true;
  }
  return false;
}

std::vector<Credential> CredentialStore::search(const std::string& query) const {
  if (query.empty()) return items_;
  std::string q = query;
  std::transform(q.begin(), q.end(), q.begin(), [](unsigned char c) { return std::tolower(c); });

  std::vector<Credential> results;
  for (const auto& item : items_) {
    std::string o = item.origin;
    std::string u = item.username;
    std::transform(o.begin(), o.end(), o.begin(), [](unsigned char c) { return std::tolower(c); });
    std::transform(u.begin(), u.end(), u.begin(), [](unsigned char c) { return std::tolower(c); });

    if (o.find(q) != std::string::npos || u.find(q) != std::string::npos) {
      results.push_back(item);
    }
  }
  return results;
}

void CredentialStore::clear() {
  items_.clear();
}

} // namespace slate
