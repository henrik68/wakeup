// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
//
// System alarm settings (snooze length, ring time, volume, vibration).
// They belong to the alarm service (ayatana-indicator-datetime) and apply to all alarms,
// also those made in the Clock app. A confined app can't write GSettings, so they are read
// and changed over D-Bus, like the Clock app does:
//   org.ayatana.indicator.datetime  /org/ayatana/indicator/datetime/AlarmProperties
#ifndef ALARMSETTINGS_H
#define ALARMSETTINGS_H

#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantMap>
#include <QStringList>

class AlarmSettings : public QObject
{
    Q_OBJECT
    // false if the alarm service could not be reached (values are then defaults)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY changed)                  // 1..100
    Q_PROPERTY(int duration READ duration WRITE setDuration NOTIFY changed)            // minutes
    Q_PROPERTY(int snoozeDuration READ snoozeDuration WRITE setSnoozeDuration NOTIFY changed) // minutes
    Q_PROPERTY(QString vibration READ vibration WRITE setVibration NOTIFY changed)     // "pulse" / "none"

public:
    explicit AlarmSettings(QObject *parent = nullptr);

    bool available() const { return m_available; }
    int volume() const { return m_volume; }
    int duration() const { return m_duration; }
    int snoozeDuration() const { return m_snoozeDuration; }
    QString vibration() const { return m_vibration; }

    void setVolume(int v);
    void setDuration(int v);
    void setSnoozeDuration(int v);
    void setVibration(const QString &v);

    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void changed();
    // emitted only when the ring time (duration) changes (rising sounds may need to be made longer)
    void ringTimeChanged();

private Q_SLOTS:
    void onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                             const QStringList &invalidated);

private:
    void apply(const QVariantMap &map);
    void setDBusProperty(const QString &name, const QVariant &value);

    bool m_available = false;
    int m_volume = 50;
    int m_duration = 10;
    int m_snoozeDuration = 10;
    QString m_vibration = QStringLiteral("pulse");
};

#endif
