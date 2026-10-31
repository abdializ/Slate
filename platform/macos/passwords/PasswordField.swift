import AppKit
import WebKit

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
    private var actions: [() -> Void] = []
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
    func install() {
        guard let web else { return }
        let controller=web.configuration.userContentController
        // A popup can inherit its parent's configuration: remove inherited handlers
        // before installing the handler owned by this view.
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
        actions=[];fieldToken=nil;frame=nil;origin=nil
    }
    func popoverDidClose(_ notification:Notification) { dismiss() }
    private func valid(_ expected:Int) -> Bool {
        guard generation == expected, let web, (web.window?.isKeyWindow == true || popover?.contentViewController?.view.window?.isKeyWindow == true), NSApp.isActive,
              web.url == committedURL, !web.isHiddenOrHasHiddenAncestor, fieldToken != nil else { return false }
        return true
    }
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard let web, message.webView === web, let body=message.body as? [String:Any] else { return }
        if body["kind"] as? String == "blur" { dismiss();fieldToken=nil;return }
        guard SlatePasswordServices.autofillEnabled, NSApp.isActive, web.window?.isKeyWindow == true,
              !web.isHiddenOrHasHiddenAncestor, !privateTab,
              let page=committedURL, page.scheme == "https", web.url == page,
              let pageHost=page.host?.lowercased(), !pageHost.isEmpty,
              message.frameInfo.securityOrigin.protocol.lowercased() == "https",
              Registrable.sameSite(pageHost,message.frameInfo.securityOrigin.host.lowercased()),
              let token=body["token"] as? String, token.count <= 128,
              let rect=body["rect"] as? [String:Double], let x=rect["x"],let y=rect["y"],let w=rect["w"],let h=rect["h"],
              [x,y,w,h].allSatisfy({$0.isFinite}),w>0,h>0 else { return }
        // Same-site frames may fill after an explicit selection. Positioning a
        // nested frame can't be trusted from page-supplied geometry; anchor its
        // suggestions to the containing view's top edge instead.
        dismiss()
        frame=message.frameInfo;fieldToken=token
        var components=URLComponents();components.scheme="https";components.host=message.frameInfo.securityOrigin.host.lowercased()
        if message.frameInfo.securityOrigin.port != 0 && message.frameInfo.securityOrigin.port != 443 { components.port=message.frameInfo.securityOrigin.port }
        guard let origin=components.url else { return };self.origin=origin
        let passwords=body["passwords"] as? Bool ?? false
        let all=accounts(origin)
        let matching=(all ?? []).filter { Self.sameOrigin(URL(string:$0["origin"] ?? ""),origin) }
        var rows:[(String,()->Void)]=[]
        let expected=generation
        if passwords && all == nil {
            rows.append(("Unlock Slate passwords…",{ [weak self] in
                guard let self,self.valid(expected),self.unlock(),let web=self.web,let frame=self.frame else { return }
                web.callAsyncJavaScript("window.__slatePasswordRefresh?.()",arguments:[:],in:frame,in:.defaultClient) { _ in }
            }))
        }
        for item in passwords ? matching.prefix(8) : [] {
            guard let id=item["id"] else { continue }
            rows.append((item["user"].flatMap{$0.isEmpty ? nil : $0} ?? "No username",{ [weak self] in
                guard let self, self.valid(expected), let found=self.select(id,origin), let user=found["user"],let password=found["password"] else { return }
                self.fill(user:user,password:password,expected:expected)
            }))
        }
        if #available(macOS 14.4,*) {
            for found in Passkeys.shared.offered(in:web) {
                rows.append((found.name + " · Passkey",{ [weak self,weak web] in
                    guard let self, self.valid(expected),let web else { return }
                    self.dismiss();Passkeys.shared.sign(in:web,with:found.id)
                }))
            }
        }
        let kept=all?.filter { item in URL(string:item["origin"] ?? "").flatMap(\.host).map { Registrable.sameSite(pageHost,$0) } ?? false }.count ?? 1
        let field=ApplePasswordsOffer.Field(page:page,privateTab:privateTab,frameHost:message.frameInfo.isMainFrame ? nil : components.host,passwords:passwords,kept:kept)
        let settings=ApplePasswordsOffer.Settings(appleOn:SlatePasswordServices.appleEnabled,fills:true,helper:ApplePasswordsOffer.helperHere,testRun:Store.testing,benchAsks:ApplePasswordsOffer.benchAsks)
        if let site=offer.site(for:field,settings) {
            pendingSite=site
            rows.append(("Use your Apple passwords?",{ [weak self] in
                guard let self,self.valid(expected) else { return }
                self.offerOutstanding=false;self.dismiss();SlatePasswordServices.shared.connect(from:web.window)
            }))
        } else if passwords && SlatePasswordServices.appleEnabled && ApplePasswordsOffer.helperHere {
            if ApplePasswords.shared.state != .paired {
                rows.append(("Connect Apple Passwords…",{ [weak self] in
                    guard let self,self.valid(expected) else { return };self.dismiss();SlatePasswordServices.shared.connect(from:web.window)
                }))
            } else {
                Task { [weak self] in
                    guard let self else { return }
                    let found=await ApplePasswords.shared.logins(for:components.host!,tab:self.tab,wanted:{ [weak self] in self?.valid(expected) ?? false })
                    guard self.valid(expected) else { return }
                    let own=found.filter { ApplePasswords.belongs($0.sites,to:components.host!) }
                    let extra:[(String,()->Void)]=own.prefix(8).map { login in
                        (login.user + " · Apple Passwords", { [weak self] in self?.selectApple(login,host:components.host!,expected:expected) })
                    }
                    if !extra.isEmpty { self.show(rows:rows + extra,rect:message.frameInfo.isMainFrame ? NSRect(x:x,y:y,width:w,height:h) : NSRect(x:12,y:0,width:240,height:24)) }
                }
            }
        }
        if !rows.isEmpty { show(rows:rows,rect:message.frameInfo.isMainFrame ? NSRect(x:x,y:y,width:w,height:h) : NSRect(x:12,y:0,width:240,height:24)) }
    }
    static func sameOrigin(_ a:URL?,_ b:URL) -> Bool {
        guard let a else { return false }
        return a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased() && (a.port ?? 443) == (b.port ?? 443)
    }
    private func show(rows:[(String,()->Void)],rect:NSRect) {
        guard let web, !rows.isEmpty else { return }
        if let shown=popover { shown.delegate=nil;shown.close() }
        let pop=NSPopover();pop.behavior = .semitransient;pop.delegate=self
        let controller=NSViewController();let content=NSView(frame:NSRect(x:0,y:0,width:340,height:CGFloat(rows.count)*32+12))
        actions=rows.map(\.1)
        for (index,row) in rows.enumerated() {
            let button=NSButton(title:row.0,target:self,action:#selector(pick(_:)));button.tag=index
            button.isBordered=false;button.alignment = .left;button.font = .systemFont(ofSize:12)
            button.frame=NSRect(x:10,y:content.frame.height-CGFloat(index+1)*32-2,width:row.0 == "Use your Apple passwords?" ? 286 : 320,height:30);content.addSubview(button)
            if row.0 == "Use your Apple passwords?" {
                let stop=NSButton(title:"×",target:self,action:#selector(dontOffer));stop.isBordered=false
                stop.toolTip="Don’t offer Apple Passwords again";stop.setAccessibilityLabel("Don’t offer Apple Passwords again")
                stop.frame=NSRect(x:302,y:button.frame.minY,width:28,height:30);content.addSubview(stop)
            }
        }
        controller.view=content;pop.contentViewController=controller;popover=pop
        let anchor=web.isFlipped ? rect : NSRect(x:rect.minX,y:web.bounds.height-rect.maxY,width:rect.width,height:rect.height)
        let clipped=anchor.intersection(web.bounds)
        guard !clipped.isNull,!clipped.isEmpty else { popover=nil;return }
        pop.show(relativeTo:clipped,of:web,preferredEdge:.maxY)
        if pop.isShown, let site=pendingSite { offer.shown(on:site);offerOutstanding=true;pendingSite=nil }
    }
    @objc private func dontOffer() { offerOutstanding=false;offer.dismissed();dismiss() }
    @objc private func pick(_ sender:NSButton) { guard actions.indices.contains(sender.tag) else { return };let action=actions[sender.tag];action() }
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
        guard valid(expected), let web,let frame,let token=fieldToken else { return }
        web.callAsyncJavaScript("return window.__slatePasswordFill(token,user,password)",arguments:["token":token,"user":user,"password":password],in:frame,in:.defaultClient) { _ in }
        dismiss()
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
      function send(body){try{webkit.messageHandlers.slatePasswords.postMessage(body);}catch{}}
      function focused(e){
        if(!(e instanceof HTMLInputElement))return;
        const p=pair(e), ac=e.autocomplete||'';
        if(!p.pass && (e.form||document).querySelector('input[autocomplete="new-password"]'))return;
        if(e!==p.pass && e!==p.user)return;
        if(!p.pass && !/username|webauthn/.test(ac))return;
        active=e;token=Array.from(crypto.getRandomValues(new Uint32Array(4))).join('-');
        const r=e.getBoundingClientRect();
        send({kind:'field',token,passwords:!!p.pass || ac.includes('username'),rect:{x:r.x,y:r.y,w:r.width,h:r.height}});
      }
      document.addEventListener('focusin',event=>focused(event.target),true);
      window.__slatePasswordRefresh=()=>{if(active===document.activeElement)focused(active);};
      document.addEventListener('focusout',()=>{setTimeout(()=>{if(document.activeElement!==active){active=null;token=null;send({kind:'blur'});}},150);},true);
      window.addEventListener('pagehide',()=>{active=null;token=null;send({kind:'blur'});});
      document.addEventListener('keydown',e=>{if(e.key==='Escape')send({kind:'blur'});},true);
      window.__slatePasswordFill=(key,user,password)=>{
        if(key!==token || !active || document.activeElement!==active || !active.isConnected)return false;
        const p=pair(active);if(!p.pass && !p.user)return false;
        const set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
        for(const [field,value] of [[p.user,user],[p.pass,password]])if(field){set.call(field,value);field.dispatchEvent(new Event('input',{bubbles:true}));field.dispatchEvent(new Event('change',{bubbles:true}));}
        return true;
      };
    })();
    """#
}
