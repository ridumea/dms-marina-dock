import { test } from "node:test";
import assert from "node:assert/strict";
import { arrange, isSeparator, separatorId } from "../lib/rowModel.mjs";

const sep = { "dockSeparator": true, "niriWindowId": separatorId };
const w = id => ({ "niriWindowId": id });
const ids = list => list.map(t => t.niriWindowId);

test("without floating windows the row is unchanged and has no gap", () => {
    const values = [w(1), w(2), w(3)];
    assert.equal(arrange(values, new Set(), [], sep), values);
});

test("floating windows come first, then the gap, then all tiled windows", () => {
    // DMS lists floating windows after the tiled ones of their workspace.
    const values = [w(1), w(2), w(9), w(3), w(4), w(8)];
    assert.deepEqual(ids(arrange(values, new Set([9, 8]), [], sep)), [9, 8, separatorId, 1, 2, 3, 4]);
});

test("floating windows follow the user's order, new ones after it", () => {
    const values = [w(1), w(7), w(8), w(9)];
    assert.deepEqual(ids(arrange(values, new Set([7, 8, 9]), [9, 7], sep)), [9, 7, 8, separatorId, 1]);
});

test("ids no longer floating are ignored in the order", () => {
    const values = [w(1), w(2), w(8)];
    assert.deepEqual(ids(arrange(values, new Set([8]), [2, 8], sep)), [8, separatorId, 1, 2]);
});

test("isSeparator recognises only the gap entry", () => {
    assert.equal(isSeparator(sep), true);
    assert.equal(isSeparator(w(1)), false);
    assert.equal(isSeparator(null), false);
});

import { pendingGapSlot, pendingOrder } from "../lib/rowModel.mjs";

test("a pending order with the same entries maps slots to current indices", () => {
    assert.deepEqual(pendingOrder([1, 2, 3], [2, 1, 3], separatorId), [1, 0, 2]);
    assert.equal(pendingOrder([1, 2, 3], [], separatorId), null);
});

test("floating the first window: the predicted gap is skipped until it exists", () => {
    // Window 2 floats: predicted [2, gap, 1, 3], the row still [1, 2, 3].
    assert.deepEqual(pendingOrder([1, 2, 3], [2, separatorId, 1, 3], separatorId), [1, 0, 2]);
    assert.equal(pendingGapSlot([1, 2, 3], [2, separatorId, 1, 3], separatorId), 1);
});

test("tiling the last floating window: the gap no longer predicted is parked first", () => {
    // Window 9 tiled between 1 and 2: predicted [1, 9, 2], the row still [9, gap, 1, 2].
    assert.deepEqual(pendingOrder([9, separatorId, 1, 2], [1, 9, 2], separatorId), [1, 2, 0, 3]);
    assert.equal(pendingGapSlot([9, separatorId, 1, 2], [1, 9, 2], separatorId), -1);
});

test("a pending order for different windows does not apply", () => {
    assert.equal(pendingOrder([1, 2, 4], [2, 1, 3], separatorId), null);
    assert.equal(pendingOrder([1, 2], [2, 1, 3], separatorId), null);
});

import { sameIds } from "../lib/rowModel.mjs";

test("sameIds compares ids in order", () => {
    assert.equal(sameIds([1, separatorId, 2], [1, separatorId, 2]), true);
    assert.equal(sameIds([1, 2], [2, 1]), false);
    assert.equal(sameIds([1, 2], [1, 2, 3]), false);
    assert.equal(sameIds([], []), true);
});

import { holdMovingWindows, rememberPlaces } from "../lib/rowModel.mjs";

const win = (id, ws) => ({ "niriWindowId": id, "niriWorkspaceId": ws });

test("a window niri reports on no workspace is held at its last place", () => {
    const a = win(1, 7), b = win(2, null), c = win(3, 7);
    const memory = {};
    rememberPlaces(memory, [a, win(2, 7), c], id => "7:" + id, new Set([1, 2, 3]));
    // Mid-move: DMS sorts the moving window last and the filter drops it.
    const kept = [a, c];
    assert.deepEqual(holdMovingWindows([a, c, b], kept, memory, ws => ws === 7).map(t => t.niriWindowId), [1, 2, 3]);
});

