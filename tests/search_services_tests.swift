import AppKit
import WebKit

@main struct SearchTests {
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    @MainActor static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "slate.search.tests." + UUID().uuidString
        Store.settings = UserDefaults(suiteName: suite)!
        Store.directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            Store.settings.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: Store.directory)
        }
        for (input, expected) in [
            ("example.com", "https://example.com"), ("localhost:8090/foo", "http://localhost:8090/foo"),
            ("192.168.2.3", "http://192.168.2.3"), ("172.31.2.3", "http://172.31.2.3"),
            ("172.32.2.3", "https://172.32.2.3"), ("printer.local", "http://printer.local"),
            ("[::1]:4000", "http://[::1]:4000"), ("LOCALHOST:3000", "http://LOCALHOST:3000"),
            ("0.0.0.0:8000/x?q=y#z", "http://localhost:8000/x?q=y#z")
        ] { check(SlateSearchServices.resolve(input, committed: true, siteTemplate: nil)["url"] == expected, input) }
        for text in ["hello", "a@b.com", "v1.2.3", "-bad.com", "bad..com"] { check(Address.url(from: text) == nil, "not a host: " + text) }
        for scheme in ["javascript:alert(1)", "mailto:a@b.com", "custom://open", "vbscript:hi"] {
            check(SlateSearchServices.resolve(scheme, committed: true, siteTemplate: nil)["kind"] == "invalid", "refuse " + scheme)
        }
        for page in ["https://example.com/", "http://example.com/", "http://localhost:90/a?q=b#c", "https://example.com:99/a?q=x#y"] {
            let url = URL(string: page)!
            check(Address.url(from: Address.editable(url))?.absoluteString == url.absoluteString || Address.url(from: Address.editable(url))?.absoluteString.appending("/") == url.absoluteString, "editable roundtrip " + page)
        }
        let local = Store.file("a file.html")
        try! Data("hello".utf8).write(to: local)
        check(SlateSearchServices.resolve(local.path, committed: true, siteTemplate: nil)["url"] == local.absoluteString, "typed file spaces")
        check(SlateSearchServices.resolve(Store.directory.path, committed: true, siteTemplate: nil)["kind"] == "invalid", "no directory navigation")
        for engine in Engine.allCases where engine != .custom {
            check(Engine.accepts(engine.template(custom: "")), "engine template " + engine.title)
            check(Engine.url(for: "a+b / café &?", template: engine.template(custom: ""))!.absoluteString.contains("a%2Bb%20%2F%20caf%C3%A9%20%26%3F"), "engine encoding " + engine.title)
        }
        for bad in ["https://%s.example.com/search", "https://%s@example.com/", "javascript:%s", "https://a.com/%s?x=%s", "https://a.com/", "https://%s.example.com/SEARCHWORDSGOHERE"] { check(!Keyword.accepts(bad), "bad keyword template: " + bad) }
        check(Engine.url(for: "cats", template: "https://SEARCHWORDSGOHERE.example.com/search?q=%s")?.host == "SEARCHWORDSGOHERE.example.com", "literal marker cannot change host")
        let shortcut = Keyword(keyword: "yt", template: "https://www.youtube.com/results?search_query=%s")
        SlateSearchServices.keywords = [shortcut]
        check(SlateSearchServices.resolve("YT cats & dogs", committed: true, siteTemplate: nil)["url"] == "https://www.youtube.com/results?search_query=cats%20%26%20dogs", "keyword resolution")
        check(Keyword.problem(word: "yT", template: shortcut.template, among: [shortcut]) != nil, "duplicate keyword")
        Store.settings.set("duckduckgo", forKey: "search.engine")
        check(SlateSearchServices.resolve("two words", committed: true, siteTemplate: nil)["url"] == "https://duckduckgo.com/?q=two%20words", "selected engine")
        check(SlateSearchServices.resolve("two words", committed: true, siteTemplate: "https://reddit.com/search?q=%s")["url"] == "https://reddit.com/search?q=two%20words", "site overrides engine")
        for bad in ["https://a.com/x", "/tmp/key", "~/Documents/file", "../file", "find a@b.com", "mysecret123456", "123-456-789", "line\nbreak", String(repeating: "x", count: 81)] { check(!EngineSuggest.sendable(bad), "private input: " + bad) }
        for text in ["coffee", "best coffee near me", "café", "red pandas"] { check(EngineSuggest.sendable(text), "plain words: " + text) }
        let data = Data(#"["coffee",["coffee"," coffee beans ","COFFEE BEANS",5,"coffee shops"]]"#.utf8)
        check(EngineSuggest.parse(data, asked: "coffee") == ["coffee beans", "coffee shops"], "suggestion filtering")
        check(SiteSearch.match("yt")?.name == "YouTube", "site alias")
        check(SiteSearch.match("google m")?.name == "Google Maps", "multiword site")
        check(SiteSearch.match("red panda") == nil, "don't capture ordinary search")
        check(SiteSearch.match("g") == nil, "minimum site prefix")
        SiteSearch.profile = "first"
        SiteSearch.adopt(host: "example.com", template: "https://example.com/?q=%s")
        check(SiteSearch.learned.count == 1 && SiteSearch.learned[0].name == "example.com", "learned site named by host")
        SiteSearch.adopt(host: "bad.com", template: "https://evil.com/?q=%s")
        check(SiteSearch.learned.count == 1, "reject cross-site template")
        check(SlateSearchServices.shared.site(for: "example", profile: "first", privateTab: true) == nil, "private tabs don't reveal learned sites")
        SiteSearch.profile = "second"
        check(SiteSearch.learned.isEmpty, "learned sites isolated by profile")
        SiteSearch.profile = "first"
        SiteSearch.forget()
        check(SiteSearch.learned.isEmpty, "forget learned sites")
        let xml = Data(#"<OpenSearchDescription><ShortName>Not trusted</ShortName><Url type="text/html" template="https://example.com/search?q={searchTerms}&amp;lang={language?}"/></OpenSearchDescription>"#.utf8)
        check(OpenSearch.parse(xml)?.template == "https://example.com/search?q=%s&lang=", "OpenSearch optional parameters")
        check(OpenSearch.parse(Data(#"<a><Url type="text/html" method="POST" template="https://a.com/{searchTerms}"/></a>"#.utf8)) == nil, "OpenSearch GET only")
        if CommandLine.arguments.count > 1 {
            let base = CommandLine.arguments[1]
            Store.settings.set(base + "/suggest?q=%s", forKey: "suggest.testURL")
            let service = SlateSearchServices()
            var replies: [[String]] = []
            service.suggest("private words", privateTab: false, siteActive: false) { replies.append($0) }
            await pause(0.2)
            check(replies.isEmpty, "suggestions off by default")
            Store.settings.set(true, forKey: "search.suggestions")
            service.suggest("private words", privateTab: true, siteActive: false) { replies.append($0) }
            service.suggest("/tmp/key", privateTab: false, siteActive: false) { replies.append($0) }
            await pause(0.2)
            check(replies.isEmpty, "private/path suggestion gate")
            service.suggest("coff", privateTab: false, siteActive: false) { replies.append($0) }
            await pause(0.03)
            service.suggest("coffee", privateTab: false, siteActive: false) { replies.append($0) }
            await pause(0.5)
            check(replies == [["coffee beans"]], "debounce and latest reply")
            Store.settings.set(base + "/redirect?q=%s", forKey: "suggest.testURL")
            service.suggest("coffee", privateTab: false, siteActive: false) { replies.append($0) }
            await pause(0.5)
            check(replies.count == 1, "redirect refused")
            Store.settings.set(base + "/slow?q=%s", forKey: "suggest.testURL")
            service.suggest("coffee", privateTab: false, siteActive: false) { replies.append($0) }
            await pause(1.2)
            check(replies.count == 1, "slow reply discarded")
            service.stop()
        }
        omniboxTests()
        await pageFindTests()
        print("PASS: \(checks) search checks")
    }
    @MainActor static func omniboxTests() {
        let profile = "omnibox-test"
        Store.settings.set(false, forKey: "search.commands")
        check(AddressCommand.matching("settings") == nil, "commands off by default")
        Store.settings.set(true, forKey: "search.commands")
        check(AddressCommand.matching(" Preferences ") == .settings, "whole command alias")
        check(AddressCommand.matching("settings for gmail") == nil && AddressCommand.matching("sett") == nil, "commands never capture prefixes or searches")
        for command in AddressCommand.allCases { for alias in command.aliases { check(AddressCommand.matching(alias) == command, "command alias " + alias) } }
        OmniboxHistory.record("https://alpha.com/", title: "Alpha home", profile: profile, privateTab: false)
        OmniboxHistory.record("https://secret.example/", title: "Private", profile: profile, privateTab: true)
        check(OmniboxHistory.all(profile).count == 1, "private visits never stored")
        check(OmniboxHistory.all("another-profile").isEmpty, "history isolated by profile")
        let bookmarks = [1,2,3].map { ["url": "https://kept\($0).com/", "title": "Alpha bookmark \($0)"] }
        let offers = SlateOmniboxServices.offers(for: "alpha", bookmarks: bookmarks, imported: [], profile: profile, privateTab: false)
        check(offers.count == 4 && offers[0]["kind"] == "bookmark" && offers[1]["kind"] == "bookmark" && offers[2]["url"] == "https://alpha.com/" && offers.last?["kind"] == "search", "bookmarks first, one history front door retained, search last")
        check(SlateOmniboxServices.completion(for: "alpha", offers: offers) == ".com", "history completion precedes bookmark completion")
        let duplicate = SlateOmniboxServices.offers(for: "alpha", bookmarks: [["url":"https://alpha.com", "title":"Alpha saved"]], imported: [], profile: profile, privateTab: false)
        check(duplicate.filter { $0["url"]?.hasPrefix("https://alpha.com") == true }.count == 1 && duplicate.first?["kind"] == "bookmark", "same place is one bookmarked row")
        let hidden = SlateOmniboxServices.offers(for: "alpha", bookmarks: [], imported: [], profile: profile, privateTab: true)
        check(!hidden.contains { $0["kind"] == "visited" }, "private suggestions never reveal history")
        let seed = SlateOmniboxServices.offers(for: "g", bookmarks: [], imported: [], profile: "empty", privateTab: false)
        check(SlateOmniboxServices.completion(for: "g", offers: seed) == nil, "one letter never autocompletes an unvisited seed")
        let oneLetter = SlateOmniboxServices.offers(for: "a", bookmarks: [], imported: [], profile: profile, privateTab: false)
        check(SlateOmniboxServices.completion(for: "a", offers: oneLetter) == "lpha.com", "one letter completes a visited front door")
        OmniboxHistory.record("https://history.com/", title: "History site", profile: profile, privateTab: false)
        let command = SlateOmniboxServices.offers(for: "history", bookmarks: [], imported: [], profile: profile, privateTab: false)
        check(command.first?["kind"] == "command" && SlateOmniboxServices.completion(for: "history", offers: command) == nil, "command on top suppresses a misleading address ending")
        check(SlateSearchServices.editable("https://name:password@example.com/path").contains("password") == false, "credentials absent from editable address")
        check(SlateOmniboxServices.nextSelection(-1, count: 3, step: 1) == 0 && SlateOmniboxServices.nextSelection(2, count: 3, step: 1) == -1 && SlateOmniboxServices.nextSelection(0, count: 3, step: -1) == -1 && SlateOmniboxServices.nextSelection(-1, count: 3, step: -1) == 2, "arrows walk off the list to no selection")
        OmniboxHistory.clear(profile)
        check(OmniboxHistory.all(profile).isEmpty && !FileManager.default.fileExists(atPath: OmniboxHistory.file(profile).path), "clear forgets history and cancels pending writes")
        Store.settings.set(false, forKey: "search.commands")
    }
    @MainActor static func pageFindTests() async {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let host = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        host.contentView = web
        host.isReleasedWhenClosed = false
        web.loadHTMLString("""
        <html><body><p id="phrase">hello <b>world</b></p><p id="words">cat cats Cat café cafe\u{301}</p>
        <div hidden>hello world cat</div><script>var secret='hello world cat';</script>
        <input value="cat"><input type="password" value="cat"><textarea>cat</textarea>
        <iframe srcdoc="<p>frame cat</p>"></iframe><p id="dynamic">other</p></body></html>
        """, baseURL: URL(string: "https://fixture.example"))
        for _ in 0..<100 { await pause(0.05); if !web.isLoading, (try? await js(web, "document.readyState")) as? String == "complete" { break } }
        let finder = PageFind()
        var generation: UInt64 = 0
        func find(_ query: String, _ matchCase: Bool = false, _ whole: Bool = false, _ steps: Int = 0) async -> PageFind.Result {
            generation += 1
            return await finder.update(on: web, query: query, matchCase: matchCase, wholeWords: whole, steps: steps, generation: generation)
        }
        _ = try? await js(web, "document.originalHTML=document.body.innerHTML; let original=document.createRange(); original.selectNodeContents(document.getElementById('dynamic')); getSelection().removeAllRanges(); getSelection().addRange(original)")
        var result = await find("hello world")
        check(result.count == 1 && result.index == 1, "cross-inline phrase excludes hidden/script")
        check((try? await js(web, "document.body.innerHTML === document.originalHTML")) as? Bool == true, "Find leaves DOM text nodes intact")
        check((try? await js(web, "typeof window.__searchPageFindState_v2")) as? String == "undefined", "Find state isolated from page")
        generation += 1
        _ = await finder.clear(on: web, generation: generation)
        check((try? await js(web, "getSelection().toString()")) as? String == "other", "original selection restored")
        _ = try? await js(web, "getSelection().removeAllRanges(); window.RegExp=function(){throw Error('page world')}")
        result = await find("cat", false, true)
        check(result.count == 5, "whole words includes visible controls and same-origin frame, excludes passwords and page monkey patches")
        result = await find("cat", true, true)
        check(result.count == 4, "match case")
        result = await find("cafe")
        check(result.count == 2, "accent folding and decomposed Unicode")
        _ = try? await js(web, "document.getElementById('dynamic').textContent='new needle'")
        result = await find("new needle")
        check(result.count == 1, "mutation rebuild")
        result = await find("needle", false, false, 1)
        check(result.index == 1, "next wraps")
        _ = try? await js(web, "document.body.innerHTML='<p>'+('token '.repeat(1005))+'</p>'")
        result = await find("token")
        check(result.count == 1000 && result.more, "incremental count limit")
        result = await find("token", false, false, -1)
        check(result.count == 1005 && result.index == 1005, "previous traverses to last match")
        let stale = await finder.update(on: web, query: "wrong", matchCase: false, wholeWords: false, steps: 0, generation: 1)
        check(stale.stale, "stale generation refused")
        generation += 1
        _ = await finder.clear(on: web, generation: generation)
        check((try? await js(web, "getSelection().toString()")) as? String == "", "clear removes current highlight selection")
        host.close()
    }
    @MainActor static func js(_ web: WKWebView, _ source: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(source) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value ?? NSNull()) }
            }
        }
    }
}
