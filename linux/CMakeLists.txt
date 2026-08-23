# Lucerne for Linux — the Qt 6 port (docs/ubuntu-port.md Phase 1, Option A).
#
# Two targets plus tests:
#   lucerne-core  — Qt Core/Gui only: the C++ mirror of Swift's LucerneCore
#                   (model, .luce ZIP IO, Markdown export, lists, history,
#                   style library, page/exclusion geometry). No widgets, so it
#                   is testable headless and reusable by tools.
#   lucerne       — the QtWidgets application: paginated editor with live
#                   text flow around freely placed images (QTextLayout manual
#                   line layout — the Scribus-proven approach).
#
# Qt >= 6.2 (Ubuntu 22.04 ships 6.2, 24.04 ships 6.4). Build:
#   cmake -S linux -B linux/build -G Ninja && cmake --build linux/build
cmake_minimum_required(VERSION 3.19)

project(lucerne VERSION 0.6.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Widgets PrintSupport)
find_package(ZLIB REQUIRED)

# ---------------------------------------------------------------- lucerne-core
add_library(lucerne-core STATIC
    src/core/Geometry.h
    src/core/Model.h            src/core/Model.cpp
    src/core/Coding.h           src/core/Coding.cpp
    src/core/MiniZip.h          src/core/MiniZip.cpp
    src/core/LuceArchive.h      src/core/LuceArchive.cpp
    src/core/Markdown.h         src/core/Markdown.cpp
    src/core/Lists.h            src/core/Lists.cpp
    src/core/History.h          src/core/History.cpp
    src/core/StyleLibrary.h     src/core/StyleLibrary.cpp
    src/core/PageMetrics.h      src/core/PageMetrics.cpp
    src/core/DefaultDocuments.h src/core/DefaultDocuments.cpp
    src/core/Furniture.h        src/core/Furniture.cpp
)
target_include_directories(lucerne-core PUBLIC src)
target_link_libraries(lucerne-core PUBLIC Qt6::Core Qt6::Gui ZLIB::ZLIB)

# --------------------------------------------------------------------- lucerne
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/app/main.cpp")
add_executable(lucerne
    src/app/main.cpp
    src/app/DocumentBridge.h    src/app/DocumentBridge.cpp
    src/app/PageLayout.h        src/app/PageLayout.cpp
    src/app/PageCanvas.h        src/app/PageCanvas.cpp
    src/app/Editor.h            src/app/Editor.cpp
    src/app/MainWindow.h        src/app/MainWindow.cpp
    src/app/Ruler.h             src/app/Ruler.cpp
    src/app/WelcomeDialog.h     src/app/WelcomeDialog.cpp
    src/app/Dialogs.h           src/app/Dialogs.cpp
    resources/lucerne.qrc
)
target_link_libraries(lucerne PRIVATE lucerne-core Qt6::Widgets Qt6::PrintSupport)
endif()

# ----------------------------------------------------------------------- tests
enable_testing()
find_package(Qt6 6.2 COMPONENTS Test)
if(Qt6Test_FOUND)
    # The shared conformance corpus lives beside the Swift tests at the repo
    # root — both implementations walk the same files (docs/ubuntu-port.md §3).
    set(LUCERNE_FIXTURES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../Tests/Fixtures")

    foreach(t minizip coding markdown lists history fixtures metrics furniture layout)
        if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_${t}.cpp")
            continue()
        endif()
        add_executable(tst_${t} tests/tst_${t}.cpp)
        target_link_libraries(tst_${t} PRIVATE lucerne-core Qt6::Test)
        target_compile_definitions(tst_${t} PRIVATE
            LUCERNE_FIXTURES_DIR="${LUCERNE_FIXTURES_DIR}")
        add_test(NAME ${t} COMMAND tst_${t})
        # Headless CI: the layout test measures real text, so it needs a QPA
        # platform but not a display.
        set_tests_properties(${t} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    endforeach()
    if(TARGET tst_layout)
        # The layout test exercises the app's paginator, not just core.
        target_sources(tst_layout PRIVATE
            src/app/DocumentBridge.cpp src/app/PageLayout.cpp)
        target_link_libraries(tst_layout PRIVATE Qt6::Widgets)
    endif()
endif()

# --------------------------------------------------------------- install / deb
include(GNUInstallDirs)
if(TARGET lucerne)
install(TARGETS lucerne RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES resources/ch.lkmc.Lucerne.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES resources/ch.lkmc.Lucerne.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES resources/lucerne-mime.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/mime/packages
        RENAME ch.lkmc.Lucerne.xml)
foreach(size 32 48 64 128 256 512)
    install(FILES resources/icons/lucerne-${size}.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps
            RENAME ch.lkmc.Lucerne.png)
endforeach()
endif()

set(CPACK_PACKAGE_NAME "lucerne")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_CONTACT "Lucerne <claudecode@lkmc.ch>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY
    "ClarisWorks-style word editor with free image placement and live text flow")
set(CPACK_GENERATOR "DEB")
set(CPACK_DEBIAN_PACKAGE_SECTION "editors")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_HOMEPAGE "https://github.com/L-K-M/Lucerne")
include(CPack)
