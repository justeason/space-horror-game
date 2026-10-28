extends SceneTree
var _ok := true
func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var screen := console.get_node("WorkstationScreen")
	var surv := main.get_node("Interactables/SurveillanceConsole")
	var dp := main.get_node("DayPlan")
	var loose := main.get_node("Interactables/LooseConnection")
	var wire := main.get_node("Interactables/WireComponent")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var carry := main.get_node("Player/CarrySystem")

	console.interact()
	await create_timer(1.0).timeout

	# Surveillance: single shared owner, no duplicated state.
	_send_key(KEY_4)
	await create_timer(0.05).timeout
	var cam_before: StringName = surv.get_current_camera_id()
	_check("workstation reads the SAME camera id the physical console owns", screen._surveillance_label.text.findn(String(cam_before)) != -1)
	_send_key(KEY_R) # cycle camera via the workstation
	await create_timer(0.05).timeout
	var cam_after: StringName = surv.get_current_camera_id()
	_check("cycling from the workstation actually changed the ONE shared selection", cam_after != cam_before)
	_check("physical console's own state reflects the same change (single owner)", surv.get_current_camera_id() == cam_after)

	# Slice A: C05 before E06 reports still-open; after, reports done.
	_send_key(KEY_1)
	await create_timer(0.05).timeout
	_send_key(KEY_R) # C01
	await create_timer(0.05).timeout
	_send_key(KEY_2)
	await create_timer(0.05).timeout
	_send_key(KEY_R) # premature verify attempt
	await create_timer(0.05).timeout
	_check("C05 before E06 does not mark the day complete", not dp.is_task_done(&"c05"))

	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout

	for i in 6:
		loose.interact()
	_check("e06 actually done now", dp.is_task_done(&"e06"))

	console.interact()
	await create_timer(1.0).timeout
	_send_key(KEY_2)
	await create_timer(0.05).timeout
	_send_key(KEY_R) # verify again, now it should succeed
	await create_timer(0.05).timeout
	_check("C05 after E06 marks c05 done", dp.is_task_done(&"c05"))

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
