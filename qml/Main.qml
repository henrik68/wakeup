// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
//
// WakeUp - alarm clock with slowly rising volume (OpenStore version).
//
// Alarms are saved in the system alarm list (Lomiri Alarm/AlarmModel -> evolution-data-server),
// so the system alarm service (ayatana-indicator-datetime) rings them, wakes the phone from
// sleep and shows Snooze/OK. They also show up in the Clock app.
// Snooze length, ring time, volume and vibration are system settings (AlarmSettings, C++, over
// D-Bus) and apply to all alarms.
// "Slowly rising volume" uses a sound file with the fade built in, made by RisingSounds (C++)
// because the system plays alarms at one fixed volume.
// Texts use i18n.tr() (po/*.po; English when a translation is missing).
import QtQuick 2.12
import Lomiri.Components 1.3
import WakeUp 1.0

MainView {
    id: root
    // Must match "name" in manifest.json. It is also the translation domain (i18n.domain).
    applicationName: "wakeup.henrik68"
    anchorToKeyboard: true
    width: units.gu(45)
    height: units.gu(80)

    readonly property var riseChoices: [30, 60, 120, 300]   // seconds
    readonly property var ringtones: risingItem.ringtones    // [{name, path}]
    readonly property string defaultSoundName: "Alarm clock"

    // How long the rising file must be: the ring time (+5 s), so it never starts again quietly.
    readonly property int ringSeconds: Math.max(1, alarmSettingsItem.duration || 10) * 60 + 5

    function tr(text) { return i18n.tr(text) }

    // Shared with the pages (they get `app: root`).
    property alias alarmModel: alarmModelItem
    property alias alarmSettings: alarmSettingsItem
    property alias rising: risingItem
    property alias newAlarm: newAlarmComponent

    AlarmModel { id: alarmModelItem }
    AlarmSettings { id: alarmSettingsItem }
    RisingSounds { id: risingItem }
    Component { id: newAlarmComponent; Alarm {} }

    // Ring time made longer (here or in the Clock app): make rising sounds long enough again.
    Connections {
        target: alarmSettingsItem
        onRingTimeChanged: risingItem.refresh(root.ringSeconds)
    }
    Component.onCompleted: risingItem.refresh(root.ringSeconds)

    // ---- helpers used by the pages ----
    function formatTime(d) {
        return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat))
    }

    // bit 0 = Monday ... bit 6 = Sunday (Alarm.Monday = 1 ... Alarm.Sunday = 64)
    function shortDay(bit) {
        return Qt.locale().dayName((bit + 1) % 7, Locale.ShortFormat)
    }

    function daysText(type, days) {
        if (type === Alarm.OneTime || days === 0 || days === Alarm.AutoDetect)
            return i18n.tr("Once")
        if (days === Alarm.Daily) return i18n.tr("Every day")
        if (days === 31) return i18n.tr("Weekdays")
        if (days === 96) return i18n.tr("Weekend")
        var names = []
        for (var i = 0; i < 7; i++)
            if (days & (1 << i)) names.push(shortDay(i))
        return names.join(", ")
    }

    // Next time this alarm rings (or null when it is off).
    function nextRing(type, days, date, enabled) {
        if (!enabled) return null
        var now = new Date()
        if (type === Alarm.OneTime)
            return date > now ? date : null
        for (var add = 0; add < 8; add++) {
            var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + add,
                             date.getHours(), date.getMinutes(), 0, 0)
            var bit = (d.getDay() + 6) % 7          // JS: 0 = Sunday -> bit 6
            if ((days & (1 << bit)) && d > now)
                return d
        }
        return null
    }

    function durationText(ms) {
        var mins = Math.max(1, Math.round(ms / 60000))
        if (mins < 60) return i18n.tr("%1 min").arg(mins)
        return i18n.tr("%1 h %2 min").arg(Math.floor(mins / 60)).arg(mins % 60)
    }

    // ---- sounds ----
    function safeName(name) { return name.replace(/[^A-Za-z0-9]/g, "_") }

    function findRingtone(name) {
        for (var i = 0; i < ringtones.length; i++)
            if (ringtones[i].name === name) return ringtones[i]
        return null
    }

    function defaultSound() {
        var r = findRingtone(defaultSoundName)
        if (!r && ringtones.length > 0) r = ringtones[0]
        return r ? { name: r.name, path: r.path, rise: 60 } : { name: defaultSoundName, path: "", rise: 60 }
    }

    function pathToUrl(path) { return "file://" + encodeURI(path) }

    function urlToPath(url) {
        var s = url ? url.toString() : ""
        if (s.indexOf("file://") === 0) s = decodeURI(s.substring(7))
        return s
    }

    // From an alarm's sound url back to {name, path, rise}.
    function describeSound(url) {
        var path = urlToPath(url)
        if (path === "")
            return defaultSound()
        var m = path.match(/\/([^\/]+)-rise(\d+)\.ogg$/)
        if (m) {
            // a rising sound (ours, or from the personal WakeUp version): find its ringtone
            for (var i = 0; i < ringtones.length; i++)
                if (safeName(ringtones[i].name) === m[1])
                    return { name: ringtones[i].name, path: ringtones[i].path, rise: parseInt(m[2]) }
            return { name: m[1], path: path, rise: 0 }
        }
        var name = path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]*$/, "")
        return { name: name, path: path, rise: 0 }
    }

    PageStack {
        id: pageStack
        Component.onCompleted: push(Qt.resolvedUrl("AlarmsPage.qml"), { app: root })
    }
}
