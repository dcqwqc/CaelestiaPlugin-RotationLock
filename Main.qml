import QtQuick
import Quickshell
import Quickshell.Io

// The plugin owns the convertible daemon now. If an old systemd-managed daemon
// is already present this process exits immediately and RotationLock continues
// talking to that socket; on a clean install this is the daemon owner.
Item {
    id: root

    width: 0
    height: 0
    visible: false

    readonly property string bin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/rotation-lock/scripts/yoga-tablet`

    Process {
        command: [root.bin, "daemon"]
        running: true
    }
}
