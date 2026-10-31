import AppKit
import Combine
import WebKit

@objc(SlatePasswordServices)
@MainActor public final class SlatePasswordServices: NSObject {
    @objc public static let shared = SlatePasswordServices()
    private var contexts = NSMapTable<WKWebView, SlatePasswordContext>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var panel: NSPanel?
    private var bag = Set<AnyCancellable>()
    @objc public static var autofillEnabled: Bool { UserDefaults.standard.object(forKey: "passwords.autofill") as? Bool ?? true }
    @objc public static var appleEnabled: Bool { UserDefaults.standard.bool(forKey: "passwords.apple.enabled") }
    @objc public static var passkeysEnabled: Bool { FormRelay.passkeysOffered }
    @objc public static var passkeysAvailable: Bool { Preferences.entitledToPasskeys }
    static func context(for web: WKWebView) -> SlatePasswordContext? { shared.contexts.object(forKey: web) }
    @objc public func configure(_ web: WKWebView, privateTab: Bool,
                         accounts: @escaping (URL) -> [[String:String]]?,
                         unlock: @escaping () -> Bool,
                         select: @escaping (String, URL) -> [String:String]?) {
        let context = SlatePasswordContext(web: web, privateTab: privateTab, accounts: accounts, unlock:unlock, select: select)
        contexts.setObject(context, forKey: web)
        context.install()
    }
    @objc public func navigating(_ web:WKWebView) { contexts.object(forKey:web)?.navigating() }
    @objc public func navigated(_ web: WKWebView) {
        contexts.object(forKey: web)?.navigated()
    }
    @objc public func close(_ web: WKWebView) {
        contexts.object(forKey:web)?.navigated()
        web.configuration.userContentController.removeScriptMessageHandler(forName:"slatePasswords",contentWorld:.defaultClient)
        if #available(macOS 14.4,*) { web.configuration.userContentController.removeScriptMessageHandler(forName:PasskeyRelay.name,contentWorld:.defaultClient) }
        contexts.removeObject(forKey:web)
    }
    @objc public func consumedAppleFill(_ web: WKWebView, host: String, user: String, password: String) -> Bool {
        contexts.object(forKey:web)?.appleFill?.matches(host:host,user:user,password:password) ?? false
    }
    @objc public func settingsView() -> NSView { PasswordSettingsView(frame:NSRect(x:0,y:0,width:450,height:218)) }
    func connect(from window: NSWindow?) {
        // The helper is only ever started by a native button click.
        UserDefaults.standard.set(true,forKey:"passwords.apple.enabled")
        if panel == nil {
            let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:470,height:240), styleMask:[.titled,.closable], backing:.buffered,defer:false)
            panel.title = "Apple Passwords"
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }
        panel?.contentView = settingsView()
        panel?.center(); panel?.makeKeyAndOrderFront(nil)
        Task { await ApplePasswords.shared.connect() }
    }
    @objc public func preferencesChanged() {
        for context in contexts.objectEnumerator()?.allObjects as? [SlatePasswordContext] ?? [] { context.dismiss() }
        if !Self.appleEnabled || !Self.autofillEnabled { ApplePasswords.shared.disconnect() }
    }
    override init() {
        super.init()
        NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification).sink { [weak self] _ in
            MainActor.assumeIsolated {
                for context in self?.contexts.objectEnumerator()?.allObjects as? [SlatePasswordContext] ?? [] { context.dismiss() }
            }
        }.store(in:&bag)
    }
}

