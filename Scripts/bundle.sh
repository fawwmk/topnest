#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/TopNest.app"
KEYCHAIN_PATH="$ROOT_DIR/.signing/Vidget.keychain-db"
SIGNING_IDENTITY="Vidget Local Development"

cd "$ROOT_DIR"
env \
    CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache" \
    swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/TopNest" "$APP_DIR/Contents/MacOS/TopNest"
cp \
    "$ROOT_DIR/.build/release/libTopNestMediaHelper.dylib" \
    "$APP_DIR/Contents/Resources/TopNestMediaHelper.dylib"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

"$ROOT_DIR/Scripts/ensure-signing-identity.sh"
codesign \
    --force \
    --keychain "$KEYCHAIN_PATH" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp=none \
    "$APP_DIR/Contents/Resources/TopNestMediaHelper.dylib"
codesign \
    --force \
    --deep \
    --keychain "$KEYCHAIN_PATH" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp=none \
    "$APP_DIR"

echo "Готово: $APP_DIR"
