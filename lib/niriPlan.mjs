// niri action plans for drag and drop. Arrays are per icon in display order; keys are
// "workspace:column" or null, with a column's tiles adjacent, top first. A "reduced" index
// skips the dragged icon; drop slots are insertion indices into the reduced row.

export function sameWorkspace(ws, i, j) {
    return ws[i] !== null && ws[i] !== undefined && ws[i] === ws[j];
}

// The run of adjacent icons sharing icon i's column.
export function runOf(keys, i) {
    let first = i;
    let last = i;
    const key = keys[i];
    if (key) {
        while (first > 0 && keys[first - 1] === key)
            first--;
        while (last < keys.length - 1 && keys[last + 1] === key)
            last++;
    }
    return {
        "first": first,
        "last": last
    };
}

export function inStack(keys, i) {
    const r = runOf(keys, i);
    return r.last > r.first;
}

// Runs of two or more icons in one column, plus joinItem's single icon so its tray can open.
export function stackRuns(keys, joinItem) {
    const runs = [];
    if (keys.length < 2)
        return runs;
    let start = 0;
    for (let i = 1; i <= keys.length; i++) {
        if (i === keys.length || keys[i] === null || keys[i] !== keys[start]) {
            if (keys[start] !== null && (i - start >= 2 || (joinItem >= start && joinItem <= i - 1)))
                runs.push({
                    "first": start,
                    "last": i - 1
                });
            start = i;
        }
    }
    return runs;
}

function reducedRange(keys, from, key) {
    let rf = -1;
    let rl = -1;
    for (let i = 0; i < keys.length; i++) {
        if (i === from || keys[i] !== key)
            continue;
        const r = i < from ? i : i - 1;
        if (rf < 0 || r < rf)
            rf = r;
        if (r > rl)
            rl = r;
    }
    return rf < 0 ? null : {
        "first": rf,
        "last": rl
    };
}

// -1 / +1 when `slot` is right before / after the rest of the dragged window's column (leave the stack), else 0.
export function ownEdgeForSlot(keys, from, slot) {
    const key = keys[from];
    if (!key)
        return 0;
    const range = reducedRange(keys, from, key);
    if (!range)
        return 0;
    return slot === range.last + 1 ? 1 : (slot === range.first ? -1 : 0);
}

// Maps a join slot in column `joinKey` to { onto, above }, or null if it has no other tiles.
export function resolveJoin(keys, from, joinKey, slot) {
    const range = reducedRange(keys, from, joinKey);
    if (!range)
        return null;
    const pos = slot - range.first;
    const m = range.last - range.first + 1;
    const r = pos < m ? range.first + pos : range.last;
    return {
        "onto": r < from ? r : r + 1,
        "above": pos < m
    };
}

function consume(right) {
    return right ? {
        "ConsumeOrExpelWindowRight": {}
    } : {
        "ConsumeOrExpelWindowLeft": {}
    };
}

function moveColumn(right) {
    return right ? {
        "MoveColumnRight": {}
    } : {
        "MoveColumnLeft": {}
    };
}

function focus(id) {
    return {
        "FocusWindow": {
            "id": id
        }
    };
}

function hasId(id) {
    return id !== undefined && id !== null;
}

// Join the column of icon `onto`, right above or below it.
export function planStack(keys, ws, from, onto, above, id) {
    const myKey = keys[from];
    const targetKey = keys[onto];
    if (!hasId(id) || !myKey || !targetKey || onto === from || !sameWorkspace(ws, from, onto))
        return [];
    const out = [focus(id)];
    const target = runOf(keys, onto);
    const m = target.last - target.first + 1;
    const t = onto - target.first + 1;

    if (targetKey === myKey) {
        const rx = onto < from ? onto : onto - 1;
        const delta = (above ? rx : rx + 1) - from;
        for (let i = 0; i < Math.abs(delta); i++)
            out.push(delta > 0 ? {
                "MoveWindowDown": {}
            } : {
                "MoveWindowUp": {}
            });
        return out;
    }

    const right = onto > from;
    if (inStack(keys, from))
        out.push(consume(right));
    const passed = new Set();
    const lo = right ? from + 1 : target.last + 1;
    const hi = right ? target.first : from;
    for (let i = lo; i < hi; i++)
        if (keys[i] && keys[i] !== myKey && keys[i] !== targetKey && sameWorkspace(ws, i, from))
            passed.add(keys[i]);
    for (let i = 0; i < passed.size; i++)
        out.push(moveColumn(right));
    // niri appends a consumed window at the bottom of the target column.
    out.push(consume(right));
    const ups = m - t + (above ? 1 : 0);
    for (let i = 0; i < ups; i++)
        out.push({
            "MoveWindowUp": {}
        });
    return out;
}

// Move the dragged window's column to insert slot `slot`, leaving its stack first.
export function planReorder(keys, ws, from, slot, ownEdge, id) {
    const myKey = keys[from];
    if (!hasId(id) || !myKey)
        return [];
    const out = [focus(id)];
    if (inStack(keys, from)) {
        // An expelled window becomes a column right beside its old one.
        out.push(consume(ownEdge !== 0 ? ownEdge > 0 : slot > from));
        if (ownEdge !== 0)
            return out;
    }
    const right = slot > from;
    const passed = new Set();
    const lo = right ? from + 1 : slot;
    const hi = right ? slot + 1 : from;
    for (let i = lo; i < hi; i++)
        if (keys[i] && keys[i] !== myKey && sameWorkspace(ws, i, from))
            passed.add(keys[i]);
    for (let i = 0; i < passed.size; i++)
        out.push(moveColumn(right));
    return out;
}

