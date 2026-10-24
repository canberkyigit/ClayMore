#!/bin/bash
# Builds ClayMore.app.   ./build.sh          → build/ClayMore.app (for this Mac's CPU)
#                        ./build.sh install  → also copies it to /Applications
#                        ./build.sh dist     → universal (Apple Silicon + Intel) build/ClayMore.zip for releases
#                        ./build.sh debug    → debug build with dev hooks (DebugHooks.swift)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP=build/ClayMore.app
BIN="$APP/Contents/MacOS/ClayMore"
FLAGS=(-O -wmo -D RELEASE)
[[ "$MODE" == "debug" ]] && FLAGS=(-O -wmo -D DEBUG)
ARCHS=("$(uname -m)")
[[ "$MODE" == "dist" ]] && ARCHS=(arm64 x86_64)

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "→ Generating icon"
    rm -rf build/AppIcon.iconset
    mkdir -p build
    swift tools/make_icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "→ Compiling (${ARCHS[*]})"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SLICES=()
for arch in "${ARCHS[@]}"; do
    swiftc "${FLAGS[@]}" -swift-version 5 -target "$arch-apple-macos13.0" \
        -Xlinker -dead_strip \
        Sources/*.swift -o "build/ClayMore-$arch"
    SLICES+=("build/ClayMore-$arch")
done
lipo -create "${SLICES[@]}" -output "$BIN"
rm -f "${SLICES[@]}"
strip -x "$BIN"

cp Resources/Info.plist "$APP/Contents/Info.plist"
# Debug builds get their own bundle id so they never touch the real app's preferences.
[[ "$MODE" == "debug" ]] && plutil -replace CFBundleIdentifier -string com.claymore.app.debug "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" 2>/dev/null

echo "✓ Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "$MODE" == "install" ]]; then
    osascript -e 'quit app "ClayMore"' 2>/dev/null || true
    rm -rf /Applications/ClayMore.app
    cp -R "$APP" /Applications/
    echo "✓ Installed to /Applications/ClayMore.app"
fi

if [[ "$MODE" == "dist" ]]; then
    rm -f build/ClayMore.zip
    ditto -c -k --keepParent "$APP" build/ClayMore.zip
    echo "✓ Packaged build/ClayMore.zip ($(du -sh build/ClayMore.zip | cut -f1))"
fi
