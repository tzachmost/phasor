# Phasor Shell

Phasor Shell is a portable desktop shell for MangoWM, built with Quickshell and QML. The v0.1 source tree is designed for first validation on a fresh CachyOS/Arch installation; it does not target or depend on the bootstrap distribution.

Phasor keeps compositor and system integration behind `phasor-core` services. Its first-party UI is loaded through the same versioned plugin host intended for third-party components.

## Development install

Clone the repository into `~/Work/phasor`, then run:

```bash
./scripts/install-dev
```

The development installer creates Phasor-owned links under `~/.config/phasor`, `~/.local/share/phasor`, `~/.local/bin`, and `~/.local/share/wayland-sessions`. It does not replace Mango's existing configuration. On a fresh Arch/CachyOS install, use `./scripts/install-deps` first if MangoWM, Quickshell, or the base Wayland tools are missing. Then choose **Phasor** from the login session selector.

Run the shell directly from the checkout with `./scripts/dev-run`. Run `./scripts/doctor` for diagnostics.

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

## Current scope

v0.1 establishes the Phasor session, the service boundary, Mango spaces/windows operations, an app/file launcher plugin, diagnostics, and plugin discovery/lifecycle. MangoWM and Quickshell must be installed on the target system. Full session validation is reserved for a fresh CachyOS install.
