import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_iconSize: iconSize.value
    property alias cfg_labelSize: labelSize.value
    property alias cfg_timeSize: timeSize.value
    property alias cfg_lineWidth: lineWidth.value
    property int cfg_iconSizeDefault
    property int cfg_labelSizeDefault
    property int cfg_timeSizeDefault
    property int cfg_lineWidthDefault

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: iconSize
            Kirigami.FormData.label: "Weather icon size (px):"
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
