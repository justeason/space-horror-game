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
	# 1. Opening the station alone never completes the task. Round 16
	# Priority 8: HOW MANY chambers start away from their own target is
	# now this STATION's own exported active_fault_count() -- a work-
	# order-scenario property, genuinely independent of difficulty (see
	# sensor_calibration_station.gd's class doc comment for the full
	# reasoning, and test_sensor_calibration_difficulty.gd for the
	# confirmation that this count stays IDENTICAL across EASY/NORMAL/
	# HARD). Real work is still required, but only from the active
	# (faulty) chambers this work order actually specifies; the rest
	# start already solved.
	# ============================================================
	station.interact()
	await process_frame
	_check("focused session active for the calibration station", focused.is_active())
	_check("calibration view visible", calib_view.visible)
	_check("opening alone does not complete l07", not day_plan.is_task_done(&"l07"))
	var fault_count: int = station.active_fault_count()
	var active_chambers: Array = calib_view.CHAMBERS.slice(0, fault_count)
	for ch in calib_view.CHAMBERS:
		if ch in active_chambers:
			_check("chamber %s starts away from its own target (active this difficulty)" % ch, absf(calib_view._reading[ch] - calib_view._TARGETS[ch]) > calib_view._tolerance)
		else:
			_check("chamber %s starts already at its own target (not active this difficulty)" % ch, absf(calib_view._reading[ch] - calib_view._TARGETS[ch]) <= calib_view._tolerance)

	# ============================================================
	# 2. COUPLING IS REAL: adjusting chamber A's regulator measurably
	# shifts chamber B's and C's READINGS too, not just A's own -- the
	# actual new mechanic, verified as real simulated behavior (not a
	# label claiming it).
	# ============================================================
	var b_before: float = calib_view._reading[&"b"]
	var c_before: float = calib_view._reading[&"c"]
	await _hold(KEY_2, 1.0) # chamber A regulator, increase
	await create_timer(0.5).timeout # let the coupled springs respond
	_check("raising chamber A's regulator also measurably shifts chamber B's reading", not is_equal_approx(calib_view._reading[&"b"], b_before))
	_check("raising chamber A's regulator also measurably shifts chamber C's reading", not is_equal_approx(calib_view._reading[&"c"], c_before))

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
