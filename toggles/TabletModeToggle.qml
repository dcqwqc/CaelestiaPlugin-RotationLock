import QtQuick
import qs.components.controls
import qs.services
import dcqwqc.tabletmode.services as TabletPlugin

IconButton {
    visible: TabletPlugin.RotationLock.available
    icon: TabletPlugin.RotationLock.tabletMode ? "tablet_android" : "laptop_mac"
    checked: TabletPlugin.RotationLock.tabletMode
    enabled: !TabletPlugin.RotationLock.tabletModeChanging
    onClicked: TabletPlugin.RotationLock.toggleTabletMode()

    inactiveColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
    fillWidth: true
    isToggle: true
    isRound: true
    shapeMorph: true

    onVisibleChanged: if (visible)
        TabletPlugin.RotationLock.refresh()
}
