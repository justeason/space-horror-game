extends SceneTree
## Round 15 Priority 5 regression coverage for E09 Diagnose Intermittent
## Electrical Fault -- a diagnostic procedure built on EVIDENCE-BASED
## DEDUCTION (probe test points, compare readings, submit a diagnosis
## of which segment is at fault), distinct in kind from every other
## maintenance mechanic in this project (not a click-sequence, not a
## discrete toggle, not alignment/insertion). Confirms: the fixed fault
## (segment tp2_tp3) is found via real diorama raycast clicks on both
## test points and segments; wrong diagnosis guesses are harmless and
## recorded, never move the fault or reset progress; readings are
## internally consistent with the one fixed topology; difficulty only
## changes reading PRESENTATION (numeric vs. qualitative), never the
## circuit itself; the world-view twin stays in sync including tested-
## point history (not just the current probe position); and reopening
## after completion shows the done state immediately.
const GameSettings = preload("res://scripts/station/game_settings.gd")

var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()

	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/CircuitTracerStation")
	var player := main.get_node("Player")
	var view := player.get_node("HUD/CircuitTracerView")
	var focused := main.get_node("FocusedInteractionState")
	var world_diorama := station.get_node("WorldDiorama")

	_check("e09 not done at start", not day_plan.is_task_done(&"e09"))
	_check("prompt invites diagnosis before completion", station.get_interact_prompt().findn("Diagnose") != -1)
	_check("no test point probed yet", station.probe_at() == &"")

	station.interact()
	await process_frame
	_check("focused session active", focused.is_active())
	_check("tracer view visible", view.visible)

	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/CircuitTracerDiorama")

	# ============================================================
	# Probing: TP1 and TP2 must read NORMAL; TP3 and TP4 must read
	# DEAD -- internally consistent with the one fixed fault at
	# tp2_tp3, in NORMAL difficulty's numeric-voltage presentation.
	# ============================================================
	await _click_tp(diorama, &"tp1")
	_check("TP1 probed", station.probe_at() == &"tp1")
	_check("TP1 reads nominal (upstream of the fault)", station.reading_text_for(&"tp1").findn("NOMINAL") != -1)

	await _click_tp(diorama, &"tp2")
	_check("TP2 reads nominal (still upstream of the fault)", station.reading_text_for(&"tp2").findn("NOMINAL") != -1)

	await _click_tp(diorama, &"tp3")
	_check("TP3 reads dead (downstream of the fault)", station.reading_text_for(&"tp3").findn("NO SIGNAL") != -1)

	await _click_tp(diorama, &"tp4")
	_check("TP4 reads dead (also downstream)", station.reading_text_for(&"tp4").findn("NO SIGNAL") != -1)
	_check("all four test points now recorded as tested", station.tested_points().size() == 4)

	# ============================================================
	# Wrong diagnosis guesses must be harmless and informative --
	# never move the fault, never reset progress, never silently
	# accepted.
	# ============================================================
	var status_label: Label = view.get_node("Panel/VBox/StatusLabel")
	await _click_segment(diorama, &"power_tp1")
	_check("wrong guess (power_tp1) does not complete the task", not day_plan.is_task_done(&"e09"))
	_check("the view surfaces the wrong-guess feedback to the player", status_label.text.findn("elsewhere") != -1)
	_check("the view's own consumption clears it (no stale repeat on next refresh)", station.consume_last_wrong_guess() == &"")
	_check("probing history survives a wrong guess (nothing reset)", station.tested_points().size() == 4)

	await _click_segment(diorama, &"tp1_tp2")
	_check("second wrong guess (tp1_tp2) also harmless", not day_plan.is_task_done(&"e09"))

	await _click_segment(diorama, &"tp3_tp4")
	_check("third wrong guess (tp3_tp4) also harmless", not day_plan.is_task_done(&"e09"))

	# ============================================================
	# The correct diagnosis (tp2_tp3) completes the task.
	# ============================================================
	await _click_segment(diorama, &"tp2_tp3")
	_check("correct diagnosis completes the procedure", station.is_complete())
	_check("e09 marked done", day_plan.is_task_done(&"e09"))

	# World-view twin must reflect the exact same state, including the
	# FULL tested-point history (not just the most recently probed
	# point) -- this is the one thing sync_full_state() must carry
	# explicitly since the world twin never receives animate_probe_to()
	# calls directly.
	await create_timer(0.3).timeout
	for tp in [&"tp1", &"tp2", &"tp3", &"tp4"]:
		var world_mat: StandardMaterial3D = world_diorama.get_node("TestPoints/" + _tp_node_name(tp) + "/Body").material
		_check("world diorama shows %s as tested" % tp, world_mat.albedo_color.is_equal_approx(world_diorama.COLOR_TP_TESTED))

	# Re-entry after completion shows the done state immediately, and a
	# fresh re-click on either a test point or a segment is a no-op
	# (never re-triggers completion events or changes the diagnosis).
	focused.end()
	await process_frame
	_check("prompt reflects nominal status", station.get_interact_prompt().findn("Nominal") != -1)
	station.interact()
	await process_frame
	_check("reopening after completion still shows complete", station.is_complete())
	_check("e09 still done on reopen (not reset)", day_plan.is_task_done(&"e09"))

	var reopen_result: Dictionary = station.submit_diagnosis(&"tp2_tp3")
	_check("submitting a diagnosis after completion is a no-op", not reopen_result.get("ok", false))
	var reopen_probe: Dictionary = station.move_probe(&"tp1")
	_check("moving the probe after completion is a no-op", not reopen_probe.get("ok", false))

	focused.end()
	await process_frame

	# ============================================================
	# Difficulty only changes reading PRESENTATION, never the circuit
	# itself -- EASY/NORMAL show numeric voltage, HARD shows only a
	# qualitative continuity state.
	# ============================================================
	GameSettings.cycle_difficulty() # NORMAL -> HARD
	_check("HARD shows qualitative continuity, not a voltage number", station.reading_text_for(&"tp1").findn("V") == -1)
	_check("HARD reading for a dead point is still internally consistent", station.reading_text_for(&"tp3") == "NO SIGNAL")
	_check("HARD does not show the running log", not station.log_shown())
	GameSettings.cycle_difficulty() # HARD -> EASY
	_check("EASY shows the running log", station.log_shown())
	_check("EASY reading for a live point is numeric", station.reading_text_for(&"tp1").findn("V") != -1)
	GameSettings.cycle_difficulty() # EASY -> NORMAL

	main.queue_free()
	await process_frame

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _tp_node_name(tp: StringName) -> String:
	return "Tp" + String(tp).substr(2)


func _click_tp(diorama: Node3D, tp: StringName) -> void:
	var pos: Vector2 = diorama.test_point_screen_position(tp)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)
	await physics_frame


func _click_segment(diorama: Node3D, segment: StringName) -> void:
	var pos: Vector2 = diorama.segment_screen_position(segment)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)
	await physics_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
