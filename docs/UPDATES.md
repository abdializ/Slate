# In-app updates

Slate 0.2.0 introduces an in-app updater powered by Sparkle 2.10.1. Users can choose
**Slate → Check for Updates…**, or use the button and automatic-check/download
controls in **Settings → About**. Routine results and errors appear inside
Settings without an OK dialog. Sparkle provides the download, installation, and
relaunch interface when a new version is available.

Automatic checks default to once per day; automatic downloading defaults off.
Sparkle persists the user's choices. The app does not reset those choices on
launch, and system profile reporting is disabled.

## Trust and hosting

The app embeds only the public key in `updates/public-key.txt`. Its private
Ed25519 signing key stays in the local macOS Keychain under account
`dev.slate.browser`; it is never copied into the repository or release files.
Both the appcast and update archive are signed. The app requires signed feeds
and verifies update archives before extracting them.

The production feed is:

`https://github.com/abdializ/Slate/releases/latest/download/appcast.xml`

The first signed release must be published before this feed can serve updates.
A local build alone does not activate the hosted service. Once published, each
subsequent GitHub release must include its signed `appcast.xml` and the matching
`Slate-VERSION.zip`. Users do not download or unpack those archives themselves.

Existing copies from before 0.2.0 need the updater-capable app installed once;
future releases can be installed through Slate. Replacing an app bundle does not
replace its browsing profile. Before installation, Slate saves its session and
UI preferences and uses its existing close path.

## Build and publish

CMake fetches the official Sparkle distribution only when it is not already
available in `third_party/Sparkle-2.10.1`. The archive is pinned by SHA-256 in
`cmake/Sparkle.cmake`. The framework, helper tools, and license are bundled with
the application and use relative runtime paths.

For each release:

1. Bump the project version in `CMakeLists.txt` and choose a greater build number.
2. Configure a production build with `-DSLATE_ENABLE_VERIFY=OFF` and
   `-DSLATE_BUILD_VERSION=NEW_BUILD_NUMBER`, then build the app.
3. Run the preparation command on the Mac whose Keychain holds the signing key:

   ```sh
   python3 scripts/prepare-update.py \
     --app build/platform/macos/Slate.app \
     --output /path/to/empty-release-directory \
     --notes updates/release-notes-0.2.0.md
   ```

4. Review the generated archive and signed appcast. Publish them as assets of the
   matching GitHub release tag, for example `v0.2.0`, and mark that release Latest.

The repository can also publish already signed artifacts through
`.github/workflows/publish-prepared-release.yml`. Commit tested source to main,
then create `release/vVERSION` with a single child commit containing `.release/`
and its `manifest.json`, `Slate-VERSION.zip`, `appcast.xml`, and `notes.md`.
The manifest records `version`, `build`, `source_sha` (the parent commit), and the
archive's `sha256`. The job validates the archive identity, feed, key, versions,
and checksum, uploads assets to a draft release, then publishes it as Latest.
The release tag targets the clean source commit. After publication, the job
verifies that the public archive and signed feed match the prepared files, then
deletes its temporary release branch. It preserves a branch that moved or has an
open pull request. Source remains on main and release tags; downloads remain on
the published release. No private signing key is sent to GitHub. Validate a
prepared payload locally with `scripts/publish-prepared-release.py --root PATH
--validate-only`. Existing releases and tags for other source are not replaced.

The preparation command refuses verification-enabled builds, mismatched public
keys, an incorrect production feed, or overwriting an existing prepared release.
It verifies both generated signatures and the archive's code signature. It never
publishes anything. Do not edit the appcast after signing it. Keep the signing
key protected and backed up through the normal Keychain backup process.

Developer ID distribution builds must sign Sparkle's nested helpers with the same
identity as the host; `scripts/codesign.sh` handles this. Local ad-hoc builds keep
the official Sparkle framework's original signatures.

## Verification

```sh
cmake -S . -B build-verify -DCMAKE_BUILD_TYPE=Release -DSLATE_ENABLE_VERIFY=ON
cmake --build build-verify -j 4
python3 scripts/verify_app_updates.py \
  --app build-verify/platform/macos/Slate.app \
  --log /tmp/slate-updates.log
```

The regression uses unique bundle identifiers, temporary profiles, signed
loopback feeds, and disposable app copies. A quiet test-only user driver performs
checks and installation without opening windows or stealing input focus. It
covers the menu's target/action, actual settings checkboxes, update results,
rejection of a modified feed, signed installation, and preserved profile files.
Other native browser regressions do not start the updater or contact its server.
Loopback feed overrides and the quiet driver are absent from production builds.

References: https://sparkle-project.org/documentation/ and
https://sparkle-project.org/documentation/programmatic-setup/

## Signed sandboxed builds

As of 0.4.1, signing enables Sparkle's Installer XPC service exactly when the
host's signed entitlements enable App Sandbox. The host grants lookup only for
`com.apple.PIPAgent`, `dev.slate.browser-spki`, and `dev.slate.browser-spks`.
The PiP route is required for WebKit's native PiP window; the latter two are
Sparkle's installer/status channels. Preparation inspects the effective signed
entitlements and rejects a release missing these routes or an inconsistent
installer-service setting. `macos_media_service_permissions` checks the real
macOS permission boundary in isolated signed probe apps.
