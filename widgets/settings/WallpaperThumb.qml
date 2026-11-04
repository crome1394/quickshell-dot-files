import QtQuick
import QtQuick.Controls

// One wallpaper tile. Live size, colors, and actions sit on the Flow.
// Bracket reads follow the tile slider without rebuilding the grid.
Rectangle {
    id: thumb

    required property var modelData

    function flowProp(name, fallback) {
        const p = thumb.parent
        if (!p)
            return fallback
        const v = p[name]
        return v === undefined ? fallback : v
    }

    readonly property bool isCurrent: thumb.flowProp("currentPath", "") === thumb.modelData.path
    readonly property bool isBusy: thumb.flowProp("busyPath", "") === thumb.modelData.path
    readonly property bool showActions: thumbMa.containsMouse || wpRenameBtnMa.containsMouse || wpDeleteBtnMa.containsMouse

    width: thumb.flowProp("tileW", 160)
    height: thumb.flowProp("tileH", 90)
    radius: thumb.flowProp("chipR", 8)
    color: Qt.rgba(0.05, 0.07, 0.12, 0.88)
    border.width: thumb.isCurrent || thumbMa.containsMouse ? 2 : 1
    border.color: thumb.isCurrent ? thumb.flowProp("onGreen", "#2ee59a")
                  : (thumbMa.containsMouse ? thumb.flowProp("accent", "#fff")
                                           : thumb.flowProp("dividerStrong", "#333"))
    clip: true

    Image {
        id: thumbImage
        anchors.fill: parent
        anchors.margins: 2
        anchors.bottomMargin: 22
        source: thumb.modelData.url || ("file://" + thumb.modelData.path)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: Math.max(296, thumb.flowProp("tilePref", 148) * 2)
        sourceSize.height: Math.max(168, Math.round(thumb.flowProp("tilePref", 148) * 2 * 9 / 16))
        smooth: true
        mipmap: true
    }

    Rectangle {
        anchors.fill: thumbImage
        visible: thumb.isBusy
        color: Qt.rgba(0, 0, 0, 0.45)
        Text {
            anchors.centerIn: parent
            text: "…"
            color: thumb.flowProp("accent", "#fff")
            font.pixelSize: 18
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 22
        color: Qt.rgba(0, 0, 0, 0.72)
        Text {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: {
                const dims = (thumb.modelData.width > 0 && thumb.modelData.height > 0)
                    ? (thumb.modelData.width + "×" + thumb.modelData.height)
                    : "?"
                return thumb.modelData.name + "  ·  " + dims
            }
            color: thumb.isCurrent ? thumb.flowProp("onGreen", "#2ee59a") : thumb.flowProp("subtext", "#aaa")
            font.pixelSize: 10
            font.family: thumb.flowProp("fontFamily", "")
        }
    }

    MouseArea {
        id: thumbMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                const fn = thumb.flowProp("openMenu", null)
                if (typeof fn === "function")
                    fn(thumb.modelData.path, thumb.modelData.name, thumbMa, mouse.x, mouse.y)
            } else {
                const fn = thumb.flowProp("applyPath", null)
                if (typeof fn === "function")
                    fn(thumb.modelData.path)
            }
        }
        ToolTip.visible: containsMouse && !wpRenameBtnMa.containsMouse && !wpDeleteBtnMa.containsMouse
        ToolTip.delay: thumb.flowProp("tooltipDelay", 0)
        ToolTip.text: {
            const dims = (thumb.modelData.width > 0 && thumb.modelData.height > 0)
                ? (thumb.modelData.width + " × " + thumb.modelData.height)
                : "dimensions unknown"
            return thumb.modelData.name + "\n" + dims + "\nClick to apply · Right-click for more"
        }
    }

    Row {
        z: 2
        visible: thumb.showActions
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
        spacing: 4

        Rectangle {
            width: 22
            height: 22
            radius: 4
            color: wpRenameBtnMa.containsMouse ? thumb.flowProp("glassHover", "transparent") : Qt.rgba(0, 0, 0, 0.62)
            border.width: 1
            border.color: wpRenameBtnMa.containsMouse ? thumb.flowProp("accent", "#fff") : thumb.flowProp("pillBorder", "transparent")
            Text {
                anchors.centerIn: parent
                text: "✎"
                color: thumb.flowProp("textColor", "#fff")
                font.pixelSize: 11
            }
            MouseArea {
                id: wpRenameBtnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const fn = thumb.flowProp("beginRename", null)
                    if (typeof fn === "function")
                        fn(thumb.modelData.path, thumb.modelData.name)
                }
            }
        }
        Rectangle {
            width: 22
            height: 22
            radius: 4
            color: wpDeleteBtnMa.containsMouse ? Qt.rgba(1, 0.24, 0.54, 0.28) : Qt.rgba(0, 0, 0, 0.62)
            border.width: 1
            border.color: wpDeleteBtnMa.containsMouse ? thumb.flowProp("offRed", "#FF3D8A") : thumb.flowProp("pillBorder", "transparent")
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: wpDeleteBtnMa.containsMouse ? thumb.flowProp("offRed", "#FF3D8A") : thumb.flowProp("textColor", "#fff")
                font.pixelSize: 11
            }
            MouseArea {
                id: wpDeleteBtnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const fn = thumb.flowProp("beginDelete", null)
                    if (typeof fn === "function")
                        fn(thumb.modelData.path, thumb.modelData.name)
                }
            }
        }
    }
}
