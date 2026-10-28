extends SceneTree
## Regression coverage for the Control Room workstation's interaction
## contract (added alongside the physical redesign / contextual-prompt
## work): a standing player must be within range before interact()
## starts the sit-down sequence, and keyboard section/run shortcuts must
## do nothing until actually seated.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var screen := console.get_node("WorkstationScreen")

	# ============================================================
	# 1. Far away: interact() must not start the sit-down sequence.
	# ============================================================
	var far_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 4.0)
	free_body.sync_to_eye_position(far_pos)
	player.global_position = far_pos
	await process_frame
	_check("far away: is_player_near() is false", not console.is_player_near())
	console.interact()
	await create_timer(0.3).timeout
	_check("far away: interact() did not start using the workstation", not wstate.is_in_use())

	# ============================================================
	# 1b. The exact boundary: right at interact_range must still count
	# as near (inclusive <=), and a small step beyond it must not.
	# ============================================================
	var range_m: float = console.interact_range
	var at_boundary: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, range_m)
	free_body.sync_to_eye_position(at_boundary)
	player.global_position = at_boundary
	await process_frame
	_check("at exactly interact_range: counts as near", console.is_player_near())

	var just_outside: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, range_m + 0.15)
	free_body.sync_to_eye_position(just_outside)
	player.global_position = just_outside
	await process_frame
	_check("15cm beyond interact_range: does not count as near", not console.is_player_near())
	console.interact()
	await create_timer(0.3).timeout
	_check("15cm beyond interact_range: interact() does not start using the workstation", not wstate.is_in_use())

	# ============================================================
	# 2. Keyboard shortcuts do nothing while standing (not yet seated),
	# even if the player is close and looking at the screen.
	# ============================================================
	var near_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	await process_frame
	_check("near: is_player_near() is true", console.is_player_near())
	_send_key(KEY_1)
	await create_timer(0.05).timeout
	_check("standing (not seated): number-key section shortcuts do nothing", screen.current_section() == 0)
	_check("standing (not seated): still not in use", not wstate.is_in_use())

	# ============================================================
	# 3. Within range: interact() starts the sequence, and once
	# settled, keyboard shortcuts work.
	# ============================================================
	console.interact()
	await create_timer(1.0).timeout
	_check("near: interact() started using the workstation", wstate.is_in_use())
	_send_key(KEY_2)
	await create_timer(0.05).timeout
	_check("seated: number-key section shortcuts now work", screen.current_section() == 2)

	# ============================================================
	# 4. Get up: input stops immediately (same instant end_use() is
	# called, not just once the stand-up tween finishes).
	# ============================================================
	wstate.end_use()
	_check("get-up: no longer in use immediately", not wstate.is_in_use())
	_send_key(KEY_1)
	await create_timer(0.05).timeout
	_check("mid get-up: number-key shortcuts already inert", screen.current_section() == 2)

	await create_timer(1.3).timeout
	_check("get-up settled: not stuck mid-transition", not wstate.is_in_use())

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
