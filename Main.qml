import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// TabletMode is the sole owner of the convertible runtime. The small
// ~/.local/bin/yoga-tablet compatibility entry is only a symlink back here so
// Hyprland keybinds and terminal commands never carry a second copy.
Item {
    id: root

    width: 0
    height: 0
    visible: false

    readonly property string home: Quickshell.env("HOME")
    // Resolve relative to this plugin rather than assuming a clone directory.
    // This keeps installs from Nexus, git clone, or a custom plugin path identical.
    readonly property string bin: Paths.toLocalFile(Qt.resolvedUrl("scripts/yoga-tablet"))
    readonly property string touchIntegrationBin: Paths.toLocalFile(Qt.resolvedUrl("scripts/ensure-touch-popouts"))

    // Keep the tiny Caelestia interaction hook owned by this plugin.
    // The helper is idempotent and refuses to guess after incompatible upstream changes.
    Process {
        id: touchIntegration
        command: [root.touchIntegrationBin]
        running: true
    }

    Process {
        id: daemon
        command: [root.bin, "daemon"]
        running: true
    }

    Process {
        id: reloadProc
        command: [root.bin, "reload"]
    }

    Process {
        id: rethemeProc
        command: [root.bin, "retheme"]
    }

    Timer {
        id: reloadDebounce
        interval: 180
        repeat: false
        onTriggered: if (!reloadProc.running)
            reloadProc.running = true
    }

    // SettingsObject persists into plugins.json. Re-read it live instead of
    // requiring a shell restart for every slider/toggle change.
    FileView {
        path: `${root.home}/.config/caelestia/plugins.json`
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            reloadDebounce.restart();
        }
    }

    // This replaces the old yoga-tablet-theme.path systemd unit.
    FileView {
        path: `${root.home}/.local/state/caelestia/scheme.json`
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            if (!rethemeProc.running)
                rethemeProc.running = true;
        }
    }
}
