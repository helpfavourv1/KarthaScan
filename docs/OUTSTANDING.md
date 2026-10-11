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

## R8 shrinking (phone check after the next APK)
Code shrinking and resource shrinking are ON in the release build (`app/android/app/build.gradle`, rules in `proguard-rules.pro`, kept resources in `res/raw/keep.xml`). CI runs the real R8 step (no APK) and it passes, but R8 cannot prove runtime behaviour. On the first release APK check each of these on a phone:
- Open the app, scan a page (document scanner), run OCR in Latin, Chinese, Japanese, Korean.
- Import a PDF (page rendering), export PDF/DOCX/TXT/CSV, print, share, save to Downloads.
- Crop a photo (UCrop screen opens), pick an image/file, camera permission prompt.
- Schedule a notification and see it appear WITH its icon; restart the phone and check it survives.
- Banner and interstitial test ads load; consent flow runs.
- Subscription screen loads products and restore works.
- Backup export and import.
- Settings (package info), links opening.
If anything crashes only in release, the fix is a keep rule; send me the crash line.