test("a moving window from a filtered-out workspace stays out", () => {
    const memory = { "2": { "ws": 8, "key": "8:1", "index": 0 } };
    const a = win(1, 7), b = win(2, null);
    assert.deepEqual(holdMovingWindows([a, b], [a], memory, ws => ws === 7), [a]);
});

test("remembering skips windows on no workspace and forgets closed ones", () => {
    const memory = { "2": { "ws": 7, "key": "7:2", "index": 1 }, "9": { "ws": 7, "key": null, "index": 4 } };
    rememberPlaces(memory, [win(1, 7), win(2, null)], () => null, new Set([1, 2]));
    assert.deepEqual(Object.keys(memory).sort(), ["1", "2"]);
    assert.equal(memory["2"].key, "7:2");
});

test("a window niri already reports nowhere keeps its place while DMS's list lags", () => {
    const memory = { "2": { "ws": 7, "key": "7:2", "index": 1 } };
    // DMS still lists window 2 on workspace 7; niri says it is being moved.
    rememberPlaces(memory, [win(1, 7), win(2, 7)], id => id === 2 ? undefined : "7:" + id, new Set([1, 2]));
    assert.deepEqual(memory["2"], { "ws": 7, "key": "7:2", "index": 1 });
});

import { columnKeyOf, isMoving, layoutOf } from "../lib/rowModel.mjs";

const nw = (id, ws, col, more) => Object.assign({
    "id": id,
    "workspace_id": ws,
    "is_floating": false,
    "layout": { "pos_in_scrolling_layout": col === null ? null : [col, 1] }
}, more);

test("the column key is workspace and column, null outside the scrolling layout", () => {
    assert.equal(columnKeyOf(nw(1, 3, 2)), "3:2");
    assert.equal(columnKeyOf(nw(1, 3, null)), null);
    assert.equal(columnKeyOf(null), null);
});

test("a window on no workspace is moving", () => {
    assert.equal(isMoving(nw(1, null, null)), true);
    assert.equal(isMoving(nw(1, undefined, null)), true);
    assert.equal(isMoving(nw(1, 0, 1)), false);
    assert.equal(isMoving(null), false);
});

test("layout gives each entry its column, workspace and kind", () => {
    const windows = [nw(1, 5, 1), nw(2, 5, 1), nw(3, 5, null, { "is_floating": true }), nw(4, 6, null)];
    const entries = [w(3), sep, w(1), w(2), w(4), w(99)];
    assert.deepEqual(layoutOf(entries, windows, {}), {
        "keys": [null, null, "5:1", "5:1", null, null],
        "ws": [5, null, 5, 5, 6, null],
        "kinds": ["float", "sep", "tile", "tile", "other", "other"]
    });
});

test("a moving window holds its remembered column and workspace", () => {
    const windows = [nw(1, 5, 1), nw(2, null, null)];
    const memory = { "2": { "ws": 5, "key": "5:2", "index": 1 } };
    assert.deepEqual(layoutOf([w(1), w(2)], windows, memory), {
        "keys": ["5:1", "5:2"],
        "ws": [5, 5],
        "kinds": ["tile", "tile"]
    });
});

test("a moving window with no remembered place has no column", () => {
    const l = layoutOf([w(2)], [nw(2, null, null)], {});
    assert.deepEqual([l.keys[0], l.ws[0], l.kinds[0]], [null, null, "other"]);
});

import { dropClosed } from "../lib/rowModel.mjs";

test("windows niri has closed are dropped before DMS catches up", () => {
    const values = [w(1), w(9), w(2)];
    assert.deepEqual(ids(dropClosed(values, new Set([1, 2]))), [1, 2]);
});

test("dropClosed keeps the list when every window is live, and unmatched toplevels", () => {
    const values = [w(1), { "appId": "x" }];
    assert.equal(dropClosed(values, new Set([1])), values);
    assert.equal(dropClosed(values, new Set()).length, 1);
});
