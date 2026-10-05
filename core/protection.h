#pragma once
#include <chrono>
#include <cstdint>
#include <string>
namespace slate {
// Observations, not a guarantee of lossless page restoration. Never persisted.
struct ProtectionSignals {
 uint64_t document_generation=0;
 bool observed=false;
 bool loading=true;
 bool uncertain=true;
 bool form_controls=false;
 bool media_elements=false;
 bool capture=false;
 bool media_permission_requested=false;
 bool download=false;
 bool dialog=false;
 std::chrono::steady_clock::time_point observed_at{};
 bool fresh(std::chrono::steady_clock::time_point now) const {
  return observed && now>=observed_at && now-observed_at<std::chrono::seconds(30);
 }
 bool blocks_discard(std::chrono::steady_clock::time_point now) const {
  return !fresh(now) || loading || uncertain || form_controls || media_elements ||
   capture || media_permission_requested || download || dialog;
 }
 std::string reason(std::chrono::steady_clock::time_point now) const {
  if(capture) return "Camera or microphone in use";
  if(download) return "Download in progress";
  if(dialog) return "Page dialog open";
  if(form_controls) return "Form or editable content";
  if(media_elements) return "Audio or video content";
  if(media_permission_requested) return "Media permission requested";
  if(loading) return "Page loading";
  if(!fresh(now)) return "Awaiting page check";
  if(uncertain) return "Page state uncertain";
  return "No blocker observed";
 }
};
}
