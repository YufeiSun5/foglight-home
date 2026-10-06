#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_CACHE_HOME="${FOGLIGHT_TEST_CACHE_HOME:-/tmp/foglight-core-cache}"
export XDG_CONFIG_HOME="${FOGLIGHT_TEST_CONFIG_HOME:-/tmp/foglight-core-config}"
export XDG_DATA_HOME="${FOGLIGHT_TEST_DATA_HOME:-/tmp/foglight-core-data}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
GODOT_BIN="${GODOT_BIN:-godot}"
for script in tests/content/validate_content.gd tests/domain/run_tests.gd tests/integration/run_save_recovery.gd; do
 timeout 75s "$GODOT_BIN" --headless --path . --script "$script"
done
python3 tests/content/check_json.py
python3 tools/check_boundaries.py

# Character-only checkpoints remain independently testable before full scene integration.
if [[ -f tests/content/validate_asset_checkpoint.py ]]; then
  python3 tests/content/validate_asset_checkpoint.py
fi
