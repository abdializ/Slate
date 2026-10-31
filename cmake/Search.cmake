# Swift is compiled separately so both Makefiles and Ninja can build the native
# Objective-C++ shell. No Swift package downloads or third-party crypto are used.
find_program(SLATE_XCRUN xcrun REQUIRED)
set(SLATE_SEARCH_DIR "${PROJECT_SOURCE_DIR}/platform/macos/search")
file(GLOB SLATE_SEARCH_SOURCES CONFIGURE_DEPENDS "${SLATE_SEARCH_DIR}/*.swift")
set(SLATE_SEARCH_BUILD "${CMAKE_CURRENT_BINARY_DIR}/search")
set(SLATE_SEARCH_LIBRARY "${SLATE_SEARCH_BUILD}/libSlateSearch.dylib")
set(SLATE_SEARCH_HEADER "${SLATE_SEARCH_BUILD}/SlateSearch-Swift.h")
set(SLATE_SEARCH_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_OSX_ARCHITECTURES)
  list(LENGTH CMAKE_OSX_ARCHITECTURES SLATE_SEARCH_ARCH_COUNT)
  if(SLATE_SEARCH_ARCH_COUNT GREATER 1)
    message(FATAL_ERROR "Build Slate separately for each macOS architecture; the search bridge uses one architecture per build.")
  endif()
  list(GET CMAKE_OSX_ARCHITECTURES 0 SLATE_SEARCH_ARCH)
endif()
file(CONFIGURE OUTPUT "${SLATE_SEARCH_BUILD}/build-mode.txt"
  CONTENT "architecture=${SLATE_SEARCH_ARCH}\nverification=${SLATE_ENABLE_VERIFY}\n")
set(SLATE_SEARCH_VERIFY_FLAG)
if(SLATE_ENABLE_VERIFY)
  set(SLATE_SEARCH_VERIFY_FLAG -D SLATE_ENABLE_VERIFY)
endif()
add_custom_command(OUTPUT "${SLATE_SEARCH_LIBRARY}" "${SLATE_SEARCH_HEADER}"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${SLATE_SEARCH_BUILD}"
  COMMAND "${SLATE_XCRUN}" swiftc -swift-version 5 -O
    -module-cache-path "${SLATE_SEARCH_BUILD}/ModuleCache"
    -target "${SLATE_SEARCH_ARCH}-apple-macosx12.0"
    ${SLATE_SEARCH_VERIFY_FLAG}
    -emit-library -emit-module -module-name SlateSearch
    -emit-objc-header-path "${SLATE_SEARCH_HEADER}"
    -emit-module-path "${SLATE_SEARCH_BUILD}/SlateSearch.swiftmodule"
    -o "${SLATE_SEARCH_LIBRARY}"
    -Xlinker -install_name -Xlinker @rpath/libSlateSearch.dylib
    ${SLATE_SEARCH_SOURCES}
  DEPENDS ${SLATE_SEARCH_SOURCES} "${SLATE_SEARCH_BUILD}/build-mode.txt"
  VERBATIM)
add_custom_target(SlateSearchBuild DEPENDS "${SLATE_SEARCH_LIBRARY}" "${SLATE_SEARCH_HEADER}")
add_library(SlateSearchServicesLib SHARED IMPORTED)
set_target_properties(SlateSearchServicesLib PROPERTIES IMPORTED_LOCATION "${SLATE_SEARCH_LIBRARY}")
add_dependencies(SlateSearchServicesLib SlateSearchBuild)

set(SLATE_SEARCH_TEST "${SLATE_SEARCH_BUILD}/search_services_tests")
add_custom_command(OUTPUT "${SLATE_SEARCH_TEST}"
 COMMAND "${SLATE_XCRUN}" swiftc -swift-version 5 -D SLATE_SEARCH_TESTS
 -module-cache-path "${SLATE_SEARCH_BUILD}/ModuleCache"
 -target "${SLATE_SEARCH_ARCH}-apple-macosx12.0"
 -o "${SLATE_SEARCH_TEST}" ${SLATE_SEARCH_SOURCES} "${PROJECT_SOURCE_DIR}/tests/search_services_tests.swift"
 DEPENDS ${SLATE_SEARCH_SOURCES} "${PROJECT_SOURCE_DIR}/tests/search_services_tests.swift" VERBATIM)
add_custom_target(SlateSearchTestsBuild ALL DEPENDS "${SLATE_SEARCH_TEST}")
add_test(NAME search_services COMMAND /usr/bin/python3 "${PROJECT_SOURCE_DIR}/tests/run_search_tests.py" "${SLATE_SEARCH_TEST}")
set_tests_properties(search_services PROPERTIES TIMEOUT 70)
add_executable(search_components_tests "${PROJECT_SOURCE_DIR}/tests/search_components_tests.mm"
 "${PROJECT_SOURCE_DIR}/platform/macos/omnibox_overlay.mm" "${PROJECT_SOURCE_DIR}/platform/macos/find_bar.mm")
add_dependencies(search_components_tests SlateSearchBuild)
target_include_directories(search_components_tests PRIVATE "${PROJECT_SOURCE_DIR}" "${SLATE_SEARCH_BUILD}")
target_compile_options(search_components_tests PRIVATE -fobjc-arc -Wno-incomplete-implementation)
target_link_libraries(search_components_tests PRIVATE SlateSearchServicesLib "-framework Cocoa" "-framework WebKit" "-framework PDFKit" "-framework QuartzCore")
add_test(NAME search_components COMMAND search_components_tests "${SLATE_SEARCH_BUILD}/test-artifacts")
add_executable(omnibox_components_tests "${PROJECT_SOURCE_DIR}/tests/omnibox_components_tests.mm" "${PROJECT_SOURCE_DIR}/platform/macos/omnibox_overlay.mm")
target_include_directories(omnibox_components_tests PRIVATE "${PROJECT_SOURCE_DIR}")
target_compile_options(omnibox_components_tests PRIVATE -fobjc-arc)
target_link_libraries(omnibox_components_tests PRIVATE "-framework Cocoa" "-framework QuartzCore")
add_test(NAME omnibox_components COMMAND omnibox_components_tests "${SLATE_SEARCH_BUILD}/test-artifacts")
