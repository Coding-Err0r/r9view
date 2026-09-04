#pragma once

#include "source.h"

#include <QMutex>
#include <QObject>
#include <QQmlEngine>
#include <QStringList>
#include <QUrl>

#include <memory>

// Thread-safe handle on the source that is currently open.
//
// The UI thread swaps the source when a new book is opened; decoder threads read
// it. Every swap bumps `generation`, which is baked into the image:// URLs the
// QML asks for -- so requests issued against the previous book resolve to
// nothing instead of racing, and Qt's pixmap cache never serves a stale page.
class PageStore
{
public:
    void set(std::shared_ptr<PageSource> source);
    std::shared_ptr<PageSource> get(int generation) const;
    int generation() const;

private:
    mutable QMutex m_mutex;
    std::shared_ptr<PageSource> m_source;
    int m_generation = 0;
};

// The open book: what it is, how many pages, which one we are on. QML talks to
// exactly this object.
class Book : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Every property gets its own notify signal. Sharing one signal across
    // several properties looks tidy and quietly breaks QML: a binding on the
    // shared signal is only re-evaluated for whichever property QML happened to
    // hook, so `model: Book.count` can sit at zero while a neighbouring text
    // binding shows the right number.
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString location READ location NOTIFY locationChanged)
    Q_PROPERTY(bool isArchive READ isArchive NOTIFY isArchiveChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int generation READ generation NOTIFY generationChanged)
    Q_PROPERTY(int index READ index WRITE setIndex NOTIFY indexChanged)
    Q_PROPERTY(QString pageName READ pageName NOTIFY pageNameChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QStringList recent READ recent NOTIFY recentChanged)
    Q_PROPERTY(bool rightToLeft READ rightToLeft WRITE setRightToLeft NOTIFY rightToLeftChanged)
    Q_PROPERTY(int fitMode READ fitMode WRITE setFitMode NOTIFY fitModeChanged)

public:
    explicit Book(QObject *parent = nullptr);
    ~Book() override;

    enum FitMode { FitWindow = 0, FitWidth = 1, FitHeight = 2, Original = 3 };
    Q_ENUM(FitMode)

    PageStore *store() { return &m_store; }

    bool ready() const { return m_count > 0; }
    bool busy() const { return m_busy; }
    QString title() const { return m_title; }
    QString location() const { return m_location; }
    bool isArchive() const { return m_isArchive; }
    int count() const { return m_count; }
    int generation() const { return m_generation; }
    int index() const { return m_index; }
    QString pageName() const;
    QString error() const { return m_error; }
    QStringList recent() const { return m_recent; }
    bool rightToLeft() const { return m_rightToLeft; }
    int fitMode() const { return m_fitMode; }

    void setIndex(int i);
    void setRightToLeft(bool rtl);
    void setFitMode(int mode);

    Q_INVOKABLE void openPath(const QString &path);
    Q_INVOKABLE void openUrl(const QUrl &url);
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void first();
    Q_INVOKABLE void last();
    Q_INVOKABLE void close();
    Q_INVOKABLE void clearError();
    Q_INVOKABLE void forgetRecent();
    Q_INVOKABLE QString shortName(const QString &path) const;
    // Absolute path of a page on disk, empty for pages inside an archive.
    Q_INVOKABLE QString pageFilePath(int i) const;

signals:
    void readyChanged();
    void titleChanged();
    void locationChanged();
    void isArchiveChanged();
    void countChanged();
    void generationChanged();
    void pageNameChanged();
    void busyChanged();
    void indexChanged();
    void errorChanged();
    void recentChanged();
    void rightToLeftChanged();
    void fitModeChanged();
    void opened();

private:
    void adopt(std::shared_ptr<PageSource> source, int startIndex, const QString &error);
    void rememberPosition() const;
    void pushRecent(const QString &path);
    void loadSettings();

    PageStore m_store;
    QString m_title;
    QString m_location;
    bool m_isArchive = false;
    int m_count = 0;
    int m_generation = 0;
    int m_index = 0;
    bool m_busy = false;
    QString m_error;
    QStringList m_recent;
    bool m_rightToLeft = false;
    int m_fitMode = FitWindow;
    quint64 m_openToken = 0;
};
