import { test } from "node:test";
import assert from "node:assert/strict";
import { columnOf, ownEdgeForSlot, planDrop, planFloating, planReorder, planStack, resolveJoin, stackRuns } from "../lib/niriPlan.mjs";

const focus = id => ({ "FocusWindow": { "id": id } });
const L = { "MoveColumnLeft": {} };
const R = { "MoveColumnRight": {} };
const CL = { "ConsumeOrExpelWindowLeft": {} };
const CR = { "ConsumeOrExpelWindowRight": {} };
const UP = { "MoveWindowUp": {} };
const DOWN = { "MoveWindowDown": {} };
const times = (a, n) => Array(n).fill(a);

// One workspace unless a test says otherwise.
const row = (...cols) => ({ keys: cols.map(c => "1:" + c), ws: cols.map(() => 1), ids: cols.map((_, i) => 100 + i), kinds: cols.map(() => "tile") });

test("stackRuns groups adjacent tiles of one column", () => {
    const keys = ["1:1", "1:1", "1:2", null, "1:3", "1:3"];
    assert.deepEqual(stackRuns(keys, -1), [{ first: 0, last: 1 }, { first: 4, last: 5 }]);
    assert.deepEqual(stackRuns(keys, 2), [{ first: 0, last: 1 }, { first: 2, last: 2 }, { first: 4, last: 5 }]);
    assert.deepEqual(stackRuns(["1:1"], 0), []);
});

test("insert right of origin moves once per distinct column passed", () => {
    const r = row(1, 2, 2, 3);
    assert.deepEqual(planReorder(r.keys, r.ws, 0, 3, 0, 100), [focus(100), R, R]);
});

test("insert left of origin", () => {
    const r = row(1, 2, 3);
    assert.deepEqual(planReorder(r.keys, r.ws, 2, 0, 0, 102), [focus(102), L, L]);
});

test("stacked window next to its own stack is expelled toward that side", () => {
    const r = row(1, 1, 2);
    assert.equal(ownEdgeForSlot(r.keys, 0, 1), 1);
    assert.equal(ownEdgeForSlot(r.keys, 0, 0), -1);
    assert.deepEqual(planReorder(r.keys, r.ws, 0, 1, 1, 100), [focus(100), CR]);
    assert.deepEqual(planReorder(r.keys, r.ws, 0, 0, -1, 100), [focus(100), CL]);
});

test("stacked window moved further is expelled, then moved", () => {
    const r = row(1, 1, 2, 3);
    assert.equal(ownEdgeForSlot(r.keys, 1, 3), 0);
    assert.deepEqual(planReorder(r.keys, r.ws, 1, 3, 0, 101), [focus(101), CR, R, R]);
});

test("join above the top tile of another column", () => {
    const r = row(1, 2, 2);
    assert.deepEqual(resolveJoin(r.keys, 0, "1:2", 0), { onto: 1, above: true });
    // Consumed at the bottom (tile 3), walked up to tile 1.
    assert.deepEqual(planStack(r.keys, r.ws, 0, 1, true, 100), [focus(100), CR, UP, UP]);
});

test("join below the last tile needs no walk", () => {
    const r = row(1, 2, 2);
    assert.deepEqual(resolveJoin(r.keys, 0, "1:2", 2), { onto: 2, above: false });
    assert.deepEqual(planStack(r.keys, r.ws, 0, 2, false, 100), [focus(100), CR]);
});

test("join a column further away expels, moves until adjacent, consumes", () => {
    const r = row(1, 1, 2, 3);
    // Tile 0 of column 1 joins below the single icon of column 3.
    assert.deepEqual(planStack(r.keys, r.ws, 0, 3, false, 100), [focus(100), CR, R, CR]);
    // Moving left from column 3 to above column 1's second tile.
    assert.deepEqual(planStack(r.keys, r.ws, 3, 1, true, 103), [focus(103), L, CL, UP]);
});

