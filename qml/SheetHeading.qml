import QtQuick

// A section label inside a sheet, in the same accent HelpSheet.qml uses for its
// headings so the two read as the same kind of surface.
Item {
    id: heading

    property string text

    implicitWidth: parent ? parent.width : 0
    implicitHeight: 34

    Text {
        anchors { left: parent.left; leftMargin: 2; bottom: parent.bottom; bottomMargin: 6 }
        text: heading.text
        color: Theme.accent2
        font.pixelSize: Theme.fontSm
        font.weight: Font.Bold
    }
}
