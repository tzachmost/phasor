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

The v0.1 service API also includes:

| Methods | Capability | Backend |
| --- | --- | --- |
| `audio.get_volume`, `audio.set_volume`, `audio.toggle_mute` | `audio.read`, `audio.control` | PipeWire `wpctl` |
| `network.status`, `network.set_wifi` | `network.status`, `network.control` | NetworkManager `nmcli` |
| `bluetooth.status`, `bluetooth.set_power` | `bluetooth.status`, `bluetooth.control` | `bluetoothctl` |
| `brightness.status`, `brightness.set` | `brightness.read`, `brightness.control` | `brightnessctl` |
| `notifications.status`, `notifications.toggle`, `notifications.set_dnd` | `notifications.read`, `notifications.control` | SwayNC |
| `screenshots.capture` | `screenshots.capture` | Flameshot |
| `clipboard.history`, `clipboard.copy` | `clipboard.read`, `clipboard.write` | cliphist and wl-clipboard |
| `media.status`, `media.command` | `media.read`, `media.control` | playerctl |

Audio volume is a scalar from `0` through `1.5`; brightness is a percentage from `0` through `100`. Boolean controls require JSON booleans. These adapters return an unavailable status when a status backend is missing and give an error when a requested action cannot run. Optional backend processes are started by the session when installed.

Built-in plugins shipped from the Phasor source or `/usr/share/phasor/plugins` are pre-approved. User plugins are disabled by default. Approve only the capabilities a plugin declares with:

```bash
phasorctl plugins approve org.example.widget --grant theme.read
phasorctl plugins enable org.example.widget
```

The grant records the plugin bundle hash and becomes invalid if any file changes. QML plugins run in the Quickshell process and are not sandboxed; do not install code from untrusted sources. The core capability check protects service calls but cannot restrict arbitrary QML/Qt imports.

Surfaces declare `anchor`, `thickness`, `reservesWorkArea`, `overlaysWindows`, `autoHide`, `priority`, and `slots`. The host reports occupied regions and rejects multiple enabled reserving surfaces on the same edge (the highest priority is selected). Overlay surfaces do not reserve work area. Extension providers declare `contributions`; the host exposes compatible providers through the named slot registry.
