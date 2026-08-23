# Data Backing Documentation

KatharScan has no backend server. There is nothing to declare as "collected and sent to us" for the simple reason that nothing is sent anywhere by KatharScan itself.

## Network traffic KatharScan initiates:
1. **In-app purchase validation** — a request to Apple's/Google's own billing servers.
2. **Google Mobile Ads** — ads are served by Google AdMob. This is disclosed in the app's privacy policy and requires Google's advertising identifier (on Android) or Apple's advertising identifier (on iOS) for ad targeting. Users can remove all ads with a one-time in-app purchase.
3. **Whatever the user explicitly does through the OS share sheet** — traffic goes from the OS to the destination the user picked.

## Permission-by-permission justification

| Permission | Platform | Justification |
|---|---|---|
| `CAMERA` | Android + iOS | Core scanning feature. |
| `READ_MEDIA_IMAGES` (Android 13+) / `NSPhotoLibraryUsageDescription` (iOS) | Both | Importing an existing photo. |
| `READ_EXTERNAL_STORAGE` (maxSdk 32) | Android only | Legacy equivalent. |
| `WRITE_EXTERNAL_STORAGE` (maxSdk 28) | Android only | Legacy requirement. |
| `INTERNET` | Android only | For IAP validation and AdMob. |

## App Store Privacy Nutrition Label — suggested answers

| Data type | Collected? | Linked to user? | Used for tracking? |
|---|---|---|---|
| Photos | Yes — user-selected only | No | No |
| Purchase history | Yes — via StoreKit | No | No |
| Advertising ID | Yes — via AdMob | Yes | Yes (for ad serving) |
| Everything else | No | — | — |

## Google Play Data Safety form — suggested answers

- **Does your app collect or share any of the required user data types?**
  - Photos/videos: *collected, not shared*
  - Advertising ID: *collected, not shared* (for ad serving)
- **Is data encrypted in transit?** N/A — no user data is transmitted by the app itself.
- **Can users request data deletion?** Uninstalling the app removes all local data.
