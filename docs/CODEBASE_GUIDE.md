# Slate codebase guide

Every original project file is listed below. Source comments explain file responsibilities and selected decisions. Binary assets, license/attribution text, filter data, and JSON measurements retain their exact original bytes; their notes live here. The installed Slate.app bundle, generated caches, and Finder metadata are build/runtime artifacts and are not source annotation targets.

## Read the project in this order

1. `core/tab_model.h` and `.cc`: logical tabs and close bookkeeping.
2. `core/browser_engine.h` and `engine/engine_events.h`: commands and callbacks.
3. `engine/webkit_engine.mm`: native page configuration and lifecycle.
4. `platform/macos/main.mm`: connect those layers to the browser interface.
5. `platform/macos/session_store.mm`, `spaces_manager.mm`, and `split_workspace.h`: persistence and workspace layout.
6. `tests/` and `scripts/`: behavior checks and native verification.

## Boundaries to keep in mind

- Logical tabs can exist without live pages. Session restore reloads URLs; it does not restore JavaScript heaps or edited forms.
- Loaded tab/split switching reuses views. A Space switch closes outgoing runtimes.
- Automatic unloading is disabled. The C++ resource controller is a policy, and current adapter observations are incomplete.
- Main-process footprint is not whole-browser footprint. Recorded benchmark results have workload and attribution limits.
- Entitlements only apply when attached to the actual signature. Some existing comments/docs retain legacy Chromium or older architecture descriptions.
- Embedded JavaScript helper headers can be unused by the current engine. A passing mock test does not demonstrate live-site or DRM compatibility.

## Project root

### `.gitignore`

Excludes generated builds, local browser/profile data, signing material, and development artifacts from Git.

- Line 5, `build/`: Build directories contain generated outputs and must not be committed as application source.

### `CMakeLists.txt`

Configures C++20, the shared core, test executables, optional Node tests, and the macOS target.

- Line 9, `add_library(slate_core`: Build reusable browser logic separately from the native shell.
- Line 18, `find_program(SLATE_NODE_EXECUTABLE node)`: JavaScript component tests are registered only when a Node executable is available.

### `LICENSE`

Contains the MIT license for original Slate source; its legal text is preserved verbatim.

### `README.md`

Introduces Slate, its product goal, build/test steps, supported behavior, and measurement limits.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

## core

### `core/browser_engine.h`

Defines the C++ interface the native UI uses to control a page engine.

WebKit implements this interface. The default occlusion and trim methods below are no-ops; calling them alone does not prove that page memory is reclaimed.

- Line 12, `class BrowserEngine {`: Virtual methods let the UI navigate and close a page without depending on WKWebView types.

### `core/credential_store.cc`

Implements the in-memory password collection, exact-origin lookup, updates, and search.

Persistent storage is handled separately by platform/macos/credential_persistence.mm.

- Line 14, `std::string normalize_host(`: Normalize scheme, host, and default port before matching; similar-looking domains must not share credentials.

### `core/credential_store.h`

Declares the in-memory password collection, exact-origin lookup, updates, and search.

Persistent storage is handled separately by platform/macos/credential_persistence.mm.

- Line 13, `struct Credential {`: Each record carries the website origin and account name as well as its password.

### `core/library.cc`

Implements the small C++ bookmark list and its validation rules.

- Line 13, `BookmarkList::BookmarkList(`: Validate restored entries and IDs before accepting them as bookmark state.

### `core/library.h`

Declares the small C++ bookmark list and its validation rules.

- Line 13, `class BookmarkList {`: This flat list is the C++ model; the native bookmark store separately supports folders.

### `core/navigation.cc`

Implements address-bar parsing into a URL, a Google search, or an invalid input.

- Line 71, `NavigationDecision resolve_address_bar(`: Reject executable/local-file schemes before treating an input as a URL or search.

### `core/navigation.h`

Declares address-bar parsing into a URL, a Google search, or an invalid input.

- Line 9, `struct NavigationDecision {`: The UI receives both the classification and the final destination URL.

### `core/protection.h`

Defines temporary page observations used to decide whether unloading would be unsafe.

These observations are not session snapshots, and declaring a signal here does not mean the current WebKit adapter detects it completely.

- Line 25, `bool fresh(`: A protection observation expires after 30 seconds; unknown or stale state blocks policy-driven discarding.
- Line 30, `bool blocks_discard(`: Any uncertain, editing, media, capture, download, or dialog condition conservatively protects the tab.

### `core/resource_controller.cc`

Implements tab lifecycle data and a pure policy that recommends state transitions.

The production memory-pressure handler does not apply automatic discard recommendations. Automatic unloading is disabled.

- Line 8, `std::vector<Transition> ResourceController::evaluate(`: Return proposed transitions without creating, destroying, or modifying any page engine.

### `core/resource_controller.h`

Declares tab lifecycle data and a pure policy that recommends state transitions.

The production memory-pressure handler does not apply automatic discard recommendations. Automatic unloading is disabled.

- Line 15, `enum class Lifecycle {`: Discarded means the tab record exists without a live engine; Cold is a policy label, not a guaranteed WebKit freeze.

### `core/shields.cc`

Implements content-blocking settings, per-site pauses, request classification, and block counters.

- Line 47, `FilterDecision ShieldController::classify(`: Allow top-level documents and honor global/per-site settings before matching subresource rules.

### `core/shields.h`

Declares content-blocking settings, per-site pauses, request classification, and block counters.

- Line 20, `class ShieldController {`: This C++ policy wraps the filter matcher; WebKit network blocking has a separate native adapter.

### `core/tab_model.cc`

