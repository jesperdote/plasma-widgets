// NBA scores on the panel: the current score of the games you follow (a starred game, a team,
// or a pasted ESPN game link), and every game of the day in the popup. Data, following and
// caching live in ../code/nba-scores; this is just the view.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // Zoom for the popup / window contents (70-180%): data only, not the header or footer.
    readonly property real zoom: Plasmoid.configuration.zoom
    function setZoom(z) {
        Plasmoid.configuration.zoom = Math.round(Math.max(0.7, Math.min(1.8, z)) * 10) / 10
    }

    // Run through python3 so it works even if the package was unpacked without the exec bit.
    readonly property string backend: "python3 '" + decodeURIComponent(Qt.resolvedUrl("../code/nba-scores").toString().replace("file://", "")) + "'"
    readonly property int panelFontSize: 14

    property var games: []
    property var followed: []
    property var teams: []
    property bool anyLive: false
    property int liveCount: 0
    property string message: ""
    property bool messageIsError: false
    property bool busy: false
    property string lastJson: ""

    signal followedSomething()

    // "Q3 5:45", "OT 1:02", "7:30 AM" (local), "Final".
    function status(g) {
        if (g.state === "in") {
            if (g.detail.indexOf("Half") >= 0 || g.detail.indexOf("End") >= 0) return g.detail
            const q = g.period > 4 ? (g.period === 5 ? "OT" : (g.period - 4) + "OT") : "Q" + g.period
            return q + " " + g.clock
        }
        if (g.state === "pre" && g.start) {
            const d = new Date(g.start)
            const sameDay = d.toDateString() === new Date().toDateString()
            return Qt.formatDateTime(d, sameDay ? "h:mm AP" : "ddd h:mm AP")
        }
        return g.state === "post" ? "Final" : g.detail
    }

    function line(g) {
        if (g.state === "pre")
            return g.away.abbr + " @ " + g.home.abbr + " · " + status(g)
        return g.away.abbr + " " + g.away.score + "–" + g.home.score + " " + g.home.abbr + " · " + status(g)
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
            const j = JSON.stringify([d.games, d.followed, d.teams])
            if (j !== lastJson) {  // rebuild rows only when something changed
                lastJson = j
                games = d.games
                followed = d.followed
                teams = d.teams
            }
            anyLive = d.anyLive
            liveCount = d.liveCount
            return d
        } catch (e) {
            return null
        }
    }

    function refresh() {
        exec.run(backend + " --json", out => apply(out))
    }

    function follow(mode, text) {
        // Only a game link/id or a team abbreviation reaches the shell.
        text = (text || "").trim()
        if (!/^[A-Za-z0-9:\/._?=&#-]{2,200}$/.test(text)) {
            message = "Paste an ESPN game link (…/gameId/123…) or a team like LAL."
            messageIsError = true
            return
        }
        busy = true
        exec.run(backend + " " + mode + " '" + text + "'", out => {
            busy = false
            const d = apply(out)
            message = d ? d.message : "Something went wrong running nba-scores."
            messageIsError = !d || !d.ok
            if (d && d.ok && mode === "--follow")
                root.followedSomething()
        })
    }

    // Every 15 s while a game is live, every 2 minutes otherwise (the backend caches 10 s).
    Timer {
        interval: root.anyLive ? 15000 : 120000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    toolTipMainText: "NBA"
    toolTipSubText: followed.length ? followed.map(g => line(g)).join("\n") + "\nClick for all games"
                                    : (liveCount ? liveCount + " games live" : "No games live") + "\nClick for today's games"

    compactRepresentation: MouseArea {
        readonly property bool solid: Plasmoid.configuration.solidBackground
        Layout.minimumWidth: label.implicitWidth + (solid ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

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

        PC3.Label {
            id: label
            anchors.centerIn: parent
            font.pointSize: root.panelFontSize
            text: "🏀 " + (root.followed.length ? root.followed.slice(0, 2).map(g => root.line(g)).join("  |  ")
                                                : (root.liveCount ? root.liveCount + " live" : "NBA"))
        }
    }

    // One team's side of a score line: logo, abbreviation, score.
    component TeamCell: RowLayout {
        property var team: ({})
        property bool showScore: true
        property bool dim: false
        spacing: Kirigami.Units.smallSpacing
        opacity: dim ? 0.55 : 1
        Image {
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium * root.zoom
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium * root.zoom
            source: team.logo || ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }
        PC3.Label { text: team.abbr || "?"; font.bold: true }
        PC3.Label { visible: showScore; text: team.score || ""; font.bold: team.winner || false }
    }

    // The popup's contents, also used for the movable window below.
    component MainView: PlasmaExtras.Representation {
        property bool inWindow: false
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        collapseMarginsHint: true

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: event => root.setZoom(root.zoom + (event.angleDelta.y > 0 ? 0.1 : -0.1))
        }
        Shortcut { sequences: [StandardKey.ZoomIn, "Ctrl+="]; onActivated: root.setZoom(root.zoom + 0.1) }
        Shortcut { sequence: StandardKey.ZoomOut; onActivated: root.setZoom(root.zoom - 0.1) }
        Shortcut { sequence: "Ctrl+0"; onActivated: root.setZoom(1) }

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: "🏀 NBA" + (root.liveCount ? " · " + root.liveCount + " live" : "")
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

            // Teams being followed, each removable.
            RowLayout {
                Layout.fillWidth: true
                visible: root.teams.length > 0
                PC3.Label { text: "Teams:"; opacity: 0.7 }
                Repeater {
                    model: root.teams
                    delegate: PC3.Button {
                        required property var modelData
                        text: modelData + "  ✕"
                        enabled: !root.busy
                        onClicked: root.follow("--unfollow", modelData)
                        PC3.ToolTip.text: "Stop following " + modelData
                        PC3.ToolTip.visible: hovered
                    }
                }
                Item { Layout.fillWidth: true }
                PC3.CheckBox {
                    text: "Solid background"
                    checked: Plasmoid.configuration.solidBackground
                    onToggled: Plasmoid.configuration.solidBackground = checked
                }
            }
            PC3.CheckBox {
                visible: root.teams.length === 0
                Layout.alignment: Qt.AlignRight
                text: "Solid background"
                checked: Plasmoid.configuration.solidBackground
                onToggled: Plasmoid.configuration.solidBackground = checked
            }

            PC3.ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom  // zoom: data only

                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: Kirigami.Units.largeSpacing

                    // ---- Followed games, with details --------------------------------------
                    Kirigami.Heading {
                        visible: root.followed.length > 0
                        level: 4
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom * 1.1
                        text: "Following"
                    }
                    Repeater {
                        model: root.followed
                        delegate: ColumnLayout {
                            id: card
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Layout.fillWidth: true
                                TeamCell { team: card.modelData.away; showScore: card.modelData.state !== "pre" }
                                PC3.Label { text: card.modelData.state === "pre" ? "@" : "–"; opacity: 0.6 }
                                TeamCell { team: card.modelData.home; showScore: card.modelData.state !== "pre" }
                                PC3.Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    color: card.modelData.state === "in" ? "#F85149" : Kirigami.Theme.textColor
                                    font.bold: card.modelData.state === "in"
                                    text: (card.modelData.state === "in" ? "● " : "") + root.status(card.modelData)
                                }
                                PC3.ToolButton {
                                    icon.name: "internet-web-browser"
                                    onClicked: Qt.openUrlExternally(card.modelData.link)
                                    PC3.ToolTip.text: "Open on ESPN"
                                    PC3.ToolTip.visible: hovered
                                }
                                PC3.ToolButton {
                                    icon.name: "list-remove"
                                    enabled: !root.busy
                                    onClicked: root.follow("--unfollow", card.modelData.id)
                                    PC3.ToolTip.text: "Stop following this game (a followed team keeps it on)"
                                    PC3.ToolTip.visible: hovered
                                }
                            }
                            // Win probability bar (home share), while it is meaningful.
                            RowLayout {
                                Layout.fillWidth: true
                                visible: card.modelData.homeWinPct !== null && card.modelData.homeWinPct !== undefined && card.modelData.state === "in"
                                PC3.Label { text: card.modelData.away.abbr + " " + (100 - (card.modelData.homeWinPct || 0)) + "%"; opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: Kirigami.Units.smallSpacing * 1.5
                                    radius: height / 2
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.25)
                                    Rectangle {
                                        anchors.right: parent.right
                                        height: parent.height
                                        radius: parent.radius
                                        width: parent.width * (card.modelData.homeWinPct || 0) / 100
                                        color: Kirigami.Theme.highlightColor
                                    }
                                }
                                PC3.Label { text: (card.modelData.homeWinPct || 0) + "% " + card.modelData.home.abbr; opacity: 0.7; font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom }
                            }
                            // Top scorer / rebounder / assists per team.
                            Repeater {
                                model: card.modelData.leaders || []
                                delegate: PC3.Label {
                                    required property var modelData
                                    opacity: 0.8
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                    text: modelData.team + " · " + modelData.stat + ": " + modelData.player + " " + modelData.value
                                }
                            }
                            // Last plays, newest first.
                            Repeater {
                                model: card.modelData.state === "in" ? (card.modelData.plays || []).slice(0, 3) : []
                                delegate: PC3.Label {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    opacity: 0.6
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize * root.zoom
                                    text: "▸ " + modelData
                                }
                            }
                            Kirigami.Separator { Layout.fillWidth: true }
                        }
                    }

                    // ---- Every game of the day --------------------------------------------
                    Kirigami.Heading {
                        level: 4
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.zoom * 1.1
                        text: "Today's games"
                    }
                    PC3.Label {
                        visible: root.games.length === 0
                        opacity: 0.6
                        text: "No games scheduled."
                    }
                    Repeater {
                        model: root.games
                        delegate: RowLayout {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            TeamCell { team: row.modelData.away; showScore: row.modelData.state !== "pre"; dim: row.modelData.state === "post" && !row.modelData.away.winner }
                            PC3.Label { text: row.modelData.state === "pre" ? "@" : "–"; opacity: 0.6 }
                            TeamCell { team: row.modelData.home; showScore: row.modelData.state !== "pre"; dim: row.modelData.state === "post" && !row.modelData.home.winner }
                            PC3.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                color: row.modelData.state === "in" ? "#F85149" : Kirigami.Theme.textColor
                                opacity: row.modelData.state === "post" ? 0.6 : 1
                                text: (row.modelData.state === "in" ? "● " : "") + root.status(row.modelData)
                            }
                            PC3.ToolButton {
                                text: row.modelData.followed ? "★" : "☆"
                                enabled: !root.busy
                                onClicked: root.follow(row.modelData.followed ? "--unfollow" : "--follow", row.modelData.id)
                                PC3.ToolTip.text: row.modelData.followed ? "Stop following this game" : "Follow this game on the panel"
                                PC3.ToolTip.visible: hovered
                            }
                            PC3.ToolButton {
                                icon.name: "internet-web-browser"
                                onClicked: Qt.openUrlExternally(row.modelData.link)
                                PC3.ToolTip.text: "Open on ESPN"
                                PC3.ToolTip.visible: hovered
                            }
                        }
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
                    id: followField
                    Layout.fillWidth: true
                    placeholderText: "Follow a team (LAL, GSW…) or paste an ESPN game link"
                    enabled: !root.busy
                    onAccepted: root.follow("--follow", text)
                    Connections {
                        target: root
                        function onFollowedSomething() { followField.text = "" }
                    }
                }
                PC3.Button {
                    icon.name: "list-add"
                    text: "Follow"
                    enabled: !root.busy && followField.text.trim() !== ""
                    onClicked: root.follow("--follow", followField.text)
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

    // Panel popups are pinned to the panel; this is the same view as a normal window.
    Window {
        id: detached
        title: "NBA Scores"
        width: Kirigami.Units.gridUnit * 32
        height: Kirigami.Units.gridUnit * 34
        minimumWidth: Kirigami.Units.gridUnit * 22
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
