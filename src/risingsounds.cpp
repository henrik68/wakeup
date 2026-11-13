// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
#include "risingsounds.h"

#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>
#include <QtConcurrent>
#include <QDebug>

#include <dlfcn.h>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

const int RATE = 32000;                 // mono, 16 bit
const int TIMEOUT_S = 300;
const char *const RINGTONE_DIRS[] = {
    "/usr/share/sounds/lomiri/ringtones",
    "/usr/share/sounds/ubuntu/ringtones",
};

// Volume over the rise time (fraction of rise time, volume). Rises slowly at first,
// because the ear hears changes in quiet sound more than in loud sound.
const double CURVE[][2] = { {0.0, 0.03}, {0.25, 0.08}, {0.5, 0.2}, {0.75, 0.45}, {1.0, 1.0} };

// ---------------------------------------------------------------- GStreamer via dlopen
struct GErr { uint32_t domain; int code; char *message; };   // GError

struct Gst {
    bool ok = false;
    QString error;
    void (*init)(int *, char ***) = nullptr;
    void *(*parseLaunch)(const char *, GErr **) = nullptr;
    int (*setState)(void *, int) = nullptr;
    void *(*getBus)(void *) = nullptr;
    void *(*popFiltered)(void *, uint64_t, int) = nullptr;
    const void *(*getStructure)(void *) = nullptr;
    void (*parseError)(void *, GErr **, char **) = nullptr;
    void (*miniObjectUnref)(void *) = nullptr;
    void (*objectUnref)(void *) = nullptr;
    void (*errorFree)(GErr *) = nullptr;
    void (*gFree)(void *) = nullptr;
};

// Only used from the worker thread (the pool runs one job at a time).
Gst &gst()
{
    static Gst g;
    static bool tried = false;
    if (tried)
        return g;
    tried = true;
    void *h = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        g.error = QStringLiteral("GStreamer not found: ") + QString::fromUtf8(dlerror());
        return g;
    }
#define WAKEUP_SYM(field, name) \
    g.field = reinterpret_cast<decltype(g.field)>(dlsym(h, name)); \
    if (!g.field) { g.error = QStringLiteral("GStreamer: missing ") + QLatin1String(name); return g; }
    WAKEUP_SYM(init, "gst_init")
    WAKEUP_SYM(parseLaunch, "gst_parse_launch")
    WAKEUP_SYM(setState, "gst_element_set_state")
    WAKEUP_SYM(getBus, "gst_element_get_bus")
    WAKEUP_SYM(popFiltered, "gst_bus_timed_pop_filtered")
    WAKEUP_SYM(getStructure, "gst_message_get_structure")
    WAKEUP_SYM(parseError, "gst_message_parse_error")
    WAKEUP_SYM(miniObjectUnref, "gst_mini_object_unref")
    WAKEUP_SYM(objectUnref, "gst_object_unref")
    WAKEUP_SYM(errorFree, "g_error_free")
    WAKEUP_SYM(gFree, "g_free")
#undef WAKEUP_SYM
    g.init(nullptr, nullptr);
    g.ok = true;
    return g;
}

QString quoted(const QString &path)
{
    QString s = path;
    s.replace(QLatin1String("\\"), QLatin1String("\\\\"));
    s.replace(QLatin1String("\""), QLatin1String("\\\""));
    return QLatin1Char('"') + s + QLatin1Char('"');
}

// Runs a gst-launch style pipeline until end of stream.
bool runPipeline(const QString &desc, QString *err)
{
    Gst &g = gst();
    if (!g.ok) {
        *err = g.error;
        return false;
    }
    GErr *e = nullptr;
    void *p = g.parseLaunch(desc.toUtf8().constData(), &e);
    if (!p || e) {                  // an element missing = error even if a pipeline came back
        *err = e ? QString::fromUtf8(e->message) : QStringLiteral("bad pipeline");
        if (e) g.errorFree(e);
        if (p) g.objectUnref(p);
        return false;
    }
    void *bus = g.getBus(p);
    g.setState(p, 4);                                                    // PLAYING
    void *msg = g.popFiltered(bus, uint64_t(TIMEOUT_S) * 1000000000ULL, 1 | 2);  // EOS | ERROR
    QString problem;
    if (!msg) {
        problem = QStringLiteral("timeout");
    } else if (g.getStructure(msg)) {                // EOS has no structure, ERROR has one
        GErr *me = nullptr;
        char *dbg = nullptr;
        g.parseError(msg, &me, &dbg);
        problem = me ? QString::fromUtf8(me->message) : QStringLiteral("error");
        if (me) g.errorFree(me);
        if (dbg) g.gFree(dbg);
    }
    if (msg) g.miniObjectUnref(msg);
    g.setState(p, 1);                                                    // NULL
    g.objectUnref(bus);
    g.objectUnref(p);
    if (!problem.isEmpty()) {
        *err = problem;
        return false;
    }
    return true;
}

