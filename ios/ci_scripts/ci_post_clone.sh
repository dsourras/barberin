#!/usr/bin/env bash
set -euo pipefail

cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is missing}"

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/flutter/bin:$PATH"

if [[ ! -d "$HOME/flutter" ]]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b 3.47.9 "$HOME/flutter"
fi
if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi
# Xcode Cloud resolves packages before Flutter can generate Package.resolved.
flutter config --no-enable-swift-package-manager
flutter precache --ios
flutter pub get
flutter build ios --release --config-only
(cd ios && pod install)
