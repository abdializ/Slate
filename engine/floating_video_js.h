#pragma once
#include <string>
#include <string_view>
#include <vector>

namespace slate {

// JavaScript for Floating Video (Picture-in-Picture)
//
// Injects CSS to isolate the playing video, hiding all other DOM elements
// while keeping the page live and responsive.
// Defends the element mark across dynamic player rebuilds (ad breaks, quality switches, React re-renders).

inline constexpr char kFloatingVideoIsolateOn[] = R"JS(
(function () {
  var videos = document.querySelectorAll('video');
  var best = null, area = 0;
  for (var i = 0; i < videos.length; i++) {
    var v = videos[i];
    if (v.paused || v.ended || v.readyState < 2) continue;
    var box = v.getBoundingClientRect();
    if (box.width < 160 || box.height < 90 ||
        v.closest('[class*="video-ad"], [id*="player-ads"], [data-ad]')) continue;
    if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
  }
  if (!best && videos.length > 0) {
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      if (v.closest && v.closest('[class*="video-ad"], [id*="player-ads"], [data-ad]')) continue;
      var box = v.getBoundingClientRect();
      if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
    }
    if (!best) best = videos[0];
  }
  if (!best) return 'none';

  best.setAttribute('data-office-float', '');
  var sheet = document.getElementById('office-float');
  if (!sheet) {
    sheet = document.createElement('style');
    sheet.id = 'office-float';
    (document.head || document.documentElement).appendChild(sheet);
  }
  sheet.textContent = [
    'html.office-floating, html.office-floating body {',
    'background:#000 !important; overflow:hidden !important; margin:0 !important}',
    'html.office-floating body > * { visibility:hidden !important }',
    'html.office-floating [data-office-float] {',
    'visibility:visible !important; position:fixed !important;',
    'left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;',
    'width:100vw !important; height:100vh !important;',
    'max-width:none !important; max-height:none !important;',
    'object-fit:contain !important; z-index:2147483647 !important}',
    'html.office-floating body :has([data-office-float]) {',
    'overflow:visible !important}',
    'html.office-floating [data-office-float]::-webkit-media-controls {',
    'display:none !important}'
  ].join('');
  document.documentElement.classList.add('office-floating');

  // The mark has to be defended.
  // Everything but the marked element is hidden, so the moment a player
  // rebuilds its DOM — and they all do, on a quality change, an ad break,
  // a React re-render — the mark goes with the old element and the window
  // turns pure black while still holding a perfectly live page.
  // So the mark is put back on whatever is playing now.
  if (window.__officeFloatObserver) window.__officeFloatObserver.disconnect();
  if (window.__officeFloatPlayHandler)
    document.removeEventListener('play', window.__officeFloatPlayHandler, true);
  function reattach() {
    if (document.querySelector('video[data-office-float]')) return;
    var candidates = document.querySelectorAll('video');
    var next = null, largest = 0;
    for (var j = 0; j < candidates.length; j++) {
      var one = candidates[j];
      if (one.ended) continue;
      var box = one.getBoundingClientRect();
      if (one.closest && one.closest('[class*="video-ad"], [id*="player-ads"], [data-ad]')) continue;
      if (!one.paused && one.readyState >= 2) {
        if (box.width * box.height >= largest) { largest = box.width * box.height; next = one; }
      } else if (!next && box.width * box.height >= largest) {
        largest = box.width * box.height; next = one;
      }
    }
    if (!next && candidates.length > 0) next = candidates[0];
    if (next) next.setAttribute('data-office-float', '');
  }
  window.__officeFloatPlayHandler = reattach;
  document.addEventListener('play', reattach, true);
  window.__officeFloatObserver = new MutationObserver(reattach);
  window.__officeFloatObserver.observe(document.body || document.documentElement,
    {childList:true, subtree:true});

  return 'floating';
})();
)JS";

inline constexpr char kFloatingVideoWhere[] = R"JS(
(function () {
  var video = document.querySelector('[data-office-float]')
    || document.querySelector('video');
  if (!video || !video.duration || !isFinite(video.duration)) return [0, true];
  return [video.currentTime / video.duration, !video.paused];
})();
)JS";

inline constexpr char kFloatingVideoToggle[] = R"JS(
(function () {
  var video = document.querySelector('[data-office-float]')
    || document.querySelector('video');
  if (!video) return true;
  if (video.paused) { video.play(); } else { video.pause(); }
  return !video.paused;
})();
)JS";

