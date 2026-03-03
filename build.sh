#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/BatteryBuddy.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

SDK=$(xcrun --show-sdk-path)

echo "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Compiling..."
swiftc \
  -target arm64-apple-macosx15.0 \
  -sdk "$SDK" \
  -O \
  -o "$MACOS_DIR/BatteryBuddy" \
  "$PROJECT_DIR/BatteryBuddy/Models/BatteryInfo.swift" \
  "$PROJECT_DIR/BatteryBuddy/Models/ProcessInfo.swift" \
  "$PROJECT_DIR/BatteryBuddy/Utilities/Extensions.swift" \
  "$PROJECT_DIR/BatteryBuddy/Services/BatteryMonitor.swift" \
  "$PROJECT_DIR/BatteryBuddy/Services/ProcessMonitor.swift" \
  "$PROJECT_DIR/BatteryBuddy/Services/NotificationManager.swift" \
  "$PROJECT_DIR/BatteryBuddy/Views/StatusItemView.swift" \
  "$PROJECT_DIR/BatteryBuddy/Views/ProcessListView.swift" \
  "$PROJECT_DIR/BatteryBuddy/Views/MenuBarView.swift" \
  "$PROJECT_DIR/BatteryBuddy/App/BatteryBuddyApp.swift"

echo "Assembling app bundle..."

# Info.plist — resolve build variables
sed \
  -e 's/$(EXECUTABLE_NAME)/BatteryBuddy/g' \
  -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.local.BatteryBuddy/g' \
  -e 's/$(PRODUCT_NAME)/BatteryBuddy/g' \
  -e 's/$(MACOSX_DEPLOYMENT_TARGET)/15.0/g' \
  "$PROJECT_DIR/BatteryBuddy/Resources/Info.plist" > "$CONTENTS/Info.plist"

echo "APPL????" > "$CONTENTS/PkgInfo"

# Remove quarantine and ad-hoc sign so macOS allows execution
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo ""
echo "Run with:  open $APP_BUNDLE"
