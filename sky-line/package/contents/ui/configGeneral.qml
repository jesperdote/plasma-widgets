import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property real cfg_latitude
    property real cfg_longitude
    property alias cfg_locationCommand: cmd.text
    property real cfg_latitudeDefault
    property real cfg_longitudeDefault
    property string cfg_locationCommandDefault

    Kirigami.FormLayout {
        QQC2.TextField {
            Kirigami.FormData.label: "Latitude:"
            text: cfg_latitude
            validator: DoubleValidator { bottom: -90; top: 90; decimals: 4; notation: DoubleValidator.StandardNotation }
            onTextEdited: if (acceptableInput) cfg_latitude = parseFloat(text)
        }
        QQC2.TextField {
            Kirigami.FormData.label: "Longitude:"
            text: cfg_longitude
            validator: DoubleValidator { bottom: -180; top: 180; decimals: 4; notation: DoubleValidator.StandardNotation }
            onTextEdited: if (acceptableInput) cfg_longitude = parseFloat(text)
        }
        QQC2.TextField {
            id: cmd
            Kirigami.FormData.label: "Or a location command:"
            placeholderText: "prints lat,lon"
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: "Decimal degrees; north and east are positive. When a command is set, its output is used instead (it runs once an hour)."
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
    }
}
