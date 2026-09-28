# Shell v0.1

The UI is a dark, compact, floating launcher presented as an overlay over a solid-color or configured SwayBG wallpaper. The first plugin shows pinned apps first in a grid when the query is empty, then provides ranked app and file results as the user types. Enter launches an application or opens a file; Escape closes the overlay. Hidden directories and removable/mounted filesystems are excluded from the default Home index.

The launcher is deliberately the first UI reference plugin. No dock, bar, tray, custom notification center, AI features, or lock screen is required for the first milestone. Plugin categories and region negotiation are designed to support these later without making them core-owned.

Design tokens live centrally in `shell/theme/Tokens.qml`. The v0.1 palette and transition durations are fixed defaults; user-selected theme and reduced-motion settings are not yet connected to the visible UI. Components should use tokens for shared colors, spacing, radii, and animation durations. The launcher supports pin/unpin, app info, opening an app's AppStream page, file open, reveal, and copy path. File rename/delete/share/copy and an in-shell Space switcher remain later work; Mango Space shortcuts and the core Spaces API are available now.
