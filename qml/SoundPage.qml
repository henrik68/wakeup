// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
// Pick the alarm sound. Tapping plays a preview; the choice is written back to the edit page.
import QtQuick 2.12
import QtMultimedia 5.12
import Lomiri.Components 1.3

Page {
    id: page
    property var app
    property var editPage

    header: PageHeader {
        id: header
        title: i18n.tr("Sound")
        trailingActionBar.actions: [
            Action {
                iconName: "media-playback-stop"
                text: i18n.tr("Stop")
                visible: preview.playbackState === Audio.PlayingState
                onTriggered: preview.stop()
            }
        ]
    }

    Audio {
        id: preview
        audioRole: Audio.AlarmRole
    }
    Component.onDestruction: preview.stop()

    ListView {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: app.ringtones

        header: ListItem {
            height: units.gu(5)
            Label {
                anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                text: i18n.tr("Tap a sound to hear it.")
                color: theme.palette.normal.backgroundSecondaryText
            }
        }

        delegate: ListItem {
            height: layout.height + (divider.visible ? divider.height : 0)
            onClicked: {
                editPage.soundName = modelData.name
                editPage.soundPath = modelData.path
                preview.stop()
                preview.source = app.pathToUrl(modelData.path)
                preview.play()
            }
            ListItemLayout {
                id: layout
                title.text: modelData.name
                Icon {
                    SlotsLayout.position: SlotsLayout.Trailing
                    name: "tick"
                    width: units.gu(2.5); height: width
                    color: theme.palette.normal.focus
                    visible: editPage.soundName === modelData.name
                }
            }
        }
    }
}
