#import "platform/macos/browser_importer.h"
#import <Foundation/Foundation.h>
#include <cassert>
#include <iostream>

int main() {
  @autoreleasepool {
    using namespace slate;

    // 1. Test Chromium Bookmarks Import
    NSString* sampleJson = @R"JSON({
      "checksum": "test123",
      "roots": {
        "bookmark_bar": {
          "children": [
            {
              "name": "Outlook Mail",
              "type": "url",
              "url": "https://outlook.office.com"
            },
            {
              "name": "School Folder",
              "type": "folder",
              "children": [
                {
                  "name": "PVAMU eCourses",
                  "type": "url",
                  "url": "https://courses.example.test"
                }
              ]
            }
          ]
        },
        "other": {
          "children": [
            {
              "name": "GitHub",
              "type": "url",
              "url": "https://github.com"
            }
          ]
        }
      }
    })JSON";

    NSString* tmpFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_bookmarks.json"];
    [sampleJson writeToFile:tmpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

    BookmarkList bList;
    size_t imported = BrowserImporter::ImportChromiumBookmarks(tmpFile.UTF8String, bList);
    assert(imported == 3);
    assert(bList.items().size() == 3);
    assert(bList.find_url("https://outlook.office.com") != nullptr);
    assert(bList.find_url("https://courses.example.test") != nullptr);
    assert(bList.find_url("https://github.com") != nullptr);
    [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];

    // 2. Test Passwords CSV Import
    NSString* sampleCsv = @"url,username,password\n"
                          @"\"https://github.com/login\",\"alice\",\"passA\"\n"
                          @"\"https://twitch.tv\",\"bob\",\"passB\"\n";
    NSString* tmpCsv = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test_passwords.csv"];
    [sampleCsv writeToFile:tmpCsv atomically:YES encoding:NSUTF8StringEncoding error:nil];

    CredentialStore cStore;
    size_t passImported = BrowserImporter::ImportPasswordsCsv(tmpCsv.UTF8String, cStore);
    assert(passImported == 2);
    assert(cStore.items().size() == 2);
    assert(cStore.find_for_origin("github.com").size() == 1);
    assert(cStore.find_for_origin("github.com")[0].username == "alice");
    assert(cStore.find_for_origin("github.com")[0].password == "passA");
    [[NSFileManager defaultManager] removeItemAtPath:tmpCsv error:nil];

    std::cout << "All browser_importer tests passed!" << std::endl;
  }
  return 0;
}
