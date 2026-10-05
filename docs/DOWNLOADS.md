# Slate downloads redesign

The downloads shelf uses native AppKit controls, macOS file icons, a visual-effect panel, search, and All / Active / Finished filters. Open it with the toolbar button or Command-J. Escape closes it; Command-F focuses search. Completed files open on double-click and can be revealed in Finder.

Downloads show transferred bytes, speed, estimated time when available, and honest failure messages. Transfers can be cancelled or paused and resumed where WebKit, the source tab, and the website support resumption. Resume data stays in memory; interrupted transfers are shown as cancelled after a restart. Large file copying and publication run off the main thread.

Files are staged until fully written, verified as regular files, marked with macOS quarantine, and published atomically without replacing existing files. Name collisions receive numbered names. Unsafe filename controls are removed, long filenames retain their extension, and symlink replacements cannot be opened from the shelf. Files never open automatically. These protections do not constitute malware scanning.

Private downloads use their originating website session and are excluded from saved history. Downloaded files still remain in the selected folder. Clearing history removes records, not files. Each transfer retains the download folder selected when it started, including when switching Spaces. Saved source URLs omit embedded credentials.

Validation: native lifecycle/security tests cover publication, quarantine, permissions, collisions, symlinks, cancellation, private history, filename sanitization, and folder retention. Local integration checks exercised WebKit and URL-session transfers, pause/resume, cancellation, private-session authentication, HTTP errors, search/filter empty states, and full-screen geometry.

This is the existing development build with ad-hoc signing. Release signing, notarization, and application sandbox distribution configuration remain separate deployment work.
