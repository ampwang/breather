#!/bin/bash
# Builds Breather.app with nothing but Apple's Command Line Tools (no Xcode project needed).
# First time only:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Breather.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Newer macOS SDKs implement SwiftUI's @State as a macro. The SwiftUIMacros plugin ships
# only with Xcode, not the Command Line Tools, so prefer Xcode's toolchain when installed.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcrun swiftc -O -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Breather"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "✅ Built $APP"
echo "   Install:  rm -rf /Applications/Breather.app && cp -R $APP /Applications/ && open /Applications/Breather.app"
