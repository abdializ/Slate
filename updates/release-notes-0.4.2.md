# Slate 0.4.2

- Fix Hide Sidebar leaving an empty strip down the left side of the window. The page now expands across the freed space, keeping only the normal outer window border.
- Keep window-button clearance in the toolbar instead of reserving it down the full page. Apply the same rule to fullscreen and hidden horizontal tabs.
- Cancel pending sidebar peeks when toggling visibility so an old hover request cannot leave the sidebar partially revealed.
- Add an offscreen native layout regression covering repeated hide/show, narrow windows, icon rails and fullscreen toolbar clearance.

The PiP and updater permission fixes from 0.4.1 are retained. Restart Slate after updating.
