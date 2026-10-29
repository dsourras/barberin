#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
defines="macos/firebase.defines.json"
local_config="macos/Runner/Configs/Local.xcconfig"

if [[ ! -f "$defines" || ! -f "$local_config" ]]; then
  echo "Missing local macOS Firebase or Google configuration. See macos/README.md." >&2
  exit 1
fi

for key in \
  BARBERIN_FIREBASE_API_KEY \
  BARBERIN_FIREBASE_APP_ID \
  BARBERIN_FIREBASE_MESSAGING_SENDER_ID \
  BARBERIN_FIREBASE_PROJECT_ID \
  BARBERIN_FIREBASE_STORAGE_BUCKET \
  BARBERIN_FIREBASE_DATABASE_URL \
  BARBERIN_GOOGLE_SERVER_CLIENT_ID; do
  value="$(plutil -extract "$key" raw -o - "$defines" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == REPLACE_WITH_* ]]; then
    echo "Missing macOS build setting: $key" >&2
    exit 1
  fi
done

for key in GOOGLE_CLIENT_ID GOOGLE_REVERSED_CLIENT_ID GOOGLE_SERVER_CLIENT_ID; do
  value="$(sed -nE "s/^${key}[[:space:]]*=[[:space:]]*(.*)/\1/p" "$local_config" | head -n 1)"
  if [[ -z "$value" || "$value" == REPLACE_WITH_* ]]; then
    echo "Missing macOS build setting: $key" >&2
    exit 1
  fi
done

flutter build macos --release --dart-define-from-file="$defines" "$@"
