// Adapted from AddressCommands and Browser.placeOffers in AllOmniboxFeatures.swift.
// UI counterparts live in omnibox_overlay.mm; this file owns suggestion decisions.
import AppKit

@MainActor enum AddressCommand: String, CaseIterable {
    case settings, newTab, newPrivateTab, newSpace, bookmarks, history, downloads, passwords, toggleSidebar
    var aliases: [String] {
        switch self {
        case .settings: return ["settings", "preferences"]
        case .newTab: return ["new tab"]
        case .newPrivateTab: return ["new private tab", "private tab"]
        case .newSpace: return ["new space"]
        case .bookmarks: return ["bookmarks"]
        case .history: return ["history"]
        case .downloads: return ["downloads"]
        case .passwords: return ["passwords"]
        case .toggleSidebar: return ["toggle sidebar", "sidebar"]
        }
    }
    static func matching(_ typed: String) -> AddressCommand? {
        guard Store.settings.bool(forKey: "search.commands") else { return nil }
        let word = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.aliases.contains(word) }
    }
}

struct OmniboxVisit: Codable {
    var url: String
    var title: String
    var visits: Int
    var touched: TimeInterval
}
@MainActor enum OmniboxHistory {
    static var loaded: [String: [OmniboxVisit]] = [:]
    static var pending: [String: DispatchWorkItem] = [:]
    static func file(_ profile: String) -> URL { Store.file("omnibox-history-" + SlateSearchServices.profile(profile) + ".json") }
    static func all(_ profile: String) -> [OmniboxVisit] {
        if let value = loaded[profile] { return value }
        let values = (try? Data(contentsOf: file(profile))).flatMap { try? JSONDecoder().decode([OmniboxVisit].self, from: $0) } ?? []
        let valid = Array(values.filter { safeURL($0.url) != nil }.prefix(2000))
        loaded[profile] = valid
        return valid
    }
    static func safeURL(_ raw: String) -> URL? {
        guard var parts = URLComponents(string: raw), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false else { return nil }
        parts.user = nil; parts.password = nil
        return parts.url
    }
    static func record(_ raw: String, title: String, profile: String, privateTab: Bool) {
        guard !privateTab, raw.count <= 8192, let url = safeURL(raw) else { return }
        var values = all(profile)
        let identity = OmniboxRules.identity(url)
        let old = values.first { URL(string: $0.url).map(OmniboxRules.identity) == identity }
        values.removeAll { URL(string: $0.url).map(OmniboxRules.identity) == identity }
        values.insert(OmniboxVisit(url: url.absoluteString, title: title, visits: min(1_000_000, (old?.visits ?? 0)+1), touched: Date.timeIntervalSinceReferenceDate), at: 0)
        loaded[profile] = Array(values.prefix(2000))
        pending[profile]?.cancel()
        let snapshot = loaded[profile]!
        let destination = file(profile)
        let task = DispatchWorkItem { if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: destination, options: .atomic) } }
        pending[profile] = task
        // The short disk write is coalesced; all suggestion reads use memory.
        DispatchQueue.main.asyncAfter(deadline: .now()+0.25, execute: task)
    }
    static func clear(_ profile: String) {
        pending[profile]?.cancel(); pending[profile] = nil; loaded[profile] = []
        try? FileManager.default.removeItem(at: file(profile))
        SlateSearchServices.shared.forgetSites(profile: profile)
    }
}

@MainActor enum OmniboxRules {
    static func identity(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.user = nil; parts.password = nil
        parts.host = parts.host?.lowercased()
        if parts.path == "/" { parts.path = "" }
        return parts.string ?? url.absoluteString
    }
    static func walk(_ index: Int, count: Int, step: Int) -> Int {
        guard count > 0 else { return -1 }
        if index < 0 { return step > 0 ? 0 : count-1 }
        let next = index+step
        return (0..<count).contains(next) ? next : -1
    }
    static func offer(_ visit: OmniboxVisit, kind: String) -> [String: String]? {
        guard let url = OmniboxHistory.safeURL(visit.url) else { return nil }
        return ["key": Address.editable(url), "title": visit.title, "url": url.absoluteString, "kind": kind]
    }
    static func score(_ item: [String: String], query: String) -> Double? {
        let key = Address.withoutWWW(item["key"] ?? "").lowercased()
        let title = (item["title"] ?? "").lowercased()
        let host = URL(string: item["url"] ?? "")?.host?.lowercased() ?? ""
        if key.hasPrefix(query) { return 6 }
        if host.split(separator: ".").dropFirst().joined(separator: ".").hasPrefix(query) { return 3 }
        if query.count >= 2, host.contains(query) { return 2 }
        if query.count >= 2, title.contains(query) { return 1 }
        if query.count >= 3, key.contains(query) { return 0.5 }
        return nil
    }
    static func completion(_ typed: String, offers: [[String: String]]) -> String? {
        guard !typed.isEmpty, !typed.contains(where: \.isWhitespace), !offers.contains(where: { $0["kind"] == "command" }) else { return nil }
        let places = offers.filter { ["visited", "seed"].contains($0["kind"] ?? "") } + offers.filter { $0["kind"] == "bookmark" }
        if typed.count == 1, places.first?["kind"] != "visited" { return nil }
        for item in typed.count == 1 ? Array(places.prefix(1)) : places {
            guard let raw = item["url"], let url = URL(string: raw), let key = item["key"] else { continue }
            var candidates = [(key, identity(url))]
            if key.lowercased().hasPrefix("www."), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = parts.host, host.lowercased().hasPrefix("www.") {
                parts.host = String(host.dropFirst(4))
                if let bare = parts.url { candidates.append((String(key.dropFirst(4)), identity(bare))) }
            }
            for (candidate, target) in candidates {
                guard candidate.count >= typed.count, String(candidate.prefix(typed.count)).caseInsensitiveCompare(typed) == .orderedSame else { continue }
                if typed.count == 1, candidate.contains("/") || candidate.contains("?") || candidate.contains("#") { continue }
                let suffix = String(candidate.dropFirst(typed.count))
                guard !suffix.isEmpty, let back = Address.url(from: typed + suffix), identity(back) == target else { continue }
                return suffix
            }
        }
        return nil
    }
}