Implements logical tab identity, selection, groups, pinning, zoom, and close bookkeeping.

Pinning controls placement. Keep loaded controls unloading. Neither is a serialized running-page snapshot.

- Line 70, `bool TabModel::select(`: Select a logical tab and update lifecycle labels without allocating a page view.
- Line 181, `void TabModel::observe(`: Ignore observations from an older document generation so late callbacks cannot overwrite newer page state.
- Line 206, `void TabModel::closed(`: Removing a tab deletes its record; discarding keeps the record and marks its live page absent.

### `core/tab_model.h`

Declares logical tab identity, selection, groups, pinning, zoom, and close bookkeeping.

Pinning controls placement. Keep loaded controls unloading. Neither is a serialized running-page snapshot.

- Line 14, `class TabModel {`: The model stores metadata and live/closing IDs; the native application owns the actual page views.

## docs

### `docs/ADBLOCK_MEDIA_ARCHITECTURE.md`

Describes how filtering and media compatibility interact.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/ARCHITECTURE.md`

Describes module boundaries and native browser/media architecture.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/BENCHMARKS.md`

Explains the controlled tab benchmark, recorded results, attribution, reproduction, and limitations.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/DEBLOAT.md`

Records resource-overhead improvements, enforced budgets, and October 6 validation.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/DOWNLOADS.md`

Describes staged downloads, safe filenames, publication, quarantine, and resumable transfers.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/PASSWORDS.md`

Describes password matching, Keychain storage, authenticated actions, and legacy migration.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/PIP.md`

Describes intended picture-in-picture behavior and its engine/native integration.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/RESOURCE_SAFETY.md`

Defines the current lifecycle/protection boundary and prerequisites for automatic unloading.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/SECURITY.md`

Describes security boundaries, storage, browser/page bridges, and validation.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/SHIELDS.md`

Describes filter lists, per-site controls, and the supported blocking architecture.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/UI_FIXES.md`

Records native interface fixes and their verification context.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `docs/benchmarks/2026-10-05-tabs.json`

Stores sanitized raw samples and environment/workload details for the October 5 Slate/Chrome benchmark.

JSON does not accept comments; the guide explains this file without changing recorded measurement bytes.

### `docs/benchmarks/2026-10-06-debloat-slate.json`

Stores sanitized Slate-only samples for the October 6 resource-overhead validation.

These records do not constitute a new matched Chrome comparison. Recorded measurement bytes are preserved.

## engine

### `engine/audio_compat_js.h`

Contains an older audio compatibility script that rewrites AAC/M4A sources to a custom WAV scheme.

- Line 11, `inline constexpr char kAudioCompatJs`: The constant holds JavaScript source. Its observer prepares relevant audio/source elements instead of rescanning on every unrelated mutation. This helper is not injected by the current WebKit engine.

### `engine/autofill_js.h`

Contains the JavaScript that finds visible sign-in inputs and requests native credential suggestions.

- Line 11, `inline constexpr char kAutofillJs`: findLoginFormElements chooses visible password/username inputs; messages ask the native handler for suggestions. Native handler validation remains the authority for credential access.

### `engine/engine_events.h`

Defines callbacks through which the WebKit engine reports page events to native browser UI.

std::function stores a callable supplied by the application. This keeps the engine independent of the concrete app delegate.

- Line 16, `struct EngineEvents {`: Navigation, media, credential, and close events flow back through this callback bundle.
- Line 30, `std::function<void()> close_ready;`: Closing has separate readiness, cancellation, and completion events so native state can follow the asynchronous engine handshake.

### `engine/floating_video_js.h`

Contains C++-embedded video isolation/control scripts and a known-player URL helper.

- Line 20, `inline constexpr char kFloatingVideoIsolateOn`: The raw string contains a script that isolates a selected video while leaving its page machinery alive. This header is tested separately; the native floating-window module also defines its own scripts.

### `engine/image_download_js.h`

Contains the isolated-world script that routes trusted image right-clicks to the native Save Image menu.

- Line 10, `static constexpr const char* kImageDownloadJs`: isTrusted filters synthetic events; composedPath finds the clicked image; HTTP(S) validation limits what gets sent to the native handler.

### `engine/media_compat_js.h`

Contains older codec diagnostics and a narrow mediaCapabilities compatibility patch.

- Line 11, `inline constexpr char kMediaCompatJs`: The script checks reported capabilities and logs media diagnostics. Its existence does not establish codec or DRM support, and the current WebKit engine does not inject this helper.

### `engine/media_monitor_js.h`

Contains event-driven audio/video, user-intent, frame, and picture-in-picture observation.

- Line 11, `inline constexpr char kMediaMonitorJs`: Trusted gestures distinguish user-started playback from autoplay. report publishes media state; mutation checks are coalesced and page-cache events reset/re-publish observations.

### `engine/page_chrome_js.h`

Contains an older audible-tab and automatic picture-in-picture script.

- Line 8, `inline constexpr char kPageChromeJs`: pickVideo chooses a media candidate; page events report playback and request PiP. Current WebKit integration uses media_monitor_js.h instead of injecting this helper.

### `engine/page_theme_js.h`

Contains the isolated main-frame script that reads page colors for Slate chrome.

- Line 9, `inline constexpr char kPageThemeJs`: report sends only a changed color. suspend removes observers/timers for hidden documents; resume reconnects and refreshes when visible.

### `engine/pip_state.h`

Combines per-frame picture-in-picture reports with authoritative native presentation state.

- Line 19, `bool active() const {`: Once a native observation exists it wins; a replaced iframe or ad player cannot contradict the native PiP window.

