# File purpose: Builds the native app bundle, links macOS frameworks, packages assets/filters, and
# signs build outputs.

set(EXECUTABLE_NAME Slate)
set(PRODUCT_NAME Slate)
include("${PROJECT_SOURCE_DIR}/cmake/Sparkle.cmake")

add_executable(Slate MACOSX_BUNDLE
  main.mm
  tab_switcher.mm
  app_updater.mm
  ../../engine/webkit_engine.mm
  ../../engine/webkit_shields.mm
  favicon_loader.mm
  interaction_feedback.mm
  memory_monitor.cc
  memory_monitor.mm
  session_store.mm
  bookmark_store.mm
  bookmarks_panel.mm
  credential_persistence.mm
  browser_importer.mm
  passwords_panel.mm
  import_dialog.mm
  specs_panel.mm
  settings_panel.mm
  download_manager.mm
  downloads_panel.mm
  spaces_manager.mm
  site_card_panel.mm
  plate_components.mm
  float_window.mm
  form_relay.mm
  omnibox_overlay.mm
  pdf_overlay.mm
  find_bar.mm
  AppIcon.icns
  AppIcon.png
  TabIconTemplate.png
  BrowserGlyph.png
  SlateRibbon.png
)

target_compile_options(Slate PRIVATE -Os "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
# Slate note: Keep scripted verification commands out of the default production build.
option(SLATE_ENABLE_VERIFY "Enable verify command runner" OFF)
set(SLATE_VERIFY_PLIST_FLAG false)
if(SLATE_ENABLE_VERIFY)
  set(SLATE_VERIFY_PLIST_FLAG true)
  target_compile_definitions(Slate PRIVATE SLATE_ENABLE_VERIFY=1)
endif()
include("${PROJECT_SOURCE_DIR}/cmake/Passwords.cmake")
include("${PROJECT_SOURCE_DIR}/cmake/Search.cmake")
add_dependencies(Slate SlateSearchBuild)
target_include_directories(Slate PRIVATE "${SLATE_SEARCH_BUILD}")
target_link_libraries(Slate PRIVATE SlateSearchServicesLib)
add_dependencies(Slate SlatePasswordsBuild)
target_include_directories(Slate PRIVATE "${SLATE_PASSWORDS_BUILD}")
target_link_libraries(Slate PRIVATE SlatePasswordServicesLib)
target_link_options(Slate PRIVATE -Wl,-dead_strip)
target_include_directories(Slate PRIVATE "${PROJECT_SOURCE_DIR}")
# Slate note: Link system WebKit/AppKit and related native services alongside slate_core.
target_link_libraries(Slate PRIVATE
  slate_core
  SlateSparkle
  "-framework WebKit"
  "-framework Cocoa"
  "-framework QuartzCore"
  "-framework AudioToolbox"
  "-framework Security"
  "-framework SecurityInterface"
  "-framework LocalAuthentication"
  "-framework UniformTypeIdentifiers"
  "-framework PDFKit"
  "-framework CoreImage"
  "-framework ImageIO"
  "-lsqlite3"
)

set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/AppIcon.icns" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/AppIcon.png" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/TabIconTemplate.png" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/BrowserGlyph.png" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/SlateRibbon.png" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

set_target_properties(Slate PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
  MACOSX_BUNDLE_ICON_FILE AppIcon.icns
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "@executable_path/../Frameworks"
  OUTPUT_NAME "Slate"
)

# Metadata/filter-only changes must run packaging and signing again, too.
set_property(TARGET Slate APPEND PROPERTY LINK_DEPENDS
  "${CMAKE_CURRENT_BINARY_DIR}/Slate.app/Contents/Info.plist"
  "${PROJECT_SOURCE_DIR}/filtering/lists/slate-network.txt"
  "${PROJECT_SOURCE_DIR}/filtering/lists/compat.txt"
  "${PROJECT_SOURCE_DIR}/scripts/codesign.sh"
  "${CMAKE_CURRENT_SOURCE_DIR}/Slate.entitlements"
)

add_custom_command(TARGET Slate POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:Slate>/Contents/Frameworks"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SLATE_PASSWORDS_LIBRARY}"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Frameworks/libSlatePasswords.dylib"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SLATE_SEARCH_LIBRARY}"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Frameworks/libSlateSearch.dylib"
  COMMAND /usr/bin/ditto --norsrc --noextattr
    "${SLATE_SPARKLE_ROOT}/Sparkle.framework"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Frameworks/Sparkle.framework"
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/licenses"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PROJECT_SOURCE_DIR}/third_party-licenses/Sparkle.txt" "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/licenses/Sparkle.txt"
  COMMAND /usr/bin/python3 "${PROJECT_SOURCE_DIR}/scripts/package-shields.py" "${PROJECT_SOURCE_DIR}/filtering/lists" "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/shields"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/AppIcon.icns"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/AppIcon.icns"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/AppIcon.png"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/AppIcon.png"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/TabIconTemplate.png"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/TabIconTemplate.png"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/SlateRibbon.png"
    "$<TARGET_BUNDLE_DIR:Slate>/Contents/Resources/SlateRibbon.png"
  COMMAND /bin/bash "${PROJECT_SOURCE_DIR}/scripts/codesign.sh" "$<TARGET_BUNDLE_DIR:Slate>"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/Release"
  COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_CURRENT_BINARY_DIR}/Release/Slate.app"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "$<TARGET_BUNDLE_DIR:Slate>" "${CMAKE_CURRENT_BINARY_DIR}/Release/Slate.app"
  VERBATIM
)
