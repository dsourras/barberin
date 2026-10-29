#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
plist="ios/Runner/GoogleService-Info.plist"
android_config="android/app/google-services.json"
defines="macos/firebase.defines.json"
local_config="macos/Runner/Configs/Local.xcconfig"

if [[ ! -f "$plist" || ! -f "$android_config" ]]; then
  echo "Missing tracked Firebase app configuration for macOS CI." >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist"
}

if [[ "$(plist_value BUNDLE_ID)" != "com.barberin.app" ]]; then
  echo "The Firebase Apple app bundle ID does not match macOS Runner." >&2
  exit 1
fi

export BARBERIN_FIREBASE_API_KEY="$(plist_value API_KEY)"
export BARBERIN_FIREBASE_APP_ID="$(plist_value GOOGLE_APP_ID)"
export BARBERIN_FIREBASE_MESSAGING_SENDER_ID="$(plist_value GCM_SENDER_ID)"
export BARBERIN_FIREBASE_PROJECT_ID="$(plist_value PROJECT_ID)"
export BARBERIN_FIREBASE_STORAGE_BUCKET="$(plist_value STORAGE_BUCKET)"
export BARBERIN_FIREBASE_DATABASE_URL="$(plist_value DATABASE_URL)"
export GOOGLE_CLIENT_ID="$(plist_value CLIENT_ID)"
export GOOGLE_REVERSED_CLIENT_ID="$(plist_value REVERSED_CLIENT_ID)"
export BARBERIN_GOOGLE_SERVER_CLIENT_ID="$(ruby -rjson -e 'config = JSON.parse(File.read(ARGV.fetch(0))); clients = config.fetch("client").flat_map { |app| app.fetch("oauth_client", []) }; match = clients.find { |client| client["client_type"] == 3 }; abort "Missing Google Web OAuth client" unless match; print match.fetch("client_id")' "$android_config")"

ruby -rjson -e 'keys = %w[BARBERIN_FIREBASE_API_KEY BARBERIN_FIREBASE_APP_ID BARBERIN_FIREBASE_MESSAGING_SENDER_ID BARBERIN_FIREBASE_PROJECT_ID BARBERIN_FIREBASE_STORAGE_BUCKET BARBERIN_FIREBASE_DATABASE_URL BARBERIN_GOOGLE_SERVER_CLIENT_ID]; values = keys.to_h { |key| [key, ENV.fetch(key)] }; abort "Empty Firebase configuration" if values.values.any?(&:empty?); File.write(ARGV.fetch(0), JSON.pretty_generate(values) + "\n")' "$defines"
printf 'GOOGLE_CLIENT_ID = %s\nGOOGLE_REVERSED_CLIENT_ID = %s\nGOOGLE_SERVER_CLIENT_ID = %s\n' \
  "$GOOGLE_CLIENT_ID" "$GOOGLE_REVERSED_CLIENT_ID" "$BARBERIN_GOOGLE_SERVER_CLIENT_ID" > "$local_config"

echo "Prepared ignored macOS Firebase and Google CI configuration."
