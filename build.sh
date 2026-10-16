#!/bin/bash
# 无 Xcode 环境下的构建 + .app bundle 组装 + ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")"

APP="MiniTrafficMonitor.app"
BIN="MiniTrafficMonitor"
BUNDLE_ID="com.mini.trafficmonitor"
VERSION="1.0.0"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$BIN" "$APP/Contents/MacOS/$BIN"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>MiniTrafficMonitor</string>
    <key>CFBundleDisplayName</key><string>MiniTrafficMonitor</string>
    <key>CFBundleExecutable</key><string>${BIN}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo ""
echo "OK  $APP  ($(du -sh "$APP" | cut -f1))"
echo "    启动: open $APP   或直接运行 $APP/Contents/MacOS/$BIN"
