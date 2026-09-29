# Development handoff

The active objective is a complete Phasor 1.0 release. Read this page with [the roadmap](roadmap.md), [architecture](architecture.md), and [the plugin API](plugin-api.md). The Preview document app is post-1.0 work and should begin after every 1.0 release check passes.

## Current implementation

The v0.1 foundation and the Bar, Dock, Desktop, and service surfaces are implemented. The repo includes the Phasor session supervisor, Quickshell plugin host, validated core configuration and local service API, Mango Space/window controls, Launcher, full Home file actions, live theme/wallpaper settings, a top Bar, an optional window Dock, and Desktop shortcuts over the wallpaper. The Bar shows workspaces, clock, tray items, notification count, Do Not Disturb, clipboard history, screenshot capture, and Settings. The Dock can focus and close running windows; Settings can enable or disable the Desktop and Dock live. These surfaces can run together.

Arch/CachyOS, Fedora, Universal Blue/OSTree, and NixOS install, update, diagnostics, and removal paths are documented. The versioned Arch recipe, Fedora RPM/SRPM, and NixOS flake package have built and passed artifact inspection. Isolated package transactions and a fresh CachyOS session run are complete. The remaining 1.0 gate is publishing from a reviewed, committed source snapshot. See [the roadmap](roadmap.md) for the source of truth.

## Latest validation

- All 48 Python unit tests passed. Python compilation and `git diff --check` passed after the plugin discovery fix.
- `scripts/build-source` creates the versioned release archive with normalized timestamps, ownership, ordering, and gzip metadata. The stable Arch recipe checksum matches the archive.
- An isolated headless Mango session loaded Quickshell, the Bar, Settings, Dock, and Desktop. It showed and removed the Dock at runtime, listed/focused/closed a test Alacritty window, displayed clipboard history, restored clipboard contents, and updated notification DND state.
- The stable Arch recipe built from the versioned source archive, installed as 1.0.0, upgraded to a temporary 1.0.1 fixture, and removed cleanly in an isolated pacman root. Fedora's 1.0.0 RPM/SRPM built and the RPM installed and removed in a clean RPM database root. The Nix flake passed `nix flake check --no-build --all-systems`; its 1.0.0 profile package installed and removed cleanly. Earlier package transaction checks also covered version upgrades.
- A fresh CachyOS VM booted from the official ISO and installed Phasor as a separate session. The Phasor login showed the Bar and Desktop; Settings changed Dock visibility live; Home opened Dolphin; Launcher searched apps and files and copied a file path into Clipboard history; Notifications and screenshot capture opened. `systemctl poweroff` completed and QEMU exited cleanly.
- The fresh guest had an earlier installed core manager, so its doctor reported duplicate diagnostics for identical source and system plugin bundles. The current manager ignores identical bundles quietly and retains a diagnostic for differing contents; regression tests cover both cases. The host Phasor session was left running untouched.
- Earlier source/system install and uninstall flows passed in temporary roots; DNF5 and OSTree adapter command paths passed simulations with mocked package tools.

## Next work

1. Review and commit the prepared 1.0.0 source, publish the `v1.0.0` GitHub release with the source archive and RPM assets, and publish the Arch recipe metadata. This checkout still has local modified and untracked work; the environment has no authenticated GitHub session.
2. Start the Preview application only after the 1.0 release checklist is complete.

## Development notes

- Use `~/Work/phasor` as the normal checkout and `./scripts/doctor` for installed-system diagnostics.
- Keep compositor and system tools behind `phasor-core`; built-in and third-party QML calls go through capability-checked services.
- Keep the system Phasor session and user configuration separate from headless test runs. The current desktop already has a system-installed Phasor session; do not stop or rewrite it while testing the repository checkout.
