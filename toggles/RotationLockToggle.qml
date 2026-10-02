import QtQuick
import qs.components.controls
import qs.services
import dcqwqc.tabletmode.services as RotationLockPlugin

// The daemon owns the lock and other things flip it (Super+Alt+O, folding the
// hinge), so this re-reads whenever it comes back on screen rather than polling
// for a change that almost never happens.
IconButton {
    // Hides itself where the yoga-tablet daemon is not answering, rather
    // than sitting there as a dead control on a desktop.
    visible: RotationLockPlugin.RotationLock.available
    icon: RotationLockPlugin.RotationLock.locked ? "screen_lock_rotation" : "screen_rotation"
    checked: RotationLockPlugin.RotationLock.locked
    onClicked: RotationLockPlugin.RotationLock.toggle()

    inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
    fillWidth: true
    isToggle: true
    isRound: true
    shapeMorph: true

    onVisibleChanged: if (visible)
        RotationLockPlugin.RotationLock.refresh()
}
