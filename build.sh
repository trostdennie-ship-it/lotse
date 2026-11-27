#!/bin/sh
# Baut Lotse.app und installiert sie nach /Applications.  Aufruf: ./build.sh [--no-install]
set -e
cd "$(dirname "$0")"
swift build -c release > build.log 2>&1 || { tail -40 build.log; echo "BUILD FEHLGESCHLAGEN" >&2; exit 1; }
tail -2 build.log
# Außerhalb von „Dokumente" bauen: Dort hängt der Finder dem Paket Attribute an, an denen die Signatur scheitert.
WORK="${TMPDIR:-/tmp}/lotse-build"
APP="$WORK/Lotse.app"
mkdir -p "$WORK"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Lotse "$APP/Contents/MacOS/Lotse"
# App-Symbol (neu erzeugen: python3 scripts/make-icon.py)
mkdir -p "$APP/Contents/Resources"
[ -f Resources/Lotse.icns ] && cp Resources/Lotse.icns "$APP/Contents/Resources/Lotse.icns"
[ -f Resources/Termin.wav ] && cp Resources/Termin.wav "$APP/Contents/Resources/Termin.wav"
[ -f Resources/Geist.woff2 ] && cp Resources/Geist.woff2 Resources/Geist-OFL.txt "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Lotse</string>
    <key>CFBundleDisplayName</key><string>Lotse</string>
    <key>CFBundleIdentifier</key><string>local.lotse.app</string>
    <key>CFBundleExecutable</key><string>Lotse</string>
    <key>CFBundleIconFile</key><string>Lotse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Lotse zeigt deinen nächsten Termin in der Insel.</string>
    <key>NSMicrophoneUsageDescription</key><string>Lotse nimmt beim Mitschnitt eines Calls auch deine Stimme auf.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Lotse schreibt deine Mitschnitte auf diesem Mac mit.</string>
    <key>NSLocationUsageDescription</key><string>Lotse rechnet aus, wann du zu einem Termin losgehen musst.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Lotse rechnet aus, wann du zu einem Termin losgehen musst.</string>
    <key>NSLocalNetworkUsageDescription</key><string>Lotse findet deine Sonos-Räume im WLAN, um Musik dorthin zu schicken.</string>
    <key>NSAppleEventsUsageDescription</key><string>Lotse zeigt und steuert die Musik in Spotify.</string>
</dict>
</plist>
EOF
xattr -cr "$APP"   # Finder-Attribute würden die Signatur verhindern
# Mit eigenem Zertifikat "Lotse Dev" bleiben die macOS-Freigaben über Neubauten erhalten.
IDENTITY="Lotse Dev"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Hinweis: Zertifikat '$IDENTITY' fehlt – Ad-hoc-Signatur, Freigaben verfallen bei jedem Neubau."
    codesign --force --sign - "$APP"
fi
rm -rf build/Lotse.app && mkdir -p build && cp -R "$APP" build/Lotse.app
echo "Gebaut: build/Lotse.app"
if [ "$1" != "--no-install" ]; then
    osascript -e 'quit app "Lotse"' 2>/dev/null || true
    sleep 1
    rm -rf /Applications/Lotse.app
    cp -R "$APP" /Applications/Lotse.app
    echo "Installiert: /Applications/Lotse.app"
    open /Applications/Lotse.app
fi