inline constexpr char kFloatingVideoOff[] = R"JS(
(function () {
  try {
    var out = document.querySelector('video[data-office-float]')
      || document.querySelector('video');
    if (out) {
      if (out.webkitPresentationMode === 'picture-in-picture') {
        out.webkitSetPresentationMode('inline');
      }
      if (document.pictureInPictureElement && document.exitPictureInPicture) {
        document.exitPictureInPicture();
      }
    }
  } catch (e) {}

  if (window.__officeFloatObserver) window.__officeFloatObserver.disconnect();
  window.__officeFloatObserver = null;
  if (window.__officeFloatPlayHandler)
    document.removeEventListener('play', window.__officeFloatPlayHandler, true);
  window.__officeFloatPlayHandler = null;
  document.documentElement.classList.remove('office-floating');
  var sheet = document.getElementById('office-float');
  if (sheet) sheet.textContent = '';
  var video = document.querySelector('[data-office-float]');
  if (video) video.removeAttribute('data-office-float');
  return 'landed';
})();
)JS";

inline std::string FloatingVideoSkipScript(double seconds) {
  char buf[512];
  snprintf(buf, sizeof(buf),
    "(function () {"
    "  var video = document.querySelector('[data-office-float]') || document.querySelector('video');"
    "  if (!video) return false;"
    "  video.currentTime = Math.max(0, video.currentTime + (%.2f));"
    "  return true;"
    "})();", seconds);
  return std::string(buf);
}

inline std::string FloatingVideoSeekScript(double ratio) {
  char buf[512];
  snprintf(buf, sizeof(buf),
    "(function () {"
    "  var video = document.querySelector('[data-office-float]') || document.querySelector('video');"
    "  if (!video || !video.duration || !isFinite(video.duration)) return false;"
    "  video.currentTime = Math.max(0, Math.min(video.duration, video.duration * (%.4f)));"
    "  return true;"
    "})();", ratio);
  return std::string(buf);
}

// Known media streaming sites where auto-floating or PiP is primary intent
class KnownPlayers {
public:
  struct Entry {
    std::string_view host;
    std::string_view path; // empty if any path
  };

  static bool knows(std::string_view url_str) {
    if (url_str.empty()) return false;
    // Extract host and path
    size_t scheme_pos = url_str.find("://");
    if (scheme_pos == std::string_view::npos) return false;
    size_t host_start = scheme_pos + 3;
    size_t host_end = url_str.find('/', host_start);
    std::string_view host = (host_end == std::string_view::npos)
      ? url_str.substr(host_start)
      : url_str.substr(host_start, host_end - host_start);
    std::string_view path = (host_end == std::string_view::npos)
      ? "/"
      : url_str.substr(host_end);

    // Strip port if present
    size_t port_pos = host.find(':');
    if (port_pos != std::string_view::npos) host = host.substr(0, port_pos);

    static const Entry kKnown[] = {
      {"youtube.com", ""}, {"youtu.be", ""}, {"netflix.com", ""},
      {"primevideo.com", ""}, {"amazon.com", "/gp/video"}, {"amazon.co.uk", "/gp/video"},
      {"amazon.de", "/gp/video"}, {"amazon.fr", "/gp/video"},
      {"disneyplus.com", ""}, {"tv.apple.com", ""}, {"twitch.tv", ""},
      {"vimeo.com", ""}, {"dailymotion.com", ""}, {"max.com", ""}, {"hbomax.com", ""},
      {"canalplus.com", ""}, {"mycanal.fr", ""}, {"arte.tv", ""}, {"france.tv", ""},
      {"tf1.fr", ""}, {"6play.fr", ""}, {"crunchyroll.com", ""}, {"plex.tv", ""},
      {"peacocktv.com", ""}, {"hulu.com", ""}, {"paramountplus.com", ""},
      {"molotov.tv", ""}, {"ocs.fr", ""}, {"mubi.com", ""}, {"criterionchannel.com", ""},
      {"ted.com", ""}, {"nebula.tv", ""}, {"curiositystream.com", ""}
    };

    for (const auto& entry : kKnown) {
      if (host == entry.host || (host.size() > entry.host.size() &&
          host.ends_with(entry.host) &&
          host[host.size() - entry.host.size() - 1] == '.')) {
        if (entry.path.empty()) return true;
        if (path.starts_with(entry.path)) return true;
      }
    }
    return false;
  }
};

} // namespace slate
