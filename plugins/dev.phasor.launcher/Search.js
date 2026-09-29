.pragma library

function create(request, complete) {
    var revision = 0
    return {
        cancel: function() { ++revision },
        search: function(query) {
            var current = ++revision
            var text = query.trim()
            var remaining = text.length >= 2 ? 2 : 1
            var apps = [], files = [], error = "", indexing = false
            function done() {
                if (current !== revision || --remaining > 0) return
                complete({ items: apps.concat(files), error: error, indexing: indexing })
            }
            request("apps.search", { query: text, limit: text.length ? 24 : 30 }, function(result) {
                if (current !== revision) return
                if (result.error) error = result.error
                else apps = (result.items || []).map(function(app) {
                    return { kind: "app", id: app.id, name: app.name, detail: app.genericName || app.comment || "Application", icon: app.icon, favorite: app.favorite, recent: app.recent }
                })
                done()
            })
            if (text.length >= 2) request("files.search", { query: text, limit: 30 }, function(result) {
                if (current !== revision) return
                if (result.error) error = result.error
                else {
                    files = (result.items || []).map(function(file) {
                        return { kind: "file", id: file.path, name: file.name, detail: file.path, directory: file.directory }
                    })
                    indexing = Boolean(result.status && result.status.indexing)
                }
                done()
            })
        }
    }
}
