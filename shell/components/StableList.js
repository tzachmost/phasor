.pragma library

// Update by identity so polling does not destroy hovered/focused delegates.
function sync(model, items) {
    var ids = items.map(function(item) { return String(item.id) })
    for (var i = model.count - 1; i >= 0; --i)
        if (ids.indexOf(model.get(i).windowId) < 0) model.remove(i)
    for (var target = 0; target < items.length; ++target) {
        var source = target
        while (source < model.count && model.get(source).windowId !== ids[target]) ++source
        var row = items[target]
        var values = {
            windowId: ids[target], title: String(row.title || row.appId || "Window"),
            appId: String(row.appId || ""), icon: String(row.icon || ""),
            focused: Boolean(row.focused), minimized: Boolean(row.minimized)
        }
        if (source === model.count) model.insert(target, values)
        else {
            if (source !== target) model.move(source, target, 1)
            for (var key in values)
                if (model.get(target)[key] !== values[key]) model.setProperty(target, key, values[key])
        }
    }
}
