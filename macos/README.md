# Barberin macOS configuration

The macOS target does not store Firebase or Google credentials in Dart or in the
repository. Configure them locally on the Mac used for development or release.

1. Use the Firebase Apple app registered for bundle ID `com.barberin.app`.
2. Copy `macos/firebase.defines.example.json` to `macos/firebase.defines.json` and fill it with the Firebase app configuration. Do not use a service-account key here.
3. Copy `macos/Runner/Configs/Local.xcconfig.example` to `macos/Runner/Configs/Local.xcconfig` and fill the Google OAuth client identifiers.
4. Verify that the Google server client ID is the Web OAuth client ID, not the Apple client ID. Build with the guarded release script:

```bash
flutter pub get
bash tools/build-macos-release.sh
```

Firebase Auth, Realtime Database, Storage and Messaging use the injected
`FirebaseOptions`. Google Sign-In uses the local Xcode client settings. StoreKit
uses the same product IDs as the Apple targets: `barbero_monthly` and
`barbero_yearly`.

The release script refuses to build with missing or placeholder Firebase and
Google configuration. For Xcode Cloud, `macos/ci_scripts/ci_post_clone.sh`
installs Flutter and CocoaPods and generates the ignored configuration from
the tracked Firebase Apple and Android app configuration. The macOS Release
target uses automatic signing so Xcode Cloud can use a cloud-managed Apple
Distribution certificate. The first Xcode Cloud workflow must be created in
Xcode with an Apple Developer account; App Store Connect cannot create that
initial workflow. Select the macOS Runner product, the Barberin GitHub branch,
set the next build number to at least 21, and select an archive/distribution
action for the existing macOS app. Do not enable
automatic distribution until a signed build has been tested. The existing
`Barberin Shared Mac App Store 2026` profile matches this bundle ID, whereas
`Barberin macOS App Store 2026` belongs to a different bundle ID.
