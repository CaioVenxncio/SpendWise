# Manual testing checklist

Manual browser checks for SpendWise 2.0. Automated tests (`flutter test`)
cover the logic; this list covers what only a real browser can show.

**Status legend**

| Mark | Meaning |
|---|---|
| ✅ | performed manually and recorded (browser and stage given) |
| 🤖 | covered by automated tests only; no manual run recorded |
| ⏳ | pending |
| ⛔ | NOT TESTED — Deferred by project owner (date given); neither a pass nor a defect |

"Recorded" means listed in `DEVELOPMENT_HANDOFF.md` or this file. A check
that may have been done but was not written down is marked ⏳.

## Rules for every session

* Use **test data only**. Never open a test build on an origin that holds
  real expenses, and never point a Drift build at the real `expenses` key:
  always build with `SPENDWISE_NAMESPACE=<ns>`.
* Use a fixed, dedicated origin per scenario (`127.0.0.1:<port>`); each
  port is separate storage. Write the port down.
* Serve builds through a server that applies `web/_headers` (see
  [hosting.md](hosting.md)); `flutter run` does not send those headers.
* Open DevTools → Console and Network before starting. Any CSP violation,
  uncaught error, or request to another host is a failure.
* Record date, browser and version, build command, origin, and result.

## Builds

```powershell
# Default (JSON) build
flutter build web --release --no-web-resources-cdn -o build/m_default

# Drift build, isolated namespace (never without a namespace)
flutter build web --release --no-web-resources-cdn --dart-define=SPENDWISE_BACKEND=drift --dart-define=SPENDWISE_NAMESPACE=<ns> -o build/m_<ns>

# Drift build without a namespace (must refuse to start)
flutter build web --release --no-web-resources-cdn --dart-define=SPENDWISE_BACKEND=drift -o build/m_refused
```

## 1. Fresh installation

| # | Check | Expected | Status |
|---|---|---|---|
| 1.1 | Default build on an unused origin | empty list, total $0.00, no error | ✅ Vivaldi 8.2, post-4B checkpoint (CSP draft applied) |
| 1.2 | Drift build, new namespace, unused origin | nothing to migrate → app opens directly | ✅ Vivaldi 8.2, post-4B checkpoint |
| 1.3 | Drift build without namespace | configuration error screen, no storage opened | ✅ Vivaldi 8.2, Stage 4A/4B |
| 1.4 | Default-build Network tab | no `sqlite3.wasm` / `drift_worker.js` fetched, 0 third-party requests | ✅ Vivaldi 8.2, Stage 4B |

## 2. JSON storage and CRUD

| # | Check | Expected | Status |
|---|---|---|---|
| 2.1 | Add expense (amount, description, category, date) | appears in list; monthly total updates exactly | ✅ Vivaldi 8.2, post-4B (`12,50` → $12.50); 🤖 |
| 2.2 | Amount input: `12.50`, `12,50`, `0.01` accepted | stored as exact cents | ⏳ (🤖) |
| 2.3 | Amount input: `-1`, `1e3`, `1,000.00`, `1.234`, empty | rejected with a message, nothing saved | ⏳ (🤖) |
| 2.4 | Delete expense | removed; total updates | ✅ Vivaldi 8.2, M3.3 (guarded delete since M3.4) |
| 2.5 | Expense dated in another month | not in "this month" total | ⏳ (🤖) |
| 2.6 | Inspect localStorage `flutter.expenses` | `amountCents` integers, ISO date text | ✅ Vivaldi 8.2, post-4B |

## 3. Legacy amount conversion

Seed `flutter.expenses` on a **test origin** through DevTools with M0-style
records (`"amount": 12.5`).

| # | Check | Expected | Status |
|---|---|---|---|
| 3.1 | Load legacy records (`12.5`, `0.1`, `19.99`) | shown as $12.50, $0.10, $19.99 | ⏳ (🤖) |
| 3.2 | Loading alone | storage unchanged (no write) | ⏳ (🤖) |
| 3.3 | First change after loading | `expenses_legacy_backup` holds the original text; collection rewritten with `amountCents` | ⏳ (🤖) |
| 3.4 | Legacy amount with 3 decimals (`1.005`) | load error, editing disabled, *Export raw data* offered | ⏳ (🤖) |