### `engine/platform_audio.h`

Declares AudioToolbox conversion of supported audio files/bytes into 16-bit PCM WAV.

This utility is built by the audio test target; the current WebKit adapter does not call it as a custom audio-scheme pipeline.

- Line 13, `bool DecodeAudioFileToWav(`: Both entry points return success and place decoded bytes or an error into the output arguments.

### `engine/platform_audio.mm`

Implements AudioToolbox conversion of supported audio files/bytes into 16-bit PCM WAV.

This utility is built by the audio test target; the current WebKit adapter does not call it as a custom audio-scheme pipeline.

- Line 102, `bool DecodeAudioBytesToWav(`: Stage a bounded byte payload in a temporary file, decode it with AudioToolbox, then remove the temporary file.

### `engine/stealth_js.h`

Contains site compatibility overrides used by the WebKit shields adapter.

- Line 8, `inline constexpr char kStealthJs`: The bypass suffix list excludes sensitive sign-in and streaming hosts from overrides. This compatibility script is not a guarantee of anonymous or undetectable browsing.

### `engine/webkit_engine.h`

Declares the bridge between the C++ BrowserEngine interface and native WKWebView pages.

- Line 15, `std::unique_ptr<BrowserEngine> make_webkit_engine(`: Opaque pointers keep native types out of the C++ API; the caller must pass the expected native objects on the UI thread.

### `engine/webkit_engine.mm`

Implements the bridge between the C++ BrowserEngine interface and native WKWebView pages.

- Line 811, `WKWebViewConfiguration* config =`: Preserve a supplied popup configuration, or create one for a new page; storage and injected scripts are configured before constructing the WKWebView.
- Line 1371, `void inspect_protection() override {`: This adapter currently reports only a limited observation; it does not inspect all DOM/application state. Automatic page destruction must not rely on it.
- Line 1194, `web_view_ = [[WKWebView alloc]`: Construct the actual native page view after configuration; this is where a saved logical tab becomes a rendering engine.
- Line 1418, `void close() override {`: Release native handlers and page-owned work through the engine close path, then notify the application.

### `engine/webkit_shields.h`

Declares native WebKit content-rule compilation, per-site application, and compatibility scripts.

Injected streaming helpers use site-specific heuristics. They do not guarantee removal of integrated stream ads.

- Line 15, `class WebKitShields {`: The singleton shares compiled rules across page controllers and tracks which hosts have shields disabled.

### `engine/webkit_shields.mm`

Implements native WebKit content-rule compilation, per-site application, and compatibility scripts.

Injected streaming helpers use site-specific heuristics. They do not guarantee removal of integrated stream ads.

- Line 676, `void WebKitShields::CompileRules(`: Translate supported list rules into WebKit content-rule JSON and compile them asynchronously.

## filtering

### `filtering/lists/NOTICE.txt`

Records attribution and separate terms for bundled EasyList/EasyPrivacy data; preserved verbatim.

### `filtering/lists/compat.txt`

Local allow exceptions intended to keep login, media, and other legitimate requests working.

Rule bytes and upstream attribution are preserved; explanations live in CODEBASE_GUIDE.md to avoid changing rule counts or compatibility data.

### `filtering/lists/easylist-network.txt`

Bundled upstream network ad-block rules used by the matchers and packaging pipeline.

Rule bytes and upstream attribution are preserved; explanations live in CODEBASE_GUIDE.md to avoid changing rule counts or compatibility data.

### `filtering/lists/easyprivacy-network.txt`

Bundled upstream network tracking-protection rules used by the matchers and packaging pipeline.

Rule bytes and upstream attribution are preserved; explanations live in CODEBASE_GUIDE.md to avoid changing rule counts or compatibility data.

### `filtering/lists/slate-network.txt`

Slate-specific supplemental network blocking rules.

Rule bytes and upstream attribution are preserved; explanations live in CODEBASE_GUIDE.md to avoid changing rule counts or compatibility data.

### `filtering/network_engine.cc`

Implements the supported subset of ad-block network rules and indexed request matching.

- Line 134, `FilterEngine FilterEngine::parse(`: Parse supported network syntax while skipping list comments, cosmetic rules, and unsupported constructs.
- Line 225, `FilterDecision FilterEngine::classify(`: Build candidates from host/token indexes before applying resource-type, domain, and exception checks.

### `filtering/network_engine.h`

Declares the supported subset of ad-block network rules and indexed request matching.

- Line 12, `enum class ResourceKind`: Each resource kind is a bit so a rule can apply to several request types.

## platform

### `platform/macos/AppIcon.icns`

macOS multi-resolution application icon resource.

Binary image bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `platform/macos/AppIcon.png`

Raster application icon packaged with the app.

Binary image bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `platform/macos/BrowserGlyph.png`

Raster browser glyph used by the native interface.

Binary image bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `platform/macos/CMakeLists.txt`

Builds the native app bundle, links macOS frameworks, packages assets/filters, and signs build outputs.

- Line 43, `option(SLATE_ENABLE_VERIFY`: Keep scripted verification commands out of the default production build.
- Line 50, `target_link_libraries(Slate PRIVATE`: Link system WebKit/AppKit and related native services alongside slate_core.

### `platform/macos/Info.plist.in`

Supplies bundle identity, executable/icon metadata, usage descriptions, and HTTP(S)/HTML handling registrations.

- Line 13, `<key>CFBundleIdentifier</key>`: This identifier is the app identity used by macOS registration and signing.
- Line 69, `<key>CFBundleURLTypes</key>`: Register HTTP and HTTPS handling so macOS can offer Slate as a browser.

