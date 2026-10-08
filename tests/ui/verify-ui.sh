#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$(mktemp -d /tmp/foglight-ui-XXXXXX)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root"/{home,cache,config,data}
export HOME="$root/home" XDG_CACHE_HOME="$root/cache" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data"
# A clean checkout has no generated import cache. Never rely on the live editor.
timeout 90s "${GODOT_BIN:-godot}" --headless --editor --path . --import --quit > "$root/import.log" 2>&1 || { cat "$root/import.log"; exit 1; }
cat "$root/import.log"
if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$root/import.log"; then exit 1; fi
for script in run_game_ui.gd run_ui_layout.gd; do
  timeout 90s "${GODOT_BIN:-godot}" --headless --path . --script "res://tests/ui/$script" > "$root/check.log" 2>&1 || { cat "$root/check.log"; exit 1; }
  cat "$root/check.log"
  grep -Eq 'checks; 0 failures' "$root/check.log"
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|WARNING: ObjectDB|resources still in use' "$root/check.log"; then exit 1; fi
done
python3 tests/ui/check_ui_assets.py
python3 tools/check_boundaries.py