## 4. Backup export and import

| # | Check | Expected | Status |
|---|---|---|---|
| 4.1 | ⋮ → *Export backup* | file downloads; count, total, SHA-256 inside | ✅ Vivaldi 8.2 (backup flow), Stage 4B |
| 4.2 | Import that file on an empty origin | preview → confirm → identical list and total | ⏳ (🤖) |
| 4.3 | Import the same file again | all records skipped as identical, no change | ⏳ (🤖) |
| 4.4 | Import a file edited by hand (checksum broken) | refused, nothing changes | ⏳ (🤖) |
| 4.5 | Import a file > 5 MB or > 50,000 records | refused before parsing | ⏳ (🤖) |
| 4.6 | Cancel at the preview | nothing changes | ⏳ (🤖) |
| 4.7 | *Export raw data* on the load-error screen | stored text saved byte-for-byte | ⏳ (🤖) |

## 5. Invalid and conflicting records

| # | Check | Expected | Status |
|---|---|---|---|
| 5.1 | Stored JSON is not valid JSON | load error, no write, raw export works | ⏳ (🤖) |
| 5.2 | Two stored records share an ID, identical | both shown; delete refused for that ID | ⏳ (🤖) |
| 5.3 | Two stored records share an ID, different | both shown; delete refused | ⏳ (🤖) |
| 5.4 | Import a record whose ID exists with other content | whole import refused | ⏳ (🤖) |
| 5.5 | Drift migration with conflicting duplicate IDs | migration screen shows *blocked*, no way into an empty app | ⏳ (🤖) |

## 6. Cross-tab changes

| # | Check | Expected | Status |
|---|---|---|---|
| 6.1 | Two JSON tabs; add in tab A | tab B pauses edits with *Reload* (storage event) | ✅ Vivaldi 8.2, Stage 4B |
| 6.2 | Same, tab B tries to save before noticing | write refused (compare-before-write), *Reload* | ⏳ (🤖) |
| 6.3 | Migration screen lists other open tabs; closing one sends `bye` | list updates | ✅ Vivaldi 8.2, Stage 4B |
| 6.4 | JSON tab open while a Drift tab migrates (same namespace) | JSON tab told the data moved | ⏳ |
| 6.5 | Two Drift tabs migrate at the same time | one completes, the other reports already moved | ✅ Vivaldi 8.2, Stage 3/4A |
| 6.6 | Old-version (M1) tab writing | detected afterwards only (documented limit) | ⏳ |

## 7. Isolated Drift migration (test namespace only)

| # | Check | Expected | Status |
|---|---|---|---|
| 7.1 | Seed namespaced JSON key, open Drift build | migration screen with correct preview | ✅ Vivaldi 8.2, Stage 4A |
| 7.2 | *Move* disabled until backup downloaded **and** checkbox ticked | as described | ✅ Vivaldi 8.2, Stage 4B |
| 7.3 | Change the source in another tab after confirming | confirmation reset | ⏳ (🤖) |
| 7.4 | Migrate 20,000 records | completes, verified summary | ✅ Vivaldi 8.2, Stage 4A |
| 7.5 | Reload after success | app opens, already migrated | ✅ Vivaldi 8.2, Stage 4A |
| 7.6 | Change JSON source after migration → *Review* | only new records added after explicit approval | ✅ Vivaldi 8.2, Stage 4A |
| 7.7 | JSON keys after migration | byte-identical to before | ⏳ (🤖) |
| 7.8 | *Export migration snapshots* | exact source text | ⏳ (🤖) |

## 8. Interrupted migration and recovery

