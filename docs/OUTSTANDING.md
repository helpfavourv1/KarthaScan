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
| 4.4 | Android 13+ phone: gallery import (image and PDF) and Save to Downloads still work; no photo-access permission prompt appears. |
| 4.3 | Privacy manifest builds in Xcode/Codemagic without warnings (iOS). |

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
- Apple Team ID, Codemagic keys.
