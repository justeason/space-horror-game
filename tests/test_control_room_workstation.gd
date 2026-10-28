extends SceneTree
## M7 Part D validation: the new Control Room workstation dressing
## (console backing/trim/shelf/kickplate, relocated ToggleSwitch,
## operator stool) does not block interaction raycasts to any of the
## real interactables, does not add new collision (verified directly,
## not just inferred), and the underlying gameplay logic (ControlPanel
## task verification, SurveillanceConsole camera cycling) still works
## exactly as before now that the pieces have been repositioned.

var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5:
		await process_frame

	var toggle_switch := main.get_node("Interactables/ToggleSwitch")
	var control_panel := main.get_node("Interactables/ControlPanel")
	var switch_a := control_panel.get_node("SwitchA")
	var switch_b := control_panel.get_node("SwitchB")
	var console := main.get_node("Interactables/SurveillanceConsole")
	var watch_window := main.get_node("Interactables/WallWatchWindow")

	# ============================================================
	# 0. NEW DRESSING HAS NO COLLISION (spot check every new node).
	# ============================================================
	var new_node_names := [
		"ConsoleDesk", "ConsoleDeskEdge", "ConsoleDeskBacking",
		"ConsoleDeskBackingTrim", "ConsoleDeskKickplate", "ConsoleConduitA",
		"ConsoleConduitB", "OperatorStoolPost", "OperatorStoolSeat",
	]
	var any_collision := false
	for n in new_node_names:
		var node := main.get_node("Geometry/" + n)
		if node == null:
			print("FAIL: node Geometry/%s exists" % n)
			_ok = false
			continue
		if node.use_collision:
			any_collision = true
			print("FAIL: Geometry/%s unexpectedly has use_collision=true" % n)
			_ok = false
	_check("new console dressing: none of the %d new pieces added collision" % new_node_names.size(), not any_collision)

	# ============================================================
	# 1. PRE-EXISTING LINTEL UNTOUCHED (regression guard for the
	# earlier .tscn-comment parsing bug this pass discovered and fixed:
	# a `#`-comment block between [node] entries silently corrupted the
	# NEXT node's properties).
	# ============================================================
	var lintel := main.get_node("Geometry/ControlRoomDoorwayLintel")
	_check("ControlRoomDoorwayLintel size unaffected by nearby edits (got %s)" % lintel.size, lintel.size.is_equal_approx(Vector3(1.2, 0.8, 0.2)))

	# ============================================================
	# 2. RAYCAST FROM A REALISTIC OPERATOR POSITION (standing at the
	# stool) reaches every real interactable, unobstructed by the new
	# backing/trim/shelf geometry.
	# ============================================================
	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	var look_pivot := player.get_node("LookPivot")
	var pitch_pivot := look_pivot.get_node("PitchPivot")
	var camera := pitch_pivot.get_node("Camera3D")

	# Stand roughly where the operator stool is, at eye height, facing
	# the back-wall desk (M7.1: console relocated so the south doorway
	# is behind the seated operator). Disable the real FreeMoveBody's
	# collision for this synthetic raycast check -- same pattern as
	# test_whole_station_capsule.gd -- since placing the ray's own
	# origin at the player's eye point would otherwise make it
	# intermittently self-intersect the capsule's own collision
	# (flaky depending on exact floating-point margins at the ray's
	# start), which has nothing to do with what this test is actually
	# checking (whether the new console geometry blocks line of sight).
	free_body.set_active(false)
	player.global_position = Vector3(0.0, 1.6, -0.35)
	player.global_rotation = Vector3.ZERO
	await process_frame

	# Direct line-of-sight check (origin -> target collider), independent
	# of the camera-rotation reconstruction used elsewhere in this suite
	# -- that reconstruction (atan2/asin -> rotation -> re-derive the ray
	# from basis.z) introduces its own floating-point rounding on top of
	# the thing actually being tested, which made this specific check
	# flake on tightly-grazing geometry even when the real line of sight
	# was clean every time (verified separately: a fixed-point
	# intersect_ray from the same two points hit the correct collider in
	# 20/20 trials). Checking line-of-sight directly is both simpler and
	# a more faithful test of "is anything new blocking this."
	var space_state := main.get_viewport().world_3d.direct_space_state
	var eye: Vector3 = player.global_position
	for target in [["ToggleSwitch", toggle_switch], ["ControlPanel SwitchA", switch_a], ["ControlPanel SwitchB", switch_b]]:
		var label: String = target[0]
		var node: Node = target[1]
		var query := PhysicsRayQueryParameters3D.create(eye, node.global_position)
		var result := space_state.intersect_ray(query)
		_check("line of sight from operator position reaches %s unobstructed" % label, result.get("collider") == node)

	# SurveillanceConsole (Control Room Workstation Revamp): deliberately
	# hidden and non-collidable now -- its camera-selection STATE is
	# still the one source of truth the new workstation screen reads
	# from (see scripts/ui/workstation_screen.gd), but the standalone
	# physical monitor itself is intentionally no longer a separate,
	# independently-clickable piece of hardware (it was stacking
	# visually with the new workstation console). A line-of-sight hit is
	# therefore no longer the right expectation; confirm the deliberate
	# hidden/non-collidable state instead.
	_check("SurveillanceConsole is deliberately hidden now (repurposed as logic-only backend)", not console.visible)
	var console_collision := console.get_node("Collision")
	_check("SurveillanceConsole collision deliberately disabled", console_collision.disabled)

	# ============================================================
	# 3. WALL WATCH WINDOW stays separate, still non-interactive.
	# ============================================================
	_check("WallWatchWindow still has no interact()", not watch_window.has_method("interact"))
	_check("WallWatchWindow unchanged position", watch_window.global_position.is_equal_approx(Vector3(-1.2, 1.5, 1.4)))

	# ============================================================
	# 4. FUNCTIONAL PRESERVATION: ControlPanel's task-verification
	# logic still evaluates correctly after being physically
	# repositioned (nothing about its switch_a/switch_b wiring changed).
	# ============================================================
	switch_a.is_on = false
	switch_b.is_on = false
	switch_a._apply_state()
	switch_b._apply_state()
	control_panel._evaluate()
	_check("control panel: wrong config (A off) is NOT flagged correct", not control_panel._is_configuration_correct())

	switch_a.is_on = true
	switch_b.is_on = false
	switch_a._apply_state()
	switch_b._apply_state()
	control_panel._evaluate()
	_check("control panel: correct config (A on, B off) still evaluates correct after relocation", control_panel._is_configuration_correct())

	# ============================================================
	# 5. FUNCTIONAL PRESERVATION: SurveillanceConsole still cycles all
	# 3 cameras after relocation.
	# ============================================================
	var seen_ids := {}
	for i in 3:
		console.interact()
		seen_ids[String(console._cameras[console._selected_index].camera_id)] = true
	_check("surveillance console still cycles through all 3 cameras after relocation", seen_ids.size() == 3)

	print("")
	if _ok:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()


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


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
