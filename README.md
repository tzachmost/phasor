# Phasor Shell

Phasor Shell is a portable desktop shell for MangoWM, built with Quickshell and QML. The first production target is CachyOS/Arch; the source and core service APIs remain distribution independent.

Phasor keeps compositor and system integration behind `phasor-core` services. Its first-party UI is loaded through the same versioned plugin host intended for third-party components.

## Install on CachyOS or Arch

Run these commands in a terminal:

```bash
mkdir -p ~/Work && git clone https://github.com/tzachmost/phasor.git ~/Work/phasor && cd ~/Work/phasor && ./scripts/install
```

The installer adds the required Arch packages, installs MangoWM from the AUR (using paru/yay or makepkg), creates Phasor-owned development links under `~/.local/bin`, installs default settings if needed, and installs the managed runtime and Wayland session entry system-wide. The login chooser can then list **Phasor** separately from Mango. The installer runs diagnostics, preserves existing MangoWM configuration, and refuses to replace unrecognized Phasor paths. The session starts with a Phasor background; set `appearance.wallpaper` in `~/.config/phasor/settings.json` to an image path to use your own wallpaper.

For a development-only link install after dependencies are present, use `./scripts/install-dev`; this writes a user-local session entry, which some login managers do not show. Run `./scripts/doctor` for diagnostics. To install or update the system runtime and chooser entry separately, use `sudo ./scripts/install-system`.

Update the development checkout with:

```bash
cd ~/Work/phasor && git pull && ./scripts/install-dev && sudo ./scripts/install-system
```

## Project layout

- `shell/`: Quickshell entry point, theme tokens, plugin host, and UI components.
- `apps/`: standalone Phasor applications, beginning with Preview.
- `plugins/`: built-in plugins with versioned manifests.
- `core/`: Python service registry, Mango adapter, app/file search, plugin policy, and local IPC.
- `config/`: default user settings and Mango bindings.
- `session/`: Wayland session entry and supervisor.
- `scripts/`: development/system install, dependency helper, diagnostics, source/RPM builders, run, and uninstall.
- `package/`: Arch, Fedora/RPM, and NixOS package definitions.
- `docs/`: architecture, UI, shortcuts, plugin API, and roadmap.

See [docs/architecture.md](docs/architecture.md) and [docs/roadmap.md](docs/roadmap.md) for implementation details. User settings live in `~/.config/phasor/`, persistent data in `~/.local/share/phasor/`, and caches in `~/.cache/phasor/`.

For other installation paths and update/removal instructions, see [docs/install.md](docs/install.md). For a new work session, start with [docs/handoff.md](docs/handoff.md) for the current state, completed work, validation limits, and suggested next steps.

## Preview

Preview opens images and PDFs, fills PDF forms, draws editable marks and signatures, merges PDFs, prints through CUPS, crops and converts images, and exports PDFs with page reorder, exclusion, and rotation. Exported files are new copies; editable work stays in a sidecar beside the original. See [docs/preview.md](docs/preview.md) for formats and optional printing/PDF dependencies.

## Release status

Phasor 1.0.0 delivers the Phasor session, validated settings, Mango Space and window controls, a top Bar with clock and tray support, an optional bottom Dock, notification and Do Not Disturb controls, clipboard history, screenshot capture, the Desktop shortcuts, the app and file Launcher, and diagnostics. Arch/CachyOS, Fedora/Universal Blue, and NixOS install adapters are included. See the [1.0 checklist](docs/roadmap.md), [1.0.0 release notes](docs/releases/1.0.0.md), and [GitHub release](https://github.com/tzachmost/phasor/releases/tag/v1.0.0). Preview is the first post-1.0 application and is now in development.
