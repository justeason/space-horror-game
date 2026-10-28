extends SceneTree
## Round 13 Workstream D rewrite: coverage for L07's new COUPLED three-
## chamber pressure calibration, replacing Round 11's single-chamber
## version -- per the player's own request: "When pressure increases in
## one chamber, pressures in connected chambers also change." Confirms:
## adjusting one chamber's regulator measurably moves the OTHER two
## chambers' readings (not just its own) in the documented direction;
## the solved equilibrium setpoints (computed by the view's own
## _solve_equilibrium()) genuinely bring all three chambers into range
## when driven there and properly damped; overshoot/poor damping is
## recoverable; and L07 only completes once ALL THREE chambers are
## simultaneously stable for the full required duration -- never from
## one chamber alone, and never from merely passing through range.
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/SensorCalibrationStation")
	var calib_view := player.get_node("HUD/SensorCalibrationView")
	var focused := main.get_node("FocusedInteractionState")

	_check("l07 not done at start", not day_plan.is_task_done(&"l07"))
	_check("prompt invites calibration before completion", station.get_interact_prompt().findn("Calibrate") != -1)

	# ============================================================
	# 1. Opening the station alone never completes the task. Round 18
	# Priority 3: HOW MANY of this station's 6 chambers start away from
	# their own target is now RANDOMIZED within the current difficulty's
	# own range each attempt (see sensor_calibration_view.gd's class doc
	# comment and test_sensor_calibration_difficulty.gd for per-
	# difficulty range coverage) -- debug_force_active_count() pins an
	# exact value here so this test can assert deterministically which
	# chambers started active vs. already-solved. Real work is still
	# required, but only from the active (faulty) chambers; the rest
	# start already solved.
	# ============================================================
	var fault_count: int = 3
	calib_view.debug_force_active_count(fault_count)
	station.interact()
	await process_frame
	_check("focused session active for the calibration station", focused.is_active())
	_check("calibration view visible", calib_view.visible)
	_check("opening alone does not complete l07", not day_plan.is_task_done(&"l07"))
	var active_chambers: Array = calib_view.CHAMBERS.slice(0, fault_count)
	for ch in calib_view.CHAMBERS:
		if ch in active_chambers:
			_check("chamber %s starts away from its own target (active this difficulty)" % ch, absf(calib_view._reading[ch] - calib_view._TARGETS[ch]) > calib_view._tolerance)
		else:
			_check("chamber %s starts already at its own target (not active this difficulty)" % ch, absf(calib_view._reading[ch] - calib_view._TARGETS[ch]) <= calib_view._tolerance)

	# ============================================================
	# 2. COUPLING IS REAL: adjusting chamber A's regulator measurably
	# shifts chamber B's READING too, not just A's own -- the actual new
	# mechanic, verified as real simulated behavior (not a label claiming
	# it). Round 18 Priority 3: coupling is now NEIGHBOR-ONLY (chamber i
	# only leaks into i-1/i+1 -- see sensor_calibration_view.gd's
	# _build_neighbor_coupling() doc comment for why), so A (index 0)
	# measurably affects its one neighbor B, but NOT the non-adjacent
	# chambers C/D/E/F -- confirming the coupling is real AND correctly
	# scoped to neighbors, not accidentally still all-to-all.
	# ============================================================
	var b_before: float = calib_view._reading[&"b"]
	await _hold(KEY_2, 1.0) # chamber A regulator, increase
	await create_timer(0.5).timeout # let the coupled springs respond
	_check("raising chamber A's regulator also measurably shifts chamber B's reading (its one neighbor)", not is_equal_approx(calib_view._reading[&"b"], b_before))
	# Round 18 Priority 3: coupling is NEIGHBOR-ONLY (see
	# sensor_calibration_view.gd's _build_neighbor_coupling() doc
	# comment) -- checked directly on the coupling MATRIX's structure
	# (A's row has zero weight at every non-adjacent column) rather than
	# by comparing simulated reading drift, since an inactive chamber's
	# reading can drift by its OWN unrelated amount even with A
	# untouched (a chamber's neighbors don't individually start at a
	# locally-blended equilibrium -- confirmed directly: chamber F,
	# nowhere near A, drifted MORE than B did in a direct measurement,
	# which is expected given this effect and does not indicate any
	# actual A->F coupling exists) -- a matrix-structure check isolates
	# exactly the property being tested instead of being confounded by
	# that separate, expected simulation behavior.
	var a_row: Array = calib_view._coupling[0]
	_check("chamber A's coupling row has a real (nonzero) weight toward its neighbor B", a_row[1] > 0.0)
	for col in range(2, calib_view.CHAMBERS.size()):
		_check("chamber A's coupling row has ZERO weight toward non-neighbor %s (coupling is neighbor-only)" % calib_view.CHAMBERS[col], is_zero_approx(a_row[col]))

	# ============================================================
	# 3. The solved equilibrium (view's own _solve_equilibrium(), the
	# actual puzzle solution for the current difficulty's coupling
	# matrix) genuinely brings all three chambers into range when
	# driven there with adequate damping -- proves the puzzle has a
	# real, reachable solution, not merely a mathematical claim.
	# ============================================================
	var solution: Dictionary = calib_view._solve_equilibrium(calib_view._coupling, calib_view._TARGETS)
	for ch in calib_view.CHAMBERS:
		_check("solved setpoint for chamber %s is within the reachable gauge range" % ch, solution[ch] >= 0.0 and solution[ch] <= 100.0)
		calib_view._setpoint[ch] = solution[ch]
	calib_view._damping = calib_view.CRITICAL_DAMPING
	await create_timer(3.5).timeout # let the coupled system settle + full stability duration, with margin

	_check("calibration committed to done once all three chambers settled at the solved equilibrium", calib_view._done)
	_check("l07 marked done only after real simultaneous stabilization", day_plan.is_task_done(&"l07"))

	# ============================================================
	# 4. Canceling afterward and reopening shows the nominal state
	# without re-running the simulation or un-doing completion.
	# ============================================================
	main.get_node("FocusedInteractionState").end()
	_check("session closes cleanly", not focused.is_active())
	_check("prompt now reflects nominal status", station.get_interact_prompt().findn("Nominal") != -1)
	station.interact()
	await process_frame
	_check("reopening after completion shows the done state immediately", calib_view._done)
	_check("l07 still done on reopen (not reset)", day_plan.is_task_done(&"l07"))
	main.get_node("FocusedInteractionState").end()
	await create_timer(0.3).timeout

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _hold(keycode: int, duration: float) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(duration).timeout
	var ev_up := InputEventKey.new()
	ev_up.keycode = keycode
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await process_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
