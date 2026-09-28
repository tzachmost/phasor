import QtQuick
import Quickshell.Io
import "api" as PhasorApi

Item {
    id: host
    width: 1
    height: 1

    property var plugins: []

    Component {
        id: contextFactory
        PhasorApi.PluginContext { pluginId: ""; backend: PhasorApi.Api }
    }

    Process {
        id: discovery
        command: ["phasorctl", "plugins", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    host.plugins = result.plugins || []
                    PhasorApi.Api.registerPlugins(host.plugins)
                } catch (error) {
                    console.error("Phasor plugin discovery returned invalid JSON", error)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.length > 0) console.warn("Phasor plugin discovery:", text)
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) console.error("Phasor plugin discovery failed with status", exitCode)
        }
    }

    function refresh() {
        discovery.exec(["phasorctl", "plugins", "list", "--json"])
    }

    Component.onCompleted: refresh()

    Connections {
        target: PhasorApi.Api
        function onEventReceived(event) {
            if (event.type === "plugin.enabled" || event.type === "plugin.disabled") host.refresh()
        }
    }

    Repeater {
        model: host.plugins.filter(function(plugin) { return plugin.loadable })

        delegate: Loader {
            id: pluginLoader
            property var plugin: modelData
            active: plugin.loadable

            Component.onCompleted: {
                const context = contextFactory.createObject(host, { pluginId: plugin.id })
                if (!context) {
                    console.error("Could not create plugin context for", plugin.id)
                    return
                }
                setSource(plugin.entrypoint, { phasor: context })
            }

            onStatusChanged: {
                if (status === Loader.Error) {
                    const detail = "QML entrypoint failed to load: " + plugin.entrypoint
                    console.error("Phasor plugin", plugin.id, detail)
                    PhasorApi.Api.reportPluginFailure(plugin.id, detail)
                }
            }
        }
    }
}
