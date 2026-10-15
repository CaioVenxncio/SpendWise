# Hosting and browser origins

**Status:** prepared, not deployed. No production domain is chosen or
hard-coded.

## Recommended setup

A static host that serves HTTPS and reads a `_headers` file, such as
Cloudflare Pages or Netlify. `web/_headers` is copied into `build/web` by
`flutter build web` and contains:

| Header | Value | Why |
|---|---|---|
| `Cross-Origin-Opener-Policy` | `same-origin` | cross-origin isolation |
| `Cross-Origin-Embedder-Policy` | `require-corp` | with COOP, lets Drift use the tab-safe OPFS mode (`opfsLocks`) |
| `X-Content-Type-Options` | `nosniff` | |
| `Referrer-Policy` | `no-referrer` | |
| `Permissions-Policy` | camera, microphone, geolocation, payment, usb disabled | |
| `Cache-Control` | `no-cache` | Flutter's `main.dart.js` is not content-hashed; revalidating keeps tabs from running an outdated version against newer data |
| `Content-Type` for `*.wasm` | `application/wasm` | required by browsers for `sqlite3.wasm` and CanvasKit |

Build command (production):

```
flutter build web --release --no-web-resources-cdn
```

`--no-web-resources-cdn` bundles CanvasKit and fonts, so the app makes
**no third-party requests**. This is also what makes `require-corp` safe:
COEP blocks cross-origin resources that do not opt in.

**Verified locally** (Vivaldi, Windows; a local server applying exactly
`web/_headers`; HTTP on 127.0.0.1, which browsers treat as a secure
context): the default and Drift builds were cross-origin isolated, made
zero third-party requests, `.wasm` was served as `application/wasm`, Drift
chose `opfsLocks`, and the default build never fetched the SQLite assets.
**Not verified:** a real host, HTTPS certificates, CDNs in front of it, other
browsers.

**SPA routing:** not needed today. The app uses no URL paths (all
navigation is in-app), so every request is for `/` or a static file. If
path-based routes are added later, add a rewrite of `/*` to `/index.html`.

**Content Security Policy:** a draft is in [csp.md](csp.md), tested
locally in Vivaldi with the default and Drift builds (0 violations). It is
**not** in `web/_headers` yet; it needs `'wasm-unsafe-eval'` and, because
the Flutter engine injects an inline `<style>`, `style-src
'unsafe-inline'`. Validate it on the real host before adding it.

**Without COOP/COEP** (e.g. a host that cannot set headers): Drift uses
`sharedIndexedDb` on desktop Chromium (verified, safe across tabs, slower),
but **Chrome on Android falls back to `unsafeIndexedDb`** (per Drift's
documentation; not verified here). SpendWise refuses to migrate in that
mode.

## Origins: why the address matters

Browser storage (localStorage, IndexedDB, the origin-private file system)
belongs to an **origin**: scheme + host + port. Each of these is a
different origin with completely separate data:

* `http://localhost:53817` and `http://localhost:60211` (two
  `flutter run` sessions on different ports)
* `http://127.0.0.1:8080` and `http://localhost:8080`
* `https://spendwise.example` and `https://www.spendwise.example`
* `https://user.github.io/spendwise` and `https://spendwise.example`

Consequences:

* **Development vs. production:** data entered while developing never
  appears in the deployed app, and vice versa. Use a fixed port
  (`flutter run -d chrome --web-port 8080`) to keep a stable development
  origin.
* **Changing the hosting domain later** leaves every user's expenses
  behind on the old origin. They are not lost, but the new address cannot
  see them, and a user who clears the old site's data loses them.
* Nothing moves data between origins automatically, by design: browsers
  isolate origins for privacy.

### Moving data to a new origin

1. Open SpendWise at the **old** address.
2. Menu ⋮ → **Export backup** (or, if it cannot load, **Export raw data**).
3. Keep the file private; it contains personal financial information.
4. Open SpendWise at the **new** address → menu ⋮ → **Import backup** →
   review the preview → confirm.
5. Check the new address, then (optionally) clear the old site's data.

Choose the final domain before the first public release to avoid this.

## Privacy of runtime requests

A Flutter Web build made **without** `--no-web-resources-cdn` downloads
CanvasKit from `www.gstatic.com` and fonts from `fonts.gstatic.com` on
every visit. Those requests reveal to a third party that someone opened
the app (IP address, time, browser), though not the expenses. The
production build above makes none. Backups and exports are created in the
browser and saved by its download mechanism; nothing is uploaded.
