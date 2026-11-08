#!/bin/bash
# 검증용 상태 항목 앱 번들: build/MenuBarFixture.app (앱 종료 검증처럼 .app 번들이 필요한 시험용)
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modcache"
swift build -c release --product menubar-fixture
APP=build/MenuBarFixture.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/menubar-fixture" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.local.menubar-fixture</string>
  <key>CFBundleName</key><string>MenuBarFixture</string>
  <key>CFBundleExecutable</key><string>menubar-fixture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "생성됨: $PWD/$APP"
