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

## Phase 5 status

Done in code: 5.2 backups, 5.3 CSV/DOCX text fixes, 5.4 debounce and wildcard escape, 5.5 dead code removal and README.
Left (needs more than code, or higher risk):
- 5.1 database version/undo hardening (wait for the rebuilt APK).
- 5.3 bundled Unicode font for PDF/DOCX text (needs a font file; the sandbox cannot download one).
- 5.4 index tags in search (needs a database change, belongs with 5.1).
- 5.5 bigger tap targets in the edit tray; unused storage-path setting; `pubspec.lock` still lists phosphoricons_flutter until the next `flutter pub get` is committed.

## Known gaps left on purpose

- Dark-mode background of the drawing canvas (needed white for exported ink).
- No new OCR-language setting (would need strings in 26 languages).
- Pages-manager rotate resets that page's other edits on Save.
- If a save fails the change stays on screen with an error (no rollback).
- `ITSAppUsesNonExemptEncryption` is a legal declaration for the owner to make.
- Share and review prompts default ON for new installs only.
- In-app wording still says "100% ON-DEVICE PRIVACY" (ticker) and "100% Private" (onboarding): ads and purchases use the network. Changing it means new text in 26 languages; your call on the wording.
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
5. app-ads.txt: host it at the root of the developer website named on the store listing, then check it in AdMob (Apps > View app-ads.txt status).
6. Account: payment profile, tax info, address PIN, payee name. Payments do not start without them.
7. Blocking controls: choose blocked ad categories / sensitive categories to suit a document scanner (kids, gambling etc.).
8. Not child-directed: leave "tagForChildDirectedTreatment" unset in the app and answer "not designed for children" in the store forms.
9. Test devices: if you add your phone as a test device for the EEA form test, remove it before launch.
10. Store forms must match: Play Data safety (ads, advertising ID, AD_ID permission is in the manifest) and Apple privacy labels (ads, tracking). Note `pubspec.yaml` description still says "no ads"; fix wording in the store listing/metadata.

## R8 shrinking: decided NOT to use
Owner measured only about 2 MB saved, not worth the release-only crash risk. `minifyEnabled` and `shrinkResources` are false again. `proguard-rules.pro` (full keep rules for every plugin, verified to pass an R8 run in CI) and `res/raw/keep.xml` stay in the repo, unused, in case shrinking is wanted later. To enable later: set both flags true and add `proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'` to the release block, then run the full phone check (OCR all scripts, PDF import/export, notifications with icon, ads and consent, subscriptions, crop, backup).

## Launch crash "Something went wrong" (fixed in code, confirm on phone)
- Cause: the share/review prompt listener (mounted around the whole app in Phase 2) read `EngagementService.instance` before the service existed, so the first frame threw "Null check operator used on a null value". Fixed by creating the service in `main.dart` before `runApp`.
- Also fixed: two `async initState` methods and a translated-text read in `initState` on the home screen (debug-only assertions).
- New test `app_boot_test.dart` starts the real app (home and onboarding) and fails with the call trace if anything throws. Both pass.
- Phone check: install the next APK; the app must open to onboarding (fresh install) or home.

## Stress review of the 21 tray tools (code reading + CI probes) - findings, fixes NOT yet made
Confirmed (code or CI probe):
1. HIGH Share (detail screen), Email and Share from the home list send the RAW saved photos, not the edited pages: crop, filter, rotation, eraser/redaction, signature, stamps are all missing (`document_tools_mixin.dart` shareDocument/emailDocument, `home_screen.dart:269`). Export and Print are correct.
2. HIGH Any failure while rendering a page silently returns the unedited ORIGINAL (`export_service.dart` `_processPage` catch). Probe: resize 0x0 brings the erased/redacted area back with no error. Resize accepts 0, negative and huge numbers (`rotate_resize_sheet.dart`).
3. HIGH Pages manager "Rotate" writes a new file, so on Confirm that page loses ALL its edits (crop, stamps, signature, eraser, OCR blocks): `updateDocumentPages` matches pages by file path.
4. HIGH Preview decodes, erases, crops, resizes, filters and re-encodes the FULL photo on the UI thread each time a page with edits is shown (`document_canvas.dart` `_loadPageAspect`), and export holds every page in memory (PDF embeds edited pages as PNG, large). Risk of freezes/out-of-memory on 20+ pages. Same family as queued 3.6.
5. MEDIUM Filter strength: probe shows the filter changes the caller's picture in place and the 50% grayscale equals full grayscale (slider does nothing for Grayscale). Other filters respond only through their parameters; the blend loop is redundant and slow. (My Phase 2.3 claim was only partly right.)
6. MEDIUM Resize always stores the sheet's numbers (defaults to the UNCROPPED size): crop then Resize then Confirm stretches the cropped area to the old size; a later re-crop keeps the stale resize.
7. MEDIUM Crop/Revert change the frame that stamps and signatures are positioned in (percent of the cropped frame), so existing layers shift when a crop is added or reverted; Revert leaves layers behind.
8. MEDIUM Fill: double-tap opens two sheets; the second close hits `_fillGhostPageIndex!` after it was cleared (Null check, layer lost) (`full_screen_edit_screen.dart:122`).
9. MEDIUM Watermark identity is (page, text) and signature identity is (page, ink): two watermarks with the same text, or the same signature twice on one page, are edited/deleted together.
10. MEDIUM Signature controller keeps old page indexes after Pages manager reorder/delete; the next signature change can write them back over the remapped ones (needs phone check).
11. MEDIUM Compress tray button opens Export with JPG; PDF cannot be compressed at all.
Plausible, to confirm on a phone: photos with EXIF rotation (camera/gallery inserted via Pages manager) export/print sideways and misalign crop/eraser (no EXIF handling anywhere; image_picker with imageQuality in the scanner path likely bakes it).
Low: Region OCR, Crop, Eraser and Resize sheets all show the unrotated raw photo; Print filter dropdown shows raw enum names; Watermark default 'CONFIDENTIAL' not localised; annotation PNGs and rotated pages leave orphan files; Email falls back to mailto silently dropping the attachment; print controllers disposed while the dialog animates out.
Not reviewed in depth: Seal/Text/Note/Date/Check drawing parity with export (sizes, fonts, RTL), OCR service internals, Convert screen, Eraser overlay gestures, sqlite FTS/migrations.
