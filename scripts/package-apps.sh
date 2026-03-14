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

build_swift_app() {
  local entry="$1"
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
}

build_nexus_app() {
  local app_bundle="$DIST_DIR/Nexus.app"
  local macos_dir="$app_bundle/Contents/MacOS"
  local resources_dir="$app_bundle/Contents/Resources"
  local plist="$app_bundle/Contents/Info.plist"
  local nexus_resources="$resources_dir/nexus"

  rm -rf "$app_bundle"
  mkdir -p "$macos_dir" "$nexus_resources"

  /usr/bin/rsync -a --delete \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    "$ROOT_DIR/nexus/" "$nexus_resources/"

  cat > "$macos_dir/NexusLauncher" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NEXUS_DIR="$APP_DIR/Resources/nexus"
RUNTIME_DIR="$HOME/.nexus/runtime"
VENV_DIR="$RUNTIME_DIR/venv"

mkdir -p "$RUNTIME_DIR"

if [ ! -x "$VENV_DIR/bin/python3" ]; then
  /usr/bin/python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python3" -m pip install --upgrade pip >/dev/null 2>&1 || true
"$VENV_DIR/bin/python3" -m pip install -r "$NEXUS_DIR/requirements.txt"

PY_CMD="cd \"$NEXUS_DIR\"; \"$VENV_DIR/bin/python3\" main.py"

/usr/bin/osascript <<OSA
tell application "Terminal"
  activate
  do script "$PY_CMD"
end tell
OSA
SH
  chmod +x "$macos_dir/NexusLauncher"

  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>NexusLauncher</string>
  <key>CFBundleIdentifier</key>
  <string>com.joebot.nexus</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Nexus</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST

  echo "Created: $app_bundle"
}

for entry in "${apps[@]}"; do
  build_swift_app "$entry"
done

build_nexus_app

cat > "$DIST_DIR/README_RUN_ON_ANOTHER_MAC.txt" <<'TXT'
Joebot Ecosystem App Bundle
==========================

Included apps:
- DirtyMixerApp.app
- GlitchCatalogSwift.app
- Observatory.app
- Nexus.app

Quick start:
1) Move these .app files to /Applications (or any folder) on the target Mac.
2) Launch Nexus.app first. It opens Terminal and starts the Python Nexus server.
3) Launch DirtyMixerApp.app, GlitchCatalogSwift.app, and Observatory.app.
4) If prompted for network/file permissions, allow them.

Notes:
- Nexus.app uses /usr/bin/python3 and creates a runtime venv at ~/.nexus/runtime/venv.
- Nexus installs dependencies from bundled requirements.txt on first launch.
- Default Nexus port is 8675.
TXT

ZIP_PATH="$DIST_DIR/joebot-ecosystem-apps-macos.zip"
rm -f "$ZIP_PATH"
(cd "$DIST_DIR" && /usr/bin/zip -qry "$ZIP_PATH" DirtyMixerApp.app GlitchCatalogSwift.app Observatory.app Nexus.app README_RUN_ON_ANOTHER_MAC.txt)

echo ""
echo "All app bundles are in: $DIST_DIR"
echo "Transfer archive: $ZIP_PATH"
