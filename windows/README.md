# Barberin Windows target

The Windows client uses Firebase Auth for the signed-in identity and an
authenticated HTTPS backend adapter for shop data. It does not access the
Realtime Database directly and it does not require a Firebase service-account
key, database secret, or other private credential on the desktop.

The adapter covers:

- Appointments and the live schedule snapshot
- Clients and active barbers
- Service durations, prices, and add-ons
- Reports and unified dashboard metrics
- Billing status, including expired and grace-period access

## Local configuration

1. Register a Windows Firebase app for project `barbero-88d00`.
2. Copy `firebase.defines.example.json` to `firebase.defines.json`.
3. Replace the placeholder values with the public Firebase app configuration
   and the Google web client ID used by the existing sign-in setup.
4. Keep `firebase.defines.json` local. It is ignored by Git.

The backend authenticates every adapter request with the current Firebase ID
token and authorizes the requested `shopId` server-side. Never place a service
account JSON file, private key, or SMTP/API secret in this directory.

## Build

```powershell
flutter pub get
flutter build windows --release --dart-define-from-file=windows/firebase.defines.json
```

The generated executable is `Barberin.exe`.