| # | Check | Expected | Status |
|---|---|---|---|
| 8.1 | Reload during a large migration | rolled back; migration screen again; retry succeeds | ✅ Vivaldi 8.2, Stage 4A |
| 8.2 | Close the tab during a migration | same as 8.1 | ⏳ |
| 8.3 | Database cannot be opened (e.g. blocked storage) | error with *Try again* and *Export original data*; no JSON fallback | ⏳ (🤖) |
| 8.4 | Rollback procedure: export from Drift → JSON build → import | records restored; deleted-after-migration records reappear (documented) | ⏳ (🤖) |

## 9. Storage-mode warnings

| # | Check | Expected | Status |
|---|---|---|---|
| 9.1 | With COOP/COEP | `opfsLocks`, migration allowed | ✅ Vivaldi 8.2, Stage 4A/4B |
| 9.2 | Without headers, desktop Chromium | `sharedIndexedDb`, migration allowed | ✅ Vivaldi 8.2, Stage 4A |
| 9.3 | `unsafeIndexedDb` (Android Chrome without headers) | warning, migration refused | ⏳ (simulated only) |
| 9.4 | `inMemory` (e.g. storage blocked) | warning, migration refused | ⏳ (simulated only) |
| 9.5 | *Storage information* menu | mode and persistence state shown honestly | ⏳ |

## 10. Reload and browser restart

| # | Check | Expected | Status |
|---|---|---|---|
| 10.1 | JSON build: add, reload | data kept | ✅ Vivaldi 8.2, post-4B |
| 10.2 | Drift build: add, reload | data kept | ✅ Vivaldi 8.2, Stage 4A |
| 10.3 | Quit the browser completely, reopen same origin | data kept (both backends) | ⏳ |
| 10.4 | Private window | data gone after closing (documented risk) | ⏳ |

## 11. Responsive layouts

| # | Check | Expected | Status |
|---|---|---|---|
| 11.1 | Widths 360, 600, 1024, 1440 px (DevTools device toolbar) | no overflow stripes, no clipped buttons | ⏳ |
| 11.2 | Migration screen at 360 px | all steps reachable by scrolling | ⏳ |
| 11.3 | Browser zoom 200 % | still usable | ⏳ |

Full responsive design is M3; this only guards against regressions.

## 12. Accessibility basics

| # | Check | Expected | Status |
|---|---|---|---|
| 12.1 | Keyboard only: add and delete an expense | every control reachable, visible focus | ⏳ (reachable: ✅ Vivaldi 8.2, M3.6 S1; visible focus: ✅ owner, Vivaldi, physical keyboard, M3.6 S2 accepted 2026-10-15 — see §19) |
| 12.2 | Screen reader (Windows Narrator) | list items and buttons have names | ⛔ **NOT TESTED — Deferred by project owner (2026-10-15)** (names verified in the DOM only, M3.6 S1; spoken output unverified) |
| 12.3 | Error messages | announced or visibly attached to the field | ✅ attached: focus moves to the field, `aria-description` + `aria-invalid` (Vivaldi 8.2, M3.6 S1); spoken: ⛔ Narrator NOT TESTED — Deferred by project owner (2026-10-15) |
| 12.4 | Contrast | text readable in light theme | ⏳ |

## 13. Browser compatibility and mobile

| # | Browser | Status |
|---|---|---|
| 13.1 | Vivaldi 8.2 (Chromium 152), Windows | ✅ main test browser, Stages 0–4B |
| 13.2 | Firefox desktop, normal and private window | ⏳ |
| 13.3 | Safari macOS / iOS | ⏳ (if in scope) |
| 13.4 | Chrome on a real Android device, with and without COOP/COEP | ⏳ |
| 13.5 | Edge / Chrome desktop | ⏳ (Chrome must not be installed on the dev machine) |

## 14. Security headers and CSP

| # | Check | Expected | Status |
|---|---|---|---|
| 14.1 | `crossOriginIsolated === true` with `web/_headers` | true | ✅ Vivaldi 8.2, Stage 4B |
| 14.2 | `.wasm` served as `application/wasm` | yes | ✅ Vivaldi 8.2, Stage 4B |
| 14.3 | CSP draft ([csp.md](csp.md)) applied, default and Drift builds | no violations, app works | ✅ Vivaldi 8.2, post-4B (startup, add, dialogs, migration preview); file-based flows ⏳ |
| 14.4 | Real host over HTTPS | headers present, no violations | ⏳ (no host chosen) |

