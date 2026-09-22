#include <cstdio>
#include "book.h"
#include "pageprovider.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTextStream>

#include "playlist.h"

#ifdef R9VIEW_VIDEO
#include <QQuickWindow>
#endif

#ifdef Q_OS_WIN
#include <windows.h>
#endif

using namespace Qt::StringLiterals;

#ifdef Q_OS_WIN
// A release build on Windows is a GUI-subsystem binary, so that double-clicking
// a comic does not flash up a console. The cost is that it starts with no
// stdout at all, which would quietly turn --list, --help and --version into
// commands that print nothing. Borrowing the console of whatever launched us
// fixes that, and does nothing when there is no console -- which is exactly the
// case when the app was started from Explorer.
static void borrowParentConsole()
{
    // If stdout already goes somewhere -- a pipe, a file, a redirect -- then it
    // works as it is, and reopening it onto the console would be the thing that
    // broke it. Only step in when there is nothing there at all.
    const HANDLE existing = GetStdHandle(STD_OUTPUT_HANDLE);
    if (existing && existing != INVALID_HANDLE_VALUE)
        return;
    if (!AttachConsole(ATTACH_PARENT_PROCESS))
        return;
    FILE *stream = nullptr;
    freopen_s(&stream, "CONOUT$", "w", stdout);
    freopen_s(&stream, "CONOUT$", "w", stderr);
}
#endif

// Qt's own log output goes nowhere useful in some desktop sessions, which makes
// a QML warning impossible to see. R9VIEW_DEBUG=1 forces every message straight
// to stderr, unbuffered.
static void stderrLogger(QtMsgType, const QMessageLogContext &context, const QString &message)
{
    fprintf(stderr, "[%s:%d] %s\n", context.file ? context.file : "?", context.line,
            qPrintable(message));
    fflush(stderr);
}

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    borrowParentConsole();
#endif

    if (qEnvironmentVariableIsSet("R9VIEW_DEBUG"))
        qInstallMessageHandler(stderrLogger);

#ifdef R9VIEW_VIDEO
    // mpv renders through OpenGL, and the scene graph has to be on the same
    // API for the video to arrive as an ordinary texture the interface can be
    // drawn over. Qt picks Direct3D on Windows by default, so say so here --
    // before any QQuickWindow exists, which is the only time it takes effect.
    //
    // This is also the one change that could stop the image viewer working on
    // a machine whose OpenGL driver is broken, so there is a way out of it:
    // R9VIEW_GRAPHICS_API=d3d11 (or vulkan, metal, software) gives up video to
    // get the pictures back.
    {
        const QByteArray api = qgetenv("R9VIEW_GRAPHICS_API").toLower();
        if (api.isEmpty() || api == "opengl")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        else if (api == "d3d11" || api == "direct3d11")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
        else if (api == "vulkan")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);
        else if (api == "metal")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Metal);
        else if (api == "software")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
#endif

    QGuiApplication app(argc, argv);
    app.setApplicationName(u"r9view"_s);
    app.setOrganizationName(u"r9view"_s);
    app.setApplicationVersion(u"1.0.0"_s);
    app.setDesktopFileName(u"io.github.codingerr0r.r9view"_s);
    QIcon::setThemeName(QIcon::themeName());
    app.setWindowIcon(QIcon::fromTheme(u"io.github.codingerr0r.r9view"_s,
                                       QIcon(u":/qt/qml/R9View/icons/r9view.svg"_s)));

    // Pin the control style: the desktop's Qt theme has no say over a viewer
    // that is drawn edge to edge in its own palette.
    QQuickStyle::setStyle(u"Basic"_s);

    QCommandLineParser parser;
    parser.setApplicationDescription(
        u"r9view -- a touch-first image and comic viewer.\n"
        "Opens a folder of images, a single image, or a zip/cbz/rar/cbr/7z archive."_s);
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(u"target"_s, u"Folder, image, or comic archive to open."_s);
    QCommandLineOption listOption(u"list"_s, u"Print the page order that would be read, then exit."_s);
    parser.addOption(listOption);
    parser.process(app);

    // --list is how you check that a weirdly named archive really does come out
    // in the right order, without opening a window.
    if (parser.isSet(listOption)) {
        const QStringList targets = parser.positionalArguments();
        if (targets.isEmpty()) {
            qWarning("--list needs a folder or archive");
            return 2;
        }
        int start = 0;
        QString error;
        QTextStream out(stdout);

        // Video first, because it is the reading that can be checked least
        // easily by eye: --list is the quickest way to see which subtitle a
        // nested Subs/ folder actually matched to which episode.
        if (const auto list = Playlist::open(targets.first(), &start, &error)) {
            for (int i = 0; i < list->count(); ++i) {
                const MediaEntry &entry = list->entries().at(i);
                out << (i + 1) << "\t" << entry.name << "\n";
                for (const SubtitleRef &sub : entry.subtitles) {
                    out << "\t\tsub [" << sub.rank << "] "
                        << (sub.lang.isEmpty() ? u"??"_s : sub.lang) << "  "
                        << sub.title << "  <- " << sub.url << "\n";
                }
            }
            for (const QString &dir : list->fontDirs())
                out << "\tfonts\t" << dir << "\n";
            return 0;
        }

        const auto source = PageSource::open(targets.first(), &start, &error);
        if (!source) {
            qWarning("%s: %s", qPrintable(targets.first()), qPrintable(error));
            return 1;
        }
        for (int i = 0; i < source->count(); ++i)
            out << (i + 1) << "\t" << source->entries().at(i).name << "\n";
        return 0;
    }

    QQmlApplicationEngine engine;

    // Ask the engine for the Book singleton rather than making one here and
    // hoping QML adopts it. It will not: QML constructs its own, and you end up
    // with C++ opening a file on an object the interface never looks at.
    Book *book = engine.singletonInstance<Book *>(u"R9View"_s, u"Book"_s);
    if (!book) {
        qWarning("could not create the Book singleton");
        return 1;
    }

    engine.addImageProvider(u"page"_s, new PageProvider(book->store(), false));
    engine.addImageProvider(u"thumb"_s, new PageProvider(book->store(), true));

    engine.loadFromModule(u"R9View"_s, u"Main"_s);
    if (engine.rootObjects().isEmpty())
        return 1;

    const QStringList args = parser.positionalArguments();
    if (!args.isEmpty())
        book->openPath(args.first());

    return app.exec();
}
