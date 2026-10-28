extends SceneTree
var _ok := true
func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var screen := console.get_node("WorkstationScreen")
	var dp := main.get_node("DayPlan")
	var look := player.get_node("LookPivot")
	var free_body := main.get_node("FreeMoveBody")
	var ic := player.get_node("LookPivot/PitchPivot/Camera3D")

	_check("not in use at boot", not wstate.is_in_use())
	console.interact()
	await create_timer(1.0).timeout
	_check("in use after interact", wstate.is_in_use())
	_check("home section shown on entry", screen.current_section() == 0)
	_check("mouse-look locked while in use", not look.input_enabled)
	_check("movement suppressed while in use", not free_body.active)
	_check("interactions suppressed while in use", not ic.interactions_enabled)

	# Depth check: every implemented function reachable within 3 clicks
	# (here: 1 keypress) from Home.
	_send_key(KEY_1)
	await create_timer(0.05).timeout
	_check("[1] -> Overview, 1 keypress from Home", screen.current_section() == 1)
	_send_key(KEY_R)
	await create_timer(0.05).timeout
	_check("C01 runs from Overview", dp.is_task_done(&"c01"))
	_check("assignment pinned to e06 after C01", dp.assignment_task_id == &"e06")

	_send_key(KEY_0)
	await create_timer(0.05).timeout
	_check("[0] -> Home", screen.current_section() == 0)

	_send_key(KEY_2)
	await create_timer(0.05).timeout
	_check("[2] -> Work Orders, 1 keypress from Home", screen.current_section() == 2)

	_send_key(KEY_3)
	await create_timer(0.05).timeout
	_check("[3] -> Diagnostics", screen.current_section() == 3)
	_send_key(KEY_R)
	await create_timer(0.05).timeout
	_check("C02 runs from Diagnostics", dp.is_task_done(&"c02"))
	_check("fault pinned after C02", dp.fault_target == &"engineering_power")

	_send_key(KEY_4)
	await create_timer(0.05).timeout
	_check("[4] -> Surveillance", screen.current_section() == 4)

	_send_key(KEY_5)
	await create_timer(0.05).timeout
	_check("[5] -> Save/Load (marked planned, not pretending to work)", screen.current_section() == 5)

	_send_key(KEY_6)
	await create_timer(0.05).timeout
	_check("[6] -> Settings (marked planned)", screen.current_section() == 6)

	# Esc exits cleanly and restores everything.
	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout
	_check("esc exits use", not wstate.is_in_use())
	_check("mouse-look restored", look.input_enabled)
	_check("movement restored", free_body.active)
	_check("interactions restored", ic.interactions_enabled)

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
