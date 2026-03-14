#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "cd '$ROOT_DIR/nexus' && python3 main.py"
  do script "cd '$ROOT_DIR/DirtyMixerApp' && swift run"
  do script "cd '$ROOT_DIR/GlitchCatalogSwift' && swift run"
  do script "cd '$ROOT_DIR/Observatory' && swift run"
end tell
APPLESCRIPT

echo "Opened Nexus + DirtyMixerApp + GlitchCatalogSwift + Observatory in Terminal."
echo "To stop: press Ctrl+C in each tab."
