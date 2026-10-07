import { test } from "node:test";
import assert from "node:assert/strict";
import { defaults, normalize } from "../lib/settings.mjs";

test("missing settings use the defaults", () => {
    assert.deepEqual(normalize(undefined), defaults);
    assert.deepEqual(normalize({}), defaults);
});

test("values are clamped to their ranges", () => {
    const s = normalize({ maxIconPx: 500, radiusItems: 0, animationMs: -5 });
    assert.equal(s.maxIconPx, 128);
    assert.equal(s.radiusItems, 1);
    assert.equal(s.animationMs, 0);
});

test("max icon size takes only multiples of 8", () => {
    assert.equal(normalize({ maxIconPx: 100 }).maxIconPx, 104);
    assert.equal(normalize({ maxIconPx: 99 }).maxIconPx, 96);
    assert.equal(normalize({ maxIconPx: 20 }).maxIconPx, 24);
    assert.equal(normalize({ maxIconPx: 10 }).maxIconPx, 16);
    assert.equal(normalize({ maxIconPx: 128 }).maxIconPx, 128);
});

test("numeric strings are accepted, garbage falls back to the default", () => {
    const s = normalize({ maxIconPx: "48", radiusItems: "wide", animationMs: null });
    assert.equal(s.maxIconPx, 48);
    assert.equal(s.radiusItems, 3);
    assert.equal(s.animationMs, 220);
});

test("zero is a valid animation duration", () => {
    assert.equal(normalize({ animationMs: 0 }).animationMs, 0);
});

test("flags accept booleans and their string forms only", () => {
    assert.equal(normalize({ magnifyEnabled: false }).magnifyEnabled, false);
    assert.equal(normalize({ magnifyEnabled: "false" }).magnifyEnabled, false);
    assert.equal(normalize({ debugLog: 1 }).debugLog, false);
});

test("placement and edge accept only known choices", () => {
    assert.equal(normalize({ placement: "bar" }).placement, "bar");
    assert.equal(normalize({ placement: "sky" }).placement, "edge");
    assert.equal(normalize({ edge: "left" }).edge, "left");
    assert.equal(normalize({ edge: "middle" }).edge, "bottom");
});

test("edge offset is clamped and edge filters default sensibly", () => {
    assert.equal(normalize({ edgeOffset: 500 }).edgeOffset, 64);
    assert.equal(normalize({ edgeOffset: -5 }).edgeOffset, 0);
    const s = normalize({});
    assert.equal(s.reserveSpace, true);
    assert.equal(s.autoHide, false);
    assert.equal(normalize({ autoHide: "true" }).autoHide, true);
    assert.equal(s.currentWorkspace, true);
    assert.equal(s.currentMonitor, true);
    assert.equal(s.groupByApp, false);
});

test("min icon size takes multiples of 8 from 16 to 128", () => {
    assert.equal(normalize({}).minIconPx, 24);
    assert.equal(normalize({ minIconPx: 30 }).minIconPx, 32);
    assert.equal(normalize({ minIconPx: 8 }).minIconPx, 16);
    assert.equal(normalize({ minIconPx: 100 }).minIconPx, 104);
    assert.equal(normalize({ minIconPx: 500 }).minIconPx, 128);
});
