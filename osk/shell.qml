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

    // The first native wvkbd row is intentionally blank and becomes this
    // Gboard-style utility row. The auxiliary panes occupy the rest of the
    // keyboard footprint and fully cover the native keys without stopping them.
    readonly property bool toolbarVisible: closing && envStr("YOGA_TOOLBAR_ENABLED", "1") === "1"
    readonly property bool clipboardEnabled: envStr("YOGA_CLIPBOARD_ENABLED", "1") === "1"
    readonly property real oskPadding: envNum("YOGA_OSK_PADDING", 8)
    readonly property int keyboardRows: (win.screen !== null && win.screen.height > win.screen.width) ? 6 : 5
    readonly property real toolbarHeight: closing && bottomMargin > 0
        ? Math.max(42, (bottomMargin - oskPadding * 2) / keyboardRows)
        : 42
    readonly property real toolbarButtonHeight: Math.min(42, Math.max(34, toolbarHeight - 14))
    readonly property real toolbarBottom: Math.max(0, bottomMargin - toolbarHeight)
    readonly property color toolbarSurface: envStr("YOGA_TOOLBAR_SURFACE", "#1b1b1f")
    readonly property color toolbarKey: envStr("YOGA_TOOLBAR_KEY", "#303034")
    readonly property color toolbarText: envStr("YOGA_TOOLBAR_TEXT", "#f4f0f6")
    readonly property color toolbarMuted: envStr("YOGA_TOOLBAR_MUTED", "#c9c5ca")

    property string pane: "keyboard"
    property string nativeLayer: "keyboard"
    property string paneQuery: ""
    property bool searchActive: false
    property string emojiCategory: "all"
    property var clipItems: []
    property bool clipboardAvailable: false
    property var emojiItems: []
    property var emojiNext: null
    property var historyItems: []

    readonly property var toolbarButtons: {
        const buttons = [
            { id: "keyboard", icon: "keyboard" }
        ];
        if (root.clipboardEnabled)
            buttons.push({ id: "clipboard", icon: "content_paste" });
        buttons.push(
            { id: "emoji", icon: "emoji_emotions" },
            { id: "tools", icon: "keyboard_command_key" },
            { id: "history", icon: "history" },
            { id: "mic", icon: "mic" }
        );
        return buttons;
    }
    readonly property var emojiCategories: [
        { id: "all", icon: "apps" },
        { id: "people", icon: "sentiment_satisfied" },
        { id: "animals", icon: "pets" },
        { id: "nature", icon: "local_florist" },
        { id: "food", icon: "restaurant" },
        { id: "activity", icon: "sports_soccer" },
        { id: "travel", icon: "flight" },
        { id: "objects", icon: "lightbulb" },
        { id: "symbols", icon: "favorite" },
        { id: "flags", icon: "flag" }
    ]

    function toolbarActive(id: string): bool {
        if (id === "keyboard")
            return root.pane === "keyboard" && root.nativeLayer === "keyboard";
        if (id === "tools")
            return root.pane === "keyboard" && root.nativeLayer === "tools";
        return root.pane === id;
    }

    function openPane(nextPane: string): void {
        root.paneQuery = "";
        root.searchActive = false;
        root.pane = nextPane;
        paneRefresh.restart();
    }

    function runToolbar(action: string): void {
        if (action === "keyboard") {
            root.pane = "keyboard";
            root.nativeLayer = "keyboard";
            root.searchActive = false;
            Quickshell.execDetached([root.tabletBin, "toolbar", "keyboard"]);
        } else if (action === "tools") {
            root.pane = "keyboard";
            root.nativeLayer = "tools";
            root.searchActive = false;
            Quickshell.execDetached([root.tabletBin, "toolbar", "tools"]);
        } else if (action === "clipboard" || action === "emoji" || action === "history") {
            root.openPane(action);
        } else if (action === "mic") {
            if (root.actionBin !== "")
                Quickshell.execDetached([root.actionBin, "protocol7"]);
            keepKeyboardVisible.restart();
        }
    }

    function refreshPane(): void {
        if (root.actionBin === "" || root.pane === "keyboard")
            return;
        if (root.pane === "clipboard") {
            if (!clipboardList.running) {
                clipboardList.command = [root.actionBin, "clipboard-list", root.paneQuery];
                clipboardList.running = true;
            }
        } else if (root.pane === "emoji") {
            root.emojiItems = [];
            root.emojiNext = null;
            if (!emojiList.running) {
                emojiList.command = [root.actionBin, "emoji-list", root.emojiCategory, root.paneQuery, "0"];
                emojiList.running = true;
            }
        } else if (root.pane === "history") {
            if (!historyList.running) {
                historyList.command = [root.actionBin, "dictation-list", root.paneQuery];
                historyList.running = true;
            }
        }
    }

    function loadMoreEmoji(): void {
        if (root.pane !== "emoji" || root.actionBin === "" || root.emojiNext === null || emojiList.running)
            return;
        emojiList.command = [root.actionBin, "emoji-list", root.emojiCategory, root.paneQuery, String(root.emojiNext)];
        emojiList.running = true;
    }

    onPaneQueryChanged: searchDebounce.restart()
    onEmojiCategoryChanged: {
        if (root.pane === "emoji")
            searchDebounce.restart();
    }

    Timer {
        id: searchDebounce
        interval: 130
        repeat: false
        onTriggered: root.refreshPane()
    }

    Timer {
        id: paneRefresh
        interval: 10
        repeat: false
        onTriggered: root.refreshPane()
    }

    Timer {
        id: keepKeyboardVisible
        interval: 180
        repeat: false
        onTriggered: Quickshell.execDetached([root.tabletBin, "osk", "show"])
    }

    Process {
        id: clipboardList
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.clipboardAvailable = result.available === true;
                    root.clipItems = Array.isArray(result.items) ? result.items : [];
                } catch (_) {
                    root.clipboardAvailable = false;
                    root.clipItems = [];
                }
            }
        }
    }

    Process {
        id: emojiList
        running: false
        property int requestedOffset: {
            const value = command.length >= 5 ? parseInt(command[4]) : 0;
            return isNaN(value) ? 0 : value;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    const page = Array.isArray(result.items) ? result.items : [];
                    root.emojiItems = emojiList.requestedOffset === 0
                        ? page
                        : root.emojiItems.concat(page);
                    root.emojiNext = result.next === null || result.next === undefined
                        ? null
                        : Number(result.next);
                } catch (_) {
                    if (emojiList.requestedOffset === 0)
                        root.emojiItems = [];
                    root.emojiNext = null;
                }
            }
        }
    }

    Process {
        id: historyList
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.historyItems = Array.isArray(result.items) ? result.items : [];
                } catch (_) {
                    root.historyItems = [];
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
        margins.left: root.leftMargin
        margins.bottom: root.toolbarBottom
        implicitHeight: root.toolbarHeight
        exclusionMode: ExclusionMode.Ignore
        color: root.toolbarSurface

        Row {
            anchors.centerIn: parent
            spacing: 7

            Repeater {
                model: root.toolbarButtons

                delegate: Item {
                    required property var modelData
                    readonly property bool active: root.toolbarActive(modelData.id)
                    width: 48
                    height: root.toolbarButtonHeight

                    Rectangle {
                        anchors.centerIn: parent
                        width: 42
                        height: 34
                        radius: 17
                        color: parent.active
                            ? root.toolbarKey
                            : (iconArea.pressed ? root.toolbarKey : "transparent")
                        opacity: parent.active ? 1 : (iconArea.pressed ? 0.78 : 1)

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: root.toolbarText
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                        }

                        MouseArea {
                            id: iconArea
                            anchors.fill: parent
                            onClicked: root.runToolbar(modelData.id)
                        }
                    }

                    Rectangle {
                        visible: parent.active
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: 18
                        height: 3
                        radius: 2
                        color: root.toolbarText
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
        margins.left: root.leftMargin
        margins.bottom: 0
        implicitHeight: root.toolbarBottom
        exclusionMode: ExclusionMode.Ignore
        color: root.toolbarSurface

        readonly property real headerHeight: root.pane === "emoji" ? 94 : 54
        readonly property real searchPadHeight: root.searchActive ? Math.max(150, height * 0.44) : 0

        Rectangle {
            id: searchBox
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 8
            height: 38
            radius: 19
            color: root.toolbarKey

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 13
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                color: root.toolbarMuted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 19
            }

            TextInput {
                id: searchInput
                anchors.left: parent.left
                anchors.right: clearSearch.left
                anchors.leftMargin: 42
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.paneQuery
                readOnly: true
                color: root.toolbarText
                font.pixelSize: 14
                clip: true
                selectByMouse: false

                Text {
                    visible: root.paneQuery.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pane === "emoji"
                        ? "Search emojis"
                        : root.pane === "history" ? "Search dictation history" : "Search clipboard"
                    color: root.toolbarMuted
                    font.pixelSize: 14
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.searchActive = true
                }
            }

            Item {
                id: clearSearch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 7
                width: 32
                height: 32

                Text {
                    anchors.centerIn: parent
                    text: root.paneQuery.length ? "close" : "search"
                    color: root.toolbarMuted
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.paneQuery.length)
                            root.paneQuery = "";
                        else
                            root.searchActive = true;
                    }
                }
            }
        }

        ListView {
            id: emojiCategoryBar
            visible: root.pane === "emoji"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: searchBox.bottom
            anchors.topMargin: 4
            height: 42
            orientation: ListView.Horizontal
            spacing: 4
            clip: true
            leftMargin: 10
            rightMargin: 10
            model: root.emojiCategories

            delegate: Rectangle {
                required property var modelData
                width: 42
                height: 34
                radius: 17
                color: root.emojiCategory === modelData.id ? root.toolbarKey : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: modelData.icon
                    color: root.toolbarText
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 19
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.emojiCategory = modelData.id;
                        root.emojiItems = [];
                        root.emojiNext = null;
                    }
                }
            }
        }

        Item {
            id: resultsArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: auxiliaryPane.headerHeight
            anchors.bottom: searchPad.top
            clip: true

            Item {
                anchors.fill: parent
                visible: root.pane === "clipboard"

                Text {
                    visible: !root.clipboardAvailable || root.clipItems.length === 0
                    anchors.centerIn: parent
                    text: root.clipboardAvailable ? "No clipboard matches" : "Clipboard history unavailable"
                    color: root.toolbarMuted
                    font.pixelSize: 14
                }

                ListView {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 8
                    spacing: 7
                    clip: true
                    model: root.clipItems

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: Math.max(56, clipPreview.implicitHeight + 20)
                        radius: 12
                        color: clipArea.pressed ? root.toolbarKey : Qt.rgba(1, 1, 1, 0.035)

                        Text {
                            id: clipPreview
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 12
                            text: modelData.preview
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: root.toolbarText
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: clipArea
                            anchors.fill: parent
                            onClicked: {
                                if (root.actionBin !== "")
                                    Quickshell.execDetached([root.actionBin, "clipboard-paste", modelData.id]);
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.pane === "emoji"

                Text {
                    visible: root.emojiItems.length === 0 && !emojiList.running
                    anchors.centerIn: parent
                    text: "No emoji matches"
                    color: root.toolbarMuted
                    font.pixelSize: 14
                }

                GridView {
                    id: emojiGrid
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.bottomMargin: 8
                    clip: true
                    cellWidth: 50
                    cellHeight: 50
                    model: root.emojiItems

                    onContentYChanged: {
                        if (contentY + height >= contentHeight - 140)
                            root.loadMoreEmoji();
                    }

                    delegate: Rectangle {
                        required property var modelData
                        width: 44
                        height: 44
                        radius: 11
                        color: emojiArea.pressed ? root.toolbarKey : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.emoji
                            font.pixelSize: 25
                            font.family: "Noto Color Emoji"
                        }

                        MouseArea {
                            id: emojiArea
                            anchors.fill: parent
                            onClicked: {
                                if (root.actionBin !== "")
                                    Quickshell.execDetached([root.actionBin, "emoji", modelData.emoji]);
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.pane === "history"

                Text {
                    visible: root.historyItems.length === 0 && !historyList.running
                    anchors.centerIn: parent
                    text: "No dictation history matches"
                    color: root.toolbarMuted
                    font.pixelSize: 14
                }

                ListView {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 8
                    spacing: 7
                    clip: true
                    model: root.historyItems

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: Math.max(70, historyText.implicitHeight + 34)
                        radius: 12
                        color: historyArea.pressed ? root.toolbarKey : Qt.rgba(1, 1, 1, 0.035)

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 8
                            text: new Date(modelData.timestamp * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat)
                            color: root.toolbarMuted
                            font.pixelSize: 11
                        }

                        Text {
                            id: historyText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.bottomMargin: 9
                            text: modelData.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            color: root.toolbarText
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: historyArea
                            anchors.fill: parent
                            onClicked: {
                                if (root.actionBin !== "")
                                    Quickshell.execDetached([
                                        root.actionBin,
                                        "dictation-insert",
                                        String(modelData.id),
                                        String(modelData.timestamp)
                                    ]);
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: searchPad
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: auxiliaryPane.searchPadHeight
            visible: root.searchActive
            clip: true

            Rectangle {
                anchors.fill: parent
                color: root.toolbarSurface
            }

            Column {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 7
                anchors.bottomMargin: 7
                spacing: 5

                Repeater {
                    model: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

                    delegate: Row {
                        required property string modelData
                        width: parent.width
                        height: (searchPad.height - 43 - 29) / 3
                        spacing: 4
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: modelData.length

                            delegate: Rectangle {
                                required property int index
                                width: (parent.width - (modelData.length - 1) * parent.spacing) / modelData.length
                                height: parent.height
                                radius: 8
                                color: letterArea.pressed ? root.toolbarText : root.toolbarKey

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.charAt(index)
                                    color: letterArea.pressed ? root.toolbarSurface : root.toolbarText
                                    font.pixelSize: 15
                                }

                                MouseArea {
                                    id: letterArea
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.paneQuery.length < 96)
                                            root.paneQuery += modelData.charAt(index);
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 38
                    spacing: 5

                    Repeater {
                        model: [
                            { id: "clear", label: "Clear", weight: 1.0 },
                            { id: "space", label: "Space", weight: 2.2 },
                            { id: "backspace", label: "⌫", weight: 1.0 },
                            { id: "done", label: "Done", weight: 1.0 }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property real unitWidth: (parent.width - parent.spacing * 3) / 5.2
                            width: unitWidth * modelData.weight
                            height: parent.height
                            radius: 9
                            color: actionArea.pressed ? root.toolbarText : root.toolbarKey

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: actionArea.pressed ? root.toolbarSurface : root.toolbarText
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: actionArea
                                anchors.fill: parent
                                onClicked: {
                                    if (modelData.id === "clear") {
                                        root.paneQuery = "";
                                    } else if (modelData.id === "space") {
                                        if (root.paneQuery.length < 96)
                                            root.paneQuery += " ";
                                    } else if (modelData.id === "backspace") {
                                        root.paneQuery = root.paneQuery.slice(0, -1);
                                    } else if (modelData.id === "done") {
                                        root.searchActive = false;
                                    }
                                }
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