### `platform/macos/Slate.entitlements`

Declares requested sandbox permissions for network access, user files, downloads, camera, and microphone.

This file grants no permission by itself. The signing script must attach it; the current ad-hoc fallback does not attach it.

- Line 9, `<key>com.apple.security.app-sandbox</key>`: Enable App Sandbox only when this entitlement is included in the effective signed application.

### `platform/macos/SlateRibbon.png`

Raster Slate ribbon artwork packaged with the app.

Binary image bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `platform/macos/TabIconTemplate.png`

Raster tab-icon template packaged with the app.

Binary image bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `platform/macos/active_browser_tab_shape.h`

Builds the Core Graphics outline for a selected horizontal tab.

- Line 18, `const CGFloat k=`: This cubic-Bezier factor approximates rounded corners.
- Line 31, `CGAffineTransform mirror=`: Mirror the path vertically when the caller uses the opposite coordinate orientation.

### `platform/macos/bookmark_store.h`

Declares bookmark/folder trees, local persistence, and bridges to the C++ bookmark list.

- Line 14, `@interface SlateBookmark :`: A node is either a website with a URL or a folder with children.

### `platform/macos/bookmark_store.mm`

Implements bookmark/folder trees, local persistence, and bridges to the C++ bookmark list.

- Line 440, `- (void)saveToPath:`: Serialize the tree as JSON and write it atomically so readers do not see a partially written file.

### `platform/macos/bookmarks_panel.h`

Declares bookmark dropdowns, management UI, tree dragging, and native bookmark menus.

- Line 10, `@protocol SlateBookmarksOwner`: The owner protocol lets the panel request navigation/bookmark actions without owning the browser implementation.

### `platform/macos/bookmarks_panel.mm`

Implements bookmark dropdowns, management UI, tree dragging, and native bookmark menus.

- Line 16, `static NSArray<SlateBookmark*>* ParseChromiumChildren(`: Recursively convert Chromium bookmark folders and URL entries into Slate native bookmark nodes.

### `platform/macos/browser_importer.h`

Declares bookmarks/history import from supported profiles and password import from CSV.

- Line 28, `class BrowserImporter {`: Static import entry points accept explicit source paths and return imported records or counts.

### `platform/macos/browser_importer.mm`

Implements bookmarks/history import from supported profiles and password import from CSV.

- Line 15, `void ExtractBookmarksRecursive(`: Walk nested bookmark JSON, accept HTTP(S) sites, and avoid adding URLs already present in the destination.

### `platform/macos/credential_persistence.h`

Declares Keychain-backed password persistence and reads of older saved-vault formats.

- Line 12, `std::unique_ptr<CredentialStore> load_credentials(`: The path identifies a profile-specific Keychain vault and the optional legacy file to read.

### `platform/macos/credential_persistence.mm`

Implements Keychain-backed password persistence and reads of older saved-vault formats.

- Line 40, `NSDictionary* VaultIdentity(`: Use the profile path as the Keychain account so separate profiles do not read the same vault.

### `platform/macos/download_manager.h`

Declares download state, WebKit/URLSession transfers, pause/resume, local history, and safe file publication.

- Line 9, `typedef NS_ENUM(NSInteger, SlateDownloadState)`: Finishing distinguishes received bytes from a safely published file that is ready to open.

### `platform/macos/download_manager.mm`

Implements download state, WebKit/URLSession transfers, pause/resume, local history, and safe file publication.

- Line 106, `static BOOL PublishDownload(`: Publish staged bytes only after filename/destination checks and quarantine handling; completion must not expose an unfinished file.

### `platform/macos/downloads_panel.h`

Declares the toolbar download indicator and native download list/actions.

- Line 11, `@interface SlateDownloadButton :`: The button reflects manager state; progress rendering is separate from the underlying transfer.

### `platform/macos/downloads_panel.mm`

Implements the toolbar download indicator and native download list/actions.

- Line 50, `- (void)configureWithItem:(SlateDownloadItem*)item ink:(NSColor*)ink muted:(NSColor*)muted {`: Render a row from its download model, including status and the actions currently available.

### `platform/macos/favicon_loader.h`

Declares bounded, cancellable icon requests, thumbnail decoding, and an in-memory cache.

- Line 8, `@interface SlateFaviconRequest :`: The returned request token lets navigation or tab closure cancel work owned by that tab.

### `platform/macos/favicon_loader.mm`

Implements bounded, cancellable icon requests, thumbnail decoding, and an in-memory cache.

- Line 39, `static NSData* SmallIcon(`: Reject oversized input/dimensions and decode only a small thumbnail rather than retaining a full-size source image.

### `platform/macos/find_bar.h`

Declares find-in-page UI with HTML and PDF search, highlights, and match navigation.

- Line 13, `@interface SlateFindBar :`: The targetWebView points at the selected page; the same bar can be retargeted after a tab switch.

### `platform/macos/find_bar.mm`

Implements find-in-page UI with HTML and PDF search, highlights, and match navigation.

- Line 323, `- (void)performSearchWithQuery:`: Route PDF documents through PDFKit search before using the HTML-page search path.

### `platform/macos/float_window.h`

Declares a custom floating-window video fallback that reuses an existing page view.

- Line 44, `@interface SlateFloat :`: lift/drop move an existing view; the application remains responsible for returning it to its original host.

### `platform/macos/float_window.mm`

Implements a custom floating-window video fallback that reuses an existing page view.

- Line 884, `- (void)drop {`: Remember position and remove observers, timers, and the lifted view when the fallback window closes.

### `platform/macos/form_relay.h`

