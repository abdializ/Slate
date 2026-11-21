import AppKit
import Security
import WebKit

private struct AutofillItem {
    enum Kind { case account, generate, unlock, passkey, apple }
    let kind: Kind
    let title: String
    let subtitle: String
    let action: () -> Void
    let dismissAction: (() -> Void)?
    init(kind: Kind, title: String, subtitle: String, action: @escaping () -> Void, dismissAction: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.dismissAction = dismissAction
    }
}

private final class AutofillRowView: NSView {
    private let onPick: () -> Void
    private let onDismiss: (() -> Void)?
    private var hovered = false
    private let bgLayer = CALayer()

    init(frame: NSRect, item: AutofillItem, onPick: @escaping () -> Void, onDismiss: (() -> Void)? = nil) {
        self.onPick = onPick
        self.onDismiss = onDismiss
        super.init(frame: frame)
        wantsLayer = true
        bgLayer.cornerRadius = 8
        if #available(macOS 11.0, *) { bgLayer.cornerCurve = .continuous }
        bgLayer.frame = bounds.insetBy(dx: 6, dy: 2)
        bgLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(bgLayer)

        let iconBox = NSView(frame: NSRect(x: 14, y: (frame.height - 28) / 2, width: 28, height: 28))
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 14
        let tint: NSColor
        let symbolName: String
        switch item.kind {
        case .account:
            tint = .controlAccentColor
            symbolName = "key.fill"
        case .generate:
            tint = .systemGreen
            symbolName = "sparkles"
        case .unlock:
            tint = .systemOrange
            symbolName = "lock.fill"
        case .passkey:
            tint = .systemIndigo
            symbolName = "person.badge.key.fill"
        case .apple:
            tint = .secondaryLabelColor
            symbolName = "key.horizontal.fill"
        }
        iconBox.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        if #available(macOS 11.0, *) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let iv = NSImageView(frame: NSRect(x: 6, y: 6, width: 16, height: 16))
                iv.image = img
                iv.contentTintColor = tint
                iv.imageAlignment = .alignCenter
                iconBox.addSubview(iv)
            }
        }
        addSubview(iconBox)

        let textWidth = frame.width - (onDismiss != nil ? 86 : 62)
        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.frame = NSRect(x: 50, y: frame.height / 2 + 1, width: textWidth, height: 16)
        addSubview(titleLabel)

        let subLabel = NSTextField(labelWithString: item.subtitle)
        subLabel.font = item.kind == .generate ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.frame = NSRect(x: 50, y: frame.height / 2 - 15, width: textWidth, height: 14)
        addSubview(subLabel)

        if onDismiss != nil {
            let stop = NSButton(title: "×", target: self, action: #selector(dismissPressed))
            stop.isBordered = false
            stop.font = .systemFont(ofSize: 14, weight: .medium)
            stop.toolTip = "Don’t offer again"
            stop.setAccessibilityLabel("Don’t offer Apple Passwords again")
            stop.frame = NSRect(x: frame.width - 34, y: (frame.height - 26) / 2, width: 24, height: 26)
            addSubview(stop)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        CATransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgLayer.backgroundColor = NSColor.clear.cgColor
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onPick()
    }

    @objc private func dismissPressed() { onDismiss?() }
}

@MainActor final class SlatePasswordContext: NSObject, WKScriptMessageHandler, NSPopoverDelegate {
    weak var web: WKWebView?
    let privateTab: Bool
    var committedURL: URL?
    var appleFill: AppleFill?
    private let accounts: (URL) -> [[String:String]]?
    private let unlock: () -> Bool
    private let select: (String,URL) -> [String:String]?
    private let tab = UUID()
    private var frame: WKFrameInfo?
    private var origin: URL?
    private var fieldToken: String?
    private var generation = 0
    private var passkeyObserver: NSObjectProtocol?
    private var popover: NSPopover?
    private var offerOutstanding = false
    private var pendingSite: String?
    private var offer: ApplePasswordsOffer { ApplePasswordsOffer(store:.standard) }

