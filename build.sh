#!/bin/zsh
# Builds Drift.app next to this script's parent folder.
set -e
cd "$(dirname "$0")"
OUT="../Drift.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$OUT/Contents/MacOS/Drift"
cat > "$OUT/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Drift</string>
  <key>CFBundleDisplayName</key><string>Drift</string>
  <key>CFBundleIdentifier</key><string>local.drift.wallpaper</string>
  <key>CFBundleExecutable</key><string>Drift</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force -s - "$OUT"
echo "Built $OUT"
