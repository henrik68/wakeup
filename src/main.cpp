// Copyright (C) 2026 Henrik Christiansen - GNU GPL v3 (see LICENSE)
// WakeUp - alarm clock with slowly rising volume (OpenStore version).
// Starts the QML user interface (qml/Main.qml) and makes the two C++ helpers available to it:
//   import WakeUp 1.0  ->  AlarmSettings (system alarm settings), RisingSounds (rising sounds)
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQuickView>
#include <QUrl>
#include <QtQml>

#include "alarmsettings.h"
#include "risingsounds.h"

int main(int argc, char *argv[])
{
    // Must match "name" in manifest.json: it decides the app's own data folder
    // (~/.local/share/wakeup.henrik68), the only place a confined app may write.
    QCoreApplication::setApplicationName(QStringLiteral("wakeup.henrik68"));
    QGuiApplication app(argc, argv);

    qmlRegisterType<AlarmSettings>("WakeUp", 1, 0, "AlarmSettings");
    qmlRegisterType<RisingSounds>("WakeUp", 1, 0, "RisingSounds");

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setSource(QUrl::fromLocalFile(QCoreApplication::applicationDirPath() + QStringLiteral("/qml/Main.qml")));
    view.show();
    return app.exec();
}
