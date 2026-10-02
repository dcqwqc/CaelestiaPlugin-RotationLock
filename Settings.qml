import Caelestia.Plugins

SettingsObject {
    property string autoRotate: "always"
    SettingMeta on autoRotate {
        label: "Automatic rotation"
        description: "Always rotates from the accelerometer, only rotates while folded into tablet mode, or never rotates automatically."
        icon: "screen_rotation"
        inputType: SettingMeta.SplitButton
        options: ["always", "tablet", "never"]
    }

    property bool invertSides: false
    SettingMeta on invertSides {
        label: "Swap portrait sides"
        description: "Use this if left and right portrait rotation are reversed for the panel's physical sensor mounting."
        icon: "swap_horiz"
        inputType: SettingMeta.Switch
    }

    property real thresholdG: 0.55
    SettingMeta on thresholdG {
        label: "Rotation sensitivity"
        description: "Minimum gravity component required before the display commits to a new side. Higher values make accidental rotations less likely."
        icon: "tune"
        inputType: SettingMeta.Slider
        min: 0.35
        max: 0.85
        step: 0.05
    }

    property int stableSamples: 4
    SettingMeta on stableSamples {
        label: "Rotation stability"
        description: "How many consecutive sensor samples must agree before rotation is applied."
        icon: "motion_sensor_active"
        inputType: SettingMeta.SpinBox
        min: 1
        max: 10
        step: 1
    }

    property bool oskHandle: true
    SettingMeta on oskHandle {
        label: "Keyboard swipe handle"
        description: "Shows the bottom-left tablet gesture strip used to pull up the on-screen keyboard."
        icon: "keyboard"
        inputType: SettingMeta.Switch
    }

    property bool oskPreload: true
    SettingMeta on oskPreload {
        label: "Preload keyboard in tablet mode"
        description: "Keeps the hidden keyboard process warm after folding so the first open is immediate."
        icon: "bolt"
        inputType: SettingMeta.Switch
    }

    property string oskTheme: "caelestia"
    SettingMeta on oskTheme {
        label: "Keyboard theme"
        description: "Match the current Caelestia colour scheme or use wvkbd's native colours."
        icon: "palette"
        inputType: SettingMeta.SplitButton
        options: ["caelestia", "none"]
    }

    property bool disablePointersInTablet: false
    SettingMeta on disablePointersInTablet {
        label: "Disable keyboard and touchpad in tablet mode"
        description: "Normally the Yoga firmware handles this. Enable only if your firmware leaves physical input active while folded."
        icon: "keyboard_off"
        inputType: SettingMeta.Switch
    }

    property bool notify: true
    SettingMeta on notify {
        label: "Mode notifications"
        description: "Show a short Caelestia toast when tablet mode or rotation state changes."
        icon: "notifications"
        inputType: SettingMeta.Switch
    }
}
