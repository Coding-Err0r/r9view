cmake_minimum_required(VERSION 3.21)
project(r9view VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Concurrent Svg)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(r9view
    src/main.cpp
    src/book.cpp
    src/book.h
    src/naturalsort.cpp
    src/naturalsort.h
    src/pageprovider.cpp
    src/pageprovider.h
    src/source.cpp
    src/source.h
)

# Globbed with CONFIGURE_DEPENDS so adding a QML file does not mean remembering
# to add it here as well -- forgetting only shows up at runtime, as "X is not a
# type", which is a poor way to find out.
file(GLOB R9VIEW_QML RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml)

file(GLOB R9VIEW_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} qml/icons/*.svg)

# The sources live in qml/ for tidiness, but the QML module expects them at its
# own root -- so every file is aliased back to its bare name (and icons to
# icons/<name>) inside the resource system.
foreach(qmlfile IN LISTS R9VIEW_QML)
    get_filename_component(alias ${qmlfile} NAME)
    set_source_files_properties(${qmlfile} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()
foreach(icon IN LISTS R9VIEW_ICONS)
    get_filename_component(alias ${icon} NAME)
    set_source_files_properties(${icon} PROPERTIES QT_RESOURCE_ALIAS icons/${alias})
endforeach()
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(r9view
    URI R9View
    VERSION 1.0
    QML_FILES ${R9VIEW_QML}
    RESOURCES ${R9VIEW_ICONS}
)

target_include_directories(r9view PRIVATE src)
target_link_libraries(r9view PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Concurrent Qt6::Svg
    PkgConfig::LIBARCHIVE
)

include(GNUInstallDirs)
install(TARGETS r9view RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES packaging/io.github.codingerr0r.r9view.desktop
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)
install(FILES qml/icons/r9view.svg
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/scalable/apps
        RENAME io.github.codingerr0r.r9view.svg)
install(FILES packaging/io.github.codingerr0r.r9view.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/metainfo)
