#!/usr/bin/env bash
# Lint and format-check the plugin's QML against installed DMS and Quickshell.
#
#   tools/lint.sh          report problems, exit non-zero if any
#   tools/lint.sh --fix    apply qmlformat in place, then lint
#
# Environment:
#   DMS_DIR     DMS shell sources (default /usr/share/quickshell/dms)
#   QT_QML_DIR  Qt QML import directory holding Quickshell's type info
#               (default: as qtpaths6 reports it, else /usr/lib64/qt6/qml)
#   QMLLINT, QMLFORMAT  tool paths (default: PATH, then Qt's bin directory)
#
# Needs qmllint and qmlformat: qt6-qtdeclarative-devel on Fedora,
# qt6-declarative-dev-tools on Debian and Ubuntu.
set -euo pipefail

cd "$(dirname "$0")/.."

# Qt's own install paths; Fedora and Debian-based systems put Qt in
# different places.
QTPATHS=$(command -v qtpaths6 2>/dev/null || true)
for dir in /usr/lib/qt6/bin /usr/lib64/qt6/bin; do
    [ -z "$QTPATHS" ] && [ -x "$dir/qtpaths6" ] && QTPATHS="$dir/qtpaths6"
done
qt_path() {
    [ -n "$QTPATHS" ] && "$QTPATHS" --query "$1" 2>/dev/null || true
}
QT_BINS=$(qt_path QT_INSTALL_BINS)
QT_BINS=${QT_BINS:-/usr/lib64/qt6/bin}
QT_QML=$(qt_path QT_INSTALL_QML)

# Debian and Ubuntu's package puts DMS one level deeper.
if [ -z "${DMS_DIR:-}" ]; then
    DMS_DIR=/usr/share/quickshell/dms
    [ -d "$DMS_DIR/Common" ] || [ ! -d "$DMS_DIR/quickshell/Common" ] || DMS_DIR=$DMS_DIR/quickshell
fi
QT_QML_DIR=${QT_QML_DIR:-${QT_QML:-/usr/lib64/qt6/qml}}

find_tool() {
    command -v "$1" 2>/dev/null || { [ -x "$QT_BINS/$1" ] && echo "$QT_BINS/$1"; } || {
        echo "$1 not found; install qt6-qtdeclarative-devel (Fedora) or qt6-declarative-dev-tools (Debian, Ubuntu), or set ${2}" >&2
        exit 2
    }
}
QMLLINT=${QMLLINT:-$(find_tool qmllint QMLLINT)}
QMLFORMAT=${QMLFORMAT:-$(find_tool qmlformat QMLFORMAT)}

[ -d "$DMS_DIR/Common" ] || { echo "DMS sources not found at $DMS_DIR" >&2; exit 2; }

# Quickshell resolves `qs.*` imports to the shell directory at runtime, without
# qmldir files. Mirror the DMS tree with generated qmldir files so qmllint can
# resolve DMS types and report unqualified access.
shim=$(mktemp -d)
trap 'rm -rf "$shim"' EXIT
while IFS= read -r dir; do
    rel=${dir#"$DMS_DIR"}
    rel=${rel#/}
    out="$shim/qs/$rel"
    mkdir -p "$out"
    {
        echo "module qs${rel:+.${rel//\//.}}"
        for f in "$dir"/*; do
            [ -f "$f" ] || continue
            ln -s "$f" "$out/"
            case "$f" in
            *.qml)
                name=$(basename "$f" .qml)
                if grep -q "^pragma Singleton" "$f"; then
                    echo "singleton $name $name.qml"
                else
                    echo "$name $name.qml"
                fi
                ;;
            esac
        done
    } >"$out/qmldir"
done < <(find "$DMS_DIR" -type d -not -path "*/PLUGINS*" -not -path "*/translations*" -not -path "*/assets*")

mapfile -t qml_files < <(find . -name "*.qml" -not -path "./.git/*" | sort)
status=0

if [ "${1:-}" = "--fix" ]; then
    "$QMLFORMAT" -i "${qml_files[@]}"
fi

for f in "${qml_files[@]}"; do
    if ! diff -u "$f" <("$QMLFORMAT" "$f") >/dev/null; then
        echo "$f: not formatted (run tools/lint.sh --fix)"
        status=1
    fi
done

if ! "$QMLLINT" --max-warnings 0 -I "$shim" -I "$QT_QML_DIR" "${qml_files[@]}"; then
    status=1
fi

exit $status
