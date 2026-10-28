extends SceneTree
## Regression for the reported "editor camera zooms back out and turns
## ~180 degrees toward the player's body shortly after entering
## EDITING." Two independent, confirmed root causes, both exercised
## here through the REAL input path (F/T keys via Input.parse_input_event,
## not direct function calls), with realistic idle time simulated via
## real timers rather than asserted on state variables alone:
##
## 1. look_controller.gd's idle focus-assist (focus_assist_enabled)
##    was left TRUE throughout LAPTOP and EDITING, still targeting the
##    LAP ANCHOR (ordinary-viewing target), not the screen. Since
##    pressing T itself involves no mouse movement, the idle timer
##    (already counting from LAPTOP) crossed its 1.2s threshold almost
##    immediately and started overriding the editor's own
##    _target_yaw/_target_pitch every frame, dragging the view away
##    from the screen. Fixed: begin_editing() disables it;
##    end_editing() re-arms it (for ordinary LAPTOP viewing) with a
##    fresh idle countdown.
## 2. scripts/player/movement_controller.gd's head-bob system wrote to
##    LookPivot.position.y UNCONDITIONALLY every frame -- including its
##    "settle back to 0" branch -- even though node-based movement
##    (the only thing that ever drove bobbing) has been permanently
##    disabled station-wide by GlobalFreeMove. This fought the editor
##    zoom's own LookPivot.position tween, silently eroding its Y
##    component back toward 0 every frame once the tween finished
##    (confirmed via the exact matching exponential-decay rate). Fixed
##    by gating the whole method on node_movement_enabled, consistent
##    with every other node-movement entry point in that script.

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
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_send_key(KEY_T)
	await create_timer(0.5).timeout # editor_zoom_duration (0.45) has settled

	_check("1. EDITING: focus_assist_enabled is OFF while editing (no competing idle authority)", not look_controller.focus_assist_enabled)

	var screen_pos: Vector3 = laptop_view.get_screen_global_position()
	var forward0: Vector3 = -camera.global_transform.basis.z
	var aim0: float = forward0.dot((screen_pos - camera.global_position).normalized())
	_check("2. right after the zoom settles, camera aims at the screen (dot=%.2f, want > 0.9)" % aim0, aim0 > 0.9)

	var pos_after_settle: Vector3 = look_controller.position
	var yaw_after_settle: float = look_controller.rotation.y
	var pitch_after_settle: float = camera.get_parent().rotation.x

	# ============================================================
	# THE ACTUAL REGRESSION: stay idle (no mouse motion, no keys)
	# for well past the old 1.2s focus-assist threshold, through
	# several real seconds -- long enough for either bug to have
	# visibly dragged the camera away if either were still present.
	# ============================================================
	await create_timer(3.0).timeout

	_check("3. NO REVERSAL: LookPivot.position is still exactly where the zoom left it (drifted %.5fm)" % look_controller.position.distance_to(pos_after_settle), look_controller.position.distance_to(pos_after_settle) < 0.0005)
	_check("4. NO REVERSAL: yaw unchanged after 3s idle (drifted %.5f rad)" % absf(look_controller.rotation.y - yaw_after_settle), absf(look_controller.rotation.y - yaw_after_settle) < 0.0005)
	_check("5. NO REVERSAL: pitch unchanged after 3s idle (drifted %.5f rad)" % absf(camera.get_parent().rotation.x - pitch_after_settle), absf(camera.get_parent().rotation.x - pitch_after_settle) < 0.0005)

	var forward1: Vector3 = -camera.global_transform.basis.z
	var aim1: float = forward1.dot((screen_pos - camera.global_position).normalized())
	_check("6. camera still aims at the screen after 3s idle (dot=%.2f, want > 0.9; was %.2f)" % [aim1, aim0], aim1 > 0.9)
	_check("7. still actually editing (never silently kicked back to LAPTOP)", sleep_state.is_editing())

	# ============================================================
	# CTRL+S saves without exiting, and does not itself perturb the
	# camera.
	# ============================================================
	_send_ctrl_s()
	await create_timer(0.1).timeout
	_check("8. Ctrl+S: still editing", sleep_state.is_editing())
	_check("8. Ctrl+S: camera still stable", look_controller.position.distance_to(pos_after_settle) < 0.0005)

	# ============================================================
	# ESC exits cleanly: eases back to ordinary LAPTOP framing,
	# re-arms focus-assist with a FRESH idle countdown (not an
	# instantly-stale one), and never snaps/rotates unexpectedly.
	# ============================================================
	_send_key(KEY_ESCAPE)
	await process_frame
	# Checked on the very next frame, before any further waiting -- the
	# idle countdown naturally accumulates real elapsed time once
	# re-armed, so this has to be read immediately after end_editing()
	# runs, not after a subsequent wait (which would of course show
	# that much idle time having passed -- correct behavior, not a bug).
	_check("9. Esc: focus-assist idle countdown was reset fresh (got %.3f, want < 0.1)" % look_controller._focus_idle_time, look_controller._focus_idle_time < 0.1)
	await create_timer(0.6).timeout
	_check("9. Esc: back in LAPTOP, not EDITING", sleep_state.is_laptop_open() and not sleep_state.is_editing())
	_check("9. Esc: zoom eased back out (LookPivot.position back near zero, got %.3f)" % look_controller.position.length(), look_controller.position.length() < 0.02)
	_check("9. Esc: focus_assist re-armed for ordinary LAPTOP viewing", look_controller.focus_assist_enabled)
	_check("9. Esc: still seated", sleep_state.is_sitting())

	# ============================================================
	# Repeated enter/exit cycles stay reliable.
	# ============================================================
	for cycle in range(3):
		_send_key(KEY_T) # enter
		await create_timer(0.5).timeout
		_check("repeat %d: editing, focus_assist off" % cycle, sleep_state.is_editing() and not look_controller.focus_assist_enabled)
		_send_key(KEY_ESCAPE) # exit -- bare T no longer exits (it ate literal "t" keystrokes; see test_daily_log_behavior.gd)
		await create_timer(0.5).timeout
		_check("repeat %d: back to LAPTOP, focus_assist on" % cycle, sleep_state.is_laptop_open() and not sleep_state.is_editing() and look_controller.focus_assist_enabled)

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
