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
import Quickshell.Io

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
    readonly property string actionBin: envStr("YOGA_OSK_ACTION", "")
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

    // The toolbar is drawn over a deliberately blank native wvkbd row.  It is
    // therefore inside wvkbd's exclusive zone rather than being another
    // overlay that covers applications above the keyboard.
    readonly property bool toolbarVisible: closing && envStr("YOGA_TOOLBAR_ENABLED", "1") === "1"
    readonly property bool clipboardEnabled: envStr("YOGA_CLIPBOARD_ENABLED", "1") === "1"
    readonly property real oskPadding: envNum("YOGA_OSK_PADDING", 8)
    readonly property int keyboardRows: (win.screen !== null && win.screen.height > win.screen.width) ? 6 : 5
    // wvkbd divides the usable height evenly across its rows. Fill the complete
    // reserved first row with the toolbar surface so there is no dead strip,
    // while keeping the controls themselves Gboard-compact in the centre.
    readonly property real toolbarHeight: closing && bottomMargin > 0
        ? Math.max(42, (bottomMargin - oskPadding * 2) / keyboardRows)
        : 42
    readonly property real toolbarButtonHeight: Math.min(44, Math.max(34, toolbarHeight - 12))
    readonly property real toolbarBottom: Math.max(0, bottomMargin - toolbarHeight)
    readonly property color toolbarSurface: envStr("YOGA_TOOLBAR_SURFACE", "#24232a")
    readonly property color toolbarKey: envStr("YOGA_TOOLBAR_KEY", "#34323b")
    readonly property color toolbarText: envStr("YOGA_TOOLBAR_TEXT", "#f0edf5")
    property string pane: "keyboard"
    property var clipItems: []
    property bool clipboardAvailable: false

    function runToolbar(action: string): void {
        if (action === "Keyboard") {
            root.pane = "keyboard";
            Quickshell.execDetached([root.tabletBin, "toolbar", "keyboard"]);
        } else if (action === "Clipboard") {
            root.pane = root.pane === "clipboard" ? "keyboard" : "clipboard";
            if (root.pane === "clipboard")
                clipboardList.running = true;
        } else if (action === "Emoji") {
            root.pane = root.pane === "emoji" ? "keyboard" : "emoji";
        } else if (action === "Tools") {
            root.pane = "keyboard";
            Quickshell.execDetached([root.tabletBin, "toolbar", "tools"]);
        } else if (action === "Protocol7") {
            if (root.actionBin !== "")
                Quickshell.execDetached([root.actionBin, "protocol7"]);
        } else if (action === "Hide") {
            root.pane = "keyboard";
            Quickshell.execDetached([root.tabletBin, "osk", "hide"]);
        }
    }

    Process {
        id: clipboardList
        command: root.actionBin === "" ? [] : [root.actionBin, "clipboard-list"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                try {
                    const result = JSON.parse(data);
                    root.clipboardAvailable = result.available === true;
                    root.clipItems = Array.isArray(result.items) ? result.items : [];
                } catch (_) {
                    root.clipboardAvailable = false;
                    root.clipItems = [];
                }
            }
        }
    }

    PanelWindow {
        id: toolbar
        visible: root.toolbarVisible
        screen: win.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yoga-osk-toolbar"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.left: true
        anchors.right: true
        anchors.bottom: true
        margins.bottom: root.toolbarBottom
        implicitHeight: root.toolbarHeight
        exclusionMode: ExclusionMode.Ignore
        color: root.toolbarSurface

        Row {
            anchors.centerIn: parent
            spacing: 6
            Repeater {
                model: root.clipboardEnabled
                       ? ["Keyboard", "Clipboard", "Emoji", "Tools", "Protocol7", "Hide"]
                       : ["Keyboard", "Emoji", "Tools", "Protocol7", "Hide"]
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool active: (modelData === "Clipboard" && root.pane === "clipboard")
                                                 || (modelData === "Emoji" && root.pane === "emoji")
                    width: Math.max(64, label.implicitWidth + 22)
                    height: root.toolbarButtonHeight
                    radius: height / 2
                    color: active || button.pressed ? root.toolbarText : root.toolbarKey
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: modelData
                        color: active || button.pressed ? root.toolbarSurface : root.toolbarText
                        font.pixelSize: 13
                        font.family: "Rubik, Noto Color Emoji, sans-serif"
                    }
                    MouseArea {
                        id: button
                        anchors.fill: parent
                        onClicked: root.runToolbar(modelData)
                    }
                }
            }
        }
    }

    PanelWindow {
        id: auxiliaryPane
        visible: root.toolbarVisible && root.pane !== "keyboard"
        screen: win.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yoga-osk-auxiliary"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.left: true
        anchors.right: true
        anchors.bottom: true
        margins.bottom: Math.max(0, root.toolbarBottom - implicitHeight)
        implicitHeight: 148
        exclusionMode: ExclusionMode.Ignore
        color: root.toolbarSurface

        Item {
            anchors.fill: parent
            visible: root.pane === "clipboard"
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.top: parent.top
                anchors.topMargin: 8
                text: root.clipboardAvailable ? "Clipboard history" : "Clipboard history is unavailable"
                color: root.toolbarText
                font.pixelSize: 13
            }
            ListView {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 8
                anchors.topMargin: 30
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: root.clipItems
                delegate: Rectangle {
                    required property var modelData
                    width: Math.min(220, Math.max(112, preview.implicitWidth + 24))
                    height: parent.height
                    radius: 10
                    color: pasteArea.pressed ? root.toolbarText : root.toolbarKey
                    Text {
                        id: preview
                        anchors.fill: parent
                        anchors.margins: 9
                        text: modelData.preview
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        color: pasteArea.pressed ? root.toolbarSurface : root.toolbarText
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: pasteArea
                        anchors.fill: parent
                        onClicked: {
                            if (root.actionBin !== "")
                                Quickshell.execDetached([root.actionBin, "clipboard-paste", modelData.id]);
                            root.pane = "keyboard";
                        }
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: root.pane === "emoji"
            Grid {
                anchors.centerIn: parent
                columns: 12
                spacing: 6
                Repeater {
                    model: ["😀", "😂", "😍", "🥳", "👍", "👎", "🙏", "❤️", "🔥", "🎉", "✅", "❌",
                            "🤔", "👏", "🚀", "💡", "📌", "📎", "✅", "⚠️", "✨", "🌍", "☕", "💻"]
                    delegate: Rectangle {
                        required property string modelData
                        width: 38
                        height: 38
                        radius: 9
                        color: emojiArea.pressed ? root.toolbarText : root.toolbarKey
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 21
                            font.family: "Noto Color Emoji, Twemoji Mozilla, sans-serif"
                        }
                        MouseArea {
                            id: emojiArea
                            anchors.fill: parent
                            onClicked: {
                                if (root.actionBin !== "")
                                    Quickshell.execDetached([root.actionBin, "emoji", modelData]);
                            }
                        }
                    }
                }
            }
        }
    }

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
