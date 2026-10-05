set(EXECUTABLE_NAME Slate)
set(PRODUCT_NAME Slate)

add_executable(Slate MACOSX_BUNDLE
  main.mm
  ../../engine/webkit_engine.mm
  ../../engine/webkit_shields.mm
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
option(SLATE_ENABLE_VERIFY "Enable verify command runner" OFF)
if(SLATE_ENABLE_VERIFY)
  target_compile_definitions(Slate PRIVATE SLATE_ENABLE_VERIFY=1)
endif()
target_link_options(Slate PRIVATE -Wl,-dead_strip)
target_include_directories(Slate PRIVATE "${PROJECT_SOURCE_DIR}")
target_link_libraries(Slate PRIVATE
  slate_core
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
  OUTPUT_NAME "Slate"
)

add_custom_command(TARGET Slate POST_BUILD
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
