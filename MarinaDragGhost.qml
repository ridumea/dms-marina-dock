pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Mapped when the icon lifts, before the pointer can leave the dock; draws the icon once the pointer is off it.
PanelWindow { // qmllint disable uncreatable-type
    id: ghostWindow

    required property var dock

    screen: ghostWindow.dock.parentScreen
    color: "transparent"
    visible: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dms:marina-drag"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // No input: the drag's pointer grab stays with the icon in the overlay.
    mask: Region {}

    Image {
        readonly property real pointerX: ghostWindow.dock.isVerticalOrientation ? (ghostWindow.dock.edgeIsFar ? ghostWindow.width - ghostWindow.dock.edgeMargin - ghostWindow.dock.dragCross : ghostWindow.dock.edgeMargin + ghostWindow.dock.dragCross) : ghostWindow.dock.dragPointer
        readonly property real pointerY: ghostWindow.dock.isVerticalOrientation ? ghostWindow.dock.dragPointer : (ghostWindow.dock.edgeIsFar ? ghostWindow.height - ghostWindow.dock.edgeMargin - ghostWindow.dock.dragCross : ghostWindow.dock.edgeMargin + ghostWindow.dock.dragCross)
        visible: ghostWindow.dock.dragOutside && source !== ""
        source: ghostWindow.dock.dragIconSource
        width: ghostWindow.dock.iconBase * ghostWindow.dock.maxScale
        height: width
        sourceSize: Qt.size(ghostWindow.dock.iconMaxPx, ghostWindow.dock.iconMaxPx)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        // Dimmed: dropping it here floats the window.
        opacity: 0.55
        x: pointerX - width / 2
        y: pointerY - height / 2
    }
}
