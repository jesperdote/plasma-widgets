// Claude usage on the panel: logo, 5-hour session % and weekly %, colour-coded.
// Data comes from ~/bin/claude-usage --json (which caches the API for 5 minutes).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property var usage: null

    function pctColor(p) {
        if (p === null || p === undefined) return Kirigami.Theme.textColor
        return p >= 80 ? "#F85149" : p >= 50 ? "#E3B341" : Kirigami.Theme.textColor
    }
    function fmtReset(iso, withDay) {
        if (!iso) return "?"
        const d = new Date(iso)
        return Qt.formatDateTime(d, withDay ? "ddd h:mm AP" : "h:mm AP")
    }

    // Panel Colorizer repaints panel text when children change; keep the warning colours.
    component PctLabel: PC3.Label {
        property color wanted
        color: wanted
        onColorChanged: if (!Qt.colorEqual(color, wanted)) Qt.callLater(() => color = wanted)
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            try { root.usage = JSON.parse(data["stdout"]) } catch (e) {}
        }
    }

    // Launch directly: Qt.openUrlExternally goes through the desktop portal,
    // which shows an app chooser and blocks the panel if the portal is down.
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource("\"$HOME/bin/claude-usage\" --json")
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Open usage page"
            icon.name: "internet-web-browser"
            onTriggered: launcher.connectSource("xdg-open https://claude.ai/settings/usage")
        }
    ]

    toolTipMainText: "Claude usage"
    toolTipSubText: !usage || !usage.ok ? "Unavailable: open Claude Code to refresh the login"
        : "Session (5h): " + Math.round(usage.session.pct) + "% · resets " + fmtReset(usage.session.resetsAt, false)
          + "\nWeekly: " + Math.round(usage.weekly.pct) + "% · resets " + fmtReset(usage.weekly.resetsAt, true)
          + (usage.ageMin > 10 ? "\n(as of " + usage.ageMin + " min ago)" : "")
          + "\nRight-click to open the usage page"

    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing * 2
            Image {
                source: Qt.resolvedUrl("../images/claude.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
            }
            // Two stacked rows like the CPU / RAM monitor, at the theme's default font size.
            GridLayout {
                columns: 2
                rowSpacing: 0
                columnSpacing: Kirigami.Units.largeSpacing
                PC3.Label { text: "5h"; opacity: 0.8 }
                PctLabel {
                    Layout.alignment: Qt.AlignRight
                    text: root.usage && root.usage.ok ? Math.round(root.usage.session.pct) + "%" : "–"
                    wanted: root.pctColor(root.usage && root.usage.ok ? root.usage.session.pct : null)
                }
                PC3.Label { text: "7d"; opacity: 0.8 }
                PctLabel {
                    Layout.alignment: Qt.AlignRight
                    text: root.usage && root.usage.ok ? Math.round(root.usage.weekly.pct) + "%" : "–"
                    wanted: root.pctColor(root.usage && root.usage.ok ? root.usage.weekly.pct : null)
                }
            }
        }
    }
    fullRepresentation: compactRepresentation
}
