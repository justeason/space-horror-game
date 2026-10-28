extends SceneTree
## M7.2 Priority 2/3 dedicated regression: the daily log is rendered
## entirely on the laptop's physical SubViewport screen (no camera-
## space 2D overlay), typed keys are forwarded into that SubViewport
## via the real input pipeline (not a direct method call -- this goes
## through Input.parse_input_event() -> the engine's normal dispatch ->
## sleep_state.gd's _unhandled_input() -> laptop_view.gd ->
## SubViewport.push_input(), exactly as a real keypress would), and
## Esc/Ctrl+S work as the new editor shortcuts without disturbing
## mouse-look or triggering unrelated gameplay actions.

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
	var laptop := main.get_node("Interactables/BunksideLaptop")
	var log_screen := player.get_node("LaptopView/SessionLogScreen")
	var look_controller := player.get_node("LookPivot")

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
	await create_timer(0.6).timeout # let the editor zoom-in tween fully settle
	_check("precondition: editing", sleep_state.is_editing())

	# ============================================================
	# 1. THE LOG SCREEN IS A REAL SUBVIEWPORT whose texture is applied
	# to the laptop's screen material -- i.e. this is genuinely
	# rendered on the 3D object, not a 2D overlay layered on top of it.
	# ============================================================
	_check("log screen is a real SubViewport", log_screen is SubViewport)
	_check("laptop's screen material is wired to this exact SubViewport's texture", laptop.get("_screen_texture") == log_screen.get_feed_texture())

	# ============================================================
	# 2. TYPING VIA THE REAL INPUT PIPELINE: Input.parse_input_event()
	# -> engine dispatch -> sleep_state._unhandled_input() ->
	# laptop_view.forward_key_to_screen() -> SubViewport.push_input()
	# -> the focused TextEdit. Not calling any of those methods
	# directly -- this is the actual keypress path a real player's
	# keyboard would take.
	# ============================================================
	log_screen.show_entry("")
	for ch in "hello":
		_send_typed_key(_keycode_for(ch), ch.unicode_at(0))
	await create_timer(0.1).timeout
	_check("typed text reaches the laptop screen's field via the real input pipeline (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "hello")

	# Backspace works too (not just forward typing).
	_send_key(KEY_BACKSPACE)
	await create_timer(0.1).timeout
	_check("backspace works through the forwarded input path (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "hell")

	# ============================================================
	# 3. MOUSE-LOOK IS LOCKED WHILE EDITING (current design: the camera
	# must stay exactly on the screen until Esc/T; see sleep_state.gd's
	# begin_editing()) -- typing itself must not ALSO independently
	# toggle it one way or the other.
	# ============================================================
	_check("mouse-look is locked while editing (typing does not change that)", not look_controller.input_enabled)

	# ============================================================
	# 4. CTRL+S SAVES WITHOUT EXITING, and does not fall through to
	# any other system (e.g. does not move the player via the "S"
	# backward-walk key, and does not end editing).
	# ============================================================
	var pos_before_save: Vector3 = player.global_position
	_send_ctrl_s()
	await create_timer(0.1).timeout
	_check("Ctrl+S: still editing", sleep_state.is_editing())
	_check("Ctrl+S: did not move the player (S is also the walk-backward key)", player.global_position.distance_to(pos_before_save) < 0.01)

	# Get up, then come back and confirm Ctrl+S actually persisted.
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	await process_frame
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_check("Ctrl+S persisted the entry across getting up and lying back down", log_screen.get_entry_text() == "hell")

	# ============================================================
	# 5. ESC EXITS THE EDITOR back to LAPTOP without closing the
	# laptop, and does not accidentally invoke look_controller's own
	# Escape handling (mouse-visibility toggle) in a way that breaks
	# anything -- is_laptop_open() must still read true.
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("precondition: editing again", sleep_state.is_editing())
	_send_key(KEY_ESCAPE)
	await create_timer(0.1).timeout
	_check("Esc: exited editing", not sleep_state.is_editing())
	_check("Esc: laptop still open (viewing), not closed", sleep_state.is_laptop_open())
	_check("Esc: laptop lid still open", laptop.is_open)
	_check("Esc: mouse-look restored (unlocked) immediately", look_controller.input_enabled)

	# ============================================================
	# 6. GETTING UP STILL WORKS from LAPTOP-viewing after this whole
	# sequence (no stuck state left behind by the new editor controls).
	# ============================================================
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("get-up works cleanly after the Esc/Ctrl+S editor flow", not sleep_state.is_sitting())
	_check("laptop closed and returned to rest", not laptop.is_open and laptop.get_parent().name == "Interactables")

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _keycode_for(ch: String) -> int:
	return ch.to_upper().unicode_at(0)


func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _send_typed_key(keycode: int, unicode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.pressed = true
	Input.parse_input_event(ev)


func _send_ctrl_s() -> void:
	# See test_sleep_state_m7.gd's identical helper for why the release
	# matters: KEY_S doubles as the free-move "walk backward" key, and
	# Input.is_key_pressed() reflects Godot's global held-key state, not
	# just queued events.
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
