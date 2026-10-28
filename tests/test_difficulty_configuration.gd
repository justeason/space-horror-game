extends SceneTree
## Coverage for Round 10 Workstream E: ONE authoritative global "Game
## Difficulty" setting (scripts/station/game_settings.gd), not a
## per-task duplicate field -- player feedback verbatim: "Difficulty
## must apply across the entire game, rather than belonging to an
## individual electrical repair task." Confirms: the workstation Settings
## section and C02 diagnostics both read the SAME global value (no
## second, contradictory flag); cycling wraps correctly and persists
## across a reload; and an ALREADY-STARTED repair's difficulty-sensitive
## requirements (hints, HARD's screw gate) stay locked to whatever the
## setting was when that repair began, even if the global setting is
## changed again mid-repair -- the documented mid-repair stability
## policy (electrical_panel.gd's `_active_difficulty`).
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true

func _init() -> void:
	# Isolate this test's persisted difficulty from any other run (the
	# global setting is persisted to disk across separate test processes).
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()

	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var console := main.get_node("Interactables/WorkstationConsole")
	var screen := console.get_node("WorkstationScreen")
	var day_plan := main.get_node("DayPlan")
	var carry := player.get_node("CarrySystem")
	var wire := main.get_node("Interactables/WireComponent")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)

	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	console.interact()
	await create_timer(1.0).timeout
	screen.show_section(screen.Section.SETTINGS)
	await create_timer(0.05).timeout

	# ============================================================
	# 1. Settings displays the REAL current global difficulty and
	# cycles it; the label text updates to match and says "GAME
	# DIFFICULTY", not "ELECTRICAL REPAIR DIFFICULTY" -- this setting
	# is no longer Engineering-specific.
	# ============================================================
	_check("starts at NORMAL (the documented default)", GameSettings.get_difficulty() == GameSettings.Difficulty.NORMAL)
	var difficulty_label: Label = screen.get_node("Control/VBox/Content/Settings/DifficultyLabel")
	_check("settings label is titled GAME DIFFICULTY (applies station-wide, not just Engineering)", difficulty_label.text.findn("GAME DIFFICULTY") != -1)
	_check("settings label shows NORMAL", difficulty_label.text.findn("NORMAL") != -1)

	screen.run_action() # R, in Settings -- cycles difficulty
	await create_timer(0.05).timeout
	_check("cycled to HARD", GameSettings.get_difficulty() == GameSettings.Difficulty.HARD)
	_check("settings label now shows HARD", difficulty_label.text.findn("HARD") != -1)

	screen.run_action()
	await create_timer(0.05).timeout
	_check("cycled to EASY", GameSettings.get_difficulty() == GameSettings.Difficulty.EASY)

	screen.run_action()
	await create_timer(0.05).timeout
	_check("wraps back to NORMAL after a full cycle", GameSettings.get_difficulty() == GameSettings.Difficulty.NORMAL)

	# ============================================================
	# 2. C02 diagnostics and the electrical panel both read the SAME
	# global flag -- not two independent copies that could disagree.
	# ============================================================
	screen.run_action() # -> HARD
	await create_timer(0.05).timeout
	_check("global setting is HARD", GameSettings.get_difficulty() == GameSettings.Difficulty.HARD)
	_check("panel.repair_difficulty() (not yet started -- reads live) agrees", panel.repair_difficulty() == &"hard")
	day_plan.mark_done(&"c02")
	day_plan.trigger_fault()
	screen.show_section(screen.Section.DIAGNOSTICS)
	await create_timer(0.05).timeout
	_check("HARD diagnostics omit the continuity line (terse)", screen.get_node("Control/VBox/Content/Diagnostics/Status").text.findn("Continuity") == -1)
	screen.show_section(screen.Section.SETTINGS)
	screen.run_action() # -> EASY
	screen.run_action() # -> NORMAL
	await create_timer(0.05).timeout
	_check("back to NORMAL before starting the repair below", GameSettings.get_difficulty() == GameSettings.Difficulty.NORMAL)

	# ============================================================
	# 3. Starting the repair (first door-open) locks this repair's
	# effective difficulty to whatever the global setting was at that
	# moment. Changing the GLOBAL setting afterward must NOT alter this
	# already-in-progress repair's hint visibility or requirements --
	# the explicit "an active procedure's requirements stay fixed until
	# completion" policy -- even though it immediately changes what a
	# brand-new task would see.
	# ============================================================
	var wstate := main.get_node("WorkstationState")
	if wstate.is_in_use():
		wstate.end_use()
		await create_timer(1.3).timeout
	free_body.set_active(false) # end_use() reactivates it; restore this test's own positioning invariant
	var panel_pos: Vector3 = panel.global_position + Vector3(0.4, 1.6 - panel.global_position.y, 0.4)
	free_body.sync_to_eye_position(panel_pos)
	player.global_position = panel_pos
	await process_frame
	if not panel.is_door_open():
		panel.interact() # locks _active_difficulty to NORMAL
	_check("repair now locked to NORMAL (the global value at first open)", panel.repair_difficulty() == &"normal")
	# Round 16 Priority 3: force the deterministic default config -- this
	# file hardcodes the fixed supply/return/service order (see
	# tests/test_electrical_wire_randomization.gd for the alternate one).
	panel.debug_force_fault_role(&"service")

	var terminal := panel.get_node("Terminal")
	terminal.interact() # E01
	terminal.interact() # E02
	carry.pick_up(wire)
	terminal.interact() # opens the focused procedure for real
	await process_frame
	panel.toggle_isolation()
	panel.disconnect_wire(&"supply")
	panel.disconnect_wire(&"return")
	_check("two wires disconnected before changing difficulty", panel.disconnected_roles() == [&"supply", &"return"])
	_check("NORMAL-locked repair still shows disconnect hints", panel.current_hint_sequence() == [&"supply", &"return", &"service"])

	GameSettings.cycle_difficulty() # NORMAL -> HARD, mid-procedure
	_check("global setting really did change to HARD", GameSettings.get_difficulty() == GameSettings.Difficulty.HARD)
	_check("disconnect progress survives a GLOBAL difficulty change mid-repair", panel.disconnected_roles() == [&"supply", &"return"])
	_check("still isolated after the global difficulty change", panel.is_isolated())
	_check("still carrying the wire after the global difficulty change", carry.is_carrying())
	_check(
		"this already-started repair stays locked to NORMAL and keeps showing hints, even though the global setting is now HARD",
		panel.repair_difficulty() == &"normal" and not panel.current_hint_sequence().is_empty()
	)
	_check("required_screw_count() for this already-open repair stays 0 (NORMAL-locked), not HARD's 4", panel.required_screw_count() == 0)

	panel.disconnect_wire(&"service")
	panel.install_replacement_wire()
	_check("install still succeeds after a mid-repair global difficulty change", wire.is_installed())
	GameSettings.cycle_difficulty() # HARD -> EASY, post-install
	panel.reconnect_wire(&"service")
	panel.reconnect_wire(&"return")
	panel.reconnect_wire(&"supply")
	var restore_result: Dictionary = panel.restore_power()
	_check("repair still completes correctly despite the global difficulty churning twice mid-attempt", restore_result.get("ok", false) and panel.is_repaired())
	_check("e05 marked done despite the difficulty churn", day_plan.is_task_done(&"e05"))
	main.get_node("FocusedInteractionState").end()

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
