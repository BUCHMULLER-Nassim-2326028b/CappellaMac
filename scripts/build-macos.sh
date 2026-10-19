#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Cette compilation exige macOS et les outils de développement Apple." >&2
  exit 1
fi
swift build -c release --arch arm64
bin_path="$(swift build -c release --arch arm64 --show-bin-path)"
app_path="$PWD/dist/Cappella.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/CappellaMac" "$app_path/Contents/MacOS/CappellaMac"
# Strip debugger data only from the distributed copy, before code signing.
# Keep Swift runtime metadata and the original build product for diagnostics.
xcrun strip -S "$app_path/Contents/MacOS/CappellaMac"
cp packaging/Info.plist "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources"
cp packaging/Resources/Mire.jpg "$app_path/Contents/Resources/Mire.jpg"
cp packaging/Resources/CappellaLogo.png packaging/Resources/CappellaLogo_dark.png "$app_path/Contents/Resources/"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/cappella-icons.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
xcrun swiftc -parse-as-library scripts/build-icons.swift -o "$icon_work/build-icons"
"$icon_work/build-icons" packaging/Resources/CappellaLogo.png packaging/Resources/CappellaLogo_dark.png "$icon_work"
for icon_name in AppIcon AppIconDark; do
  iconutil --convert icns "$icon_work/$icon_name.iconset" --output "$app_path/Contents/Resources/$icon_name.icns"
  test -s "$app_path/Contents/Resources/$icon_name.icns"
done

chmod +x "$app_path/Contents/MacOS/CappellaMac"
plutil -lint "$app_path/Contents/Info.plist"
[[ "$(lipo -archs "$app_path/Contents/MacOS/CappellaMac")" == "arm64" ]]
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$PWD/dist/Cappella-MacOS-arm64.zip"
echo "Application ARM64 : $app_path"
echo "Archive : $PWD/dist/Cappella-MacOS-arm64.zip"
