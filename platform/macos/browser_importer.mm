// File purpose: Implements bookmarks/history import from supported profiles and password import
// from CSV.

#import "platform/macos/browser_importer.h"
#import <Foundation/Foundation.h>
#include <pwd.h>
#include <sqlite3.h>
#include <sstream>
#include <unistd.h>

namespace slate {

namespace {

// Slate note: Walk nested bookmark JSON, accept HTTP(S) sites, and avoid adding URLs already present in
// the destination.
void ExtractBookmarksRecursive(id node, BookmarkList& list, size_t& count) {
  if (!node || ![node isKindOfClass:[NSDictionary class]]) return;

  NSString* type = node[@"type"];
  if ([type isEqualToString:@"url"]) {
    NSString* url = node[@"url"];
    NSString* name = node[@"name"] ?: @"";
    if (url && url.length > 0 && ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])) {
      std::string sUrl = url.UTF8String;
      std::string sName = name.UTF8String;
      if (!list.find_url(sUrl)) {
        list.add(sUrl, sName.empty() ? sUrl : sName);
        count++;
      }
    }
  }

  id children = node[@"children"];
  if (children && [children isKindOfClass:[NSArray class]]) {
    for (id child in children) {
      ExtractBookmarksRecursive(child, list, count);
    }
  }
}

} // namespace

bool BrowserImporter::HasDiaInstalled() {
  NSString* appPath = @"/Applications/Dia.app";
  NSString* dataPath = [NSString stringWithUTF8String:GetDiaProfilePath().c_str()];
  return [[NSFileManager defaultManager] fileExistsAtPath:appPath] ||
         [[NSFileManager defaultManager] fileExistsAtPath:dataPath];
}

bool BrowserImporter::HasChromeInstalled() {
  NSString* appPath = @"/Applications/Google Chrome.app";
  NSString* dataPath = [NSString stringWithUTF8String:GetChromeProfilePath().c_str()];
  return [[NSFileManager defaultManager] fileExistsAtPath:appPath] ||
         [[NSFileManager defaultManager] fileExistsAtPath:dataPath];
}

