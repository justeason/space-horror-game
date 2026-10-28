extends SceneTree
## Regression for two specific reported bugs in this round:
## 1. "After I pressed T to edit, the whole body sinks into the bed" --
##    root cause: the editor zoom used to tween Player.global_position
##    (the eye), and since the whole SittingPose body is authored
##    relative to that same origin, lowering/moving the eye toward the
##    laptop dragged the entire seated body (legs included) down with
##    it, sinking the feet below the mattress. Fixed by zooming
##    LookPivot's local position instead (moves only the camera);
##    PlayerBody is a SEPARATE child of Player and never moves.
## 2. "After pressing T I don't see the interface to edit" -- root
##    cause: the zoom moved the eye closer without ever changing where
##    it was LOOKING, so if the player hadn't been idle long enough for
##    the separate soft focus-assist to kick in, they could zoom in
##    while still facing some other direction. Fixed by having the zoom
##    also aim the camera at the screen immediately (eased, not
##    snapped).

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var player_body := player.get_node("PlayerBody")
	var sitting_pose := player_body.get_node("SittingPose")
	var laptop_view := player.get_node("LaptopView")
	var camera := player.get_node("LookPivot/PitchPivot/Camera3D")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame
	bunk.interact()
	await create_timer(1.6).timeout

	var foot_before: Vector3 = sitting_pose.get_node("FootR").global_position
	var hip_before: Vector3 = sitting_pose.get_node("Hips").global_position
	var player_pos_before: Vector3 = player.global_position

	_send_key(KEY_F)
	await create_timer(0.6).timeout

	# Make sure the player is facing somewhere other than the screen
	# before entering the editor, so the "camera must re-aim itself"
	# fix is actually exercised, not vacuously true.
	var look_controller := player.get_node("LookPivot")
	look_controller._target_yaw += 2.5
	look_controller.rotation.y += 2.5
	await process_frame

	_send_key(KEY_T)
	await create_timer(0.6).timeout
	_check("precondition: editing", sleep_state.is_editing())

	# ============================================================
	# BUG 1: the body must NOT have moved at all -- PlayerBody is
	# independent of the camera-only zoom.
	# ============================================================
	var foot_after: Vector3 = sitting_pose.get_node("FootR").global_position
	var hip_after: Vector3 = sitting_pose.get_node("Hips").global_position
	_check("body: foot position unchanged by the editor zoom (moved %.4fm)" % foot_before.distance_to(foot_after), foot_before.distance_to(foot_after) < 0.001)
	_check("body: hip position unchanged by the editor zoom (moved %.4fm)" % hip_before.distance_to(hip_after), hip_before.distance_to(hip_after) < 0.001)
	_check("body: Player.global_position itself is unchanged (the body's whole frame of reference)", player.global_position.distance_to(player_pos_before) < 0.001)
	_check("body: feet still at/above mattress height, not sunk (got y=%.2f)" % foot_after.y, foot_after.y > 0.5)

	# ============================================================
	# BUG 2: the camera must actually be looking AT the screen once
	# zoomed in, not wherever it happened to face before pressing T.
	# ============================================================
	var screen_pos: Vector3 = laptop_view.get_screen_global_position()
	var forward: Vector3 = -camera.global_transform.basis.z
	var to_screen: Vector3 = (screen_pos - camera.global_position).normalized()
	var aim_dot: float = forward.dot(to_screen)
	_check("aim: camera forward points at the screen after zooming in (dot=%.2f, want > 0.9)" % aim_dot, aim_dot > 0.9)

	# The camera (not the body) DID move closer -- that's the actual
	# "enlarge the screen" zoom.
	_check("zoom: the camera itself moved toward the screen", look_controller.position.length() > 0.05)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
