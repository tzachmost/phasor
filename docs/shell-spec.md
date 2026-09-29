# Shell 1.0 scope

The Launcher is a dark, compact overlay over a solid-color or configured SwayBG wallpaper. It shows pinned apps first in a grid when the query is empty, then provides ranked app and file results as the user types. Enter launches an application or opens a file; Escape closes the overlay. Hidden directories and removable/mounted filesystems are excluded from the default Home index.

The top Bar shows the active Mango Spaces, a clock, tray icons and a Settings entry point. The optional bottom Dock lists running windows and lets users focus or close them. Both surfaces use independent edge reservations and can run together. Tray menus are provided by the StatusNotifierItem protocol.

Design tokens live centrally in `shell/theme/Tokens.qml`. The visible UI reads the user's dark, light, or system theme, accent, and reduced-motion settings through the core. Components should use tokens for shared colors, spacing, radii, and animation durations. The launcher supports pin/unpin, app info, opening an app's AppStream page, file open, reveal, copy path, share link, duplicate, rename, and move to Trash. Mango Space shortcuts and the core Spaces API remain available alongside the in-launcher Space switcher.

The Settings surface opens with Super+comma or from the Bar. It edits the theme, accent, reduced-motion, wallpaper, and optional Desktop and Dock preferences in the validated settings file. Theme token changes and plug-in lifecycle changes are applied while the shell is running. The notification status control, clipboard history panel, and screenshot action are exposed through Bar slots. A built-in Desktop surface adds Home, Applications, and Settings shortcuts over the wallpaper.
