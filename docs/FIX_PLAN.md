# Stress-review fix plan (all findings, phased)

Rules for every batch: smallest fix, no refactors, `build_and_deploy.yml` untouched, I run only the compile check (never the APK build), you rebuild the APK after a batch and test the "phone check" line. Numbers match `docs/OUTSTANDING.md`.

## Batch A: what leaves the app must be correct (export, share, filters)
| # | Problem | Fix | Phone check |
|---|---|---|---|
| 1 | Share/Email/home-list share send raw photos | Share and Email render each page through the same function Export/Print use, then send those files | Edit a page (crop, stamp, erase), Share: the received file shows the edits |
| 2 | Render failure silently returns the unedited original (redacted text comes back) | On failure show an error and stop; never fall back to the original | Normal export unchanged |
| 2b | Resize accepts 0, negative, huge | Validate 1 to a sane maximum, disable Confirm otherwise | Type 0: Confirm blocked |
| 6 | Resize stores the uncropped size, so crop then resize stretches | Sheet starts from the cropped size; re-crop clears stale resize | Crop, resize, confirm: no stretch |
| 5 | Filter alters caller's image in place; 50% grayscale same as 100% | Filter a copy; make strength actually blend | Grayscale slider changes result |
| 18 | Stamp export loses multi-line alignment, no wrap, no length limit | Wrap to box width, apply alignment, cap length | Long/multi-line note exports like preview |
| 17a | Convert ignores EXIF rotation | Bake orientation after decode in Convert | Gallery photo to PDF upright |
Unskip the 3 probe tests in `stress_findings_test.dart` once 2, 5 are fixed.

## Batch B: no lost pages, edits or search text (Pages manager, extract)
| # | Problem | Fix |
|---|---|---|
| 12 | Camera/gallery pages stay in cache and can vanish | Copy into managed pages when added |
| 3 | Pages-manager Rotate drops all edits for that page | Rotate by adding a turn to the page transform instead of writing a new file |
| 15 | Page changes never refresh OCR text/thumbnail; files orphaned | After save: update thumbnail, drop deleted pages' text, OCR new pages, delete orphan files |
| 16 | Extract and Convert-as-document lose edits and OCR text | Carry crop/rotation/layers for extracted pages; OCR the new document |
| 10 | Signature controller keeps stale page indexes after reorder/delete | Re-seed controller from the document after Pages manager saves |
| 9 | Watermark/signature identity collides (same text, same ink twice) | Give each layer its own id; key edits by id |
Phone check: reorder, delete, rotate, add from camera, extract; edits stay, search finds the right text.

## Batch C: tool screens and gestures
| # | Problem | Fix |
|---|---|---|
| 13 | Text box shows on Checkbox and Date sheets | Put the TextField inside the text/note condition |
| 14 | Dark mode: white-on-white in Text/Note/Date/Checkbox/Seal sheets | Use the theme's colours like the other sheets |
| 8 | Fill double-tap opens two sheets, then Null check | Ignore a second tap while one sheet is open |
| 19 | Eraser tap does nothing; Annotate resets colour on tool change; blank margins in layer | Tap draws a dot; keep colour for non-highlighter; trim canvas to drawing |
| 20 | Seal: re-tap Logo reopens picker; "star"/"image" centre text misread | Keep existing logo unless user picks again; store mode separately |
| 22 | Ad right after drawing a signature | Move the ad to after the signature is placed |

## Batch D: speed and memory (with queued 3.6)
| # | Problem | Fix |
|---|---|---|
| 4 | Preview re-decodes and re-renders the full photo on the UI thread; export holds all pages | Do the work in an isolate, cache the result, render pages one at a time |
| 19b/20b | Annotation PNG and seal logo decoded on UI thread | Decode in an isolate |
| 17b | PDF to TXT/CSV: every page, up to 4 OCR passes, no cancel, stalled progress | Latin pass only unless text is near empty, progress per page, Cancel button |
| 21 | Low-text pages trigger 4 OCR passes | Same rule as above |
Phone check: a 20+ page document scrolls and exports without freezing.

## Batch E: low items
Convert cleanup of `converted_docs`; txt to csv conversion; print filter names and Watermark default localised; orphan annotation/rotated files; Email fallback tells the user the attachment was dropped; print dialog controllers; crop/eraser/region/resize sheets show the rotated page.

## Needs your decision before I touch it
- 7: Adding or reverting a crop shifts stamps and signatures. Options: keep layers where they are on the page (recommended, needs conversion on crop) or warn before cropping a page with layers.
- 11: Compress opens Export as JPG and PDFs cannot be compressed. Do you want a real PDF compress (re-encode pages at lower quality)? Bigger piece of work.

## Not yet reviewed
`layer_control_panel.dart`, `signature_editor_bar.dart`, FTS migration path. I will read these before Batch C starts.
