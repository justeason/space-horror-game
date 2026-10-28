extends SceneTree
## Round 13 Workstream D rewrite: L07's global-difficulty coverage,
## updated for the three-chamber coupled system. Confirms: EASY uses a
## WEAKER (more diagonal-dominant) coupling matrix, a wider tolerance
## and a shorter stability hold than NORMAL; HARD uses a STRONGER
## coupling matrix, a tighter tolerance and a longer hold; the fixed
## target vector and RESPONSE_STRENGTH never change by difficulty
## (only the coupling matrix/tolerance/duration do); and HARD still
## permits a genuine, correctly-tuned success despite its stronger
## cross-chamber influence making the puzzle harder to decouple by eye.
##
## Round 16 Priority 8 update: fault count (how many chambers start
## broken) is now the STATION's own exported active_fault_count(), a
## work-order-scenario property, genuinely independent of difficulty --
## see sensor_calibration_station.gd's class doc comment. This file now
## explicitly confirms fault count stays IDENTICAL across EASY/NORMAL/
## HARD (previously it scaled 1/2/3 with difficulty, which conflated
## progression with difficulty -- the exact thing the brief asks to
## keep separate).
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var station := main.get_node("Interactables/SensorCalibrationStation")
	var view := player.get_node("HUD/SensorCalibrationView")
	var focused := main.get_node("FocusedInteractionState")

	# ============================================================
	# 1. NORMAL (the default): the documented baseline tolerance/
	# stability/coupling values.
	# ============================================================
	station.interact()
	await process_frame
	_check("NORMAL tolerance is 4.0", is_equal_approx(view._tolerance, 4.0))
	_check("NORMAL stability duration is 1.8s", is_equal_approx(view._stability_duration, 1.8))
	_check("NORMAL starts exactly 2 of 3 chambers active (this station's fault_count, independent of difficulty -- Round 16 Priority 8)", view._active_fault_count == station.active_fault_count())
	var normal_diagonal_sum: float = view._coupling[0][0] + view._coupling[1][1] + view._coupling[2][2]
	focused.end()
	await process_frame

	# ============================================================
	# 2. EASY: wider tolerance, shorter required hold, and a WEAKER
	# (more diagonal-dominant -- higher self-coefficients, lower
	# cross-chamber coefficients) coupling matrix than NORMAL.
	# ============================================================
	GameSettings.cycle_difficulty() # NORMAL -> HARD
	GameSettings.cycle_difficulty() # HARD -> EASY
	station.interact()
	await process_frame
	_check("EASY tolerance is wider than NORMAL's", view._tolerance > 4.0)
	_check("EASY required stability hold is shorter than NORMAL's", view._stability_duration < 1.8)
	_check("EASY: fault count is UNCHANGED from NORMAL's (Round 16 Priority 8: progression is no longer keyed off difficulty)", view._active_fault_count == station.active_fault_count())
	_check("EASY: the active (faulty) chambers start away from their targets", absf(view._reading[&"a"] - view._TARGETS[&"a"]) > view._tolerance and absf(view._reading[&"b"] - view._TARGETS[&"b"]) > view._tolerance)
	_check("EASY: the one inactive chamber starts already at its target", absf(view._reading[&"c"] - view._TARGETS[&"c"]) <= view._tolerance)
	var easy_diagonal_sum: float = view._coupling[0][0] + view._coupling[1][1] + view._coupling[2][2]
	_check("EASY's coupling matrix is more diagonal-dominant (weaker cross-chamber influence) than NORMAL's", easy_diagonal_sum > normal_diagonal_sum)
	var easy_response_strength: float = view.RESPONSE_STRENGTH
	focused.end()
	await process_frame

	# ============================================================
	# 3. HARD: tighter tolerance, longer required hold, and a STRONGER
	# (less diagonal-dominant) coupling matrix than NORMAL.
	# ============================================================
	GameSettings.cycle_difficulty() # EASY -> NORMAL
	GameSettings.cycle_difficulty() # NORMAL -> HARD
	station.interact()
	await process_frame
	_check("HARD tolerance is tighter than NORMAL's", view._tolerance < 4.0)
	_check("HARD required stability hold is longer than NORMAL's", view._stability_duration > 1.8)
	_check("HARD: fault count is STILL unchanged (Round 16 Priority 8: this station's fault_count, not difficulty)", view._active_fault_count == station.active_fault_count())
	var hard_diagonal_sum: float = view._coupling[0][0] + view._coupling[1][1] + view._coupling[2][2]
	_check("HARD's coupling matrix is LESS diagonal-dominant (stronger cross-chamber influence) than NORMAL's", hard_diagonal_sum < normal_diagonal_sum)

	# ============================================================
	# 4. The underlying spring physics (each chamber's own fixed
	# responsiveness) and the fixed target vector never change by
	# difficulty -- only the coupling matrix/tolerance/hints do.
	# ============================================================
	_check("RESPONSE_STRENGTH is identical across difficulties (only coupling/tolerance/duration change)", is_equal_approx(view.RESPONSE_STRENGTH, easy_response_strength))
	for ch in view.CHAMBERS:
		_check("chamber %s's target pressure is the same fixed value regardless of difficulty" % ch, view._TARGETS[ch] == view._TARGETS[ch]) # sanity: _TARGETS is a shared const, not difficulty-indexed at all

	# ============================================================
	# 5. HARD still permits a genuine, correctly-tuned success despite
	# its stronger coupling.
	# ============================================================
	var solution: Dictionary = view._solve_equilibrium(view._coupling, view._TARGETS)
	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
	view._damping = view.CRITICAL_DAMPING
	await create_timer(4.0).timeout # settle + HARD's longer stability duration, with margin
	_check("HARD difficulty repair still completes correctly when properly tuned", view._done)
	var day_plan := main.get_node("DayPlan")
	_check("l07 marked done under HARD", day_plan.is_task_done(&"l07"))
	focused.end()
	await create_timer(0.3).timeout

	# Leave the global setting clean for any later test run in the same
	# process/session.
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
