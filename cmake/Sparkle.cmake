# Pin the official binary distribution. Keep all signing keys outside source control.
set(SLATE_SPARKLE_VERSION "2.10.1")
set(SLATE_SPARKLE_ROOT "${PROJECT_SOURCE_DIR}/third_party/Sparkle-${SLATE_SPARKLE_VERSION}" CACHE PATH "Sparkle distribution directory")
if(NOT EXISTS "${SLATE_SPARKLE_ROOT}/Sparkle.framework/Sparkle")
  file(MAKE_DIRECTORY "${PROJECT_BINARY_DIR}/downloads")
  set(sparkle_archive "${PROJECT_BINARY_DIR}/downloads/Sparkle-${SLATE_SPARKLE_VERSION}.tar.xz")
  file(DOWNLOAD
    "https://github.com/sparkle-project/Sparkle/releases/download/${SLATE_SPARKLE_VERSION}/Sparkle-${SLATE_SPARKLE_VERSION}.tar.xz"
    "${sparkle_archive}"
    EXPECTED_HASH SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
    TLS_VERIFY ON)
  file(MAKE_DIRECTORY "${SLATE_SPARKLE_ROOT}")
  file(ARCHIVE_EXTRACT INPUT "${sparkle_archive}" DESTINATION "${SLATE_SPARKLE_ROOT}")
endif()
add_library(SlateSparkle SHARED IMPORTED)
set_target_properties(SlateSparkle PROPERTIES
  IMPORTED_LOCATION "${SLATE_SPARKLE_ROOT}/Sparkle.framework/Sparkle"
  INTERFACE_COMPILE_OPTIONS "-F${SLATE_SPARKLE_ROOT}")
set(SLATE_UPDATE_FEED_URL "https://github.com/abdializ/Slate/releases/latest/download/appcast.xml" CACHE STRING "HTTPS URL of Slate's signed update feed")
if(NOT SLATE_UPDATE_FEED_URL MATCHES "^https://[^/]+/")
  message(FATAL_ERROR "SLATE_UPDATE_FEED_URL must use HTTPS")
endif()
file(READ "${PROJECT_SOURCE_DIR}/updates/public-key.txt" SLATE_UPDATE_PUBLIC_KEY)
string(STRIP "${SLATE_UPDATE_PUBLIC_KEY}" SLATE_UPDATE_PUBLIC_KEY)
string(LENGTH "${SLATE_UPDATE_PUBLIC_KEY}" public_key_length)
if(NOT public_key_length EQUAL 44)
  message(FATAL_ERROR "Slate requires a 32-byte base64 Sparkle public key")
endif()
