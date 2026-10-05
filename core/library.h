#pragma once
#include <string>
#include <vector>
namespace slate {
struct Bookmark {
 std::string id;
 std::string title;
 std::string url;
};
class BookmarkList {
 public:
 explicit BookmarkList(std::vector<Bookmark> restored={});
 const std::vector<Bookmark>& items() const { return items_; }
 std::string add(std::string url, std::string title);
 bool remove(const std::string& id);
 const Bookmark* find(const std::string& id) const;
 const Bookmark* find_url(const std::string& url) const;
 private:
 Bookmark* mutable_url(const std::string& url);
 std::vector<Bookmark> items_;
 unsigned long long next_id_=1;
};
}