// The 1-based niri column number in a key, or 0.
export function columnOf(key) {
    if (!key)
        return 0;
    const n = Number(key.split(":")[1]);
    return Number.isFinite(n) ? n : 0;
}

// Tiles a floating window and moves it to the first column, so every other column keeps
// its number for MoveColumnToIndex; a join then consumes rightwards and walks up.
export function planFloating(keys, ws, from, slot, join, joinKey, id) {
    if (!hasId(id))
        return [];
    const out = [focus(id), {
        "MoveWindowToTiling": {
            "id": id
        }
    }, {
        "MoveColumnToFirst": {}
    }];
    const j = (join && joinKey) ? resolveJoin(keys, from, joinKey, slot) : null;
    if (j) {
        const target = runOf(keys, j.onto);
        const c = columnOf(keys[j.onto]);
        if (!c || !sameWorkspace(ws, from, j.onto))
            return [focus(id)];
        out.push({
            "MoveColumnToIndex": {
                "index": c
            }
        });
        out.push(consume(true));
        const m = target.last - target.first + 1;
        const t = j.onto - target.first + 1;
        const ups = m - t + (j.above ? 1 : 0);
        for (let i = 0; i < ups; i++)
            out.push({
                "MoveWindowUp": {}
            });
        return out;
    }
    let index = 0;
    let last = 0;
    for (let i = 0; i < keys.length; i++) {
        if (i === from || !keys[i] || !sameWorkspace(ws, i, from))
            continue;
        const r = i < from ? i : i - 1;
        const c = columnOf(keys[i]);
        if (r >= slot && index === 0)
            index = c;
        last = Math.max(last, c);
    }
    if (index === 0)
        index = last + 1;
    out.push({
        "MoveColumnToIndex": {
            "index": index
        }
    });
    return out;
}

// The window ids in the order the drop asks for, or null if any id is unknown.
export function reorderIds(ids, from, insertAt) {
    if (ids.some(id => !hasId(id)))
        return null;
    const order = ids.filter((_, i) => i !== from);
    order.splice(insertAt, 0, ids[from]);
    return order;
}

function floatingOrderFor(drop, id) {
    const order = [];
    let at = 0;
    let r = 0;
    for (let i = 0; i < drop.ids.length; i++) {
        if (i === drop.from)
            continue;
        if (drop.kinds[i] === "float") {
            if (r < drop.slot)
                at++;
            order.push(drop.ids[i]);
        }
        r++;
    }
    order.splice(at, 0, id);
    return order;
}

function predictedRow(tiledIds, floatingIds, sepId) {
    return floatingIds.length > 0 ? floatingIds.concat([sepId], tiledIds) : tiledIds;
}

// Everything a completed drop sends, always ending with the dragged window focused.
//   drop: { keys, ws, ids, kinds, from, slot, join, joinKey, moved, atHome, zone?, sepId? }
// order and floatingOrder are the pending window-id orders, or null when unchanged.
export function planDrop(drop) {
    const id = drop.ids[drop.from];
    const result = {
        "actions": [],
        "order": null,
        "onto": -1,
        "above": false,
        "ownEdge": ownEdgeForSlot(drop.keys, drop.from, drop.slot),
        "floatingOrder": null
    };
    if (!hasId(id))
        return result;
    const floats = drop.kinds[drop.from] === "float";
    const sepId = drop.sepId || "separator";
    const others = kind => drop.ids.filter((_, i) => i !== drop.from && drop.kinds[i] === kind);
    if (!drop.atHome && drop.zone === "float") {
        result.floatingOrder = floatingOrderFor(drop, id);
        if (floats) {
            result.actions = [focus(id)];
        } else {
            result.actions = [focus(id), {
                "MoveWindowToFloating": {
                    "id": id
                }
            }];
            const tiled = drop.ids.filter((_, i) => i !== drop.from && drop.kinds[i] !== "float" && drop.kinds[i] !== "sep");
            result.order = predictedRow(tiled, result.floatingOrder, sepId);
        }
    } else if (!drop.atHome && floats) {
        if (drop.slot >= 0) {
            result.actions = planFloating(drop.keys, drop.ws, drop.from, drop.slot, drop.join, drop.joinKey, id);
            const j = (drop.join && drop.joinKey) ? resolveJoin(drop.keys, drop.from, drop.joinKey, drop.slot) : null;
            if (j) {
                result.onto = j.onto;
                result.above = j.above;
            }
        }
        if (result.actions.length > 1) {
            result.floatingOrder = others("float");
            const order = reorderIds(drop.ids, drop.from, drop.slot);
            result.order = (order && result.floatingOrder.length === 0) ? order.filter(x => x !== sepId) : order;
        }
    } else if (!drop.atHome) {
        const j = (drop.join && drop.joinKey) ? resolveJoin(drop.keys, drop.from, drop.joinKey, drop.slot) : null;
        if (j) {
            result.onto = j.onto;
            result.above = j.above;
            result.actions = planStack(drop.keys, drop.ws, drop.from, j.onto, j.above, id);
        } else if (drop.slot >= 0 && (drop.slot !== drop.from || (drop.moved && result.ownEdge !== 0))) {
            result.actions = planReorder(drop.keys, drop.ws, drop.from, drop.slot, result.ownEdge, id);
        }
        if (result.actions.length > 1)
            result.order = reorderIds(drop.ids, drop.from, drop.slot);
    }
    if (result.actions.length === 0)
        result.actions = [focus(id)];
    return result;
}
