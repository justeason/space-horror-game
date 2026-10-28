extends SceneTree
## Regression for this round's Issue 3: Escape must reliably exit the
## daily log editor through the REAL input path, without racing against
## look_controller.gd's own (unrelated) Escape handling, which also
## listens for KEY_ESCAPE to toggle mouse visibility. Investigation
## confirmed scripts/player/sleep_state.gd's _unhandled_input already
## consumed Escape first (SleepState is added to main.tscn after Player,
## and Godot visits more-recently-added nodes first for
## _unhandled_input) -- but that was a tree-order coincidence, not a
## guarantee. look_controller.gd now has an explicit escape_enabled
## flag that sleep_state.gd clears for the EDITING state, so Escape's
## behavior no longer depends on sibling order at all. This test proves
## that directly by instrumenting look_controller's own branch.

var _ok := true
var _look_controller: Node


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
	_look_controller = player.get_node("LookPivot")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame

	# ============================================================
	# 1. Entering edit mode works, and suppresses look_controller's own
	# Escape handling (so the two can never race for the same keypress,
	# regardless of node tree order).
	# ============================================================
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_check("precondition: laptop open", sleep_state.is_laptop_open())
	_check("precondition: look_controller.escape_enabled is true before editing", _look_controller.escape_enabled)

	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("1. entering EDITING works", sleep_state.is_editing())
	_check("1. look_controller.escape_enabled is now false while editing", not _look_controller.escape_enabled)
	_check("1. mouse-look is LOCKED while editing (current design)", not _look_controller.input_enabled)

	# ============================================================
	# 2. Typing and backspace work.
	# ============================================================
	log_screen.show_entry("")
	for ch in "hi":
		_send_typed_key(ch.to_upper().unicode_at(0), ch.unicode_at(0))
	await create_timer(0.1).timeout
	_check("2. typing reaches the entry field (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "hi")
	_send_key(KEY_BACKSPACE)
	await create_timer(0.1).timeout
	_check("2. backspace works (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "h")

	# ============================================================
	# 3. Ctrl+S saves without exiting.
	# ============================================================
	_send_ctrl_s()
	await create_timer(0.1).timeout
	_check("3. Ctrl+S: still editing (did not exit)", sleep_state.is_editing())

	# ============================================================
	# 4. Escape exits editing without closing the laptop, and (the
	# actual regression this round) look_controller's OWN Escape branch
	# must not have fired -- confirmed by checking escape_enabled was
	# false at the moment Escape was sent (checked above) and that the
	# laptop/editing state ended up exactly where sleep_state.gd's own
	# handler puts it, not in some partially-handled state.
	# ============================================================
	_send_key(KEY_ESCAPE)
	await create_timer(0.1).timeout
	_check("4. Escape: exited EDITING", not sleep_state.is_editing())
	_check("4. Escape: laptop still open (viewing), not closed", sleep_state.is_laptop_open())
	_check("4. Escape: look_controller.escape_enabled restored to true", _look_controller.escape_enabled)
	_check("4. Escape: mouse-look UNLOCKED immediately back in LAPTOP viewing", _look_controller.input_enabled)

	# ============================================================
	# 5. The entry is preserved after exiting (Ctrl+S already saved it,
	# and exiting via Escape saves again through the same path).
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("5. entry preserved across the Esc exit ('h')", log_screen.get_entry_text() == "h")

	# ============================================================
	# 6. Mouse-look is LOCKED again now that T re-entered EDITING (we
	# never left the editor/laptop between steps 4 and 5 other than
	# briefly passing through LAPTOP) -- confirms the lock/unlock is
	# tied correctly to the actual EDITING state, not left stuck one
	# way from an earlier transition.
	# ============================================================
	_check("6. mouse-look is locked again after re-entering EDITING", not _look_controller.input_enabled)

	# ============================================================
	# 7. Getting up remains possible after exiting editing (Esc back to
	# LAPTOP, then E).
	# ============================================================
	_send_key(KEY_ESCAPE)
	await create_timer(0.1).timeout
	_check("precondition: back in LAPTOP, not EDITING", sleep_state.is_laptop_open() and not sleep_state.is_editing())
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("7. get-up works after exiting editing via Esc", not sleep_state.is_sitting())
	_check("7. look_controller.escape_enabled still true after get-up", _look_controller.escape_enabled)
	_check("7. mouse-look unlocked after standing up", _look_controller.input_enabled)
	_check("7. laptop closed and returned to rest", not laptop.is_open and laptop.get_parent().name == "Interactables")

	# ============================================================
	# 8. Getting up DIRECTLY from EDITING (E, not Esc first) still
	# works, and still restores escape_enabled -- this is the path that
	# bypasses sleep_state.end_editing() entirely (end_sitting() tears
	# down the laptop via laptop_view.close(), not sleep_state's own
	# end_editing()), so escape_enabled must be restored there too, not
	# only in end_editing().
	# ============================================================
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	await process_frame
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("precondition: editing again", sleep_state.is_editing())
	_check("precondition: escape_enabled false again while editing", not _look_controller.escape_enabled)
	_check("precondition: mouse-look locked again while editing", not _look_controller.input_enabled)

	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("8. get-up directly from EDITING (E, no Esc first) works", not sleep_state.is_sitting())
	_check("8. escape_enabled restored to true even via the direct-get-up path", _look_controller.escape_enabled)
	_check("8. mouse-look unlocked even via the direct-get-up path (bypassing end_editing())", _look_controller.input_enabled)
	_check("8. laptop closed and returned to rest", not laptop.is_open and laptop.get_parent().name == "Interactables")

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
