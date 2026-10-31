import AppKit

@MainActor @objc public final class SlateOmniboxHistoryPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static var active: SlateOmniboxHistoryPanel?
    private let table = NSTableView()
    private let search = NSSearchField()
    private let empty = NSTextField(labelWithString: "No history yet")
    private var records: [[String: String]] = []
    private var visible: [[String: String]] = []
    private var profile = "default"
    private var openPage: ((String) -> Void)?
    private var onClear: (() -> Void)?
    @objc public static func show(profile: String, imported: [[String: String]], open: @escaping (String) -> Void, clear: @escaping () -> Void) {
        let controller = active ?? SlateOmniboxHistoryPanel()
        active = controller; controller.profile = profile; controller.openPage = open; controller.onClear = clear
        var seen: Set<String> = []
        controller.records = (SlateOmniboxServices.history(profile: profile) + imported).filter {
            guard let raw = $0["url"], let url = OmniboxHistory.safeURL(raw) else { return false }
            return seen.insert(OmniboxRules.identity(url)).inserted
        }
        controller.search.stringValue = ""; controller.filter()
        controller.window?.center(); controller.showWindow(nil)
        controller.window?.makeFirstResponder(controller.search)
    }
    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "History"; panel.minSize = NSSize(width: 400, height: 280)
        super.init(window: panel)
        let root = panel.contentView!
        search.frame = NSRect(x: 20, y: 390, width: 600, height: 28)
        search.autoresizingMask = [.width, .minYMargin]; search.placeholderString = "Search history"; search.delegate = self
        root.addSubview(search)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 58, width: 600, height: 316))
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = 600; table.addTableColumn(column); table.headerView = nil; table.rowHeight = 42
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(openSelected)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        scroll.documentView = table; root.addSubview(scroll)
        empty.frame = NSRect(x: 30, y: 210, width: 550, height: 22)
        empty.textColor = .secondaryLabelColor; empty.autoresizingMask = [.width, .minYMargin]; root.addSubview(empty)
        let open = NSButton(title: "Open selected", target: self, action: #selector(openSelected))
        open.frame = NSRect(x: 475, y: 16, width: 145, height: 28); open.autoresizingMask = [.minXMargin]; root.addSubview(open)
        let clear = NSButton(title: "Clear history", target: self, action: #selector(clearHistory))
        clear.frame = NSRect(x: 20, y: 16, width: 135, height: 28); root.addSubview(clear)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func filter() {
        let query = search.stringValue.lowercased()
        visible = records.filter { query.isEmpty || (($0["url"] ?? "") + " " + ($0["title"] ?? "")).lowercased().contains(query) }
        empty.stringValue = records.isEmpty ? "No history yet" : "No matching pages"
        empty.isHidden = !visible.isEmpty
        table.reloadData()
    }
    public func controlTextDidChange(_ notification: Notification) { filter() }
    public func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = visible[row]
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: item["title"].flatMap { $0.isEmpty ? nil : $0 } ?? item["url"] ?? "")
        title.font = .systemFont(ofSize: 13); title.frame = NSRect(x: 8, y: 22, width: tableView.bounds.width-30, height: 18)
        title.lineBreakMode = .byTruncatingTail; title.autoresizingMask = [.width]; cell.addSubview(title)
        let address = NSTextField(labelWithString: item["key"] ?? item["url"] ?? "")
        address.font = .systemFont(ofSize: 11); address.textColor = .secondaryLabelColor
        address.frame = NSRect(x: 8, y: 4, width: tableView.bounds.width-30, height: 16)
        address.lineBreakMode = .byTruncatingMiddle; address.autoresizingMask = [.width]; cell.addSubview(address)
        return cell
    }
    @objc private func openSelected() {
        let selected = table.selectedRow
        guard visible.indices.contains(selected), let url = visible[selected]["url"] else { return }
        window?.orderOut(nil); openPage?(url)
    }
    @objc private func clearHistory() {
        OmniboxHistory.clear(profile); onClear?(); records = []; filter()
    }
}
