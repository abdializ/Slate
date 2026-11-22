# Slate 0.4.18

- Fix Twitch streams stalling on the loading spinner: preserve native `Response.url` (and return unmodified `Response` objects when no stitched ads are present), delay revoking wrapped Blob Worker URLs so `importScripts()` never hits a revoked URL, and skip module workers.

Restart Slate after updating.
