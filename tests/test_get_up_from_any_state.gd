extends SceneTree
## M7.1 Part 4 regression: getting up (E) now works from SITTING, LAPTOP,
## and EDITING alike -- the laptop no longer has to be manually closed
## first. Covers all three starting states, that the laptop is always
## folded shut and returned to its resting spot (never left floating
## at the lap position), that an in-progress log entry is saved rather
## than silently discarded, and that the camera/mouse/editor state is
## left fully consistent afterward in every case.

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
	var player_body := player.get_node("PlayerBody")
	var standing_pose := player_body.get_node("StandingPose")
	var sitting_pose := player_body.get_node("SittingPose")
	var log_screen := player.get_node("LaptopView/SessionLogScreen")
	var look_controller := player.get_node("LookPivot")
	var camera := player.get_node("LookPivot/PitchPivot/Camera3D")
	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)

	# ============================================================
	# CASE 1: get up from plain SITTING (the original, already-working
	# path -- confirms this round's changes didn't regress it).
	# ============================================================
	_move(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	_check("case SITTING: lying down succeeded", sleep_state.is_sitting())
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("case SITTING: get-up succeeds", not sleep_state.is_sitting())
	_check("case SITTING: standing pose restored", standing_pose.visible and not sitting_pose.visible)
	_check("case SITTING: free body reactivated", free_body.active)
	_check("case SITTING: interactions re-enabled", camera.interactions_enabled)
	_check("case SITTING: laptop still resting (was never opened)", laptop.get_parent().name == "Interactables")

	# ============================================================
	# CASE 2: get up directly from LAPTOP (open, not editing) -- must
	# not require closing it first.
	# ============================================================
	_move(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_check("case LAPTOP: laptop is open", sleep_state.is_laptop_open() and not sleep_state.is_editing())
	_check("case LAPTOP: laptop lid is open", laptop.is_open)

	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("case LAPTOP: get-up succeeds without closing the laptop first", not sleep_state.is_sitting())
	_check("case LAPTOP: laptop lid folded shut", not laptop.is_open)
	_check("case LAPTOP: laptop returned to its resting parent, not left floating at the lap", laptop.get_parent().name == "Interactables")
	_check("case LAPTOP: laptop restored to its original resting transform", laptop.position.is_equal_approx(Vector3(5.36, 0.605, 0.0)))
	_check("case LAPTOP: standing pose restored", standing_pose.visible and not sitting_pose.visible)
	_check("case LAPTOP: free body reactivated", free_body.active)
	_check("case LAPTOP: laptop state fully closed (no longer open or editing)", not sleep_state.is_laptop_open() and not sleep_state.is_editing())

	# ============================================================
	# CASE 3: get up from EDITING, with an unsaved entry in progress --
	# must save it (not discard it), close the editor, fold the
	# laptop, and leave input/camera state consistent.
	# ============================================================
	_move(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("case EDITING: editing started", sleep_state.is_editing())

	log_screen.show_entry("Unsaved note written just before getting up.")
	await create_timer(0.1).timeout

	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("case EDITING: get-up succeeds directly from EDITING", not sleep_state.is_sitting())
	_check("case EDITING: laptop lid folded shut", not laptop.is_open)
	_check("case EDITING: laptop returned to its resting spot", laptop.get_parent().name == "Interactables")
	_check("case EDITING: no longer editing or laptop-open", not sleep_state.is_laptop_open() and not sleep_state.is_editing())
	_check("case EDITING: standing pose restored", standing_pose.visible and not sitting_pose.visible)
	_check("case EDITING: free body reactivated, movement restored", free_body.active)
	_check("case EDITING: interactions re-enabled", camera.interactions_enabled)
	_check("case EDITING: look input left enabled (not stuck suspended)", look_controller.input_enabled)
	_check("case EDITING: focus-assist left disabled (not stuck armed while standing)", not look_controller.focus_assist_enabled)

	# Confirm the entry was actually SAVED, not discarded: reopen and
	# check the 3D screen / re-entering the editor shows it.
	_move(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	_send_key(KEY_F)
	await create_timer(0.6).timeout
	_send_key(KEY_T)
	await create_timer(0.1).timeout
	_check("case EDITING: the unsaved entry was preserved across get-up/lie-down-again, not discarded", log_screen.get_entry_text() == "Unsaved note written just before getting up.")

	# Clean up.
	sleep_state.end_sitting()
	await create_timer(2.6).timeout

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


func _move(free_body: Node, player: Node, pos: Vector3) -> void:
	free_body.sync_to_eye_position(pos)
	player.global_position = pos
	for i in 3:
		await player.get_tree().process_frame


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
