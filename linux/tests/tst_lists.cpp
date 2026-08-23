// List numbering engine (C++) — mirrors Swift's ListSupportTests so ordered
// counters, nesting, and marker glyphs resolve identically across ports.

#include "core/Lists.h"

#include <QtTest>

using namespace lucerne;

namespace {

std::optional<ListItemModel> item(const QString &list, bool ordered, const QString &marker,
                                  int level = 0, std::optional<int> start = std::nullopt) {
    ListItemModel m;
    m.list = list;
    m.ordered = ordered;
    m.marker = marker;
    m.level = level;
    m.start = start;
    return m;
}

QStringList markers(const QVector<std::optional<ListItemModel>> &items) {
    QStringList out;
    for (const auto &r : ListMarkers::resolve(items))
        out.append(r ? r->text : QStringLiteral("∅"));
    return out;
}

} // namespace

class tst_lists : public QObject {
    Q_OBJECT

private slots:
    void orderedCountsFromOne() {
        QCOMPARE(markers({item("A", true, "decimal"), item("A", true, "decimal"),
                          item("A", true, "decimal")}),
                 (QStringList{"1.", "2.", "3."}));
    }

    void orderedRespectsStartNumber() {
        QCOMPARE(markers({item("A", true, "decimal", 0, 5), item("A", true, "decimal")}),
                 (QStringList{"5.", "6."}));
    }

    void differentListIdsRestartNumbering() {
        QCOMPARE(markers({item("A", true, "decimal"), item("B", true, "decimal")}),
                 (QStringList{"1.", "1."}));
    }

    void nonListParagraphBreaksTheList() {
        QCOMPARE(markers({item("A", true, "decimal"), std::nullopt,
                          item("A", true, "decimal")}),
                 (QStringList{"1.", "∅", "1."}));
    }

    void bulletBeforeOrderedDoesNotBumpTheFirstNumber() {
        QCOMPARE(markers({item("A", false, "disc"), item("A", true, "decimal")}),
                 (QStringList{"•", "1."}));
    }

    void orderedContinuesAcrossAnInterveningBullet() {
        QCOMPARE(markers({item("A", true, "decimal"), item("A", false, "dash"),
                          item("A", true, "decimal")}),
                 (QStringList{"1.", "–", "2."}));
    }

    void nestingRestartsAndResumesCounters() {
        QCOMPARE(markers({
                     item("A", true, "decimal", 0),
                     item("A", true, "lower-alpha", 1),
                     item("A", true, "lower-alpha", 1),
                     item("A", true, "decimal", 0),
                     item("A", true, "lower-alpha", 1),   // fresh deeper counter
                 }),
                 (QStringList{"1.", "a.", "b.", "2.", "a."}));
    }

    void alphaLabels() {
        QCOMPARE(ListMarkers::alpha(1, false), QStringLiteral("a"));
        QCOMPARE(ListMarkers::alpha(26, false), QStringLiteral("z"));
        QCOMPARE(ListMarkers::alpha(27, false), QStringLiteral("aa"));
        QCOMPARE(ListMarkers::alpha(52, false), QStringLiteral("az"));
        QCOMPARE(ListMarkers::alpha(53, true), QStringLiteral("BA"));
    }

    void romanLabels() {
        QCOMPARE(ListMarkers::roman(4, true), QStringLiteral("IV"));
        QCOMPARE(ListMarkers::roman(1994, true), QStringLiteral("MCMXCIV"));
        QCOMPARE(ListMarkers::roman(3, false), QStringLiteral("iii"));
        QCOMPARE(ListMarkers::roman(4000, true), QStringLiteral("4000"));   // fallback
    }

    void bulletGlyphs() {
        QCOMPARE(ListMarkers::bulletGlyph("disc", 0), QStringLiteral("•"));
        QCOMPARE(ListMarkers::bulletGlyph("circle", 0), QStringLiteral("◦"));
        QCOMPARE(ListMarkers::bulletGlyph("square", 0), QStringLiteral("▪"));
        QCOMPARE(ListMarkers::bulletGlyph("dash", 0), QStringLiteral("–"));
        // Unknown cycles by depth.
        QCOMPARE(ListMarkers::bulletGlyph("mystery", 1), QStringLiteral("◦"));
    }

    void contentIndentGrowsPerLevelAndClamps() {
        QCOMPARE(ListGeometry::contentIndent(0), 24.0);
        QCOMPARE(ListGeometry::contentIndent(2), 72.0);
        QCOMPARE(ListGeometry::contentIndent(400), ListGeometry::contentIndent(8));
        QCOMPARE(ListGeometry::clampedLevel(-3), 0);
    }
};

QTEST_GUILESS_MAIN(tst_lists)
#include "tst_lists.moc"
