import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showTime: showTime.checked
    property alias cfg_showTemp: showTemp.checked
    property alias cfg_use24h: clock24.checked
    property alias cfg_fahrenheit: fahrenheit.checked
    property alias cfg_showSunTimes: showSunTimes.checked
    property int cfg_labelEvery
    property alias cfg_dimPast: dimPast.checked
    property alias cfg_iconSize: iconSize.value
    property alias cfg_labelSize: labelSize.value
    property alias cfg_timeSize: timeSize.value
    property alias cfg_lineWidth: lineWidth.value

    property bool cfg_showTimeDefault
    property bool cfg_showTempDefault
    property bool cfg_use24hDefault
    property bool cfg_fahrenheitDefault
    property bool cfg_showSunTimesDefault
    property int cfg_labelEveryDefault
    property bool cfg_dimPastDefault
    property int cfg_iconSizeDefault
    property int cfg_labelSizeDefault
    property int cfg_timeSizeDefault
    property int cfg_lineWidthDefault

    QQC2.ButtonGroup { id: clockGroup }
    QQC2.ButtonGroup { id: unitGroup }

    Kirigami.FormLayout {
        // Beside the weather icon
        QQC2.CheckBox {
            id: showTime
            Kirigami.FormData.label: "Beside the weather icon:"
            text: "Current time"
        }
        QQC2.CheckBox {
            id: showTemp
            text: "Temperature"
        }
        QQC2.Label {
            text: "Turn both off to keep only the weather icon."
            opacity: 0.7
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.RadioButton {
            id: clock24
            QQC2.ButtonGroup.group: clockGroup
            Kirigami.FormData.label: "Clock:"
            text: "24-hour (08:45, 17:30)"
        }
        QQC2.RadioButton {
            QQC2.ButtonGroup.group: clockGroup
            checked: !clock24.checked
            text: "12-hour (8:45 AM, 5:30 PM)"
        }
        QQC2.RadioButton {
            QQC2.ButtonGroup.group: unitGroup
            Kirigami.FormData.label: "Temperature:"
            text: "°C"
            checked: !fahrenheit.checked
        }
        QQC2.RadioButton {
            id: fahrenheit
            QQC2.ButtonGroup.group: unitGroup
            text: "°F"
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showSunTimes
            Kirigami.FormData.label: "Scale:"
            text: "Show sunrise and sunset times"
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: "Hour labels:"
            readonly property var steps: [1, 2, 3, 6]
            model: ["Every hour", "Every 2 hours", "Every 3 hours", "Every 6 hours"]
            currentIndex: Math.max(0, steps.indexOf(cfg_labelEvery))
            onActivated: (i) => cfg_labelEvery = steps[i]
        }
        QQC2.CheckBox {
            id: dimPast
            text: "Fade the hours already past"
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: iconSize
            Kirigami.FormData.label: "Weather icon size:"
            from: 0; to: 96
            textFromValue: (v) => v === 0 ? "Fit" : v + " px"
            valueFromText: (t) => t.toLowerCase().startsWith("fit") ? 0 : parseInt(t)
        }
        QQC2.Label {
            text: "Fit = as big as the panel allows above the line."
            opacity: 0.7
        }
        QQC2.SpinBox {
            id: labelSize
            Kirigami.FormData.label: "Hour labels (pt):"
            from: 5; to: 24
        }
        QQC2.SpinBox {
            id: timeSize
            Kirigami.FormData.label: "Time and temperature (pt):"
            from: 5; to: 28
        }
        QQC2.SpinBox {
            id: lineWidth
            Kirigami.FormData.label: "Line thickness (px):"
            from: 1; to: 12
        }
    }
}
