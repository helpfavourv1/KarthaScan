# KatharScan

Free document scanning with unlimited OCR. No watermark, no account
required, and no ads.

## Repository structure

```
KatharScan/
├── app/                    Flutter app (iOS + Android)
├── website/                Static HTML/CSS marketing site — hand-written,
│                           deliberately not Flutter Web (see app/lib and
│                           Section 2 of the design blueprint for why)
├── .github/workflows/      Android CI (manual trigger only)
├── codemagic.yaml          iOS CI (manual trigger only)
└── store_submission/       App Store / Play Store submission reference docs
```

## Before your first build

Five placeholders are not yet filled in, tracked from the original design
document:

| Placeholder | Where | Blocks Android? |
|---|---|---|
| `[YOUR_DOMAIN]` | `website/privacy.html`, `website/support.html`, `app/lib/core/utils/constants.dart` (`AppSupportContact`) | No |
| `[YOUR_CF_ACCOUNT_ID]` | Cloudflare Pages deployment (not yet wired up) | No |
| `[YOUR_TEAM_ID]` | `app/ios/ExportOptions.plist`, `codemagic.yaml` | Yes — iOS only |
| `[YOUR_KEY_ID]` / `APP_STORE_CONNECT_KEY_IDENTIFIER` | Codemagic environment variable group | Yes — iOS only |
| `[YOUR_ISSUER_ID]` / `APP_STORE_CONNECT_ISSUER_ID` | Codemagic environment variable group | Yes — iOS only |

Android can be built and run today without any of these. iOS needs the
Team ID and App Store Connect API credentials before `codemagic.yaml` can
actually sign and publish a build.

You'll also need real signing material this repo never contains:

- **Android:** an upload keystore + `android/key.properties` (gitignored —
  see `app/.gitignore`). `android/app/build.gradle` reads from this file
  and falls back to unsigned local builds if it's absent.
- **iOS:** a Distribution certificate and provisioning profile, or a
  Developer Portal integration connected in Codemagic's UI for automatic
  signing (see the note at the top of `codemagic.yaml`).
- **Launcher icon / splash source images:** `flutter_launcher_icons.yaml`
  and `flutter_native_splash.yaml` both expect PNG source files
  (`assets/icon_source.png`, `assets/splash_logo.png`) that don't exist
  yet — `assets/logo.svg` is vector and needs to be rasterized once,
  outside this repo, before running either generator.

## Building locally

```bash
cd app
flutter pub get      # also runs `flutter gen-l10n`, producing
                      # lib/l10n/app_localizations.dart from the 11 ARB
                      # files in lib/l10n/ — this generated file is
                      # gitignored and rebuilds automatically
flutter analyze
flutter test
flutter run
```

### Version-pin caveat

`pubspec.yaml`'s dependency versions were chosen for consistency with the
pinned Flutter 3.24.0 / Dart ~3.5 timeframe, based on known package
release history — they were not resolved against pub.dev's actual
dependency solver, since this repo was authored without network access.
Run `flutter pub get` and `flutter pub outdated` before the first real CI
build, resolve whatever version conflicts Flutter reports, and update
`pubspec.yaml` with the exact resolved versions.

A few individual dependencies carry their own narrower caveats — search
`pubspec.yaml` and the relevant service file for comments flagging
anything verified against a single documentation source rather than
confirmed working end-to-end (e.g. `pdf_crypto`'s exact API in
`export_service.dart`, `flutter_doc_scanner`'s return shape in
`doc_scanner_service.dart`).

## Architecture

- **`lib/core/models/`** — immutable data models (`copyWith`, `toJson`/
  `fromJson`, `==`/`hashCode`). No Flutter framework dependency beyond
  what's needed for typing (e.g. `ThemeMode`, `Color`).
- **`lib/core/services/`** — business logic that may wrap a plugin
  (sqflite, ML Kit, `flutter_doc_scanner`, share_plus, `pdf`/`archive`/
  `image`), as long as the plugin presents uniform cross-platform behavior
  with no OS-branching decision logic in the wrapper. No `dart:io`, except
  one narrow, explicitly-documented exception in `export_service.dart` for
  writing generated export bytes to disk.
- **`lib/platform/`** — the two services whose *behavior itself* genuinely
  diverges by OS: `permission_service.dart` (Android's rationale/
  permanently-denied flow differs structurally from iOS's) and
  `iap_service.dart` (Play Billing's acknowledge-within-3-days requirement
  vs. StoreKit's receipt/restore model).
- **`lib/core/providers/`** — app state, one `ValueNotifier`-based provider
  per domain (scans, folders, settings, theme, subscription).
  `ChangeNotifierProvider`, `Consumer`, and `context.watch<T>()` are never
  used anywhere in this codebase — `provider` is dependency injection only
  (`Provider.value` + `Provider.of(context, listen: false)`); all
  reactivity is `ValueNotifier` + `ListenableBuilder`. See the comment
  block at the top of `lib/core/utils/constants.dart`.
- **`lib/widgets/`** — presentational components. They take data and
  callbacks via constructor, not direct provider/service access, so
  they're reusable and don't need a BuildContext-bound lookup to render.
- **`lib/screens/`** — the glue layer: wires providers to widgets via
  `Provider.of` + `ListenableBuilder`, handles navigation via `go_router`
  (`context.push(...)`, never `Navigator.pushNamed(...)`).
- **`lib/l10n/`** — 11 ARB files feeding Flutter's `gen-l10n` codegen.
  Every user-facing string in `lib/widgets/` and `lib/screens/` routes
  through `AppLocalizations.of(context)!`, with one deliberate exception:
  language endonyms in the language picker (`Español`, `日本語`, etc.) are
  never translated, since a language picker should always show a
  language's name for itself regardless of the app's current UI language.

## Testing

```bash
cd app
flutter test
```

CI (`build_and_deploy.yml`) additionally fails the build if any file under
`lib/` contains `throw UnimplementedError` — a stub check, not a
substitute for real test coverage.

## Contributing

- Match the layering rules above — a new file that wraps a plugin
  belongs in `core/services/` unless its behavior genuinely diverges by
  OS, in which case it belongs in `platform/`.
- Every new user-facing string needs an ARB key added to all 11
  `lib/l10n/app_*.arb` files, not just `app_en.arb` — a mismatched key set
  breaks `flutter gen-l10n`.
- No `TODO`, `FIXME`, or `throw UnimplementedError()` in anything merged —
  CI enforces this for the latter; treat the first two as blocking review
  comments in practice.
- If a change touches a Pro-gated feature, check it against Section 19's
  Trust Promise before merging: "we will never lock a free feature behind
  a paywall" is a permanent commitment, not launch-only copy.