## 15. Theme (M3.3)

| # | Check | Expected | Status |
|---|---|---|---|
| 15.1 | System dark mode: home, add form, error screen, dialogs, migration screen | dark theme everywhere, readable | ✅ Vivaldi 8.2, M3.3 |
| 15.2 | Light mode, same screens | light theme everywhere, readable | ✅ Vivaldi 8.2, M3.3 (via `matchMedia` override) |
| 15.3 | Notices show an icon as well as colour | info / warning / error icons | ✅ Vivaldi 8.2, M3.3 |
| 15.4 | Add button while edits are paused | looks disabled | ✅ Vivaldi 8.2, M3.3 |
| 15.5 | Dialogs on a wide window | at most 560 px wide | ✅ Vivaldi 8.2, M3.3 |
| 15.6 | Keyboard focus ring visible on Tab (real keyboard) | visible on every control | ⏳ (automation inconclusive) |
| 15.7 | Switching OS theme while the app is open | follows immediately | ⏳ |

## 16. Editing (M3.4)

| # | Check | Expected | Status |
|---|---|---|---|
| 16.1 | Select a row → edit form with stored values | amount, description, category, date prefilled | ✅ Vivaldi 8.2, M3.4 |
| 16.2 | Edit amount, save | list and total update; same ID; exact cents | ✅ Vivaldi 8.2, M3.4 |
| 16.3 | Record with an unknown category | category shown and kept | ✅ Vivaldi 8.2, M3.4 |
| 16.4 | Offset/`Z` date, edit another field | `dateText` byte-for-byte | ✅ Vivaldi 8.2, M3.4 (`+02:00`) |
| 16.5 | Pre-2000 or future date, open the picker | no error | ⏳ (🤖 widget tests) |
| 16.6 | Dirty form: back / Escape | "Discard changes?"; keep or discard | ✅ Vivaldi 8.2, M3.4 |
| 16.7 | Open and save without changes | no write | ⏳ (🤖) |
| 16.8 | Two tabs edit the same record (JSON) | second tab paused, never overwrites | ✅ Vivaldi 8.2, M3.4 |
| 16.9 | Two tabs edit the same record (Drift namespace) | stale save refused, input kept | ✅ Vivaldi 8.2, M3.4 |
| 16.10 | Delete a row changed in another tab | refused; record kept | ✅ Vivaldi 8.2, M3.4 (JSON and Drift) |
| 16.11 | Storage failure while saving | input kept, retry works | ⏳ (🤖) |
| 16.12 | Keyboard: Tab to a row, Enter opens it | edit form opens | ⏳ (🤖; browser focus inconclusive) |

## 17. Responsive workspace and Electric After Hours (M3.5)

Vivaldi here ignores window resizing (window stays 1920 px), so widths were
checked with a dev-only harness page in a build copy that embeds the app in
fixed-width same-origin iframes (served without the CSP, whose
`frame-ancestors 'none'` forbids framing). Real-device widths are pending.