Declares sign-in monitoring, framework-aware autofill, typing/fullscreen signals, and optional passkey suppression.

- Line 14, `@interface SlateFormRelay :`: Class methods supply scripts to the WebKit adapter; native code still validates and authorizes messages.

### `platform/macos/form_relay.mm`

Implements sign-in monitoring, framework-aware autofill, typing/fullscreen signals, and optional passkey suppression.

- Line 317, `+ (NSString *)fillScriptWithUser:`: JSON-encode values before placing them into JavaScript so quotes and special characters cannot become executable source.

### `platform/macos/import_dialog.h`

Declares the native dialog for selecting a source browser and categories to import.

- Line 10, `@interface SlateImportDialog :`: The dialog collects choices and reports them through a completion callback.

### `platform/macos/import_dialog.mm`

Implements the native dialog for selecting a source browser and categories to import.

- Line 125, `- (void)onImport:`: Read the selected categories and source, then complete the dialog with the requested import operation.

### `platform/macos/interaction_feedback.h`

Declares temporary zoom feedback and the download-arrival visual effect.

- Line 8, `@interface SlateZoomIndicator :`: showPercent presents the current zoom near its page; dismiss removes transient feedback.

### `platform/macos/interaction_feedback.mm`

Implements temporary zoom feedback and the download-arrival visual effect.

- Line 99, `+ (void)playInWindow:`: Reuse one bounded arrival effect per window so a burst of downloads does not accumulate overlays.

### `platform/macos/main.mm`

Starts Slate and coordinates native browser windows, tabs, split layouts, Spaces, navigation, media, and persistence.

Objective-C++ lets this file manipulate C++ TabModel state and AppKit/WebKit objects together. The logical model and the runtimes collection have different ownership: metadata versus live engines/views.

- Line 6977, `- (void)unloadTabWithId:(TabId)identifier {`: Manual unloading asks for confirmation because only tab metadata survives; page state can be lost.
- Line 7077, `- (void)switchSpaceToId:(NSString*)newSpaceId {`: A Space switch parks metadata and closes outgoing engines. It does not preserve running documents across Spaces.
- Line 9580, `- (void)presentWorkspacePages {`: Show existing hosts for the selected tab or split pair; view reuse preserves state when switching loaded pages.
- Line 9729, `- (void)memoryChanged:(slate::MemorySample)sample {`: Memory pressure trims bounded app-owned caches. Automatic page destruction remains disconnected.
- Line 10007, `- (void)activateTab:(TabId)identifier {`: Selecting an unloaded tab creates its runtime on demand; selecting an already loaded tab reuses it.
- Line 10560, `- (void)performClose:(TabId)identifier reason:`: Record the pending close reason before asking the engine to close; the completion path updates model/runtime ownership.
- Line 10619, `- (void)finishClose:(TabId)identifier {`: Remove page-owned runtime objects after close completion, retaining or deleting tab metadata according to the close reason.
- Line 7838, `- (void)requestAutoPiPForTab:(TabId)identifier origin:(int)origin {`: Only request automatic PiP for user-started playback; clear the pending state if WebKit declines or times out.
- Line 9754, `- (void)saveSession {`: Persist metadata for regular tabs and Spaces, excluding private tabs; running page contents are not serialized.
- Line 10709, `- (void)applicationDidFinishLaunching:(NSNotification *)notification {`: Connect application startup to window/session initialization; optional verification handling is build-gated.
- Line 13541, `int main(int argc, char* argv[]) {`: Create the native application/delegate and enter the AppKit event loop that drives browser interactions.

### `platform/macos/memory_monitor.cc`

Reads the current application process physical footprint using the Mach task API.

- Line 8, `MemorySample sample_memory(`: phys_footprint covers this process only; separate WebKit content/network processes require separate whole-browser attribution.

### `platform/macos/memory_monitor.h`

Declares native application footprint sampling and cancellable system memory-pressure observations.

- Line 12, `class MemoryMonitor {`: Destroying the monitor stops observation; the callback receives main-process footprint and pressure information.

### `platform/macos/memory_monitor.mm`

Implements native application footprint sampling and cancellable system memory-pressure observations.

- Line 22, `class MacMemoryMonitor final`: Use dispatch pressure events and a periodic sampler on the main queue; shutdown cancels both sources.

### `platform/macos/omnibox_overlay.h`

Declares the address/search field card, inline completion, and its centered page overlay.

- Line 16, `@protocol SlateOmniboxDelegate`: The field reports queries and submissions to the browser; navigation decisions live outside this view.

### `platform/macos/omnibox_overlay.mm`

Implements the address/search field card, inline completion, and its centered page overlay.

- Line 176, `- (NSString*)findEndingFor:`: Offer a suffix for a known domain matching the typed prefix; this is completion, not a network lookup.

### `platform/macos/passwords_panel.h`

Declares the native searchable password manager and authentication-gated password actions.

- Line 9, `@interface SlatePasswordsPanel :`: The panel borrows a C++ credential store and requests persistence through its supplied save callback.

### `platform/macos/passwords_panel.mm`

Implements the native searchable password manager and authentication-gated password actions.

- Line 175, `- (void)authenticate:`: Authenticate with macOS and reject late results when the panel/request state changed before completion.

### `platform/macos/pdf_overlay.h`

Declares PDF detection and a native HUD for page navigation, zoom, printing, and saving.

- Line 13, `@interface SlatePDFOverlay :`: The helper locates a PDFKit view inside a WebKit page and manages its native controls.

### `platform/macos/pdf_overlay.mm`

Implements PDF detection and a native HUD for page navigation, zoom, printing, and saving.

