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

    // The handle process stays resident while tablet mode is active. Its initial
    // environment is only a bootstrap fallback; after the first state-file load,
    // keyboard visibility and geometry follow the daemon live without restarting
    // Quickshell. This lets the toolbar and wvkbd begin the same layer animation.
    readonly property bool envClosing: envStr("YOGA_HANDLE_MODE", "open") === "close"
    readonly property real envBottom: envNum("YOGA_HANDLE_BOTTOM", 0)
    property bool oskStateLoaded: false
    property bool oskStateVisible: false
    property real oskStateInset: 0
    property real lastOskInset: 0
    readonly property bool closing: oskStateLoaded ? oskStateVisible : envClosing
    // In close mode this is the keyboard's height. Keep the handle immediately
    // ABOVE wvkbd instead of inside its surface.
    readonly property real bottomMargin: oskStateLoaded ? oskStateInset : envBottom
    readonly property real targetBottom: envNum("YOGA_OSK_TARGET_BOTTOM", 0)
    readonly property real effectiveBottom: bottomMargin > 0 ? bottomMargin : targetBottom

    IpcHandler {
        target: "yogaOsk"

        function setState(visible: string, inset: string): string {
            root.oskStateVisible = visible === "1";
            const parsed = parseFloat(inset);
            root.oskStateInset = root.oskStateVisible && !isNaN(parsed)
                ? Math.max(0, parsed)
                : 0;
            if (root.oskStateInset > 0)
                root.lastOskInset = root.oskStateInset;
            root.oskStateLoaded = true;
            return "ok";
        }
    }

    FileView {
        id: oskStateFile
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/yoga-tablet-osk.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.oskStateVisible = state.visible === true;
                root.oskStateInset = root.oskStateVisible ? Math.max(0, Number(state.inset) || 0) : 0;
                if (root.oskStateInset > 0)
                    root.lastOskInset = root.oskStateInset;
                root.oskStateLoaded = true;
            } catch (_) {
                root.oskStateLoaded = false;
            }
        }
        onLoadFailed: root.oskStateLoaded = false
    }

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
    readonly property bool toolbarEnabled: envStr("YOGA_TOOLBAR_ENABLED", "1") === "1"
    readonly property bool toolbarVisible: closing && toolbarEnabled
    property bool furnitureReady: false
    readonly property bool toolbarRaised: toolbarVisible && furnitureReady
    readonly property bool clipboardEnabled: envStr("YOGA_CLIPBOARD_ENABLED", "1") === "1"
    readonly property real oskPadding: envNum("YOGA_OSK_PADDING", 8)
    readonly property int keyboardRows: (win.screen !== null && win.screen.height > win.screen.width) ? 6 : 5
    readonly property real toolbarRowWeight: 0.62
    readonly property real toolbarReferenceBottom: effectiveBottom > 0
        ? effectiveBottom
        : (lastOskInset > 0 ? lastOskInset : (keyboardRows === 6 ? 570 : 410))
    readonly property real toolbarHeight: Math.max(
        52,
        ((toolbarReferenceBottom - oskPadding * 2) * toolbarRowWeight
            / (keyboardRows - 1 + toolbarRowWeight)) + oskPadding
    )
    readonly property real toolbarButtonHeight: Math.min(36, Math.max(30, toolbarHeight - 16))
    readonly property real toolbarBottom: Math.max(0, effectiveBottom - toolbarHeight)
    property real toolbarLift: toolbarRaised ? toolbarBottom : -toolbarHeight

    Behavior on toolbarLift {
        NumberAnimation {
            duration: 230
            easing.type: Easing.OutCubic
        }
    }
    readonly property color toolbarSurface: envStr("YOGA_TOOLBAR_SURFACE", "#1b1b1f")
    readonly property color toolbarKey: envStr("YOGA_TOOLBAR_KEY", "#303034")
    readonly property color toolbarText: envStr("YOGA_TOOLBAR_TEXT", "#f4f0f6")
    readonly property color toolbarMuted: envStr("YOGA_TOOLBAR_MUTED", "#c9c5ca")

    property string pane: "keyboard"
    property string nativeLayer: "keyboard"
    property bool pagerTransitioning: false
    property bool pageAFront: true
    property string queuedPane: ""
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
            {
                id: "layer",
                icon: root.pane === "keyboard" && root.nativeLayer === "tools"
                    ? "keyboard"
                    : "keyboard_command_key"
            }
        ];
        if (root.clipboardEnabled)
            buttons.push({ id: "clipboard", icon: "content_paste" });
        buttons.push(
            { id: "emoji", icon: "emoji_emotions" },
            { id: "history", icon: "history" },
            { id: "mic", icon: "mic" }
        );
        return buttons;
    }
    Component.onCompleted: {
        // Map the toolbar surface transparent at the bottom first. On the next
        // frame it may rise with the keyboard, so Hyprland never gets a visible
        // freshly-mapped toolbar to animate in from the side.
        Qt.callLater(() => {
            root.furnitureReady = true;
            Quickshell.execDetached([
                root.tabletBin, "pager", "keyboard-reset", "1", "1"
            ]);
        });
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
        if (id === "layer")
            return root.pane === "keyboard";
        return root.pane === id;
    }

    readonly property int toolbarActiveIndex: {
        for (let i = 0; i < root.toolbarButtons.length; ++i) {
            if (root.toolbarActive(root.toolbarButtons[i].id))
                return i;
        }
        return 0;
    }

    function paneIndex(value: string): int {
        if (value === "clipboard")
            return 1;
        if (value === "emoji")
            return 2;
        if (value === "history")
            return 3;
        return 0;
    }

    function finishPagerTransition(): void {
        const outgoing = root.pageAFront ? pageA : pageB;
        outgoing.animateX = false;
        outgoing.visible = false;
        outgoing.x = 0;
        root.pageAFront = !root.pageAFront;
        root.pagerTransitioning = false;

        if (root.queuedPane !== "") {
            const queued = root.queuedPane;
            root.queuedPane = "";
            if (queued !== root.pane)
                Qt.callLater(() => root.transitionTo(queued));
        }
    }

    function transitionTo(nextPane: string): void {
        if (nextPane !== "keyboard" && nextPane !== "clipboard" &&
                nextPane !== "emoji" && nextPane !== "history")
            return;
        if (root.pagerTransitioning) {
            root.queuedPane = nextPane;
            return;
        }
        if (nextPane === root.pane)
            return;

        root.paneQuery = "";
        root.searchActive = false;

        const oldIndex = root.paneIndex(root.pane);
        const newIndex = root.paneIndex(nextPane);
        const direction = newIndex > oldIndex ? 1 : -1;
        const outgoing = root.pageAFront ? pageA : pageB;
        const incoming = root.pageAFront ? pageB : pageA;
        const travel = Math.max(1, auxiliaryPane.width);
        const keyboardTravel = Math.max(1, travel + root.leftMargin);

        // The native keyboard is a separate layer-shell surface. Move that real
        // surface with the same horizontal curve as the QML pages so keyboard is
        // a first-class member of the cycle rather than a static backdrop.
        if (root.pane === "keyboard" && nextPane !== "keyboard") {
            Quickshell.execDetached([
                root.tabletBin, "pager", "keyboard-out-left",
                String(Math.round(keyboardTravel)), "230"
            ]);
        } else if (root.pane !== "keyboard" && nextPane === "keyboard") {
            Quickshell.execDetached([
                root.tabletBin, "pager", "keyboard-in-left",
                String(Math.round(keyboardTravel)), "230"
            ]);
        }

        outgoing.visible = true;
        outgoing.animateX = false;
        outgoing.x = 0;
        incoming.visible = true;
        incoming.animateX = false;
        incoming.pageMode = nextPane;
        incoming.x = direction * travel;

        root.pane = nextPane;
        paneRefresh.restart();
        root.pagerTransitioning = true;

        Qt.callLater(() => {
            outgoing.animateX = true;
            incoming.animateX = true;
            outgoing.x = -direction * travel;
            incoming.x = 0;
            pagerFinish.restart();
        });
    }

    function runToolbar(action: string): void {
        if (action === "layer") {
            root.searchActive = false;
            if (root.pane !== "keyboard") {
                root.nativeLayer = "keyboard";
                Quickshell.execDetached([root.tabletBin, "toolbar", "keyboard"]);
                root.transitionTo("keyboard");
            } else if (root.nativeLayer === "keyboard") {
                root.nativeLayer = "tools";
                Quickshell.execDetached([root.tabletBin, "toolbar", "tools"]);
            } else {
                root.nativeLayer = "keyboard";
                Quickshell.execDetached([root.tabletBin, "toolbar", "keyboard"]);
            }
        } else if (action === "clipboard" || action === "emoji" || action === "history") {
            root.transitionTo(action);
        } else if (action === "mic") {
            if (root.actionBin !== "")
                Quickshell.execDetached([root.actionBin, "protocol7"]);
            keyboardGuard.remaining = 4;
            keyboardGuard.restart();
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
        id: pagerFinish
        interval: 235
        repeat: false
        onTriggered: root.finishPagerTransition()
    }

    Timer {
        id: keyboardGuard
        property int remaining: 0
        interval: 140
        repeat: true
        onTriggered: {
            Quickshell.execDetached([root.tabletBin, "osk", "show"]);
            remaining -= 1;
            if (remaining <= 0)
                stop();
        }
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
        // Keep this surface mapped for the entire tablet session. It rests
        // transparent at the bottom while the keyboard is closed, then moves
        // vertically with the OSK instead of receiving Hyprland's layer-in slide.
        visible: root.toolbarEnabled
        screen: win.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yoga-osk-toolbar"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.left: true
        anchors.right: true
        anchors.bottom: true
        margins.left: root.leftMargin
        margins.bottom: root.toolbarLift
        implicitHeight: root.toolbarHeight
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: toolbarInputRegion

        Region {
            id: toolbarInputRegion
            width: root.toolbarRaised ? toolbar.width : 0
            height: root.toolbarRaised ? toolbar.height : 0
        }

        Rectangle {
            anchors.fill: parent
            color: root.toolbarSurface
            opacity: root.toolbarRaised ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 90 }
            }
        }

        Item {
            id: toolbarDeck
            anchors.centerIn: parent
            width: toolbarRow.implicitWidth
            height: root.toolbarButtonHeight
            opacity: root.toolbarRaised ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 90 }
            }

            Row {
                id: toolbarRow
                anchors.fill: parent
                spacing: 5

                Repeater {
                    model: root.toolbarButtons

                    delegate: Item {
                    required property var modelData
                    readonly property bool active: root.toolbarActive(modelData.id)
                    width: 44
                    height: root.toolbarButtonHeight

                    Rectangle {
                        anchors.centerIn: parent
                        width: 38
                        height: 30
                        radius: 15
                        // Neutral grey is preview/hover only. Selection itself
                        // is communicated solely by the underline below.
                        color: hoverHandler.hovered ? root.toolbarKey : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: 90 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: root.toolbarText
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 21
                        }

                        HoverHandler {
                            id: hoverHandler
                            acceptedDevices: PointerDevice.Mouse
                                | PointerDevice.TouchPad
                                | PointerDevice.Stylus
                        }

                        MouseArea {
                            id: iconArea
                            anchors.fill: parent
                            onClicked: root.runToolbar(modelData.id)
                        }
                    }

                    }
                }
            }

            Rectangle {
                id: activeIndicator
                // One physical active indicator: hover can move independently,
                // then a click updates toolbarActiveIndex and this line catches up.
                x: root.toolbarActiveIndex * (44 + toolbarRow.spacing) + (44 - width) / 2
                anchors.bottom: parent.bottom
                width: 18
                height: 3
                radius: 2
                color: root.toolbarText

                Behavior on x {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }


    Component {
        id: modePageComponent

        Item {
            id: page

            property string mode: "keyboard"
            readonly property bool current: root.pane === page.mode
            readonly property real headerHeight: page.mode === "emoji" ? 94 : 54
            readonly property real searchPadHeight: root.searchActive && page.current
                ? Math.max(150, height * 0.44)
                : 0

            Rectangle {
                anchors.fill: parent
                color: page.mode === "keyboard" ? "transparent" : root.toolbarSurface
            }

            Item {
                anchors.fill: parent
                visible: page.mode !== "keyboard"

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
                        anchors.left: parent.left
                        anchors.right: clearSearch.left
                        anchors.leftMargin: 42
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.current ? root.paneQuery : ""
                        readOnly: true
                        color: root.toolbarText
                        font.pixelSize: 14
                        clip: true
                        selectByMouse: false

                        Text {
                            visible: parent.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.mode === "emoji"
                                ? "Search emojis"
                                : page.mode === "history"
                                    ? "Search Protocol 7 history"
                                    : "Search clipboard"
                            color: root.toolbarMuted
                            font.pixelSize: 14
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (page.current)
                                    root.searchActive = true;
                            }
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
                            text: page.current && root.paneQuery.length ? "close" : "search"
                            color: root.toolbarMuted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 18
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!page.current)
                                    return;
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
                    visible: page.mode === "emoji"
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
                                if (!page.current)
                                    return;
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
                    anchors.topMargin: page.headerHeight
                    anchors.bottom: searchPad.top
                    clip: true

                    Item {
                        anchors.fill: parent
                        visible: page.mode === "clipboard"

                        Text {
                            visible: !root.clipboardAvailable || root.clipItems.length === 0
                            anchors.centerIn: parent
                            text: root.clipboardAvailable
                                ? "No clipboard matches"
                                : "Clipboard history unavailable"
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
                                color: clipArea.pressed
                                    ? root.toolbarKey
                                    : Qt.rgba(1, 1, 1, 0.035)

                                Text {
                                    id: clipPreview
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 12
                                    text: modelData.preview
                                    textFormat: Text.PlainText
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
                                        if (page.current && root.actionBin !== "")
                                            Quickshell.execDetached([
                                                root.actionBin,
                                                "clipboard-paste",
                                                modelData.id
                                            ]);
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: page.mode === "emoji"

                        Text {
                            visible: root.emojiItems.length === 0 && !emojiList.running
                            anchors.centerIn: parent
                            text: "No emoji matches"
                            color: root.toolbarMuted
                            font.pixelSize: 14
                        }

                        GridView {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.bottomMargin: 8
                            clip: true
                            cellWidth: 50
                            cellHeight: 50
                            model: root.emojiItems

                            onContentYChanged: {
                                if (page.current && contentY + height >= contentHeight - 140)
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
                                        if (page.current && root.actionBin !== "")
                                            Quickshell.execDetached([
                                                root.actionBin,
                                                "emoji",
                                                modelData.emoji
                                            ]);
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: page.mode === "history"

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
                                color: historyArea.pressed
                                    ? root.toolbarKey
                                    : Qt.rgba(1, 1, 1, 0.035)

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 8
                                    text: new Date(modelData.timestamp * 1000)
                                        .toLocaleString(Qt.locale(), Locale.ShortFormat)
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
                                    textFormat: Text.PlainText
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
                                        if (page.current && root.actionBin !== "")
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
                    height: page.searchPadHeight
                    visible: root.searchActive && page.current
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
                                        width: (parent.width - (modelData.length - 1) * parent.spacing)
                                            / modelData.length
                                        height: parent.height
                                        radius: 8
                                        color: letterArea.pressed
                                            ? root.toolbarText
                                            : root.toolbarKey

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.charAt(index)
                                            color: letterArea.pressed
                                                ? root.toolbarSurface
                                                : root.toolbarText
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
                                    readonly property real unitWidth:
                                        (parent.width - parent.spacing * 3) / 5.2
                                    width: unitWidth * modelData.weight
                                    height: parent.height
                                    radius: 9
                                    color: actionArea.pressed
                                        ? root.toolbarText
                                        : root.toolbarKey

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: actionArea.pressed
                                            ? root.toolbarSurface
                                            : root.toolbarText
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
        }
    }

    PanelWindow {
        id: auxiliaryPane
        visible: root.toolbarVisible
        screen: win.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yoga-osk-pager"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.left: true
        anchors.right: true
        anchors.bottom: true
        margins.left: root.leftMargin
        margins.bottom: 0
        implicitHeight: root.toolbarBottom
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: pagerInputRegion

        Region {
            id: pagerInputRegion
            width: root.pane === "keyboard" && !root.pagerTransitioning
                ? 0 : auxiliaryPane.width
            height: root.pane === "keyboard" && !root.pagerTransitioning
                ? 0 : auxiliaryPane.height
        }

        Loader {
            id: pageA
            property string pageMode: "keyboard"
            property bool animateX: false
            x: 0
            y: 0
            width: auxiliaryPane.width
            height: auxiliaryPane.height
            visible: true
            sourceComponent: modePageComponent

            onLoaded: item.mode = pageMode
            onPageModeChanged: {
                if (item)
                    item.mode = pageMode;
            }

            Behavior on x {
                enabled: pageA.animateX
                NumberAnimation {
                    duration: 230
                    easing.type: Easing.OutCubic
                }
            }
        }

        Loader {
            id: pageB
            property string pageMode: "keyboard"
            property bool animateX: false
            x: 0
            y: 0
            width: auxiliaryPane.width
            height: auxiliaryPane.height
            visible: false
            sourceComponent: modePageComponent

            onLoaded: item.mode = pageMode
            onPageModeChanged: {
                if (item)
                    item.mode = pageMode;
            }

            Behavior on x {
                enabled: pageB.animateX
                NumberAnimation {
                    duration: 230
                    easing.type: Easing.OutCubic
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
        margins.bottom: root.closing ? root.effectiveBottom : 0

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
