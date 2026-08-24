# Barberin macOS configuration

The macOS target does not store Firebase or Google credentials in Dart or in the
repository. Configure them locally on the Mac used for development or release.

1. Register a macOS/Apple Firebase app with bundle ID `com.barberin.app.macos`.
2. Copy `macos/firebase.defines.example.json` to `macos/firebase.defines.json` and fill it with the Firebase app configuration. Do not use a service-account key here.
3. Copy `macos/Runner/Configs/Local.xcconfig.example` to `macos/Runner/Configs/Local.xcconfig` and fill the Google OAuth client identifiers.
4. Run the build with the local defines file:

```bash
flutter pub get
flutter build macos --release --dart-define-from-file=macos/firebase.defines.json
```

Firebase Auth, Realtime Database, Storage and Messaging use the injected
`FirebaseOptions`. Google Sign-In uses the local Xcode client settings. StoreKit
uses the same product IDs as the Apple targets: `barbero_monthly` and
`barbero_yearly`.
