#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(awk -F'[<>]' '/CFBundleShortVersionString/{getline; print $3; exit}' Resources/Info.plist 2>/dev/null || true)"
VERSION="${VERSION:-0.1.0}"
rm -rf dist
swift build -c release --product ConsolepilotAppBinary -j 1
swift build -c release --product consolepilot -j 1
mkdir -p dist/Consolepilot.app/Contents/MacOS dist/Consolepilot.app/Contents/Resources
cp .build/arm64-apple-macosx/release/ConsolepilotAppBinary dist/Consolepilot.app/Contents/MacOS/Consolepilot
cp .build/arm64-apple-macosx/release/consolepilot dist/consolepilot
cp Resources/Consolepilot.entitlements dist/Consolepilot.app/Contents/Resources/
cat > dist/Consolepilot.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Consolepilot</string>
<key>CFBundleDisplayName</key><string>Consolepilot</string>
<key>CFBundleIdentifier</key><string>com.local.consolepilot</string>
<key>CFBundleExecutable</key><string>Consolepilot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
cp Sources/Infrastructure/Config/DefaultConfig.toml dist/config.example.toml
./Scripts/sign.sh dist/Consolepilot.app
(cd dist && ditto -c -k --keepParent Consolepilot.app "Consolepilot-${VERSION}.zip")
echo "产物就绪：dist/  版本 ${VERSION}"
