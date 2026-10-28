extends SceneTree
## End-to-end Slice B: C02 -> E01 -> E02 -> (identify wire) -> S01 ->
## E05 -> C05. Control -> Engineering -> Storage -> Engineering ->
## Control, without ever forcing a detour back through Control between
## Engineering and Storage.
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true
func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty() # isolate from any stray persisted difficulty
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var dp := main.get_node("DayPlan")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var wire := main.get_node("Interactables/WireComponent")
	var carry := player.get_node("CarrySystem")

	# Control: C02 Run Subsystem Diagnostic.
	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	for i in 3: await process_frame
	console.interact()
	await create_timer(1.0).timeout
	_send_key(KEY_3)
	await create_timer(0.05).timeout
	_send_key(KEY_R)
	await create_timer(0.05).timeout
	_check("C02 reveals the fault", dp.is_task_done(&"c02") and dp.fault_target == &"engineering_power")
	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout

	# Engineering (no detour back through Control): E01 then E02.
	var panel_pos: Vector3 = panel.global_position + Vector3(0.4, 1.6 - panel.global_position.y, 0.4)
	free_body.sync_to_eye_position(panel_pos)
	player.global_position = panel_pos
	for i in 3: await process_frame
	panel.interact() # open the cabinet door (door open/close only, no task progress)
	_check("panel opens on first interact", panel.is_door_open())
	# Round 16 Priority 3: force the deterministic default config -- this
	# file hardcodes the fixed supply/return/service order further below
	# (see tests/test_electrical_wire_randomization.gd for the alternate
	# one).
	panel.debug_force_fault_role(&"service")
	panel.terminal_interact(&"damaged") # E01
	_check("E01 inspection found the damaged wire", dp.is_task_done(&"e01"))
	panel.terminal_interact(&"damaged") # E02
	_check("E02 traced the circuit and specified the part", dp.is_task_done(&"e02") and dp.required_component_id == &"wire_control_16ga")

	# Attempting the repair with empty hands first: must fail cleanly,
	# without losing the diagnostic progress already made.
	panel.terminal_interact(&"damaged")
	_check("repair attempt with empty hands does not repair", not panel.is_repaired())
	_check("E02 state preserved after the failed attempt", dp.is_task_done(&"e02"))

	# Storage (direct from Engineering, no Control detour): S01 Retrieve Component.
	var wire_pos: Vector3 = wire.global_position + Vector3(0.3, 1.6 - wire.global_position.y, 0.3)
	free_body.sync_to_eye_position(wire_pos)
	player.global_position = wire_pos
	for i in 3: await process_frame
	wire.interact()
	_check("S01: correct wire retrieved and now carried", carry.is_carrying() and carry.carried_item_id() == &"wire_control_16ga")

	# Back to Engineering (direct, no Control detour): E05 Replace Damaged Wire.
	free_body.sync_to_eye_position(panel_pos)
	player.global_position = panel_pos
	for i in 3: await process_frame
	_check("door is still open from before the Storage trip", panel.is_door_open())
	panel.terminal_interact(&"damaged") # opens the focused multi-stage repair procedure
	_check("E05 procedure opened", panel.procedure_stage() == &"isolate")
	panel.toggle_isolation()
	panel.disconnect_wire(&"supply")
	panel.disconnect_wire(&"return")
	panel.disconnect_wire(&"service")
	panel.install_replacement_wire()
	panel.reconnect_wire(&"service")
	panel.reconnect_wire(&"return")
	panel.reconnect_wire(&"supply")
	panel.restore_power()
	# Close the real focused session the terminal click above opened --
	# see electrical_panel.gd's _open_procedure() -- now that the
	# procedure is complete, same as pressing Enter/Escape, so
	# interactions_enabled/free movement/look input are restored before
	# this test continues on to the Control Room/C05 sequence below.
	main.get_node("FocusedInteractionState").end()
	_check("E05: wire installed, panel repaired", panel.is_repaired() and dp.is_task_done(&"e05"))
	_check("wire consumed from hand", not carry.is_carrying())
	_check("installed wire is visible and parented at the terminal, not deleted", is_instance_valid(wire) and wire.is_installed())

	# Control: C05 Verify Repaired System.
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	for i in 3: await process_frame
	console.interact()
	await create_timer(1.0).timeout
	_send_key(KEY_2)
	await create_timer(0.05).timeout
	_send_key(KEY_R)
	await create_timer(0.05).timeout
	_check("C05 confirms the repair", dp.is_task_done(&"c05"))
	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout
	_check("player fully back in control after the whole chain", not wstate.is_in_use())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
