// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
// New / edit alarm: time, repeat days, description, sound, slowly rising volume.
import QtQuick 2.12
import Lomiri.Components 1.3
import Lomiri.Components.Pickers 1.3

Page {
    id: page
    property var app
    property int alarmIndex: -1          // -1 = new alarm
    property var alarm: null

    property int days: 0                 // Alarm.Monday (1) ... Alarm.Sunday (64); 0 = once
    property string soundName: "Alarm clock"
    property string soundPath: ""
    property int rise: 60                // seconds, 0 = off
    property bool busy: false
    property string errorText: ""

    header: PageHeader {
        id: header
        title: alarmIndex < 0 ? i18n.tr("New alarm") : i18n.tr("Edit alarm")
        trailingActionBar.actions: [
            Action {
                iconName: "ok"
                text: i18n.tr("Save")
                enabled: !page.busy
                onTriggered: page.save()
            }
        ]
    }

    Component.onCompleted: {
        var d = new Date()
        d.setHours(7, 0, 0, 0)
        var s = app.defaultSound()
        if (alarmIndex >= 0) {
            alarm = app.alarmModel.get(alarmIndex)
            d = alarm.date
            days = alarm.type === Alarm.OneTime ? 0 : (alarm.daysOfWeek & Alarm.Daily)
            messageField.text = alarm.message === i18n.tr("Alarm") ? "" : alarm.message
            s = app.describeSound(alarm.sound)
            rise = s.rise
        }
        soundName = s.name
        soundPath = s.path
        hourPicker.selectedIndex = d.getHours()
        minutePicker.selectedIndex = d.getMinutes()
    }

    // ---- saving ----
    // With rising volume the sound file is made first (RisingSounds, in the background; about
    // 20 seconds), then the alarm is saved with it. Without, the ringtone is used as it is.
    property string waitingFor: ""

    function save() {
        errorText = ""
        if (rise <= 0 || soundPath === "") {
            commit(soundPath === "" ? "" : app.pathToUrl(soundPath))
            return
        }
        busy = true
        waitingFor = app.rising.risingPath(soundPath, rise)
        app.rising.make(soundPath, rise, app.ringSeconds)   // answers with made()
    }

    Connections {
        target: app.rising
        onMade: {
            if (path !== page.waitingFor) return
            page.waitingFor = ""
            if (ok) {
                page.commit(app.pathToUrl(path))
            } else {
                page.busy = false
                page.errorText = i18n.tr("Could not make the rising sound.") + "\n" + message
            }
        }
    }

    function commit(soundUrl) {
        busy = true
        var a = alarm ? alarm : app.newAlarm.createObject(page)
        var d = new Date()
        d.setHours(hourPicker.selectedIndex, minutePicker.selectedIndex, 0, 0)
        if (days === 0) {
            a.type = Alarm.OneTime
            a.daysOfWeek = Alarm.AutoDetect
            if (d <= new Date()) d.setDate(d.getDate() + 1)
        } else {
            a.type = Alarm.Repeating
            a.daysOfWeek = days
        }
        a.date = d
        a.message = messageField.text.trim() || i18n.tr("Alarm")
        a.sound = soundUrl
        a.enabled = true
        a.statusChanged.connect(function() {
            if (a.status === Alarm.Ready && a.error === Alarm.NoError) {
                busy = false
                pageStack.pop()
            } else if (a.status === Alarm.Fail || (a.status === Alarm.Ready && a.error !== Alarm.NoError)) {
                busy = false
                errorText = i18n.tr("Could not save the alarm (error %1).").arg(a.error)
            }
        })
        a.save()
    }

    function remove() {
        if (alarm)
            alarm.cancel()
        pageStack.pop()
    }

    // ---- layout ----
    Flickable {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: content.height + units.gu(4)
        clip: true

        Column {
            id: content
            width: parent.width

            // Hour and minute wheels (24 h). Lomiri's DatePicker makes its wheels just wide enough
            // for "99" plus a margin; these are 25 % wider (user wish), so two Pickers are used.
            Item {
                id: timeWheels
                width: parent.width
                height: units.gu(24)            // wheels 20 gu + 2 gu free space above and below
                Label { id: digitSizer; visible: false; text: "99" }
                readonly property real wheelWidth: Math.round((digitSizer.paintedWidth + units.gu(3)) * 1.25)

                Row {
                    anchors.centerIn: parent
                    height: units.gu(20)
                    Picker {
                        id: hourPicker
                        width: timeWheels.wheelWidth
                        height: parent.height
                        circular: true
                        model: 24
                        delegate: PickerDelegate {
                            Label {
                                anchors.centerIn: parent
                                text: (index < 10 ? "0" : "") + index
                            }
                        }
                    }
                    Picker {
                        id: minutePicker
                        width: timeWheels.wheelWidth
                        height: parent.height
                        circular: true
                        model: 60
                        delegate: PickerDelegate {
                            Label {
                                anchors.centerIn: parent
                                text: (index < 10 ? "0" : "") + index
                            }
                        }
                    }
                }
            }

            ListItem {
                height: repeatCol.height + units.gu(3)
                Column {
                    id: repeatCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              margins: units.gu(2); topMargin: units.gu(1.5) }
                    spacing: units.gu(1.5)

                    Item {
                        width: parent.width; height: repeatLabel.height
                        Label { id: repeatLabel; text: i18n.tr("Repeat") }
                        Label {
                            anchors.right: parent.right
                            text: app.daysText(page.days === 0 ? Alarm.OneTime : Alarm.Repeating, page.days)
                            color: theme.palette.normal.backgroundSecondaryText
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: (parent.width - 7 * units.gu(4.5)) / 6
                        Repeater {
                            model: 7
                            delegate: AbstractButton {
                                readonly property bool on: (page.days & (1 << index)) !== 0
                                width: units.gu(4.5); height: width
                                onClicked: page.days = page.days ^ (1 << index)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: on ? theme.palette.normal.focus : "transparent"
                                    border.width: on ? 0 : units.dp(1)
                                    border.color: theme.palette.normal.base
                                }
                                Label {
                                    anchors.centerIn: parent
                                    text: app.shortDay(index).charAt(0).toUpperCase()
                                    color: on ? theme.palette.normal.focusText : theme.palette.normal.baseText
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    Row {
                        spacing: units.gu(1)
                        anchors.horizontalCenter: parent.horizontalCenter
                        Button { text: i18n.tr("Once"); onClicked: page.days = 0 }
                        Button { text: i18n.tr("Weekdays"); onClicked: page.days = 31 }
                        Button { text: i18n.tr("Every day"); onClicked: page.days = Alarm.Daily }
                    }
                }
            }

            ListItem {
                height: units.gu(7)
                TextField {
                    id: messageField
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              margins: units.gu(2) }
                    placeholderText: i18n.tr("Description") + " (" + i18n.tr("Alarm") + ")"
                }
            }

            ListItem {
                height: soundLayout.height + (divider.visible ? divider.height : 0)
                onClicked: pageStack.push(Qt.resolvedUrl("SoundPage.qml"), { app: app, editPage: page })
                ListItemLayout {
                    id: soundLayout
                    title.text: i18n.tr("Sound")
                    Label {
                        SlotsLayout.position: SlotsLayout.Trailing
                        text: page.soundName
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                    ProgressionSlot {}
                }
            }

            ListItem {
                height: riseLayout.height + (divider.visible ? divider.height : 0)
                onClicked: riseSwitch.trigger()
                ListItemLayout {
                    id: riseLayout
                    title.text: i18n.tr("Slowly rising volume")
                    Switch {
                        id: riseSwitch
                        SlotsLayout.position: SlotsLayout.Trailing
                        checked: page.rise > 0
                        onTriggered: page.rise = checked ? 60 : 0
                    }
                }
            }

            ListItem {
                visible: page.rise > 0
                height: riseCol.height + units.gu(3)
                Column {
                    id: riseCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              margins: units.gu(2); topMargin: units.gu(1.5) }
                    spacing: units.gu(1)
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: i18n.tr("Starts quiet and reaches full volume after:")
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                    Row {
                        spacing: units.gu(1)
                        Repeater {
                            model: app.riseChoices
                            delegate: Button {
                                readonly property var labels: [i18n.tr("30 s"), i18n.tr("1 min"),
                                                               i18n.tr("2 min"), i18n.tr("5 min")]
                                text: labels[index]
                                color: page.rise === modelData ? theme.palette.normal.focus
                                                               : theme.palette.normal.base
                                onClicked: page.rise = modelData
                            }
                        }
                    }
                }
            }

            ListItem {
                height: snoozeLayout.height + (divider.visible ? divider.height : 0)
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { app: app })
                ListItemLayout {
                    id: snoozeLayout
                    title.text: i18n.tr("Snooze length")
                    summary.text: i18n.tr("Same for all alarms (system setting).")
                    Label {
                        SlotsLayout.position: SlotsLayout.Trailing
                        text: i18n.tr("%1 min.").arg(app.alarmSettings.snoozeDuration)
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                    ProgressionSlot {}
                }
            }

            Item { width: 1; height: units.gu(2) }

            Row {
                visible: page.busy
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: units.gu(1)
                ActivityIndicator { running: page.busy }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: i18n.tr("Preparing the rising sound…")
                }
            }

            Label {
                visible: page.errorText !== ""
                width: parent.width - units.gu(4)
                anchors.horizontalCenter: parent.horizontalCenter
                wrapMode: Text.Wrap
                text: page.errorText
                color: theme.palette.normal.negative
            }

            Item { width: 1; height: units.gu(2) }

            Button {
                visible: page.alarmIndex >= 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - units.gu(4)
                text: i18n.tr("Delete alarm")
                color: theme.palette.normal.negative
                onClicked: page.remove()
            }
        }
    }
}
