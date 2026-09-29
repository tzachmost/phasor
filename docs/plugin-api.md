# Plugin API v1

Plugins are directories with `plugin.json` and a QML `entrypoint`. The manifest names an API version, categories, capabilities, permissions, supported extension slots, and optional surface metadata. Every entrypoint and contribution must remain inside its plugin directory.

```json
{
  "id": "org.example.widget",
  "name": "Example widget",
  "version": "1.0.0",
  "apiVersion": 1,
  "entrypoint": "Widget.qml",
  "categories": ["status-item"],
  "capabilities": ["theme.read"],
  "permissions": [],
  "supportedSlots": ["launcher.actions"],
  "contributions": [{"slot": "launcher.actions", "entrypoint": "Widget.qml"}]
}
```

The host loads enabled plugins and passes a `phasor` context object into each QML root. Its API is `phasor.request(method, params, callback)`, `phasor.state`, `phasor.eventReceived`, and `phasor.extensions(slot)`. Calls go through the core; the plugin must declare the matching capability. Service methods include `apps.search`, `apps.launch`, `files.search`, `spaces.list`, and `windows.list`.

The service API also includes:

| Methods | Capability | Backend |
| --- | --- | --- |
| `audio.get_volume`, `audio.set_volume`, `audio.toggle_mute` | `audio.read`, `audio.control` | PipeWire `wpctl` |
| `network.status`, `network.set_wifi` | `network.status`, `network.control` | NetworkManager `nmcli` |
| `bluetooth.status`, `bluetooth.set_power` | `bluetooth.status`, `bluetooth.control` | `bluetoothctl` |
| `brightness.status`, `brightness.set` | `brightness.read`, `brightness.control` | `brightnessctl` |
| `notifications.status`, `notifications.toggle`, `notifications.set_dnd` | `notifications.read`, `notifications.control` | SwayNC |
| `screenshots.capture` | `screenshots.capture` | Flameshot |
| `clipboard.history`, `clipboard.toggle` | `clipboard.read` | Clipboard history UI action |
| `clipboard.copy`, `clipboard.restore` | `clipboard.write` | wl-clipboard; cliphist for history restore |
| `media.status`, `media.command` | `media.read`, `media.control` | playerctl |
| `files.rename`, `files.trash`, `files.copy` | `files.rename`, `files.trash`, `files.copy` | User Home file actions; Trash uses GIO |
| `files.share` | `clipboard.write` | Copy the local file URI to the Wayland clipboard |
| `settings.get`, `settings.update` | `settings.read`, `settings.control` | Validated per-user settings |
| `launcher.toggle`, `settings.toggle` | `apps.read`, `settings.control` | Toggle the built-in overlays |

Launcher file actions are restricted to the user's Home directory. Rename stays in the current directory, Trash asks for confirmation in the Launcher, and copy creates a uniquely named duplicate beside the source. Share copies a `file://` URI for pasting into another application. Clipboard history exposes a preview and numeric item id; `clipboard.restore` decodes the selected item in the core before copying it back to the Wayland clipboard.

Audio volume is a scalar from `0` through `1.5`; brightness is a percentage from `0` through `100`. Boolean controls require JSON booleans. `theme.get` returns the user's theme, accent, reduced-motion, and wallpaper preferences. `settings.update` accepts a partial object in its `patch` field, validates it against the settings schema, saves atomically, and publishes `settings.changed`; changing a plugin's `enabled` preference also publishes its lifecycle event so the host reloads it. These adapters return an unavailable status when a status backend is missing and give an error when a requested action cannot run. Optional backend processes are started by the session when installed.

Built-in plugins shipped from the Phasor source or `/usr/share/phasor/plugins` are pre-approved. User plugins are disabled by default. Approve only the capabilities a plugin declares with:

```bash
phasorctl plugins approve org.example.widget --grant theme.read
phasorctl plugins enable org.example.widget
```

The grant records the plugin bundle hash and becomes invalid if any file changes. QML plugins run in the Quickshell process and are not sandboxed; do not install code from untrusted sources. The core capability check protects service calls but cannot restrict arbitrary QML/Qt imports.

Surfaces declare `anchor`, `thickness`, `reservesWorkArea`, `overlaysWindows`, `autoHide`, `priority`, and `slots`. The host reports occupied regions and permits one enabled reserving surface per edge (the highest priority is selected). Overlay surfaces do not reserve work area. Extension providers declare `contributions`; the host exposes compatible providers through the named slot registry. The built-in Bar uses `bar.left` and `bar.right`; the optional Dock uses `dock.left`, `dock.center`, `dock.right`, and `dock.status`.
