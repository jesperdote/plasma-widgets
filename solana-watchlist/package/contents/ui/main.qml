// Solana token watchlist for the panel. Data, validation and the watchlist file
// (~/.config/sol-mc/watchlist) all live in ../code/sol-mc; this is just the view.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // Run through python3 so it works even if the package was unpacked without the exec bit.
    readonly property string backend: "python3 '" + decodeURIComponent(Qt.resolvedUrl("../code/sol-mc").toString().replace("file://", "")) + "'"
    readonly property int maxInPanel: 3
    readonly property int panelFontSize: 14
    // One colour per time frame, same in the panel and the popup.
    readonly property var windows: [
        { key: "m5",  label: "5m",  color: "#8BD5CA" },
        { key: "h1",  label: "1h",  color: "#8AADF4" },
        { key: "h6",  label: "6h",  color: "#EED49F" },
        { key: "h24", label: "24h", color: "#F5BDE6" }
    ]
    property var tokens: []
    readonly property var shown: tokens.filter(t => !t.hidden)
    readonly property var panelKeys: Plasmoid.configuration.panelWindows.split(",").filter(k => k)
    readonly property var panelWindows: windows.filter(w => panelKeys.includes(w.key))

    function togglePanelWindow(key, on) {
        // Keep the 5m/1h/6h/24h order whatever order they're ticked in.
        const keys = windows.map(w => w.key).filter(k => k === key ? on : panelKeys.includes(k))
        Plasmoid.configuration.panelWindows = keys.join(",")
    }
    property int age: 0
    property string message: ""
    property bool messageIsError: false
    property bool busy: false

    signal added()

    // Panel Colorizer repaints every Text in the panel with its foreground colour whenever a
    // widget's children change (e.g. after adding a token); put the time-frame colour back.
    component FrameLabel: PC3.Label {
        property color frameColor
        color: frameColor
        onColorChanged: if (!Qt.colorEqual(color, frameColor)) Qt.callLater(() => color = frameColor)
    }

    function fmt(c) {
        if (c === undefined || c === null)
            return "–"  // DexScreener drops a window with no trades / no movement
        const a = Math.abs(c)
        return (c >= 0 ? "▲" : "▼") + (a < 10 ? a.toFixed(1) : a.toFixed(0)) + "%"
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: (source, data) => {
            const cb = callbacks[source]
            delete callbacks[source]
            disconnectSource(source)
            if (cb)
                cb(data["stdout"])
        }
        function run(cmd, cb) {
            callbacks[cmd] = cb
            connectSource(cmd)
        }
    }

    property string lastTokensJson: ""

    function apply(out) {
        try {
            const d = JSON.parse(out)
            // Rebuilding the rows makes Panel Colorizer repaint the panel; with a 5 s refresh
            // only do it when the numbers actually changed.
            const tj = JSON.stringify(d.tokens)
            if (tj !== lastTokensJson) {
                lastTokensJson = tj
                tokens = d.tokens
            }
            age = d.age || 0
            return d
        } catch (e) {
            return null
        }
    }

    function refresh() {
        exec.run(backend + " --json", out => apply(out))
    }

    function change(mode, address) {
        // Only base58 ever reaches the shell.
        if (!/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(address)) {
            message = "That doesn't look like a Solana address."
            messageIsError = true
            return
        }
        busy = true
        message = mode === "--add" ? "Looking it up on DexScreener…" : ""
        messageIsError = false
        exec.run(backend + " " + mode + " " + address, out => {
            busy = false
            const d = apply(out)
            if (!d) {
                message = "Something went wrong running sol-mc."
                messageIsError = true
                return
            }
            message = d.message
            messageIsError = !d.ok
            if (d.ok && mode === "--add")
                root.added()
        })
    }

    Timer {
        interval: 2000  // cheap when nothing is due: the backend only hits the network when its caches expire
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    toolTipMainText: "Solana watchlist"
    toolTipSubText: tokens.length ? tokens.filter(t => !t.hidden).map(t => t.symbol + " " + (t.found ? t.marketCap : "not found")).join(" · ") + "\nClick to add / remove tokens"
                                  : "Click to add a token"

    compactRepresentation: MouseArea {
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing * 2

            PC3.Label {
                text: root.shown.length ? "◎" : (root.tokens.length ? "◎ all hidden" : "◎ add token")
                font.pointSize: root.panelFontSize
            }
            Repeater {
                model: root.shown.slice(0, root.maxInPanel)
                delegate: RowLayout {
                    id: tokenRow
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing * 2
                    PC3.Label {
                        text: tokenRow.modelData.symbol + " " + (tokenRow.modelData.found ? tokenRow.modelData.marketCap : "?")
                        font.pointSize: root.panelFontSize
                    }
                    Repeater {
                        model: tokenRow.modelData.found ? root.panelWindows : []
                        delegate: FrameLabel {
                            required property var modelData
                            text: modelData.label + " " + root.fmt(tokenRow.modelData.changes[modelData.key])
                            frameColor: modelData.color
                            font.pointSize: root.panelFontSize
                        }
                    }
                }
            }
            PC3.Label {
                visible: root.shown.length > root.maxInPanel
                text: "+" + (root.shown.length - root.maxInPanel)
                font.pointSize: root.panelFontSize
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 18
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: "Solana watchlist"
                }
                PC3.Label {
                    opacity: 0.6
                    text: root.age > 120 ? "updated " + Math.round(root.age / 60) + " min ago" : ""
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    PC3.ToolTip.text: "Refresh now"
                    PC3.ToolTip.visible: hovered
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                PC3.Label {
                    text: "On the panel:"
                    opacity: 0.7
                }
                Repeater {
                    model: root.windows
                    delegate: RowLayout {
                        id: windowToggle
                        required property var modelData
                        spacing: 0
                        PC3.CheckBox {
                            checked: root.panelKeys.includes(windowToggle.modelData.key)
                            onToggled: root.togglePanelWindow(windowToggle.modelData.key, checked)
                        }
                        FrameLabel {
                            text: windowToggle.modelData.label
                            frameColor: windowToggle.modelData.color
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            PC3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: root.tokens
                    clip: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: list.count === 0
                        iconName: "office-chart-line"
                        text: "No tokens yet"
                        explanation: "Paste a Solana token address below"
                    }

                    delegate: PlasmaExtras.ListItem {
                        id: item
                        required property var modelData
                        width: ListView.view.width
                        // Hidden from the panel: still listed and updated here, just dimmed.
                        opacity: modelData.hidden ? 0.5 : 1

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PC3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: true
                                    text: item.modelData.found
                                          ? item.modelData.name + " (" + item.modelData.symbol + ") · MC " + item.modelData.marketCap
                                          : item.modelData.symbol + " · no DexScreener pair"
                                }
                                RowLayout {
                                    spacing: Kirigami.Units.largeSpacing
                                    visible: item.modelData.found
                                    PC3.Label {
                                        opacity: 0.7
                                        text: "$" + item.modelData.price
                                    }
                                    Repeater {
                                        model: root.windows
                                        delegate: FrameLabel {
                                            required property var modelData
                                            text: modelData.label + " " + root.fmt(item.modelData.changes[modelData.key])
                                            frameColor: modelData.color
                                        }
                                    }
                                }
                                PC3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    opacity: 0.5
                                    font: Kirigami.Theme.smallFont
                                    text: item.modelData.address
                                }
                            }
                            PC3.ToolButton {
                                icon.name: item.modelData.hidden ? "layer-visible-off" : "layer-visible-on"
                                enabled: !root.busy
                                onClicked: root.change(item.modelData.hidden ? "--show" : "--hide", item.modelData.address)
                                PC3.ToolTip.text: item.modelData.hidden ? "Show on the panel" : "Hide from the panel"
                                PC3.ToolTip.visible: hovered
                            }
                            PC3.ToolButton {
                                icon.name: "internet-web-browser"
                                onClicked: Qt.openUrlExternally(item.modelData.url)
                                PC3.ToolTip.text: "Open on DexScreener"
                                PC3.ToolTip.visible: hovered
                            }
                            PC3.ToolButton {
                                icon.name: "edit-copy"
                                onClicked: { clip.text = item.modelData.address; clip.selectAll(); clip.copy() }
                                PC3.ToolTip.text: "Copy address"
                                PC3.ToolTip.visible: hovered
                            }
                            PC3.ToolButton {
                                icon.name: "edit-delete"
                                enabled: !root.busy
                                onClicked: root.change("--remove", item.modelData.address)
                                PC3.ToolTip.text: "Remove from watchlist"
                                PC3.ToolTip.visible: hovered
                            }
                        }
                    }
                }
            }

            // Hidden helper for "Copy address".
            TextEdit {
                id: clip
                visible: false
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: root.message !== ""
                wrapMode: Text.Wrap
                text: root.message
                color: root.messageIsError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
            }

            RowLayout {
                Layout.fillWidth: true
                PC3.TextField {
                    id: addressField
                    Layout.fillWidth: true
                    placeholderText: "Paste a Solana token address"
                    enabled: !root.busy
                    onAccepted: root.change("--add", text.trim())
                    Connections {
                        target: root
                        function onAdded() { addressField.text = "" }
                    }
                }
                PC3.Button {
                    icon.name: "list-add"
                    text: "Add"
                    enabled: !root.busy && addressField.text.trim() !== ""
                    onClicked: root.change("--add", addressField.text.trim())
                }
            }
        }
    }
}
