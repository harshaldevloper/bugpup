#!/usr/bin/env bash
# The Bugpup's test suite.
#
# Runs the agent's self test: the bug lab (four planted bugs, all four
# must be caught with 3/3 replays) and the clean lab (the same world
# with the bugs fixed, which must report nothing).
#
# Usage (from your Godot project's root):
#   bash addons/bugpup/tests/run_tests.sh
#
# It prints the real output of the run - there is no summary file to
# trust, the output IS the proof.

set -uo pipefail

# This script lives at <project>/addons/bugpup/tests/run_tests.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
	echo "Godot not found: $GODOT_BIN"
	echo "Set GODOT_BIN to the Godot 4.3+ binary and try again."
	exit 1
fi

echo "project: $PROJECT_DIR"
echo "godot:   $GODOT_BIN"
"$GODOT_BIN" --version
echo ""

echo "=== parse check ==="
for script in \
	res://addons/bugpup/agent.gd \
	res://addons/bugpup/bugpup_api.gd \
	res://addons/bugpup/agent_panel.gd \
	res://addons/bugpup/tests/bug_lab.tscn.gd \
	res://addons/bugpup/tests/slow_fall_lab.tscn.gd \
	res://addons/bugpup/tests/harness.gd \
	res://addons/bugpup/tests/replay_test.gd; do
	if [ ! -f "$PROJECT_DIR/${script#res://}" ]; then
		echo "  SKIP $script (not present)"
		continue
	fi
	out="$("$GODOT_BIN" --headless --path "$PROJECT_DIR" --check-only --script "$script" 2>&1)"
	if [ $? -eq 0 ]; then
		echo "  OK   $script"
	else
		echo "  FAIL $script"
		echo "$out"
		exit 1
	fi
done
echo ""

echo "=== the self test ==="
"$GODOT_BIN" --headless --path "$PROJECT_DIR" \
	--script res://addons/bugpup/tests/harness.gd
STATUS=$?

echo ""
if [ $STATUS -ne 0 ]; then
	echo "SELF TEST FAILED (exit $STATUS)"
	exit $STATUS
fi
echo "SELF TEST PASSED"

# The replay test: a finding that needs TIME to develop must still be
# confirmable. It failed once, because the replay stopped too early.
echo ""
echo "=== the replay test ==="
"$GODOT_BIN" --headless --path "$PROJECT_DIR" \
	--script res://addons/bugpup/tests/replay_test.gd
STATUS=$?

echo ""
if [ $STATUS -eq 0 ]; then
	echo "REPLAY TEST PASSED"
else
	echo "REPLAY TEST FAILED (exit $STATUS)"
fi
exit $STATUS
