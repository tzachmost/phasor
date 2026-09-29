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
- [x] Publish the versioned 1.0.0 packages and user documentation from a reviewed, committed source snapshot.
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

- Preview application with multi-tool image/PDF viewing, navigation, markup, and export
- Agent, Control, and Auth components after the shell/service APIs settle

The 1.0 checklist is complete. Submitting the stable Arch recipe to the AUR is a separate distribution follow-up; it requires an AUR SSH key registered to the maintainer account.

## Preview first milestone

- [x] Install Preview as a standalone Wayland app with command-line and file-manager open paths.
- [x] View common Qt-supported image formats and PDFs, with fit/zoom/rotation controls.
- [x] Browse PDF thumbnails and pages, search text, select text, and copy it.
- [x] Add pen, highlight, rectangle, and text markup with autosaved editable sidecars.
- [x] Crop and resize images, convert formats, and export a flattened result.
- [x] Export PDF markup into a flattened PDF, with page reorder, exclusion, and rotation operations.
- [x] Fill common PDF form fields and export the values while preserving editable fields.
- [x] Draw visual signatures and include them in export and print copies.
- [x] Merge PDFs into a new copy, preserving pages and avoiding imported form field name collisions.
- [x] Print prepared images and PDFs through configured CUPS printers.
- [x] Add certificate-based PDF signing.

## Preview multi-tool follow-on

The first Preview milestone is complete. Continue toward a broader document and image workspace, using the [Apple Preview guide](https://support.apple.com/en-gb/guide/preview/welcome/mac) as a feature reference while keeping Phasor's Wayland and sidecar-based workflow.

- [x] Browse embedded PDF bookmarks in a Contents sidebar and jump to their destinations.
- [ ] Add single-page, continuous-scroll, and two-page reading layouts.
- [ ] Add and move individual PDF pages, including blank pages and pages selected from another open document.
- [ ] Add text-anchored highlighting, underline, strike-through, and note annotations.
- [ ] Add a document information panel for PDF metadata and image dimensions, format, and metadata.
- [ ] Add PDF password entry/protection and file-size reduction with explicit copy-based export.
- [ ] Expand image workflows with flip, animated-image frame browsing, and background removal.
- [ ] Exercise Preview with complex public forms, outlines, signed files, large scans, and real printer queues.
