import AppKit
import WebKit
import Darwin

// This module keeps its settings and learned sites separate from page content.
enum Store {
    static var settings = UserDefaults.standard
    static var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Slate")
    static var testing: Bool {
        #if SLATE_SEARCH_TESTS
        return true
        #else
        return false
        #endif
    }
    static func file(_ name: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}
enum Disk {
    static func write(_ url: URL, data: () -> Data?) { if let value = data() { try? value.write(to: url, options: .atomic) } }
}
enum Web { static let world = WKContentWorld.world(name: "SlateSearch") }

// Use the same system suffix boundary as Slate's password policy. If unavailable,
// require an exact host, rather than guessing across hosting providers.
enum Vault {
    static let suffix: (@convention(c) (CFString) -> Bool)? = {
        guard let lib = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_NOW),
              let symbol = dlsym(lib, "_CFHostIsDomainTopLevel") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString) -> Bool).self)
    }()
    static func registrable(_ raw: String) -> String {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let suffix, !host.isEmpty, !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return host }
        let labels = host.split(separator: ".")
        for size in 1...labels.count {
            let candidate = labels.suffix(size).joined(separator: ".")
            if !suffix(candidate as CFString) { return candidate }
        }
        return host
    }
}

@MainActor
@objc public final class SlateSearchServices: NSObject {
    @objc public static let shared = SlateSearchServices()
    private let suggester = EngineSuggester()
    private var revision = 0
    private var discovery: Set<String> = []
    static var engine: Engine { Engine(rawValue: Store.settings.string(forKey: "search.engine") ?? "") ?? .standard }
    static var custom: String { Store.settings.string(forKey: "search.custom") ?? "" }
    static var keywords: [Keyword] {
        get { Store.settings.data(forKey: "search.keywords").flatMap { try? JSONDecoder().decode([Keyword].self, from: $0) } ?? [] }
        set { Store.settings.set(try? JSONEncoder().encode(newValue), forKey: "search.keywords") }
    }
    @objc public static var engineName: String { engine.name(custom: custom) }
    @objc public static func configure(directory: String) { Store.directory = URL(fileURLWithPath: directory, isDirectory: true) }
    @objc public static func editable(_ text: String) -> String { URL(string: text).map(Address.editable) ?? text }
    static func profile(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "default" }

    @objc public static func resolve(_ typed: String, committed: Bool, siteTemplate: String?) -> [String: String] {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        func answer(_ url: URL?, _ kind: String) -> [String: String] {
            guard let url else { return ["kind": "invalid"] }
            return ["kind": kind, "url": (Address.reachable(url) ?? url).absoluteString]
        }
        guard !text.isEmpty else { return ["kind": "invalid"] }
        if let siteTemplate, Keyword.accepts(siteTemplate) { return answer(Engine.url(for: text, template: siteTemplate), "search") }
        if let (shortcut, words) = Keyword.match(text, in: keywords) { return answer(Engine.url(for: words, template: shortcut.template), "search") }
        if text.hasPrefix("/") || text.hasPrefix("~/") {
            return committed ? answer(Address.file(from: text), "url") : ["kind": "url", "url": text]
        }
        if let url = Address.url(from: text) {
            if url.isFileURL {
                guard committed else { return answer(url, "url") }
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return ["kind": "invalid"] }
            }
            if ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty != false { return ["kind": "invalid"] }
            return answer(url, "url")
        }
        // An explicit unsupported scheme is refused instead of becoming a search.
        if text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil { return ["kind": "invalid"] }
        return answer(Engine.url(for: text, template: engine.template(custom: custom)), "search")
    }

    @objc public func site(for typed: String, profile: String, privateTab: Bool) -> [String: String]? {
        guard Store.settings.object(forKey: "search.sites") as? Bool ?? true else { return nil }
        SiteSearch.profile = Self.profile(profile)
        let visits = Store.settings.dictionary(forKey: "search.visits." + SiteSearch.profile) as? [String: Int] ?? [:]
        guard let site = SiteSearch.match(typed, learnedToo: !privateTab, visits: { _ in visits }) else { return nil }
        return ["name": site.name, "host": site.host, "template": site.template]
    }
    @objc public func stop() { revision += 1; suggester.stop() }
    @objc public func suggest(_ typed: String, privateTab: Bool, siteActive: Bool, completion: @escaping ([String]) -> Void) {
        stop()
        let mine = revision
        guard Store.settings.bool(forKey: "search.suggestions"), !privateTab, !siteActive,
              Keyword.match(typed, in: Self.keywords) == nil, EngineSuggest.sendable(typed),
              let url = EngineSuggest.url(for: typed, engine: Self.engine, test: EngineSuggest.testEndpoint) else { return }
        suggester.ask(url, words: typed) { [weak self] words in
            guard self?.revision == mine, Store.settings.bool(forKey: "search.suggestions") else { return }
            completion(words)
        }
    }
    @objc public func visited(_ web: WKWebView, profile: String, privateTab: Bool) {
        guard !privateTab, web.window != nil, !web.isHidden, let page = web.url, page.scheme == "https", let host = page.host else { return }
        let key = Self.profile(profile)
        let historyKey = "search.visits." + key
        var visits = Store.settings.dictionary(forKey: historyKey) as? [String: Int] ?? [:]
        visits[host, default: 0] += 1
        if visits.count > 2000, let least = visits.min(by: { $0.value < $1.value })?.key { visits.removeValue(forKey: least) }
        Store.settings.set(visits, forKey: historyKey)
        guard Store.settings.object(forKey: "search.sites") as? Bool ?? true else { return }
        let discoveryKey = key + ":" + host
        guard discovery.insert(discoveryKey).inserted else { return }
        web.evaluateJavaScript(SiteSearch.lookup, in: nil, in: Web.world) { result in
            guard web.url == page, web.window != nil, !web.isHidden,
                  case .success(let value) = result, let address = value as? String,
                  let description = URL(string: address) else { return }
            SiteSearch.profile = key
            SiteSearch.learn(from: page, description: description)
        }
    }
    @objc public func forgetSites(profile: String) {
        SiteSearch.profile = Self.profile(profile)
        SiteSearch.forget()
        Store.settings.removeObject(forKey: "search.visits." + SiteSearch.profile)
        discovery = discovery.filter { !$0.hasPrefix(SiteSearch.profile + ":") }
    }
    @objc public static func settingsView() -> NSView { settingsView(profile: "default") }
    @objc public static func settingsView(profile: String) -> NSView {
        let view = SearchSettingsView(frame: .zero); view.profile = profile; return view
    }
}

@MainActor
@objc public final class SlatePageFinder: NSObject {
    private let finder = PageFind()
    private var generation: UInt64 = 0
    @objc public func update(_ web: WKWebView, query: String, matchCase: Bool, wholeWords: Bool, steps: Int, completion: @escaping ([String: Any]) -> Void) {
        generation += 1
        let mine = generation
        Task {
            let result = await finder.update(on: web, query: query, matchCase: matchCase, wholeWords: wholeWords, steps: steps, generation: mine)
            guard mine == generation, !result.stale else { return }
            completion(["count": result.count ?? -1, "index": result.index ?? 0, "more": result.more,
                        "found": result.found, "available": result.available, "wholeWordsAvailable": result.wholeWordsAvailable])
        }
    }
    @objc public func clear(_ web: WKWebView) {
        generation += 1
        let mine = generation
        Task { _ = await finder.clear(on: web, generation: mine) }
    }
}
