#pragma once

// The start experience: icon, tagline, New / Open / Sample buttons, recent
// documents, and the day's epigraph — the Mac welcome window's content in a
// GNOME-appropriate dialog.

#include <QDialog>

class QListWidget;

namespace lucerne {

class WelcomeDialog : public QDialog {
    Q_OBJECT
public:
    explicit WelcomeDialog(QWidget *parent = nullptr);

    enum class Choice { None, NewLetter, Open, SampleLetter, OpenRecent };
    Choice choice() const { return m_choice; }
    QString recentPath() const { return m_recentPath; }

    static QStringList recentFiles();
    static void addRecentFile(const QString &path);

private:
    Choice m_choice = Choice::None;
    QString m_recentPath;
    QListWidget *m_recents;
};

} // namespace lucerne
