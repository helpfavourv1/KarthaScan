# Screenshot Strategy (Section 16 file #69)

No actual screenshots are produced by this document — that requires a
running build on a real or simulated device, which is outside what a
blueprint/codebase can generate. This is the shot list and messaging plan
for whoever captures them.

---

## Principles

1. **Every claim on a screenshot must be true today, not "true once we
   ship X."** Section 12 (Apple 2.3.7) and Play's equivalent policy both
   reject misleading marketing, and Section 19's Trust Promise is a
   permanent commitment — screenshots are exactly the kind of asset that
   quietly goes stale and turns a true claim into a false one after a
   pricing or feature change. Re-verify every text overlay against the
   live app before each submission, not just at launch.
2. **Lead with "free," because it's the actual differentiator.** The
   category is crowded with scanner apps that gate OCR or watermark
   exports behind a paywall — "free, unlimited, no watermark, no ads" is
   the honest hook, not a generic productivity pitch.
3. **Show the product, not just describe it.** Every screenshot is a real
   (or realistic mock) in-app screen, not a marketing illustration
   disconnected from the actual UI.

---

## Device frames

- **iPhone:** 6.7" display (current largest standard size at submission
  time) as the primary set; App Store Connect also requires a 6.5" and
  5.5" set unless Apple's scaling exemption applies to the versions
  submitted — check current App Store Connect requirements at submission
  time, since Apple's required size matrix changes across OS/device
  generations.
- **iPad:** 12.9" set, since the app supports iPad per Section 1's
  "iOS 14+" target (not iPhone-only).
- **Android:** one phone-size set (1080×1920 or current Play Console
  recommended resolution) and one 7"/10" tablet set.
- Use plain device bezels, not heavily stylized 3D-angled mockups — keeps
  the focus on the UI, consistent with the "no raw hex, semantic tokens"
  design discipline used throughout the app itself (Section 17).

---

## Shot list (6 screenshots, in display order)

| # | Screen | Callout text | Notes |
|---|---|---|---|
| 1 | Home screen with a populated document list | "Unlimited scanning. Unlimited OCR. Always free." | The hero shot — leads with the free-tier promise, not a feature list. |
| 2 | Live camera capture / edge detection in progress | "Scan documents in seconds" | Show the perspective-correction overlay mid-capture if the UI displays it. |
| 3 | Scan detail screen with OCR text panel expanded | "Every word, searchable" | Demonstrates OCR actually working, not just claimed. |
| 4 | Export format sheet (all 5 formats visible) | "5 export formats. Every one free." | Directly counters competitors that paywall PDF/Word export. |
| 5 | Settings screen showing theme + language picker | "Works the way you work — 11 languages, dark mode included" | Shows breadth without overselling. |
| 6 | Paywall screen (free vs. Pro comparison) | "Free forever. Pro is optional." | Deliberately transparent — showing the paywall itself, rather than hiding it, is more honest than only showing free-tier screens and surprising the user later. |

## App Store-specific: first-frame text overlay

Apple weights the first 2-3 screenshots most heavily for conversion.
Screenshot #1's overlay should be the single strongest, most literally
true claim available: **"Free unlimited OCR. No watermark. No ads."** —
matches `website/index.html`'s hero copy exactly, so the store listing and
the marketing site never contradict each other.

## What NOT to do

- No fabricated review quotes or star ratings overlaid on the screenshots
  themselves.
- No "#1 Scanner App" or similar ranking claims unless independently,
  currently true and verifiable at submission time.
- No feature shown that isn't actually shipped in the build being
  submitted alongside these screenshots.
