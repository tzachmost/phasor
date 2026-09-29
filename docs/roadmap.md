# Roadmap

## Phasor 1.0 release scope

The 1.0 release is the complete portable desktop shell described by the project docs. The first production validation target remains a fresh CachyOS install; support for other distributions is provided through isolated install adapters.

- [x] Complete the v0.1 foundation, including the in-shell Space switcher, appearance and reduced-motion settings, and full launcher file actions.
- [x] Ship an optional Dock and a Bar that can coexist with other surfaces, including tray and clock slots.
- [x] Ship notification controls, clipboard history, and screenshot capture through the existing service boundary.
- [x] Ship a built-in desktop surface.
- [x] Add a settings UI and finish the launcher and file action flows.
- [x] Provide documented install, update, diagnostics, and uninstall paths for Arch/CachyOS, Fedora/Universal Blue, and NixOS.
- [x] Build and inspect the Arch package, Fedora RPM/SRPM, and NixOS package from clean source snapshots.
- [x] Exercise package install, upgrade, and uninstall paths in clean isolated package roots for Arch, RPM, and Nix outputs.
- [ ] Publish the versioned 1.0.0 packages and user documentation from a reviewed, committed source snapshot.
- [x] Validate the complete Phasor session on a fresh CachyOS desktop, including login, surfaces, core actions, and clean shutdown.

The Preview application is the first post-1.0 product. Build it after this checklist is complete and the service/plugin APIs are settled. Agent, Control, and Auth components remain later products.

## v0.1 foundation

- [x] Monorepo and portable core/service contracts
- [x] Development/session scripts and CachyOS dependency path
- [x] Mango state/actions adapter and Space keyboard shortcuts
- [x] In-shell Space indicator and switcher
- [x] Quickshell plugin host and Launcher reference plugin
- [x] Home file search/index, app discovery/launch, shared theme tokens
- [x] Diagnostics and Arch package recipe
- [x] Fresh CachyOS validation
- [x] Theme and reduced-motion settings applied to QML tokens
- [x] Complete file action menu (rename, delete, share, copy file)

## Post-1.0 products

- Preview application with multi-tool document viewing and editing
- Agent, Control, and Auth components after the shell/service APIs settle