    init(web:WKWebView,privateTab:Bool,accounts:@escaping (URL)->[[String:String]]?,unlock:@escaping ()->Bool,select:@escaping (String,URL)->[String:String]?) {
        self.web=web;self.privateTab=privateTab;self.accounts=accounts;self.unlock=unlock;self.select=select;committedURL=web.url
        super.init()
        if #available(macOS 14.4,*) {
            passkeyObserver=NotificationCenter.default.addObserver(forName:Passkeys.offeredChanged,object:nil,queue:.main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,let web=self.web,note.object as? WKWebView === web,let frame=self.frame,self.fieldToken != nil else { return }
                    web.callAsyncJavaScript("window.__slatePasswordRefresh?.()",arguments:[:],in:frame,in:.defaultClient) { _ in }
                }
            }
        }
    }
    deinit { if let passkeyObserver { NotificationCenter.default.removeObserver(passkeyObserver) } }

    static func generateStrongPassword() -> String {
        let lower = Array("abcdefghijkmnopqrstuvwxyz")
        let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let digits = Array("23456789")
        let all = lower + upper + digits
        func randomIndex(_ bound: Int) -> Int {
            var v: UInt32 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &v)
            return Int(v % UInt32(bound))
        }
        var chars: [Character] = [
            upper[randomIndex(upper.count)],
            lower[randomIndex(lower.count)],
            digits[randomIndex(digits.count)],
            digits[randomIndex(digits.count)]
        ]
        while chars.count < 16 {
            chars.append(all[randomIndex(all.count)])
        }
        // Fisher-Yates shuffle using CSPRNG
        for i in stride(from: chars.count - 1, through: 1, by: -1) {
            let j = randomIndex(i + 1)
            chars.swapAt(i, j)
        }
        return stride(from: 0, to: 16, by: 4).map { String(chars[$0..<$0+4]) }.joined(separator: "-")
    }

    func install() {
        guard let web else { return }
        let controller=web.configuration.userContentController
        controller.removeScriptMessageHandler(forName:"slatePasswords",contentWorld:.defaultClient)
        controller.add(self,contentWorld:.defaultClient,name:"slatePasswords")
        if !controller.userScripts.contains(where:{$0.source == Self.fieldScript}) {
            controller.addUserScript(WKUserScript(source:Self.fieldScript,injectionTime:.atDocumentEnd,forMainFrameOnly:false,in:.defaultClient))
        }
        if #available(macOS 14.4,*), Preferences.entitledToPasskeys {
            controller.removeScriptMessageHandler(forName:PasskeyRelay.name,contentWorld:.defaultClient)
            controller.addScriptMessageHandler(PasskeyRelay(),contentWorld:.defaultClient,name:PasskeyRelay.name)
            let kept=controller.userScripts.filter { !$0.source.hasPrefix("/* slate-passkeys-page */") && $0.source != PasskeyRelay.bridge }
            controller.removeAllUserScripts()
            kept.forEach { controller.addUserScript($0) }
            controller.addUserScript(WKUserScript(source:PasskeyRelay.page,injectionTime:.atDocumentStart,forMainFrameOnly:false,in:.page))
            controller.addUserScript(WKUserScript(source:PasskeyRelay.bridge,injectionTime:.atDocumentStart,forMainFrameOnly:false,in:.defaultClient))
        }
    }
    func navigating() {
        dismiss();frame=nil;origin=nil;fieldToken=nil
        if #available(macOS 14.4,*), let web { Passkeys.shared.forget(web) }
    }
    func navigated() {
        dismiss();frame=nil;origin=nil;fieldToken=nil;appleFill=nil;committedURL=web?.url
        if #available(macOS 14.4,*), let web { Passkeys.shared.forget(web) }
    }
    func dismiss() {
        generation += 1
        if offerOutstanding { offerOutstanding=false;offer.unanswered() }
        pendingSite=nil
        let shown=popover;popover=nil;shown?.delegate=nil;shown?.close()
        fieldToken=nil;frame=nil;origin=nil
    }
    func popoverDidClose(_ notification:Notification) { dismiss() }
    private func valid(_ expected:Int) -> Bool {
        guard generation == expected, let web, (web.window?.isKeyWindow == true || popover?.contentViewController?.view.window?.isKeyWindow == true), NSApp.isActive,
              let curHost = web.url?.host?.lowercased(),
              let refHost = (committedURL ?? web.url)?.host?.lowercased(),
              Registrable.sameSite(curHost, refHost),
              !web.isHiddenOrHasHiddenAncestor, fieldToken != nil else { return false }
        return true
    }

    private func pointerInsidePopover() -> Bool {
        guard let popWin = popover?.contentViewController?.view.window, popWin.isVisible else { return false }
        return popWin.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard let web, message.webView === web, let body=message.body as? [String:Any] else { return }
        if body["kind"] as? String == "blur" {
            if pointerInsidePopover() || popover?.contentViewController?.view.window?.isKeyWindow == true { return }
            dismiss();fieldToken=nil;return
        }
        let page = web.url ?? committedURL
        guard SlatePasswordServices.autofillEnabled, NSApp.isActive, web.window?.isKeyWindow == true,
              !web.isHiddenOrHasHiddenAncestor, !privateTab,
              let page, page.scheme == "https",
              let pageHost=page.host?.lowercased(), !pageHost.isEmpty,
              message.frameInfo.securityOrigin.protocol.lowercased() == "https",
              Registrable.sameSite(pageHost,message.frameInfo.securityOrigin.host.lowercased()),
              let token=body["token"] as? String, token.count <= 128,
              let rect=body["rect"] as? [String:Double], let x=rect["x"],let y=rect["y"],let w=rect["w"],let h=rect["h"],
              [x,y,w,h].allSatisfy({$0.isFinite}),w>0,h>0 else { return }
        committedURL = page
        dismiss()
        frame=message.frameInfo;fieldToken=token
        var components=URLComponents();components.scheme="https";components.host=message.frameInfo.securityOrigin.host.lowercased()
        if message.frameInfo.securityOrigin.port != 0 && message.frameInfo.securityOrigin.port != 443 { components.port=message.frameInfo.securityOrigin.port }
        guard let origin=components.url else { return };self.origin=origin
        let hostLabel = components.host ?? pageHost
        let passwords=body["passwords"] as? Bool ?? false
        let generate=body["generate"] as? Bool ?? false
        let expected=generation
        var items: [AutofillItem] = []

        if generate {
            let suggestion = Self.generateStrongPassword()
            items.append(AutofillItem(kind: .generate, title: "Use Strong Password", subtitle: suggestion, action: { [weak self] in
                guard let self, self.valid(expected) else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(suggestion, forType: .string)
                self.fillGenerated(password: suggestion, expected: expected)
            }))
        }

        let all = passwords ? accounts(origin) : []
        let matching = (all ?? []).filter { item in
            Self.matchesSite(URL(string: item["origin"] ?? ""), origin)
        }.sorted { a, b in
            let aExact = Self.sameOrigin(URL(string: a["origin"] ?? ""), origin)
            let bExact = Self.sameOrigin(URL(string: b["origin"] ?? ""), origin)
            if aExact != bExact { return aExact }
            return (a["user"] ?? "") < (b["user"] ?? "")
        }
        if passwords && all == nil {
            items.append(AutofillItem(kind: .unlock, title: "Unlock Slate Vault…", subtitle: "Authenticate with Touch ID or password", action: { [weak self] in
                guard let self,self.valid(expected),self.unlock(),let web=self.web,let frame=self.frame else { return }
                web.callAsyncJavaScript("window.__slatePasswordRefresh?.()",arguments:[:],in:frame,in:.defaultClient) { _ in }
            }))
        }
        for item in passwords ? matching.prefix(8) : [] {
            guard let id=item["id"] else { continue }
            let username = item["user"].flatMap{$0.isEmpty ? nil : $0} ?? "Saved Account"
            items.append(AutofillItem(kind: .account, title: username, subtitle: hostLabel + " · Slate Vault", action: { [weak self] in
                guard let self, self.valid(expected), let found=self.select(id,origin), let user=found["user"],let password=found["password"] else { return }
                self.fill(user:user,password:password,expected:expected)
            }))
        }
        if #available(macOS 14.4,*) {
            for found in Passkeys.shared.offered(in:web) {
                items.append(AutofillItem(kind: .passkey, title: found.name, subtitle: "Passkey", action: { [weak self,weak web] in
                    guard let self, self.valid(expected),let web else { return }
                    self.dismiss();Passkeys.shared.sign(in:web,with:found.id)
                }))
            }
        }
        if passwords && SlatePasswordServices.appleEnabled && ApplePasswordsOffer.helperHere && ApplePasswords.shared.state == .paired {
            Task { [weak self] in
                guard let self else { return }
                let found=await ApplePasswords.shared.logins(for:hostLabel,tab:self.tab,wanted:{ [weak self] in self?.valid(expected) ?? false })
                guard self.valid(expected) else { return }
                let own=found.filter { ApplePasswords.belongs($0.sites,to:hostLabel) }
                let extra:[AutofillItem]=own.prefix(8).map { login in
                    AutofillItem(kind: .apple, title: login.user, subtitle: hostLabel + " · Apple Passwords", action: { [weak self] in
                        self?.selectApple(login,host:hostLabel,expected:expected)
                    })
                }
                if !extra.isEmpty {
                    self.show(items:items + extra,rect:message.frameInfo.isMainFrame ? NSRect(x:x,y:y,width:w,height:h) : NSRect(x:12,y:0,width:240,height:24))
                }
            }
        }
        if !items.isEmpty {
            show(items:items,rect:message.frameInfo.isMainFrame ? NSRect(x:x,y:y,width:w,height:h) : NSRect(x:12,y:0,width:240,height:24))
        }
    }

    static func sameOrigin(_ a:URL?,_ b:URL) -> Bool {
        guard let a else { return false }
        return a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased() && (a.port ?? 443) == (b.port ?? 443)
    }

    static func matchesSite(_ saved:URL?, _ current:URL) -> Bool {
        guard let saved, let savedHost = saved.host?.lowercased(), let curHost = current.host?.lowercased() else { return false }
        if sameOrigin(saved, current) { return true }
        return Registrable.sameSite(savedHost, curHost)
    }

    private func show(items:[AutofillItem],rect:NSRect) {
        guard let web, !items.isEmpty else { return }
        if let shown=popover { shown.delegate=nil;shown.close() }
        let pop=NSPopover();pop.behavior = .semitransient;pop.delegate=self
        let rowHeight: CGFloat = 46
        let headerHeight: CGFloat = 26
        let width: CGFloat = 310
        let totalHeight = headerHeight + CGFloat(items.count) * rowHeight + 8
        let controller=NSViewController()
        let content=NSView(frame:NSRect(x:0,y:0,width:width,height:totalHeight))

        let header = NSTextField(labelWithString: "SLATE VAULT")
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = .tertiaryLabelColor
        header.frame = NSRect(x: 16, y: totalHeight - 20, width: width - 32, height: 14)
        content.addSubview(header)

        let sep = NSView(frame: NSRect(x: 12, y: totalHeight - headerHeight, width: width - 24, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        content.addSubview(sep)

        for (index, item) in items.enumerated() {
            let y = totalHeight - headerHeight - 4 - CGFloat(index + 1) * rowHeight
            let row = AutofillRowView(frame: NSRect(x: 0, y: y, width: width, height: rowHeight), item: item, onPick: item.action, onDismiss: item.dismissAction)
            content.addSubview(row)
        }
        controller.view=content;pop.contentViewController=controller;popover=pop
        let anchor=web.isFlipped ? rect : NSRect(x:rect.minX,y:web.bounds.height-rect.maxY,width:rect.width,height:rect.height)
        let clipped=anchor.intersection(web.bounds)
        guard !clipped.isNull,!clipped.isEmpty else { popover=nil;return }
        pop.show(relativeTo:clipped,of:web,preferredEdge:.maxY)
        if pop.isShown, let site=pendingSite { offer.shown(on:site);offerOutstanding=true;pendingSite=nil }
    }

    @objc private func dontOffer() { offerOutstanding=false;offer.dismissed();dismiss() }

    private func selectApple(_ login:AppleLogin,host:String,expected:Int) {
        guard valid(expected) else { return }
        Task { [weak self] in
            guard let self, let value=await ApplePasswords.shared.password(for:login.user,host:host,tab:self.tab,wanted:{ [weak self] in self?.valid(expected) ?? false }),
                  self.valid(expected),ApplePasswords.belongs(value.sites,to:host) else { return }
            self.appleFill=AppleFill(host:host,user:login.user,password:value.password)
            self.fill(user:login.user,password:value.password,expected:expected)
        }
    }

    private func fill(user:String,password:String,expected:Int) {
        guard valid(expected), let web, let frame, let token=fieldToken else { return }
        let targetWeb = web
        let targetFrame = frame
        let targetToken = token
        dismiss()
        targetWeb.window?.makeKeyAndOrderFront(nil)
        targetWeb.window?.makeFirstResponder(targetWeb)
        targetWeb.callAsyncJavaScript("return window.__slatePasswordFill(token,user,password)",arguments:["token":targetToken,"user":user,"password":password],in:targetFrame,in:.defaultClient) { _ in }
    }

    private func fillGenerated(password:String,expected:Int) {
        guard valid(expected), let web, let frame, let token=fieldToken else { return }
        let targetWeb = web
        let targetFrame = frame
        let targetToken = token
        dismiss()
        targetWeb.window?.makeKeyAndOrderFront(nil)
        targetWeb.window?.makeFirstResponder(targetWeb)
        targetWeb.callAsyncJavaScript("return window.__slatePasswordGenerateFill(token,password)",arguments:["token":targetToken,"password":password],in:targetFrame,in:.defaultClient) { _ in }
    }

    static let fieldScript = #"""
    (() => {
      if(window.__slatePasswordFields) return;
      window.__slatePasswordFields=true;
      let active=null, token=null;
      const visible=e=>e && !e.disabled && !e.readOnly && e.getBoundingClientRect().width>0 && e.getBoundingClientRect().height>0;
      const pair=e=>{
        const root=e.form || document;
        const pass=Array.from(root.querySelectorAll('input[type=password]')).find(x=>visible(x)&&!['new-password','one-time-code'].includes(x.autocomplete));
        const fields=Array.from(root.querySelectorAll('input')).filter(visible);
        const before=pass ? fields.slice(0,fields.indexOf(pass)) : fields;
        const candidates=before.filter(x=>['email','text','tel'].includes(x.type)&&x.autocomplete!=='one-time-code');
        const user=candidates.find(x=>x.autocomplete.includes('username')||x.autocomplete.includes('webauthn')) || candidates.find(x=>x.type==='email') || candidates[candidates.length-1];
        return {pass,user};
      };
      const isLoginInput=e=>{
        const ac=(e.autocomplete||'').toLowerCase();
        if(/username|webauthn|email/.test(ac))return true;
        if(e.type==='email')return true;
        if(e.type==='text'||e.type==='tel'){
          const meta=((e.name||'')+' '+(e.id||'')+' '+(e.placeholder||'')).toLowerCase();
          return /\b(user(name)?|email|login|account|identifier|session_key|signin|handle)\b/.test(meta);
        }
        return false;
      };
      function send(body){try{webkit.messageHandlers.slatePasswords.postMessage(body);}catch{}}
      function focused(e){
        if(!(e instanceof HTMLInputElement))return;
        const ac=e.autocomplete||'';
        if(ac==='one-time-code')return;
        if(e.type==='password' && ac==='new-password'){
          active=e;token=Array.from(crypto.getRandomValues(new Uint32Array(4))).join('-');
          const r=e.getBoundingClientRect();
          send({kind:'field',token,passwords:false,generate:true,rect:{x:r.x,y:r.y,w:r.width,h:r.height}});
          return;
        }
        const p=pair(e);
        if(!p.pass && (e.form||document).querySelector('input[autocomplete="new-password"]'))return;
        const loginLike=!p.pass && isLoginInput(e);
        if(e!==p.pass && e!==p.user && !loginLike)return;
        if(!p.pass && !loginLike)return;
        active=e;token=Array.from(crypto.getRandomValues(new Uint32Array(4))).join('-');
        const r=e.getBoundingClientRect();
        send({kind:'field',token,passwords:!!p.pass || loginLike,rect:{x:r.x,y:r.y,w:r.width,h:r.height}});
      }
      document.addEventListener('focusin',event=>focused(event.target),true);
      document.addEventListener('click',event=>{if(event.target instanceof HTMLInputElement)focused(event.target);},true);
      if(typeof requestAnimationFrame==='function'){
        requestAnimationFrame(()=>{if(document.activeElement instanceof HTMLInputElement)focused(document.activeElement);});
      }
      window.__slatePasswordRefresh=()=>{if(active && active.isConnected)focused(active);};
      document.addEventListener('focusout',()=>{setTimeout(()=>{if(document.activeElement!==active){send({kind:'blur'});}},180);},true);
      window.addEventListener('pagehide',()=>{active=null;token=null;send({kind:'blur'});});
      document.addEventListener('keydown',e=>{if(e.key==='Escape')send({kind:'blur'});},true);
      window.__slatePasswordFill=(key,user,password)=>{
        const movedToOtherInput = document.activeElement instanceof HTMLInputElement && document.activeElement !== active;
        if(key!==token || !active || !active.isConnected || movedToOtherInput)return false;
        const p=pair(active);
        const targetUser = p.user || (active.type !== 'password' ? active : null);
        const targetPass = p.pass || (active.type === 'password' ? active : null);
        if(!targetPass && !targetUser)return false;
        const set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
        for(const [field,value] of [[targetUser,user],[targetPass,password]])if(field && value){set.call(field,value);field.dispatchEvent(new Event('input',{bubbles:true}));field.dispatchEvent(new Event('change',{bubbles:true}));}
        return true;
      };
      window.__slatePasswordGenerateFill=(key,password)=>{
        if(key!==token || !active || document.activeElement!==active || !active.isConnected)return false;
        const root=active.form || document;
        const targets=Array.from(root.querySelectorAll('input[type=password]')).filter(x=>visible(x)&&(x===active||x.autocomplete==='new-password'));
        if(!targets.length)targets.push(active);
        const set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
        for(const field of targets){set.call(field,password);field.dispatchEvent(new Event('input',{bubbles:true}));field.dispatchEvent(new Event('change',{bubbles:true}));}
        return true;
      };
    })();
    """#
}
