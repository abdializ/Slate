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
    private let apple = NSButton(checkboxWithTitle:"Use Apple Passwords",target:nil,action:nil)
    private let fills = NSButton(checkboxWithTitle:"Offer saved accounts under sign-in fields",target:nil,action:nil)
    private let passkeys = NSButton(checkboxWithTitle:"Offer passkeys and security keys",target:nil,action:nil)
    private let status = NSTextField(wrappingLabelWithString:"")
    private let code = NSSecureTextField()
    private let connect = NSButton(title:"Connect…",target:nil,action:nil)
    private let verify = NSButton(title:"Verify Code",target:nil,action:nil)
    private var bag = Set<AnyCancellable>()
    override init(frame:NSRect) {
        super.init(frame:frame)
        for (view,y) in [(fills as NSView,186.0),(apple,154),(passkeys,122),(connect,88),(code,88),(verify,88),(status,10)] {
            view.frame=NSRect(x:8,y:y,width:frame.width-16,height:view === status ? 66 : 26)
            addSubview(view)
        }
        fills.target=self; fills.action=#selector(toggleFills)
        apple.target=self; apple.action=#selector(toggleApple)
        passkeys.target=self; passkeys.action=#selector(togglePasskeys)
        connect.target=self; connect.action=#selector(connectClicked)
        verify.target=self; verify.action=#selector(verifyClicked)
        connect.frame.size.width=112
        code.frame=NSRect(x:130,y:88,width:140,height:26); code.placeholderString="Six-digit code"; code.maximumNumberOfLines=1
        verify.frame=NSRect(x:278,y:88,width:110,height:26)
        status.font = .systemFont(ofSize:11);status.textColor = .secondaryLabelColor
        apple.toolTip="Optional, unofficial connection using Apple's signed system helper. Pairing is required after each launch."
        passkeys.toolTip=Preferences.entitledToPasskeys ? "Changes to availability apply to new tabs." : "This build needs Apple's approved browser passkey entitlement."
        ApplePasswords.shared.$state.combineLatest(ApplePasswords.shared.$trouble).sink { [weak self] _,_ in self?.refresh() }.store(in:&bag)
        refresh()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func refresh() {
        fills.state=SlatePasswordServices.autofillEnabled ? .on : .off
        apple.state=SlatePasswordServices.appleEnabled ? .on : .off
        apple.isEnabled=ApplePasswordsOffer.helperHere
        passkeys.state=SlatePasswordServices.passkeysEnabled ? .on : .off
        passkeys.isEnabled=Preferences.entitledToPasskeys
        let state=ApplePasswords.shared.state
        connect.title=state == .paired ? "Disconnect" : "Connect…"
        connect.isEnabled=ApplePasswordsOffer.helperHere && (state == .idle || state == .paired)
        code.isHidden=state != .code && state != .checking
        verify.isHidden=code.isHidden;verify.isEnabled=state == .code
        if state != .code && state != .checking { code.stringValue="" }
        let words=ApplePasswords.shared.trouble ?? (state == .paired ? "Connected. Accounts stay in Apple Passwords; selected passwords are filled without saving a copy in Slate." : state == .code || state == .checking ? "Enter the six-digit code shown by Apple's helper." : "Optional connection to Apple's system helper. Connect only when you want to use it; pair again after restarting Slate.")
        status.stringValue = !ApplePasswordsOffer.helperHere ? "Apple Passwords needs macOS 15.4 or later and Apple's signed system helper." : words
        if !Preferences.entitledToPasskeys { status.stringValue += "\nPasskeys require an Apple-approved browser build." }
    }
    @objc private func toggleFills() { UserDefaults.standard.set(fills.state == .on,forKey:"passwords.autofill"); SlatePasswordServices.shared.preferencesChanged();refresh() }
    @objc private func toggleApple() { UserDefaults.standard.set(apple.state == .on,forKey:"passwords.apple.enabled"); SlatePasswordServices.shared.preferencesChanged();refresh() }
    @objc private func togglePasskeys() { UserDefaults.standard.set(passkeys.state == .on,forKey:"passkeys");refresh() }
    @objc private func connectClicked() {
        if ApplePasswords.shared.state == .paired { ApplePasswords.shared.disconnect() }
        else { UserDefaults.standard.set(true,forKey:"passwords.apple.enabled");Task { await ApplePasswords.shared.connect() } }
        refresh()
    }
    @objc private func verifyClicked() { let value=code.stringValue;code.stringValue="";Task { await ApplePasswords.shared.enter(value) } }
}
