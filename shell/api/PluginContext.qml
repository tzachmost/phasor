import QtQuick

Item {
    id: context
    visible: false
    width: 1
    height: 1
    required property string pluginId
    required property var backend
    readonly property int apiVersion: 1
    readonly property var state: backend.snapshot
    signal eventReceived(var event)

    function request(method, params, callback) {
        return backend.request(pluginId, method, params || ({}), callback)
    }

    function refreshState() {
        request("spaces.list", {}, function(result) {})
    }

    function extensions(slot) { return backend.extensions(slot) }

    Connections {
        target: context.backend
        function onEventReceived(event) { context.eventReceived(event) }
    }
}
