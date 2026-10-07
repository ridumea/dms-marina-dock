import { test } from "node:test";
import assert from "node:assert/strict";
import { withoutAppSuffix } from "../lib/label.mjs";

test("a trailing app name is dropped", () => {
    assert.equal(withoutAppSuffix("QML Modules | Qt Qml | Qt 6.12.0 - Brave Origin", "Brave Origin"), "QML Modules | Qt Qml | Qt 6.12.0");
    assert.equal(withoutAppSuffix("main.qml - dms-marina - Visual Studio Code", "Visual Studio Code"), "main.qml - dms-marina");
});

test("the name may carry a version, a vendor, or be the short form", () => {
    assert.equal(withoutAppSuffix("Setup Git with SSH - Remote - Obsidian 1.13.7", "Obsidian"), "Setup Git with SSH - Remote");
    assert.equal(withoutAppSuffix("Release notes — Mozilla Firefox", "Firefox"), "Release notes");
    assert.equal(withoutAppSuffix("New Tab - Brave", "Brave Origin"), "New Tab");
});

test("other separators work, case is ignored", () => {
    assert.equal(withoutAppSuffix("Inbox · gmail", "Gmail"), "Inbox");
    assert.equal(withoutAppSuffix("Draft – LibreOffice Writer", "LibreOffice Writer"), "Draft");
});

test("titles that only mention the app elsewhere are kept", () => {
    assert.equal(withoutAppSuffix("Brave Search - Wikipedia", "Brave Origin"), "Brave Search - Wikipedia");
    assert.equal(withoutAppSuffix("Firefox tips - Blog", "Firefox"), "Firefox tips - Blog");
    assert.equal(withoutAppSuffix("Cast - Bravery", "Brave"), "Cast - Bravery");
});

test("nothing is dropped that would leave the title empty or without a separator", () => {
    assert.equal(withoutAppSuffix("Brave Origin", "Brave Origin"), "Brave Origin");
    assert.equal(withoutAppSuffix(" - Brave Origin", "Brave Origin"), "- Brave Origin");
    assert.equal(withoutAppSuffix("Calculator", "Calculator"), "Calculator");
    assert.equal(withoutAppSuffix("", "Files"), "");
    assert.equal(withoutAppSuffix("Downloads - Files", ""), "Downloads - Files");
});
