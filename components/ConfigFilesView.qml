import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Static Hyprland config files under ~/.config/hypr/config/ with bat syntax view.
Item {
    id: root

    property var files: []
    property string configDir: (Quickshell.env("HOME") + "/.config/hypr/config")
    property string selectedFileId: "monitors"
    property string fileSearch: ""
    property string globalFilter: ""

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"

    function entryPath(entry) {
        if (!entry || !entry.file) return ""
        const base = entry.dir || configDir
        return base + "/" + entry.file
    }

    function currentEntry() {
        for (let i = 0; i < files.length; i++) {
            if (files[i].id === selectedFileId) return files[i]
        }
        return files.length ? files[0] : null
    }

    function currentFilePath() {
        const entry = currentEntry()
        return entry ? entryPath(entry) : ""
    }

    function currentBatLanguage() {
        const entry = currentEntry()
        return (entry && entry.batLanguage) ? entry.batLanguage : ""
    }

    function filteredFiles() {
        const q = (fileSearch && fileSearch.trim()) ? fileSearch.toLowerCase().trim() : ""
        if (!q) return files
        return files.filter(function(f) {
            return (f.label && f.label.toLowerCase().indexOf(q) !== -1) ||
                   (f.file && f.file.toLowerCase().indexOf(q) !== -1) ||
                   (f.id && f.id.toLowerCase().indexOf(q) !== -1)
        })
    }

    function selectFileId(fileId) {
        if (!fileId) return
        selectedFileId = fileId
        fileSearch = ""
        syncComboIndex()
    }

    function currentFileIndex() {
        for (let i = 0; i < files.length; i++) {
            if (files[i].id === selectedFileId) return i
        }
        return -1
    }

    function prevFile() {
        if (!files.length) return
        const idx = currentFileIndex()
        const nextIdx = idx <= 0 ? files.length - 1 : idx - 1
        selectFileId(files[nextIdx].id)
    }

    function nextFile() {
        if (!files.length) return
        const idx = currentFileIndex()
        const nextIdx = idx < 0 || idx >= files.length - 1 ? 0 : idx + 1
        selectFileId(files[nextIdx].id)
    }

    function focusNav() {
        navFocus.forceActiveFocus()
    }

    function focusScroll() {
        batViewer.focusScroll()
    }

    function handleNavKey(event) {
        if (filePopup.opened) return false
        if (event.key === Qt.Key_Left) {
            prevFile()
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Right) {
            nextFile()
            event.accepted = true
            return true
        }
        if (batViewer.handleScrollKey(event)) return true
        return false
    }

    function syncComboIndex() {
        for (let i = 0; i < files.length; i++) {
            if (files[i].id === selectedFileId) {
                fileCombo.currentIndex = i
                return
            }
        }
        if (files.length > 0) fileCombo.currentIndex = 0
    }

    function plainText() {
        return batViewer.plainText()
    }

    function refreshBat() {
        batViewer.refresh()
    }

    function pageScroll(direction) {
        batViewer.pageScroll(direction)
    }

    function lineScroll(direction) {
        batViewer.lineScroll(direction)
    }

    function resetScroll() {
        batViewer.resetScroll()
    }

    onFilesChanged: syncComboIndex()
    onSelectedFileIdChanged: {
        batViewer.resetScroll()
        batViewer.refresh()
        Qt.callLater(function() {
            batViewer.forceLayoutRefresh()
            batViewer.focusScroll()
        })
    }
    onVisibleChanged: {
        if (visible) Qt.callLater(function() {
            batViewer.forceLayoutRefresh()
            batViewer.focusScroll()
        })
    }

    Item {
        anchors.fill: parent

        Item {
            id: navFocus
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28

            Keys.onPressed: function(event) {
                root.handleNavKey(event)
            }

            onVisibleChanged: {
                if (visible) Qt.callLater(function() { root.focusScroll() })
            }

            RowLayout {
                anchors.fill: parent
                spacing: 8

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28
                radius: 6
                color: prevFileMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.files.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "◀"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: prevFileMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.files.length > 0
                    onClicked: root.prevFile()
                }
            }

            ComboBox {
            id: fileCombo
            Layout.fillWidth: true
            model: root.files
            textRole: "label"

            onActivated: function(index) {
                const item = root.files[index]
                if (item) root.selectFileId(item.id)
            }

            contentItem: Text {
                leftPadding: 8
                rightPadding: fileCombo.indicator.width + fileCombo.spacing
                text: fileCombo.displayText
                font.pixelSize: 13
                color: root.textColor
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            indicator: Canvas {
                x: fileCombo.width - width - fileCombo.rightPadding
                y: fileCombo.topPadding + (fileCombo.availableHeight - height) / 2
                width: 10
                height: 6
                contextType: "2d"
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = root.subtextColor
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    ctx.moveTo(0, 1)
                    ctx.lineTo(5, 5)
                    ctx.lineTo(10, 1)
                    ctx.stroke()
                }
                onWidthChanged: requestPaint()
            }

            background: Rectangle {
                radius: 6
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
            }

                popup: Popup {
                id: filePopup
                y: fileCombo.height
                width: Math.max(fileCombo.width, 280)
                implicitHeight: Math.min(filePopupContent.implicitHeight + 2, 360)
                padding: 1
                modal: true
                focus: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                onClosed: Qt.callLater(function() { root.focusScroll() })

                onOpened: {
                    fileFilterField.text = ""
                    root.fileSearch = ""
                    Qt.callLater(function() { fileFilterField.forceActiveFocus() })
                }

                background: Rectangle {
                    radius: 6
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }

                contentItem: Column {
                    id: filePopupContent
                    spacing: 0
                    width: filePopup.width

                    Rectangle {
                        width: parent.width
                        height: 34
                        color: root.surfaceColor

                        TextField {
                            id: fileFilterField
                            anchors.fill: parent
                            anchors.margins: 4
                            placeholderText: "Filter files..."
                            placeholderTextColor: root.overlayColor
                            color: root.textColor
                            font.pixelSize: 13
                            selectionColor: Qt.rgba(0.55, 0.70, 0.96, 0.35)
                            selectedTextColor: root.textColor
                            onTextChanged: root.fileSearch = text
                            background: Rectangle {
                                radius: 4
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)
                            }
                        }
                    }

                    ListView {
                        id: fileList
                        width: parent.width
                        height: Math.min(contentHeight, 300)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.filteredFiles()
                        property string _filterBind: root.fileSearch

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        delegate: ItemDelegate {
                            width: fileList.width
                            height: 40
                            readonly property bool isSelected: modelData.id === root.selectedFileId

                            contentItem: Column {
                                spacing: 0
                                leftPadding: 10
                                Text {
                                    text: modelData.label
                                    color: parent.parent.isSelected ? root.accentColor : root.textColor
                                    font.pixelSize: 13
                                    font.bold: parent.parent.isSelected
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.file
                                    color: root.overlayColor
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    elide: Text.ElideRight
                                }
                            }

                            background: Rectangle {
                                color: parent.hovered ? Qt.rgba(1, 1, 1, 0.05)
                                    : (parent.isSelected ? Qt.rgba(0.55, 0.70, 0.96, 0.12) : "transparent")
                            }

                            onClicked: {
                                root.selectFileId(modelData.id)
                                filePopup.close()
                            }
                        }
                    }
                }
            }
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28
                radius: 6
                color: nextFileMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.files.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: nextFileMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.files.length > 0
                    onClicked: root.nextFile()
                }
            }
            }
        }

        BatSyntaxView {
            id: batViewer
            anchors.top: navFocus.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            filePath: root.currentFilePath()
            language: root.currentBatLanguage()
            filterText: root.globalFilter
            defaultColor: root.textColor
            accentColor: root.accentColor
            onUnhandledKey: function(event) {
                if (event.key === Qt.Key_Left) {
                    root.prevFile()
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.nextFile()
                    event.accepted = true
                }
            }
        }
    }
}