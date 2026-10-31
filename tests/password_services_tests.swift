import Foundation
import CryptoKit
import WebKit

func check(_ value: @autoclosure () -> Bool,_ message:String) { if !value(){ fatalError(message) } }
func fails(_ message:String,_ work:()throws->Void) { do{try work();fatalError(message)}catch{} }

@MainActor final class FakeAppleLink: AppleLink {
    var onMessage: (([String:Any])->Void)?
    var onEnd: (()->Void)?
    var starts=0, stops=0
    private var tid=""
    func start()throws { starts += 1 }
    func stop(){stops += 1}
    func send(_ message:[String:Any])throws {
        let command=message["cmd"] as! Int
        if command==14 { onMessage?(["cmd":14,"capabilities":["secretSessionVersion":1,"shouldUseBase64":true]]);return }
        guard command==2,let text=message["msg"] as? String,
              let outer=try JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any],
              let encoded=outer["PAKE"] as? String,let data=Data(base64Encoded:encoded),
              let pake=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
        tid=pake["TID"] as! String
        let reply:[String:Any]
        if pake["MSG"] as? Int == 0 { reply=["TID":tid,"MSG":1,"PROTO":1,"B":Data([2]).base64EncodedString(),"s":Data([1]).base64EncodedString()] }
        else { reply=["TID":tid,"MSG":3,"ErrCode":1] }
        let body=try JSONSerialization.data(withJSONObject:reply).base64EncodedString()
        onMessage?(["cmd":2,"payload":["PAKE":body]])
    }
}

