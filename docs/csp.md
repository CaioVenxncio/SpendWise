# Content Security Policy (draft)

**Status:** draft, tested locally only. It is **not** in `web/_headers`
and is not served by any build yet. Add it there only after it has been
checked on the real host (see [hosting.md](hosting.md)).

## Recommended draft

```
Content-Security-Policy: default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'; img-src 'self' data: blob:; font-src 'self'; style-src 'self' 'unsafe-inline'; manifest-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'; object-src 'none'
```

It must apply to **every** response (`/*`), including `drift_worker.js`:
a worker enforces the policy of its own script response, and the worker
needs `'wasm-unsafe-eval'` to compile `sqlite3.wasm`.

| Directive | Value | Why |
|---|---|---|
| `default-src` | `'none'` | everything not listed is blocked |
| `script-src` | `'self' 'wasm-unsafe-eval'` | `flutter_bootstrap.js`, `main.dart.js`, `canvaskit.js`; `'wasm-unsafe-eval'` lets CanvasKit and `sqlite3.wasm` compile. No `'unsafe-eval'`, no `'unsafe-inline'` |
| `worker-src` | `'self'` | `drift_worker.js` (dedicated and shared worker) |
| `connect-src` | `'self'` | fetches of `.wasm`, fonts, `FontManifest.json`, assets |
| `img-src` | `'self' data: blob:` | icons; `data:`/`blob:` for images Flutter may decode |
| `font-src` | `'self'` | bundled fonts (`--no-web-resources-cdn`) |
| `style-src` | `'self' 'unsafe-inline'` | see below |
| `manifest-src` | `'self'` | `manifest.json` |
| `base-uri` | `'self'` | `<base href>` cannot be redirected elsewhere |
| `form-action` | `'none'` | the app submits no HTML forms |
| `frame-ancestors` | `'none'` | cannot be framed (clickjacking) |
| `object-src` | `'none'` | no plugins |

Backup downloads use `blob:` URLs on an `<a download>` link. CSP does not
govern downloads, so no extra directive is needed (not re-tested with the
CSP applied; see "Not verified").

## Why `style-src 'unsafe-inline'`

With `style-src 'self'`, Chromium blocked one inline `<style>` element
created by the Flutter engine at startup (`main.dart.js`, the global rules
for `flt-scene-host`, semantics inputs, text selection, focus outline). The
app still rendered, but those rules were lost.

The safer alternatives do not fit a static host today:

* **Nonce:** the engine supports one (`engineInitializer` config `nonce`),
  but a nonce must be random per response. A static host cannot generate
  it; a fixed nonce gives no protection. Possible later with an edge
  function (e.g. Cloudflare Pages Functions, Netlify Edge) that rewrites
  `index.html` per request.
* **Hashes:** the stylesheet text differs by browser engine and user agent
  (extra rules for WebKit, Firefox, Edge) and is built from several text
  appends, so it would need many hashes that change with every Flutter
  upgrade. Fragile.

Risk of `'unsafe-inline'` for **styles only**: injected CSS cannot run
scripts; it could at most change how the page looks or leak data through
CSS selectors with URLs, which `img-src`/`connect-src`/`font-src` limited
to `'self'` already stop. Scripts stay strict.

## Trusted Types: not compatible with the Drift build yet

Adding `require-trusted-types-for 'script'; trusted-types flutter-js`
worked for the **default (JSON) build** (0 violations; the Flutter loader
creates its own `flutter-js` policy). In the **Drift build** it blocked the
`Worker` and `SharedWorker` constructors (Drift passes a plain string URL
for `drift_worker.js`), and Drift fell back to `inMemory` storage. The
app's existing safety rule then showed the temporary-storage warning and
would refuse a migration, so this failed safely, but Drift was unusable.

Trusted Types is therefore **not** in the draft. Revisit if Drift accepts a
`TrustedScriptURL`, or the app adds a policy for `drift_worker.js`.

## Local test (2026-10-15, M2 post-4B checkpoint)

Vivaldi 8.2 (Chromium 152), Windows 10. A development-only static server
from the session scratchpad (not in the repository) applied `web/_headers`
plus the policy under test, and logged CSP violation reports
(`report-uri`, added only for testing). Fresh origins with test data only.

| Port | Build | Policy | Result |
|---|---|---|---|
| 8821 | default | strict (`style-src 'self'`) | renders; **1 violation**: engine inline `<style>` |
| 8823 | default | draft + Trusted Types | **0 violations**; add expense (`12,50` → $12.50), menu, *Storage information* dialog, reload keeps data; cross-origin isolated; only own-origin requests; no `sqlite3.wasm` fetched; no console errors |
| 8824 | Drift `qacsp` | draft + Trusted Types | **2 violations** (`Worker`, `SharedWorker` constructors) → `inMemory` fallback and warning |
| 8825 | Drift `qacsp` | **recommended draft** | **0 violations**; Drift chose OPFS with cross-tab locks (`opfsLocks`); seeded test records (one legacy `19.99`) → migration screen with correct preview (2 records, $32.49); `drift_worker.js` and `sqlite3.wasm` loaded from own origin; cross-origin isolated; no console errors |

The default build passing the draft **plus** Trusted Types implies it
passes the recommended draft (a subset of those restrictions).

Browser extensions inject their own styles; extension content is not
subject to the page's CSP and did not produce reports.

### Not verified

* Completing a migration, *Download backup*, *Export backup*, *Export raw
  data* and *Import backup* with the CSP applied (these save or pick
  files; not run in this check).
* Any browser other than Vivaldi; a real host over HTTPS; `<meta>`-tag
  delivery (not recommended: `frame-ancestors` and reporting do not work
  in `<meta>`).
* Behaviour when a CDN or host adds its own headers or scripts (for
  example analytics injection), which this policy would block.

## Before release

1. Re-run the table above on the chosen host over HTTPS, with
   `Content-Security-Policy-Report-Only` first, then enforced.
2. Run the file-based flows (backup, import, exports, migration) with the
   policy enforced.
3. Repeat in Firefox and on Android Chrome.
4. Then add the line to the `/*` block of `web/_headers` and add a CI check
   that it is present in `build/web/_headers`.
