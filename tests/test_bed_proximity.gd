extends SceneTree
## M7.1 Part 3 regression: the bunk's click/interact() and the new E-key
## path both require the player to actually be near the bed --
## clicking (or pressing E) from across the room must not start the
## lying-down transition. Also covers the near-bed prompt appearing/
## disappearing, and that unrelated interactables/navigation keep
## working (this is a per-interactable proximity check on the bunk
## specifically, not a station-wide interact_distance change).

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
	var prompt := player.get_node("HUD/PromptLabel")
	var switch_a := main.get_node("Interactables/ControlPanel/SwitchA")

	# ============================================================
	# 1. CLICKING THE BED FROM ACROSS THE ROOM must not start lying
	# down. "Across the room" = the far side of Living Quarters, well
	# outside bunk.gd's interact_range (1.3m) but still a position a
	# raycast could plausibly reach.
	# ============================================================
	# LivingDoor's own position -- a known-clear, walkable spot far from
	# the bunk at (5.0, 0.4, -0.5).
	var far_pos: Vector3 = main.get_node("MovementNodes/LivingDoor").global_position
	await _move_player(free_body, player, far_pos)
	_check("precondition: far position is actually outside interact_range", not bunk.is_player_near())
	bunk.interact()
	await create_timer(0.1).timeout
	_check("click from across the room does not start sitting down", not sleep_state.is_sitting())
	_check("prompt hidden while far from the bed", not prompt.visible)

	# ============================================================
	# 2. APPROACHING THE BED shows the prompt.
	# ============================================================
	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	await _move_player(free_body, player, near_pos)
	_check("precondition: near position is actually inside interact_range", bunk.is_player_near())
	_check("prompt appears when near the bed", prompt.visible and prompt.text.find("Sit Down") != -1)

	# ============================================================
	# 3. THE INTERACTION KEY (E) NEAR THE BED starts the normal
	# transition.
	# ============================================================
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	sleep_state._unhandled_input(ev)
	await create_timer(1.6).timeout
	_check("E key near the bed starts the sitting-down transition", sleep_state.is_sitting())
	var target: Vector3 = sleep_state.sit_position
	_check("the transition eased to the normal lie-down position", player.global_position.distance_to(target) < 0.05)

	# Get back up for the remaining checks.
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("precondition: awake again", not sleep_state.is_sitting())

	# ============================================================
	# 4. LEAVING THE INTERACTION RANGE hides the prompt.
	# ============================================================
	await _move_player(free_body, player, far_pos)
	_check("prompt hides again after leaving interact_range", not prompt.visible)

	# ============================================================
	# 5. CLICKING NEAR THE BED still works (the click path isn't
	# removed, just gated -- same as the key).
	# ============================================================
	await _move_player(free_body, player, near_pos)
	bunk.interact()
	await create_timer(1.6).timeout
	_check("clicking the bed while near it still starts sitting down", sleep_state.is_sitting())
	sleep_state.end_sitting()
	await create_timer(2.6).timeout

	# ============================================================
	# 6. UNRELATED INTERACTION/NAVIGATION IS UNCHANGED: the bed's new
	# proximity gate is specific to the bunk, not a station-wide
	# interact_distance change -- a Control Room switch (far from the
	# bed) must still be clickable without any proximity requirement
	# of its own.
	# ============================================================
	_check("unrelated interactable (ControlPanel switch) has no proximity gate of its own", switch_a.has_method("interact"))
	var state_before: bool = switch_a.is_on
	switch_a.interact()
	_check("unrelated interactable still responds to interact() normally", switch_a.is_on != state_before)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


## Moves both the free body (the real position source) and Player (so
## checks reading player.global_position see it immediately) -- and
## waits enough frames for bunk.gd's _process() to observe the change,
## matching the same pattern test_sleep_state.gd uses.
func _move_player(free_body: Node, player: Node, pos: Vector3) -> void:
	free_body.sync_to_eye_position(pos)
	player.global_position = pos
	for i in 3:
		await player.get_tree().process_frame


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