- Line 44, `+ (void)checkAndConfigureForWebView:`: Retry briefly because WebKit can create its PDF view asynchronously after navigation finishes.

### `platform/macos/plate_components.h`

Declares shared native panel colors, cards, rows, search fields, and action controls.

- Line 10, `@interface SlatePalette :`: Central color helpers keep native panels consistent with the current macOS appearance.

### `platform/macos/plate_components.mm`

Implements shared native panel colors, cards, rows, search fields, and action controls.

- Line 13, `+ (NSColor*)ground {`: Resolve the panel background dynamically for light or dark appearance instead of fixing a single color.

### `platform/macos/session_store.h`

Declares JSON persistence of tab metadata and groups for lazy session restoration.

- Line 8, `std::unique_ptr<SessionStore> make_session_store(`: The factory chooses a local session path; no engine/page snapshot is exposed by this API.

### `platform/macos/session_store.mm`

Implements JSON persistence of tab metadata and groups for lazy session restoration.

- Line 19, `class JsonSessionStore final`: Validate the saved schema before rebuilding logical tabs, restoring them without live page engines.

### `platform/macos/settings_panel.h`

Declares the native settings pages and their connection to browser preferences/actions.

- Line 9, `@interface SlateSettingsPanel :`: The weak delegate reference avoids the settings window retaining the browser owner.

### `platform/macos/settings_panel.mm`

Implements the native settings pages and their connection to browser preferences/actions.

- Line 259, `- (void)updateFromDelegate {`: Refresh visible settings from the browser state so reopening the panel reflects current preferences.

### `platform/macos/site_card_panel.h`

Declares the address-site card with connection/certificate information and page actions.

- Line 13, `@interface SlateSiteCardPanel :`: The panel receives URL, trust, secure-content, and zoom information from the selected page.

### `platform/macos/site_card_panel.mm`

Implements the address-site card with connection/certificate information and page actions.

- Line 346, `- (void)updateWithURL:`: Invalidate cached certificate presentation when the URL changes, then render the new page information.

### `platform/macos/spaces_manager.h`

Declares workspace metadata, parked tab records, local storage, and per-space website data stores.

- Line 10, `@interface SlateSpace :`: sharesSignIns chooses shared versus separate website storage; downloads stores an optional folder preference.

### `platform/macos/spaces_manager.mm`

Implements workspace metadata, parked tab records, local storage, and per-space website data stores.

- Line 225, `- (WKWebsiteDataStore*)dataStoreForSpace:`: Shared-sign-in Spaces use the default store; other Spaces request a persistent store keyed by their UUID.

### `platform/macos/specs_panel.h`

Declares a native panel presenting browser capability/resource comparison cards.

- Line 6, `@interface SlateSpecsPanel :`: The singleton exposes a window presentation entry point to the browser.

### `platform/macos/specs_panel.mm`

Implements a native panel presenting browser capability/resource comparison cards.

- Line 38, `@implementation SlateSpecCard`: Build a comparison card from supplied row values; the bars display those inputs rather than measuring browser processes.

### `platform/macos/split_drag_intent.h`

Distinguishes a deliberate split hover from an ordinary tab drag or tear-off.

- Line 12, `static constexpr double hold_seconds`: Require a 350 ms hold, allowing small hand movement, before arming a split.
- Line 23, `armed_ = armed_`: Once armed on this target the intent stays armed until a target change or reset.

### `platform/macos/split_workspace.h`

Stores active and parked split pairs, divider ratios, and pane-selection rules.

This is layout state over existing tab IDs; it does not own or create page views.

- Line 87, `void select(TabId id) {`: Bring the selected parked pair forward while preserving the outgoing pair and its divider position.
- Line 141, `double clamped_ratio(`: Keep both panes usable by clamping the divider according to the available window width.

## scripts

### `scripts/benchmark_tabs.py`

Runs isolated Slate/Chrome tab workloads and attributes whole-browser memory samples.

- Line 83, `def owned_pids(`: Identify the browser process group and helpers; missing helpers invalidate the measurement rather than silently understating memory.

### `scripts/build.sh`

Configures a Release build, builds Slate, and runs the configured tests.

- Line 6, `set -euo pipefail`: Stop on failed commands or unset variables so a broken build cannot be reported as successful.

### `scripts/codesign.sh`

Stages and signs an app bundle with a development identity or an ad-hoc fallback.

- Line 18, `IDENTITY="${SLATE_CODESIGN_IDENTITY:-}"`: Use an explicitly configured identity or look for a local development identity; later fallback uses an ad-hoc signature. Actual signing mode determines which entitlements are attached.

### `scripts/package-shields.py`

Copies local filter lists and attribution into app resources, retaining supported EasyList network syntax.

- Line 23, `for fname in ["easylist-network.txt"`: Filter upstream list entries before packaging; keep bundled attribution alongside the rule files.

### `scripts/profile_memory.py`

Provides a compatibility command that invokes the current isolated tab benchmark.

- Line 13, `if __name__ == '__main__':`: Forward command-line execution to benchmark_tabs.main instead of maintaining a second measurement implementation.

### `scripts/slim.sh`

Removes older CEF SDK/build leftovers and reports local workspace/app sizes.

- Line 11, `rm -rf "$ROOT/third_party"`: This is an explicit cleanup operation for legacy third-party build content, not part of normal page-memory management.

### `scripts/test-core.sh`

Compiles and runs focused C++ tests in a disposable temporary directory.

- Line 8, `trap 'rm -rf`: Remove the scratch test binaries on exit; the source checkout remains the test input.

### `scripts/verify_drag_intent.py`

