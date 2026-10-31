// Adapted from the supplied AllSearchFeatures.swift reference.
import Foundation

enum Engine: String, CaseIterable, Identifiable {
    case google, duckduckgo, bing, ecosia, startpage, kagi, brave, qwant, custom

    static let standard = Engine.google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        case .kagi: return "Kagi"
        case .brave: return "Brave Search"
        case .qwant: return "Qwant"
        case .custom: return "Custom"
        }
    }

    func template(custom: String) -> String {
        switch self {
        case .google: return "https://www.google.com/search?q=%s"
        case .duckduckgo: return "https://duckduckgo.com/?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .ecosia: return "https://www.ecosia.org/search?q=%s"
        case .startpage: return "https://www.startpage.com/sp/search?query=%s"
        case .kagi: return "https://kagi.com/search?q=%s"
        case .brave: return "https://search.brave.com/search?q=%s"
        case .qwant: return "https://www.qwant.com/?q=%s"
        case .custom:
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return Engine.accepts(trimmed) ? trimmed : Engine.standard.template(custom: "")
        }
    }

    func name(custom: String) -> String {
        guard self == .custom else { return title }
        return Engine.bareHost(of: custom) ?? Engine.standard.title
    }

    static func accepts(_ template: String) -> Bool {
        host(of: template) != nil && KeywordTemplate.valid(template)
    }

    /// A template's host, with any leading "www." dropped — what a person
    /// would call the site if you asked them.
    static func bareHost(of template: String) -> String? {
        guard let host = host(of: template) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func url(for text: String, template: String) -> URL? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A fresh marker cannot collide with a literal part of the template.
        let mark = "SLATESEARCH" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard !words.isEmpty, accepts(template),
              let escaped = words.addingPercentEncoding(withAllowedCharacters: unreserved),
              let base = URL(string: template.replacingOccurrences(of: "%s", with: mark))?.absoluteString
        else { return nil }
        return URL(string: base.replacingOccurrences(of: mark, with: escaped))
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func host(of template: String) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("%s"),
              let parts = URLComponents(string: trimmed.replacingOccurrences(of: "%s", with: "a")),
              let other = URLComponents(string: trimmed.replacingOccurrences(of: "%s", with: "b")),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty, host == other.host
        else { return nil }
        return host.lowercased()
    }
}

private enum KeywordTemplate { static func valid(_ value: String) -> Bool {
 let parts = URLComponents(string: value.replacingOccurrences(of: "%s", with: "SEARCHWORDSGOHERE"))
 return value.components(separatedBy: "%s").count == 2 && parts?.host?.isEmpty == false && ["http", "https"].contains(parts?.scheme?.lowercased() ?? "") && parts?.user == nil && parts?.password == nil && [parts?.percentEncodedPath, parts?.percentEncodedQuery, parts?.percentEncodedFragment].contains { $0?.contains("SEARCHWORDSGOHERE") == true }
} }
