import AppKit
import Foundation
import Security
import Darwin

enum Store {
    static var testing: Bool {
        #if SLATE_PASSWORD_TESTS || SLATE_ENABLE_VERIFY
        return true
        #else
        return false
        #endif
    }
}

enum Preferences {
    static let entitledToPasskeys: Bool = {
        var code: SecCode?
        var info: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return false }
        return entitlements["com.apple.developer.web-browser.public-key-credential"] as? Bool == true
    }()
}

enum FormRelay {
    static var passkeysOffered: Bool {
        Preferences.entitledToPasskeys && (UserDefaults.standard.object(forKey: "passkeys") as? Bool ?? true)
    }
}

enum Registrable {
    static let publicSuffix: (@convention(c) (CFString) -> Bool)? = {
        guard let library = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_NOW),
              let symbol = dlsym(library, "_CFHostIsDomainTopLevel") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString) -> Bool).self)
    }()
    static func domain(_ host: String, isSuffix: ((String) -> Bool)? = nil) -> String {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return host }
        let test = isSuffix ?? publicSuffix.map { suffix in { suffix($0 as CFString) } }
        guard let test else { return host } // Fail closed when the system's suffix list isn't available.
        let labels = host.split(separator: ".").map(String.init)
        for count in 1...labels.count {
            let candidate = labels.suffix(count).joined(separator: ".")
            if !test(candidate) { return candidate }
        }
        return host
    }
    static func sameSite(_ a: String, _ b: String, isSuffix: ((String) -> Bool)? = nil) -> Bool {
        !a.isEmpty && !b.isEmpty && domain(a,isSuffix:isSuffix) == domain(b,isSuffix:isSuffix)
    }
}

enum Vault {
    static func registrable(_ host: String) -> String { Registrable.domain(host) }
    static func host(of value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: text.contains("://") ? text : "https://" + text)?.host?.lowercased() ?? ""
    }
}

/// The user's supplied offer rules; no helper is launched by this decision.
struct ApplePasswordsOffer {
    let store: UserDefaults
    static let offeredKey = "passwords.apple.offered"
    static let unansweredKey = "passwords.apple.offer.unanswered"
    static let neverKey = "passwords.apple.offer.never"
    static let patience = 2
    @MainActor static var benchAsks = false
    @MainActor static var benchHelper: Bool?
    static let helperHere: Bool = AppleHelper.access.canConnect
    struct Field: Equatable {
        var page: URL?
        var privateTab: Bool
        var frameHost: String? = nil
        var passwords = true
        var kept = 0
    }
    struct Settings: Equatable {
        var appleOn = false
        var fills = true
        var helper = true
        var testRun = false
        var benchAsks = false
    }
    func site(for field: Field, _ settings: Settings) -> String? {
        guard !settings.appleOn, settings.fills, settings.helper,
              !settings.testRun || settings.benchAsks,
              field.passwords, field.kept == 0,
              let host = ApplePasswords.offers(on: field.page, privateTab: field.privateTab)
        else { return nil }
        let site = Vault.registrable(host)
        if let frame = field.frameHost?.lowercased(), Vault.registrable(frame) != site { return nil }
        guard !store.bool(forKey: Self.neverKey),
              store.integer(forKey: Self.unansweredKey) < Self.patience,
              !offered.contains(site) else { return nil }
        return site
    }
    var offered: Set<String> { Set(store.stringArray(forKey: Self.offeredKey) ?? []) }
    func shown(on site: String) {
        var sites = offered
        guard sites.insert(site).inserted else { return }
        store.set(sites.sorted(), forKey: Self.offeredKey)
    }
    func unanswered() {
        store.set(store.integer(forKey: Self.unansweredKey) + 1, forKey: Self.unansweredKey)
    }
    func dismissed() { store.set(true, forKey: Self.neverKey) }
    var retired: Bool { store.bool(forKey: Self.neverKey) || store.integer(forKey: Self.unansweredKey) >= Self.patience }
    func forget() {
        for key in [Self.offeredKey, Self.unansweredKey, Self.neverKey] { store.removeObject(forKey:key) }
    }
}