@MainActor @objc public final class SlateOmniboxServices: NSObject {
    @objc public static func offers(for typed: String, bookmarks: [[String: String]], imported: [[String: String]], profile: String, privateTab: Bool) -> [[String: String]] {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        func ranked(_ source: [[String: String]]) -> [[String: String]] {
            source.enumerated().compactMap { index, row -> (Int, Double, [String: String])? in
                OmniboxRules.score(row, query: query).map { (index, $0, row) }
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.map { $0.2 }
        }
        let kept = ranked(bookmarks.compactMap { record -> [String: String]? in
            guard let raw = record["url"], let url = OmniboxHistory.safeURL(raw) else { return nil }
            return ["url": url.absoluteString, "key": Address.editable(url), "title": record["title"] ?? "", "kind": "bookmark"]
        })
        var visited: [[String: String]] = []
        if !privateTab {
            let now = Date.timeIntervalSinceReferenceDate
            let visits = OmniboxHistory.all(profile).sorted {
                func weight(_ visit: OmniboxVisit) -> Double { log(Double(visit.visits)+1) + 5 / (1+max(0,now-visit.touched)/86400) }
                return weight($0) > weight($1)
            }
            visited += visits.compactMap { OmniboxRules.offer($0, kind: "visited") }
            visited += imported.compactMap { record in
                guard let url = record["url"] else { return nil }
                return OmniboxRules.offer(OmniboxVisit(url: url, title: record["title"] ?? "", visits: 0, touched: 0), kind: "visited")
            }
        }
        visited += SiteSearch.builtIn.filter { !$0.host.contains("/") }.compactMap { site in
            guard let url = URL(string: "https://" + site.host) else { return nil }
            return ["url": url.absoluteString, "key": Address.editable(url), "title": "", "kind": "seed"]
        }
        visited = ranked(visited)
        var list: [[String: String]] = [], seen: Set<String> = []
        func identity(_ row: [String: String]) -> String { URL(string: row["url"] ?? "").map(OmniboxRules.identity) ?? "" }
        func add(_ row: [String: String]) { if list.count < 3, seen.insert(identity(row)).inserted { list.append(row) } }
        let front = visited.first.map(identity)
        for item in kept {
            if list.count == 2, let front, !seen.contains(front), identity(item) != front { break }
            add(item)
        }
        visited.forEach(add)
        let resolved = SlateSearchServices.resolve(typed, committed: false, siteTemplate: nil)
        if resolved["kind"] == "search", let url = resolved["url"] {
            let name = Keyword.match(typed, in: SlateSearchServices.keywords)?.0.name ?? SlateSearchServices.engineName
            list.append(["key": typed, "title": name, "url": url, "kind": "search"])
        }
        if let command = AddressCommand.matching(typed) {
            list.insert(["key": command.aliases[0].localizedCapitalized, "title": "", "kind": "command", "command": command.rawValue], at: 0)
        }
        return list
    }
    @objc public static func command(for typed: String) -> String? { AddressCommand.matching(typed)?.rawValue }
    @objc public static func nextSelection(_ current: Int, count: Int, step: Int) -> Int { OmniboxRules.walk(current, count: count, step: step) }
    @objc public static func completion(for typed: String, offers: [[String: String]]) -> String? { OmniboxRules.completion(typed, offers: offers) }
    @objc public static func record(_ url: String, title: String, profile: String, privateTab: Bool) { OmniboxHistory.record(url, title: title, profile: profile, privateTab: privateTab) }
    @objc public static func history(profile: String) -> [[String: String]] { OmniboxHistory.all(profile).compactMap { OmniboxRules.offer($0, kind: "visited") } }
    @objc public static func clearHistory(profile: String) { OmniboxHistory.clear(profile) }
}
