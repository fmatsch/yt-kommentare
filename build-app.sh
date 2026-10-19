#!/bin/zsh
# build-app.sh — baut "YT Kommentare.app" im Projektordner.
#   ./build-app.sh           Release
#   ./build-app.sh --debug   Debug
set -e
cd "$(dirname "$0")"

# Die Command Line Tools 27 liefern das Makro-Plugin für SwiftUIs @State nicht
# mit — gegen das noch installierte SDK 26.5 baut es. Ein gesetztes SDKROOT gewinnt.
OLD_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -z "$SDKROOT" && -d "$OLD_SDK" ]]; then
    export SDKROOT="$OLD_SDK"
fi

CONFIG="release"; FLAGS="-c release"
[[ "$1" == "--debug" ]] && { CONFIG="debug"; FLAGS=""; }
swift build ${=FLAGS}

APP="YT Kommentare.app"
pkill -x YTKommentare 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/${CONFIG}/YTKommentare" "$APP/Contents/MacOS/YTKommentare"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>YTKommentare</string>
    <key>CFBundleIdentifier</key><string>at.fmatsch.ytkommentare</string>
    <key>CFBundleName</key><string>YT Kommentare</string>
    <key>CFBundleDisplayName</key><string>YT Kommentare</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>de</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
echo "Fertig: $(pwd)/$APP"
