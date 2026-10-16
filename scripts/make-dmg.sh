#!/usr/bin/env bash
# Builds build/MacSweep.dmg: the app plus an Applications shortcut, compressed.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/make-app.sh
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/MacSweep.app/Contents/Info.plist)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R build/MacSweep.app "$staging/"
ln -s /Applications "$staging/Applications"
rm -f build/MacSweep.dmg
hdiutil create -volname "MacSweep $version" -srcfolder "$staging" -ov -format UDZO build/MacSweep.dmg >/dev/null
echo "build/MacSweep.dmg ($version)"
