# Changelog

All notable changes to KatharScan will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-08

### Added
- **Core Features**
  - Unlimited document scanning with on-device OCR
  - 26 language support for app interface (English, Spanish, French, German, Portuguese, Arabic, Hindi, Japanese, Korean, Chinese, Hebrew, Indonesian, Italian, Dutch, Turkish, Swedish, Norwegian, Danish, Finnish, Malay, Polish, Russian, Ukrainian, Vietnamese, Bengali, Thai)
  - Export formats: PDF, Word (.docx), TXT, JPG, PNG, CSV
  - Folders, tags, and full-text search
  - Non-destructive editing with undo/redo

- **Editing Suite**
  - 21-tool edit suite (annotate, watermark, stamps, seals, text, notes, dates, checkboxes)
  - E-signature with saved signature library
  - Fill-to-type form filling with snippet library
  - Custom seals and text stamps
  - Region OCR for selective text extraction

- **Privacy & Monetization**
  - 100% on-device processing (no server, no cloud)
  - No account required
  - No watermarks
  - Optional one-time ad removal purchase
  - App Tracking Transparency (ATT) support for iOS 14+

- **Platform Support**
  - Android (targetSdk 36, minSdk 21)
  - iOS (TestFlight ready, iOS 13.0+)

### Security
- All documents stored locally on device
- AdMob integration with SKAdNetwork compliance
- Privacy manifest for Apple App Store requirements

### Known Limitations
- Google ML Kit Doc Scanner is Android-only (iOS falls back to camera import)
- Some OCR scripts (Chinese, Korean, Japanese) require on-demand language pack download