Exercises native drag routing, split holds, cancellation, and tear-off gestures.

- Line 22, `def verify(`: Run the verification app with isolated browser data and local fixtures; production verification commands must be enabled in its build.

### `scripts/verify_fullscreen_controls.py`

Checks native full-screen controls, hit targets, and exiting full screen.

- Line 21, `def verify(`: Use a temporary verification app/profile to exercise real full-screen transitions without changing the normal browsing session.

### `scripts/verify_interaction_feedback.py`

Checks per-pane zoom, zoom persistence, and transient download feedback.

- Line 20, `def verify(`: Serve loopback fixtures and drive verification commands against isolated application state.

### `scripts/verify_security.py`

Probes signed entitlements, script-bridge isolation, autofill, downloads, and selected process metrics.

- Line 62, `def find_slate_subprocesses(`: This legacy helper currently finds WebKit processes broadly; its results are not a validated Slate-only whole-browser benchmark.

### `scripts/verify_split_switch.py`

Checks loaded split/single-page switches, live-view identity, edited state, and PiP follow-up behavior.

- Line 24, `def verify(`: Exercise a verification build with disposable data and local pages so continuity assertions do not depend on personal browsing state.

### `scripts/verify_window_tabs.py`

Checks detached-window tabs, shortcuts, popup routing, and view-preserving tab transfers.

- Line 23, `def verify(`: The scripted moves verify that transferring a live tab retains its edited fields and JavaScript state.

## tests

### `tests/audio_observer_tests.cjs`

Checks that the older audio-rewrite observer handles relevant mutations without repeated full-page scans.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 29, `vm.runInNewContext(script, {document, window: {}, URL,`: The harness executes extracted JavaScript with mock browser objects; these assertions are component checks, not proof of live-site compatibility.
- Line 40, `assert.equal(inserted.loads, 1);`: One newly inserted audio source should be prepared once, without repeatedly reloading it.

### `tests/browser_importer_tests.mm`

Checks bookmark JSON and password CSV import with synthetic records.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 11, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 57, `assert(imported == 3);`: The synthetic bookmark tree must produce exactly three imported sites.

### `tests/core_tests.cc`

Checks resource-policy priority, pressure/idle transitions, and the absence of policy side effects.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 12, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 33, `check(tabs[2].state==Lifecycle::Warm);`: Evaluating a policy must leave the original tab unchanged; callers decide whether to apply recommendations.

### `tests/credential_persistence_tests.mm`

