#include "app/WelcomeDialog.h"

#include <QDate>
#include <QFileInfo>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QSettings>
#include <QVBoxLayout>

namespace lucerne {

namespace {

const int maxRecents = 10;

QString epigraphOfTheDay() {
    static const char *const epigraphs[] = {
        QT_TRANSLATE_NOOP("WelcomeDialog", "“A letter does not blush.” — Cicero"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“Letters mingle souls.” — John Donne"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“Write while the heat is in you.” — Thoreau"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“Writing maketh an exact man.” — Francis Bacon"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“While we teach, we learn.” — Seneca"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“Brevity is the soul of wit.” — Shakespeare"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“Style is the dress of thoughts.” — Chesterfield"),
        QT_TRANSLATE_NOOP("WelcomeDialog", "“Well done is better than well said.” — Franklin"),
    };
    const int day = QDate::currentDate().dayOfYear();
    return QObject::tr(epigraphs[(day - 1) % 8]);
}

} // namespace

QStringList WelcomeDialog::recentFiles() {
    QStringList list = QSettings().value(QStringLiteral("recentFiles")).toStringList();
    list.erase(std::remove_if(list.begin(), list.end(),
                              [](const QString &p) { return !QFileInfo::exists(p); }),
               list.end());
    return list;
}

void WelcomeDialog::addRecentFile(const QString &path) {
    QSettings settings;
    QStringList list = settings.value(QStringLiteral("recentFiles")).toStringList();
    list.removeAll(path);
    list.prepend(path);
    while (list.size() > maxRecents) list.removeLast();
    settings.setValue(QStringLiteral("recentFiles"), list);
}

WelcomeDialog::WelcomeDialog(QWidget *parent) : QDialog(parent) {
    setWindowTitle(tr("Welcome to Lucerne"));
    setMinimumWidth(420);

    auto *column = new QVBoxLayout(this);
    column->setSpacing(10);
    column->setContentsMargins(28, 24, 28, 20);

    auto *icon = new QLabel(this);
    icon->setPixmap(QIcon(QStringLiteral(":/icons/lucerne.png")).pixmap(96, 96));
    icon->setAlignment(Qt::AlignHCenter);
    column->addWidget(icon);

    auto *title = new QLabel(QStringLiteral("<h2>Lucerne</h2>"), this);
    title->setAlignment(Qt::AlignHCenter);
    column->addWidget(title);

    auto *tagline = new QLabel(tr("A small, pleasant tool for writing letters."), this);
    tagline->setAlignment(Qt::AlignHCenter);
    tagline->setStyleSheet(QStringLiteral("font-style: italic;"));
    column->addWidget(tagline);
    column->addSpacing(8);

    auto addButton = [&](const QString &text, Choice choice, bool isDefault = false) {
        auto *button = new QPushButton(text, this);
        button->setDefault(isDefault);
        connect(button, &QPushButton::clicked, this, [this, choice] {
            m_choice = choice;
            accept();
        });
        column->addWidget(button);
        return button;
    };
    addButton(tr("New Letter"), Choice::NewLetter, true);
    addButton(tr("Open…"), Choice::Open);
    addButton(tr("New Sample Letter"), Choice::SampleLetter);
    column->addSpacing(10);

    auto *recentsLabel = new QLabel(tr("Recent Documents"), this);
    recentsLabel->setStyleSheet(QStringLiteral("font-weight: 600;"));
    column->addWidget(recentsLabel);

    m_recents = new QListWidget(this);
    m_recents->setMinimumHeight(150);
    m_recents->setAlternatingRowColors(true);
    const QStringList recents = recentFiles();
    if (recents.isEmpty()) {
        auto *empty = new QListWidgetItem(tr("No recent letters yet"), m_recents);
        empty->setFlags(Qt::NoItemFlags);
    } else {
        for (const QString &path : recents) {
            auto *item = new QListWidgetItem(QFileInfo(path).completeBaseName(), m_recents);
            item->setToolTip(path);
            item->setData(Qt::UserRole, path);
        }
    }
    connect(m_recents, &QListWidget::itemActivated, this, [this](QListWidgetItem *item) {
        const QString path = item->data(Qt::UserRole).toString();
        if (path.isEmpty()) return;
        m_choice = Choice::OpenRecent;
        m_recentPath = path;
        accept();
    });
    column->addWidget(m_recents);

    auto *epigraph = new QLabel(epigraphOfTheDay(), this);
    epigraph->setAlignment(Qt::AlignHCenter);
    epigraph->setWordWrap(true);
    epigraph->setStyleSheet(
        QStringLiteral("font-style: italic; color: palette(placeholder-text);"));
    column->addSpacing(6);
    column->addWidget(epigraph);
}

} // namespace lucerne
