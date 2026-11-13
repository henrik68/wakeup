// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
// Alarm list: time, description + repeat days, on/off switch.
// Tap = edit, swipe right = delete, header: + (new) and settings.
import QtQuick 2.12
import Lomiri.Components 1.3

Page {
    id: page
    property var app
    readonly property var model: app.alarmModel

    header: PageHeader {
        id: header
        title: i18n.tr("Alarms")
        trailingActionBar.actions: [
            Action {
                iconName: "add"
                text: i18n.tr("New alarm")
                onTriggered: pageStack.push(Qt.resolvedUrl("EditPage.qml"), { app: app, alarmIndex: -1 })
            },
            Action {
                iconName: "settings"
                text: i18n.tr("Settings")
                onTriggered: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { app: app })
            }
        ]
    }

    // "Next alarm in ..." line, refreshed every 30 s and whenever the list changes.
    property string nextText: ""
    function updateNext() {
        var best = null
        for (var i = 0; i < model.count; i++) {
            var a = model.get(i)
            var d = app.nextRing(a.type, a.daysOfWeek, a.date, a.enabled)
            if (d && (!best || d < best)) best = d
        }
        nextText = best ? i18n.tr("Next alarm in %1").arg(app.durationText(best - new Date()))
                        : i18n.tr("No alarm is on")
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.updateNext() }
    Connections {
        target: page.model
        onCountChanged: page.updateNext()
        onDataChanged: page.updateNext()
    }

    function setEnabled(index, on) {
        var a = model.get(index)
        if (a.enabled === on) return
        a.enabled = on
        // A one-time alarm whose time has passed: move it to the next time that clock time comes.
        if (on && a.type === Alarm.OneTime && a.date <= new Date()) {
            var d = new Date()
            d.setHours(a.date.getHours(), a.date.getMinutes(), 0, 0)
            if (d <= new Date()) d.setDate(d.getDate() + 1)
            a.date = d
        }
        a.save()
    }

    ListView {
        id: list
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: page.model

        header: ListItem {
            height: units.gu(5)
            divider.visible: true
            Label {
                anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                text: page.nextText
                color: theme.palette.normal.backgroundSecondaryText
            }
        }

        delegate: ListItem {
            id: item
            height: layout.height + (divider.visible ? divider.height : 0)
            leadingActions: ListItemActions {
                actions: [
                    Action {
                        iconName: "delete"
                        text: i18n.tr("Delete")
                        onTriggered: page.model.get(index).cancel()
                    }
                ]
            }
            onClicked: pageStack.push(Qt.resolvedUrl("EditPage.qml"), { app: app, alarmIndex: index })

            ListItemLayout {
                id: layout
                title.text: app.formatTime(model.date)
                title.textSize: Label.XLarge
                title.color: model.enabled ? theme.palette.normal.baseText
                                           : theme.palette.normal.backgroundTertiaryText
                subtitle.text: (model.message || i18n.tr("Alarm")) + " · " + app.daysText(model.type, model.daysOfWeek)

                Switch {
                    SlotsLayout.position: SlotsLayout.Trailing
                    checked: model.enabled
                    onClicked: page.setEnabled(index, checked)
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - units.gu(6)
        spacing: units.gu(1)
        visible: list.count === 0
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "alarm-clock"
            width: units.gu(8); height: width
            color: theme.palette.normal.backgroundTertiaryText
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: i18n.tr("No alarms yet")
            textSize: Label.Large
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: i18n.tr("Tap + to add an alarm.")
            color: theme.palette.normal.backgroundSecondaryText
        }
    }
}
