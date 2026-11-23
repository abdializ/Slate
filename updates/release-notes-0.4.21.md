# Slate 0.4.21

- **Fix Twitch videos & live streams failing to play:**
  - Stopped injecting synthetic `postMessage` metadata into Twitch's IVS WASM Web Worker (which poisoned the worker's message handler).
  - Scoped Worker wrapping exclusively to Twitch's IVS player worker with flat inline source instead of wrapping every `blob:` Worker via nested `importScripts('blob:...')`.
  - Removed the main-thread `gql.twitch.tv/gql` `fetch` hijack that could break batched GraphQL playback token requests.