@MainActor final class PasswordSettingsView: NSView {
    private let engine: ApplePasswords
    private let access: AppleHelper.Access
    private let store: UserDefaults
    private let apple = NSButton(checkboxWithTitle:"Use Apple Passwords",target:nil,action:nil)
    private let fills = NSButton(checkboxWithTitle:"Offer saved accounts under sign-in fields",target:nil,action:nil)
    private let passkeys = NSButton(checkboxWithTitle:"Offer passkeys and security keys",target:nil,action:nil)
    private let status = NSTextField(wrappingLabelWithString:"")
    private let code = NSSecureTextField()
    private let connect = NSButton(title:"Connect…",target:nil,action:nil)
    private let verify = NSButton(title:"Verify Code",target:nil,action:nil)
    private let open = NSButton(title:"Open Apple Passwords",target:nil,action:nil)
    private var bag = Set<AnyCancellable>()
    init(frame:NSRect, engine: ApplePasswords? = nil, access: AppleHelper.Access? = nil, store:UserDefaults? = nil) {
        self.engine=engine ?? .shared
        self.access=access ?? AppleHelper.access
        self.store=store ?? .standard
        super.init(frame:frame)
        for (view,y) in [(fills as NSView,186.0),(apple,154),(passkeys,122),(connect,88),(code,88),(verify,88),(open,88),(status,10)] {
            view.frame=NSRect(x:8,y:y,width:frame.width-16,height:view === status ? 66 : 26)
            addSubview(view)
        }
        fills.target=self; fills.action=#selector(toggleFills)
        apple.target=self; apple.action=#selector(toggleApple)
        passkeys.target=self; passkeys.action=#selector(togglePasskeys)
        connect.target=self; connect.action=#selector(connectClicked)
        verify.target=self; verify.action=#selector(verifyClicked)
        code.target=self;code.action=#selector(verifyClicked)
        open.target=self;open.action=#selector(openClicked)
        connect.frame.size.width=112
        code.frame=NSRect(x:130,y:88,width:140,height:26); code.placeholderString="Six-digit code"; code.maximumNumberOfLines=1
        verify.frame=NSRect(x:278,y:88,width:110,height:26)
        open.frame=NSRect(x:130,y:88,width:190,height:26)
        connect.identifier=NSUserInterfaceItemIdentifier("apple-passwords-connect")
        code.identifier=NSUserInterfaceItemIdentifier("apple-passwords-code")
        verify.identifier=NSUserInterfaceItemIdentifier("apple-passwords-verify")
        status.identifier=NSUserInterfaceItemIdentifier("apple-passwords-status")
        status.font = .systemFont(ofSize:11);status.textColor = .secondaryLabelColor
        status.isSelectable=true
        apple.toolTip="Optional connection using Apple's signed system helper. Pairing is required after each launch."
        passkeys.toolTip=Preferences.entitledToPasskeys ? "Changes to availability apply to new tabs." : "This build needs Apple's approved browser passkey entitlement."
        // @Published emits before the stored property changes. Render the values
        // delivered by the publisher; rereading engine.state here lags one event.
        self.engine.$state.combineLatest(self.engine.$trouble).sink { [weak self] state,trouble in
            self?.refresh(state:state,trouble:trouble)
        }.store(in:&bag)
        refreshCurrent()
    }
    override func draw(_ dirtyRect:NSRect) { NSColor.windowBackgroundColor.setFill();dirtyRect.fill() }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func refreshCurrent() { refresh(state:engine.state,trouble:engine.trouble) }
    private func refresh(state:ApplePasswords.State,trouble:String?) {
        fills.state=(store.object(forKey:"passwords.autofill") as? Bool ?? true) ? .on : .off
        apple.state=store.bool(forKey:"passwords.apple.enabled") ? .on : .off
        apple.isEnabled=access.canConnect || apple.state == .on
        passkeys.state=SlatePasswordServices.passkeysEnabled ? .on : .off
        passkeys.isEnabled=Preferences.entitledToPasskeys
        switch state {
        case .idle: connect.title="Connect…"
        case .paired: connect.title="Disconnect"
        case .starting,.code,.checking: connect.title="Cancel"
        }
        // An unavailable helper produces an inline explanation when clicked;
        // never leave a button looking inert or allow a busy connection to stick.
        connect.isEnabled=true
        code.isHidden=state != .code && state != .checking
        verify.isHidden=code.isHidden;verify.isEnabled=state == .code
        open.isHidden=access.canConnect || !code.isHidden
        if code.isHidden { code.stringValue="" }
        let words:String
        switch state {
        case .starting: words="Connecting to Apple Passwords…"
        case .checking: words="Checking the pairing code…"
        case .code: words="Enter the six-digit code shown by Apple's helper."
        case .paired: words="Connected. Accounts stay in Apple Passwords; selected passwords are filled without saving a copy in Slate."
        case .idle: words="Connect when you want to use Apple Passwords. Pair again after restarting Slate."
        }
        status.stringValue=trouble ?? access.explanation ?? words
        if !Preferences.entitledToPasskeys && access != .browserApprovalRequired {
            status.stringValue += "\nPasskeys require an Apple-approved browser build."
        }
    }
    @objc private func toggleFills() { store.set(fills.state == .on,forKey:"passwords.autofill"); SlatePasswordServices.shared.preferencesChanged();refreshCurrent() }
    @objc private func toggleApple() { store.set(apple.state == .on,forKey:"passwords.apple.enabled"); SlatePasswordServices.shared.preferencesChanged();refreshCurrent() }
    @objc private func togglePasskeys() { store.set(passkeys.state == .on,forKey:"passkeys");refreshCurrent() }
    @objc private func connectClicked() {
        if engine.state != .idle { engine.disconnect() }
        else {
            guard access.canConnect else {
                engine.explainUnavailable(access.explanation ?? "Apple Passwords is unavailable.")
                return
            }
            store.set(true,forKey:"passwords.apple.enabled")
            Task { await engine.connect() }
        }
        refreshCurrent()
    }
    @objc private func verifyClicked() { let value=code.stringValue;code.stringValue="";Task { await engine.enter(value) } }
    @objc private func openClicked() {
        guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Passwords") else {
            status.stringValue="Apple Passwords couldn't be found on this Mac.";return
        }
        NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration()) { [weak self] _,error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.status.stringValue="Apple Passwords could not be opened." }
        }
    }
}
