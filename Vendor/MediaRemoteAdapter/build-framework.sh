#!/bin/sh
set -eu

# Reproducible build for the vendored BSD-3-Clause mediaremote-adapter.
# The resulting framework is a resource of the host app; the app does not link it.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR="$SCRIPT_DIR/Upstream"
OUTPUT_DIR=${1:-"$SCRIPT_DIR/../../Panel/Features/Player/Resources"}
FRAMEWORK_DIR="$OUTPUT_DIR/MediaRemoteAdapter.bundle"
FRAMEWORK_BINARY="$FRAMEWORK_DIR/Versions/A/MediaRemoteAdapter"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

mkdir -p "$FRAMEWORK_DIR/Versions/A/Headers" "$FRAMEWORK_DIR/Versions/A/Resources"

SOURCES="
$SOURCE_DIR/src/adapter/env.m
$SOURCE_DIR/src/adapter/get.m
$SOURCE_DIR/src/adapter/globals.m
$SOURCE_DIR/src/adapter/keys.m
$SOURCE_DIR/src/adapter/now_playing.m
$SOURCE_DIR/src/adapter/repeat.m
$SOURCE_DIR/src/adapter/seek.m
$SOURCE_DIR/src/adapter/send.m
$SOURCE_DIR/src/adapter/shuffle.m
$SOURCE_DIR/src/adapter/speed.m
$SOURCE_DIR/src/adapter/stream.m
$SOURCE_DIR/src/adapter/test.m
$SOURCE_DIR/src/private/MediaRemote.m
$SOURCE_DIR/src/utility/Debounce.m
$SOURCE_DIR/src/utility/helpers.m
"

# shellcheck disable=SC2086
xcrun --sdk macosx clang \
  -isysroot "$SDK_PATH" \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -dynamiclib -fobjc-arc -fblocks -fvisibility=default \
  -I "$SOURCE_DIR/include" -I "$SOURCE_DIR/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.bundle/Versions/A/MediaRemoteAdapter" \
  -current_version 0.1.0 -compatibility_version 0.1.0 \
  $SOURCES \
  -o "$FRAMEWORK_BINARY"

cp "$SOURCE_DIR/include/MediaRemoteAdapter.h" "$FRAMEWORK_DIR/Versions/A/Headers/"
cp "$SCRIPT_DIR/Info.plist" "$FRAMEWORK_DIR/Versions/A/Resources/Info.plist"

ln -sfn A "$FRAMEWORK_DIR/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FRAMEWORK_DIR/MediaRemoteAdapter"
ln -sfn Versions/Current/Headers "$FRAMEWORK_DIR/Headers"
ln -sfn Versions/Current/Resources "$FRAMEWORK_DIR/Resources"

codesign --force --sign - "$FRAMEWORK_DIR"
cp "$SOURCE_DIR/bin/mediaremote-adapter.pl" "$OUTPUT_DIR/mediaremote-adapter.pl"
lipo -archs "$FRAMEWORK_BINARY"

