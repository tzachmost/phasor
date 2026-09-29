# Architecture

MangoWM owns compositor state and primitives. `phasor-core` is the adapter boundary for windows, Spaces, apps, files, media, clipboard, notifications, audio, networking, Bluetooth, brightness, screenshots, and plugin actions. Quickshell hosts the visible UI; it talks to the core through `phasorctl` and never shells out to compositor/system tools itself.

```text
MangoWM --mmsg IPC--> phasor-core --versioned local JSONL API--> Quickshell plugin host
                                                               ├── Launcher and Settings
                                                               ├── Bar and clock/tray slots
                                                               ├── optional Dock
                                                               ├── Desktop, clipboard, and screenshot
                                                               └── optional user plugins
```

The core uses Python's standard library and a per-user Unix socket in `$XDG_RUNTIME_DIR/phasor/`. Socket access is restricted to the current user. Service calls use named methods and JSON values; shell input is never interpolated into a command string. `mmsg` is invoked with argument arrays.

Plugins declare categories, API version, entrypoint, capabilities, and slots in `plugin.json`. The host discovers repository, system, and user plugins. Optional plugins default to disabled; third-party grants bind to the hash of the full plugin bundle so code or manifest changes invalidate approval. The QML engine is not a process sandbox: only install plugins from sources you trust. Core service calls still enforce declared/granted capabilities.

Visible surfaces declare an anchor, thickness, work-area reservation, overlay policy, priority, and extension slots. The top Bar reserves the top edge and hosts the clock, StatusNotifier tray, notification controls, clipboard history, screenshot action, and Settings entry point. The optional bottom Dock lists and focuses running windows and reserves the bottom edge when enabled. The Desktop adds shortcuts on the bottom layer above the wallpaper. The Launcher and Settings use overlay surfaces. Independent top and bottom surfaces can run at the same time; two enabled surfaces that reserve the same edge are resolved by priority.

Runtime config: `~/.config/phasor/`. Persistent state: `~/.local/share/phasor/`. Cache and file index: `~/.cache/phasor/`. Logs: `~/.local/state/phasor/`.

Standalone applications live in `apps/` and launch as regular Wayland windows. Preview starts from the project-root `preview.qml` entrypoint so Quickshell can resolve app and shared UI files inside one resource tree. It uses Qt Quick PDF when that optional module is installed. Editable annotations, visual signature strokes, PDF form values, and page operations are stored in a validated, atomically written sidecar beside the source file. Export operations write a new copy: Pillow rasterizes image markup and pypdf/ReportLab update form values, add vector marks, and apply page operations while retaining source page content. PDF merge prepares the current document and appends selected sources with imported form names grouped by source filename and import order. Printing sends a temporary prepared copy to CUPS through `lp`.
