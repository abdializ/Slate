# Slate 0.4.14

- Add High-Alert Privacy & Security defaults: native WebKit EasyList/EasyPrivacy ad & tracker blocker, URL tracker stripping (`utm_*`, `fbclid`, `gclid`, etc.), Global Privacy Control + DNT, HTTPS-Only Mode, and automatic WebRTC IP-leak blocking in Incognito tabs.
- Add native Incognito VPN / Proxy Tunnel in Settings › Privacy (powered by macOS 14+ `Network.framework` `WKWebsiteDataStore.proxyConfigurations`) supporting Tor (`127.0.0.1:9050`), custom SOCKS5 VPN/proxy endpoints (Mullvad, Proton, SSH, etc.), HTTP CONNECT proxies, Keychain-stored credentials, a Fail-Closed Kill Switch, and a live tunnel connectivity test.

Restart Slate after updating.
