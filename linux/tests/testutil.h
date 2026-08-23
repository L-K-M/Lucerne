#pragma once

// Small shared helpers for the Qt test suite. EXPECT_THROW instead of
// QVERIFY_THROWS_EXCEPTION so the suite builds against Qt 6.2 (Ubuntu 22.04)
// as well as 6.4+ (Ubuntu 24.04).

#include <QtTest>

#define EXPECT_THROW(expression, ExceptionType)                                     \
    do {                                                                            \
        bool caughtExpected = false;                                                \
        try {                                                                       \
            expression;                                                             \
        } catch (const ExceptionType &) {                                           \
            caughtExpected = true;                                                  \
        } catch (...) {                                                             \
            QFAIL("threw, but not the expected " #ExceptionType);                   \
        }                                                                           \
        QVERIFY2(caughtExpected, "expected " #ExceptionType " from " #expression);  \
    } while (false)
