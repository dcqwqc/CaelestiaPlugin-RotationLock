// Bottom-left on-screen-keyboard handle.
//
// Why this exists at all: the natural gesture for the keyboard is a swipe up
// from the bottom-left, and hyprgrass cannot express it. Its edge binds match
// on an edge *bitmask* only (Gestures.cpp find_swipe_edges), never on where
// along the edge the swipe started, and its Lua API rejects a combined origin
// outright (main.cpp: "expected a single direction"). So the whole bottom edge
// is the smallest thing it can bind -- and that edge already belongs to
// Caelestia: the launcher owns the centre, utilities the right corner.
//
// Caelestia does the region test itself, in QML, because it can (Interactions
// .qml: inBottomPanel + withinPanelWidth). This does the same thing: a small
// layer-shell strip that occupies exactly the dead space at the bottom-left,
// on the overlay layer so it sits above caelestia-drawers (which is on top).
//
// The daemon owns its lifetime and its mode. In tablet mode the strip is
// always there: at the bottom of the screen while the keyboard is down (swipe
// up to open it), and riding directly on top of wvkbd while it is up (swipe
// down to put it away). Pull it up, push it down -- the same handle either
// way, which is the only reason a strip this small is discoverable at all.

import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    function envStr(name: string, fallback: string): string {
        const v = Quickshell.env(name);
        return (v === undefined || v === null || v === "") ? fallback : v;
    }

    function envNum(name: string, fallback: real): real {
        const n = parseFloat(root.envStr(name, ""));
        return isNaN(n) ? fallback : n;
    }

    readonly property string tabletBin: envStr("YOGA_HANDLE_BIN", "yoga-tablet")
    readonly property string output: envStr("YOGA_HANDLE_OUTPUT", "")

    // "open" sits on the screen edge and pulls the keyboard up; "close" sits on
    // top of the keyboard and pushes it back down.
    readonly property bool closing: envStr("YOGA_HANDLE_MODE", "open") === "close"
    // In close mode this is the keyboard's height. Keep the handle window
    // immediately ABOVE wvkbd instead of inside its surface: wvkbd may be on
    // the same overlay layer and can otherwise paint over the close handle.
    readonly property real bottomMargin: envNum("YOGA_HANDLE_BOTTOM", 0)

    // Clears Caelestia's left bar, which reserves 60px, so the strip never
    // shadows it.
    readonly property real leftMargin: envNum("YOGA_HANDLE_LEFT", 68)
    readonly property real barWidth: envNum("YOGA_HANDLE_WIDTH", 190)
    readonly property real barHeight: envNum("YOGA_HANDLE_HEIGHT", 26)

    readonly property color grabColour: envStr("YOGA_HANDLE_COLOUR", "#c8c5d0")
    readonly property color grabActiveColour: envStr("YOGA_HANDLE_COLOUR_ACTIVE", "#e6e0e9")

    // A swipe this far counts; anything shorter is treated as a tap. Both do
    // the same thing, so this only decides how early it fires.
    readonly property real dragThreshold: envNum("YOGA_HANDLE_THRESHOLD", 18)

    PanelWindow {
        id: win

        screen: {
            if (root.output === "")
                return null;
            for (const s of Quickshell.screens)
                if (s.name === root.output)
                    return s;
            return null;
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yoga-osk-handle"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.left: true
        anchors.bottom: true
        margins.left: root.leftMargin
        margins.bottom: root.bottomMargin

        implicitWidth: root.barWidth
        implicitHeight: root.barHeight

        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        property bool armed: false

        function trigger(): void {
            if (win.armed)
                return;
            win.armed = true;
            Quickshell.execDetached([root.tabletBin, "osk", root.closing ? "hide" : "show"]);
            disarm.restart();
        }

        Timer {
            id: disarm

            interval: 700
            onTriggered: win.armed = false
        }

        Rectangle {
            id: grab

            anchors.horizontalCenter: parent.horizontalCenter
            // In close mode the whole window sits just above the keyboard, so
            // keep the grabber along its bottom edge. In open mode it stays on
            // the screen's bottom edge as before.
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7

            width: area.pressed ? parent.width * 0.7 : parent.width * 0.55
            height: area.pressed ? 6 : 5
            radius: height / 2
            color: area.pressed ? root.grabActiveColour : root.grabColour
            opacity: area.pressed ? 1 : 0.65

            Behavior on width {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent

            property real pressY

            onPressed: event => pressY = event.y
            // Fires as soon as the swipe is long enough, so the keyboard is
            // already moving while the finger still is.
            onPositionChanged: event => {
                if (!pressed)
                    return;
                const travelled = root.closing ? event.y - pressY : pressY - event.y;
                if (travelled >= root.dragThreshold)
                    win.trigger();
            }
            // A plain tap works too -- the strip is small and deliberate
            // enough that touching it can only mean one thing.
            onReleased: win.trigger()
        }
    }
}
