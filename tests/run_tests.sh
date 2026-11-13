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
  test_wristwatch_part_hint
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
  test_sensor_calibration_layout_progression
  test_control_room_walkway_seal
  test_storage_cabinet
  test_storage_cabinet_door_direction
  test_hand_mesh_and_mirror_fov
  test_junction_engineering_doorway
  test_storage_cabinet2_filter
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
  test_used_filter_disposal
  test_filter_no_duplicate_cartridge
  test_circuit_tracer
  test_electrical_wire_randomization
  test_valve_routing_dual_outlet
  test_signal_calibration
  test_workstation_room_discoverability
  test_mirror_reflection
  test_storage_cabinet_depth
  test_watch_raise_pose
  test_rigged_technician_prototype
  test_look_pose_sync
  test_rigged_character
  test_workdays
  test_carry_reach
  test_station_ambience
  test_carry_no_drift
  test_bed_camera
  test_watch_high_range
  test_gait_footsteps
  test_workday_recurrence
  test_animation_transitions
  test_furniture_contact
  test_bed_laptop
  test_multiday_maintenance
  test_furniture_blocks_player
  test_grasp_ownership
  test_drop_release
  test_electrical_spare_types
  test_cargo_delivery
  test_sustainability_20days
  test_day_hint
  test_save_load
  test_save_reload
  test_shift_routine
  test_inspection_tasks
  test_cargo_carrier
  test_environment_readout
  test_save_load_20days
  test_load_via_workstation_input
  test_loose_parts_walkable
  test_laptop_clicks
  test_shift_day_system
  test_menus_settings
  test_r35_equipment
  test_r35_scheduling_ui
  test_r35_save
  test_vent_clips
  test_data_module_return
  test_filter_variants
  test_r36_lighting_seal
  test_thermal_probe
  test_station_ai
  test_r37_ui_scale
  test_r37_calibration_gauges
  test_r37_emergency
  test_r37_workstation
  test_r37_speakers
  test_r37_laptop_personal
  test_r38_cameras_exterior
  test_r38_tools
  test_r38_laptop_station
  test_r39_hull_seal
  test_r39_airlock_eva
  test_r39_routine_layout
  test_r40_walkway_clear
  test_r41_eva_dual_tether
  test_r41_solar
  test_r41_story_events
  test_r41_cargo_drop
  test_r41_cameras_suit
  test_r40_eva_clarity
  test_r42_eva_airlock
  test_r42_story_dev
  test_r42_cameras_live
  test_r42_maintenance
  test_r42_laptop
  test_r42_watch_shift
  test_r43_clock_laptop
  test_r43_holdout
  test_r43_station
  test_r44_laptop_family
  test_r44_records_horror
  test_r44_holdout_light
  test_r45_window_access
  test_r45_laptop_station
  test_r46_shift_timer
  test_r46_dev_input
  test_r46_holdout_balance
  test_r46_life_systems
  test_r46_horror
  test_r47_windows_floor
  test_r47_life_audio
  test_r47_horror
  test_r47_messages_scroll
  test_r48_window_figure
  test_r48_audio
  test_r48_handover
  test_r48_holdout_economy
  test_r48_clock_calendar
  test_r48_chapter_one
  test_r49_deck_b_layout
  test_r49_shaft
  test_r49_water_thermal
  test_r49_workshop_lab
  test_r49_botany_medical
  test_r49_cargo_archive
  test_r49_tasks
  test_r49_story
  test_r49_save
  test_r50_lower_gaps
  test_r50_pressure
  test_r50_suit_hull
)

if [ "$#" -gt 0 ]; then
  TESTS=("$@")
fi

# Tests that need a real window (GUI mouse events); see the run loop.
WINDOWED_TESTS=(test_r46_dev_input test_r46_horror test_r47_horror test_r47_messages_scroll)

overall_status=0
summary=()
TEST_TIMEOUT_S="${TEST_TIMEOUT_S:-600}"
# Round 36: tests use their own settings file, never the player's
# user://game_settings.cfg (it used to be rewritten by every save/load test).
export SMH_SETTINGS_PATH="${SMH_SETTINGS_PATH:-user://test_game_settings.cfg}"
ERROR_IDLE_S="${ERROR_IDLE_S:-20}"

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

  # Round 33: bounded run. A test that hangs (e.g. a SCRIPT ERROR aborted
  # its _init so it never calls quit()) is killed and reported instead of
  # stalling the whole suite. TEST_TIMEOUT_S bounds a test's total time;
  # ERROR_IDLE_S kills a test that printed a SCRIPT ERROR and then produced
  # no further output for that long. Normal long tests (the 20-day run)
  # keep printing and stay well under the limit.
  tmp_out="$(mktemp -t godot_test_out)"
  # Round 46: GUI hover / clicks are only delivered with a real window
  # (headless has no mouse-in-window state), so the few tests that must
  # click real Controls run windowed (a small window appears briefly).
  mode_flag="--headless"
  for w in "${WINDOWED_TESTS[@]}"; do
    if [ "$w" = "$name" ]; then mode_flag=""; fi
  done
  godot $mode_flag --path . --script "$script" > "$tmp_out" 2>&1 &
  pid=$!
  ticks=0
  idle_ticks=0
  last_size=0
  note=""
  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.25
    ticks=$((ticks + 1))
    size=$(wc -c < "$tmp_out")
    if [ "$size" = "$last_size" ]; then idle_ticks=$((idle_ticks + 1)); else idle_ticks=0; fi
    last_size=$size
    if grep -q "SCRIPT ERROR" "$tmp_out" && [ "$idle_ticks" -ge $((ERROR_IDLE_S * 4)) ]; then
      kill "$pid" 2>/dev/null; note="HUNG after SCRIPT ERROR (no output for ${ERROR_IDLE_S}s)"; break
    fi
    if [ "$ticks" -ge $((TEST_TIMEOUT_S * 4)) ]; then
      kill "$pid" 2>/dev/null; note="TIMEOUT after ${TEST_TIMEOUT_S}s"; break
    fi
  done
  wait "$pid" 2>/dev/null
  output="$(cat "$tmp_out")"
  rm -f "$tmp_out"
  echo "$output"

  if [ -n "$note" ]; then
    echo "RUNNER: ${name} killed -- ${note}"
    summary+=("TIMEOUT     $name ($note)")
    overall_status=1
  elif echo "$output" | grep -q "SCRIPT ERROR"; then
    # Round 33: a test that "passes" while the engine reports script errors
    # is not a pass (a startup error once hid in every test this way).
    summary+=("ERRORS      $name ($(echo "$output" | grep -c "SCRIPT ERROR") SCRIPT ERROR line(s))")
    overall_status=1
  elif echo "$output" | grep -q "NEW REGRESSIONS FOUND"; then
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
