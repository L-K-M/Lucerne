// Header/footer tokens (C++) — mirrors Swift's FurnitureTokenTests, plus the
// page-number bookkeeping the canvas uses.

#include "core/Furniture.h"

#include <QtTest>

using namespace lucerne;

class tst_furniture : public QObject {
    Q_OBJECT

private slots:
    void allFourTokensSubstitute() {
        QCOMPARE(Furniture::resolveTemplate("{title} — page {page} of {pages} · {date}",
                                            2, 5, "March 3, 2026", "Offer Letter"),
                 QStringLiteral("Offer Letter — page 2 of 5 · March 3, 2026"));
    }

    void pageTokenOnUnnumberedPageBlanksZone() {
        QCOMPARE(Furniture::resolveTemplate("Page {page} of {pages}", std::nullopt, 5,
                                            "d", "t"),
                 QString());
        QCOMPARE(Furniture::resolveTemplate("{title}", std::nullopt, 5,
                                            "March 3, 2026", "Offer Letter"),
                 QStringLiteral("Offer Letter"));
        QCOMPARE(Furniture::resolveTemplate("{date}", std::nullopt, 5,
                                            "March 3, 2026", "Offer Letter"),
                 QStringLiteral("March 3, 2026"));
    }

    void pagesShowsNumberedCount() {
        QCOMPARE(Furniture::resolveTemplate("{pages}", 1, 3, "d", "t"), QStringLiteral("3"));
    }

    void emptyTemplateStaysEmpty() {
        QCOMPARE(Furniture::resolveTemplate("", 1, 2, "d", "t"), QString());
    }

    void numberingStartSkipsEarlyPages() {
        // pageNumberStart = 3: physical pages 0 and 1 are unnumbered, page 2
        // shows 1 (spec §3.2's worked example).
        QCOMPARE(Furniture::displayedPageNumber(0, 5, 3), std::optional<int>());
        QCOMPARE(Furniture::displayedPageNumber(1, 5, 3), std::optional<int>());
        QCOMPARE(Furniture::displayedPageNumber(2, 5, 3), std::optional<int>(1));
        QCOMPARE(Furniture::displayedPageNumber(4, 5, 3), std::optional<int>(3));
        QCOMPARE(Furniture::numberedPageCount(5, 3), 3);
        QCOMPARE(Furniture::numberedPageCount(5, std::nullopt), 5);
    }
};

QTEST_GUILESS_MAIN(tst_furniture)
#include "tst_furniture.moc"
