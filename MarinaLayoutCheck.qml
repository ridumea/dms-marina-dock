pragma ComponentBehavior: Bound

import QtQuick

// Loaded only while debug logging is on.
Item {
    id: check

    required property var dock
    // Null while the overlay is not loaded; icons are read from it on each check so ones created earlier are seen.
    required property var rows

    property string _lastProblem: ""
    property string _loggedProblem: ""

    function rowItems() {
        const items = [];
        const r = check.rows;
        if (!r)
            return items;
        for (let i = 0; i < r.count; i++) {
            const it = r.itemAt(i);
            if (it)
                items.push(it);
        }
        return items;
    }

    function snapshot(tag) {
        const d = check.dock;
        const items = check.rowItems().map(it => ({
                    "i": it.index,
                    "slot": it.slot,
                    "layoutSlot": it.layoutSlot,
                    "animSlot": Math.round(it.animSlot * 100) / 100,
                    "x": Math.round(it.x),
                    "vis": it.visible,
                    "app": (d.modelValues[it.index]?.appId || "").slice(0, 6)
                }));
        items.sort((a, b) => a.i - b.i);
        return JSON.stringify({
            "tag": tag,
            "dragging": d.dragging,
            "hasGap": d.hasGap,
            "slotCount": d.slotCount,
            "n": d.windowCount,
            "pending": d.pendingIds,
            "amount": Math.round(d.magnifyAmount * 100) / 100,
            "hoverActive": d.hoverActive,
            "animSlotCount": Math.round(d.animSlotCount * 100) / 100,
            "rowStart": Math.round(d.rowStartScene),
            "baseStart": Math.round(d.baseStartScene),
            "items": items
        });
    }

    Timer {
        interval: check.dock.layoutCheckMs
        repeat: true
        running: check.rows !== null && (check.dock.hoverActive || check.dock.dragging || check.dock.magnifyAmount > 0)
        onTriggered: {
            const d = check.dock;
            if (d.dragging)
                return;
            const n = d.windowCount;
            const items = check.rowItems();
            const seen = new Set();
            let problem = "";
            for (const it of items) {
                if (it.index < 0 || it.index >= n) {
                    problem = "stale index " + it.index;
                    break;
                }
                if (!it.visible) {
                    problem = "hidden item " + it.index;
                    break;
                }
                if (it.slot < 0 || it.slot >= n || seen.has(it.slot)) {
                    problem = "bad slot " + it.slot + " for item " + it.index;
                    break;
                }
                seen.add(it.slot);
                if (Math.abs(it.animSlot - it.layoutSlot) > 0.01) {
                    problem = "item " + it.index + " stuck between slots";
                    break;
                }
            }
            if (!problem && items.length !== n)
                problem = "expected " + n + " items, have " + items.length;
            if (!problem && d.slotCount !== n)
                problem = "slotCount " + d.slotCount + " != " + n;
            // A glide between slots is shorter than layoutCheckMs, so only a problem seen twice in a row is real.
            if (problem && problem === check._lastProblem && problem !== check._loggedProblem) {
                console.warn("[marina] layout inconsistency:", problem, check.snapshot("check"));
                check._loggedProblem = problem;
            }
            if (!problem)
                check._loggedProblem = "";
            check._lastProblem = problem;
        }
    }
}
