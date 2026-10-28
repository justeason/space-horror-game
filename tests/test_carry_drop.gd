extends SceneTree
## Regression coverage for the unified Space pickup/drop action
## (scripts/player/carry_system.gd's _unhandled_input(), wired to the
## Space key and surfaced via interaction_controller.gd's prompt) --
## this round replaced the previous G-drop-only key with Space for
## BOTH halves (empty-handed picks up whatever's hovered, if it's a
## valid carryable item; carrying something drops it at the player's
## feet), per direct player feedback asking for Space instead of G.
var _ok := true
var _player: Node3D
var _free_body: Node

## Moves the player via the real authority (FreeMoveBody) rather than
## just the mirrored Player node -- global_free_move.gd re-syncs
## Player.global_position FROM the free body every frame, so setting
## Player.global_position alone gets silently overwritten the next frame.
func _place(eye_pos: Vector3) -> void:
	_free_body.sync_to_eye_position(eye_pos)
	_free_body.velocity = Vector3.ZERO
	_player.global_position = eye_pos

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var carry := player.get_node("CarrySystem")
	_free_body = free_body
	_player = player
	var wire := main.get_node("Interactables/WireComponent")
	var prompt_label := player.get_node("HUD/PromptLabel")
	var wstate := main.get_node("WorkstationState")
	var console := main.get_node("Interactables/WorkstationConsole")
	var dp := main.get_node("DayPlan")
	var look_pivot := player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var cam := pitch_pivot.get_node("Camera3D")

	# Player.rotation.y is a fixed, never-updated baked value from scene
	# load (see movement_controller.gd's own class doc comment) -- zero
	# it once, same as test_interaction_prompts.gd already does, so
	# _aim_at()'s plain atan2/asin yaw math (which assumes no parent
	# rotation already in the chain) resolves to the correct world
	# direction for every aim in this file.
	player.rotation.y = 0.0

	# ============================================================
	# 0. Space picks up whatever is actually hovered/targeted -- the
	# SAME object interaction_controller.gd's own raycast resolves,
	# not a second independent one. Aim at the wire first.
	# ============================================================
	var original_resting_transform: Transform3D = wire.transform
	var wire_eye: Vector3 = wire.global_position + Vector3(0.3, 1.6 - wire.global_position.y, 0.3)
	_place(wire_eye)
	await _aim_at(look_pivot, pitch_pivot, wire_eye, wire.global_position)
	_check("wire is actually hovered before pressing Space", cam.get_hovered() == wire)
	_check("not carrying yet", not carry.is_carrying())
	_send_key(KEY_SPACE)
	await process_frame
	_check("Space picks up the hovered item", carry.is_carrying())
	_check("picked up the correct item", carry.carried_item_id() == &"wire_control_16ga")

	# ============================================================
	# 1. Pressing Space again while carrying must drop it (not re-pick-
	# up or duplicate it) -- confirms the SAME key cleanly does both
	# halves. Moved to the open Control Room floor first: Storage's own
	# resting spot is tight enough that a drop attempt right there can
	# legitimately find "no safe floor nearby" (see check 6 below, which
	# deliberately exercises that same protection) and this check's
	# intent is to verify Space's pickup/drop toggle, not clearance at
	# that specific shelf.
	# ============================================================
	# Control Room floor spans x:[-1.4,1.4] z:[-1.2,2.2] -- stand well
	# inside it (not the void used elsewhere as an "away from
	# everything" raycast baseline, which has no floor at all).
	var player_start: Vector3 = Vector3(0.0, 1.6, 0.5)
	_place(player_start)
	look_pivot.rotation.y = 0.0
	await process_frame

	_send_key(KEY_SPACE)
	await process_frame
	_check("pressing Space again while carrying drops it (not a stuck pickup)", not carry.is_carrying())
	wire.interact() # pick back up directly for the remaining checks
	_check("picked back up for the remaining checks", carry.is_carrying())
	_send_key(KEY_SPACE)
	await process_frame
	_check("Space key drops the carried item", not carry.is_carrying())

	var wire_count := 0
	for child in main.get_node("Interactables").get_children():
		if child == wire or (child.has_method("get_display_name") and child.get_display_name() == "Wire Component"):
			wire_count += 1
	_check("exactly one wire exists after drop (no duplication)", wire_count == 1)
	_check("dropped wire did not snap back to its original Storage transform", not wire.transform.is_equal_approx(original_resting_transform))
	_check("dropped wire landed near the player, not far away", wire.global_position.distance_to(player_start) < 2.0)

	# ============================================================
	# 2. Pick the dropped item back up again -- this time via Space,
	# aimed at wherever it actually landed.
	# ============================================================
	var dropped_eye: Vector3 = wire.global_position + Vector3(0.3, 1.6 - wire.global_position.y, 0.3)
	_place(dropped_eye)
	await _aim_at(look_pivot, pitch_pivot, dropped_eye, wire.global_position)
	_send_key(KEY_SPACE)
	await process_frame
	_check("dropped wire can be picked back up via Space", carry.is_carrying())
	_check("picking it back up gives the same item id", carry.carried_item_id() == &"wire_control_16ga")

	# ============================================================
	# 3. Task/day-plan state untouched by a plain drop (not a
	# task-consuming action).
	# ============================================================
	_check("dropping/re-picking up did not touch c02", not dp.is_task_done(&"c02"))
	_check("dropping/re-picking up did not touch e05", not dp.is_task_done(&"e05"))

	# ============================================================
	# 4. Drop prompt text and visibility while carrying.
	# ============================================================
	# A few extra frames for the hover/prompt cache to settle after the
	# reposition-then-pickup above (consistent with this test suite's
	# established pattern elsewhere of allowing settle frames after a
	# teleport+interaction in quick succession).
	for i in 5: await process_frame
	_check("prompt mentions the drop key while carrying", prompt_label.text.find("Space: Drop") != -1)

	# ============================================================
	# 5. Dropping is inert while seated at the workstation (exclusive
	# state) -- reuses interaction_controller.gd's interactions_enabled,
	# the same signal workstation_state.gd/sleep_state.gd already drive.
	# ============================================================
	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	_place(console_pos)
	console.interact()
	await create_timer(1.0).timeout
	_check("seated at workstation", wstate.is_in_use())
	_send_key(KEY_SPACE)
	await process_frame
	_check("Space does nothing while seated (still carrying)", carry.is_carrying())
	wstate.end_use()
	await create_timer(1.3).timeout
	free_body.set_active(false)

	# ============================================================
	# 6. Dropping with no safe floor nearby: keeps the item, no crash,
	# no duplication -- face straight down into the player's own
	# capsule / a known-tight spot. Using a location far off any mapped
	# floor (deep into unmapped void) guarantees no floor hit.
	# ============================================================
	_place(Vector3(50.0, 1.6, 50.0))
	await process_frame
	_send_key(KEY_SPACE)
	await process_frame
	_check("no safe floor found: item is NOT lost (still carrying)", carry.is_carrying())
	var total_wires := 0
	for n in [main.get_node("Interactables"), player.get_node("PlayerBody/CarryAnchor")]:
		for child in n.get_children():
			if child.has_method("get_display_name"):
				total_wires += 1
	_check("no safe floor found: no duplicate wire exists (count=%d)" % total_wires, total_wires == 1)

	# ============================================================
	# 7. Space is a no-op (not an error, not a crash) when empty-handed
	# and nothing valid is hovered.
	# ============================================================
	carry.drop() # back to its resting spot, hands empty, for this check
	_place(Vector3(50.0, 1.6, 50.0)) # looking at nothing
	await process_frame
	_check("nothing hovered before the no-op check", cam.get_hovered() == null)
	_send_key(KEY_SPACE)
	await process_frame
	_check("Space with nothing hovered is a harmless no-op", not carry.is_carrying())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

## Same yaw/pitch-from-direction convention test_interaction_prompts.gd
## and others already use.
func _aim_at(look_pivot: Node3D, pitch_pivot: Node3D, from_pos: Vector3, to_pos: Vector3) -> void:
	var dir: Vector3 = (to_pos - from_pos).normalized()
	var desired_yaw := atan2(-dir.x, -dir.z)
	var desired_pitch := asin(clampf(dir.y, -1.0, 1.0))
	look_pivot.rotation.y = desired_yaw
	look_pivot._target_yaw = desired_yaw
	pitch_pivot.rotation.x = desired_pitch
	look_pivot._target_pitch = desired_pitch
	for i in 3:
		await process_frame

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
