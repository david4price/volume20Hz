#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-release}"
case "$mode" in
    release) cargo_profile=release ;;
    debug) cargo_profile=dev ;;
    *) echo "Usage: $0 [release|debug]" >&2; exit 2 ;;
esac

target=aarch64-apple-darwin
export CARGO_TARGET_DIR="$PWD/target"
cargo build --locked --target "$target" --profile "$cargo_profile"

mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/20HzPlayer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "target/$target/$mode/volume20hz" "$app/Contents/MacOS/"
cp build/icon.icns "$app/Contents/Resources/"
cp sound-wave_20Hz_tray.png "$app/Contents/Resources/tray.png"
cp build/Info.plist "$app/Contents/"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto "$app" "dist/20HzPlayer.app"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -format UDZO -volname "20HzPlayer" -srcfolder "$stage" \
    "$PWD/dist/20HzPlayer.dmg"