// ---------------------------------------------------------------- WAV + fade
quint32 le32(const char *p)
{
    const unsigned char *u = reinterpret_cast<const unsigned char *>(p);
    return quint32(u[0]) | (quint32(u[1]) << 8) | (quint32(u[2]) << 16) | (quint32(u[3]) << 24);
}

bool readWav(const QString &path, std::vector<int16_t> &pcm, QString *err)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        *err = QStringLiteral("cannot read decoded sound");
        return false;
    }
    const QByteArray all = f.readAll();
    if (all.size() < 12 || !all.startsWith("RIFF") || all.mid(8, 4) != "WAVE") {
        *err = QStringLiteral("decoded sound is not WAV");
        return false;
    }
    int pos = 12;
    while (pos + 8 <= all.size()) {
        const QByteArray id = all.mid(pos, 4);
        qint64 len = le32(all.constData() + pos + 4);
        pos += 8;
        if (id == "data") {
            if (len == 0 || len > all.size() - pos)
                len = all.size() - pos;
            pcm.resize(size_t(len / 2));
            std::memcpy(pcm.data(), all.constData() + pos, pcm.size() * 2);   // little endian
            if (pcm.size() < size_t(RATE / 10)) {
                *err = QStringLiteral("no audio in the sound");
                return false;
            }
            return true;
        }
        pos += int(len + (len & 1));
    }
    *err = QStringLiteral("no audio data in decoded sound");
    return false;
}

double gainAt(double t, int rise)
{
    const double f = t / rise;
    for (int i = 0; i < 4; i++) {
        const double f0 = CURVE[i][0], v0 = CURVE[i][1], f1 = CURVE[i + 1][0], v1 = CURVE[i + 1][1];
        if (f <= f1)
            return v0 + (v1 - v0) * (f - f0) / (f1 - f0);
    }
    return 1.0;
}

void put32(QByteArray &b, quint32 v) { for (int i = 0; i < 4; i++) b.append(char((v >> (8 * i)) & 0xff)); }
void put16(QByteArray &b, quint16 v) { b.append(char(v & 0xff)); b.append(char(v >> 8)); }

// Writes `total` seconds of the repeated sound, faded in over `rise` seconds.
bool buildWav(const std::vector<int16_t> &pcm, int rise, int total, const QString &path, QString *err)
{
    const qint64 nTotal = qint64(total) * RATE;
    const qint64 nRise = std::min<qint64>(qint64(rise) * RATE, nTotal);
    const qint64 n = qint64(pcm.size());
    const qint64 block = RATE / 100;                  // gain changes every 10 ms

    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        *err = QStringLiteral("cannot write ") + path;
        return false;
    }
    QByteArray h;
    h.append("RIFF"); put32(h, quint32(36 + nTotal * 2)); h.append("WAVE");
    h.append("fmt "); put32(h, 16); put16(h, 1); put16(h, 1);
    put32(h, RATE); put32(h, RATE * 2); put16(h, 2); put16(h, 16);
    h.append("data"); put32(h, quint32(nTotal * 2));
    f.write(h);

    std::vector<int16_t> buf(static_cast<size_t>(block));
    qint64 pos = 0;
    while (pos < nTotal) {
        const qint64 off = pos % n;
        qint64 count;
        if (pos < nRise) {
            count = std::min({block, n - off, nRise - pos});
            const double g = gainAt(double(pos) / RATE, rise);
            for (qint64 i = 0; i < count; i++)
                buf[size_t(i)] = int16_t(pcm[size_t(off + i)] * g);
            f.write(reinterpret_cast<const char *>(buf.data()), count * 2);
        } else {
            count = std::min(n - off, nTotal - pos);
            f.write(reinterpret_cast<const char *>(pcm.data() + off), count * 2);
        }
        pos += count;
    }
    if (f.error() != QFileDevice::NoError) {
        *err = f.errorString();
        return false;
    }
    return true;
}

