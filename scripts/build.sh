#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
APP="dist/Kernel Atlas.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/ModuleCache \
  -framework AppKit -framework SwiftUI -framework SceneKit -framework Metal \
  Sources/*.swift -o "$APP/Contents/MacOS/KernelAtlas"
cp Corpus/index.json "$APP/Contents/Resources/index.json"
ditto Corpus/linux "$APP/Contents/Resources/linux"
cp research/kernel-sha256sums.asc "$APP/Contents/Resources/kernel-sha256sums.asc"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Kernel Atlas</string>
<key>CFBundleDisplayName</key><string>Kernel Atlas</string>
<key>CFBundleExecutable</key><string>KernelAtlas</string>
<key>CFBundleIdentifier</key><string>local.kernelatlas.mac</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
<key>NSHumanReadableCopyright</key><string>Kernel Atlas. Linux source © its original authors, GPL-2.0.</string>
</dict></plist>
PLIST
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $PWD/$APP"