| # | Check | Expected | Status |
|---|---|---|---|
| 17.1 | 320 / 360 px | Compact Hero: summary + lime add button, rows; no horizontal scroll; full amounts | ✅ Vivaldi 8.2, M3.5 (iframe harness) |
| 17.2 | 600 px | centred single column | ✅ Vivaldi 8.2, M3.5 (iframe harness) |
| 17.3 | 840 / 1200 / 1440 px | Asymmetric Workspace (hero + selected panel left, activity right) | ✅ Vivaldi 8.2, M3.5 (840/1200/1440 harness; 1879 px full window) |
| 17.4 | Dark (system) and light | identity consistent, readable | ✅ Vivaldi 8.2, M3.5 (light via `matchMedia` override) |
| 17.5 | Select a row (desktop) | panel shows description, amount, category, date, Edit, Delete | ✅ Vivaldi 8.2, M3.5 |
| 17.6 | Long description, large and negative amounts | wraps / scales, never cut | ✅ Vivaldi 8.2, M3.5 |
| 17.7 | Delete → Cancel | nothing written | ✅ Vivaldi 8.2, M3.5 |
| 17.8 | Delete a record another tab changed (Drift namespace) | refused, notice, buttons disabled | ✅ Vivaldi 8.2, M3.5 |
| 17.9 | Dirty form, other tab writes, Reload | "Discard changes and reload?"; Keep editing keeps input; Discard reloads | ✅ Vivaldi 8.2, M3.5 (JSON) |
| 17.10 | Browser back on a dirty form | "Discard changes?" | ✅ Vivaldi 8.2, M3.5 |
| 17.11 | Live window resize keeps the selection | same expense selected | ⏳ (window resize unavailable; 🤖 widget test) |
| 17.12 | Compact detail page on a real phone | opens, back returns | ⏳ (🤖) |
| 17.13 | 200 % browser zoom / text size | no clipping | ⏳ (🤖 at 2.0× text scale) |
| 17.14 | Closing the tab with unsaved input | (no guard yet) | ⏳ known gap |

### M3.5 acceptance review (re-check)

| # | Check | Expected | Status |
|---|---|---|---|
| 17.15 | Max amount at 320/360 | own line, readable, all digits | ✅ Vivaldi 8.2 (harness) |
| 17.16 | Widths 599/600/839/840/1024/1200/1440 | correct layout, no overflow | ✅ Vivaldi 8.2 (harness); 900/1199 🤖 |
| 17.17 | Month total beyond the range | "Total unavailable" + explanation; rows exact | ✅ Vivaldi 8.2 (harness, light) |
| 17.18 | Empty workspace | "Nothing to show yet"; hint under the header | ✅ Vivaldi 8.2 (harness, light); position fix 🤖 |
| 17.19 | Delete dialog at 320 | fits / scrolls; full description | ✅ Vivaldi 8.2 (3-line cut seen, fixed, 🤖) |
| 17.20 | Dropdown menu surface | graphite, not page colour | ✅ Vivaldi 8.2 (CSP origin) |
| 17.21 | Dirty Reload + browser back (JSON, CSP) | confirmations, input kept | ✅ Vivaldi 8.2 |
| 17.22 | Stale delete (JSON, CSP) | blocked; storage unchanged | ✅ Vivaldi 8.2 |
| 17.23 | Light theme with the CSP applied | no violations | ✅ Vivaldi 8.2, M3.5 closure |

### M3.5 closure

| # | Check | Expected | Status |
|---|---|---|---|
| 17.24 | Month with MAX, +0.01, −0.01 in any stored order | exact `$90,071,992,547,409.91`, same in every order | ✅ Vivaldi 8.2 (two orders); 🤖 all permutations |
| 17.25 | Month whose exact total exceeds the range | "Total unavailable" + explanation; rows exact | ✅ Vivaldi 8.2 (dark and light) |
| 17.26 | English dates: rows / detail / compact detail / form / delete dialog / hero | `Oct 12, 2026` / `October 12, 2026` / `October 2026` | ✅ Vivaldi 8.2 |
| 17.27 | Unchanged edit of an offset-dated record | nothing written; `dateText` verbatim | ✅ Vivaldi 8.2 |

## 18. Accessibility semantics (M3.6 Stage 1)

Evidence kinds: 🤖 widget/semantics-tree test · 🌐 Vivaldi accessibility
DOM · 🔊 Narrator spoken output. Only 🔊 counts as a screen-reader pass.

**Status at the Stage 1 closure (2026-10-15):** M3.6 Stage 1 is
technically complete (798 passed, 0 failed, 0 skipped). Every 🔊 item
below is **NOT TESTED — Deferred by project owner (2026-10-15)**:
screen-reader behaviour and screen-reader activation of "Enable
accessibility" remain unverified. This is neither a pass nor a confirmed
defect, and it is no claim of WCAG compliance.

