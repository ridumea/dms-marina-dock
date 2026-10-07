# Contributing to Marina Dock

## Layout

- `MarinaWidget.qml`: the dock, used both as the bar widget and inside the
  edge dock (`MarinaEdgeDock.qml`, created by `MarinaDaemon.qml`).
- `MarinaOverlay.qml`: the magnified row, drawn in a window over the dock.
- `MarinaDelegate.qml`: one icon. `MarinaDragGhost.qml`: an icon dragged off
  the dock.
- `MarinaSettings.qml`: the settings page.
- `lib/`: the logic, free of Qt and DMS (geometry, drop targeting, niri
  actions, row order, settings), tested in `tests/`.

## Developing

```sh
node --test tests/*.test.mjs   # tests
tools/lint.sh                  # qmllint and qmlformat check (--fix to format)
dms restart                    # load your changes
```

Lint needs DMS, Quickshell and Qt's QML tools installed. CI runs tests and
lint on every push and pull request.

`dms ipc call marina debug on|off` logs each drop to the DMS journal.

To translate, add a `translations/<locale>.json` next to `plugin.json`, as the
DMS plugin guide describes.

## Branches and commits

Work on `dev` and open pull requests against it. `main` holds only the latest
release, since DMS installs and updates the plugin from it. Commits must be
signed.

## Releases

Run the **Release** workflow on `dev` from the Actions tab and choose `patch`,
`minor` or `major` ([Semantic Versioning](https://semver.org)). It checks the
code, bumps the version on `dev`, moves `main` to it, tags the release and
publishes release notes.

## Known limitations

- Dragging a window to another workspace or monitor is not supported.
