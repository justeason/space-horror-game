extends SceneTree
## Regression coverage for the shared bottom-center contextual prompt
## (HUD/PromptLabel), now driven every frame by
## scripts/player/interaction_controller.gd while the player is free to
## roam: hover-based prompts for the wire/panel/workstation, the
## existing proximity-based bed prompt, hiding when out of range or
## looking away, and clearing while an exclusive sequence (seated at the
## workstation) owns the camera.
var _ok := true
var _player: Node3D
var _free_body: Node

const GameSettings = preload("res://scripts/station/game_settings.gd")

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty() # isolate from any stray persisted difficulty
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	_player = main.get_node("Player")
	_free_body = main.get_node("FreeMoveBody")
	# This test only ever teleports the player for precise hover-prompt
	# checks -- it never needs real WASD movement simulation. Leaving
	# the body physically active let gravity/collision response drift
	# it a few cm away from the exact spot _place() set once enough
	# real frames had elapsed (most visible later in this test, after
	# the bed section), which was enough to make the camera's raycast
	# miss a small target like the wire. Same self-intersection concern
	# documented on free_move_controller.gd's set_active() and already
	# worked around the same way in test_control_room_workstation.gd.
	_free_body.set_active(false)
	var carry := _player.get_node("CarrySystem")
	var look_pivot := _player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var prompt_label := _player.get_node("HUD/PromptLabel")
	var wire := main.get_node("Interactables/WireComponent")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var bunk := main.get_node("Interactables/Bunk")

	# Player spawns with rotation.y = PI (the station's MovementNode
	# "facing" convention -- see e.g. ControlRoomRearLeft's transform).
	# Zero it so _aim_at()'s plain atan2/asin yaw math (which assumes no
	# parent yaw to compose with, same convention test_control_room_workstation.gd
	# uses) is correct for the rest of this test.
	_player.rotation.y = 0.0

	# ============================================================
	# 1. Nothing hovered, far from everything: prompt hidden.
	# ============================================================
	_place(Vector3(0.0, 1.6, -3.0))
	look_pivot.rotation.y = 0.0
	pitch_pivot.rotation.x = 0.0
	for i in 3: await process_frame
	_check("baseline: prompt hidden with nothing in range/sight", not prompt_label.visible)

	# ============================================================
	# 2. Bed proximity prompt (not a raycast target -- proximity only).
	# ============================================================
	_place(Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z))
	look_pivot.rotation.y = PI # face away from the bed -- proximity, not sight, drives this one
	for i in 3: await process_frame
	_check("near bed (looking away): prompt shows Sit Down", prompt_label.text == "E: Sit Down")
	_check("near bed: prompt visible", prompt_label.visible)

	_place(Vector3(0.0, 1.6, -3.0))
	for i in 3: await process_frame
	_check("walked away from bed: prompt clears", not prompt_label.visible)

	# ============================================================
	# 3. Wire component: hover prompt appears, disappears once carried.
	# ============================================================
	var wire_eye: Vector3 = wire.global_position + Vector3(0.3, 1.6 - wire.global_position.y, 0.3)
	_place(wire_eye)
	await _aim_at(look_pivot, pitch_pivot, wire_eye, wire.global_position)
	_check("looking at wire: pick-up prompt shown", prompt_label.text == "Click: Pick Up Wire Component")

	wire.interact()
	await process_frame
	_check("wire picked up", carry.is_carrying())
	await _aim_at(look_pivot, pitch_pivot, wire_eye, wire.global_position)
	_check("wire gone from its resting spot: no stale pick-up prompt", prompt_label.text != "Click: Pick Up Wire Component")

	# ============================================================
	# 4. Electrical panel: cabinet click only opens/closes the door;
	# the inspect/trace/install prompts now live on the separate
	# Terminal collider (reachable only once the door is open).
	# ============================================================
	# Looking at the panel while carrying the wire: the prompt also
	# carries the drop hint ("Space: Drop <item>",
	# interaction_controller.gd's _update_prompt()) appended after the
	# hovered object's own prompt, same multi-action-on-one-line
	# convention sleep_state.gd already uses. (Space replaced G as the
	# pickup/drop key -- see carry_system.gd's class doc comment.)
	var drop_suffix := "    Space: Drop %s" % carry.carried_item_display_name()
	var panel_eye: Vector3 = panel.global_position + Vector3(0.4, 1.6 - panel.global_position.y, 0.4)
	_place(panel_eye)
	await _aim_at(look_pivot, pitch_pivot, panel_eye, panel.global_position)
	_check("panel CLOSED: open prompt shown on the cabinet itself", prompt_label.text == "Click: Open Panel" + drop_suffix)

	panel.interact() # open the door (door toggle only, no task progress)
	var terminal := panel.get_node("Terminal")
	await _aim_at(look_pivot, pitch_pivot, panel_eye, terminal.global_position)
	_check("door open, terminal targeted: inspect prompt shown", prompt_label.text == "Click: Inspect Electrical Panel (Terminal T-2)" + drop_suffix)

	# Round 16 Priority 3: force the deterministic default config -- this
	# file hardcodes the fixed supply/return/service order further below
	# (see tests/test_electrical_wire_randomization.gd for the alternate
	# one).
	panel.debug_force_fault_role(&"service")
	panel.terminal_interact(&"damaged") # E01 inspect
	await _aim_at(look_pivot, pitch_pivot, panel_eye, terminal.global_position)
	_check("terminal INSPECTED: trace prompt shown", prompt_label.text == "Click: Trace Circuit (Terminal T-2)" + drop_suffix)

	panel.terminal_interact(&"damaged") # E02 trace
	await _aim_at(look_pivot, pitch_pivot, panel_eye, terminal.global_position)
	_check("terminal TRACED, carrying correct wire: begin-procedure prompt shown", prompt_label.text == "Click: Begin Repair Procedure (Terminal T-2)" + drop_suffix)

	# This terminal click now opens the focused multi-stage repair
	# procedure (scripts/ui/electrical_repair_view.gd) instead of
	# installing immediately -- drive it directly through the panel's
	# own methods (same technique test_electrical_panel_chain.gd and
	# test_slice_b_e2e.gd already use) to reach REPAIRED, then confirm
	# the prompt/carry state this test has always checked for.
	panel.terminal_interact(&"damaged")
	_check("terminal click opened the procedure", panel.procedure_stage() == &"isolate")
	panel.toggle_isolation()
	panel.disconnect_wire(&"supply")
	panel.disconnect_wire(&"return")
	panel.disconnect_wire(&"service")
	panel.install_replacement_wire()
	panel.reconnect_wire(&"service")
	panel.reconnect_wire(&"return")
	panel.reconnect_wire(&"supply")
	panel.restore_power()
	# Close the real focused session the terminal click above opened --
	# see electrical_panel.gd's _open_procedure() -- now that the
	# procedure is complete, same as pressing Enter/Escape, so
	# interactions_enabled is restored before this test continues on to
	# the workstation-prompt checks below. end() unconditionally
	# re-activates FreeMoveBody (correct for real gameplay -- the
	# player regains normal free movement) but this test positions the
	# player by writing global_position directly and relies on
	# FreeMoveBody staying inactive (see _free_body.set_active(false)
	# near the top) for the rest of its checks, so re-disable it right
	# back -- otherwise real physics (gravity/wall depenetration) can
	# nudge the player a few centimeters off the exact aim point before
	# the next check, which is what was actually happening here.
	main.get_node("FocusedInteractionState").end()
	_free_body.set_active(false)
	await _aim_at(look_pivot, pitch_pivot, panel_eye, terminal.global_position)
	_check("terminal REPAIRED: nominal prompt shown", prompt_label.text == "Click: Check Panel (Nominal)")
	_check("wire no longer carried (installed, not freed)", not carry.is_carrying())
	_check("installed wire still exists, just no longer carried", is_instance_valid(wire) and wire.is_installed())

	# ============================================================
	# 5. Workstation: near prompt shown while standing, hidden while
	# seated (an exclusive sequence owns the camera/prompt then).
	# ============================================================
	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	_place(console_pos)
	await _aim_at(look_pivot, pitch_pivot, console_pos, console.get_screen_global_position())
	_check("near workstation, standing: Use Workstation prompt shown", prompt_label.text == "Click: Use Workstation")

	console.interact()
	await create_timer(1.0).timeout
	_check("seated at workstation: in use", wstate.is_in_use())
	_check("seated at workstation: prompt cleared (screen owns the view now)", not prompt_label.visible)

	wstate.end_use()
	await create_timer(1.3).timeout
	_check("stood back up: no longer in use", not wstate.is_in_use())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Moves the player via the real authority (FreeMoveBody) rather than
## just the mirrored Player node -- global_free_move.gd re-syncs
## Player.global_position FROM the free body every frame, so setting
## Player.global_position alone gets silently overwritten the next frame.
func _place(eye_pos: Vector3) -> void:
	_free_body.sync_to_eye_position(eye_pos)
	_free_body.velocity = Vector3.ZERO
	_player.global_position = eye_pos


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
	# A CollisionShape3D.disabled toggle (e.g. terminal_connector.gd's
	# set_reachable(), flipped synchronously by panel.interact()/
	# terminal_interact() just before this is called) only reaches the
	# physics server on the next physics step, not the next idle/
	# process frame -- those can run out of lockstep in headless mode.
	# Without this, the raycast fired by interaction_controller.gd's
	# own _process() can intermittently observe the terminal's OLD
	# (disabled) collision state immediately after the door opens,
	# producing a flaky false failure unrelated to any real bug.
	await physics_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
