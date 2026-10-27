#!/bin/zsh
# Builds Boto and wraps the SwiftPM executable in a minimal .app bundle so macOS gives it a window and Dock icon.
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

swift build
bin="$(swift build --show-bin-path)/Boto"

app="$root/build/Boto.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Boto"
cp -R "$root/Resources/Fonts" "$app/Contents/Resources/Fonts"

iconset="$root/build/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
icon="$root/Resources/Brand/boto-icon-1024.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Boto</string>
    <key>CFBundleIdentifier</key><string>app.boto.kanban</string>
    <key>CFBundleName</key><string>Boto</string>
    <key>CFBundleDisplayName</key><string>Boto</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Boto adds your card due dates to a calendar named Boto, with an alert at 9:00.</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --entitlements "$root/Resources/Boto.entitlements" --sign - "$app" >/dev/null
echo "$app"
