#include "app/Dialogs.h"

#include <QCheckBox>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QDoubleSpinBox>
#include <QFormLayout>
#include <QGridLayout>
#include <QLabel>
#include <QLineEdit>
#include <QSettings>
#include <QSpinBox>

namespace lucerne {

namespace {
constexpr double pointsPerCm = 72.0 / 2.54;
constexpr double pointsPerInch = 72.0;
}

// MARK: - Document Setup

DocumentSetupDialog::DocumentSetupDialog(const PageConfig &page, bool metricUnits,
                                         QWidget *parent)
    : QDialog(parent), m_metric(metricUnits) {
    setWindowTitle(tr("Document Setup"));
    const double unit = m_metric ? pointsPerCm : pointsPerInch;
    const QString suffix = m_metric ? tr(" cm") : tr(" in");

    auto *form = new QFormLayout(this);
    form->setFieldGrowthPolicy(QFormLayout::FieldsStayAtSizeHint);

    m_preset = new QComboBox(this);
    m_preset->addItem(tr("A4"), QStringLiteral("A4"));
    m_preset->addItem(tr("US Letter"), QStringLiteral("Letter"));
    m_preset->addItem(tr("Custom"), QStringLiteral("custom"));
    form->addRow(tr("Page size:"), m_preset);

    auto makeSpin = [&](double maxPoints) {
        auto *spin = new QDoubleSpinBox(this);
        spin->setDecimals(2);
        spin->setRange(0, maxPoints / unit);
        spin->setSuffix(suffix);
        spin->setSingleStep(m_metric ? 0.5 : 0.25);
        return spin;
    };
    m_width = makeSpin(5000);
    m_height = makeSpin(5000);
    auto *sizeRow = new QGridLayout;
    sizeRow->addWidget(new QLabel(tr("Width")), 0, 0);
    sizeRow->addWidget(m_width, 0, 1);
    sizeRow->addWidget(new QLabel(tr("Height")), 0, 2);
    sizeRow->addWidget(m_height, 0, 3);
    form->addRow(QString(), sizeRow);

    m_top = makeSpin(1000);
    m_left = makeSpin(1000);
    m_bottom = makeSpin(1000);
    m_right = makeSpin(1000);
    auto *margins = new QGridLayout;
    margins->addWidget(new QLabel(tr("Top")), 0, 0);
    margins->addWidget(m_top, 0, 1);
    margins->addWidget(new QLabel(tr("Bottom")), 0, 2);
    margins->addWidget(m_bottom, 0, 3);
    margins->addWidget(new QLabel(tr("Left")), 1, 0);
    margins->addWidget(m_left, 1, 1);
    margins->addWidget(new QLabel(tr("Right")), 1, 2);
    margins->addWidget(m_right, 1, 3);
    form->addRow(tr("Margins:"), margins);

    m_foldMarks = new QCheckBox(tr("Fold marks for windowed envelopes (DIN 5008)"), this);
    form->addRow(QString(), m_foldMarks);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    form->addRow(buttons);

    connect(m_preset, &QComboBox::currentIndexChanged, this, [this](int) {
        const QString key = m_preset->currentData().toString();
        if (key == QLatin1String("A4")) loadPreset(PageConfig::a4());
        else if (key == QLatin1String("Letter")) loadPreset(PageConfig::usLetter());
    });

    // Seed from the document (after the connect so a preset pick still works).
    const int presetIndex = m_preset->findData(page.size);
    m_preset->setCurrentIndex(presetIndex >= 0 ? presetIndex : m_preset->findData("custom"));
    loadPreset(page);
    // Editing any dimension flips the preset to Custom.
    for (QDoubleSpinBox *spin : {m_width, m_height})
        connect(spin, &QDoubleSpinBox::valueChanged, this, [this](double) {
            if (!m_width->hasFocus() && !m_height->hasFocus()) return;
            m_preset->setCurrentIndex(m_preset->findData("custom"));
        });
}

void DocumentSetupDialog::loadPreset(const PageConfig &page) {
    const double unit = m_metric ? pointsPerCm : pointsPerInch;
    m_width->setValue(page.width / unit);
    m_height->setValue(page.height / unit);
    m_top->setValue(page.margins.top / unit);
    m_left->setValue(page.margins.left / unit);
    m_bottom->setValue(page.margins.bottom / unit);
    m_right->setValue(page.margins.right / unit);
    m_foldMarks->setChecked(page.foldMarks.value_or(false));
}

PageConfig DocumentSetupDialog::pageConfig() const {
    const double unit = m_metric ? pointsPerCm : pointsPerInch;
    PageConfig page;
    page.size = m_preset->currentData().toString();
    page.width = std::max(72.0, m_width->value() * unit);
    page.height = std::max(72.0, m_height->value() * unit);
    page.margins = {m_top->value() * unit, m_left->value() * unit,
                    m_bottom->value() * unit, m_right->value() * unit};
    // Keep at least 72 pt of writable area on each axis (the Mac's guard),
    // scaling a facing pair down proportionally when it would squeeze it out.
    auto limitPair = [](double total, double &a, double &b) {
        const double writable = total - a - b;
        if (writable >= 72 || a + b <= 0) return;
        const double scale = std::max(0.0, (total - 72) / (a + b));
        a *= scale;
        b *= scale;
    };
    limitPair(page.width, page.margins.left, page.margins.right);
    limitPair(page.height, page.margins.top, page.margins.bottom);
    if (m_foldMarks->isChecked()) page.foldMarks = true;
    return page;
}

// MARK: - Header & Footer

HeaderFooterDialog::HeaderFooterDialog(const std::optional<PageFurniture> &header,
                                       const std::optional<PageFurniture> &footer,
                                       std::optional<int> pageNumberStart, QWidget *parent)
    : QDialog(parent) {
    setWindowTitle(tr("Header & Footer"));
    auto *grid = new QGridLayout(this);

    grid->addWidget(new QLabel(tr("Left")), 0, 1);
    grid->addWidget(new QLabel(tr("Center")), 0, 2);
    grid->addWidget(new QLabel(tr("Right")), 0, 3);
    grid->addWidget(new QLabel(tr("Header:")), 1, 0);
    grid->addWidget(new QLabel(tr("Footer:")), 2, 0);
    for (int band = 0; band < 2; ++band) {
        const PageFurniture furniture =
            (band == 0 ? header : footer).value_or(PageFurniture{});
        const QString zoneTexts[3] = {furniture.left, furniture.center, furniture.right};
        for (int zone = 0; zone < 3; ++zone) {
            auto *edit = new QLineEdit(zoneTexts[zone], this);
            edit->setPlaceholderText(QStringLiteral("—"));
            edit->setMinimumWidth(130);
            m_zones[band][zone] = edit;
            grid->addWidget(edit, band + 1, zone + 1);
        }
    }

    auto *numberedRow = new QGridLayout;
    m_numberedFrom = new QSpinBox(this);
    m_numberedFrom->setRange(1, 2000);
    m_numberedFrom->setValue(pageNumberStart.value_or(1));
    numberedRow->addWidget(new QLabel(tr("Numbered from page:")), 0, 0);
    numberedRow->addWidget(m_numberedFrom, 0, 1);
    numberedRow->setColumnStretch(2, 1);
    grid->addLayout(numberedRow, 3, 0, 1, 4);

    auto *hint = new QLabel(
        tr("Each zone may use the tokens {page}, {pages}, {date}, and {title} — for "
           "example a centered footer of “Page {page} of {pages}”. “Numbered "
           "from” is the first page that counts as page 1; earlier pages are "
           "unnumbered."),
        this);
    hint->setWordWrap(true);
    hint->setStyleSheet(QStringLiteral("color: palette(placeholder-text);"));
    grid->addWidget(hint, 4, 0, 1, 4);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    grid->addWidget(buttons, 5, 0, 1, 4);
}

std::optional<PageFurniture> HeaderFooterDialog::header() const {
    const PageFurniture furniture{m_zones[0][0]->text(), m_zones[0][1]->text(),
                                  m_zones[0][2]->text()};
    return furniture.isEmpty() ? std::nullopt : std::optional<PageFurniture>(furniture);
}

std::optional<PageFurniture> HeaderFooterDialog::footer() const {
    const PageFurniture furniture{m_zones[1][0]->text(), m_zones[1][1]->text(),
                                  m_zones[1][2]->text()};
    return furniture.isEmpty() ? std::nullopt : std::optional<PageFurniture>(furniture);
}

std::optional<int> HeaderFooterDialog::pageNumberStart() const {
    // A start of 1 is the default and stays out of the file.
    return m_numberedFrom->value() <= 1 ? std::nullopt
                                        : std::optional<int>(m_numberedFrom->value());
}

// MARK: - Preferences

PreferencesDialog::PreferencesDialog(QWidget *parent) : QDialog(parent) {
    setWindowTitle(tr("Preferences"));
    auto *form = new QFormLayout(this);

    auto *units = new QComboBox(this);
    units->addItem(tr("Centimeters"), QStringLiteral("centimeters"));
    units->addItem(tr("Inches"), QStringLiteral("inches"));
    QSettings settings;
    const QString current =
        settings.value(QStringLiteral("rulerUnit"), QStringLiteral("centimeters")).toString();
    units->setCurrentIndex(std::max(0, units->findData(current)));
    form->addRow(tr("Ruler units:"), units);

    auto *hint = new QLabel(tr("Affects the ruler and the Document Setup fields."), this);
    hint->setStyleSheet(QStringLiteral("color: palette(placeholder-text);"));
    form->addRow(QString(), hint);

    connect(units, &QComboBox::currentIndexChanged, this, [this, units](int) {
        QSettings().setValue(QStringLiteral("rulerUnit"), units->currentData().toString());
        emit rulerUnitChanged();
    });

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close, this);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    form->addRow(buttons);
}

} // namespace lucerne