| # | Check | Expected | Status |
|---|---|---|---|
| 18.1 | Before enabling accessibility | no semantics nodes, no expense text in the DOM | ✅ 🌐 Vivaldi 8.2 |
| 18.2 | Enable accessibility (placeholder) with Narrator | Narrator finds and activates "Enable accessibility" | ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15); activation by Narrator unverified (🌐 a click works; Enter/Space alone do not) |
| 18.3 | Tab to an expense row | row reached, read as "description, amount, category - date" | ✅ 🌐 (tabindex 0, real Tab); ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15) |
| 18.4 | Enter or screen-reader activation on a row (desktop) | selected; `aria-current="true"`; panel shows it | ✅ 🌐 🤖; ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15) |
| 18.5 | Activate a row (compact) | detail page opens; no selected state | 🤖 (360 px); ⏳ 🌐; ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15) |
| 18.6 | Reach Edit and Delete after selecting | reachable (after the rows; KB-02 in Stage 2) | ✅ 🌐 🤖 |
| 18.7 | Delete → dialog → Cancel | dialog named "Delete expense"; nothing written | ✅ 🌐 (name on an inner element, see handoff); ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15) |
| 18.8 | Headings | one `h1` "SpendWise", `h2` "Expenses, N" | ✅ 🌐 🤖 |
| 18.9 | Add expense name | announced once; tooltip still on hover | ✅ 🌐 🤖 |
| 18.10 | Empty submit | focus on Amount, message attached, nothing written | ✅ 🌐 🤖; ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15) |
| 18.11 | Negative / very large amount, "Total unavailable" read aloud | understandable, exact | ⛔ 🔊 NOT TESTED — Deferred by project owner (2026-10-15) (labels exact in 🌐) |
| 18.12 | Light theme, CSP | same results, 0 CSP reports | ✅ 🌐 Vivaldi 8.2 |

## 19. Keyboard navigation and focus (M3.6 Stage 2)

Evidence kinds: 🤖 widget test (`test/widgets/keyboard_focus_test.dart`) ·
🌐⌨ Chromium 152 on `127.0.0.1:8911` (synthetic data, CSP), driven by
synthetic `KeyboardEvent`s because the automation's real key presses
stopped reaching the page · 👤 owner, Vivaldi, physical keyboard,
`127.0.0.1:8911` with the 4 synthetic records (2026-10-15).

**Owner acceptance (2026-10-15):** M3.6 Stage 2 formally accepted;
820 automated tests passed, 0 failed, 0 skipped. Step 1 (Tab / Shift+Tab
focus visibility) reported PASS; the owner then confirmed that all tested
keyboard interactions work correctly, without separate per-step reports
for steps 2–5. No deletion was performed. Narrator: NOT TESTED —
Deferred by project owner (2026-10-15).

| # | Check | Expected | Status |
|---|---|---|---|
| 19.1 | Tab through the workspace | ring (focus colour, 2 px, gap) on menu, Add expense, rows, Edit, Delete | ✅ 🤖 (dark, light); ✅ 🌐⌨ dark; ✅ 👤 step 1 PASS |
| 19.2 | Mouse use | no ring after a pointer press; ring back on the next key | ✅ 🤖; ✅ 🌐 (click on a row) |
| 19.3 | Focused vs selected row | focus: ring inside the row; selected: fill + left bar; both can show | ✅ 🤖; ✅ 🌐⌨; ✅ 👤 (owner-approved, 2026-10-15) |
| 19.4 | Workspace order | menu → Edit → Delete → Add expense → rows; same whichever row is selected | ✅ 🤖; ✅ 🌐⌨ (Shift+Tab from a row); ✅ 👤 (owner-approved, 2026-10-15) |
| 19.5 | Compact order (< 840 px) | Add expense → rows in list order | ✅ 🤖 (360 px); ✅ 👤 (owner-approved, 2026-10-15) |
| 19.6 | Add / edit form opens | focus on Amount; existing value not selected or changed | ✅ 🤖 (edit on desktop platform); ✅ 🌐⌨ edit ("-5.00", selection 5–5); ⏳ 🌐 add; ✅ 👤 (owner-approved, 2026-10-15) (edit) |
| 19.7 | Escape in the form | unchanged: leaves, focus back on Edit; changed: asks first | ✅ 🤖; ✅ 🌐⌨ (unchanged); ✅ 👤 (owner-approved, 2026-10-15) |
| 19.8 | Delete dialog | opens on Cancel; Enter or Escape closes it, focus back on Delete, nothing written | ✅ 🤖; ✅ 🌐⌨; ✅ 👤 (owner-approved, 2026-10-15) (Cancel) |
| 19.9 | Confirmed delete | focus to the next row, else previous, else Add expense | ✅ 🤖 (workspace and compact); not run in the browser (keeps the synthetic data) |
| 19.10 | Refused delete (changed in another tab) | no focus jump to another row | ✅ 🤖 |
| 19.11 | Compact Back from details | focus returns to that row | ✅ 🤖; ⏳ 🌐 |
| 19.12 | Light theme, zoom, live resize | rings visible (deep green), layouts unchanged | ✅ 🤖 light; ⏳ 🌐 |

