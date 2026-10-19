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
- OPEN, small: watermarks are still identified by page + text (`removeWatermarkLayer`). Two watermarks with the same text on one page are removed together, and "Tools" (edit text, size, colour) on one of them replaces both with a single one. Fix needs an id on the watermark layer (model + stored data + panel).

## Tray stress test (2026-10-18)
`app/test/tray_flow_stress_test.dart` (runs in CI) fires 150 quick mixed edits, undo/redo, page delete/reorder/extract, delete-while-saving, and exports a heavily edited document in every format. Defects it found and that are fixed: double tap opened a tool twice (700 ms tap gap in the tray); a delete during queued edits let the document come back; undo restored a whole old copy of the document (undid renames, tags and deleted pages); text export of a document with no text wrote an empty file. Not tested here (needs a phone): memory use of very large pages (the resize limit is 40 megapixels), real gesture feel of the sheets, ads and share/print hand-off.
