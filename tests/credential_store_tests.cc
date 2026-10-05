#include "core/credential_store.h"
#include <cassert>
#include <iostream>

int main() {
  using namespace slate;

  CredentialStore store;
  assert(store.items().empty());

  // 1. Save new credential
  std::string id1 = store.save({
    .origin = "https://github.com/login",
    .username = "octocat",
    .password = "secret123"
  });
  assert(!id1.empty());
  assert(store.items().size() == 1);

  // 2. Find for origin
  auto found = store.find_for_origin("https://github.com");
  assert(found.size() == 1);
  assert(found[0].username == "octocat");
  assert(found[0].password == "secret123");

  // Never silently share a password with another host.
  auto subFound = store.find_for_origin("https://api.github.com");
  assert(subFound.empty());
  assert(store.find_for_origin("http://github.com").empty());
  assert(store.find_for_origin("https://github.com:8443").empty());
  assert(store.find_for_origin("https://github.com:443").size()==1);
  assert(store.find_for_origin("https://www.github.com").empty());
  assert(store.find_for_origin("https://github.com@evil.test").empty());
  assert(store.find_for_origin("https://evilgithub.com").empty());
  assert(store.find_for_origin("").empty());

  // 3. Update credential (same origin & username)
  std::string idUpdated = store.save({
    .origin = "github.com",
    .username = "octocat",
    .password = "newSecret456"
  });
  assert(idUpdated == id1);
  assert(store.items().size() == 1);
  assert(store.find_for_origin("github.com")[0].password == "newSecret456");

  // 4. Save second credential for different domain
  std::string id2 = store.save({
    .origin = "https://courses.example.test",
    .username = "student01",
    .password = "canvasPass!"
  });
  assert(store.items().size() == 2);

  // 5. Search
  assert(store.search("courses").size() == 1);
  assert(store.search("octo").size() == 1);
  assert(store.search("nonexistent").empty());

  // 6. Remove
  assert(store.remove(id1));
  assert(store.items().size() == 1);
  assert(store.find_for_origin("github.com").empty());
  assert(!store.remove("nonexistent_id"));

  std::cout << "All credential_store tests passed!" << std::endl;
  return 0;
}
