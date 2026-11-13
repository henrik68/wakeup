cmake_minimum_required(VERSION 3.5)
project(wakeup C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

find_package(Qt5 REQUIRED COMPONENTS Core Gui Qml Quick DBus Concurrent)

# Architecture of the phone the click is built for (arm64, armhf or amd64).
execute_process(COMMAND dpkg-architecture -qDEB_HOST_ARCH
                OUTPUT_VARIABLE CLICK_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
configure_file(manifest.json.in ${CMAKE_CURRENT_BINARY_DIR}/manifest.json)

add_executable(wakeup src/main.cpp src/alarmsettings.cpp src/risingsounds.cpp)
target_link_libraries(wakeup Qt5::Core Qt5::Gui Qt5::Qml Qt5::Quick Qt5::DBus Qt5::Concurrent ${CMAKE_DL_LIBS})

install(TARGETS wakeup RUNTIME DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/manifest.json wakeup.apparmor wakeup.desktop LICENSE
        DESTINATION ${CMAKE_INSTALL_PREFIX})
install(DIRECTORY qml DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES assets/icon.png DESTINATION ${CMAKE_INSTALL_PREFIX}/assets)
install(DIRECTORY share DESTINATION ${CMAKE_INSTALL_PREFIX})
