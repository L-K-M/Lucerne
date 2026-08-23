#pragma once

// The small modal dialogs: Document Setup (page size, margins, fold marks),
// Header & Footer (three zones × two bands + "numbered from page"), and
// Preferences (ruler units). Standard QDialog + QFormLayout chrome so they
// feel native under Yaru/Adwaita rather than mirroring the Mac's classic look.

#include "core/Model.h"

#include <QDialog>

class QCheckBox;
class QComboBox;
class QDoubleSpinBox;
class QLineEdit;
class QSpinBox;

namespace lucerne {

class DocumentSetupDialog : public QDialog {
    Q_OBJECT
public:
    DocumentSetupDialog(const PageConfig &page, bool metricUnits, QWidget *parent = nullptr);
    PageConfig pageConfig() const;

private:
    void loadPreset(const PageConfig &page);
    bool m_metric;
    QComboBox *m_preset;
    QDoubleSpinBox *m_width;
    QDoubleSpinBox *m_height;
    QDoubleSpinBox *m_top;
    QDoubleSpinBox *m_left;
    QDoubleSpinBox *m_bottom;
    QDoubleSpinBox *m_right;
    QCheckBox *m_foldMarks;
};

class HeaderFooterDialog : public QDialog {
    Q_OBJECT
public:
    HeaderFooterDialog(const std::optional<PageFurniture> &header,
                       const std::optional<PageFurniture> &footer,
                       std::optional<int> pageNumberStart, QWidget *parent = nullptr);
    std::optional<PageFurniture> header() const;
    std::optional<PageFurniture> footer() const;
    std::optional<int> pageNumberStart() const;

private:
    QLineEdit *m_zones[2][3];   // [header/footer][left/center/right]
    QSpinBox *m_numberedFrom;
};

class PreferencesDialog : public QDialog {
    Q_OBJECT
public:
    explicit PreferencesDialog(QWidget *parent = nullptr);

signals:
    void rulerUnitChanged();
};

} // namespace lucerne
