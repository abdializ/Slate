#pragma once
#include <string>
#include <vector>
#include <optional>
#include <cstdint>

namespace slate {

struct Credential {
  std::string id;
  std::string origin;     // e.g. "https://github.com" or "github.com"
  std::string username;
  std::string password;
  int64_t created_at = 0;
  int64_t last_used_at = 0;
};

class CredentialStore {
 public:
  explicit CredentialStore(std::vector<Credential> items = {});

  const std::vector<Credential>& items() const { return items_; }

  // Exact scheme/host/port match; bare imported domains mean HTTPS.
  std::vector<Credential> find_for_origin(const std::string& origin) const;
  std::optional<Credential> find_by_id(const std::string& id) const;

  // Adds new credential or updates existing one if (origin, username) matches
  std::string save(Credential cred);

  // Removes credential by ID
  bool remove(const std::string& id);

  // Search by domain/origin or username
  std::vector<Credential> search(const std::string& query) const;

  void clear();

 private:
  std::vector<Credential> items_;
  uint64_t next_id_ = 1;
};

} // namespace slate
