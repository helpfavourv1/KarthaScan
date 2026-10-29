# Outstanding ledger

Items waiting for an APK rebuild. Nothing here has run on a device yet; the
compile check (lint, unit tests, Kotlin compile) is green on `main`.

## Queued (not started)

| ID | Item | Why it waits | Gate |
|----|------|--------------|------|
| 3.6 | Move export heavy work off the UI thread: background isolate with a progress callback; image decode, filter, crop, rotate, composite and encode move there. Stamp and watermark text drawing must stay on the UI thread (dart:ui). | High risk, touches the same export code as 3.1 and 3.4, cannot be proven by unit tests alone. Do after the APK is rebuilt and 3.1 to 3.5 are checked on a phone. | Export a 20-page document: the spinner keeps moving and the app does not freeze. |

## Done in code, needs a phone check after the next APK

| ID | Check |
|----|-------|
| 1.1 | Ad-free buyer stays ad-free after a cold start. |
| 2.1 | OCR a Chinese/Japanese/Korean page; import a multi-page PDF and search its text. |
| 2.2 | PDF import pages are not stretched. |
| 2.3 | Filter strength slider changes the exported result; highlighter is yellow and wide. |
| 2.4 | Notifications toggle asks permission; share and review prompts appear (share after 5 return visits, review after 4 exports). |
| 2.5 | Print shows edits; wide scans print landscape; Save on Android 9 asks for storage. |
| 3.1 | Rotate a page 90 degrees, add a stamp in a corner, export: stamp in the same corner. |
| 3.2 | Stamp page 2, move it to page 1: stamp stays with the page. Page tile menu: duplicate, rotate, extract. |
| 3.3 | Crop, filter and revert show immediately without leaving the editor. |
| 3.4 | Crop a page, erase a word, export: the word is gone. |
| 3.5 | Copy a watermark to 5 pages: all 5 keep it. Dragging a signature feels smooth. |
| 4.2 | Android phone set to an EEA region (or with a test device ID): the consent form appears before any ad; Settings shows "Privacy settings". Outside the EEA: ads still load. iOS: tracking prompt, then ads. |
| 5.2 | Settings > Device Migration: make a backup with a password, delete the app data (or use a second phone), import it: documents, annotations, saved signature and snippets return. Also import a backup made by the OLD app version. A wrong password shows the import error. |
| 5.3 | Export a document as CSV and open it in a spreadsheet: one row per line. Export Arabic text as Word: right-to-left. |
| 5.4 | Type in the home search box: results appear after a short pause. Search for "a_b". |
| 4.4 | Android 13+ phone: gallery import (image and PDF) and Save to Downloads still work; no photo-access permission prompt appears. |
| 4.3 | Privacy manifest builds in Xcode/Codemagic without warnings (iOS). |

## Batch F and database v2 (done in code, compile check green, needs a phone check)
- Licences page lists Noto Sans, Noto Sans Arabic and Plus Jakarta Sans (SIL OFL). Check: Settings > Open source licences.
- Privacy wording: ticker "YOUR DOCUMENTS STAY ON YOUR DEVICE", onboarding title "Private by design" in all 26 languages (my translations, native review advised).
- Edit tray buttons have a 48 px touch area (compact tray too).
- Unused storagePath setting removed; stale phosphoricons entry removed from pubspec.lock.
- Database version 2: tags are searchable; old search index is rebuilt on upgrade. Check: add a tag, search for it. Undo rollback on a failed save NOT done on purpose: when the database is unavailable every save reports failure, so a rollback would undo every edit on screen.

