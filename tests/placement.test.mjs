import { test } from "node:test";
import assert from "node:assert/strict";
import { barAttachments, barZoneOnEdge } from "../lib/placement.mjs";

const bar = (extra) => ({ "enabled": true, "visible": true, "position": 1, "spacing": 4, "bottomGap": 0, "innerPadding": 4, ...extra });

test("bars on the dock's edge and screen push it outward, others do not", () => {
    const configs = [bar({}), bar({ "position": 0 }), bar({ "autoHide": true }), bar({ "visible": false }), bar({ "enabled": false })];
    assert.equal(barZoneOnEdge(configs, "bottom", () => true, () => 40), 44);
    assert.equal(barZoneOnEdge(configs, "top", () => true, () => 40), 44);
    assert.equal(barZoneOnEdge(configs, "left", () => true, () => 40), 0);
    assert.equal(barZoneOnEdge(configs, "bottom", () => false, () => 40), 0);
});

test("bars stacked on one edge add up, with their gaps", () => {
    const configs = [bar({ "spacing": 0 }), bar({ "spacing": 2, "bottomGap": 6 })];
    assert.equal(barZoneOnEdge(configs, "bottom", () => true, () => 30), 30 + 38);
});

test("island bars take no space on their edge", () => {
    const configs = [bar({ "island": true }), bar({ "spacing": 2 })];
    assert.equal(barZoneOnEdge(configs, "bottom", () => true, () => 30), 32);
    assert.equal(barZoneOnEdge([bar({ "island": true })], "bottom", () => true, () => 30), 0);
});

test("the widget is found in any section of any enabled bar", () => {
    const configs = [
        { "name": "Main Bar", "centerWidgets": [{ "id": "marina", "enabled": true }], "leftWidgets": ["clock"] },
        { "name": "Side", "position": 2, "rightWidgets": ["marina"] },
        { "name": "Off", "enabled": false, "centerWidgets": ["marina"] },
        { "name": "Hidden entry", "leftWidgets": [{ "id": "marina", "enabled": false }] }
    ];
    assert.deepEqual(barAttachments(configs, "marina"), [{ "bar": "Main Bar", "section": "center", "vertical": false }, { "bar": "Side", "section": "right", "vertical": true }]);
    assert.deepEqual(barAttachments([], "marina"), []);
});
