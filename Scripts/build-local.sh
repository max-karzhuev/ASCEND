#!/bin/sh
set -eu
ASCEND_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ASCEND_BUILD_DIR=${ASCEND_BUILD_DIR:-"$ASCEND_ROOT/build/mac"}
xcodebuild -project "$ASCEND_ROOT/ASCEND.xcodeproj" -scheme ASCEND \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$ASCEND_BUILD_DIR" CODE_SIGN_IDENTITY=- build
printf '\nStandalone app: %s\n' "$ASCEND_BUILD_DIR/Build/Products/Release/ASCEND.app"