// ---------------------------------------------------------------- files
QString safeBase(const QString &source)
{
    QString base = QFileInfo(source).completeBaseName();
    base.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9]")), QStringLiteral("_"));
    return base;
}

QString pathFor(const QString &dir, const QString &source, int rise)
{
    return dir + safeBase(source) + QStringLiteral("-rise") + QString::number(rise) + QStringLiteral(".ogg");
}

QJsonObject loadIndex(const QString &dir)
{
    QFile f(dir + QStringLiteral("index.json"));
    if (!f.open(QIODevice::ReadOnly))
        return QJsonObject();
    return QJsonDocument::fromJson(f.readAll()).object();
}

void saveIndex(const QString &dir, const QJsonObject &index)
{
    const QString path = dir + QStringLiteral("index.json");
    QFile f(path + QStringLiteral(".tmp"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(index).toJson());
        f.close();
        ::rename(QFile::encodeName(path + QStringLiteral(".tmp")).constData(), QFile::encodeName(path).constData());
    }
}

void logLine(const QString &dir, const QString &line)
{
    QFile f(dir + QStringLiteral("status.txt"));
    if (f.size() > 200000)
        f.remove();
    if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream(&f) << QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss "))
                        << line << "\n";
    }
    qInfo().noquote() << "WakeUp:" << line;
}

bool usable(const QString &path)
{
    QFileInfo fi(path);
    return fi.exists() && fi.size() > 1000;
}

struct Result {
    QString path;
    bool ok = false;
    QString message;
};

// Makes the rising file (worker thread). The new file replaces the old one only when it is
// complete, so an alarm that uses the old one keeps working meanwhile.
Result makeFile(const QString &dir, const QString &source, int rise, int total)
{
    Result r;
    r.path = pathFor(dir, source, rise);
    if (!QFileInfo(source).isFile()) {
        r.message = QStringLiteral("sound not found: ") + source;
        return r;
    }
    QDir().mkpath(dir);
    QElapsedTimer t;
    t.start();
    const QString tmpIn = r.path + QStringLiteral(".in.wav");
    const QString tmpLong = r.path + QStringLiteral(".long.wav");
    const QString tmpOut = r.path + QStringLiteral(".tmp");
    QString err;
    std::vector<int16_t> pcm;
    QString how = QStringLiteral("ogg");
    bool ok = runPipeline(QStringLiteral("filesrc location=%1 ! decodebin ! audioconvert ! audioresample ! "
                                         "audio/x-raw,format=S16LE,channels=1,rate=%2 ! wavenc ! filesink location=%3")
                              .arg(quoted(source)).arg(RATE).arg(quoted(tmpIn)), &err)
              && readWav(tmpIn, pcm, &err)
              && buildWav(pcm, rise, total, tmpLong, &err);
    if (ok) {
        QString encErr;
        if (!runPipeline(QStringLiteral("filesrc location=%1 ! wavparse ! audioconvert ! vorbisenc quality=0.3 ! "
                                        "oggmux ! filesink location=%2").arg(quoted(tmpLong), quoted(tmpOut)), &encErr)
            || !usable(tmpOut)) {
            // No Vorbis encoder: keep the WAV. Players detect the format by content, not by name.
            how = QStringLiteral("wav (ogg failed: ") + encErr + QLatin1Char(')');
            QFile::remove(tmpOut);
            ok = QFile::rename(tmpLong, tmpOut);
            if (!ok) err = QStringLiteral("cannot rename WAV");
        }
    }
    if (ok)
        ok = ::rename(QFile::encodeName(tmpOut).constData(), QFile::encodeName(r.path).constData()) == 0;
    for (const QString &f : {tmpIn, tmpLong, tmpOut})
        QFile::remove(f);
    if (!ok) {
        r.message = err.isEmpty() ? QStringLiteral("could not save the sound") : err;
        return r;
    }
    QJsonObject index = loadIndex(dir);
    QJsonObject entry;
    entry.insert(QStringLiteral("src"), source);
    entry.insert(QStringLiteral("rise"), rise);
    entry.insert(QStringLiteral("total"), total);
    index.insert(QFileInfo(r.path).fileName(), entry);
    saveIndex(dir, index);
    r.ok = true;
    r.message = QStringLiteral("made %1 in %2 s (%3 s long, %4 kB)")
                    .arg(how).arg(t.elapsed() / 1000.0, 0, 'f', 1).arg(total).arg(QFileInfo(r.path).size() / 1024);
    return r;
}