## Batch G: CJK and Hindi text in generated PDFs (done in code, compile check green, needs a phone check)
- Chinese/Japanese/Korean: fonts live in `website/fonts/cjk/` (served at https://katharscan.helpfavourv1.workers.dev/fonts/cjk/, repo copy on GitHub raw as a spare) (SC 10.6 MB, JP 5.8 MB, KR 6.2 MB). The app downloads the one it needs the first time a PDF has that text, checks its SHA-256, keeps it in the app's private folder. Offline: PDF is made without it (boxes) and the download is not retried for 5 minutes. Needs the website deploy to include `fonts/cjk/`; open the URL above in a browser after deploying to confirm the file downloads.
- Hindi, other Indic scripts, Hebrew, Thai: those lines are drawn as pictures with the phone's own fonts (TXT, DOCX, CSV to PDF). Text is not selectable there. The hidden text layer of searchable PDFs is unchanged.
- Check: convert a TXT with Chinese, Korean and Japanese lines to PDF with data on (first time downloads, shows the text), then offline (cached, still works). Convert a TXT with Hindi, Hebrew and Thai lines: all readable. CSV with Hindi cells: table shows them.

## OCR for Chinese, Japanese, Korean, Hindi (done in code, compile check green incl. Kotlin, needs a phone check)
- Cause of "never works": the packs come from Google Play services and the app never asked for them; the scan flow only ever ran the Latin recognizer; a "not ready" result was remembered for the whole session so scans skipped those scripts.
- Now: Android asks Play services to download the pack (`ocr_models` channel), the scan flow tries Latin then Chinese/Japanese/Korean/Devanagari, "still downloading" is retried (only hard failures are remembered), Devanagari (Hindi, Marathi) added to Settings > OCR Languages.
- Check (phone online, Google Play services present): Settings > OCR Languages, tap the download icon on Chinese, Korean, Japanese and Hindi; wait a minute, tap refresh until the status clears. Then scan a Chinese page: text is found and searchable.
- Arabic, Russian, Ukrainian, Greek, Hebrew, Thai, Bengali: done with Tesseract (Android only; iOS shows Unsupported). Language files live in `website/tessdata/` and download on first use (website first, GitHub raw as spare), SHA-256 checked. Scans use only packs already installed. Compiles and packages in CI (debug APK job green); recognition quality still needs a phone test. After deploying the website, confirm https://katharscan.helpfavourv1.workers.dev/tessdata/tha.traineddata opens.

## Phase 5 status

Done in code: 5.2 backups, 5.3 CSV/DOCX text fixes, 5.4 debounce and wildcard escape, 5.5 dead code removal and README.
Left: nothing in code. 5.1 (undo/database hardening) and 3.6 wait for the phone test. Bundled fonts, tags in search, bigger tap targets and the unused-setting cleanup are done (see Batches F and G).

## Known gaps left on purpose

- Dark-mode background of the drawing canvas (needed white for exported ink).
- No new OCR-language setting (would need strings in 26 languages).
- If a save fails the change stays on screen with an error (no rollback).
- `ITSAppUsesNonExemptEncryption` is a legal declaration for the owner to make.
- Share and review prompts default ON for new installs only.
- Ads now start after the tracking prompt is answered, even if the answer is "Ask app not to track" (non-personalised ads). Before, a "no" blocked ads entirely.

## Waiting on the owner (Phase 4)

- Real AdMob ad unit IDs (4 of them) and App ID.
- Apple Team ID: replace `[YOUR_TEAM_ID]` in `app/ios/ExportOptions.plist` and `codemagic.yaml`.
- Codemagic: connect the App Store Connect API key (Issuer ID, Key ID, private key) in the `app_store_credentials` group, then run the iOS workflow by hand (I cannot trigger Codemagic from here).

## 5.3 Bundled PDF fonts (phone check)
- Noto Sans + Noto Sans Arabic (SIL OFL, from notofonts GitHub) bundled in `app/assets/fonts/`, used by TXT/CSV/DOCX-to-PDF, the searchable-PDF text layer and the empty-doc page.
- Check: convert a TXT with Cyrillic, Greek and Arabic lines to PDF; no empty boxes.
- Not covered: Chinese/Japanese/Korean (fonts are 8-16 MB each) and Hindi (the pdf package cannot shape Devanagari joins). Add the OFL licence text to the in-app licences page before launch.

## AdMob console: everything still to do (owner)
App IDs already in the build: Android `ca-app-pub-2731774500195310~5515913454` (AndroidManifest), iOS `ca-app-pub-2731774500195310~7132336744` (Info.plist). Check both exist in AdMob under Apps and match.
1. Create 4 real ad units: Android banner, Android interstitial, iOS banner, iOS interstitial. Send me the 4 IDs; I replace the Google test IDs in `banner_ad_widget.dart`, `conditional_banner.dart` (same banner unit) and `interstitial_ad_service.dart`. Until then the app only shows test ads.
2. Privacy & messaging, European regulations: create and PUBLISH the consent message (covers EEA, UK, Switzerland), tick both apps. Without it, no consent form appears for those users.
3. Privacy & messaging, US states regulations message (optional but advised) and the iOS "IDFA explainer" (optional, the app already shows Apple's prompt).
4. After each app is live in its store, link it in AdMob (Apps > App settings > App store details) so ads serve and app-ads.txt can be verified.
5. app-ads.txt: the file is in `website/app-ads.txt` (served at the site root after deploy; publisher ID from the app ID). Put the website address in the store listing as the developer website, then check it in AdMob (Apps > View app-ads.txt status).
6. Account: payment profile, tax info, address PIN, payee name. Payments do not start without them.
7. Blocking controls: choose blocked ad categories / sensitive categories to suit a document scanner (kids, gambling etc.).
8. Not child-directed: leave "tagForChildDirectedTreatment" unset in the app and answer "not designed for children" in the store forms.
9. Test devices: if you add your phone as a test device for the EEA form test, remove it before launch.
10. Store forms must match: Play Data safety (ads, advertising ID, AD_ID permission is in the manifest) and Apple privacy labels (ads, tracking). `pubspec.yaml` description no longer says "no ads"; make sure the store listing text does not either.

## R8 shrinking: decided NOT to use
Owner measured only about 2 MB saved, not worth the release-only crash risk. `minifyEnabled` and `shrinkResources` are false again. `proguard-rules.pro` (full keep rules for every plugin, verified to pass an R8 run in CI) and `res/raw/keep.xml` stay in the repo, unused, in case shrinking is wanted later. To enable later: set both flags true and add `proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'` to the release block, then run the full phone check (OCR all scripts, PDF import/export, notifications with icon, ads and consent, subscriptions, crop, backup).

## Launch crash "Something went wrong" (fixed in code, confirm on phone)
- Cause: the share/review prompt listener (mounted around the whole app in Phase 2) read `EngagementService.instance` before the service existed, so the first frame threw "Null check operator used on a null value". Fixed by creating the service in `main.dart` before `runApp`.
- Also fixed: two `async initState` methods and a translated-text read in `initState` on the home screen (debug-only assertions).
- New test `app_boot_test.dart` starts the real app (home and onboarding) and fails with the call trace if anything throws. Both pass.
- Phone check: install the next APK; the app must open to onboarding (fresh install) or home.

## Stress review of the 21 tray tools: resolved
The 22 findings from the code review were fixed in Batches A to E (see `docs/FIX_PLAN.md`) and are waiting for the phone check above. Review of `layer_control_panel.dart`, `signature_editor_bar.dart` and the search-index upgrade is done (2026-10-19):
- Signature: one placement per signer per page by design (keyed by signer and page), so the old "same signature twice" finding does not apply.
- Search-index upgrade (database v1 to v2): drops and rebuilds the index inside one transaction from the stored rows; covered by `db_upgrade_test.dart`. A rebuild error is logged and swallowed (search is then empty until documents are saved again, documents are never touched).
- CLOSED: watermarks, annotation pictures and signature copies each have their own id. The same watermark text, the same picture or the same signature can be placed several times on one page and each copy is moved, resized and removed on its own (unit-tested; older saved layers load with a derived id). Signature: tapping Sign / Place here again on a page that already has that signature adds a second copy 15% lower.

## Tray stress test (2026-10-18)
`app/test/tray_flow_stress_test.dart` (runs in CI) fires 150 quick mixed edits, undo/redo, page delete/reorder/extract, delete-while-saving, and exports a heavily edited document in every format. Defects it found and that are fixed: double tap opened a tool twice (700 ms tap gap in the tray); a delete during queued edits let the document come back; undo restored a whole old copy of the document (undid renames, tags and deleted pages); text export of a document with no text wrote an empty file. Not tested here (needs a phone): memory use of very large pages (the resize limit is 40 megapixels), real gesture feel of the sheets, ads and share/print hand-off.

## Emulator test results (GitHub Actions, `android-emulator-tests` job)
Run from the compile-check workflow (Run workflow; optional filter box: a regex like `S4|S6`, or `monkey`).
- Suite 1 (`app/integration_test/emulator_suite_test.dart`): font downloads, PDF text drawing for 12 scripts, OCR (Latin + 7 Tesseract languages), stamp/watermark/rotate on device, export formats, compression, page ops/search, every tray tool opens/closes. All pass. ML Kit Chinese/Japanese/Korean/Hindi packs cannot install on a CI emulator: those 4 OCR checks are SKIPPED (phone test), CJK PDF glyph shapes only checked by ink.
- Suite 2 (`emulator_stress_test.dart`): 26 languages x 2 text sizes x light/dark x 3 screens = 312 combinations (pass after fixes); 100-page export PDF 27 s / JPG 16 s; 12 MP and 24 MP edited pages export, 48 MP edited page refuses cleanly ("Could not render page"); 400 rapid edits + undo/redo + delete-while-saving (database equals memory); 360 rapid tray taps with 6 background/resume cycles (no errors); adb monkey 2,300 random events (no app crash/ANR).
- Found and fixed from these runs: Arabic PDF text reversed/unjoined; auto OCR missing Cyrillic when a pack is installed; tray label overflow (large text/tall scripts); settings accent-row overflow; page-row overflow; duplicate tray keys when two labels match.
- Closed after these runs: 48 MP edited pages now export (decoded at reduced size; 12/24/48 MP in 20/43/59 s on the emulator); PDF export builds and saves on a background isolate (longest screen freeze on a 20-page edited export 894 ms -> 117 ms in a debug build); watermark edit/copy/clear are single saves with a single undo step; failed saves retry 3 times then show a red "could not save" banner with Try again (new string `saveFailedBanner` in all 26 languages, translations need native review).
- iOS: Arabic, Russian, Ukrainian and Thai now read with Apple Vision (iOS simulator: 100%, 98%, 98%, 100%). Greek, Hebrew and Bengali are not supported by Apple Vision on iOS; the app shows them as unsupported there.
- iOS build blockers found by the new iOS simulator job and fixed: deployment target raised to 15.5 (google_mlkit_commons), and `google_mobile_ads` 9.1.0 does not compile for iOS; `pubspec.yaml` now pins the upstream commit with the fix. Switch back to a normal `google_mobile_ads: ^9.2.0` line once 9.2.0 is on pub.dev.
- Not fixable: Greek/Hebrew/Bengali OCR on iOS (Apple limitation); ML Kit CJK/Hindi packs and camera/Print/Email/ads/purchase cannot be tested on CI.

## Play Store emulator attempt for ML Kit (2026-10-23)
- Tried `google_apis_playstore` (new `emu_target` input on compile-check) with the pack download: Chinese, Japanese, Korean and Devanagari still SKIP (Play services delivered nothing, no error text). Chinese/Japanese/Korean/Hindi OCR therefore remains a phone check; it cannot be proven on CI.
- Found by the full emulator run: the 100-page PDF export ran out of memory after other tests had used the app (passed alone). Fixed: pages are staged on disk as JPEG (quality 95 at the original tier) and read one at a time instead of all held as PNG and unpacked to raw pixels. `ExportFailedException` now keeps the underlying cause for diagnostics.
- Stress tests now run one scenario per app process (S1, S3, S3b, S4, S5, S6). Run all together in one process, the app eventually hit a Java heap OutOfMemoryError (first seen in the ads SDK thread, even with a 512 MB heap). The cause of that build-up across ~15 minutes of back-to-back tests is NOT found; each scenario passes on its own. `android:largeHeap="true"` was added as a mitigation, not proven needed. Worth a look with a real-device memory profile if users report crashes after long sessions.
- Latest full run (all five jobs green): 100-page export PDF 151 s / JPG 18 s / DOCX 19 s (debug build); 12/24/48 MP 45/79/126 s; 400 rapid edits consistent; 360 tray taps + 6 background cycles clean; 312 language/size/theme screens clean.


## Editing UX overhaul, steps 1 to 5 (2026-10-24/25)
Verified in CI (dart-check = analyzer plus unit/widget tests on pixels; emulator suite):
1. **Share/Save/Export at the top; banner reserved.** Measured on the emulator: 58 dp banner space always reserved, scan-detail Share/Export under the tab bar, export-screen Share/Save at the top. Banner is hidden only while the keyboard is up.
2. **Editing controls merged into two rows** (step buttons in one row, Edit/Copy all/Remove/Clear all/Done in the second). `overlay_controls_layout_test.dart`: at most 96 dp tall, no overflow, English/German/Russian at 360 and 411 dp. (The Clear buttons were reworked afterwards: see "Clear scopes" below.)
3. **Fill = type on the page.** Tap the page, type in the bar above the keyboard (live on the page), Date/tick/cross/saved phrases, size, width, bold, align, font, colour, Done. Double tap placed text, or Edit, reopens it. Tray hidden only while typing. `fill_v2_test.dart`: model JSON (legacy vs new), exported pixels (text lands at its place, wraps inside its box), typing bar. The old inline modal for Fill is gone.
4. **Filters rebuilt, one engine** (`filter_service.dart`): Shadow removal divides out the estimated paper colour (flattens a 50 percent shadow, tested), Black and white is adaptive (only pure 0/255, paper white on the shadowed side, writing black), Grayscale uses luminance weights, Colour enhance stretches levels. Size-independent so preview equals export (tested on small vs large, and exported pixels equal the filter output exactly, for PNG/JPG; PDF decodes). Strength slider monotonic (tested). Export screen: a filter picked there replaces the page filter; "Original" keeps each page's own filter, and the preview now shows exactly that (before, it ignored page filters).
5. **Compress sheet.** Tray Compress opens a sheet first (PDF/JPG, Small/Medium/Original with real size and percent saving measured on the edited first page, scaled by page count), then the export screen opens preselected. Estimates match the real JPG export within 10 percent (tested). PDF "Original" estimate was 0 before; now real.
- Emulator screen-measurement run: the emulator dropped off adb after the watermark step in three runs (cause unknown, not reproduced by the stress suite), so editor heights were verified with widget tests instead. Phone check still needed: Fill typing with the real keyboard, filters on a real photo of a shadowed page, Compress sheet.
- New strings to review natively: `editLabel`, `fillTapHint`, `fillTypeHint` (all 26 locales). The compress sheet reuses existing strings.

## Clear scopes (2026-10-25)
Every layer kind now has the same three buttons: **Clear this** (the selected item), **Clear page** (every item of that kind on the page you are viewing), **Clear all pages** (every item of that kind on every page). "Remove" no longer exists as a word. Stamps are per subtype (Text, Note, Date, Checkbox, Seal, Fill). Each clear shows "Cleared N" with Undo; the message disappears if another edit is made, so Undo never undoes something else. Deleting a saved signature moved to a delete button in the signature picker (undoable); "Clear all pages" on signatures takes placements off but keeps saved signatures.
- Unit tests (CI): `tray_flow_stress_test.dart` group "clear scopes" (page, all, per kind, undo/redo, nothing-matched adds no undo step, exported pixels, signature clears, Undo fills only empty spots). Layout test: six buttons fit at 360 and 411 dp in English, German and Russian.
- Emulator feature test (`emulator_features_test.dart`, workflow input `emu_features`): clear scopes with Undo through the real buttons, Fill typing/placing/double-tap re-edit/export, saved signature delete and Undo, Compress sheet, all four filters on a 12 MP shadowed page (about 15 s per page in the debug build; release is faster). All passing on the emulator.
- Previous note about the screen-measuring run that lost the emulator still stands; those numbers come from widget tests.
- Native review: new strings `clearPage`, `clearAllPages`, `clearedCount` (26 locales).

## Import / convert hardening (verified on emulator, Oct 2026)
- ID card output: real-size A4 default (85.6 mm cards, 300 dpi), Full width as an option in the result sheet.
- Conversion workspace: per-job scratch folder, always deleted; startup sweeper; no intermediates left for any source/target pair (emulator `clean-*` checks).
- Streaming PDF render: one page at a time, native PNG encode, direct JPG, 3000 px longest-side cap. Peak memory 2.6 GB -> ~0.85 GB; 100-page PDF->JPG 75 s -> 20 s.
- PDF text: real text read via pdfrx (instant), OCR only for scanned pages; page-range dialog (>20 pages); progress with ETA; checkpoints and resume.
- PDF import: 100 pages in ~40 s (was ~4 min), searchable immediately for text PDFs, background OCR only for scans; cancel leaves nothing behind.
- Dependency changes: added `pdfrx ^2.6.5`; `archive` 3.6 -> ^4.5.0 (DOCX export + device backup rely on it: phone-check a backup/restore round trip).
- Open: new strings need native review (pagesToReadTitle, pagesToReadHint, pageFromLabel, pageToLabel, readingPageProgress, readingPageEta, idLayoutRealSize, idLayoutFullWidth). Reading runs while the app is open (no background service); document appears after the render pass, not after page 1.

## Custom seal upgrade (verified in CI, Oct 2026)
- Fixed: size slider was dead above ~36; long text overflowed; Arabic/Hindi arc text broke; export was a 480 px picture enlarged; no preview; no saved seals; no tests.
- Now: auto-fitted lettering, working text-size (50-100 %), shapes oval/round/box, clean/classic font, separate text colour, worn-stamp look (deterministic), live preview, saved seals (12, long-press deletes), 256 px circular logos with optional transparent white, export drawn at output resolution (480-2048 px). Arabic/Hebrew set straight; Indic letters grouped by cluster (approximate shaping).
- Tests: test/seal_test.dart (25). Old seals keep their look (new fields default).
- Open: logo is still stored per seal layer (Copy all repeats it; now ~4x smaller); new strings need native review (sealShapeRound, sealFontSans, sealFontSerif, sealInkLook, sealSaveToLibrary, sealSavedHeading, sealTextColorLabel, sealTextColorSame, sealTextSizePercent, sealRemoveWhite, sealSavedMessage); not yet looked at on a real phone.

## Signature / Annotate / Watermark upgrade (Oct 2026)
- Signature pad: smoothed, speed-based (pen-like) width, 4 ink colours, 3 widths, undo, 240 px pad, cut to the ink on export (it was the whole pad, so it printed small), Type tab with two bundled script fonts (Dancing Script, Caveat; Latin letters only, others fall back to the normal font; about 0.5 MB), up to 6 saved signatures (an older single saved one joins once). Lines start where the finger lands (they started ~18 px late before; same fix in Annotate).
- Annotate: draws over the real page (crop and resize respected; rotation applies afterwards as before); the result is cut to the ink and placed by computed pctX/pctY/scale so it lands exactly where drawn; marks are items (select/move/recolour/resize/delete, eraser, undo/redo across all of it); highlighter is one even band at 40 % (no beads); shapes unchanged. Stored form is still a PNG layer (not vector), so very large enlargement still softens it.
- Watermark: Single / Diagonal / Tiled layouts, text or logo image (stored as PNG <= 1024 px in watermark_logos), page choice when adding (this page / all / typed range). Tiled draws with the same code in preview and export; the tiled preview ignores touches (chosen from the tool bar). A missing logo stops the export (never ships an unmarked page).
- Housekeeping: drawings and logos no document uses are removed at start-up once older than a day (Undo needs them for a while).
- Tests: test/signature_pad_test.dart, annotate_test.dart, watermark_test.dart, overlay_files_test.dart.
- Open: 23 new strings need native review; not yet looked at on a real phone (typing/drawing feel, tiled preview speed on big pages); watermark text single-line preview vs export size still approximate; typed signatures are Latin-only; signature colour is fixed per saved picture.

## Crop / Rotate / Filter / Resize upgrade (Oct 2026)

Done and checked by CI unit/widget tests (dart-check green); emulator run pending at time of writing:
- Smooth resizing everywhere (area average when shrinking, cubic when enlarging, soft-edged rotation) — `smooth_resize.dart`.
- Crop: four corners with perspective straightening, auto-detect, magnifier, A4/Letter/ID/Square shapes, "Crop" wording, header-only size read — `perspective.dart`, `perspective_crop_sheet.dart`. Layers placed before a skewed crop are only approximately kept in place; layers added after are exact.
- Rotate: ±45° straighten slider with grid (page keeps its size, edges trimmed); "all pages" is one undo step. Flip was NOT built: flipped pages would not match signatures/marks already placed.
- Filter: Magic colour, brightness/contrast, preview built from the cropped/tilted page, last slider value always shown, apply to all pages (one undo). `FilterType` gets new values at the END only.
- Resize: A4/A5/Letter + 150/300 dpi presets, size estimate from a real JPEG encode of a sample, enlarge warning.
- Bug found and fixed on the way: pages edited only by tilt or brightness/contrast were skipped on export.

Still owed: native review of the new strings (cropAuto, cropAspectFree/Id/Square, cropNoPageFound, straightenLabel, filterMagicColor, filterBrightnessLabel, filterContrastLabel, resizeUpscaleWarning); phone checks (dragging crop corners with a real finger, straighten feel, Magic colour on a real photo); the editor Crop overlaps the scanner's own edge detection at capture — decide whether to keep both.
