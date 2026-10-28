extends SceneTree
## Round 13 Workstream D: dedicated coverage for the actual NEW
## mechanic L07 gained this round -- cross-chamber coupling -- on top
## of (not replacing) test_sensor_calibration.gd's broader simulation/
## completion coverage. Verifies, as genuine simulated behavior rather
## than labels claiming it:
##   - every difficulty's coupling matrix has a real, in-bounds,
##     in-range equilibrium solution (the actual "is this puzzle
##     solvable" check, per the explicit D8 requirement) -- not merely
##     that SOME solution exists mathematically, but that it lands
##     within [0,100] for every chamber;
##   - a plausible sequence of player adjustments (move each regulator
##     toward its own solved value, raise damping) actually reaches
##     completion, for NORMAL specifically (the default difficulty);
##   - the direction of cross-chamber influence matches each matrix's
##     own authored sign/magnitude (every coefficient here is positive,
##     so raising any one regulator must never visibly LOWER another
##     chamber's reading);
##   - numeric stability: stepping the simulation with many small
##     substeps vs. fewer larger ones (both clamped by
##     MAX_PHYSICS_STEP) converges to the same equilibrium, confirming
##     the integration is not frame-rate dependent in a way that would
##     make the puzzle behave inconsistently across machines.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var station := main.get_node("Interactables/SensorCalibrationStation")
	var view := player.get_node("HUD/SensorCalibrationView")
	const GameSettings = preload("res://scripts/station/game_settings.gd")

	station.interact()
	await process_frame

	# ============================================================
	# 1. Solvability: every difficulty's coupling matrix has a real
	# equilibrium solution landing within the actual reachable gauge
	# range [0,100] for all three chambers -- the puzzle is never
	# impossible to solve at any difficulty.
	# ============================================================
	for diff_name in ["EASY", "NORMAL", "HARD"]:
		var diff_val: int = GameSettings.Difficulty[diff_name]
		var matrix: Array = view._COUPLING_BY_DIFFICULTY[diff_val]
		var solution: Dictionary = view._solve_equilibrium(matrix, view._TARGETS)
		_check("%s: a real equilibrium solution exists (matrix is invertible)" % diff_name, not solution.is_empty())
		for ch in view.CHAMBERS:
			_check(
				"%s: solved setpoint for chamber %s is within the reachable gauge range (%.1f)" % [diff_name, ch, solution.get(ch, -1.0)],
				solution.has(ch) and solution[ch] >= 0.0 and solution[ch] <= 100.0
			)
		# Residual check: M * solution must equal the target vector
		# EXACTLY (within floating-point tolerance) -- confirms the
		# solver's output is a genuine fixed point, not an approximation.
		for i in view.CHAMBERS.size():
			var row: Array = matrix[i]
			var sum: float = 0.0
			for j in view.CHAMBERS.size():
				sum += row[j] * solution[view.CHAMBERS[j]]
			_check(
				"%s: solution satisfies row %d exactly (M*S=%.4f, target=%.4f)" % [diff_name, i, sum, view._TARGETS[view.CHAMBERS[i]]],
				is_equal_approx(sum, view._TARGETS[view.CHAMBERS[i]])
			)

	# ============================================================
	# 2. A plausible player sequence actually reaches completion under
	# NORMAL: drive every setpoint toward its own solved value, raise
	# damping toward critical, and let the coupled system settle.
	# ============================================================
	var solution: Dictionary = view._solve_equilibrium(view._coupling, view._TARGETS)
	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
	view._damping = view.CRITICAL_DAMPING
	await create_timer(3.5).timeout
	_check("a plausible adjustment sequence (set every regulator to its solved value, raise damping) reaches completion under NORMAL", view._done)

	main.get_node("FocusedInteractionState").end()
	await process_frame

	# ============================================================
	# 3. Direction of influence: every authored coefficient is
	# positive, so raising chamber A's regulator alone must never
	# LOWER chamber B's or C's reading -- it should raise or hold them,
	# never push them the opposite way.
	# ============================================================
	station.interact()
	await process_frame
	for ch in view.CHAMBERS:
		view._setpoint[ch] = 50.0
		view._reading[ch] = 50.0
		view._velocity[ch] = 0.0
	view._damping = view.CRITICAL_DAMPING
	for i in 60: view._step_springs(1.0 / 60.0) # let it settle at the neutral baseline first
	var baseline_b: float = view._reading[&"b"]
	var baseline_c: float = view._reading[&"c"]
	view._setpoint[&"a"] = 90.0 # a large, isolated change to A only
	for i in 90: view._step_springs(1.0 / 60.0)
	_check("raising chamber A alone does not LOWER chamber B's reading (all coupling coefficients are positive)", view._reading[&"b"] >= baseline_b - 0.01)
	_check("raising chamber A alone does not LOWER chamber C's reading (all coupling coefficients are positive)", view._reading[&"c"] >= baseline_c - 0.01)
	_check("raising chamber A alone measurably raises chamber B's reading (real coupling, not zero)", view._reading[&"b"] > baseline_b + 1.0)

	main.get_node("FocusedInteractionState").end()
	await process_frame

	# ============================================================
	# 4. Numeric stability across different substep counts: integrating
	# the SAME total elapsed time via many small steps vs. fewer larger
	# ones (both within MAX_PHYSICS_STEP) must converge to
	# approximately the same reading -- confirms the simulation is not
	# meaningfully frame-rate dependent.
	# ============================================================
	station.interact()
	await process_frame
	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
		view._reading[ch] = 50.0
		view._velocity[ch] = 0.0
	view._damping = view.CRITICAL_DAMPING
	var total_time: float = 2.0
	var fine_steps: int = 400 # dt=0.005
	for i in fine_steps:
		view._step_springs(total_time / fine_steps)
	var fine_result: Dictionary = {&"a": view._reading[&"a"], &"b": view._reading[&"b"], &"c": view._reading[&"c"]}

	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
		view._reading[ch] = 50.0
		view._velocity[ch] = 0.0
	var coarse_steps: int = 40 # dt=0.05, exactly MAX_PHYSICS_STEP
	for i in coarse_steps:
		view._step_springs(total_time / coarse_steps)
	var coarse_result: Dictionary = {&"a": view._reading[&"a"], &"b": view._reading[&"b"], &"c": view._reading[&"c"]}

	for ch in view.CHAMBERS:
		_check(
			"chamber %s converges to approximately the same reading regardless of substep count (fine=%.3f coarse=%.3f)" % [ch, fine_result[ch], coarse_result[ch]],
			absf(fine_result[ch] - coarse_result[ch]) < 1.0
		)

	main.get_node("FocusedInteractionState").end()
	await create_timer(0.3).timeout

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
