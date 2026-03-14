#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

mkdir -p "$DIST_DIR"

apps=(
  "DirtyMixerApp|DirtyMixerApp"
  "GlitchCatalogSwift|GlitchCatalogSwift"
  "Observatory|Observatory"
)

for entry in "${apps[@]}"; do
  IFS="|" read -r project_name exec_name <<<"$entry"
  project_dir="$ROOT_DIR/$project_name"

  echo "Building $project_name (release)..."
  (cd "$project_dir" && swift build -c release)

  binary="$project_dir/.build/release/$exec_name"
  app_bundle="$DIST_DIR/$project_name.app"
  macos_dir="$app_bundle/Contents/MacOS"
  resources_dir="$app_bundle/Contents/Resources"
  plist="$app_bundle/Contents/Info.plist"

  rm -rf "$app_bundle"
  mkdir -p "$macos_dir" "$resources_dir"

  cp "$binary" "$macos_dir/$exec_name"
  chmod +x "$macos_dir/$exec_name"

  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$exec_name</string>
  <key>CFBundleIdentifier</key>
  <string>com.joebot.$(echo "$project_name" | tr '[:upper:]' '[:lower:]')</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$project_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

  echo "Created: $app_bundle"
done

echo "\nAll app bundles are in: $DIST_DIR"
