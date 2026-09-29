import QtQuick
import QtTest
import "../../plugins/dev.phasor.launcher/Search.js" as Search

TestCase {
    name: "LauncherSearch"
    QtObject {
        id: backend
        property var pending: []
        signal eventReceived(var event)
        function extensions(slot) { return [] }
        function request(method, params, callback) {
            if (method === "spaces.list") { callback({ items: [] }); return }
            pending.push({ method: method, params: params, callback: callback })
        }
    }
    property var search: null
    property var results: []
    property bool indexing: false
    property int completions: 0
    function init() {
        backend.pending = []
        results = []
        indexing = false
        completions = 0
        search = Search.create(backend.request, function(result) {
            results = result.items
            indexing = result.indexing
            ++completions
        })
    }
    function test_lateSearchDoesNotReplaceNewResults() {
        search.search("old")
        search.search("new")
        compare(backend.pending.length, 4)
        backend.pending[2].callback({ items: [{ id: "new", name: "New app" }] })
        backend.pending[3].callback({ items: [] })
        compare(results[0].id, "new")
        backend.pending[0].callback({ items: [{ id: "old", name: "Old app" }] })
        backend.pending[1].callback({ items: [], status: { indexing: true } })
        compare(results[0].id, "new")
        compare(indexing, false)
        compare(completions, 1)
    }
    function test_cancelOnClose() {
        search.search("late")
        search.cancel()
        backend.pending[0].callback({ items: [{ id: "late", name: "Late" }] })
        backend.pending[1].callback({ items: [] })
        compare(completions, 0)
    }
    function test_clearQueryIgnoresPendingFiles() {
        search.search("old")
        search.search("")
        backend.pending[2].callback({ items: [{ id: "favorite", name: "Favorite" }] })
        backend.pending[0].callback({ items: [] })
        backend.pending[1].callback({ items: [{ path: "/old", name: "Old file" }] })
        compare(results.length, 1)
        compare(results[0].id, "favorite")
    }
}
