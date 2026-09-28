# Shell v0.1

The UI is a dark, compact, floating launcher presented as an overlay. The first plugin searches installed applications and indexed files. Enter launches an application or opens a file; Escape closes the overlay. Hidden directories and removable/mounted filesystems are excluded from the default Home index.

The launcher is deliberately the first UI reference plugin. No dock, bar, tray, custom notification center, AI features, or lock screen is required for the first milestone. Plugin categories and region negotiation are designed to support these later without making them core-owned.

Design tokens live centrally in `shell/theme/tokens.qml`. Animation defaults are quick, ease-out, and disabled when reduced motion is requested. Components must use tokens instead of hard-coded product colors.
