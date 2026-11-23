# Slate 0.4.26

- **Instant Dark & Light Mode Adaptation for All Colored Backgrounds:**
  - Custom accent colors and secondary gradient colors now automatically adapt to a deep, hue-preserving Dark Mode surface (and lift to a clean Light Mode tint) the instant you switch Appearance Mode.
  - Switching between System, Light, and Dark in Settings now updates `NSApp.appearance` immediately so the browser window, Settings window, panels, and all colored backgrounds transition together right away.
