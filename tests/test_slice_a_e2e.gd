extends SceneTree
## End-to-end Slice A: Wake -> C01 -> travel to Engineering -> E06 ->
## travel back -> C05 -> travel to Living -> sleep -> next day.
## Validates actual state transitions at each beat, not just that
## functions were callable.
var _ok := true
func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var dp := main.get_node("DayPlan")
	var loose := main.get_node("Interactables/LooseConnection")

	# 1. Wake (start of session = awake, standing, in Living Quarters
	# per the scene's own starting transform -- no special action
	# needed to represent "wake" the very first time).
	_check("starts awake, not sitting", not sleep_state.is_sitting())

	# 2. (Optional personal routine) -- intentionally skipped entirely,
	# per Slice A's own requirement that optional content never blocks
	# the loop.

	# 3/4. Travel to Control Room workstation, C01.
	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	for i in 3: await process_frame
	console.interact()
	await create_timer(1.0).timeout
	_check("workstation in use", wstate.is_in_use())
	_send_key(KEY_1)
	await create_timer(0.05).timeout
	_send_key(KEY_R)
	await create_timer(0.05).timeout
	_check("C01 complete", dp.is_task_done(&"c01"))

	# 5. Assignment received.
	_check("assignment is E06 in Engineering", dp.assignment_task_id == &"e06")
	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout
	_check("back in control of the player after exiting workstation", not wstate.is_in_use())

	# 6/7. Travel to Engineering, E06.
	var loose_pos: Vector3 = loose.global_position + Vector3(0.3, 1.6 - loose.global_position.y, 0.3)
	free_body.sync_to_eye_position(loose_pos)
	player.global_position = loose_pos
	for i in 3: await process_frame
	for i in 6:
		loose.interact()
	_check("E06 complete", dp.is_task_done(&"e06"))

	# 8. Return to Control, C05.
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	for i in 3: await process_frame
	console.interact()
	await create_timer(1.0).timeout
	_send_key(KEY_2)
	await create_timer(0.05).timeout
	_send_key(KEY_R)
	await create_timer(0.05).timeout
	_check("C05 complete -- workday verified", dp.is_task_done(&"c05"))
	_send_key(KEY_ESCAPE)
	await create_timer(1.3).timeout

	# 9. Return to Living Quarters, sleep.
	var near_bed := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_bed)
	player.global_position = near_bed
	for i in 3: await process_frame
	bunk.interact()
	await create_timer(1.6).timeout
	_check("sitting on the bed", sleep_state.is_sitting())

	# 10. Sleep -> eyes-closing transition -> minimal reset -> wake.
	sleep_state.begin_sleep()
	await create_timer(2.0).timeout
	_check("awake again after the night", sleep_state.is_sitting() and not sleep_state.is_sleeping())
	_check("next-day reset cleared yesterday's completed work", not dp.is_task_done(&"c01") and not dp.is_task_done(&"e06") and not dp.is_task_done(&"c05"))
	_check("assignment cleared for the new day", dp.assignment_task_id == &"")

	# The player can immediately get up and the whole loop is ready to
	# run again -- no stuck state.
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("standing again, ready for a new day", not sleep_state.is_sitting() and free_body.active)

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
