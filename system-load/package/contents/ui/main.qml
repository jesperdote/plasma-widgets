// CPU (average of all cores) and RAM usage, icon + value, stacked like a small monitor.
// Same sensors as KDE's System Monitor widget; click opens System Monitor.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    Sensors.Sensor { id: cpu; sensorId: "cpu/all/usage"; updateRateLimit: 2000 }
    Sensors.Sensor { id: ram; sensorId: "memory/physical/usedPercent"; updateRateLimit: 2000 }
    Sensors.Sensor { id: ramUsed; sensorId: "memory/physical/used"; updateRateLimit: 5000 }
    Sensors.Sensor { id: ramTotal; sensorId: "memory/physical/total"; updateRateLimit: 60000 }

    // Launch directly: Qt.openUrlExternally goes through the desktop portal,
    // which shows an app chooser and blocks the panel if the portal is down.
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
    }

    // Each row has its own colour; warnings still win.
    readonly property color cpuColor: "#F5BDE6"
    readonly property color ramColor: "#8AADF4"
    function level(p, normal) {
        return p >= 90 ? "#F85149" : p >= 70 ? "#E3B341" : normal
    }

    // Panel Colorizer repaints panel text when children change; keep the warning colours.
    component ValueLabel: PC3.Label {
        property color wanted
        color: wanted
        horizontalAlignment: Text.AlignRight
        onColorChanged: if (!Qt.colorEqual(color, wanted)) Qt.callLater(() => color = wanted)
    }

    toolTipMainText: "CPU & RAM"
    toolTipSubText: "CPU " + cpu.formattedValue + " (all cores)\nRAM " + ram.formattedValue + " · "
                    + ramUsed.formattedValue + " of " + ramTotal.formattedValue + "\nClick for System Monitor"

    compactRepresentation: MouseArea {
        Layout.minimumWidth: grid.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: launcher.connectSource("gtk-launch org.kde.plasma-systemmonitor")

        GridLayout {
            id: grid
            anchors.centerIn: parent
            columns: 2
            rowSpacing: 0
            columnSpacing: Kirigami.Units.smallSpacing * 2
            Kirigami.Icon {
                source: "cpu"
                isMask: true
                color: root.cpuColor
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            ValueLabel {
                // Fixed width so the panel doesn't shift as the number changes.
                Layout.preferredWidth: metrics.width
                text: (cpu.value || 0).toFixed(1) + "%"
                wanted: root.level(cpu.value || 0, root.cpuColor)
            }
            Kirigami.Icon {
                source: Qt.resolvedUrl("../images/ram.svg")
                isMask: true
                color: root.ramColor
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            ValueLabel {
                Layout.preferredWidth: metrics.width
                text: (ram.value || 0).toFixed(1) + "%"
                wanted: root.level(ram.value || 0, root.ramColor)
            }
        }
        TextMetrics { id: metrics; text: "100.0%" }
    }
    fullRepresentation: compactRepresentation
}
