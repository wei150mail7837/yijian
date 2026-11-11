#!/bin/zsh
# 译见 YiJian 构建脚本：swiftc 直编（无 Xcode 依赖，纯 AppKit）
set -e
cd "$(dirname "$0")"
VERSION="1.0.0"

APP="YiJian.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$BIN" "$RES"

echo "[1/3] swiftc 编译..."
swiftc -O \
  -o "$BIN/YiJian" \
  Sources/*.swift \
  -framework AppKit -framework Carbon -framework Vision -framework ServiceManagement

echo "[2/3] Info.plist..."
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>译见</string>
  <key>CFBundleDisplayName</key><string>译见</string>
  <key>CFBundleIdentifier</key><string>app.yijian.translate</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>YiJian</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>个人自用</string>
</dict>
</plist>
EOF

echo "[2.5/3] 图标（assets/make_icon.swift 程序化生成）..."
ICONTMP=$(mktemp -d)
swift assets/make_icon.swift "$ICONTMP"
iconutil -c icns "$ICONTMP/AppIcon.iconset" -o "$RES/AppIcon.icns"
cp "$ICONTMP/trayTemplate.png" "$ICONTMP/trayTemplate@2x.png" "$RES/"
cp "$RES/AppIcon.icns" assets/AppIcon.icns
cp "$ICONTMP"/trayTemplate*.png assets/
rm -rf "$ICONTMP"

# ad-hoc 签名保证本地运行
echo "[3/3] ad-hoc 签名..."
codesign --force --sign - "$APP"

du -sh "$APP"
echo "构建完成: $APP"
