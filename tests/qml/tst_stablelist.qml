import QtQuick
import QtTest
import "../../shell/components/StableList.js" as StableList

TestCase {
    name: "DockModel"
    ListModel { id: model }
    Repeater {
        id: repeater
        model: model
        Item { required property string windowId; Component.onCompleted: ++testState.created }
    }
    QtObject { id: testState; property int created: 0 }
    function init() { model.clear(); testState.created = 0 }
    function row(id, focused) { return { id: id, title: "Window " + id, focused: !!focused } }
    function test_refreshPreservesDelegates() {
        StableList.sync(model, [row("one"), row("two")])
        const first = repeater.itemAt(0)
        StableList.sync(model, [row("one", true), row("two")])
        compare(repeater.itemAt(0), first)
        compare(testState.created, 2)
        compare(model.get(0).focused, true)
        for (let i = 0; i < 10; ++i) StableList.sync(model, [row("one", true), row("two")])
        compare(testState.created, 2)
    }
    function test_addRemoveReorder() {
        StableList.sync(model, [row("one"), row("two"), row("three")])
        const retained = repeater.itemAt(2)
        StableList.sync(model, [row("three"), row("two"), row("four")])
        compare(repeater.itemAt(0), retained)
        compare(model.count, 3)
        compare(model.get(2).windowId, "four")
        compare(testState.created, 4)
        StableList.sync(model, [])
        compare(model.count, 0)
    }
}
