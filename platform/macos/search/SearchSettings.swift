import AppKit

private final class SearchSettingsDocument: NSView { override var isFlipped: Bool { true } }

@MainActor
final class SearchSettingsView: NSView {
    var profile = "default"
    private let content = NSStackView()
    private let engine = NSPopUpButton()
    private let custom = NSTextField()
    private var customHint: NSTextField?
    private let error = NSTextField(wrappingLabelWithString: "")
    private let shortcuts = NSStackView()
    private let word = NSTextField()
    private let template = NSTextField()
    override init(frame: NSRect) {
        super.init(frame: frame)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)])
        let document = SearchSettingsDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), content.topAnchor.constraint(equalTo: document.topAnchor, constant: 24), content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)])
        label("Search", size: 19, bold: true)
        label("Search engine", bold: true)
        engine.addItems(withTitles: Engine.allCases.map(\.title))
        engine.selectItem(at: Engine.allCases.firstIndex(of: SlateSearchServices.engine) ?? 0)
        engine.target = self; engine.action = #selector(changeEngine)
        content.addArrangedSubview(engine)
        custom.stringValue = SlateSearchServices.custom
        custom.placeholderString = "https://example.com/search?q=%s"
        custom.target = self; custom.action = #selector(saveCustom)
        custom.delegate = self
        content.addArrangedSubview(custom)
        custom.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        customHint = label("A custom address must contain %s once, where the search words go. Google is used until the address is valid.", secondary: true)
        addToggle("Suggestions from your search engine", key: "search.suggestions", fallback: false)
        label("Sends search words to your chosen engine as you type. Off by default and always off in private tabs. Addresses, email addresses, file paths and text that resembles a key stay on this Mac.", secondary: true)
        addToggle("Search sites from the address field", key: "search.sites", fallback: true)
        label("Type a site’s name, then press Tab to search there. Backspace in an empty field removes the site. Sites you visit can add their own shortcut.", secondary: true)
        addToggle("Address bar commands", key: "search.commands", fallback: false)
        label("Use whole commands such as settings, history or new private tab. Off by default; other words continue to search.", secondary: true)
        addToggle("Use lighter motion when this Mac is low on power", key: "motion.light", fallback: false)
        label("Site shortcuts", bold: true)
        label("Type a keyword and a space, such as “yt cats”. These work with any search engine.", secondary: true)
        shortcuts.orientation = .vertical; shortcuts.alignment = .leading; shortcuts.spacing = 8
        content.addArrangedSubview(shortcuts)
        shortcuts.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        word.placeholderString = "Keyword, e.g. yt"
        template.placeholderString = "https://www.youtube.com/results?search_query=%s"
        for field in [word, template] {
            content.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        error.textColor = .systemRed; error.font = .systemFont(ofSize: 11)
        content.addArrangedSubview(error)
        let add = NSButton(title: "Add shortcut", target: self, action: #selector(addShortcut))
        content.addArrangedSubview(add)
        let forget = NSButton(title: "Forget learned sites", target: self, action: #selector(forgetSites))
        content.addArrangedSubview(forget)
        renderShortcuts(); changeEngine()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @discardableResult private func label(_ text: String, size: CGFloat = 13, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: secondary ? 11 : size, weight: bold ? .semibold : .regular)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        content.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return label
    }
    private func addToggle(_ title: String, key: String, fallback: Bool) {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.state = Store.settings.object(forKey: key) as? Bool ?? fallback ? .on : .off
        content.addArrangedSubview(button)
    }
    @objc private func forgetSites(_ button: NSButton) {
        SlateSearchServices.shared.forgetSites(profile: profile)
        button.title = "Learned sites forgotten"
        button.isEnabled = false
    }
    @objc private func toggle(_ button: NSButton) {
        Store.settings.set(button.state == .on, forKey: button.identifier!.rawValue)
        SlateSearchServices.shared.stop()
    }
    @objc private func changeEngine() {
        Store.settings.set(Engine.allCases[max(0, engine.indexOfSelectedItem)].rawValue, forKey: "search.engine")
        custom.isHidden = SlateSearchServices.engine != .custom
        customHint?.isHidden = custom.isHidden
        SlateSearchServices.shared.stop()
    }
    @objc private func saveCustom() { Store.settings.set(custom.stringValue, forKey: "search.custom") }
    private func renderShortcuts() {
        for row in shortcuts.arrangedSubviews { shortcuts.removeArrangedSubview(row); row.removeFromSuperview() }
        for shortcut in SlateSearchServices.keywords {
            let row = NSStackView()
            let text = NSTextField(labelWithString: shortcut.keyword + "  →  " + shortcut.name)
            text.lineBreakMode = .byTruncatingMiddle
            row.addArrangedSubview(text)
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeShortcut(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier(shortcut.id.uuidString)
            row.addArrangedSubview(remove)
            shortcuts.addArrangedSubview(row)
        }
    }
    @objc private func addShortcut() {
        let message = Keyword.problem(word: word.stringValue, template: template.stringValue, among: SlateSearchServices.keywords)
        error.stringValue = message ?? ""
        guard message == nil else { return }
        SlateSearchServices.keywords.append(Keyword(keyword: word.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), template: template.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)))
        word.stringValue = ""; template.stringValue = ""; renderShortcuts()
    }
    @objc private func removeShortcut(_ button: NSButton) {
        SlateSearchServices.keywords.removeAll { $0.id.uuidString == button.identifier?.rawValue }
        renderShortcuts()
    }
}
extension SearchSettingsView: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) { saveCustom() }
}
