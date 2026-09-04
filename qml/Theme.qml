pragma Singleton

import QtQuick

// One place for the palette and the handful of metrics the UI repeats.
// Touch targets are 44px because that is roughly a fingertip on this panel;
// nothing interactive is allowed to be smaller.
QtObject {
    readonly property color background: "#0b0b0f"
    readonly property color surface: "#16161d"
    readonly property color surfaceHigh: "#20202b"
    readonly property color overlay: Qt.rgba(0.05, 0.05, 0.07, 0.86)
    readonly property color text: "#e9e9f2"
    readonly property color textDim: "#9b9bad"
    readonly property color accent: "#7c5cff"
    readonly property color accent2: "#2ad0c8"
    readonly property color danger: "#ff6b6b"
    readonly property color line: Qt.rgba(1, 1, 1, 0.09)

    readonly property int touch: 44
    readonly property int radius: 12
    readonly property int pad: 12
    readonly property int fontSm: 12
    readonly property int fontMd: 14
    readonly property int fontLg: 18

    readonly property int anim: 160
}
