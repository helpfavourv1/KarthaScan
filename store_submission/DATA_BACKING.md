# Data Backing Documentation (Section 16 file #68)

Backing reference for filling out Apple's App Privacy ("Privacy Nutrition
Label") questionnaire and Google Play's Data Safety form. Keep this
document in sync with `lib/core/utils/constants.dart`'s
`AppPermissionRationale` and with `AndroidManifest.xml` / `Info.plist` — if
a permission is ever added or removed from those files, update this
document in the same change.

---

## Architecture summary

KatharScan has no backend server (Section 1/13). There is nothing to
declare as "collected and sent to us" for the simple reason that nothing
is sent anywhere by KatharScan itself. The only network traffic KatharScan
initiates is:

1. **In-app purchase validation** — a request to Apple's/Google's own
   billing servers, not to KatharScan.
2. **Whatever the user explicitly does through the OS share sheet** (e.g.
   choosing to share a file to Drive, iCloud, email, etc.) — that traffic
   goes from the OS to the destination the user picked, not through
   KatharScan.

Everything else — scanning, OCR, storage, search, export, filters,
signatures — happens entirely on-device.

---

## Permission-by-permission justification

| Permission | Platform | Justification |
|---|---|---|
| `CAMERA` | Android + iOS (`NSCameraUsageDescription`) | Core scanning feature. Required to capture document photos. Rationale string shown to the user: *"To scan documents. Images are processed on your device and stored locally."* |
| `READ_MEDIA_IMAGES` (Android 13+) / `NSPhotoLibraryUsageDescription` (iOS) | Both | Importing an existing photo of a document instead of using the live camera (used by the manual crop fallback, file #75, and the ordinary gallery-import path). Rationale string: *"To import photos of documents from your gallery for scanning."* |
| `READ_EXTERNAL_STORAGE` (maxSdk 32) | Android only | Legacy equivalent of `READ_MEDIA_IMAGES` for Android 12 and below, where the modern scoped media permission doesn't exist yet. Same justification as above. |
| `WRITE_EXTERNAL_STORAGE` (maxSdk 28) | Android only | Legacy requirement for writing exported files on Android 9 and below, before scoped storage. Not used or requested on modern Android. |
| `INTERNET` | Android only (iOS doesn't gate this behind a runtime permission) | Required solely for in-app purchase validation with Google Play Billing. Not used for any other network activity KatharScan itself initiates. |

**Explicitly NOT requested, on either platform:** location (fine or
coarse), contacts, SMS, call log, biometric authentication, notifications,
microphone, or video-specific media access (`READ_MEDIA_VIDEO`) — none of
these trace to any feature in this app.

---

## App Store Privacy Nutrition Label — suggested answers

| Data type | Collected? | Linked to user? | Used for tracking? |
|---|---|---|---|
| Photos | Yes — user-selected only (gallery import) | No | No |
| Purchase history | Yes — via StoreKit, for entitlement status | No (handled by Apple) | No |
| Camera | N/A — images processed and stored on-device, never transmitted by KatharScan | — | — |
| Everything else (contacts, location, identifiers, usage data, diagnostics, etc.) | No | — | — |

**App Tracking Transparency (ATT):** not applicable. No advertising
identifier is requested and no cross-app/cross-site tracking occurs — see
Section 12.

---

## Google Play Data Safety form — suggested answers

- **Does your app collect or share any of the required user data types?**
  Photos/videos: *collected, not shared* (user-selected gallery images,
  processed locally; "collected" here reflects that the app reads a
  user-selected file, not that it's transmitted anywhere).
- **Is data encrypted in transit?** N/A — no user data is transmitted by
  the app itself, aside from IAP validation traffic that goes directly to
  Google's billing servers over their own encrypted channel.
- **Can users request data deletion?** Not applicable in the account-based
  sense Play's form is built around — there is no KatharScan account or
  server-side record to delete. Uninstalling the app removes all local
  data.
- **Advertising ID:** not collected. No ad SDK is present in this app.
- **Location, personal identifiers, financial info, health data, contacts,
  SMS/call logs:** none collected.

---

## Review notes for whoever submits this

If either store's questionnaire UI has changed since this document was
written, re-derive the answers from the "Permission-by-permission
justification" table above rather than copying the suggested answers
verbatim without checking — the underlying facts (no server, on-device
processing, no ad SDK, no tracking) are what's durable here, not the exact
wording of a form that both companies periodically redesign.
