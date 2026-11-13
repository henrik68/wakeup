// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
#include "alarmsettings.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDebug>

static const char *SERVICE = "org.ayatana.indicator.datetime";
static const char *PATH = "/org/ayatana/indicator/datetime/AlarmProperties";
static const char *IFACE = "org.ayatana.indicator.datetime.AlarmProperties";
static const char *PROPS = "org.freedesktop.DBus.Properties";

AlarmSettings::AlarmSettings(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().connect(SERVICE, PATH, PROPS, "PropertiesChanged", this,
        SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    refresh();
}

void AlarmSettings::refresh()
{
    QDBusInterface props(SERVICE, PATH, PROPS, QDBusConnection::sessionBus());
    QDBusReply<QVariantMap> reply = props.call("GetAll", QString::fromLatin1(IFACE));
    if (!reply.isValid()) {
        qWarning() << "WakeUp: alarm settings not available:" << reply.error().message();
        if (m_available) {
            m_available = false;
            Q_EMIT changed();
        }
        return;
    }
    m_available = true;
    apply(reply.value());
    Q_EMIT changed();
}

void AlarmSettings::apply(const QVariantMap &map)
{
    if (map.contains("DefaultVolume")) m_volume = map.value("DefaultVolume").toInt();
    if (map.contains("SnoozeDuration")) m_snoozeDuration = map.value("SnoozeDuration").toInt();
    if (map.contains("HapticFeedback")) m_vibration = map.value("HapticFeedback").toString();
    if (map.contains("Duration")) {
        const int d = map.value("Duration").toInt();
        if (d != m_duration) {
            m_duration = d;
            Q_EMIT ringTimeChanged();
        }
    }
}

void AlarmSettings::onPropertiesChanged(const QString &interface, const QVariantMap &changedProps,
                                        const QStringList &)
{
    if (interface != QLatin1String(IFACE))
        return;
    apply(changedProps);
    Q_EMIT changed();
}

void AlarmSettings::setDBusProperty(const QString &name, const QVariant &value)
{
    QDBusInterface props(SERVICE, PATH, PROPS, QDBusConnection::sessionBus());
    props.asyncCall("Set", QString::fromLatin1(IFACE), name, QVariant::fromValue(QDBusVariant(value)));
}

void AlarmSettings::setVolume(int v)
{
    if (v == m_volume) return;
    m_volume = v;
    setDBusProperty("DefaultVolume", v);
    Q_EMIT changed();
}

void AlarmSettings::setDuration(int v)
{
    if (v == m_duration) return;
    m_duration = v;
    setDBusProperty("Duration", v);
    Q_EMIT changed();
    Q_EMIT ringTimeChanged();
}

void AlarmSettings::setSnoozeDuration(int v)
{
    if (v == m_snoozeDuration) return;
    m_snoozeDuration = v;
    setDBusProperty("SnoozeDuration", v);
    Q_EMIT changed();
}

void AlarmSettings::setVibration(const QString &v)
{
    if (v == m_vibration) return;
    m_vibration = v;
    setDBusProperty("HapticFeedback", v);
    Q_EMIT changed();
}