## 20. Favicon and app icons (2026-10-15)

"s." monogram (obsidian tile, soft-white s, lime full stop), owner-approved
from previews. Evidence: 🌐 Chromium 152 on `127.0.0.1:8911` (synthetic
data, CSP `csp_v2`) · 🔧 file checks (Pillow, `cmp`).

| # | Check | Expected | Status |
|---|---|---|---|
| 20.1 | Sizes and transparency | favicon.png 32×32 RGBA; Icon-192/512 RGBA with transparent corners; maskable opaque | ✅ 🔧 |
| 20.2 | Manifest | valid JSON; icon sizes match files; `background_color`/`theme_color` `#0B1010` | ✅ 🔧 🌐 |
| 20.3 | Build output | `build/web` icons and manifest identical to `web/` | ✅ 🔧 |
| 20.4 | Browser loads the favicon | SVG requested by the browser; PNG fallback present; all icons 200 with correct type | ✅ 🌐 |
| 20.5 | CSP | 0 reports; no console errors | ✅ 🌐 |
| 20.6 | Maskable safe area | artwork inside the 80 % circle | ✅ 🔧 (preview with circle and rounded masks) |
| 20.7 | Safari (PNG fallback), installed PWA, Android launcher | icon shown correctly | ⏳ |

## 21. Unreadable stored data (DATA-02, 2026-10-15)

Evidence: 🤖 `test/services/unreadable_storage_test.dart` (synthetic data) ·
🌐 Chromium 152, never-used origin `127.0.0.1:8952`, namespaced build
`qad02`, synthetic damaged value in `flutter.spendwise_ns.qad02.expenses`
only. Never run on real data or on the normal development origin.

| # | Check | Expected | Status |
|---|---|---|---|
| 21.1 | Key absent | empty list, adding works | ✅ 🤖; ✅ 🌐 (0 keys → "No expenses") |
| 21.2 | Undecodable value present | recovery screen; nothing written; value byte-identical after load and Retry | ✅ 🤖; ✅ 🌐 |
| 21.3 | Wrong-type value / JSON `null` | recovery screen, not a crash or empty list | ✅ 🤖 |
| 21.4 | Storage blocked | treated as unreadable, export says the value could not be retrieved | ✅ 🤖 |
| 21.5 | Damage after loading | next save refused, app switches to the recovery screen, nothing written | ✅ 🤖 |
| 21.6 | Unreadable legacy backup | never replaced; the rewrite that needed it is refused | ✅ 🤖 |
| 21.7 | Raw export | exact browser-storage value under `unreadable`; readable data exports the previous v1 shape | ✅ 🤖; ⏳ 🌐 (download not performed) |
| 21.8 | Migration with an unreadable source | fails; nothing written to the database | ✅ 🤖 |
| 21.9 | Valid data | load, add, edit, delete, keyboard and accessibility unchanged | ✅ 🤖 (full suite, 839 passed) |
