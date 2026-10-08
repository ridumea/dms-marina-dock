// Display order of the row on niri: floating windows in the user's order, a gap entry, then tiled windows.

export const separatorId = "separator";

export function isSeparator(entry) {
    return !!entry && entry.dockSeparator === true;
}

// Drops windows niri has closed but DMS still lists; entries without a niriWindowId are kept.
export function dropClosed(values, liveIds) {
    const kept = values.filter(t => t?.niriWindowId === undefined || liveIds.has(t.niriWindowId));
    return kept.length === values.length ? values : kept;
}

// Returns the row in display order; floatingOrder lists niri window ids, separator is the gap entry.
export function arrange(values, floatingIds, floatingOrder, separator) {
    const tiled = [];
    const floats = [];
    values.forEach((t, i) => {
        if (floatingIds.has(t?.niriWindowId))
            floats.push({
                "t": t,
                "i": i
            });
        else
            tiled.push(t);
    });
    if (floats.length === 0)
        return values;
    const rank = id => {
        const k = floatingOrder.indexOf(id);
        return k < 0 ? floatingOrder.length : k;
    };
    floats.sort((a, b) => (rank(a.t.niriWindowId) - rank(b.t.niriWindowId)) || (a.i - b.i));
    return floats.map(f => f.t).concat([separator], tiled);
}

// Current indices by slot for the row a pending drop predicts, or null when the rows hold different
// windows. A predicted gap not yet in the row is skipped; one no longer predicted is parked first.
export function pendingOrder(ids, pendingIds, sepId) {
    if (!pendingIds || pendingIds.length === 0)
        return null;
    const hasGap = ids.indexOf(sepId) >= 0;
    let want = pendingIds.filter(id => id !== sepId || hasGap);
    if (hasGap && want.indexOf(sepId) < 0)
        want = [sepId].concat(want);
    if (want.length !== ids.length)
        return null;
    const order = want.map(id => ids.indexOf(id));
    return order.some(i => i < 0) ? null : order;
}

// Slot of a predicted gap not yet in the row, else -1.
export function pendingGapSlot(ids, pendingIds, sepId) {
    if (!pendingIds || ids.indexOf(sepId) >= 0)
        return -1;
    return pendingIds.indexOf(sepId);
}

// Whether two id lists hold the same ids in the same order.
export function sameIds(a, b) {
    return a.length === b.length && a.every((id, i) => id === b[i]);
}

// Inserts windows niri reports on no workspace (during a mouse move) at their remembered index so
// the filters do not hide them. memory[id] = { ws, key, index }; allowed(ws) tests a workspace.
export function holdMovingWindows(all, kept, memory, allowed) {
    const keptSet = new Set(kept);
    const held = [];
    for (const t of all) {
        if (keptSet.has(t))
            continue;
        const ws = t?.niriWorkspaceId;
        if (ws !== null && ws !== undefined)
            continue;
        const m = memory[t?.niriWindowId];
        if (m && allowed(m.ws))
            held.push({
                "t": t,
                "at": m.index
            });
    }
    if (held.length === 0)
        return kept;
    held.sort((a, b) => a.at - b.at);
    const out = kept.slice();
    for (const h of held)
        out.splice(Math.min(Math.max(0, h.at), out.length), 0, h.t);
    return out;
}

// Records each window's place for holdMovingWindows and forgets windows not in liveIds; keyOf(id)
// returns undefined while niri reports the window nowhere, so it keeps its last place.
export function rememberPlaces(memory, values, keyOf, liveIds) {
    values.forEach((t, i) => {
        const id = t?.niriWindowId;
        const ws = t?.niriWorkspaceId;
        if (id === undefined || ws === null || ws === undefined)
            return;
        const key = keyOf(id);
        if (key === undefined)
            return;
        memory[id] = {
            "ws": ws,
            "key": key,
            "index": i
        };
    });
    for (const id in memory)
        if (!liveIds.has(Number(id)))
            delete memory[id];
}

// While niri moves a window with the mouse it reports it on no workspace.
export function isMoving(w) {
    return !!w && (w.workspace_id === null || w.workspace_id === undefined);
}

// The "workspace:column" key of a niri window, or null when it is in no scrolling column.
export function columnKeyOf(w) {
    const pos = w?.layout?.pos_in_scrolling_layout;
    return (w && pos && pos.length >= 2) ? (w.workspace_id + ":" + pos[0]) : null;
}

// Per row entry: column key, workspace id and kind ("sep", "float", "tile" or "other").
// A moving window keeps its remembered column and workspace.
export function layoutOf(entries, niriWindows, memory) {
    const byId = new Map();
    for (const w of niriWindows)
        byId.set(w.id, w);
    const keys = [];
    const ws = [];
    const kinds = [];
    for (const t of entries) {
        const w = t?.niriWindowId !== undefined ? byId.get(t.niriWindowId) : null;
        const held = isMoving(w) ? memory[w.id] : null;
        const key = held ? held.key : columnKeyOf(w);
        keys.push(key);
        ws.push(held ? held.ws : (w ? w.workspace_id : null));
        kinds.push(isSeparator(t) ? "sep" : (w && w.is_floating ? "float" : (key ? "tile" : "other")));
    }
    return {
        "keys": keys,
        "ws": ws,
        "kinds": kinds
    };
}