@main struct PasswordServicesTests {
    @MainActor static func main() async throws {
        let root=CommandLine.arguments[1]
        let artifacts=CommandLine.arguments[2]
        try FileManager.default.createDirectory(atPath:artifacts,withIntermediateDirectories:true)
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:root+"/tests/fixtures/apple_passwords_vectors.json"))) as! [String:String]
        let client=SRPClient(base64:true,random:{ count in (0..<count).map{UInt8($0)} })
        check(client.tid==fixture["tid"],"Session wire encoding")
        check(Data(client.publicKey.bytes).hexString==fixture["publicKey"],"3072-bit modular exponent")
        let proof=try client.prove(serverKey:Array(Data(hexString:fixture["serverKey"]!)!),salt:Array(Data(hexString:fixture["salt"]!)!),code:"123456")
        check(Data(proof.m).hexString==fixture["proof"],"SRP client proof vs independent Python vector")
        check(Data(proof.expected).hexString==fixture["serverProof"],"SRP server proof")
        check(proof.key.withUnsafeBytes{Data($0).hexString}==fixture["aesKey"],"AES session key")
        fails("Refuse zero server key"){_ = try client.prove(serverKey:[0],salt:[1],code:"123456")}
        fails("Refuse out-of-range server key"){_ = try client.prove(serverKey:SRPClient.group.bytes,salt:[1],code:"123456")}
        fails("Refuse empty salt"){_ = try client.prove(serverKey:[2],salt:[],code:"123456")}
        let key=SymmetricKey(data:Data(repeating:7,count:16)),iv=[UInt8](repeating:4,count:16),plain=Data("sealed fixture".utf8)
        let outgoing=try SecretChannel.seal(plain,key:key,iv:iv)
        check(Array(outgoing.suffix(16))==iv,"Outgoing IV is last")
        let incoming=iv + outgoing.dropLast(16)
        let opened = try SecretChannel.open(Array(incoming),key:key)
        check(opened==plain,"AES-GCM opposite direction")
        var altered=Array(incoming);altered[17] ^= 1
        fails("Authenticate ciphertext"){_ = try SecretChannel.open(altered,key:key)}
        fails("Refuse truncated ciphertext"){_ = try SecretChannel.open([1],key:key)}
        let login=try AppleMessages.readLoginNames(["STATUS":0,"Entries":[["USR":"me","sites":["example.com"]],["USR":"Passwords not saved"]]])
        check(login.count==1 && login[0].user=="me","Names only and never-save sentinel")
        let other = try AppleMessages.readPassword(["STATUS":0,"Entries":[["USR":"other","PWD":"secret"]]],user:"me")
        check(other==nil,"A different account cannot fill")
        let suite="dev.slate.password-tests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let offer=ApplePasswordsOffer(store:defaults)
        let field=ApplePasswordsOffer.Field(page:URL(string:"https://login.example.com/signin"),privateTab:false)
        var settings=ApplePasswordsOffer.Settings(helper:true)
        check(offer.site(for:field,settings)=="example.com","Registrable offer site")
        for i in 0..<8 {
            var f=field;var s=settings
            switch i {case 0:f.privateTab=true;case 1:f.page=URL(string:"http://example.com");case 2:f.frameHost="attacker.com";case 3:f.passwords=false;case 4:f.kept=1;case 5:s.appleOn=true;case 6:s.fills=false;default:s.helper=false}
            check(offer.site(for:f,s)==nil,"Offer eligibility rule \(i)")
        }
        settings.testRun=true;check(offer.site(for:field,settings)==nil,"No offers during tests")
        settings.benchAsks=true;check(offer.site(for:field,settings) != nil,"Explicit offer bench")
        settings.testRun=false
        var same=field;same.frameHost="accounts.example.com"
        check(offer.site(for:same,settings)=="example.com","Same-site frame")
        offer.shown(on:"example.com");offer.shown(on:"example.com")
        check(offer.offered.count==1 && offer.site(for:field,settings)==nil,"At most once per site")
        offer.unanswered();check(!offer.retired,"One unanswered is not retired")
        offer.unanswered();check(offer.retired,"Two unanswered retire the offer")
        offer.forget();check(!offer.retired && offer.offered.isEmpty,"Reset test suite")
        offer.dismissed();check(offer.retired,"Cross dismisses permanently")
        check(Vault.registrable("a.example.co.uk")=="example.co.uk","Public suffix multi-label boundary")
        check(!Registrable.sameSite("a.github.io","b.github.io"),"Private suffix isolation")
        check(!ApplePasswords.belongs(["evil-example.com"],to:"example.com"),"Related-looking sites stay separate")
        check(ApplePasswords.belongs(["https://accounts.example.com/login"],to:"login.example.com"),"Same registrable site")
        check(!AppleHelper.isApples(URL(fileURLWithPath:root)),"Unsigned helper refused")
        let mark=AppleFill(host:"example.com",user:"me",password:"ephemeral")
        check(mark.matches(host:"www.example.com",user:"me",password:"ephemeral"),"HMAC recognizes Apple fill")
        check(!mark.matches(host:"evil.com",user:"me",password:"ephemeral"),"HMAC does not cross sites")
        let fake=FakeAppleLink(),apple=ApplePasswords(makeLink:{fake})
        await apple.connect();check(apple.state == .code && fake.starts==1,"Explicit click starts injected helper")
        await apple.enter("000000");check(apple.state == .idle && apple.trouble  !=  nil,"Wrong code never pairs")
        await apple.connect();check(apple.state == .code,"Can reconnect after wrong code")
        let pending=Task{await apple.enter("123456")}
        while apple.state == .code { await Task.yield() }
        apple.disconnect()
        await apple.connect()
        await pending.value
        check(apple.state == .code,"An old detached proof cannot overwrite a new pairing")
        apple.disconnect();check(apple.state == .idle,"Disconnect clears the session")
        let real=ApplePasswords();await real.connect()
        check(real.state == .idle && real.trouble  !=  nil,"Tests cannot launch Apple's real helper")
        if #available(macOS 14.4,*) {
            check(Passkeys.fits("example.com","login.example.com"),"RP registrable suffix")
            check(!Passkeys.fits("co.uk","example.co.uk"),"RP public suffix refused")
            check(!Passkeys.fits("github.io","account.github.io"),"RP private suffix refused")
            check(!Passkeys.fits("other.com","example.com"),"RP cross-site refused")
            let page=P256.KeyAgreement.PrivateKey(),first=SymmetricKey(data:Data(repeating:9,count:32))
            let reply=Passkeys.prfReply(enabled:true,first:first,second:nil,for:page.publicKey)
            let sealed=reply["sealed"] as! [String:String]
            let peer=try P256.KeyAgreement.PublicKey(x963Representation:Passkeys.data(sealed["key"])!)
            let shared=try page.sharedSecretFromKeyAgreement(with:peer)
            let key=shared.hkdfDerivedSymmetricKey(using:SHA256.self,salt:Data(),sharedInfo:Data("slate-prf".utf8),outputByteCount:32)
            let decoded=try AES.GCM.open(AES.GCM.SealedBox(combined:Passkeys.data(sealed["box"])!),using:key)
            check(!decoded.isEmpty,"PRF is sealed for request's one-time key")
            check(Passkeys.prfReply(enabled:true,first:first,second:nil,for:nil)["sealed"]==nil,"No unencrypted PRF fallback")
            try PasskeyRelay.page.write(toFile:artifacts+"/password-page-test.js",atomically:true,encoding:.utf8)
        }
        try SlatePasswordContext.fieldScript.write(toFile:artifacts+"/password-field-test.js",atomically:true,encoding:.utf8)
        print("Password offer policy, independent SRP vectors, authenticated messages, pairing lifecycle, site boundaries, and PRF checks passed.")
    }
}
