#!/bin/bash
# Build "E3372 Modem.app" (arm64) into ../build/.
set -euo pipefail
cd "$(dirname "$0")"
APP="../build/E3372 Modem.app"
VERSION=1.0.0

swift build -c release --arch arm64
rm -rf "$APP" ../build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/E3372Modem "$APP/Contents/MacOS/E3372Modem"

swift tools/make-icon.swift ../build/AppIcon.iconset
rm -f ../build/AppIcon.iconset/icon_1024x1024.png ../build/AppIcon.iconset/icon_8x8@2x.png
iconutil -c icns ../build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>E3372 Modem</string>
	<key>CFBundleDisplayName</key><string>E3372 Modem</string>
	<key>CFBundleIdentifier</key><string>io.github.sniffr.e3372-modem</string>
	<key>CFBundleExecutable</key><string>E3372Modem</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>E3372 Modem talks to your Huawei stick over its USB network connection.</string>
	<key>NSAppTransportSecurity</key>
	<dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
