import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Location"
        icon: "mark-location"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: "Appearance"
        icon: "preferences-desktop-font"
        source: "configAppearance.qml"
    }
}
