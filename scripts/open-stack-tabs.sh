#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

echo "Stopping running app instances (if any)..."
osascript <<APPLESCRIPT
try
  tell application "DirtyMixerApp" to quit
end try
try
  tell application "GlitchCatalogSwift" to quit
end try
try
  tell application "Observatory" to quit
end try
APPLESCRIPT

echo "Building latest app bundles..."
(cd "$ROOT_DIR" && make package)

if ! lsof -iTCP:8675 -sTCP:LISTEN >/dev/null 2>&1; then
  osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "cd '$ROOT_DIR/nexus' && python3 main.py"
end tell
APPLESCRIPT
  echo "Started Nexus in Terminal."
else
  echo "Nexus already running on port 8675."
fi

open "$DIST_DIR/DirtyMixerApp.app"
open "$DIST_DIR/GlitchCatalogSwift.app"
open "$DIST_DIR/Observatory.app"

echo "Opened DirtyMixerApp + GlitchCatalogSwift + Observatory as app bundles."
echo "Tip: this mode keeps mouse/keyboard focus inside the app windows."
