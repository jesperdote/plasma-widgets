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
    readonly property var windows: [
        { key: "m5",  label: "5m" },
        { key: "h1",  label: "1h" },
        { key: "h6",  label: "6h" },
        { key: "h24", label: "24h" }
    ]
    property var tokens: []
    // The popup list gets its own copy so it can hold still while an alert editor is open:
    // replacing the model rebuilds the rows and would wipe what's being typed.
    property var listTokens: []
    property string editingAddress: ""
    onEditingAddressChanged: if (editingAddress === "") listTokens = tokens
    onExpandedChanged: if (!expanded) editingAddress = ""
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

    // Green up, red down; plain text when DexScreener has no figure. Fixed colours rather than
    // the theme's positive/negative ones, which some themes make the same hue.
    readonly property color upColor: "#3FB950"
    readonly property color downColor: "#F85149"
    function changeColor(c) {
        if (c === undefined || c === null)
            return Kirigami.Theme.textColor
        return c >= 0 ? upColor : downColor
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
                if (editingAddress === "")
                    listTokens = d.tokens
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

    // Market-cap alerts: "" clears that direction, otherwise an amount like 50M / 1.2B / 300K.
    function setAlerts(address, above, below, current) {
        const clean = v => v.replace(/[$\s]/g, "")
        const ok = v => v === "" || /^[0-9][0-9,]*\.?[0-9]*[kmbKMB]?$/.test(v)
        above = clean(above); below = clean(below)
        if (!ok(above) || !ok(below)) {
            message = "Enter amounts like 50M, 1.2B or 300K."
            messageIsError = true
            return false
        }
        let args = []
        if (above !== "") args.push("above", above)
        else if (current.above) args.push("above", "off")
        if (below !== "") args.push("below", below)
        else if (current.below) args.push("below", "off")
        if (!args.length)
            return true
        busy = true
        exec.run(backend + " --alert " + address + " " + args.join(" "), out => {
            busy = false
            const d = apply(out)
            message = d ? d.message : "Something went wrong running sol-mc."
            messageIsError = !d || !d.ok
        })
        return true
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
        readonly property bool solid: Plasmoid.configuration.solidBackground
        Layout.minimumWidth: row.implicitWidth + (solid ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        // Optional solid pill behind the text; off = transparent (panel / Panel Colorizer shows through).
        Rectangle {
            visible: parent.solid
            anchors.fill: parent
            anchors.topMargin: Kirigami.Units.smallSpacing
            anchors.bottomMargin: Kirigami.Units.smallSpacing
            radius: height / 4
            // Tooltip colours: the theme's raised surface, so it stands out from the panel.
            Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip
            Kirigami.Theme.inherit: false
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.highlightColor, 0.45)
        }

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
                            frameColor: root.changeColor(tokenRow.modelData.changes[modelData.key])
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
        Layout.preferredWidth: Kirigami.Units.gridUnit * 36
        Layout.preferredHeight: Kirigami.Units.gridUnit * 20
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
                        PC3.Label {
                            text: windowToggle.modelData.label
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                PC3.CheckBox {
                    text: "Solid background"
                    checked: Plasmoid.configuration.solidBackground
                    onToggled: Plasmoid.configuration.solidBackground = checked
                }
            }

            PC3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: root.listTokens
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
                        readonly property bool editing: root.editingAddress === modelData.address
                        width: ListView.view.width
                        // Hidden from the panel: still listed and updated here, just dimmed.
                        opacity: modelData.hidden ? 0.5 : 1

                        contentItem: ColumnLayout {
                          spacing: 0
                          RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing
                            ColumnLayout {
                                // Take whatever width the buttons leave; long text is cut, never the buttons.
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                clip: true
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
                                            frameColor: root.changeColor(item.modelData.changes[modelData.key])
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
                                PC3.Label {
                                    readonly property var al: item.modelData.alerts || {}
                                    visible: !item.editing && (al.above || al.below) ? true : false
                                    font: Kirigami.Theme.smallFont
                                    text: "🔔 " + [al.above ? "above " + al.above.text : "", al.below ? "below " + al.below.text : ""].filter(x => x).join(" · ")
                                }
                            }
                            PC3.ToolButton {
                                icon.name: "preferences-desktop-notification-bell"  // in Breeze and char-white; "bell" is not
                                checked: item.editing
                                enabled: item.modelData.found
                                onClicked: root.editingAddress = item.editing ? "" : item.modelData.address
                                PC3.ToolTip.text: "Market cap alerts"
                                PC3.ToolTip.visible: hovered
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
                          // Alert editor, opened with the bell button.
                          RowLayout {
                              visible: item.editing
                              Layout.topMargin: Kirigami.Units.smallSpacing
                              PC3.Label { text: "🔔 Above $" }
                              PC3.TextField {
                                  id: aboveField
                                  Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                  placeholderText: "e.g. 50M"
                                  text: item.modelData.alerts && item.modelData.alerts.above ? item.modelData.alerts.above.text.replace("$", "") : ""
                                  onAccepted: saveAlerts.clicked()
                              }
                              PC3.Label { text: "Below $" }
                              PC3.TextField {
                                  id: belowField
                                  Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                  placeholderText: "e.g. 30M"
                                  text: item.modelData.alerts && item.modelData.alerts.below ? item.modelData.alerts.below.text.replace("$", "") : ""
                                  onAccepted: saveAlerts.clicked()
                              }
                              PC3.Button {
                                  id: saveAlerts
                                  text: "Save"
                                  enabled: !root.busy
                                  onClicked: if (root.setAlerts(item.modelData.address, aboveField.text, belowField.text, item.modelData.alerts || {})) root.editingAddress = ""
                              }
                              PC3.ToolButton {
                                  icon.name: "dialog-cancel"
                                  onClicked: root.editingAddress = ""
                                  PC3.ToolTip.text: "Cancel (leave both empty and Save to remove alerts)"
                                  PC3.ToolTip.visible: hovered
                              }
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
