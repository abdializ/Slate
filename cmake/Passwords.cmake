# Swift is compiled separately so both Makefiles and Ninja can build the native
# Objective-C++ shell. No Swift package downloads or third-party crypto are used.
find_program(SLATE_XCRUN xcrun REQUIRED)
set(SLATE_PASSWORDS_DIR "${PROJECT_SOURCE_DIR}/platform/macos/passwords")
file(GLOB SLATE_PASSWORD_SOURCES CONFIGURE_DEPENDS "${SLATE_PASSWORDS_DIR}/*.swift")
set(SLATE_PASSWORDS_BUILD "${CMAKE_CURRENT_BINARY_DIR}/passwords")
set(SLATE_PASSWORDS_LIBRARY "${SLATE_PASSWORDS_BUILD}/libSlatePasswords.dylib")
set(SLATE_PASSWORDS_HEADER "${SLATE_PASSWORDS_BUILD}/SlatePasswords-Swift.h")
set(SLATE_PASSWORD_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_OSX_ARCHITECTURES)
  list(LENGTH CMAKE_OSX_ARCHITECTURES SLATE_PASSWORD_ARCH_COUNT)
  if(SLATE_PASSWORD_ARCH_COUNT GREATER 1)
    message(FATAL_ERROR "Build Slate separately for each macOS architecture; the password bridge uses one architecture per build.")
  endif()
  list(GET CMAKE_OSX_ARCHITECTURES 0 SLATE_PASSWORD_ARCH)
endif()
file(CONFIGURE OUTPUT "${SLATE_PASSWORDS_BUILD}/build-mode.txt"
  CONTENT "architecture=${SLATE_PASSWORD_ARCH}\nverification=${SLATE_ENABLE_VERIFY}\n")
set(SLATE_PASSWORD_VERIFY_FLAG)
if(SLATE_ENABLE_VERIFY)
  set(SLATE_PASSWORD_VERIFY_FLAG -D SLATE_ENABLE_VERIFY)
endif()
add_custom_command(OUTPUT "${SLATE_PASSWORDS_LIBRARY}" "${SLATE_PASSWORDS_HEADER}"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${SLATE_PASSWORDS_BUILD}"
  COMMAND "${SLATE_XCRUN}" swiftc -swift-version 5 -O
    -module-cache-path "${SLATE_PASSWORDS_BUILD}/ModuleCache"
    -target "${SLATE_PASSWORD_ARCH}-apple-macosx12.0"
    ${SLATE_PASSWORD_VERIFY_FLAG}
    -emit-library -emit-module -module-name SlatePasswords
    -emit-objc-header-path "${SLATE_PASSWORDS_HEADER}"
    -emit-module-path "${SLATE_PASSWORDS_BUILD}/SlatePasswords.swiftmodule"
    -o "${SLATE_PASSWORDS_LIBRARY}"
    -Xlinker -install_name -Xlinker @rpath/libSlatePasswords.dylib
    ${SLATE_PASSWORD_SOURCES}
  DEPENDS ${SLATE_PASSWORD_SOURCES} "${SLATE_PASSWORDS_BUILD}/build-mode.txt"
  VERBATIM)
add_custom_target(SlatePasswordsBuild DEPENDS "${SLATE_PASSWORDS_LIBRARY}" "${SLATE_PASSWORDS_HEADER}")
add_library(SlatePasswordServicesLib SHARED IMPORTED)
set_target_properties(SlatePasswordServicesLib PROPERTIES IMPORTED_LOCATION "${SLATE_PASSWORDS_LIBRARY}")
add_dependencies(SlatePasswordServicesLib SlatePasswordsBuild)

set(SLATE_PASSWORD_TEST "${SLATE_PASSWORDS_BUILD}/password_services_tests")
add_custom_command(OUTPUT "${SLATE_PASSWORD_TEST}"
  COMMAND "${SLATE_XCRUN}" swiftc -swift-version 5
    -module-cache-path "${SLATE_PASSWORDS_BUILD}/ModuleCache"
    -target "${SLATE_PASSWORD_ARCH}-apple-macosx12.0" -D SLATE_PASSWORD_TESTS
    -o "${SLATE_PASSWORD_TEST}" ${SLATE_PASSWORD_SOURCES}
    "${PROJECT_SOURCE_DIR}/tests/password_services_tests.swift"
  DEPENDS ${SLATE_PASSWORD_SOURCES} "${PROJECT_SOURCE_DIR}/tests/password_services_tests.swift"
  VERBATIM)
add_custom_target(SlatePasswordTestsBuild ALL DEPENDS "${SLATE_PASSWORD_TEST}")
add_test(NAME password_services COMMAND "${SLATE_PASSWORD_TEST}" "${PROJECT_SOURCE_DIR}"
  "${SLATE_PASSWORDS_BUILD}/test-artifacts")
if(SLATE_NODE_EXECUTABLE)
  add_test(NAME password_field_and_webauthn COMMAND "${SLATE_NODE_EXECUTABLE}"
    "${PROJECT_SOURCE_DIR}/tests/password_fields_tests.js" "${SLATE_PASSWORDS_BUILD}/test-artifacts")
  set_tests_properties(password_field_and_webauthn PROPERTIES DEPENDS password_services)
endif()
