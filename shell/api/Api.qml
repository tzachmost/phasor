pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: api
    visible: false
    width: 1
    height: 1

    property var snapshot: ({})
    property var plugins: []
    signal eventReceived(var event)

    Component {
        id: requestComponent
        Request {}
    }

    Process {
        id: eventStream
        command: ["phasorctl", "watch", "--events"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    const event = JSON.parse(line)
                    if (event.type === "snapshot") api.snapshot = event.data || ({})
                    api.eventReceived(event)
                } catch (error) {
                    console.warn("Phasor: ignored malformed service event", error)
                }
            }
        }
        stderr: StdioCollector {}
        onRunningChanged: if (!running) retryTimer.start()
    }

    Timer {
        id: retryTimer
        interval: 1000
        repeat: false
        onTriggered: if (!eventStream.running) eventStream.running = true
    }

    function request(pluginId, method, params, callback) {
        const request = requestComponent.createObject(api, {
            command: ["phasorctl", "plugins", "call", pluginId, method, JSON.stringify(params || ({}))]
        })
        if (!request) {
            callback({ error: "Could not create Phasor service request" })
            return null
        }
        request.completed.connect(function(result) { callback(result) })
        return request
    }

    function registerPlugins(value) {
        plugins = value || []
    }

    function extensions(slot) {
        let result = []
        for (const plugin of plugins) {
            if (!plugin.loadable) continue
            for (const contribution of (plugin.contributions || [])) {
                if (contribution.slot === slot) result.push({ pluginId: plugin.id, entrypoint: contribution.entrypoint })
            }
        }
        return result
    }

    function reportPluginFailure(pluginId, message) {
        const request = requestComponent.createObject(api, {
            command: ["phasorctl", "rpc", "plugins.report-failure", JSON.stringify({ id: pluginId, message: message })]
        })
        if (request) request.completed.connect(function(result) {
            if (result && result.disabled) console.warn("Phasor disabled repeatedly failing plugin", pluginId)
        })
    }
}
