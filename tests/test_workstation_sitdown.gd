extends SceneTree
## Dedicated coverage for the Control Room Workstation Revamp's
## sit-down/get-up transition (workstation_state.gd): the player
## actually moves into a seated position (not just a camera zoom),
## settles before the computer becomes usable, and getting up reverses
## cleanly without corrupting state under repeated input.
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
	var player_body := player.get_node("PlayerBody")
	var standing_pose := player_body.get_node("StandingPose")
	var sitting_pose := player_body.get_node("SittingPose")
	var look := player.get_node("LookPivot")
	var ic := player.get_node("LookPivot/PitchPivot/Camera3D")

	# Approach from a reasonable standing distance (not adjacent), within
	# workstation_console.gd's interact_range (1.0m, tightened this
	# round from 2.0m -- see that script's doc comment).
	var approach := Vector3(0.0, 1.6, -0.05)
	free_body.sync_to_eye_position(approach)
	player.global_position = approach
	for i in 3: await process_frame

	_check("starts standing", standing_pose.visible and not sitting_pose.visible)
	_check("not in use yet", not wstate.is_in_use())

	console.interact()
	# Mid-transition: must not have snapped/teleported, must not be
	# usable yet, pose must not have swapped yet.
	await create_timer(0.15).timeout
	_check("mid-transition: not yet in use (computer not usable yet)", not wstate.is_in_use())
	_check("mid-transition: still standing pose (no premature swap)", standing_pose.visible and not sitting_pose.visible)
	var mid_pos: Vector3 = player.global_position
	_check("mid-transition: already moving smoothly (not still at approach pos)", mid_pos.distance_to(approach) > 0.02)
	_check("mid-transition: not yet fully at the seat (still easing)", mid_pos.distance_to(wstate.sit_position) > 0.02)

	# A repeated interact() while mid-transition must not start a second,
	# overlapping transition.
	console.interact()
	await create_timer(0.1).timeout
	_check("repeated interact() mid-transition is a no-op (still not in use)", not wstate.is_in_use())

	await create_timer(1.0).timeout
	_check("settled: in use", wstate.is_in_use())
	_check("settled: eye position exactly at sit_position", player.global_position.distance_to(wstate.sit_position) < 0.001)
	_check("settled: pose swapped to sitting only now", sitting_pose.visible and not standing_pose.visible)
	_check("settled: mouse-look locked", not look.input_enabled)
	_check("settled: movement locked", not free_body.active)
	_check("settled: other interactions locked", not ic.interactions_enabled)
	_check("settled: Home section shown", console.get_node("WorkstationScreen").current_section() == 0)

	# While seated, "movement" must not be able to drift the player away
	# (free_body.active is false, so WASD has no effect at all).
	_check("free body inactive while seated (WASD cannot move the player away)", not free_body.active)

	# Get up.
	_send_key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	_check("get-up: no longer in use immediately", not wstate.is_in_use())
	_check("get-up: look/interactions restored immediately on Esc", look.input_enabled and ic.interactions_enabled)

	# A repeated Esc (or a repeated console click) during the stand-up
	# tween must not corrupt or restart anything.
	_send_key(KEY_ESCAPE)
	console.interact()
	await create_timer(0.1).timeout

	await create_timer(1.0).timeout
	_check("get-up settled: standing pose restored", standing_pose.visible and not sitting_pose.visible)
	_check("get-up settled: back at the original approach position", player.global_position.distance_to(approach) < 0.01)
	_check("get-up settled: movement restored", free_body.active)
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
