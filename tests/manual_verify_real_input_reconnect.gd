extends SceneTree
## NOT part of tests/run_tests.sh -- this script requires a REAL
## rendering context (e.g. `godot --path . --write-movie out.png
## --quit-after 90 --script tests/manual_verify_real_input_reconnect.gd`)
## and does NOT work under plain `--headless` (confirmed directly: a
## top-level push_input() click silently fails to reach anything when
## run headless, but correctly reaches the diorama's own
## _unhandled_input() when run with real rendering -- Godot's
## SubViewportContainer GUI-input forwarding appears to require an
## actual rendering context to function). This is the documented
## "closest available end-to-end integration" the Round 15 brief asked
## for: genuine InputEventMouseMotion/MouseButton events pushed at
## get_root(), in TOP-LEVEL screen coordinates, exercising the REAL
## SubViewportContainer forwarding path -- the one layer every other
## test in this suite deliberately bypasses (see
## test_reconnect_visual_position.gd's own class doc comment for why
## that bypass exists and what it does/doesn't prove).
##
## Round 15 Priority 0 finding from this exact script: the very first
## run surfaced a GENUINE bug (unrelated to collider tracking) --
## electrical_repair_diorama.tscn's three terminal indicator lights AND
## the breaker status light all shared ONE StandardMaterial3D resource
## (`Mat_light_on`), so updating any one light's color visually changed
## ALL FOUR. Fixed by giving each light its own material
## (Mat_light_on_return/_service/_breaker). This script is kept as a
## permanent, reusable artifact specifically because it was the ONLY
## method that caught that bug -- every headless-compatible test
## computes expected click positions analytically and never actually
## renders+reads back pixel-level/material state the way a human
## playtester would notice.

var _step := 0

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame

	var player := main.get_node("Player")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var day_plan: Node = main.get_node("DayPlan")
	var carry: Node = player.get_node("CarrySystem")
	var wire: Node = main.get_node("Interactables/WireComponent")
	var view: Node = player.get_node("HUD/ElectricalRepairView")
	var container: SubViewportContainer = view.get_node("Panel/VBox/DioramaContainer")
	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama")

	day_plan.trigger_fault()
	panel.interact()
	# Round 16 Priority 3: force the deterministic default config -- this
	# script's whole point is proving the fixed Yellow-then-Blue report,
	# so it must not be derailed by a randomly-picked alternate fault.
	panel.debug_force_fault_role(&"service")
	var terminal: Node = panel.get_node("Terminal")
	terminal.interact()
	terminal.interact()
	carry.pick_up(wire)
	terminal.interact()
	for i in 5: await process_frame

	await _click(diorama, container, diorama._breaker_collider.global_position)
	await _click(diorama, container, diorama._wire_colliders[&"supply"].global_position)
	await _click(diorama, container, diorama._wire_colliders[&"return"].global_position)
	await _click(diorama, container, diorama._wire_colliders[&"service"].global_position)
	print("disconnected=", panel.disconnected_roles())

	await _click(diorama, container, diorama._wire_colliders[&"service"].global_position) # begin replace
	await create_timer(0.4).timeout
	await _click(diorama, container, diorama._replacement_wire.get_node("VisualGroup_service/Cap").global_position) # install
	print("procedure_stage=", panel.procedure_stage())

	print("=== THE REPORTED SEQUENCE, via genuine top-level forwarded clicks ===")
	await _click(diorama, container, diorama._replacement_wire.get_node("VisualGroup_service/Cap").global_position) # Yellow
	print("[AFTER YELLOW] reconnected=", panel.reconnected_roles(), " yellow indicator ON=", _is_on(diorama, &"service"))

	await _click(diorama, container, diorama._wire_nodes[&"return"].get_node("VisualGroup/Cap").global_position) # Blue, immediately after
	print("[AFTER BLUE] reconnected=", panel.reconnected_roles(), " blue indicator ON=", _is_on(diorama, &"return"))

	if panel.reconnected_roles() == [&"service", &"return"] and _is_on(diorama, &"service") and _is_on(diorama, &"return"):
		print(">>>> PASS: real top-level forwarded clicks correctly reconnect Blue immediately after Yellow, both indicators correctly ON. <<<<")
	else:
		print("!!!! FAIL: real top-level forwarded reconnect sequence did not behave as expected. !!!!")

	await _click(diorama, container, diorama._wire_nodes[&"supply"].get_node("VisualGroup/Cap").global_position) # Red
	await create_timer(0.4).timeout
	await _click(diorama, container, diorama._breaker_collider.global_position) # restore power
	print("is_repaired=", panel.is_repaired(), " e05 done=", day_plan.is_task_done(&"e05"))

	quit()


func _is_on(diorama: Node3D, role: StringName) -> bool:
	var mat: StandardMaterial3D = diorama._terminal_indicators[role].material
	return mat.emission.is_equal_approx(diorama.LIGHT_ON_COLOR)


func _click(diorama: Node3D, container: SubViewportContainer, world_pos: Vector3) -> void:
	_step += 1
	var local_pos: Vector2 = diorama.screen_position_for(world_pos)
	var viewport_size: Vector2 = Vector2(diorama.get_viewport().size)
	var scale: Vector2 = container.size / viewport_size
	var top_level_pos: Vector2 = container.global_position + local_pos * scale
	var motion := InputEventMouseMotion.new()
	motion.position = top_level_pos
	get_root().push_input(motion)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = top_level_pos
	get_root().push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = top_level_pos
	get_root().push_input(up)
	await process_frame