bool BrowserImporter::HasSafariInstalled() {
  return [[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Safari.app"];
}

std::string BrowserImporter::GetRealHomeDirectory() {
  struct passwd* pw = getpwuid(getuid());
  if (pw && pw->pw_dir && pw->pw_dir[0] != '\0') {
    return std::string(pw->pw_dir);
  }
  return NSHomeDirectory().UTF8String;
}

std::string BrowserImporter::GetDiaProfilePath() {
  NSString* home = [NSString stringWithUTF8String:GetRealHomeDirectory().c_str()];
  NSString* path = [home stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data/Default"];
  return path.UTF8String;
}

std::string BrowserImporter::GetChromeProfilePath() {
  NSString* home = [NSString stringWithUTF8String:GetRealHomeDirectory().c_str()];
  NSString* path = [home stringByAppendingPathComponent:@"Library/Application Support/Google/Chrome/Default"];
  return path.UTF8String;
}

std::string BrowserImporter::GetSafariProfilePath() {
  NSString* home = [NSString stringWithUTF8String:GetRealHomeDirectory().c_str()];
  NSString* path = [home stringByAppendingPathComponent:@"Library/Safari"];
  return path.UTF8String;
}

size_t BrowserImporter::ImportChromiumBookmarks(const std::string& bookmarks_json_path, BookmarkList& bookmark_list) {
  @autoreleasepool {
    NSString* path = [NSString stringWithUTF8String:bookmarks_json_path.c_str()];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return 0;

    NSData* data = [NSData dataWithContentsOfFile:path];
    if (!data) return 0;

    NSError* error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json || ![json isKindOfClass:[NSDictionary class]]) return 0;

    NSDictionary* roots = json[@"roots"];
    if (!roots || ![roots isKindOfClass:[NSDictionary class]]) return 0;

    size_t count = 0;
    ExtractBookmarksRecursive(roots[@"bookmark_bar"], bookmark_list, count);
    ExtractBookmarksRecursive(roots[@"other"], bookmark_list, count);
    ExtractBookmarksRecursive(roots[@"synced"], bookmark_list, count);

    return count;
  }
}

size_t BrowserImporter::ImportHtmlBookmarks(const std::string& html_path, BookmarkList& bookmark_list) {
  @autoreleasepool {
    NSString* path = [NSString stringWithUTF8String:html_path.c_str()];
    NSString* content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content.length) return 0;

    NSError* regexErr = nil;
    NSRegularExpression* regex = [NSRegularExpression
        regularExpressionWithPattern:@"<A\\b[^>]*HREF=[\"']([^\"']+)[\"'][^>]*>([^<]*)</A>"
                             options:NSRegularExpressionCaseInsensitive
                               error:&regexErr];
    if (!regex) return 0;

    size_t count = 0;
    NSArray<NSTextCheckingResult*>* matches = [regex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
    for (NSTextCheckingResult* match in matches) {
      if (match.numberOfRanges < 3) continue;
      NSString* url = [[content substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      NSString* title = [[content substringWithRange:[match rangeAtIndex:2]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (!url.length || (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"])) continue;
      std::string sUrl = url.UTF8String;
      std::string sTitle = title.length ? title.UTF8String : sUrl;
      if (!bookmark_list.find_url(sUrl)) {
        bookmark_list.add(sUrl, sTitle);
        count++;
      }
    }
    return count;
  }
}

std::vector<HistoryItem> BrowserImporter::ImportChromiumHistory(const std::string& history_db_path, size_t max_items) {
  std::vector<HistoryItem> items;
  @autoreleasepool {
    NSString* rawPath = [NSString stringWithUTF8String:history_db_path.c_str()];
    if (![[NSFileManager defaultManager] fileExistsAtPath:rawPath]) return items;

    // Copy to a temporary file inside our sandbox temp dir so we can safely read even if
    // the source browser is open/locking the DB or the path contains spaces.
    NSString* tempCopy = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"slate-import-history-%@.sqlite", NSUUID.UUID.UUIDString]];
    NSError* copyErr = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtPath:rawPath toPath:tempCopy error:&copyErr];
    NSString* openPath = copied ? tempCopy : rawPath;
    NSURL* fileURL = [NSURL fileURLWithPath:openPath];
    NSString* uriString = [NSString stringWithFormat:@"%@?immutable=1", fileURL.absoluteString];

    sqlite3* db = nullptr;
    int rc = sqlite3_open_v2(uriString.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nullptr);
    if (rc != SQLITE_OK || !db) {
      if (db) sqlite3_close(db);
      if (copied) [[NSFileManager defaultManager] removeItemAtPath:tempCopy error:nil];
      return items;
    }

    const char* sql = "SELECT url, title, visit_count, last_visit_time FROM urls "
                      "WHERE url NOT LIKE 'chrome%' AND url NOT LIKE 'about:%' "
                      "ORDER BY last_visit_time DESC LIMIT ?;";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
      sqlite3_bind_int64(stmt, 1, (sqlite3_int64)max_items);

      while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char* url = (const char*)sqlite3_column_text(stmt, 0);
        const char* title = (const char*)sqlite3_column_text(stmt, 1);
        int64_t visits = sqlite3_column_int64(stmt, 2);
        int64_t lastTime = sqlite3_column_int64(stmt, 3);

        if (url && strlen(url) > 0) {
          HistoryItem item;
          item.url = url;
          item.title = title ? title : "";
          item.visit_count = visits;
          item.last_visit_time = lastTime;
          items.push_back(std::move(item));
        }
      }
      sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    if (copied) [[NSFileManager defaultManager] removeItemAtPath:tempCopy error:nil];
  }
  return items;
}

size_t BrowserImporter::ImportPasswordsCsv(const std::string& csv_path, CredentialStore& store) {
  @autoreleasepool {
    NSString* path = [NSString stringWithUTF8String:csv_path.c_str()];
    NSString* content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content.length) return 0;
    if ([content hasPrefix:@"\uFEFF"]) content = [content substringFromIndex:1];

    NSArray* lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (lines.count < 2) return 0;

    NSString* header = lines[0];
    NSArray* headers = [header componentsSeparatedByString:@","];

    int urlCol = -1;
    int userCol = -1;
    int passCol = -1;

    for (int i = 0; i < (int)headers.count; ++i) {
      NSString* h = [[headers[i] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      h = [h stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
      if ([h isEqualToString:@"url"] || [h isEqualToString:@"origin"] || [h isEqualToString:@"login_url"] || [h isEqualToString:@"login_uri"] || [h isEqualToString:@"website"]) urlCol = i;
      else if ([h isEqualToString:@"username"] || [h isEqualToString:@"user"] || [h isEqualToString:@"login"] || [h isEqualToString:@"login_username"]) userCol = i;
      else if ([h isEqualToString:@"password"] || [h isEqualToString:@"pass"] || [h isEqualToString:@"login_password"]) passCol = i;
    }

    if (urlCol < 0 || passCol < 0) return 0;

    size_t imported = 0;
    for (NSUInteger i = 1; i < lines.count; ++i) {
      NSString* line = lines[i];
      if (!line.length) continue;

      // Handle simple CSV parsing (accounting for quotes)
      NSMutableArray* fields = [NSMutableArray array];
      NSScanner* scanner = [NSScanner scannerWithString:line];
      while (!scanner.isAtEnd) {
        NSString* field = nil;
        if ([scanner scanString:@"\"" intoString:NULL]) {
          [scanner scanUpToString:@"\"" intoString:&field];
          [scanner scanString:@"\"" intoString:NULL];
        } else {
          [scanner scanUpToString:@"," intoString:&field];
        }
        [fields addObject:field ?: @""];
        [scanner scanString:@"," intoString:NULL];
      }

      if ((int)fields.count > std::max(urlCol, std::max(userCol, passCol))) {
        NSString* uUrl = fields[urlCol];
        NSString* uUser = (userCol >= 0) ? fields[userCol] : @"";
        NSString* uPass = fields[passCol];

        if (uUrl.length && uPass.length) {
          Credential cred;
          cred.origin = uUrl.UTF8String;
          cred.username = uUser.UTF8String;
          cred.password = uPass.UTF8String;
          store.save(std::move(cred));
          imported++;
        }
      }
    }
    return imported;
  }
}

ImportSummary BrowserImporter::ImportChromiumProfile(const std::string& profile_dir, bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history) {
  ImportSummary summary;
  NSString* dir = [NSString stringWithUTF8String:profile_dir.c_str()];
  NSFileManager* fm = [NSFileManager defaultManager];
  NSString* bookmarksPath = [dir stringByAppendingPathComponent:@"Bookmarks"];
  NSString* historyPath = [dir stringByAppendingPathComponent:@"History"];
  if (![fm fileExistsAtPath:bookmarksPath] && ![fm fileExistsAtPath:historyPath]) {
    NSString* defaultSub = [dir stringByAppendingPathComponent:@"Default"];
    if ([fm fileExistsAtPath:[defaultSub stringByAppendingPathComponent:@"Bookmarks"]] ||
        [fm fileExistsAtPath:[defaultSub stringByAppendingPathComponent:@"History"]]) {
      dir = defaultSub;
      bookmarksPath = [dir stringByAppendingPathComponent:@"Bookmarks"];
      historyPath = [dir stringByAppendingPathComponent:@"History"];
    }
  }
  if (import_bookmarks) {
    summary.bookmarks_imported = ImportChromiumBookmarks(bookmarksPath.UTF8String, bookmarks);
  }
  if (import_history) {
    out_history = ImportChromiumHistory(historyPath.UTF8String, 10000);
    summary.history_imported = out_history.size();
  }
  return summary;
}

ImportSummary BrowserImporter::ImportFromDia(bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history) {
  return ImportChromiumProfile(GetDiaProfilePath(), import_bookmarks, import_history, bookmarks, out_history);
}

ImportSummary BrowserImporter::ImportFromChrome(bool import_bookmarks, bool import_history, BookmarkList& bookmarks, std::vector<HistoryItem>& out_history) {
  return ImportChromiumProfile(GetChromeProfilePath(), import_bookmarks, import_history, bookmarks, out_history);
}

} // namespace slate
