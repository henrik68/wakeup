// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
//
// Makes "slowly rising" versions of alarm sounds.
//
// The alarm service plays a sound at one fixed volume and starts it again when it ends, so the
// fade-in has to be inside the file: the ringtone is repeated for the whole ring time and faded
// in over the first N seconds. Files go to <app data>/rising/<name>-rise<seconds>.ogg, where the
// alarm service (which is not confined) can read them.
//
// The work runs in a background thread, one sound at a time. GStreamer (decode + Ogg Vorbis
// encode) is loaded at run time with dlopen, so no GStreamer headers are needed to build.
#ifndef RISINGSOUNDS_H
#define RISINGSOUNDS_H

#include <QObject>
#include <QString>
#include <QThreadPool>
#include <QVariantList>

class RisingSounds : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString dir READ dir CONSTANT)                 // ends with "/"
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantList ringtones READ ringtones CONSTANT) // [{name, path}], sorted by name

public:
    explicit RisingSounds(QObject *parent = nullptr);
    ~RisingSounds() override;

    QString dir() const { return m_dir; }
    bool busy() const { return m_pending > 0; }
    QVariantList ringtones() const;

    // Path of the rising file for this sound + rise time (it may not exist yet).
    Q_INVOKABLE QString risingPath(const QString &source, int riseSeconds) const;
    // Make the rising file if it is missing or shorter than ringSeconds. Always answers with made().
    Q_INVOKABLE void make(const QString &source, int riseSeconds, int ringSeconds);
    // Make again every rising file that is shorter than ringSeconds (ring time was made longer).
    Q_INVOKABLE void refresh(int ringSeconds);

Q_SIGNALS:
    void made(const QString &path, bool ok, const QString &message);
    void refreshed(int remade, const QString &message);
    void busyChanged();

private:
    void finished();

    QString m_dir;
    int m_pending = 0;
    QThreadPool m_pool;
};

#endif
