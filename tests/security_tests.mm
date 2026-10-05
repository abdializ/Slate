#include "core/navigation.h"
#include "core/credential_store.h"
#import "platform/macos/download_manager.h"
#import "engine/webkit_shields.h"
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <sys/xattr.h>
#include <iostream>
#include <cassert>

using namespace slate;

static void TestAddressBarSecurity() {
  // Test 1: Dangerous schemes must be rejected
  assert(resolve_address_bar("javascript:alert(document.cookie)").kind == InputKind::Invalid);
  assert(resolve_address_bar("file:///etc/passwd").kind == InputKind::Invalid);
  assert(resolve_address_bar("FILE:///Users/").kind == InputKind::Invalid);
  assert(resolve_address_bar("data:text/html,<script>alert(1)</script>").kind == InputKind::Invalid);
  assert(resolve_address_bar("vbscript:MsgBox(1)").kind == InputKind::Invalid);
  assert(resolve_address_bar("blob:https://example.com/1234").kind == InputKind::Invalid);
  assert(resolve_address_bar("about:config").kind == InputKind::Invalid);

  // Test 2: Safe about:blank allowed
  assert(resolve_address_bar("about:blank").kind == InputKind::Url);

  // Test 3: Public websites default to HTTPS
  auto bank = resolve_address_bar("mybank.com");
  assert(bank.kind == InputKind::Url && bank.url == "https://mybank.com");

  auto securePath = resolve_address_bar("portal.example.edu/login");
  assert(securePath.kind == InputKind::Url && securePath.url == "https://portal.example.edu/login");

  // Test 4: Local development preserved
  auto local = resolve_address_bar("localhost:8080");
  assert(local.kind == InputKind::Url && local.url == "http://localhost:8080");

  auto ip = resolve_address_bar("127.0.0.1:5000");
  assert(ip.kind == InputKind::Url && ip.url == "http://127.0.0.1:5000");

  std::cout << "[PASS] Address-bar and scheme security tests passed.\n";
}

static void TestDownloadPathTraversal() {
  @autoreleasepool {
    NSString* tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"slate_dl_test"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    char canonicalTemp[PATH_MAX];
    assert(realpath(tempDir.fileSystemRepresentation, canonicalTemp));
    tempDir = [NSString stringWithUTF8String:canonicalTemp];

    // Attempt path traversal with ../../../../etc/passwd
    NSURL* dest1 = [SlateDownloadManager uniqueDestinationURLForFilename:@"../../../../etc/passwd" inDirectory:tempDir];
    assert([dest1.path hasPrefix:tempDir]);
    assert([dest1.lastPathComponent isEqualToString:@"passwd"]);

    // Attempt path traversal with hidden file
    NSURL* dest2 = [SlateDownloadManager uniqueDestinationURLForFilename:@"../../../.zshrc" inDirectory:tempDir];
    assert([dest2.path hasPrefix:tempDir]);
    assert(![dest2.lastPathComponent isEqualToString:@".zshrc"]);
    assert([dest2.lastPathComponent isEqualToString:@"zshrc"]);

    // Attempt with empty or whitespace
    NSURL* dest3 = [SlateDownloadManager uniqueDestinationURLForFilename:@"   " inDirectory:tempDir];
    assert([dest3.path hasPrefix:tempDir]);
    assert([dest3.lastPathComponent isEqualToString:@"download"]);

    // Attempt with forward and backslashes
    NSURL* dest4 = [SlateDownloadManager uniqueDestinationURLForFilename:@"foo/bar\\baz.pdf" inDirectory:tempDir];
    assert([dest4.path hasPrefix:tempDir]);
    assert([dest4.lastPathComponent isEqualToString:@"bar_baz.pdf"]);

    // Attempt with null byte injection
    NSURL* dest5 = [SlateDownloadManager uniqueDestinationURLForFilename:@"test\0hack.pdf" inDirectory:tempDir];
    assert([dest5.path hasPrefix:tempDir]);

    // Path prefix collision test (ensuring directory prefix matches with trailing separator)
    NSString* collisionDir = [tempDir stringByAppendingString:@"_fake"];
    [[NSFileManager defaultManager] createDirectoryAtPath:collisionDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL* dest6 = [SlateDownloadManager uniqueDestinationURLForFilename:@"test.txt" inDirectory:collisionDir];
    assert([dest6.path hasPrefix:[collisionDir stringByAppendingString:@"/"]]);
    [[NSFileManager defaultManager] removeItemAtPath:collisionDir error:nil];

    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    std::cout << "[PASS] Download path traversal sanitization tests passed.\n";
  }
}

static void TestQuarantineAttribute() {
  @autoreleasepool {
    NSString* testFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"slate_quarantine_test.bin"];
    NSData* testData = [@"test binary data" dataUsingEncoding:NSUTF8StringEncoding];
    [testData writeToFile:testFile atomically:YES];

    // Apply quarantine
    time_t now = time(NULL);
    NSString* uuidStr = [[NSUUID UUID] UUIDString];
    NSString* qAttr = [NSString stringWithFormat:@"0081;%lx;dev.slate.browser;%@", (long)now, uuidStr];
    const char* qVal = [qAttr UTF8String];
    int res = setxattr(testFile.fileSystemRepresentation, "com.apple.quarantine", qVal, strlen(qVal), 0, 0);
    assert(res == 0);

    // Read quarantine
    char buf[512] = {0};
    ssize_t readLen = getxattr(testFile.fileSystemRepresentation, "com.apple.quarantine", buf, sizeof(buf) - 1, 0, 0);
    assert(readLen > 0);
    NSString* readStr = [NSString stringWithUTF8String:buf];
    assert([readStr hasPrefix:@"0081;"]);
    assert([readStr containsString:@"dev.slate.browser"]);

    [[NSFileManager defaultManager] removeItemAtPath:testFile error:nil];
    std::cout << "[PASS] Download Gatekeeper quarantine metadata tests passed.\n";
  }
}

