// Solana token watchlist for the panel. Data, validation and the watchlist file
// (~/.config/sol-mc/watchlist) all live in ../code/sol-mc; this is just the view.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
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
    property var sol: null  // {price, change24h} for the SOL readout
    function solPrice() {
        return sol ? "$" + sol.price.toFixed(2) : ""
    }
    // The popup list is a ListModel updated row by row (each row's data as JSON), so price
    // updates change the existing rows in place instead of rebuilding them: whatever is being
    // typed in a row (alert levels, a custom buy amount) survives.
    ListModel { id: tokenModel }
    function syncList(arr) {
        for (let i = 0; i < arr.length; i++) {
            const j = JSON.stringify(arr[i])
            if (i < tokenModel.count && tokenModel.get(i).address === arr[i].address) {
                if (tokenModel.get(i).json !== j)
                    tokenModel.setProperty(i, "json", j)
            } else {
                // Added, removed or reordered: rebuild from here down.
                if (i < tokenModel.count)
                    tokenModel.remove(i, tokenModel.count - i)
                tokenModel.append({ address: arr[i].address, json: j })
            }
        }
        if (tokenModel.count > arr.length)
            tokenModel.remove(arr.length, tokenModel.count - arr.length)
    }
    property string editingAddress: ""
    onExpandedChanged: if (!expanded) { editingAddress = ""; tradingFor = ""; quote = null; exportedKey = "" }

    // Optional manual trading, only when the separate `sol-trade` tool is installed in ~/bin
    // (it holds the trading wallet's key in the desktop keyring). Every trade is a quote the
    // user confirms; nothing is automatic.
    readonly property string trader: "\"$HOME/bin/sol-trade\""
    property bool tradeAvailable: false
    property string tradeAddress: ""
    property real tradeSol: 0
    property var portfolio: null             // positions, P&L and trades from `sol-trade portfolio`
    property bool showPortfolio: false
    readonly property var openPositions: portfolio ? portfolio.positions.filter(p => p.amount > 0) : []
    readonly property real openCost: openPositions.reduce((a, p) => a + (p.costSol || 0), 0)
    readonly property real openPnl: openPositions.reduce((a, p) => a + (p.unrealizedSol || 0), 0)

    readonly property var pnlFormats: [
        { key: "pct", label: "%" }, { key: "sol", label: "SOL" }, { key: "usd", label: "USD" },
        { key: "sol+pct", label: "SOL + %" }, { key: "usd+pct", label: "USD + %" }
    ]

    // Open P&L for the panel, e.g. "+$1.15 (+2.8%)".
    function pnlText() {
        const sign = openPnl >= 0 ? "+" : "−"
        const pct = sign + Math.abs(openCost ? openPnl / openCost * 100 : 0).toFixed(1) + "%"
        const usd = sign + "$" + Math.abs(openPnl * (portfolio ? portfolio.solUsd : 0)).toFixed(2)
        const sol = fmtSol(openPnl, true)
        switch (Plasmoid.configuration.pnlDisplay) {
            case "sol": return sol
            case "usd": return usd
            case "sol+pct": return sol + " (" + pct + ")"
            case "usd+pct": return usd + " (" + pct + ")"
            default: return pct
        }
    }

    function fmtSol(v, signed) {
        const a = Math.abs(v)
        const n = a >= 1 ? a.toFixed(3) : a >= 0.01 ? a.toFixed(4) : a.toFixed(6)
        return (signed ? (v >= 0 ? "+" : "−") : (v < 0 ? "−" : "")) + n + " SOL"
    }

    function fmtQty(a) {
        if (a >= 1e9) return (a / 1e9).toFixed(2) + "B"
        if (a >= 1e6) return (a / 1e6).toFixed(2) + "M"
        if (a >= 1000) return Math.round(a).toLocaleString(Qt.locale("en_US"), "f", 0)
        return Number(a.toPrecision(4)).toString()
    }

    function ago(t) {
        const s = Math.max(0, Math.round(Date.now() / 1000 - t))
        return s < 60 ? s + " s ago" : s < 3600 ? Math.round(s / 60) + " min ago" : s < 86400 ? Math.round(s / 3600) + " h ago" : Math.round(s / 86400) + " d ago"
    }
    property var tradeCfg: ({ buyAmounts: [0.01, 0.05, 0.1], sellPercents: [25, 50, 100] })
    property string tradingFor: ""          // token row with the trade line open
    onTradingForChanged: quote = null
    property var quote: null                 // last quote, waiting for Confirm
    property real quoteAt: 0
    property int quoteLeft: 0
    property string lastTxUrl: ""
    property string exportedKey: ""          // only while the export panel is open

    function trade(cmd, cb) {
        exec.run(trader + " " + cmd, out => {
            let d = null
            try { d = JSON.parse(out) } catch (e) {}
            cb(d)
        })
    }

    function refreshTradeWallet() {
        trade("portfolio", d => {
            if (d && d.ok) {
                tradeAvailable = true
                tradeAddress = d.address
                tradeSol = d.sol || 0
                portfolio = d
                return
            }
            // RPC hiccup or no wallet: fall back to the cheap balance call, keep the last portfolio.
            trade("balance", b => {
                tradeAvailable = !!(b && b.address)
                if (tradeAvailable) {
                    tradeAddress = b.address
                    tradeSol = b.sol || 0
                }
            })
        })
    }

    function requestQuote(side, mint, amount) {
        amount = String(amount).trim()
        if (!/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(mint) || !/^[0-9]*\.?[0-9]+$/.test(amount))
            return
        busy = true
        quote = null
        message = "Getting a quote from Jupiter…"
        messageIsError = false
        trade("quote " + side + " " + mint + " " + amount, d => {
            busy = false
            if (!d || !d.ok) {
                message = d ? d.message : "Couldn't run sol-trade."
                messageIsError = true
                return
            }
            message = ""
            quote = d
            quoteAt = Date.now()
            quoteLeft = d.expiresIn
        })
    }

    function confirmQuote() {
        if (!quote || !/^[0-9a-fA-F-]{20,64}$/.test(quote.requestId))
            return
        const q = quote
        quote = null
        busy = true
        message = "Sending…"
        messageIsError = false
        trade("execute " + q.requestId, d => {
            busy = false
            message = d ? d.message : "Couldn't run sol-trade."
            messageIsError = !d || !d.ok
            lastTxUrl = d && d.url ? d.url : ""
            refreshTradeWallet()
            if (d && d.ok)
                tradingFor = ""
        })
    }

    Timer {
        // Quote countdown; Jupiter quotes expire after ~45 s.
        interval: 1000
        repeat: true
        running: root.quote !== null
        onTriggered: {
            root.quoteLeft = Math.max(0, root.quote.expiresIn - Math.round((Date.now() - root.quoteAt) / 1000))
            if (root.quoteLeft === 0) {
                root.quote = null
                root.message = "Quote expired: pick an amount again."
                root.messageIsError = true
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshTradeWallet()
            root.trade("config", d => { if (d && d.ok) root.tradeCfg = d })
        }
    }

    Timer {
        // After "Copy key": wipe Klipper's history, which would otherwise keep the key forever.
        id: clipboardWipe
        interval: 60000
        onTriggered: exec.run("qdbus6 org.kde.klipper /klipper org.kde.klipper.klipper.clearClipboardHistory", () => {})
    }
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

    // Alert sound choice (the backend plays it when an alert fires).
    property var soundChoices: [{ name: "None (silent)", path: "none" }]
    property string alertSound: ""
    function loadSounds() {
        exec.run(backend + " --sounds", out => {
            try {
                const d = JSON.parse(out)
                soundChoices = [{ name: "None (silent)", path: "none" }].concat(d.sounds)
                alertSound = d.current
            } catch (e) {}
        })
    }
    function quotedPath(p) {
        return p.indexOf("'") < 0 ? "'" + p + "'" : ""  // paths come from the backend's own list
    }
    Component.onCompleted: loadSounds()

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
                syncList(d.tokens)
            }
            age = d.age || 0
            sol = d.sol || sol
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
            // Open positions' P&L, when trading with sol-trade; format picked in the Positions section.
            FrameLabel {
                visible: root.openPositions.length > 0 && root.openCost > 0
                text: "💼 " + root.pnlText()
                frameColor: root.openPnl >= 0 ? root.upColor : root.downColor
                font.pointSize: root.panelFontSize
            }
        }
    }

    // Quote waiting for Confirm, shown under whatever asked for it.
    component QuoteConfirm: RowLayout {
        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.quote ? root.quote.summary
                  + "  ·  impact " + root.quote.priceImpactPct.toFixed(2) + "%"
                  + "  ·  fee " + (root.quote.feeBps / 100) + "%"
                  + "  ·  " + root.quoteLeft + " s" : ""
        }
        PC3.Button {
            icon.name: "dialog-ok-apply"
            text: "Confirm"
            enabled: !root.busy
            onClicked: root.confirmQuote()
        }
        PC3.Button {
            icon.name: "dialog-cancel"
            text: "Cancel"
            onClicked: root.quote = null
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
        Layout.preferredWidth: Kirigami.Units.gridUnit * 36
        Layout.preferredHeight: Kirigami.Units.gridUnit * 20
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                                    Layout.fillWidth: true
                    level: 3
                    text: "Solana watchlist" + (root.sol ? "  ·  SOL " + root.solPrice() + " " + root.fmt(root.sol.change24h) : "")
                }
                PC3.Label {
                    opacity: 0.6
                    text: root.age > 120 ? "updated " + Math.round(root.age / 60) + " min ago" : ""
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
                PC3.Label {
                    text: "Alert sound:"
                }
                PC3.ComboBox {
                    id: soundBox
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    model: root.soundChoices
                    textRole: "name"
                    currentIndex: Math.max(0, root.soundChoices.findIndex(c => c.path === root.alertSound))
                    onActivated: index => {
                        const path = root.soundChoices[index].path
                        exec.run(root.backend + " --set-sound " + root.quotedPath(path), out => {
                            root.alertSound = path
                            if (path !== "none")
                                exec.run(root.backend + " --play " + root.quotedPath(path), () => {})
                        })
                    }
                }
                PC3.ToolButton {
                    icon.name: "media-playback-start"
                    enabled: root.alertSound !== "none"
                    onClicked: exec.run(root.backend + " --play " + root.quotedPath(root.alertSound), () => {})
                    PC3.ToolTip.text: "Play the alert sound"
                    PC3.ToolTip.visible: hovered
                }
                Item { Layout.fillWidth: true }
                PC3.CheckBox {
                    text: "Solid background"
                    checked: Plasmoid.configuration.solidBackground
                    onToggled: Plasmoid.configuration.solidBackground = checked
                }
            }

            // Token list and Positions share the height (by these preferred sizes) and both
            // grow/shrink with the popup or window.
            PC3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom  // zoom: data only

                ListView {
                    id: list
                    model: tokenModel
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
                        required property string json
                        readonly property var modelData: JSON.parse(json)
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
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                    text: item.modelData.address
                                }
                                PC3.Label {
                                    readonly property var al: item.modelData.alerts || {}
                                    visible: !item.editing && (al.above || al.below) ? true : false
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                    text: "🔔 " + [al.above ? "above " + al.above.text : "", al.below ? "below " + al.below.text : ""].filter(x => x).join(" · ")
                                }
                            }
                            PC3.ToolButton {
                                visible: root.tradeAvailable
                                icon.name: "wallet-open"
                                checked: root.tradingFor === item.modelData.address
                                enabled: item.modelData.found
                                onClicked: root.tradingFor = checked ? "" : item.modelData.address
                                PC3.ToolTip.text: "Buy / sell with the trading wallet"
                                PC3.ToolTip.visible: hovered
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
                          // Trade line, opened with the wallet button: presets, then a quote to confirm.
                          ColumnLayout {
                              visible: root.tradingFor === item.modelData.address
                              Layout.topMargin: Kirigami.Units.smallSpacing
                              spacing: Kirigami.Units.smallSpacing
                              RowLayout {
                                  visible: !root.quote || root.quote.mint !== item.modelData.address
                                  PC3.Label { text: "Buy with" }
                                  Repeater {
                                      model: root.tradeCfg.buyAmounts
                                      delegate: PC3.Button {
                                          required property var modelData
                                          text: modelData + " SOL"
                                          enabled: !root.busy
                                          onClicked: root.requestQuote("buy", item.modelData.address, modelData)
                                      }
                                  }
                                  PC3.TextField {
                                      id: customBuy
                                      Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                      placeholderText: "SOL"
                                      onAccepted: root.requestQuote("buy", item.modelData.address, text)
                                  }
                                  Item { Layout.fillWidth: true }
                                  PC3.Label { text: "Sell" }
                                  Repeater {
                                      model: root.tradeCfg.sellPercents
                                      delegate: PC3.Button {
                                          required property var modelData
                                          text: modelData + "%"
                                          enabled: !root.busy
                                          onClicked: root.requestQuote("sell", item.modelData.address, modelData)
                                      }
                                  }
                              }
                              QuoteConfirm {
                                  visible: !!root.quote && root.quote.mint === item.modelData.address
                              }
                          }
                          // Alert editor, opened with the bell button.
                          RowLayout {
                              visible: item.editing
                              Layout.topMargin: Kirigami.Units.smallSpacing
                              // Start from the saved levels each time the editor opens.
                              onVisibleChanged: if (visible) {
                                  const al = item.modelData.alerts || {}
                                  aboveField.text = al.above ? al.above.text.replace("$", "") : ""
                                  belowField.text = al.below ? al.below.text.replace("$", "") : ""
                              }
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

            // Positions and recent trades (from the chain), opened from the trading wallet bar.
            PC3.ScrollView {
                id: portfolioScroll
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom  // zoom: data only
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                Layout.minimumHeight: Kirigami.Units.gridUnit * 5
                // Don't take more room than the content needs.
                Layout.maximumHeight: portfolioColumn.implicitHeight
                visible: root.tradeAvailable && root.showPortfolio && root.portfolio !== null
                contentWidth: availableWidth  // full width, no sideways scrolling
                ColumnLayout {
                    id: portfolioColumn
                    width: portfolioScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom * (level <= 3 ? 1.3 : 1.1)
                        level: 4
                        text: "Positions"
                    }
                    RowLayout {
                        PC3.Label {
                            text: "Panel shows open P&L as"
                            opacity: 0.8
                        }
                        PC3.ComboBox {
                            model: root.pnlFormats
                            textRole: "label"
                            currentIndex: Math.max(0, root.pnlFormats.findIndex(f => f.key === Plasmoid.configuration.pnlDisplay))
                            onActivated: index => Plasmoid.configuration.pnlDisplay = root.pnlFormats[index].key
                        }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.portfolio ? "Total " + root.fmtSol(root.portfolio.totalSol) + " ($" + root.portfolio.totalUsd.toFixed(2) + ")"
                              + "  ·  open P&L " + root.fmtSol(root.portfolio.unrealizedSol, true)
                              + "  ·  realized " + root.fmtSol(root.portfolio.realizedSol, true) : ""
                    }
                    PC3.Label {
                        visible: root.portfolio && root.portfolio.positions.length === 0
                        opacity: 0.6
                        text: "No positions yet."
                    }
                    RowLayout {
                        visible: root.portfolio && root.portfolio.emptyAccounts > 0
                        PC3.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            opacity: 0.8
                            text: root.portfolio ? root.portfolio.emptyAccounts + " empty token account(s) still hold "
                                  + root.fmtSol(root.portfolio.reclaimableSol) + " in deposits" : ""
                        }
                        PC3.Button {
                            icon.name: "edit-undo"
                            text: "Reclaim"
                            enabled: !root.busy
                            onClicked: {
                                root.busy = true
                                root.message = "Closing empty token accounts…"
                                root.messageIsError = false
                                root.trade("reclaim", d => {
                                    root.busy = false
                                    root.message = d ? d.message : "Couldn't run sol-trade."
                                    root.messageIsError = !d || !d.ok
                                    root.lastTxUrl = d && d.url ? d.url : root.lastTxUrl
                                    root.refreshTradeWallet()
                                })
                            }
                            PC3.ToolTip.text: "Close token accounts left at 0 after selling and get their SOL deposit back"
                            PC3.ToolTip.visible: hovered
                        }
                    }
                    Repeater {
                        model: root.portfolio ? root.portfolio.positions : []
                        delegate: ColumnLayout {
                            id: pos
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            opacity: modelData.amount > 0 ? 1 : 0.55  // closed: only realized P&L left
                            RowLayout {
                                Layout.fillWidth: true
                                Image {
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium * root.zoom
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium * root.zoom
                                    source: pos.modelData.icon
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    clip: true
                                    spacing: 0
                                    PC3.Label {
                                        font.bold: true
                                        text: pos.modelData.symbol + (pos.modelData.amount > 0 ? "  ·  " + root.fmtQty(pos.modelData.amount) : "  ·  closed")
                                    }
                                    PC3.Label {
                                        opacity: 0.7
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                        text: pos.modelData.amount > 0
                                              ? "value " + root.fmtSol(pos.modelData.valueSol) + " ($" + pos.modelData.valueUsd.toFixed(2) + ")"
                                                + (pos.modelData.costSol ? "  ·  cost " + root.fmtSol(pos.modelData.costSol) : "")
                                              : "realized " + root.fmtSol(pos.modelData.realizedSol, true)
                                    }
                                }
                                FrameLabel {
                                    visible: pos.modelData.unrealizedSol !== null
                                    text: pos.modelData.unrealizedSol === null ? "" : root.fmtSol(pos.modelData.unrealizedSol, true)
                                          + " (" + (pos.modelData.unrealizedPct >= 0 ? "+" : "") + pos.modelData.unrealizedPct.toFixed(1) + "%)"
                                    frameColor: (pos.modelData.unrealizedSol || 0) >= 0 ? root.upColor : root.downColor
                                }
                                PC3.Button {
                                    visible: pos.modelData.amount > 0
                                    text: "Sell 50%"
                                    enabled: !root.busy
                                    onClicked: { root.tradingFor = ""; root.requestQuote("sell", pos.modelData.mint, 50) }
                                }
                                PC3.Button {
                                    visible: pos.modelData.amount > 0
                                    text: "Sell all"
                                    enabled: !root.busy
                                    onClicked: { root.tradingFor = ""; root.requestQuote("sell", pos.modelData.mint, 100) }
                                }
                            }
                            QuoteConfirm {
                                Layout.fillWidth: true
                                visible: !!root.quote && root.quote.mint === pos.modelData.mint && root.tradingFor === ""
                            }
                        }
                    }
                    Kirigami.Heading {
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom * (level <= 3 ? 1.3 : 1.1)
                        level: 4
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: "Recent trades"
                    }
                    Repeater {
                        model: root.portfolio ? root.portfolio.trades.slice(0, 10) : []
                        delegate: RowLayout {
                            id: tr
                            required property var modelData
                            Layout.fillWidth: true
                            PC3.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                readonly property var t: tr.modelData
                                text: t.kind === "buy" ? "✓ Bought " + root.fmtQty(t.amount) + " " + t.symbol + " for " + root.fmtSol(-t.sol)
                                    : t.kind === "sell" ? "✓ Sold " + root.fmtQty(-t.amount) + " " + t.symbol + " for " + root.fmtSol(t.sol)
                                    : t.kind === "failed" ? "✗ Failed transaction"
                                    : t.kind === "deposit" ? "↓ Received " + root.fmtSol(t.sol)
                                    : "↑ Sent " + root.fmtSol(-t.sol)
                            }
                            PC3.Label {
                                opacity: 0.6
                                font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                text: tr.modelData.time ? root.ago(tr.modelData.time) : ""
                            }
                            PC3.ToolButton {
                                icon.name: "internet-web-browser"
                                onClicked: Qt.openUrlExternally(tr.modelData.url)
                                PC3.ToolTip.text: "Open on Solscan"
                                PC3.ToolTip.visible: hovered
                            }
                        }
                    }
                }
            }

            // Trading wallet (only with sol-trade installed): address, SOL, key export for Phantom.
            RowLayout {
                Layout.fillWidth: true
                visible: root.tradeAvailable
                PC3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    opacity: 0.8
                    text: "Trading wallet " + root.tradeAddress.slice(0, 4) + "…" + root.tradeAddress.slice(-4)
                          + "  ·  " + root.tradeSol.toFixed(4) + " SOL"
                }
                PC3.Button {
                    checkable: true
                    checked: root.showPortfolio
                    icon.name: "view-list-details"
                    text: "Positions"
                    onToggled: root.showPortfolio = checked
                }
                PC3.ToolButton {
                    visible: root.lastTxUrl !== ""
                    icon.name: "internet-web-browser"
                    onClicked: Qt.openUrlExternally(root.lastTxUrl)
                    PC3.ToolTip.text: "Last trade on Solscan"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    icon.name: "edit-copy"
                    onClicked: { clip.text = root.tradeAddress; clip.selectAll(); clip.copy() }
                    PC3.ToolTip.text: "Copy address (send SOL here to fund it)"
                    PC3.ToolTip.visible: hovered
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refreshTradeWallet()
                    PC3.ToolTip.text: "Refresh balance"
                    PC3.ToolTip.visible: hovered
                }
                PC3.Button {
                    text: root.exportedKey ? "Hide key" : "Export key…"
                    onClicked: {
                        if (root.exportedKey) {
                            root.exportedKey = ""
                            return
                        }
                        exec.run(root.trader + " export", out => {
                            const k = (out || "").trim()
                            root.exportedKey = /^[1-9A-HJ-NP-Za-km-z]{80,90}$/.test(k) ? k : ""
                            if (!root.exportedKey) { root.message = "Couldn't read the key from the keyring."; root.messageIsError = true }
                        })
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.exportedKey !== ""
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.negativeTextColor
                    text: "Anyone with this key controls the trading wallet. Paste it only into Phantom (Add wallet → Import Private Key). "
                          + "Copy also clears the clipboard history 60 s later."
                }
                RowLayout {
                    PC3.TextField {
                        id: keyField
                        Layout.fillWidth: true
                        readOnly: true
                        text: root.exportedKey
                        echoMode: revealKey.checked ? TextInput.Normal : TextInput.Password
                    }
                    PC3.CheckBox {
                        id: revealKey
                        text: "Show"
                    }
                    PC3.Button {
                        icon.name: "edit-copy"
                        text: "Copy"
                        onClicked: { clip.text = root.exportedKey; clip.selectAll(); clip.copy(); clip.text = ""; clipboardWipe.restart() }
                    }
                }
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
        title: "Solana Watchlist"
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
