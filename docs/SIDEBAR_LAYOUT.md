# Fully hiding the sidebar

The sidebar already collapsed to zero width, but `layoutTrafficLights` activated
a separate required constraint on the entire browser plate. That constraint
reserved the native window buttons' width down the whole window, overriding the
plate's ordinary sidebar-edge constraint and producing an empty left-hand strip.

`SlateApplyWindowControlClearance` retains the measured window-button clearance
for a revealed narrow rail, leaves the full-height constraint inactive, and adds
clearance only to the toolbar's navigation row when both tab layouts are hidden.
The ordinary 8-point plate inset remains (5 points in fullscreen). Showing the
sidebar restores its stored width and normal toolbar spacing. Window controls
remain visible and usable without reserving an empty column below them.

The toggle also cancels pending peek requests and clears transient peek state.
A delayed hover callback cannot reveal a sidebar after the layout has switched
away from collapsed vertical tabs. Deliberate edge-hover reveal is retained.

`sidebar_hide_geometry` uses the production clearance function in an offscreen
AppKit window with native traffic-light measurements and real layout constraints.
It first reproduces the old gutter, then verifies full page width after hiding,
restoration after showing, icon-rail widths, repeated toggles, 1200/780/480-point
windows, fullscreen insets and toolbar-button clearance. It does not activate or
resize the user's running browser.

When both tab layouts are hidden, the native titlebar buttons would still sit
above the toolbar row. The existing content-hosted AppKit button cluster now
serves this layout as well as fullscreen. Its center follows the navigation
cluster's actual laid-out center, and its measured right edge sets toolbar-only
clearance. Titlebar-owned buttons stay in their original hierarchy and are
hidden only while their toolbar counterparts are in use. Showing tabs restores
them. Minimize is enabled in a normal window and disabled in fullscreen.

The native regression also reproduces the previous vertical mismatch, checks
actual click hit-testing for all three AppKit-created controls, verifies window
action targets and minimize state, and repeats the hidden/shown transitions.
