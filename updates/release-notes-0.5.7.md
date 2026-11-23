# Slate 0.5.7

## Fixes
- Fixed file downloads silently cancelling across websites (including Google Docs, Google Drive, PDFs, Word documents, and general downloads) caused by assigning `WKDownload.delegate` before registering the download in `SlateDownloadManager`.
- Fixed `Content-Disposition: attachment` responses (such as Google Docs PDF exports) being swallowed as inline PDFs instead of triggering a download.
- Added WebKit context-menu download handling (`Download Linked File`), popup-link download handling (`<a download target="_blank">`), and explicit HTTP/HTTPS download redirect handling.
- Resolved sandboxed Downloads staging paths via `realpath` and auto-registered fallback downloads in `decideDestinationUsingResponse:` so downloads never silently drop.
