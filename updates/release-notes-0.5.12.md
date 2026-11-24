# Slate 0.5.12

## Fixes
- Fixed YouTube video flickering by disabling WebKit's `_setLowPowerVideoAudioBufferSizeEnabled` (restoring full-size hardware decode buffers for MSE/60fps/HDR YouTube streams).
- Stopped the stream ad defuser from observing `style` attribute ticks or redundantly mutating `<video>` attributes on YouTube, and narrowed YouTube ad detection strictly to active player `.ad-showing` states.
- Added explicit `shadowPath` to split-pane card shadows so CoreAnimation does not re-rasterize offscreen shadows behind hardware-decoded video surfaces.
