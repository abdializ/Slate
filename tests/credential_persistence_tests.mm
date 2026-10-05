#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "platform/macos/credential_persistence.h"
#include <cassert>
#include <stdexcept>
// CMake renames all three Keychain entry points for this target. No real
// Keychain items are read or written, even when tests run outside a sandbox.
static NSMutableDictionary* vault;
static OSStatus failure=errSecSuccess;
extern "C" OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef* result) {
 if(failure) return failure;
 NSString* key=((__bridge NSDictionary*)query)[(__bridge id)kSecAttrAccount];
 NSData* data=vault[key]; if(!data) return errSecItemNotFound;
 *result=CFBridgingRetain(data); return errSecSuccess;
}
extern "C" OSStatus SecItemUpdate(CFDictionaryRef query,CFDictionaryRef values) {
 if(failure) return failure;
 NSString* key=((__bridge NSDictionary*)query)[(__bridge id)kSecAttrAccount];
 if(!vault[key]) return errSecItemNotFound;
 vault[key]=((__bridge NSDictionary*)values)[(__bridge id)kSecValueData]; return errSecSuccess;
}
extern "C" OSStatus SecItemAdd(CFDictionaryRef query,CFTypeRef* result) {
 if(failure) return failure;
 NSDictionary* item=(__bridge NSDictionary*)query;
 assert([item[(__bridge id)kSecAttrAccessible] isEqual:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly]);
 vault[item[(__bridge id)kSecAttrAccount]]=item[(__bridge id)kSecValueData]; return errSecSuccess;
}
int main() { @autoreleasepool {
 vault=[NSMutableDictionary dictionary];
 NSString* path=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 const std::string filename=path.UTF8String;
 assert(slate::load_credentials(filename)->items().empty());
 slate::CredentialStore store; store.save({.origin="https://example.test",.username="test",.password="synthetic-test-value"});
 slate::save_credentials(filename,store);
 auto loaded=slate::load_credentials(filename);
 assert(loaded->items().size()==1 && loaded->items()[0].password=="synthetic-test-value");
 assert(![[NSFileManager defaultManager] fileExistsAtPath:path]);
 assert(slate::load_credentials(filename+"-other-profile")->items().empty());
 NSData* previous=[vault[path] copy]; failure=errSecAuthFailed;
 bool rejected=false; try { slate::load_credentials(filename); } catch(const std::exception&) { rejected=true; } assert(rejected);
 rejected=false; try { slate::save_credentials(filename,slate::CredentialStore{}); } catch(const std::exception&) { rejected=true; } assert(rejected);
 assert([previous isEqual:vault[path]]); failure=errSecSuccess;
 vault[path]=[@"{\"version\":99,\"credentials\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
 rejected=false; try { slate::load_credentials(filename); } catch(const std::exception&) { rejected=true; } assert(rejected);
 vault[path]=[@"bad data" dataUsingEncoding:NSUTF8StringEncoding];
 rejected=false; try { slate::load_credentials(filename); } catch(const std::exception&) { rejected=true; } assert(rejected);
 puts("credential persistence checks passed (mock Keychain)");
} }
