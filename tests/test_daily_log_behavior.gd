extends SceneTree
## Investigation + regression for Section 2: "the daily log does not
## appear to do much -- is this intentional or broken?"
##
## Findings from reading the actual code (scripts/ui/session_log_screen.gd,
## scripts/player/laptop_view.gd, scenes/ui/session_log_screen.tscn) and
## grepping the ENTIRE scripts/ tree for any persistence mechanism
## (FileAccess, ConfigFile, user://, JSON -- none exist anywhere in this
## project):
##
## 1. The log is a single editable TextEdit (EntryField) on the laptop's
##    physical 3D screen. The "SampleLabel" text ("[SAMPLE DATA -- not
##    actual station records] Power: nominal...") is a SEPARATE, static,
##    non-editable decorative Label -- clearly marked as fake placeholder
##    flavor text, not the actual entry. This is NOT a bug: it is
##    explicitly labeled sample data in the scene itself.
## 2. Typing is forwarded via the real input pipeline into the TextEdit
##    (confirmed working in prior rounds' tests, re-confirmed here).
## 3. Ctrl+S calls laptop_view.gd's save_entry(), which copies the
##    TextEdit's current text into an in-memory String
##    (_saved_entry) -- but so does simply EXITING the editor
##    (end_editing() does the exact same copy). There is no "discard"
##    path at all: Ctrl+S's only actual benefit is letting you save
##    without interrupting typing; it is not functionally different
##    from just continuing to type and exiting later.
## 4. The entry DOES persist across closing/reopening the laptop and
##    across getting up and sitting back down, for the lifetime of the
##    CURRENT play session -- because _saved_entry lives on the
##    LaptopView node, which is never destroyed while playing.
## 5. The entry does NOT persist across an actual game restart --
##    confirmed here by loading a completely FRESH main.tscn instance
##    (a new scene tree, simulating what a restart would produce) and
##    checking the entry field is back to empty/placeholder. There is
##    no save-to-disk code anywhere in scripts/ (grepped for
##    FileAccess/ConfigFile/user:///JSON -- zero matches outside the
##    in-memory save_entry() method names themselves).
##
## CONCLUSION: this is NOT a bug. The code's own doc comments (sleep_
## state.gd's class comment: "the daily log is prototype/sample data
## only... no day/time or task-history/save-data system exists anywhere
## in this project yet") explicitly scope OUT cross-session persistence.
## Implementing disk-based save-game persistence would be ADDING new
## functionality beyond the documented design, not completing a
## documented gap -- so this task does not add it (see the final
## report for the explicit reasoning).

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
	var log_screen := player.get_node("LaptopView/SessionLogScreen")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3:
		await process_frame
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(1.3).timeout

	# ============================================================
	# 1. The field starts empty (not fabricated content) -- the visible
	# "sample data" text is a SEPARATE static label, not the entry.
	# ============================================================
	_check("1. entry field starts empty (no fabricated prior entries)", log_screen.get_entry_text() == "")

	# ============================================================
	# 2. Typing changes the entry, through the real input path.
	# ============================================================
	_send_key(KEY_T)
	await create_timer(0.5).timeout
	for ch in "Quiet shift.":
		var kc: int = ch.to_upper().unicode_at(0) if ch != " " else KEY_SPACE
		_send_typed_key(kc, ch.unicode_at(0))
	await create_timer(0.1).timeout
	_check("2. typing changes the entry (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "Quiet shift.")

	# ============================================================
	# 3. Ctrl+S saves without exiting (the entry is readable immediately
	# either way, since there is no discard path -- Ctrl+S's only real
	# effect is NOT exiting while still saving).
	# ============================================================
	_send_ctrl_s()
	await create_timer(0.1).timeout
	_check("3. Ctrl+S saves without exiting the editor", sleep_state.is_editing())

	# ============================================================
	# 4. The entry persists across closing and reopening the laptop
	# (same play session).
	# ============================================================
	_send_key(KEY_ESCAPE)
	await create_timer(0.6).timeout
	_send_key(KEY_F) # close
	await create_timer(0.5).timeout
	_send_key(KEY_F) # reopen
	await create_timer(1.3).timeout
	_check("4. entry persists across closing/reopening the laptop (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "Quiet shift.")

	# ============================================================
	# 5. The entry persists across getting up and sitting back down
	# (same play session).
	# ============================================================
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("precondition: standing again", not sleep_state.is_sitting())
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	await process_frame
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(1.3).timeout
	_check("5. entry persists across getting up and sitting back down (got '%s')" % log_screen.get_entry_text(), log_screen.get_entry_text() == "Quiet shift.")

	sleep_state.end_sitting()
	await create_timer(2.6).timeout

	# ============================================================
	# 6. The entry does NOT persist across a simulated restart -- a
	# completely fresh scene tree (no shared state with the one above)
	# shows an empty field. This is the ACTUAL CURRENT behavior, not a
	# guess -- and matches the complete absence of any
	# FileAccess/ConfigFile/user:///JSON persistence code anywhere in
	# scripts/ (grepped, zero matches).
	# ============================================================
	var main2: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main2)
	for i in 5:
		await process_frame
	var log_screen2 := main2.get_node("Player/LaptopView/SessionLogScreen")
	_check("6. a fresh scene tree (simulated restart) shows an EMPTY entry, confirming no disk persistence exists", log_screen2.get_entry_text() == "")

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
