import QtQuick
import Quickshell.Io

Item {
    id: root
    visible: false
    width: 1
    height: 1

    property var command: []
    signal completed(var result)
    property bool finished: false

    function finish(stdoutText, stderrText, exitCode) {
        if (finished) return
        finished = true
        let value = {}
        if (stdoutText && stdoutText.trim().length > 0) {
            try {
                value = JSON.parse(stdoutText)
            } catch (error) {
                value = { error: "Phasor service returned invalid JSON", detail: String(error) }
            }
        } else {
            value = { error: stderrText && stderrText.trim().length > 0 ? stderrText.trim() : "Phasor request failed", exitCode: exitCode }
        }
        completed(value)
        Qt.callLater(function() { root.destroy() })
    }

    Process {
        id: process
        command: root.command
        stdout: StdioCollector { id: stdoutCollector }
        stderr: StdioCollector { id: stderrCollector }
        onExited: function(exitCode, exitStatus) {
            root.finish(stdoutCollector.text, stderrCollector.text, exitCode)
        }
        Component.onCompleted: running = true
    }
}
