extends SceneTree
## Regression test for the two concrete M7.1 playtest bugs:
## 1. Soft focus-assist turned the camera to face the LAPTOP, not the
##    exact opposite direction (the headboard) -- a parent-rotation
##    sign error in look_controller.gd's yaw math.
## 2. The log-editing overlay is positioned over the laptop's actual
##    projected screen location, not a fixed unrelated screen region.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var player := main.get_node("Player")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var player_body := player.get_node("PlayerBody")
	var lap_anchor := player_body.get_node("LapAnchor")
	var look_pivot := player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var camera := pitch_pivot.get_node("Camera3D")
	var free_body := main.get_node("FreeMoveBody")

	# M7.1: bunk.interact() now requires proximity -- move the free
	# body too, or GlobalFreeMove's per-physics-tick mirror undoes a
	# plain Player.global_position assignment on the very next tick.
	free_body.sync_to_eye_position(Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z))
	player.global_position = Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	await process_frame

	print("step: lying down...")
	bunk.interact()
	await create_timer(1.6).timeout
	print("step: opening laptop...")
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	print("step: checking laptop open...")
	_check("precondition: laptop open", sleep_state.is_laptop_open())

	# Force the view away from the laptop, then let the soft return run
	# to completion, and check it actually faces TOWARD the laptop
	# (not the opposite direction -- the exact bug reported).
	print("step: forcing look-away and waiting for soft-return...")
	look_pivot._target_yaw += PI * 0.5
	look_pivot._focus_idle_time = 0.0
	await create_timer(2.0).timeout # well past focus_assist_idle_delay
	print("step: checking alignment...")

	var forward: Vector3 = -camera.global_transform.basis.z
	var to_anchor: Vector3 = (lap_anchor.global_position - camera.global_position).normalized()
	var alignment: float = forward.dot(to_anchor)
	_check("soft-return: camera forward now points TOWARD the lap anchor (dot=%.2f, want > 0.8)" % alignment, alignment > 0.8)
	_check("soft-return: camera does NOT point away from the lap anchor (would be dot < -0.5)", alignment > -0.5)

	# M7.2: begin editing and confirm the log now lives entirely on the
	# laptop's physical 3D screen (no more projected 2D overlay to
	# align at all -- see test_laptop_screen_editor.gd for full
	# coverage of the new SubViewport-based editor).
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("precondition: editing", sleep_state.is_editing())
	# Reversed by a later round's explicit design: mouse-look is now
	# LOCKED while editing (see sleep_state.gd's begin_editing() and
	# test_editor_camera_lock.gd for the dedicated regression coverage).
	_check("current design: mouse-look is locked while editing", not look_pivot.input_enabled)

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
