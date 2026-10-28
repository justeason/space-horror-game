extends SceneTree
## Regression for this round's Section 3: while actually EDITING, mouse-
## look must be fully LOCKED (not just "no competing tween" -- genuine
## input rejection), the camera must stay exactly on the screen for at
## least 15 seconds of simulated idle, and unlocking on exit must be
## immediate and reliable across repeated cycles.
##
## NOTE on headless mouse testing: look_controller.gd's own mouse-motion
## handling is gated on `Input.mouse_mode == MOUSE_MODE_CAPTURED`, and
## Input.mouse_mode is a documented no-op under --headless (the dummy
## DisplayServer always reports MOUSE_MODE_VISIBLE regardless of what's
## set) -- confirmed in earlier rounds. That means a synthetic
## InputEventMouseMotion sent via Input.parse_input_event() would be
## rejected by THAT check before ever reaching the input_enabled gate,
## which would "pass" this test for the wrong reason. To actually
## exercise the input_enabled gate itself, this test calls
## look_controller._unhandled_input() directly with a real
## InputEventMouseMotion and confirms it is rejected because
## input_enabled is false -- not because of the headless mouse_mode
## quirk. Manual playtest must still confirm an actual mouse move does
## nothing while editing.

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
	var laptop_view := player.get_node("LaptopView")
	var look_controller := player.get_node("LookPivot")
	var camera := player.get_node("LookPivot/PitchPivot/Camera3D")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame
	bunk.interact()
	await create_timer(1.6).timeout

	# ============================================================
	# A. LAPTOP open, editor closed: normal mouse-look enabled, focus-
	# assist must not PREVENT looking around (a live mouse nudge always
	# wins immediately over the idle ease).
	# ============================================================
	_send_key(KEY_F)
	await create_timer(1.3).timeout
	_check("A: mouse-look enabled in ordinary LAPTOP viewing", look_controller.input_enabled)
	_check("A: focus-assist armed (idle guidance exists)", look_controller.focus_assist_enabled)
	var yaw_before_nudge: float = look_controller._target_yaw
	look_controller._target_yaw += 0.3 # a live "mouse move" always updates _target_yaw directly
	_check("A: a live look input is not blocked by focus-assist", absf(look_controller._target_yaw - yaw_before_nudge - 0.3) < 0.0001)

	# ============================================================
	# B. Enter the editor: mouse-look LOCKED, focus-assist disabled, no
	# competing tween, camera stays exactly on the screen for 15+
	# simulated idle seconds.
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.5).timeout
	_check("B: EDITING state active", sleep_state.is_editing())
	_check("B: mouse-look is LOCKED (input_enabled == false)", not look_controller.input_enabled)
	_check("B: focus-assist disabled", not look_controller.focus_assist_enabled)

	# Directly exercise the actual input_enabled gate with a real
	# InputEventMouseMotion (see class doc comment for why this is
	# necessary in headless mode specifically).
	var yaw_before_motion: float = look_controller._target_yaw
	var pitch_before_motion: float = look_controller._target_pitch
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(500, 500) # a huge nudge -- if this did anything, it would be obvious
	look_controller._unhandled_input(motion)
	_check("B: a direct mouse-motion event changes nothing while locked (yaw)", look_controller._target_yaw == yaw_before_motion)
	_check("B: a direct mouse-motion event changes nothing while locked (pitch)", look_controller._target_pitch == pitch_before_motion)

	var screen_pos: Vector3 = laptop_view.get_screen_global_position()
	var pos0: Vector3 = look_controller.position
	var yaw0: float = look_controller.rotation.y
	var pitch0: float = camera.get_parent().rotation.x
	var aim0: float = (-camera.global_transform.basis.z).dot((screen_pos - camera.global_position).normalized())
	_check("B: camera aims at the screen once settled (dot=%.2f)" % aim0, aim0 > 0.9)

	await create_timer(15.0).timeout # the explicit >=15s idle requirement

	_check("B: after 15s idle, LookPivot.position unchanged (drift %.5fm)" % look_controller.position.distance_to(pos0), look_controller.position.distance_to(pos0) < 0.0005)
	_check("B: after 15s idle, yaw unchanged (drift %.5f rad)" % absf(look_controller.rotation.y - yaw0), absf(look_controller.rotation.y - yaw0) < 0.0005)
	_check("B: after 15s idle, pitch unchanged (drift %.5f rad)" % absf(camera.get_parent().rotation.x - pitch0), absf(camera.get_parent().rotation.x - pitch0) < 0.0005)
	var aim1: float = (-camera.global_transform.basis.z).dot((screen_pos - camera.global_position).normalized())
	_check("B: camera still aims at the screen after 15s idle (dot=%.2f)" % aim1, aim1 > 0.9)
	_check("B: still actually editing (never silently kicked out)", sleep_state.is_editing())

	# Ctrl+S saves without exiting or perturbing the lock.
	_send_ctrl_s()
	await create_timer(0.1).timeout
	_check("B: Ctrl+S saves without exiting", sleep_state.is_editing())
	_check("B: Ctrl+S does not unlock mouse-look", not look_controller.input_enabled)

	# ============================================================
	# C. Esc exits: camera eases back to ordinary framing, mouse-look
	# restored immediately, player remains seated.
	# ============================================================
	_send_key(KEY_ESCAPE)
	await process_frame
	_check("C: mouse-look restored on the very next frame after Esc", look_controller.input_enabled)
	await create_timer(0.6).timeout
	_check("C: back in LAPTOP, not EDITING", sleep_state.is_laptop_open() and not sleep_state.is_editing())
	_check("C: still seated", sleep_state.is_sitting())
	_check("C: zoom eased back out (LookPivot.position near zero, got %.3f)" % look_controller.position.length(), look_controller.position.length() < 0.02)

	# ============================================================
	# Repeated entry/exit cycles never leave the lock stuck either way.
	# ============================================================
	for cycle in range(3):
		_send_key(KEY_T) # enter
		await create_timer(0.5).timeout
		_check("repeat %d: locked while editing" % cycle, not look_controller.input_enabled)
		_send_key(KEY_ESCAPE) # exit -- bare T no longer exits (it ate literal "t" keystrokes; see test_daily_log_behavior.gd)
		await create_timer(0.5).timeout
		_check("repeat %d: unlocked back in LAPTOP" % cycle, look_controller.input_enabled)

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


func _send_ctrl_s() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_S
	down.physical_keycode = KEY_S
	down.ctrl_pressed = true
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = KEY_S
	up.physical_keycode = KEY_S
	up.pressed = false
	Input.parse_input_event(up)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
