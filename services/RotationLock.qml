pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Rotation lock, as owned by the yoga-tablet daemon.
//
// The daemon is the authority: it also flips the lock from the CLI
// (Super+Alt+O rotates and latches) and from its own tablet-mode handling, so
// this never caches a guess -- it re-reads `status` whenever the panel that
// shows it opens, and again after every write.
Singleton {
    id: root

    // Rotation Lock now lives inside TabletMode. Resolve the daemon relative
    // to this plugin so the toggle survives any Nexus clone directory name.
    readonly property string bin: Paths.toLocalFile(Qt.resolvedUrl("../scripts/yoga-tablet"))

    // False until a reply actually lands, so the toggle stays hidden on a
    // machine where the daemon is not installed or not running.
    property bool available: false
    property bool locked: false
    property bool tabletMode: false

    function refresh(): void {
        if (!status.running)
            status.running = true;
    }

    function toggle(): void {
        if (!toggler.running)
            toggler.running = true;
    }

    // `status` is the only subcommand that answers on stdout; the rest report
    // through the exit code alone, hence the read-back in toggler below.
    Process {
        id: status

        command: [root.bin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    root.available = false;
                    return;
                }
                if (!data || data.ok === false) {
                    root.available = false;
                    return;
                }
                root.available = true;
                root.locked = data.rotation_locked ?? root.locked;
                root.tabletMode = data.tablet_mode ?? root.tabletMode;
            }
        }
        // A missing binary produces no stdout at all, so failure has to clear
        // the flag on its own.
        onExited: code => {
            if (code !== 0)
                root.available = false;
        }
    }

    Process {
        id: toggler

        command: [root.bin, "toggle-lock"]
        onExited: code => {
            if (code === 0)
                root.refresh();
            else
                root.available = false;
        }
    }

    Component.onCompleted: root.refresh()
}
