# Development handoff

Phasor 1.0.0 is published; the active product is Preview, the first post-1.0 document app. Read this page with [the roadmap](roadmap.md), [architecture](architecture.md), and [the plugin API](plugin-api.md).

## Current implementation

The v0.1 foundation and the Bar, Dock, Desktop, and service surfaces are implemented. The repo includes the Phasor session supervisor, Quickshell plugin host, validated core configuration and local service API, Mango Space/window controls, Launcher, full Home file actions, live theme/wallpaper settings, a top Bar, an optional window Dock, and Desktop shortcuts over the wallpaper. The Bar shows workspaces, clock, tray items, notification count, Do Not Disturb, clipboard history, screenshot capture, and Settings. The Dock can focus and close running windows; Settings can enable or disable the Desktop and Dock live. These surfaces can run together.

Preview is implemented as a standalone Wayland application. It opens images and PDFs; supports PDF page navigation, thumbnails, text search and copy; provides image/PDF markup with autosaved sidecars; and exports flattened image copies or PDFs with searchable source content. Image export supports crop, resize, rotate, format conversion, and quality settings. PDF export supports markup, page reorder, exclusion, and per-page rotation while preserving the source file. The 1.1.0 development package includes Pillow, pypdf, ReportLab, WebP support, and DejaVu Sans for export.

Arch/CachyOS, Fedora, Universal Blue/OSTree, and NixOS install, update, diagnostics, and removal paths are documented. The versioned Arch recipe, Fedora RPM/SRPM, and NixOS flake package have built and passed artifact inspection. Isolated package transactions and a fresh CachyOS session run are complete. The reviewed source commit, `v1.0.0` tag, packages, checksums, and user documentation are published in the [GitHub release](https://github.com/tzachmost/phasor/releases/tag/v1.0.0). The stable Arch recipe still needs an AUR SSH key before it can be submitted; that distribution follow-up does not block the completed 1.0 roadmap checklist.

## Latest validation

- All 61 Python unit tests passed, including image format/crop/resize/markup export, PDF text-preserving markup and page operations, offset CropBox placement, and sidecar validation. Python compilation, `git diff --check`, and dependency-script shell syntax checks passed.
- Preview opened a local two-page PDF in a fresh Quickshell process on the desktop. The app rendered both pages, page thumbnails, navigation and export controls; the Quickshell log had no QML warnings or errors. Image Preview was also inspected during the earlier viewer milestone.
- `scripts/build-source` creates the versioned release archive with normalized timestamps, ownership, ordering, and gzip metadata. The stable Arch recipe checksum matches the archive.
- An isolated headless Mango session loaded Quickshell, the Bar, Settings, Dock, and Desktop. It showed and removed the Dock at runtime, listed/focused/closed a test Alacritty window, displayed clipboard history, restored clipboard contents, and updated notification DND state.
- The stable Arch recipe built from the versioned source archive, installed as 1.0.0, upgraded to a temporary 1.0.1 fixture, and removed cleanly in an isolated pacman root. Fedora's 1.0.0 RPM/SRPM built and the RPM installed and removed in a clean RPM database root. The Nix flake passed `nix flake check --no-build --all-systems`; its 1.0.0 profile package installed and removed cleanly. Earlier package transaction checks also covered version upgrades.
- A fresh CachyOS VM booted from the official ISO and installed Phasor as a separate session. The Phasor login showed the Bar and Desktop; Settings changed Dock visibility live; Home opened Dolphin; Launcher searched apps and files and copied a file path into Clipboard history; Notifications and screenshot capture opened. `systemctl poweroff` completed and QEMU exited cleanly.
- The `v1.0.0` GitHub release is published with the source archive, Arch package, Fedora RPM/SRPM, and `SHA256SUMS`; every published asset checksum matches the local release manifest.
- The `1.1.0.dev0` source archive rebuilt reproducibly, the Fedora RPM/SRPM built with the Preview app included, and Nix flake outputs evaluated for all systems.
- The fresh guest had an earlier installed core manager, so its doctor reported duplicate diagnostics for identical source and system plugin bundles. The current manager ignores identical bundles quietly and retains a diagnostic for differing contents; regression tests cover both cases. The host Phasor session was left running untouched.
- Earlier source/system install and uninstall flows passed in temporary roots; DNF5 and OSTree adapter command paths passed simulations with mocked package tools.

## Next work

1. Continue Preview with PDF form filling, signature workflows, and printing; assess PDF merge and richer page tools against the current sidecar/export model.
2. Submit the stable Arch recipe metadata to the AUR after an AUR SSH public key is registered. No SSH key is currently present in `~/.ssh`.

## Development notes

- Use `~/Work/phasor` as the normal checkout and `./scripts/doctor` for installed-system diagnostics.
- Keep compositor and system tools behind `phasor-core`; built-in and third-party QML calls go through capability-checked services.
- Keep the system Phasor session and user configuration separate from headless test runs. The current desktop already has a system-installed Phasor session; do not stop or rewrite it while testing the repository checkout.
