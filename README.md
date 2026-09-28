# Phasor Shell

Phasor Shell is a portable desktop shell for MangoWM, built with Quickshell and QML. The v0.1 source tree is designed for first validation on a fresh CachyOS/Arch installation; it does not target or depend on the bootstrap distribution.

Phasor keeps compositor and system integration behind `phasor-core` services. Its first-party UI is loaded through the same versioned plugin host intended for third-party components.

## Install on CachyOS or Arch

Run these commands in a terminal:

```bash
mkdir -p ~/Work && git clone https://github.com/tzachmost/phasor.git ~/Work/phasor && cd ~/Work/phasor && ./scripts/install
```

The installer adds the required Arch packages, installs MangoWM from the AUR (using paru/yay or makepkg), creates Phasor-owned links under `~/.local/bin`, installs default settings if needed, registers the Phasor login session, and runs diagnostics. It keeps existing MangoWM configuration and refuses to replace unrecognized Phasor paths. The session starts with a Phasor background; set `appearance.wallpaper` in `~/.config/phasor/settings.json` to an image path to use your own wallpaper. Choose **Phasor** from the login session selector when installation completes.

For a development-only link install after dependencies are present, use `./scripts/install-dev`. Run `./scripts/doctor` for diagnostics. For a system install, use `sudo ./scripts/install-system`.

Update the development checkout with:

```bash
cd ~/Work/phasor && git pull && ./scripts/install-dev
```

## Project layout

- `shell/`: Quickshell entry point, theme tokens, plugin host, and UI components.
- `plugins/`: built-in plugins with versioned manifests.
- `core/`: Python service registry, Mango adapter, app/file search, plugin policy, and local IPC.
- `config/`: default user settings and Mango bindings.
- `session/`: Wayland session entry and supervisor.
- `scripts/`: development/system install, dependency helper, diagnostics, run, and uninstall.
- `package/arch/`: Arch package recipe.
- `docs/`: architecture, UI, shortcuts, plugin API, and roadmap.

See [docs/architecture.md](docs/architecture.md) and [docs/roadmap.md](docs/roadmap.md) for implementation details. User settings live in `~/.config/phasor/`, persistent data in `~/.local/share/phasor/`, and caches in `~/.cache/phasor/`.

For a new work session, start with [docs/handoff.md](docs/handoff.md) for the current state, completed work, validation limits, and suggested next steps.

## Current scope

v0.1 establishes the Phasor session, wallpaper, the service boundary, Mango spaces/windows operations, an app/file launcher plugin, diagnostics, and plugin discovery/lifecycle. The core exposes Space state and controls, though an in-shell Space indicator is still planned. File actions currently cover open, reveal, and copy path; rename, delete, share, and copy-file actions are not implemented. MangoWM and Quickshell must be installed on the target system. Full session validation is reserved for a fresh CachyOS install.
