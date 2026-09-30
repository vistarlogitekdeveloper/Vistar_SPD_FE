# VST SPD — Frontend

The console half of **VST SPD — Pre-Packing Process Automation**, the system
specified in `VST_SPD_PrePacking_SRS.docx`. The API it talks to lives in
[Vistar_SPD_BE](https://github.com/warehousevistar/Vistar_SPD_BE), and it will
not do anything useful without it.

The system digitises the SPD pre-packing cycle end to end: the SAP GRN export is
uploaded once, validated column by column and displayed invoice- and
part-number-wise; ID labels are generated and printed from that data; lines are
allocated to packing tables; table members start and submit packing with the
times captured for them; packed and pending quantities reconcile in real time;
exceptions are flagged for the Supervisor; hourly reports are generated and
emailed; and the MIS is written automatically the moment the shift is finalised.

Flutter / Dart. The Supervisor console, the touch-first table-member screens,
the MIS and the live dashboard — transcribed from the approved prototype
`Vistar_SPD_PrePacking_Prototype.html`.

## Quick start

Needs Flutter 3.41+ with Dart 3.11+, and the backend running.

```bash
flutter pub get
flutter run -d chrome --dart-define=SPD_API=http://localhost:4100/api
```

Sign in as `sup.rmenon` / `vistar@2026` against the seeded demo shift; the other
demo accounts are listed in the backend's README.

Release builds:

```bash
flutter build web     --release --no-web-resources-cdn --dart-define=SPD_API=https://<host>/api
flutter build apk     --release --dart-define=SPD_API=https://<host>/api   # table tablets
flutter build windows --release --dart-define=SPD_API=https://<host>/api   # supervisor station
```

`--no-web-resources-cdn` is not optional for a shop-floor deployment — see
[Running offline](#running-offline). Without `--dart-define` a web or desktop
build points at `http://localhost:4100/api` and an Android build at
`http://10.0.2.2:4100/api` (the emulator's alias for the host). A deployed web
build that was never told where its API is says so in the connection error
rather than failing silently.

## Screens

| Screen | Route | Covers |
|---|---|---|
| Login | `/login` | FR-5.1, NFR-3.1 |
| Live Dashboard | `/dashboard` | FR-11 |
| GRN Upload & import history | `/grn` | FR-1 |
| Invoice / Part Lines | `/lines` | FR-2 |
| ID Labels | `/labels` | FR-3 — one card per label, so an MOQ-split line shows each pack (FR-3.5) |
| Table Allocation & status board | `/allocation` | FR-4 |
| Review, exceptions & final submission | `/review` | FR-9, FR-10.1 |
| Hourly Reports | `/hourly` | FR-8 |
| MIS Report | `/mis` | FR-10, FR-12.1 |
| Audit Trail | `/audit` | NFR-3.3, NFR-7.1 |
| My Work Queue | `/my/work` | FR-5.2, BR-05 |
| Pack (Start → Qty → Submit) | `/my/pack` | FR-6, FR-7.2 |
| My Submissions | `/my/history` | FR-6.5 |
| Users & Roles | `/admin/users` | FR-13.1, FR-13.3 |
| Masters & Config | `/admin/config` | FR-13.2, NFR-5.1, NFR-6.1 |

```
lib/
├── main.dart
├── app.dart                 router, role-based route guards, theme wiring
├── core/
│   ├── theme.dart           design tokens, named after the prototype's CSS custom properties
│   ├── api.dart             Dio client, ApiException
│   ├── format.dart          nf(), fmtD(), fmtTs(), durTxt() — the prototype's helpers
│   └── downloads.dart       saving an export or a label sheet
├── models/models.dart       typed views over the API's JSON
├── data/
│   ├── repository.dart      one place that knows the API's shape
│   └── providers.dart       Riverpod graph, the shift scope, the live refresh
└── ui/
    ├── splash_screen.dart · login_screen.dart · shell.dart
    ├── widgets/             common.dart (the component set), label_card.dart, line_detail.dart
    ├── supervisor/          dashboard, grn_upload, lines, labels, allocation, review, hourly
    ├── member/              my_work, pack, my_history
    ├── reports/             mis, audit
    └── admin/               users, config
```

## Running

```bash
flutter pub get
flutter run -d chrome --dart-define=SPD_API=http://localhost:4100/api
```

The backend must be running; see `../backend/README.md`.

## Tests

```bash
flutter test
```

Four files, and the split between them is deliberate.

`screen_render_test.dart` mounts all fourteen content screens at desktop and
tablet widths in both themes, over a fake repository that always succeeds.

`screen_states_test.dart` covers the two states that one never reaches. A screen
has three, and the other two are the ones nobody looks at, because the API is up
on the machine where the screen was written. So every screen is mounted once
against a repository that refuses everything and once against one that never
answers, and must show an `ErrorPanel` or an `SpdLoader` rather than a blank
rectangle.

That file exists because of what it found. Every screen declared an `error:`
branch and none of them could reach it: Riverpod keeps the previous error on a
provider that is reloading, a plain `.when()` reports that as loading, and the
default retry budget is ten attempts with a doubling backoff. A supervisor whose
server was down watched a spinner for about thirty-eight seconds, with the
message and the Try again button held behind it the whole time. `spdRetry` in
`data/providers.dart` now spends its budget in 600ms — two quick attempts absorb
a blip, and past that the screen says what happened and hands the retry back to
the person, who knows things the client does not. `skipLoadingOnReload` is what
lets the screen show the error it is already holding. One test measures that the
panel appears within 800ms; remove either half and it fails.

`widget_gallery_test.dart` mounts every widget in the shared library on its own.
It exists because of a bug a release build cannot catch: `Wordmark` reproduced
the prototype's negative CSS margin with a negative `EdgeInsets`, which
`RenderPadding` asserts against. Asserts are stripped from a release bundle, so
the signed-off web build rendered it happily while `flutter run` threw on the
splash and left the element tree inconsistent. Anything that only fails under an
assert is invisible to a release build and to a screenshot.

`widget_behaviour_test.dart` covers what mounting cannot tell you. A `GradButton`
whose `onPressed` never reaches its gesture detector renders pixel for pixel like
one that works, so every callback is pressed and observed. A layout that fits at
1440px may not at 390px, so the specimens are re-mounted at tablet and phone
widths and any `RenderFlex` overflow fails the test — that is how `LabelCard`
was found overflowing by 34px whenever `width` was set below its default. The
tables, modals, toasts and the print preview are opened and operated rather than
merely constructed. Each probe was mutation-checked: unwiring `GradButton`,
`DropZone` and the `SpdRow` drill-down, and removing `ProgressBar`'s clamp, each
fails exactly the test that claims to cover it.

## How the prototype maps onto this

The prototype is a single HTML file with its own CSS component set. Each class
has one widget here, named after it, so the two can be read side by side:

| Prototype | Widget |
|---|---|
| `.card`, `.card .corner-s` | `SpdCard`, `Panel` |
| `.kpi` | `KpiCard`, `DeltaChip` |
| `.pill`, `.p-*` | `Pill`, `StatusPill`, `PillTone` |
| `.alertbox` | `AlertBox`, `AlertTone` |
| `.phead` | `PageHeader`, `BlurbText` |
| `.tbl-wrap` + `table` | `SpdTable`, `SpdCol`, `SpdRow`, and the `cell` helpers |
| `.filterbar` | `FilterBar` |
| `.bar`, `.barrow` | `ProgressBar`, `BarRow` |
| `.ring-prog` | `RingProgress` (a `CustomPainter` for the conic gradient) |
| `.plabel` | `LabelCard` |
| `.partcard`, `.tablecard` | `PartCard`, `TableCard` |
| `.modal`, `#toasts` | `showSpdModal`, `Toast` |
| `.grid.gN`, `.split-l/.split-r` | `ResponsiveGrid`, `SplitPane` |
| `#ambient` | `AmbientBackground` |

Four things are worth knowing when changing the layout or the palette:

- **Stay inside the fonts' own glyph coverage.** The prototype's ditto mark in
  the Lines invoice column is U+3003, a CJK codepoint Manrope does not carry. It
  renders in a browser with internet access only because the engine fetches a
  fallback font at runtime; on a closed shop-floor LAN it would be a tofu box.
  The column uses U+201D instead — the mark the ditto derives from, and one
  Manrope has. Same reasoning applies to any glyph added later.

- **Inset controls use `Brand.field` / `Brand.fieldLine`, not `Brand.surface` / `Brand.line`.**
  In light mode `--surface` and `--bg2` are both pure white, so a white text
  field on a white card or on the white login panel was separated from it by a
  10%-opacity hairline and nothing else. `Brand.field` resolves to the recessed
  tint in light mode and to `surface` in dark, so dark mode is unchanged. Use it
  for anything a user clicks *into* — fields, dropdowns, top-bar pickers, icon
  buttons, list rows. Cards, tables and part cards keep `Brand.surface`: they sit
  on the page background, where white already reads.

- **Breakpoints read the viewport, not the element.** The prototype's
  breakpoints are CSS media queries. `ResponsiveGrid` and `SplitPane` therefore
  use `MediaQuery.sizeOf(context).width`, because deciding from the local
  constraint drops the four KPI tiles to two on a 1440px screen purely because
  the sidebar takes 248 of them.
- **`.mono` is not a monospace face.** It is Manrope with tabular figures, so
  quantities line up in a column without looking like source code. That is what
  `mono()` in `theme.dart` returns.

## Running offline

The SRS puts this console on the organisation's own LAN (§2.6), so a table
device may have no route to the internet at all. **Nothing the app needs is
fetched from a third party at runtime** — verified by loading every screen with
the network panel open and confirming no request leaves the app's own origin
except calls to its own API.

Three things had to be brought in-house to get there:

| | |
|---|---|
| The three typefaces | `assets/google_fonts/` holds every normal-style weight of Manrope, Bricolage Grotesque and Fredoka. `google_fonts` finds them by filename, and `main()` sets `GoogleFonts.config.allowRuntimeFetching = false` so a missing weight is a loud error in development rather than a quiet download that only works at a desk. |
| CanvasKit | Built with `--no-web-resources-cdn`, which serves the engine's wasm from `build/web/canvaskit/` instead of `www.gstatic.com`. Without this the app does not start offline at all. |
| The engine's own fallbacks | Flutter fetches Roboto (the default family for text that names no font) and a Noto symbols face. `web/flutter_bootstrap.js` points `fontFallbackBaseUrl` at `web/fallback-fonts/`, where both are mirrored. |

**Always build web with `--no-web-resources-cdn`** — the flag is not sticky, and
a build without it silently goes back to the CDN for CanvasKit:

```bash
flutter build web --release --no-web-resources-cdn --dart-define=SPD_API=https://<host>/api
```

The mirrored fallback paths carry the engine's version stamps
(`roboto/v32/…`). A Flutter upgrade can change them; if it does, the engine
requests a file that is not there and falls back to the bundled faces — the
console still renders, it just loses symbol coverage. After upgrading Flutter,
reload with the network panel open and re-mirror anything that 404s.

The font files were downloaded and verified against the SHA-256 and byte length
that the `google_fonts` package itself declares for each variant, so what is
committed is provably the file the package expects.

## Brand assets

`assets/brand/vistar_s.png` and `vistar_s_sm.png` were extracted from the
prototype's own embedded data URIs (the `--sm` and `--sm-sm` custom properties),
so the mark on screen is byte-for-byte the approved one.

## Behaviour worth noting

- **The API is the authority.** Every rule the user can hit — a quantity of
  zero, an over-pack, a second table without a split, a reprint without a
  reason, a finalise with an un-annotated exception — is refused by the server
  with the message the SRS asks for, and the console shows that message rather
  than one of its own.
- **"Floor live"** replaces the prototype's simulated floor: it polls the API at
  the configured refresh interval (FR-11.4). It stays a toggle for the reason
  the prototype's was — a supervisor reading a table does not want the rows
  moving under them.
- **"View as"** appears for an Administrator only. It changes what the console
  draws, never what the server will accept.
- **Printing goes through an in-app preview** (`widgets/pdf_preview_dialog.dart`)
  rather than straight to `Printing.layoutPdf`. Handing the bytes to the OS
  leaves the preview to the platform, and the Windows print dialog answers
  "This app doesn't support print preview" — so a Supervisor would be committing
  label stock to a sheet nobody had seen. The dialog renders the pages, then
  offers Print (which is still the OS dialog, since that is what talks to the
  label printer) and Save PDF.
- **The light/dark choice is remembered** in local storage under
  `spd.theme.light`. `main()` loads it before the first frame, so the remembered
  theme is the one that paints rather than a dark flash corrected a moment
  later. `sharedPrefsProvider` is deliberately nullable: if storage is
  unavailable — a private window, a locked profile, a platform whose plugin did
  not register — the app still starts and simply forgets the choice.
