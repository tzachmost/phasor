# Architecture

MangoWM owns compositor state and primitives. `phasor-core` is the adapter boundary for windows, Spaces, apps, files, media, clipboard, notifications, audio, networking, Bluetooth, brightness, screenshots, and plugin actions. Quickshell hosts the visible UI; it talks to the core through `phasorctl` and never shells out to compositor/system tools itself.

```text
MangoWM --mmsg IPC--> phasor-core --versioned local JSONL API--> Quickshell plugin host
                                                               ├── Launcher plugin
                                                               ├── future Dock / Bar
                                                               └── optional user plugins
```

The core uses Python's standard library and a per-user Unix socket in `$XDG_RUNTIME_DIR/phasor/`. Socket access is restricted to the current user. Service calls use named methods and JSON values; shell input is never interpolated into a command string. `mmsg` is invoked with argument arrays.

Plugins declare categories, API version, entrypoint, capabilities, and slots in `plugin.json`. The host discovers repository, system, and user plugins. Optional plugins default to disabled; third-party grants bind to the hash of the full plugin bundle so code or manifest changes invalidate approval. The QML engine is not a process sandbox: only install plugins from sources you trust. Core service calls still enforce declared/granted capabilities.

Visible surfaces negotiate an anchor, thickness, work-area reservation, overlay policy, priority, and extension slots. There is no single-panel assumption. v0.1 demonstrates the surface contract with the Launcher overlay and the extension-slot loader with a clock component in its status row; Dock and Bar remain optional future plugins.

Runtime config: `~/.config/phasor/`. Persistent state: `~/.local/share/phasor/`. Cache and file index: `~/.cache/phasor/`. Logs: `~/.local/state/phasor/`.