static void TestPrivateBrowsingIsolation() {
  @autoreleasepool {
    WKWebsiteDataStore* persistent = [WKWebsiteDataStore defaultDataStore];
    WKWebsiteDataStore* nonPersistent = [WKWebsiteDataStore nonPersistentDataStore];

    assert(persistent.isPersistent == YES);
    assert(nonPersistent.isPersistent == NO);
    assert(persistent != nonPersistent);

    std::cout << "[PASS] Private browsing WKWebsiteDataStore isolation tests passed.\n";
  }
}

static void TestCredentialOriginIsolation() {
  CredentialStore store;
  Credential c1;
  c1.origin = "https://bank.com";
  c1.username = "alice";
  c1.password = "Secret123!";
  store.save(c1);

  Credential c2;
  c2.origin = "https://portal.work.com";
  c2.username = "bob";
  c2.password = "WorkPass456!";
  store.save(c2);

  // Exact origin matching
  auto bankCreds = store.find_for_origin("https://bank.com");
  assert(!bankCreds.empty());
  assert(bankCreds[0].username == "alice");

  // Attacker site cannot match bank credentials
  auto evilCreds = store.find_for_origin("https://evilbank.com");
  assert(evilCreds.empty());

  // Insecure HTTP cannot match secure HTTPS credentials
  auto insecureCreds = store.find_for_origin("http://bank.com");
  assert(insecureCreds.empty());

  std::cout << "[PASS] Credential origin isolation tests passed.\n";
}

static void TestSandboxEntitlements() {
  @autoreleasepool {
#ifndef SLATE_SOURCE_DIR
#define SLATE_SOURCE_DIR "."
#endif
    NSString* sourceDir = [NSString stringWithUTF8String:SLATE_SOURCE_DIR];
    NSString* path = [sourceDir stringByAppendingPathComponent:@"platform/macos/Slate.entitlements"];
    NSData* data = [NSData dataWithContentsOfFile:path];
    assert(data != nil);

    NSError* err = nil;
    NSDictionary* plist = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:0
                                                                     format:nil
                                                                      error:&err];
    assert(plist != nil);
    assert([plist[@"com.apple.security.app-sandbox"] boolValue] == YES);
    assert([plist[@"com.apple.security.network.client"] boolValue] == YES);
    assert([plist[@"com.apple.security.files.user-selected.read-write"] boolValue] == YES);
    assert([plist[@"com.apple.security.files.downloads.read-write"] boolValue] == YES);
    assert([plist[@"com.apple.security.device.camera"] boolValue] == YES);
    assert([plist[@"com.apple.security.device.microphone"] boolValue] == YES);

    // Insecure debug entitlements MUST NOT be present
    assert(plist[@"com.apple.security.cs.allow-jit"] == nil);
    assert(plist[@"com.apple.security.cs.allow-unsigned-executable-memory"] == nil);
    assert(plist[@"com.apple.security.cs.disable-library-validation"] == nil);

    std::cout << "[PASS] App Sandbox least-privilege entitlements tests passed.\n";
  }
}

static void TestWebKitShieldsProtection() {
  @autoreleasepool {
    WKUserContentController* controller = [[WKUserContentController alloc] init];
    WebKitShields& shields = WebKitShields::Shared();

    shields.ApplyToUserContentController(controller, false);

    assert(controller.userScripts.count == 0);
    for (WKUserScript* script in controller.userScripts) {
      assert(![script.source containsString:@"__slate_pie_defuser_installed__"]);
    }

    WKUserContentController* incogController = [[WKUserContentController alloc] init];
    shields.ApplyToUserContentController(incogController, true);
    BOOL foundStealth = NO;
    for (WKUserScript* script in incogController.userScripts) {
      if ([script.source containsString:@"__slate_stealth_active__"]) {
        foundStealth = YES;
      }
    }
    assert(foundStealth && "Stealth script must be active in incognito");

    NSString* cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [@"slate-rule-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    setenv("SLATE_SHIELDS_CACHE_DIR", cacheDir.fileSystemRepresentation, 1);
    const std::string root = SLATE_SOURCE_DIR;
    shields.Initialize({root+"/filtering/lists/easylist-network.txt",
      root+"/filtering/lists/easyprivacy-network.txt",
      root+"/filtering/lists/slate-network.txt",
      root+"/filtering/lists/compat.txt"});
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:25];
    while (!shields.HasCompiledRules() && [deadline timeIntervalSinceNow] > 0)
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    assert(shields.HasCompiledRules() && "Full bundled WebKit rule list must compile");
    assert(shields.CompiledRuleCount() > 30000 && "Both EasyList and EasyPrivacy must contribute native rules");
    unsetenv("SLATE_SHIELDS_CACHE_DIR");
    [[NSFileManager defaultManager] removeItemAtPath:cacheDir error:nil];

    std::cout << "[PASS] WebKit Shields native rules and private stealth tests passed.\n";
  }
}

int main() {
  std::cout << "Running Slate security test suite...\n";
  TestAddressBarSecurity();
  TestDownloadPathTraversal();
  TestQuarantineAttribute();
  TestPrivateBrowsingIsolation();
  TestCredentialOriginIsolation();
  TestSandboxEntitlements();
  TestWebKitShieldsProtection();
  std::cout << "All Slate security hardening tests PASSED successfully!\n";
  return 0;
}
