#include "library.h"
#include <algorithm>
#include <stdexcept>
namespace slate {
namespace {
bool http_url(const std::string& url) {
 return url.rfind("https://",0)==0 || url.rfind("http://",0)==0;
}
}
BookmarkList::BookmarkList(std::vector<Bookmark> restored) : items_(std::move(restored)) {
 if(items_.size()>200) throw std::runtime_error("Too many bookmarks");
 std::vector<std::string> ids;
 for(auto& item:items_) {
  if(item.id.empty() || item.title.size()>4096 || item.url.size()>8192 || !http_url(item.url))
   throw std::runtime_error("Invalid bookmark");
  if(std::find(ids.begin(),ids.end(),item.id)!=ids.end()) throw std::runtime_error("Duplicate bookmark");
  ids.push_back(item.id);
  try { next_id_=std::max(next_id_,std::stoull(item.id)+1); } catch(...) {}
 }
}
const Bookmark* BookmarkList::find(const std::string& id) const {
 for(const auto& item:items_) if(item.id==id) return &item;
 return nullptr;
}
const Bookmark* BookmarkList::find_url(const std::string& url) const {
 for(const auto& item:items_) if(item.url==url) return &item;
 return nullptr;
}
Bookmark* BookmarkList::mutable_url(const std::string& url) {
 return const_cast<Bookmark*>(find_url(url));
}
std::string BookmarkList::add(std::string url, std::string title) {
 if(!http_url(url) || url.size()>8192) throw std::runtime_error("Invalid bookmark URL");
 if(title.size()>4096) title.resize(4096);
 if(title.empty()) title=url;
 if(auto* existing=mutable_url(url)) {
  existing->title=std::move(title);
  return existing->id;
 }
 if(items_.size()>=200) throw std::runtime_error("Bookmark limit reached");
 Bookmark item{std::to_string(next_id_++),std::move(title),std::move(url)};
 items_.push_back(item);
 return item.id;
}
bool BookmarkList::remove(const std::string& id) {
 const auto it=std::find_if(items_.begin(),items_.end(),[&](const Bookmark& item){ return item.id==id; });
 if(it==items_.end()) return false;
 items_.erase(it);
 return true;
}
}
