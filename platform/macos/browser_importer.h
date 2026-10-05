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

class BrowserImporter {
 public:
  static bool HasDiaInstalled();
  static bool HasChromeInstalled();
  static bool HasSafariInstalled();

  static std::string GetDiaProfilePath();
  static std::string GetChromeProfilePath();
  static std::string GetSafariProfilePath();

  // Import Bookmarks from a Chromium Bookmarks JSON file (Dia, Chrome, Brave, Arc)
  static size_t ImportChromiumBookmarks(const std::string& bookmarks_json_path, BookmarkList& bookmark_list);

  // Import History from a Chromium SQLite History database (using ?immutable=1)
  static std::vector<HistoryItem> ImportChromiumHistory(const std::string& history_db_path, size_t max_items = 10000);

  // Import Passwords from CSV (format: url,username,password or name,url,username,password)
  static size_t ImportPasswordsCsv(const std::string& csv_path, CredentialStore& store);

  // One-shot import for Dia
  static ImportSummary ImportFromDia(bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history);

  // One-shot import for Chrome
  static ImportSummary ImportFromChrome(bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history);
};

} // namespace slate
