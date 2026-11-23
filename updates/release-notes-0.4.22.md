# Slate 0.4.22

- **Fix Twitch video pulsing and white-background blinking glitch:**
  - Kept `WKWebView` opaque (`drawsBackground = YES` instead of permanently `NO`) so hardware-accelerated video layers on Twitch never bleed the Light Mode backing layer through as a white flash during re-compositing.
  - Stopped the generic streaming ad defuser's `subtree: true` `MutationObserver` + 10Hz synchronous layout-reflow loop from running on `twitch.tv` (where live chat updates triggered constant reflows while video played).
  - Kept active Twitch backup HLS streams alive across an entire ad break instead of resetting every 20 seconds.
