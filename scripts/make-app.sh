#!/bin/bash
# 릴리즈 빌드 후 더블클릭으로 실행 가능한 CleanMac.app 번들을 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="CleanMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CleanMacBar "$APP/Contents/MacOS/CleanMacBar"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CleanMacBar</string>
    <key>CFBundleIdentifier</key>
    <string>local.cleanmac.menubar</string>
    <key>CFBundleName</key>
    <string>CleanMac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# 로컬 실행용 ad-hoc 서명
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ $APP 생성 완료 — 더블클릭하거나 'open $APP'으로 실행하세요."
