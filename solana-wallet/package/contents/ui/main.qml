// Solana wallet value for the panel. Balances, prices and the wallet list
// (~/.config/sol-wallet/wallets) all live in ../code/sol-wallet; this is just the view.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // Zoom for the popup / window contents (70-180%), like a word processor's zoom.
    readonly property real zoom: Plasmoid.configuration.zoom
    function setZoom(z) {
        Plasmoid.configuration.zoom = Math.round(Math.max(0.7, Math.min(1.8, z)) * 10) / 10
    }

    // Run through python3 so it works even if the package was unpacked without the exec bit.
    readonly property string backend: "python3 '" + decodeURIComponent(Qt.resolvedUrl("../code/sol-wallet").toString().replace("file://", "")) + "'"
    readonly property int panelFontSize: 14
    readonly property bool hideSmall: Plasmoid.configuration.hideSmall
    // Privacy: mask dollar values and amounts (symbols and % changes stay visible).
    readonly property bool hideValues: Plasmoid.configuration.hideValues
    readonly property color upColor: "#3FB950"
    readonly property color downColor: "#F85149"

    property var wallets: []
    property real totalUsd: 0
    property var change24h: null
    property string priceError: ""
    property var fx: ({})  // units per 1 USD, from the backend
    property var sol: null  // {price (USD), change24h} for the SOL readout
    readonly property var currencySymbols: ({ USD: "$", PHP: "₱" })
    // Fall back to USD until the exchange rate has been fetched once.
    readonly property string currency: fx[Plasmoid.configuration.currency] ? Plasmoid.configuration.currency : "USD"
    readonly property string sym: currencySymbols[currency] || "$"
    property string message: ""
    property bool messageIsError: false
    property bool busy: false
    property string lastJson: ""

    signal added()

    // Small inline "copy token address (CA)" icon, next to a token's name/ticker.
    TextEdit { id: rootClip; visible: false }
    function copyCA(address, symbol) {
        rootClip.text = address; rootClip.selectAll(); rootClip.copy(); rootClip.text = ""
        message = "Copied the " + symbol + " token address (CA)"
        messageIsError = false
    }
    // Small inline "open on DexScreener" icon, next to the copy icon.
    component DexLink: Kirigami.Icon {
        property string address
        property string url: "https://dexscreener.com/solana/" + address
        source: "internet-web-browser"
        Layout.preferredWidth: Math.round(Kirigami.Units.iconSizes.small * 0.75 * root.zoom)
        Layout.preferredHeight: Layout.preferredWidth
        opacity: dexArea.containsMouse ? 1 : 0.5
        MouseArea {
            id: dexArea
            anchors.fill: parent
            anchors.margins: -Kirigami.Units.smallSpacing
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(parent.url)
        }
        PC3.ToolTip.text: "Open on DexScreener"
        PC3.ToolTip.visible: dexArea.containsMouse
    }
    component CopyCA: Kirigami.Icon {
        property string address
        property string symbol
        source: "edit-copy"
        Layout.preferredWidth: Math.round(Kirigami.Units.iconSizes.small * 0.75 * root.zoom)
        Layout.preferredHeight: Layout.preferredWidth
        opacity: copyArea.containsMouse ? 1 : 0.5
        MouseArea {
            id: copyArea
            anchors.fill: parent
            anchors.margins: -Kirigami.Units.smallSpacing  // a slightly bigger target than the icon
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.copyCA(parent.address, parent.symbol)
        }
        PC3.ToolTip.text: "Copy token address (CA)"
        PC3.ToolTip.visible: copyArea.containsMouse
    }

    // Panel Colorizer repaints every Text in the panel with its foreground colour whenever a
    // widget's children change; put the red/green back.
    component ChangeLabel: PC3.Label {
        property color wanted
        color: wanted
        onColorChanged: if (!Qt.colorEqual(color, wanted)) Qt.callLater(() => color = wanted)
    }

    function changeColor(c) {
        if (c === undefined || c === null)
            return Kirigami.Theme.textColor
        return c >= 0 ? upColor : downColor
    }

    function fmtChange(c) {
        if (c === undefined || c === null)
            return ""
        const a = Math.abs(c)
        return (c >= 0 ? "▲" : "▼") + (a < 10 ? a.toFixed(1) : a.toFixed(0)) + "%"
    }

    // Values arrive in USD; shown in the chosen currency.
    function fmtMoney(usd) {
        if (usd === undefined || usd === null)
            return "no price"
        const v = usd * (fx[currency] || 1)
        if (v >= 1000)
            return sym + Math.round(v).toLocaleString(Qt.locale("en_US"), "f", 0)
        return sym + v.toFixed(2)
    }

    function shownMoney(v) {
        return hideValues && v !== null && v !== undefined ? sym + "•••" : fmtMoney(v)
    }

    function shownAmount(a) {
        return hideValues ? "•••" : fmtAmount(a)
    }

    function toggleHideValues() {
        Plasmoid.configuration.hideValues = !Plasmoid.configuration.hideValues
    }

    function fmtAmount(a) {
        if (a >= 1e9) return (a / 1e9).toFixed(2) + "B"
        if (a >= 1e6) return (a / 1e6).toFixed(2) + "M"
        if (a >= 1000) return Math.round(a).toLocaleString(Qt.locale("en_US"), "f", 0)
        return Number(a.toPrecision(4)).toString()
    }

    function visibleHoldings(w) {
        return hideSmall ? w.holdings.filter(h => h.isSol || (h.usd !== null && h.usd >= 1)) : w.holdings
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

    function apply(out) {
        try {
            const d = JSON.parse(out)
            // Only rebuild the rows when something changed (rebuilding makes Colorizer repaint).
            const j = JSON.stringify(d.wallets)
            if (j !== lastJson) {
                lastJson = j
                wallets = d.wallets
            }
            totalUsd = d.totalUsd
            change24h = d.change24h
            priceError = d.priceError || ""
            fx = d.fx || {}
            sol = d.sol || sol
            return d
        } catch (e) {
            return null
        }
    }

    function refresh(force) {
        exec.run(backend + (force ? " --refresh" : " --json"), out => apply(out))
    }

    function change(mode, address, label) {
        // Only base58 and a plain label ever reach the shell.
        if (!/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(address)) {
            message = "That doesn't look like a Solana address."
            messageIsError = true
            return
        }
        const safeLabel = (label || "").replace(/[^A-Za-z0-9 _.\-]/g, "").trim().slice(0, 30)
        busy = true
        message = mode === "--add" ? "Looking it up…" : ""
        messageIsError = false
        exec.run(backend + " " + mode + " " + address + (safeLabel ? " '" + safeLabel + "'" : ""), out => {
            busy = false
            const d = apply(out)
            if (!d) {
                message = "Something went wrong running sol-wallet."
                messageIsError = true
                return
            }
            message = d.message
            messageIsError = !d.ok
            if (d.ok && mode === "--add")
                root.added()
        })
    }

    // The backend caches balances for 60 s and prices for 30 s, so this is cheap.
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    toolTipMainText: "Solana wallets"
    toolTipSubText: wallets.length ? wallets.map(w => w.label + ": " + shownMoney(w.totalUsd)).join("\n") + "\nClick for holdings"
                                   : "Click to add a wallet"

    compactRepresentation: MouseArea {
        readonly property bool solid: Plasmoid.configuration.solidBackground
        Layout.minimumWidth: row.implicitWidth + (solid ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // Middle-click hides/shows the values without opening the popup.
        onClicked: mouse => mouse.button === Qt.MiddleButton ? root.toggleHideValues() : root.expanded = !root.expanded

        Rectangle {
            visible: parent.solid
            anchors.fill: parent
            anchors.topMargin: Kirigami.Units.smallSpacing
            anchors.bottomMargin: Kirigami.Units.smallSpacing
            radius: height / 4
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
                text: root.wallets.length ? "👛 " + root.shownMoney(root.totalUsd) : "👛 add wallet"
                font.pointSize: root.panelFontSize
            }
            ChangeLabel {
                visible: root.wallets.length > 0 && root.change24h !== null
                text: root.fmtChange(root.change24h)
                wanted: root.changeColor(root.change24h)
                font.pointSize: root.panelFontSize
            }
        }
    }

    // The popup's contents, also used for the movable window below.
    component MainView: PlasmaExtras.Representation {
        property bool inWindow: false

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: event => root.setZoom(root.zoom + (event.angleDelta.y > 0 ? 0.1 : -0.1))
        }
        Shortcut { sequences: [StandardKey.ZoomIn, "Ctrl+="]; onActivated: root.setZoom(root.zoom + 0.1) }
        Shortcut { sequence: StandardKey.ZoomOut; onActivated: root.setZoom(root.zoom - 0.1) }
        Shortcut { sequence: "Ctrl+0"; onActivated: root.setZoom(1) }
        Layout.preferredWidth: Kirigami.Units.gridUnit * 32
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                    level: 3
                    text: "Solana wallets"
                }
                PC3.Label {
                    visible: root.sol !== null
                    opacity: 0.8
                    text: root.sol ? "·  SOL " + root.fmtMoney(root.sol.price) : ""
                }
                ChangeLabel {
                    visible: root.sol !== null && root.sol.change24h !== null && root.sol.change24h !== undefined
                    text: root.sol ? root.fmtChange(root.sol.change24h) : ""
                    wanted: root.changeColor(root.sol ? root.sol.change24h : null)
                }
                Item { Layout.fillWidth: true }
                Kirigami.Heading {
                                    level: 3
                    visible: root.wallets.length > 0
                    text: root.shownMoney(root.totalUsd)
                }
                ChangeLabel {
                    visible: root.change24h !== null
                    text: root.fmtChange(root.change24h) + " 24h"
                    wanted: root.changeColor(root.change24h)
                }
                PC3.ToolButton {
                    icon.name: root.hideValues ? "layer-visible-off" : "layer-visible-on"
                    onClicked: root.toggleHideValues()
                    PC3.ToolTip.text: root.hideValues ? "Show values" : "Hide values (also: middle-click the panel)"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    icon.name: "zoom-out"
                    enabled: root.zoom > 0.7
                    onClicked: root.setZoom(root.zoom - 0.1)
                    PC3.ToolTip.text: "Zoom out (Ctrl+−, Ctrl+wheel)"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    text: Math.round(root.zoom * 100) + "%"
                    onClicked: root.setZoom(1)
                    PC3.ToolTip.text: "Reset zoom (Ctrl+0)"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    icon.name: "zoom-in"
                    enabled: root.zoom < 1.8
                    onClicked: root.setZoom(root.zoom + 0.1)
                    PC3.ToolTip.text: "Zoom in (Ctrl+=, Ctrl+wheel)"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    visible: !inWindow
                    icon.name: "window-new"
                    onClicked: root.openWindow()
                    PC3.ToolTip.text: "Open in a window you can move and resize"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh(true)
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
                PC3.CheckBox {
                    text: "Hide balances under $1"
                    checked: Plasmoid.configuration.hideSmall
                    onToggled: Plasmoid.configuration.hideSmall = checked
                }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    text: "Currency:"
                }
                PC3.ComboBox {
                    model: ["USD", "PHP"]
                    currentIndex: Math.max(0, model.indexOf(Plasmoid.configuration.currency))
                    onActivated: index => Plasmoid.configuration.currency = model[index]
                }
                Item { Layout.fillWidth: true }
                PC3.CheckBox {
                    text: "Solid background"
                    checked: Plasmoid.configuration.solidBackground
                    onToggled: Plasmoid.configuration.solidBackground = checked
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: root.priceError !== ""
                wrapMode: Text.Wrap
                color: Kirigami.Theme.neutralTextColor
                text: "Prices not updated: " + root.priceError
            }

            PC3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom  // zoom: data only

                ListView {
                    id: list
                    model: root.wallets
                    clip: true
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: list.count === 0
                        iconName: "wallet-open"
                        text: "No wallets yet"
                        explanation: "Paste a Solana wallet address below. Only public balances are read; nothing can be signed or sent."
                    }

                    delegate: ColumnLayout {
                        id: walletItem
                        required property var modelData
                        readonly property var shown: root.visibleHoldings(modelData)
                        width: ListView.view.width
                        spacing: 0

                        // Wallet heading: label, address, value, actions.
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PC3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: true
                                    text: walletItem.modelData.label + "  ·  " + root.shownMoney(walletItem.modelData.totalUsd)
                                }
                                RowLayout {
                                    PC3.Label {
                                        opacity: 0.6
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                        text: walletItem.modelData.short
                                    }
                                    ChangeLabel {
                                        visible: walletItem.modelData.change24h !== null
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                        text: root.fmtChange(walletItem.modelData.change24h) + " 24h"
                                        wanted: root.changeColor(walletItem.modelData.change24h)
                                    }
                                    PC3.Label {
                                        visible: walletItem.modelData.error !== ""
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                        color: Kirigami.Theme.neutralTextColor
                                        text: walletItem.modelData.loaded ? "(not updated: RPC error)" : "(couldn't load: RPC error)"
                                    }
                                }
                            }
                            PC3.ToolButton {
                                icon.name: "edit-copy"
                                onClicked: { clip.text = walletItem.modelData.address; clip.selectAll(); clip.copy() }
                                PC3.ToolTip.text: "Copy address"
                                PC3.ToolTip.visible: hovered
                            }
                            PC3.ToolButton {
                                icon.name: "internet-web-browser"
                                onClicked: Qt.openUrlExternally("https://solscan.io/account/" + walletItem.modelData.address)
                                PC3.ToolTip.text: "Open on Solscan"
                                PC3.ToolTip.visible: hovered
                            }
                            PC3.ToolButton {
                                icon.name: "edit-delete"
                                enabled: !root.busy
                                onClicked: root.change("--remove", walletItem.modelData.address, "")
                                PC3.ToolTip.text: "Remove wallet"
                                PC3.ToolTip.visible: hovered
                            }
                        }

                        Kirigami.Separator { Layout.fillWidth: true }

                        // Holdings: SOL first, then by value.
                        Repeater {
                            model: walletItem.shown
                            delegate: RowLayout {
                                id: holding
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.largeSpacing

                                Item {
                                    implicitWidth: Kirigami.Units.iconSizes.medium * root.zoom
                                    implicitHeight: Kirigami.Units.iconSizes.medium * root.zoom
                                    Image {
                                        id: logo
                                        anchors.fill: parent
                                        source: holding.modelData.icon
                                        sourceSize.width: width * 2
                                        sourceSize.height: height * 2
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    // Letter badge while the logo loads, or if it has none.
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: logo.status !== Image.Ready
                                        radius: width / 2
                                        color: Qt.alpha(Kirigami.Theme.highlightColor, 0.3)
                                        PC3.Label {
                                            anchors.centerIn: parent
                                            text: holding.modelData.symbol.charAt(0)
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing
                                        PC3.Label {
                                            font.bold: true
                                            text: holding.modelData.symbol + (holding.modelData.verified ? "  ✓" : "")
                                        }
                                        // SOL itself has no token address worth copying.
                                        CopyCA { visible: !holding.modelData.isSol; address: holding.modelData.mint; symbol: holding.modelData.symbol }
                                        DexLink { visible: !holding.modelData.isSol; address: holding.modelData.mint }
                                        Item { Layout.fillWidth: true }
                                    }
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        opacity: 0.6
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                        text: root.shownAmount(holding.modelData.amount) + (holding.modelData.name ? "  ·  " + holding.modelData.name : "")
                                    }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    PC3.Label {
                                        Layout.alignment: Qt.AlignRight
                                        text: root.shownMoney(holding.modelData.usd)
                                        opacity: holding.modelData.usd === null ? 0.5 : 1
                                    }
                                    ChangeLabel {
                                        Layout.alignment: Qt.AlignRight
                                        visible: holding.modelData.change24h !== null
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                        text: root.fmtChange(holding.modelData.change24h)
                                        wanted: root.changeColor(holding.modelData.change24h)
                                    }
                                }
                            }
                        }

                        PC3.Label {
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            visible: walletItem.modelData.holdings.length > walletItem.shown.length
                            opacity: 0.5
                            font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                            text: (walletItem.modelData.holdings.length - walletItem.shown.length) + " small or unpriced balances hidden"
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
                    placeholderText: "Paste a Solana wallet address"
                    enabled: !root.busy
                    onAccepted: root.change("--add", text.trim(), labelField.text)
                }
                PC3.TextField {
                    id: labelField
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                    placeholderText: "Label (optional)"
                    enabled: !root.busy
                    onAccepted: root.change("--add", addressField.text.trim(), text)
                }
                PC3.Button {
                    icon.name: "list-add"
                    text: "Add"
                    enabled: !root.busy && addressField.text.trim() !== ""
                    onClicked: root.change("--add", addressField.text.trim(), labelField.text)
                }
                Connections {
                    target: root
                    function onAdded() {
                        addressField.text = ""
                        labelField.text = ""
                    }
                }
            }
        }
    }

    fullRepresentation: MainView {}

    function openWindow() {
        root.expanded = false
        detached.show()
        detached.raise()
        detached.requestActivate()
    }

    // Panel popups are pinned to the panel; this is the same view as a normal window
    // (movable, resizable, stays open until closed).
    Window {
        id: detached
        title: "Solana Wallet"
        width: Kirigami.Units.gridUnit * 36
        height: Kirigami.Units.gridUnit * 26
        minimumWidth: Kirigami.Units.gridUnit * 24
        minimumHeight: Kirigami.Units.gridUnit * 14
        visible: false

        Rectangle {
            anchors.fill: parent
            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            Kirigami.Theme.inherit: false
            color: Kirigami.Theme.backgroundColor
        }
        Loader {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            active: detached.visible
            sourceComponent: Component {
                MainView {
                    inWindow: true
                }
            }
        }
    }
}