test("reorder inside the same column moves by the tile delta", () => {
    const r = row(1, 1, 1);
    assert.deepEqual(resolveJoin(r.keys, 0, "1:1", 2), { onto: 2, above: false });
    assert.deepEqual(planStack(r.keys, r.ws, 0, 2, false, 100), [focus(100), ...times(DOWN, 2)]);
    assert.deepEqual(planStack(r.keys, r.ws, 2, 0, true, 102), [focus(102), ...times(UP, 2)]);
});

test("release on the reserved spot only focuses", () => {
    const r = row(1, 2, 3);
    const plan = planDrop({ ...r, from: 1, slot: 1, join: false, joinKey: "", moved: true, atHome: true });
    assert.deepEqual(plan.actions, [focus(101)]);
    assert.equal(plan.order, null);
});

test("a stacked tile released at home after moving still gets focus", () => {
    const r = row(1, 1, 2);
    const plan = planDrop({ ...r, from: 0, slot: 0, join: false, joinKey: "", moved: true, atHome: true });
    assert.deepEqual(plan.actions, [focus(100)]);
});

test("a completed move sets the pending order", () => {
    const r = row(1, 2, 3);
    const plan = planDrop({ ...r, from: 0, slot: 2, join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.actions, [focus(100), R, R]);
    assert.deepEqual(plan.order, [101, 102, 100]);
});

test("unknown window id plans nothing", () => {
    const r = row(1, 2);
    r.ids[0] = undefined;
    const plan = planDrop({ ...r, from: 0, slot: 1, join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.actions, []);
});

test("columns on other workspaces are never counted or joined", () => {
    const keys = ["1:1", "1:2", "2:1", "2:2"];
    const ws = [1, 1, 2, 2];
    assert.deepEqual(planReorder(keys, ws, 0, 3, 0, 100), [focus(100), R]);
    assert.deepEqual(planStack(keys, ws, 0, 2, true, 100), []);
    assert.deepEqual(planStack(keys, ws, 1, 3, false, 101), []);
});

// ---- floating windows ----
const TILE = id => ({ "MoveWindowToTiling": { "id": id } });
const FIRST = { "MoveColumnToFirst": {} };
const AT = i => ({ "MoveColumnToIndex": { "index": i } });

// Floating windows 300 and 301, the gap, then tiled columns: the row as
// rowModel.arrange builds it.
const floatRow = (...cols) => ({
    keys: [null, null, null, ...cols.map(c => "1:" + c)],
    ws: [1, 1, null, ...cols.map(() => 1)],
    ids: [300, 301, "separator", ...cols.map((_, i) => 100 + i)],
    kinds: ["float", "float", "sep", ...cols.map(() => "tile")],
    sepId: "separator"
});

test("columnOf reads the column number from a key", () => {
    assert.equal(columnOf("1:3"), 3);
    assert.equal(columnOf(null), 0);
});

// Dragging 301 (index 1): the reduced row is 300, the gap, then the columns
// from slot 2.
test("floating window inserted before a column is tiled, parked first, then moved to that column number", () => {
    const r = floatRow(1, 2, 3);
    assert.deepEqual(planFloating(r.keys, r.ws, 1, 3, false, "", 301), [focus(301), TILE(301), FIRST, AT(2)]);
    assert.deepEqual(planFloating(r.keys, r.ws, 1, 2, false, "", 301), [focus(301), TILE(301), FIRST, AT(1)]);
});

test("floating window inserted after the last column goes one past it", () => {
    const r = floatRow(1, 2, 3);
    assert.deepEqual(planFloating(r.keys, r.ws, 1, 5, false, "", 301), [focus(301), TILE(301), FIRST, AT(4)]);
});

test("floating window joining a stack lands before it, consumes right, walks up", () => {
    const r = floatRow(1, 2, 2);
    // slot 3 in the reduced row = above the stack's top tile (column 2, two tiles)
    assert.deepEqual(planFloating(r.keys, r.ws, 1, 3, true, "1:2", 301), [focus(301), TILE(301), FIRST, AT(2), CR, UP, UP]);
    // slot 5 = below the last tile
    assert.deepEqual(planFloating(r.keys, r.ws, 1, 5, true, "1:2", 301), [focus(301), TILE(301), FIRST, AT(2), CR]);
});

test("floating window joining a stack on another workspace only focuses", () => {
    const r = floatRow(1, 2, 2);
    r.keys = [...r.keys.slice(0, 4), "2:2", "2:2"];
    r.ws = [...r.ws.slice(0, 4), 2, 2];
    assert.deepEqual(planFloating(r.keys, r.ws, 1, 3, true, "2:2", 301), [focus(301)]);
});

test("planDrop routes a floating source through planFloating and sets the order", () => {
    const plan = planDrop({ ...floatRow(1, 2, 3), from: 1, slot: 3, zone: "tile", join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.actions, [focus(301), TILE(301), FIRST, AT(2)]);
    assert.deepEqual(plan.floatingOrder, [300]);
    assert.deepEqual(plan.order, [300, "separator", 100, 301, 101, 102]);
});

test("a floating source joining a stack reports the tile it lands on", () => {
    const plan = planDrop({ ...floatRow(1, 2, 2), from: 1, slot: 3, zone: "tile", join: true, joinKey: "1:2", moved: true, atHome: false });
    assert.deepEqual(plan.actions, [focus(301), TILE(301), FIRST, AT(2), CR, UP, UP]);
    assert.equal(plan.onto, 4);
    assert.equal(plan.above, true);
    assert.deepEqual(plan.floatingOrder, [300]);
    assert.deepEqual(plan.order, [300, "separator", 100, 301, 101, 102]);
});

test("a floating source released at home only focuses", () => {
    const plan = planDrop({ ...floatRow(1, 2, 3), from: 1, slot: 1, zone: "float", join: false, joinKey: "", moved: false, atHome: true });
    assert.deepEqual(plan.actions, [focus(301)]);
    assert.equal(plan.order, null);
});

// ---- floating zone ----
// Floating windows 300 and 301, the gap, tiled columns 1..3.
const zoneRow = () => floatRow(1, 2, 3);
const FLOAT = id => ({ "MoveWindowToFloating": { "id": id } });

test("a floating icon reordered among the floating icons sends only focus", () => {
    const plan = planDrop({ ...zoneRow(), from: 0, slot: 1, zone: "float", join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.actions, [focus(300)]);
    assert.deepEqual(plan.floatingOrder, [301, 300]);
    assert.equal(plan.order, null);
});

test("a tiled window dropped in the floating zone is floated at that place", () => {
    const plan = planDrop({ ...zoneRow(), from: 4, slot: 1, zone: "float", join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.actions, [focus(101), FLOAT(101)]);
    assert.deepEqual(plan.floatingOrder, [300, 101, 301]);
    assert.deepEqual(plan.order, [300, 101, 301, "separator", 100, 102]);
});

test("a tiled window dropped off the dock lands last among the floating icons", () => {
    const plan = planDrop({ ...zoneRow(), from: 3, slot: 2, zone: "float", join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.floatingOrder, [300, 301, 100]);
    assert.deepEqual(plan.order, [300, 301, 100, "separator", 101, 102]);
});

test("floating the first window creates the gap in the predicted row", () => {
    const r = { keys: ["1:1", "1:2"], ws: [1, 1], ids: [100, 101], kinds: ["tile", "tile"], sepId: "separator" };
    const plan = planDrop({ ...r, from: 1, slot: 0, zone: "float", join: false, joinKey: "", moved: true, atHome: false });
    assert.deepEqual(plan.actions, [focus(101), FLOAT(101)]);
    assert.deepEqual(plan.order, [101, "separator", 100]);
});

test("the last floating window tiled removes the gap from the predicted row", () => {
    const r = { keys: [null, null, "1:1", "1:2"], ws: [1, null, 1, 1], ids: [300, "separator", 100, 101], kinds: ["float", "sep", "tile", "tile"], sepId: "separator" };
    const plan = planDrop({ ...r, from: 0, slot: 2, zone: "tile", join: false, joinKey: "", moved: true, atHome: false });
    assert.equal(plan.actions[1].MoveWindowToTiling.id, 300);
    assert.deepEqual(plan.actions[3], { "MoveColumnToIndex": { "index": 2 } });
    assert.deepEqual(plan.floatingOrder, []);
    assert.deepEqual(plan.order, [100, 300, 101]);
});
