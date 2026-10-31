# PiP service access regression in 0.4

The user reported that all sites froze on a still picture on entering PiP while
audio continued. The PiP, media-monitor and WebKit navigation source was unchanged
from 0.3. The installed binaries differed: 0.3 was ad-hoc signed without App
Sandbox entitlements; 0.4 was signed with a development identity and attached the
source App Sandbox entitlements for the first time. That entitlement set omitted
the system PiP service. The signed test below reproduces the resulting denial.

`macos_media_service_permissions` signs two disposable apps with App Sandbox.
With the old policy, `mach-lookup` for `com.apple.PIPAgent` is denied and
`bootstrap_look_up` returns 1100. With the corrected policy, access is allowed and
the bootstrap connection succeeds. Both remain sandboxed, and an unrelated Mach
service remains denied. The test does not open a video window, use a site account
or interrupt the user's running browser. It verifies the service connection;
visual playback in the user's PiP window is checked after restarting the app.

The permission list is limited to the PiP service and Slate's own Sparkle
installer/status channels. No global wildcard, JIT, unsigned memory, disabled
library validation, or filesystem exception is introduced. WebKit's child process
sandbox and Slate's host App Sandbox stay enabled in signed releases.

The same change in signing mode exposed the missing Sparkle installer routes in
0.4 logs. The signing script now sets `SUEnableInstallerLauncherService` according
to the effective host sandbox mode. Ad-hoc builds and disposable updater fixtures
leave that service disabled; sandboxed signed builds enable it and carry their
own `-spki` and `-spks` lookup permissions. The release preparation command reads
the actual signature and rejects missing service routes or an inconsistent
installer-service setting. Entitlement changes also cause packaging and signing
to run again.

References:
- WebKit MiniBrowser's PiP entitlement: https://github.com/WebKit/WebKit/blob/main/Tools/MiniBrowser/MiniBrowser.entitlements
- Sparkle's sandbox integration: https://sparkle-project.org/documentation/sandboxing/
