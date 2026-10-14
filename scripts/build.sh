#!/bin/zsh
# Regenerates the Xcode project from project.yml and builds a Release AINCRAD.app into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
# Build output lives outside ~/Documents: iCloud Drive adds attributes codesign rejects.
DERIVED="$HOME/Library/Caches/AINCRAD-build"
DEST="${AINCRAD_INSTALL_DIR:-/Applications}"
xcodebuild -project AINCRAD.xcodeproj -scheme AINCRAD -configuration Release \
  -derivedDataPath "$DERIVED" build -quiet
mkdir -p "$DEST"
if pgrep -x AINCRAD >/dev/null; then echo "Note: AINCRAD is running; quit it from the menu bar before relaunching the new build."; fi
rm -rf "$DEST/AINCRAD.app"
ditto "$DERIVED/Build/Products/Release/AINCRAD.app" "$DEST/AINCRAD.app"
codesign --verify --verbose=1 "$DEST/AINCRAD.app"
# Refresh LaunchServices so Finder, the Dock and icon lookups see the new build's icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/AINCRAD.app"
echo "Installed $DEST/AINCRAD.app"
