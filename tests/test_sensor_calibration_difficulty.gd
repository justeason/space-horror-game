extends SceneTree
## Round 13 Workstream D rewrite: L07's global-difficulty coverage,
## updated for the six-chamber coupled system (Round 18 Priority 3).
## Confirms: EASY uses a WEAKER (more diagonal-dominant) coupling matrix,
## a wider tolerance and a shorter stability hold than NORMAL; HARD uses
## a STRONGER coupling matrix, a tighter tolerance and a longer hold;
## the fixed target vector and RESPONSE_STRENGTH never change by
## difficulty (only the coupling matrix/tolerance/duration do); and HARD
## still permits a genuine, correctly-tuned success despite its stronger
## cross-chamber influence making the puzzle harder to decouple by eye.
##
## Round 18 Priority 3 update (supersedes Round 16 Priority 8): the
## brief's own explicit instruction this round ties the REQUIRED
## CALIBRATION COUNT to difficulty (EASY 1-2, NORMAL 3-4, HARD 5-6 of 6
## chambers), randomized within that range each attempt --
## debug_force_active_count() pins an exact value for deterministic
## assertions here, mirroring every other debug_force_*() hook already
## established in this project.
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
	# stability/coupling values, and a forced required count of 3 (must
	# land inside NORMAL's own documented 3-4 range).
	# ============================================================
	view.debug_force_active_count(3)
	station.interact()
	await process_frame
	_check("NORMAL tolerance is 4.0", is_equal_approx(view._tolerance, 4.0))
	_check("NORMAL stability duration is 1.8s", is_equal_approx(view._stability_duration, 1.8))
	_check("NORMAL: forced required count of 3 is honored (within NORMAL's own 3-4 range)", view._active_fault_count == 3)
	var normal_diagonal_sum: float = _diagonal_sum(view._coupling)
	focused.end()
	await process_frame

	# ============================================================
	# 2. EASY: wider tolerance, shorter required hold, a WEAKER (more
	# diagonal-dominant) coupling matrix than NORMAL, and a required
	# count genuinely randomized within EASY's own 1-2 range (not forced
	# this time -- confirms the real random path, not just the debug
	# override).
	# ============================================================
	view._debug_forced_count = -1
	GameSettings.cycle_difficulty() # NORMAL -> HARD
	GameSettings.cycle_difficulty() # HARD -> EASY
	station.interact()
	await process_frame
	_check("EASY tolerance is wider than NORMAL's", view._tolerance > 4.0)
	_check("EASY required stability hold is shorter than NORMAL's", view._stability_duration < 1.8)
	_check("EASY: random required count lands in the documented 1-2 range", view._active_fault_count >= 1 and view._active_fault_count <= 2)
	var easy_diagonal_sum: float = _diagonal_sum(view._coupling)
	_check("EASY's coupling matrix is more diagonal-dominant (weaker cross-chamber influence) than NORMAL's", easy_diagonal_sum > normal_diagonal_sum)
	var easy_response_strength: float = view.RESPONSE_STRENGTH
	focused.end()
	await process_frame

	# ============================================================
	# 3. HARD: tighter tolerance, longer required hold, a STRONGER (less
	# diagonal-dominant) coupling matrix than NORMAL, and a forced
	# required count of 6 (all chambers active -- the documented upper
	# end of HARD's 5-6 range).
	# ============================================================
	view.debug_force_active_count(6)
	GameSettings.cycle_difficulty() # EASY -> NORMAL
	GameSettings.cycle_difficulty() # NORMAL -> HARD
	station.interact()
	await process_frame
	_check("HARD tolerance is tighter than NORMAL's", view._tolerance < 4.0)
	_check("HARD required stability hold is longer than NORMAL's", view._stability_duration > 1.8)
	_check("HARD: forced required count of 6 is honored (within HARD's own 5-6 range)", view._active_fault_count == 6)
	_check("HARD: every chamber starts away from its target when all 6 are active", view.CHAMBERS.all(func(ch): return absf(view._reading[ch] - view._TARGETS[ch]) > view._tolerance))
	var hard_diagonal_sum: float = _diagonal_sum(view._coupling)
	_check("HARD's coupling matrix is LESS diagonal-dominant (stronger cross-chamber influence) than NORMAL's", hard_diagonal_sum < normal_diagonal_sum)

	# ============================================================
	# 4. The underlying spring physics (each chamber's own fixed
	# responsiveness) and the fixed target vector never change by
	# difficulty -- only the coupling matrix/tolerance/hints do.
	# ============================================================
	_check("RESPONSE_STRENGTH is identical across difficulties (only coupling/tolerance/duration change)", is_equal_approx(view.RESPONSE_STRENGTH, easy_response_strength))
	_check("CHAMBERS has 6 entries (Round 18 Priority 3 expansion)", view.CHAMBERS.size() == 6)

	# ============================================================
	# 5. HARD still permits a genuine, correctly-tuned success despite
	# its stronger coupling, with all 6 chambers active.
	# ============================================================
	var solution: Dictionary = view._solve_equilibrium(view._coupling, view._TARGETS)
	_check("HARD's 6x6 coupling system has a real solution (Gaussian elimination didn't hit a singular matrix)", not solution.is_empty())
	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
	view._damping = view.CRITICAL_DAMPING
	await create_timer(4.0).timeout # settle + HARD's longer stability duration, with margin
	_check("HARD difficulty repair still completes correctly when properly tuned, all 6 chambers active", view._done)
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


func _diagonal_sum(matrix: Array) -> float:
	var sum: float = 0.0
	for i in matrix.size():
		sum += matrix[i][i]
	return sum


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
