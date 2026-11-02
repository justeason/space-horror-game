extends SceneTree
## Round 19 Priority 4 regression coverage: the six calibration gauges
## now lay out as two rows of three (a GridContainer, not one long
## HBoxContainer row -- see scenes/player.tscn's ChamberRow), and
## required-fault COUNT no longer depends on the global EASY/NORMAL/HARD
## difficulty setting at all -- it depends on
## sensor_calibration_view.gd's own _completions_this_session
## (technician-progression axis) instead, per this round's explicit
## audit instruction. Difficulty continues to govern only
## tolerance/stability/coupling (already covered by
## test_sensor_calibration_difficulty.gd) -- this file covers the NEW
## layout and the NEW count/difficulty independence specifically.
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var station := main.get_node("Interactables/SensorCalibrationStation")
	var view := player.get_node("HUD/SensorCalibrationView")
	var focused := main.get_node("FocusedInteractionState")

	# ============================================================
	# 1. Layout: ChamberRow is a 3-column GridContainer (two rows of
	# three), not the old single 6-wide row -- and the six chamber
	# panels actually land in two distinct Y bands once laid out, not
	# just "the container's class says GridContainer" (a real geometric
	# check, not merely a type check).
	# ============================================================
	var row: GridContainer = view.get_node("Panel/VBox/ChamberRow")
	_check("ChamberRow is a GridContainer (3x2 layout, not a single 6-wide row)", row is GridContainer)
	_check("ChamberRow has exactly 3 columns", row.columns == 3)
	_check("ChamberRow has all 6 chamber panels as children", row.get_child_count() == 6)

	station.interact()
	await process_frame
	await process_frame # let the container actually sort/position children

	var top_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberA").global_position.y
	var bottom_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberD").global_position.y
	_check("Chamber A (row 1) and Chamber D (row 2) sit at genuinely different vertical positions", not is_equal_approx(top_y, bottom_y))
	_check("Chamber D is BELOW Chamber A (row 2 under row 1, not beside it)", bottom_y > top_y)
	var a_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberA").global_position.y
	var b_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberB").global_position.y
	var c_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberC").global_position.y
	_check("Chamber A/B/C (row 1) share the same vertical position", is_equal_approx(a_y, b_y) and is_equal_approx(b_y, c_y))
	var e_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberE").global_position.y
	var f_y: float = view.get_node("Panel/VBox/ChamberRow/ChamberF").global_position.y
	_check("Chamber D/E/F (row 2) share the same vertical position", is_equal_approx(bottom_y, e_y) and is_equal_approx(e_y, f_y))
	focused.end()
	await process_frame

	# ============================================================
	# 2. Required count no longer depends on difficulty: with a fresh
	# view (_completions_this_session == 0), HARD must still produce
	# the FIRST (manageable, 1-2) progression tier, not its old 5-6
	# difficulty-tied range -- the actual reported-wrong coupling this
	# round's audit targeted.
	# ============================================================
	_check("fresh session starts with zero completions", view._completions_this_session == 0)
	while GameSettings.get_difficulty() != GameSettings.Difficulty.HARD:
		GameSettings.cycle_difficulty()
	view._debug_forced_count = -1
	var hard_first_counts: Array = []
	for i in 6:
		station.interact()
		await process_frame
		hard_first_counts.append(view._active_fault_count)
		focused.end()
		await process_frame
	var hard_first_all_low: bool = hard_first_counts.all(func(c): return c >= 1 and c <= 2)
	_check("HARD difficulty with zero completions still gets the manageable 1-2 introduction range, not its old 5-6 (count/difficulty are now independent) -- got %s" % [hard_first_counts], hard_first_all_low)

	# ============================================================
	# 3. Completing the station advances the progression counter, which
	# then widens the reachable required-count range -- independent of
	# whatever difficulty is active. Force a count, drive a real
	# completion, and confirm the counter advanced.
	# ============================================================
	view.debug_force_active_count(1)
	station.interact()
	await process_frame
	var solution: Dictionary = view._solve_equilibrium(view._coupling, view._TARGETS)
	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
	view._damping = view.CRITICAL_DAMPING
	await create_timer(4.0).timeout
	_check("HARD repair completes with a forced 1-chamber fault", view._done)
	_check("completions_this_session advanced to 1 after a real completion", view._completions_this_session == 1)
	focused.end()
	await create_timer(0.3).timeout

	# With completions_this_session == 3+, EASY must be able to reach
	# the full complex (up to 6) range -- the other half of the audit's
	# explicit requirement ("an experienced player on EASY should
	# eventually encounter complex multi-chamber faults"). Clear the
	# forced count left over from the step above first -- otherwise
	# every subsequent interact() would keep honoring that forced value
	# instead of exercising the real random/progression path at all.
	view._debug_forced_count = -1
	view._completions_this_session = 3
	while GameSettings.get_difficulty() != GameSettings.Difficulty.EASY:
		GameSettings.cycle_difficulty()
	var easy_experienced_counts: Array = []
	for i in 10:
		station.interact()
		await process_frame
		easy_experienced_counts.append(view._active_fault_count)
		focused.end()
		await process_frame
	var easy_can_reach_complex: bool = easy_experienced_counts.any(func(c): return c >= 5)
	_check("EASY difficulty with 3+ completions can reach complex multi-chamber faults (>=5 of 6) -- got %s" % [easy_experienced_counts], easy_can_reach_complex)

	# Leave global state clean for any later test in the same process.
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
