// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
// System alarm settings (AlarmSettings in C++, D-Bus to the alarm service). Apply to all alarms,
// also those made in the Clock app.
import QtQuick 2.12
import Lomiri.Components 1.3

Page {
    id: page
    property var app
    readonly property var s: app.alarmSettings

    readonly property var snoozeChoices: [5, 9, 10, 15, 20, 30]
    readonly property var ringChoices: [1, 3, 5, 10, 15, 20, 30]

    header: PageHeader {
        id: header
        title: i18n.tr("Settings")
    }

    function minutesModel(list) {
        var out = []
        for (var i = 0; i < list.length; i++) out.push(i18n.tr("%1 min.").arg(list[i]))
        return out
    }
    function indexOrNearest(list, value) {
        var best = 0
        for (var i = 0; i < list.length; i++)
            if (Math.abs(list[i] - value) < Math.abs(list[best] - value)) best = i
        return best
    }

    Flickable {
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: col.height + units.gu(4)
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: units.gu(2)
            topPadding: units.gu(2)

            Label {
                visible: !page.s.available
                x: units.gu(2); width: parent.width - units.gu(4)
                wrapMode: Text.Wrap
                text: i18n.tr("Could not reach the system alarm service, so these settings can't be changed right now.")
                color: theme.palette.normal.negative
            }

            Label {
                x: units.gu(2); width: parent.width - units.gu(4)
                wrapMode: Text.Wrap
                text: i18n.tr("These settings apply to all alarms, also in the Clock app.")
                color: theme.palette.normal.backgroundSecondaryText
            }

            OptionSelector {
                x: units.gu(2); width: parent.width - units.gu(4)
                // Dropdown: closed it shows only the current value. Saves only when a different
                // value is picked, so just opening it never changes the setting.
                expanded: false
                text: i18n.tr("Snooze length")
                model: page.minutesModel(page.snoozeChoices)
                selectedIndex: page.indexOrNearest(page.snoozeChoices, page.s.snoozeDuration)
                onDelegateClicked: if (page.s.snoozeDuration !== undefined
                                       && page.s.snoozeDuration !== page.snoozeChoices[index])
                                       page.s.snoozeDuration = page.snoozeChoices[index]
            }

            OptionSelector {
                x: units.gu(2); width: parent.width - units.gu(4)
                expanded: false
                text: i18n.tr("Alarm ring time")
                model: page.minutesModel(page.ringChoices)
                selectedIndex: page.indexOrNearest(page.ringChoices, page.s.duration)
                onDelegateClicked: if (page.s.duration !== undefined
                                       && page.s.duration !== page.ringChoices[index])
                                       page.s.duration = page.ringChoices[index]
            }
            Label {
                x: units.gu(2); width: parent.width - units.gu(4)
                wrapMode: Text.Wrap
                textSize: Label.Small
                color: theme.palette.normal.backgroundSecondaryText
                text: i18n.tr("After this the alarm snoozes by itself.") + " "
                      + i18n.tr("When the ring time is made longer, WakeUp makes its rising sounds longer too (about 20 seconds per sound, while WakeUp is open).")
            }

            Column {
                x: units.gu(2); width: parent.width - units.gu(4)
                Label { text: i18n.tr("Alarm volume") }
                Slider {
                    width: parent.width
                    minimumValue: 1
                    maximumValue: 100
                    live: false
                    value: page.s.volume
                    function formatValue(v) { return Math.round(v) + " %" }
                    onValueChanged: if (Math.round(value) !== page.s.volume)
                                        page.s.volume = Math.round(value)
                }
            }

            ListItem {
                height: vibLayout.height + (divider.visible ? divider.height : 0)
                divider.visible: false
                onClicked: vibSwitch.trigger()
                ListItemLayout {
                    id: vibLayout
                    title.text: i18n.tr("Vibrate")
                    Switch {
                        id: vibSwitch
                        SlotsLayout.position: SlotsLayout.Trailing
                        checked: page.s.vibration === "pulse"
                        onTriggered: page.s.vibration = checked ? "pulse" : "none"
                    }
                }
            }
        }
    }
}
