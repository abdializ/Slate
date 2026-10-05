#pragma once
#include <map>
#include <optional>
#include <string>

namespace slate {
// A new/non-playing frame must not dismiss PiP owned by another frame. Once
// WebKit reports native presentation state, it takes precedence over page DOM
// signals (which can lag while an ad player or iframe is replaced).
class PiPState {
 std::optional<bool> native_;
 std::map<std::string,bool> frames_;
public:
 bool active() const {
  if(native_) return *native_;
  for(const auto& [id,active]:frames_) if(active) return true;
  return false;
 }
 bool frame(const std::string& id,bool active) {
  const bool before=this->active(); frames_[id]=active;
  return before!=this->active();
 }
 bool remove_frame(const std::string& id) {
  const bool before=active(); frames_.erase(id); return before!=active();
 }
 void native(bool active) { native_=active; }
 void clear_frames() { frames_.clear(); }
};
}
