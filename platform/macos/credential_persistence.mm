#include "platform/macos/credential_persistence.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonRandom.h>
#include <vector>
#include <stdexcept>
#include <set>

namespace slate {

namespace {

NSString* const kSlateKeychainService = @"Slate Safe Storage";
NSString* const kSlateKeychainAccount = @"Slate Credential Master Key";

NSData* ReadLegacyMasterKey() {
  NSDictionary* query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: kSlateKeychainService,
    (__bridge id)kSecAttrAccount: kSlateKeychainAccount,
    (__bridge id)kSecReturnData: @YES,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
  };

  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
  if (status == errSecSuccess && result) {
    return (__bridge_transfer NSData*)result;
  }

  throw std::runtime_error("The legacy password encryption key is unavailable. The original file was preserved.");
}

NSDictionary* VaultIdentity(const std::string& path) {
 return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
          (__bridge id)kSecAttrService:@"Slate Password Vault",
          (__bridge id)kSecAttrAccount:[NSString stringWithUTF8String:path.c_str()]};
}

NSData* DecryptData(NSData* encryptedData, NSData* key) {
  if (!encryptedData || encryptedData.length <= kCCBlockSizeAES128 || !key || key.length < 32) return nil;

  NSData* iv = [encryptedData subdataWithRange:NSMakeRange(0, kCCBlockSizeAES128)];
  NSData* cipherText = [encryptedData subdataWithRange:NSMakeRange(kCCBlockSizeAES128, encryptedData.length - kCCBlockSizeAES128)];

  size_t bufferSize = cipherText.length + kCCBlockSizeAES128;
  NSMutableData* plainText = [NSMutableData dataWithLength:bufferSize];

  size_t numBytesDecrypted = 0;
  CCCryptorStatus cryptStatus = CCCrypt(
      kCCDecrypt,
      kCCAlgorithmAES,
      kCCOptionPKCS7Padding,
      key.bytes,
      kCCKeySizeAES256,
      iv.bytes,
      cipherText.bytes,
      cipherText.length,
      plainText.mutableBytes,
      plainText.length,
      &numBytesDecrypted);

  if (cryptStatus != kCCSuccess) return nil;

  plainText.length = numBytesDecrypted;
  return plainText;
}

} // namespace

std::unique_ptr<CredentialStore> load_credentials(const std::string& path) {
  @autoreleasepool {
    NSMutableDictionary* query=[VaultIdentity(path) mutableCopy];
    query[(__bridge id)kSecReturnData]=@YES;
    query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    CFTypeRef result=nullptr;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&result);
    NSData* jsonBytes=nil;
    NSError* parseError=nil;
    if(status==errSecSuccess && result) jsonBytes=CFBridgingRelease(result);
    else if(status!=errSecItemNotFound)
      throw std::runtime_error("macOS could not unlock Slate's password vault.");
    else {
      // Read the old file only for compatibility. Never replace it on a failed read.
      NSString* filePath=[NSString stringWithUTF8String:path.c_str()];
      if(![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return std::make_unique<CredentialStore>();
      NSData* fileBytes=[NSData dataWithContentsOfFile:filePath];
      if(!fileBytes.length) throw std::runtime_error("The saved password file could not be read.");
      id direct=[NSJSONSerialization JSONObjectWithData:fileBytes options:0 error:nil];
      jsonBytes=[direct isKindOfClass:NSDictionary.class] ? fileBytes : DecryptData(fileBytes,ReadLegacyMasterKey());
      if(!jsonBytes) throw std::runtime_error("The saved password file could not be unlocked.");
    }

    id root = [NSJSONSerialization JSONObjectWithData:jsonBytes options:0 error:&parseError];
    if (!root || ![root isKindOfClass:[NSDictionary class]]) {
      throw std::runtime_error("The saved password data is invalid; it was preserved.");
    }

    if(![root[@"version"] isKindOfClass:NSNumber.class] || [root[@"version"] integerValue]!=1)
      throw std::runtime_error("Unsupported password data version.");
    NSArray* list = root[@"credentials"];
    if (!list || ![list isKindOfClass:[NSArray class]]) {
      throw std::runtime_error("The saved password data is invalid; it was preserved.");
    }

    std::vector<Credential> items;
    std::set<std::string> ids;
    for (id item in list) {
      if (![item isKindOfClass:[NSDictionary class]]) throw std::runtime_error("Invalid password record.");
      Credential cred;
      cred.id = [item[@"id"] isKindOfClass:[NSString class]] ? [item[@"id"] UTF8String] : "";
      cred.origin = [item[@"origin"] isKindOfClass:[NSString class]] ? [item[@"origin"] UTF8String] : "";
      cred.username = [item[@"username"] isKindOfClass:[NSString class]] ? [item[@"username"] UTF8String] : "";
      cred.password = [item[@"password"] isKindOfClass:[NSString class]] ? [item[@"password"] UTF8String] : "";
      cred.created_at = [item[@"created_at"] respondsToSelector:@selector(longLongValue)] ? [item[@"created_at"] longLongValue] : 0;
      cred.last_used_at = [item[@"last_used_at"] respondsToSelector:@selector(longLongValue)] ? [item[@"last_used_at"] longLongValue] : 0;

      if(cred.id.empty() || cred.origin.empty() || !ids.insert(cred.id).second ||
         ![item[@"username"] isKindOfClass:NSString.class] || ![item[@"password"] isKindOfClass:NSString.class])
        throw std::runtime_error("Invalid password record; original data preserved.");
      items.push_back(std::move(cred));
    }

    return std::make_unique<CredentialStore>(std::move(items));
  }
}

void save_credentials(const std::string& path, const CredentialStore& store) {
  @autoreleasepool {
    NSMutableArray* credArray = [NSMutableArray array];
    for (const auto& item : store.items()) {
      [credArray addObject:@{
        @"id": [NSString stringWithUTF8String:item.id.c_str()],
        @"origin": [NSString stringWithUTF8String:item.origin.c_str()],
        @"username": [NSString stringWithUTF8String:item.username.c_str()],
        @"password": [NSString stringWithUTF8String:item.password.c_str()],
        @"created_at": @(item.created_at),
        @"last_used_at": @(item.last_used_at)
      }];
    }

    NSDictionary* dict = @{
      @"version": @1,
      @"credentials": credArray
    };

    NSError* jsonError = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!jsonData || jsonError) throw std::runtime_error("The password data could not be encoded.");

    NSDictionary* identity=VaultIdentity(path);
    NSDictionary* values=@{(__bridge id)kSecValueData:jsonData};
    OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)identity,(__bridge CFDictionaryRef)values);
    if(status==errSecItemNotFound) {
      NSMutableDictionary* item=[identity mutableCopy];
      [item addEntriesFromDictionary:values];
      item[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
      status=SecItemAdd((__bridge CFDictionaryRef)item,nullptr);
    }
    if(status!=errSecSuccess) throw std::runtime_error("macOS could not save Slate's password vault.");
  }
}

} // namespace slate
