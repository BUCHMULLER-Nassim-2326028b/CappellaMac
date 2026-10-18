#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Cette compilation exige macOS et les outils de développement Apple." >&2
  exit 1
fi
swift build -c release --arch arm64
bin_path="$(swift build -c release --arch arm64 --show-bin-path)"
app_path="$PWD/dist/Cappella Mac.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/CappellaMac" "$app_path/Contents/MacOS/CappellaMac"
cp packaging/Info.plist "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources"
cp packaging/Resources/Mire.jpg "$app_path/Contents/Resources/Mire.jpg"
chmod +x "$app_path/Contents/MacOS/CappellaMac"
plutil -lint "$app_path/Contents/Info.plist"
[[ "$(lipo -archs "$app_path/Contents/MacOS/CappellaMac")" == "arm64" ]]
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$PWD/dist/CappellaMac-arm64.zip"
echo "Application ARM64 : $app_path"
echo "Archive : $PWD/dist/CappellaMac-arm64.zip"
