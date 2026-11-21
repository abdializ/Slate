// File purpose: Declares bookmarks/history import from supported profiles and password import from
// CSV.

#pragma once
#include "core/library.h"
#include "core/credential_store.h"
#include <string>
#include <vector>

namespace slate {

struct HistoryItem {
  std::string url;
  std::string title;
  int64_t visit_count = 0;
  int64_t last_visit_time = 0;
};

struct ImportSummary {
  size_t bookmarks_imported = 0;
  size_t history_imported = 0;
  size_t passwords_imported = 0;
  std::string error_message;
};

// Slate note: Static import entry points accept explicit source paths and return imported records or
// counts.
class BrowserImporter {
 public:
  static bool HasDiaInstalled();
  static bool HasChromeInstalled();
  static bool HasSafariInstalled();

  static std::string GetRealHomeDirectory();
  static std::string GetDiaProfilePath();
  static std::string GetChromeProfilePath();
  static std::string GetSafariProfilePath();

  // Import Bookmarks from a Chromium Bookmarks JSON file (Dia, Chrome, Brave, Arc, Edge)
  static size_t ImportChromiumBookmarks(const std::string& bookmarks_json_path, BookmarkList& bookmark_list);

  // Import Bookmarks from a standard Netscape HTML export (Safari, Chrome, Firefox, Arc, Brave)
  static size_t ImportHtmlBookmarks(const std::string& html_path, BookmarkList& bookmark_list);

  // Import History from a Chromium SQLite History database (via safe temp copy + ?immutable=1)
  static std::vector<HistoryItem> ImportChromiumHistory(const std::string& history_db_path, size_t max_items = 10000);

  // Import Passwords from CSV (Chrome, Safari, 1Password, Bitwarden, Brave, Edge, Arc)
  static size_t ImportPasswordsCsv(const std::string& csv_path, CredentialStore& store);

  // Import Bookmarks and/or History from any Chromium profile directory (e.g. Chrome/Dia/Arc/Brave/Edge Default)
  static ImportSummary ImportChromiumProfile(const std::string& profile_dir, bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history);

  // One-shot import for Dia
  static ImportSummary ImportFromDia(bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history);

  // One-shot import for Chrome
  static ImportSummary ImportFromChrome(bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history);
};

} // namespace slate