int totalFor(int rise, int ringSeconds)
{
    return std::max(ringSeconds, rise + 30);
}

} // namespace

// ---------------------------------------------------------------- RisingSounds
RisingSounds::RisingSounds(QObject *parent)
    : QObject(parent)
{
    m_dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/rising/");
    QDir().mkpath(m_dir);
    m_pool.setMaxThreadCount(1);

    // A confined app may only write in its own folders: keep GStreamer's plugin cache there.
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(cache);
    if (qEnvironmentVariableIsEmpty("GST_REGISTRY"))
        qputenv("GST_REGISTRY", QFile::encodeName(cache + QStringLiteral("/gst-registry.bin")));
}

RisingSounds::~RisingSounds()
{
    m_pool.waitForDone();
}

QVariantList RisingSounds::ringtones() const
{
    QMap<QString, QString> byName;          // sorted, first folder wins
    for (const char *d : RINGTONE_DIRS) {
        const QFileInfoList files = QDir(QString::fromLatin1(d)).entryInfoList(
            {QStringLiteral("*.ogg"), QStringLiteral("*.oga"), QStringLiteral("*.mp3"), QStringLiteral("*.wav")},
            QDir::Files, QDir::Name);
        for (const QFileInfo &fi : files) {
            const QString key = fi.completeBaseName().toLower();
            if (!byName.contains(key))
                byName.insert(key, fi.absoluteFilePath());
        }
    }
    QVariantList out;
    for (const QString &path : byName) {
        QVariantMap m;
        m.insert(QStringLiteral("name"), QFileInfo(path).completeBaseName());
        m.insert(QStringLiteral("path"), path);
        out.append(m);
    }
    return out;
}

QString RisingSounds::risingPath(const QString &source, int riseSeconds) const
{
    return pathFor(m_dir, source, riseSeconds);
}

void RisingSounds::finished()
{
    m_pending--;
    Q_EMIT busyChanged();
}

void RisingSounds::make(const QString &source, int riseSeconds, int ringSeconds)
{
    m_pending++;
    Q_EMIT busyChanged();
    const QString dir = m_dir;
    QtConcurrent::run(&m_pool, [this, dir, source, riseSeconds, ringSeconds]() {
        const int total = totalFor(riseSeconds, ringSeconds);
        Result r;
        r.path = pathFor(dir, source, riseSeconds);
        const QJsonObject entry = loadIndex(dir).value(QFileInfo(r.path).fileName()).toObject();
        if (usable(r.path) && entry.value(QStringLiteral("total")).toInt() >= total) {
            r.ok = true;
            r.message = QStringLiteral("exists");
        } else {
            r = makeFile(dir, source, riseSeconds, total);
            logLine(dir, (r.ok ? QStringLiteral("OK ") : QStringLiteral("ERROR ")) + r.path + QStringLiteral(": ") + r.message);
        }
        QMetaObject::invokeMethod(this, [this, r]() {
            Q_EMIT made(r.path, r.ok, r.message);
            finished();
        }, Qt::QueuedConnection);
    });
}

void RisingSounds::refresh(int ringSeconds)
{
    m_pending++;
    Q_EMIT busyChanged();
    const QString dir = m_dir;
    QtConcurrent::run(&m_pool, [this, dir, ringSeconds]() {
        const QJsonObject index = loadIndex(dir);
        int remade = 0;
        QStringList problems;
        for (auto it = index.constBegin(); it != index.constEnd(); ++it) {
            const QJsonObject e = it.value().toObject();
            const QString src = e.value(QStringLiteral("src")).toString();
            const int rise = e.value(QStringLiteral("rise")).toInt();
            const int total = totalFor(rise, ringSeconds);
            if (!usable(dir + it.key()) || e.value(QStringLiteral("total")).toInt() >= total)
                continue;
            const Result r = makeFile(dir, src, rise, total);
            logLine(dir, QStringLiteral("REFRESH %1 for ring time %2 s: %3").arg(it.key()).arg(ringSeconds).arg(r.message));
            if (r.ok) remade++;
            else problems << it.key() + QStringLiteral(": ") + r.message;
        }
        const QString msg = problems.join(QStringLiteral("\n"));
        QMetaObject::invokeMethod(this, [this, remade, msg]() {
            Q_EMIT refreshed(remade, msg);
            finished();
        }, Qt::QueuedConnection);
    });
}