Checks profile-specific Keychain persistence and failure behavior using replacement Keychain functions.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 34, `int main() { @autoreleasepool {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 44, `assert(![[NSFileManager defaultManager] fileExistsAtPath:path]);`: Saving to the mock Keychain must not also create a password file on disk.

### `tests/credential_store_tests.cc`

Checks exact-origin password matching, updates, removal, and search.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 10, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 35, `assert(store.find_for_origin("http://github.com").empty());`: An HTTP page must not receive a credential saved for the HTTPS origin.

### `tests/download_manager_tests.mm`

Checks download publication, filename collisions, unsafe URLs, and quarantine with local fixtures.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 22, `int main() { @autoreleasepool {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 30, `assert([manager startDownloadFromURL:[NSURL URLWithString:@"file:///etc/passwd"]`: A download entry point must reject local-file URLs rather than expose local files through the network-download path.

### `tests/favicon_loader_tests.mm`

Checks icon size/request/cache limits, cancellation, private-cache bypass, and loader teardown.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 44, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 102, `assert(starts==before+4 && peak<=4);`: Even a burst of requests must respect the four-active-request budget.

### `tests/fixtures/README.md`

Explains local verification fixtures and the provenance/license of media samples.

Read architecture and validation claims alongside the current implementation. RESOURCE_SAFETY.md describes the current automatic-unloading boundary; some older architecture/fixture text retains earlier engine assumptions.

### `tests/fixtures/codecs.html`

Provides local audio/video samples and capability diagnostics for codec testing.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/dynamic.html`

Provides a minimal scripted page for page-state/protection checks.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/flower.mp4`

Local H.264/AAC sample for video/media tests; see fixture attribution.

Binary media bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `tests/fixtures/flower.webm`

Local WebM sample for media/MSE tests; see fixture attribution.

Binary media bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `tests/fixtures/form.html`

Provides an editable field for unsaved-form protection checks.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/frame.html`

Provides a nested static page for iframe/protection checks.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/hls.html`

Records native HLS and related capability responses; it does not implement an HLS player.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/index.html`

Provides editable state, a before-unload handler, and navigation for lifecycle testing.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/media.html`

Provides a paused audio element for media-presence protection checks.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/mse.html`

Probes Media Source Extensions support and local WebM append/playback.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/pip_test.html`

Provides a local video and controls for picture-in-picture verification.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/security_autofill_page.html`

Provides a synthetic login form and observations for autofill security testing.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/security_bridge_iframe.html`

Checks script-handler/credential exposure from an embedded page.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/security_bridge_top.html`

Checks page-world bridge exposure and collects iframe observations.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/shields.html`

Mixes ad/tracker-shaped requests with legitimate content/media for blocking checks.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/static.html`

Provides a simple reading page without scripts, forms, frames, or media.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/fixtures/tone.wav`

Local PCM WAV tone used by audio/media fixtures.

Binary media bytes are preserved; notes live in CODEBASE_GUIDE.md.

### `tests/fixtures/upload_test.html`

Provides a file input and status display for native upload-dialog testing.

These are test inputs. Labels or earlier engine references in a fixture are not guarantees about current production support.

### `tests/floating_video_tests.cc`

Checks the embedded floating-video helpers and known-player URL recognition.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 11, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 17, `assert(slate::KnownPlayers::knows("https://www.youtube.com/`: Known-player matching recognizes the host/path pattern; it does not test actual video playback.

### `tests/image_download_menu_tests.js`

Checks trusted image right-click routing and rejection of synthetic/unsafe requests.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 31, `vm.runInNewContext(script, context);`: The harness executes extracted JavaScript with mock browser objects; these assertions are component checks, not proof of live-site compatibility.
- Line 51, `assert.deepEqual(rightClick([image], false)`: A synthetic right-click must leave the native image-download handler untouched.

### `tests/library_tests.cc`

Checks bookmark deduplication/validation and logical tab-group operations.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 12, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 18, `check(list.add("https://example.com/a","Alpha renamed")==a);`: Adding the same URL updates its title while retaining the original bookmark ID.

### `tests/media_monitor_tests.js`

Checks user-intent PiP decisions, ad-player transitions, page-cache refresh, and bounded mutation work.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 15, `function fixture({ad = false, hidden = false} = {}) {`: The harness executes extracted JavaScript with mock browser objects; these assertions are component checks, not proof of live-site compatibility.
- Line 73, `assert.equal(f.pipCalls(), 0, 'autoplay must not enter PiP');`: Playback without a trusted user gesture must not trigger automatic picture-in-picture.

### `tests/memory_monitor_tests.mm`

Checks that native memory callbacks arrive and stop after monitor destruction.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 10, `int main() { @autoreleasepool {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 21, `monitor.reset(); const int before=callbacks;`: Destroy the monitor, then verify that queued work cannot call the released observer.

### `tests/navigation_tests.cc`

Checks address/search classification, URL construction, and blocked schemes.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 11, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 18, `check(host.kind==InputKind::Url`: A bare public hostname gets an HTTPS destination rather than being sent as a search query.

### `tests/page_theme_tests.js`

Checks that hidden-page theme observers and timers stop doing work.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 13, `function advance(ms) {`: The harness executes extracted JavaScript with mock browser objects; these assertions are component checks, not proof of live-site compatibility.
- Line 40, `assert.equal(reads,before,'hidden tabs perform no theme layout/color reads');`: After hiding the page, simulated mutations/time must cause no additional layout or color reads.

### `tests/pip_state_tests.cc`

Checks that frame/ad changes cannot contradict authoritative native PiP state.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 8, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 18, `state.native(true);`: Native presentation takes priority even if DOM frame records disappear or change during an ad break.

### `tests/platform_audio_tests.mm`

Checks a generated PCM-to-AAC-to-WAV round trip using native audio tools and the decoder.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 30, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 49, `if(!slate::DecodeAudioFileToWav(`: Decode the generated AAC sample and subsequently verify a valid WAV container is produced.

### `tests/protection_tests.cc`

Checks stale/unknown observations, media/editing blockers, and protection state after navigation or restore.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 12, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 27, `check(target({})==Lifecycle::Protected);`: Unknown system pressure is a protection condition, not permission to destroy a page.

### `tests/security_tests.mm`

Checks unsafe navigation, exact-origin credentials, filter exceptions, and download security helpers.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 240, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 19, `static void TestAddressBarSecurity() {`: Keep unsafe schemes out of address-bar navigation even when capitalization or payload syntax varies.

### `tests/session_store_tests.mm`

Checks metadata round trips, lazy restore, private-tab exclusion, and corrupt-file preservation.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 13, `int main() { @autoreleasepool {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 28, `check(saved[2].selected && saved[2].state==slate::Lifecycle::Discarded);`: Restore selection metadata while leaving the selected record unloaded until the application activates it.

### `tests/shields_tests.cc`

Checks network rule matching, exceptions, site/global switches, counters, and bundled-list coverage.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 16, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 49, `assert(main.action==FilterAction::Allow);`: Network shields must allow the top-level document instead of blocking the page itself.

### `tests/split_drag_intent_tests.cc`

Checks hold timing, hand jitter, target changes, and reset behavior for split gestures.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 9, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 20, `assert(!move(2,160,110,0.8));`: Changing split sides restarts the hold; an already armed opposite side must not carry over.

### `tests/split_workspace_tests.cc`

Checks split membership, parked pairs, pane selection/replacement, swapping, and divider bounds.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 11, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 25, `workspace.select(30);`: Selecting an unrelated single tab hides the pair but must not replace its membership or selected side.

### `tests/stream_ad_skip_tests.js`

Checks streaming-ad helper behavior against mocked players, including restoration of sound and speed.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 15, `new vm.Script(match[1]);`: The harness executes extracted JavaScript with mock browser objects; these assertions are component checks, not proof of live-site compatibility.
- Line 61, `assert.equal(introClicks, 0,`: Ad skipping must not accidentally click a separate Skip Intro control.

### `tests/tab_model_tests.cc`

Checks logical tab selection, live state, zoom, Keep loaded, and asynchronous close bookkeeping.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 12, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 40, `check(model.tabs().size()==20 && !model.live(2)`: Discard completion removes the live page while retaining all logical tab records.

### `tests/tab_shape_tests.cc`

Checks selected-tab path bounds, symmetry, coordinate flipping, and toolbar joining.

Tests document the behavior they assert; they do not change production browser behavior.

- Line 12, `int main() {`: Run the synthetic scenarios below; failed assertions/checks terminate the executable so CTest can report a failure.
- Line 28, `assert(left==right && left==reflected);`: Hit regions must stay symmetric and agree after vertical coordinate flipping.

