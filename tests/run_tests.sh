#!/bin/bash
# Reusable regression test runner.
#
# Runs a fixed, explicitly-listed set of Godot headless SceneTree test
# scripts from this directory, prints each test's own output, then prints
# a one-line-per-test summary. Exits nonzero if any test failed or a test
# script could not be found, so this script's exit code can gate other
# work.
#
# Usage: tests/run_tests.sh [test_name ...]
#   No arguments: runs every test in TESTS below.
#   One or more arguments: runs only the named tests (without the .gd
#   suffix), e.g. tests/run_tests.sh test_sleep_wake test_day_plan
#
# Every run's full output is also written to tests/.last_run.log (a
# fixed, predictable path, overwritten each run -- not a timestamped or
# /tmp path) via an internal `tee`, so a log is always available without
# needing shell redirection (`... > logfile.txt`) on the invocation
# itself. This is a process-substitution tee (`exec > >(tee ...)`), not
# a trailing pipe on the whole script, so it does NOT affect the exit
# code below -- the caller still sees this script's real exit status,
# not tee's.

set -u
cd "$(dirname "$0")/.."

exec > >(tee "tests/.last_run.log") 2>&1

TESTS=(
  test_sitting_pose
  test_standing_body_composition
  test_lying_body_transform
  test_sleep_state_m7
  test_laptop_screen_editor
  test_editor_escape_hardening
  test_get_up_from_any_state
  test_get_up_staged_sequence
  test_bed_proximity
  test_m7_smoke
  test_m7_bugfixes
  test_laptop_hand_gesture_and_facing
  test_editor_zoom_body_and_aim
  test_arm_gesture_reversible
  test_editor_camera_no_reversal
  test_editor_camera_lock
  test_daily_log_behavior
  test_control_room_workstation
  test_sleep_wake
  test_day_plan
  test_carry_and_e06
  test_cabinet_compartments
  test_electrical_panel_chain
  test_workstation_nav
  test_workstation_surveillance_and_verify
  test_slice_a_e2e
  test_slice_b_e2e
  test_workstation_sitdown
  test_station_capsule_sweep
  test_workstation_proximity
  test_interaction_prompts
  test_tunnel_trap
  test_workstation_seated_view
  test_surveillance_camera_angles
  test_carry_drop
  test_electrical_panel_terminal
  test_electrical_panel_hatch_visual
  test_wristwatch
  test_station_map
  test_focused_interaction_state
  test_electrical_repair_procedure
  test_sensor_calibration
  test_electrical_repair_diorama
  test_reconnect_hitbox_bug
  test_reconnect_lifecycle
  test_reconnect_visual_position
  test_wire_geometry
  test_sensor_calibration_knob
  test_sensor_calibration_difficulty
  test_sensor_calibration_coupling
  test_workstation_visual_overview
  test_wristwatch_screen_stability
  test_e06_contextual_guidance
  test_cylindrical_gauge
  test_difficulty_configuration
  test_debug_labels_visibility
  test_flashlight
  test_flashlight_hard_mode
  test_valve_routing
  test_filter_housing
  test_circuit_tracer
  test_electrical_wire_randomization
  test_valve_routing_dual_outlet
  test_signal_calibration
  test_workstation_room_discoverability
  test_mirror_reflection
)

if [ "$#" -gt 0 ]; then
  TESTS=("$@")
fi

overall_status=0
summary=()

for name in "${TESTS[@]}"; do
  script="tests/${name}.gd"
  echo "=== ${name} ==="
  if [ ! -f "$script" ]; then
    echo "SKIPPED (script not found: $script)"
    summary+=("SKIPPED     $name")
    overall_status=1
    echo ""
    continue
  fi

  output="$(godot --headless --path . --script "$script" 2>&1)"
  echo "$output"

  if echo "$output" | grep -q "NEW REGRESSIONS FOUND"; then
    summary+=("REGRESSION  $name")
    overall_status=1
  elif echo "$output" | grep -q "SOME TESTS FAILED"; then
    summary+=("FAILED      $name")
    overall_status=1
  elif echo "$output" | grep -qE "ALL TESTS PASSED|NO NEW REGRESSIONS|SMOKE TEST DONE"; then
    summary+=("PASS        $name")
  else
    summary+=("UNKNOWN     $name (no recognized result marker)")
    overall_status=1
  fi
  echo ""
done

echo "================ SUMMARY ================"
for line in "${summary[@]}"; do
  echo "$line"
done

exit $overall_status
