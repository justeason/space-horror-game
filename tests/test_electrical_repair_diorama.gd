extends SceneTree
## Coverage for scripts/ui/electrical_repair_diorama.gd specifically --
## the raycast/hover mapping within its own isolated 3D world, the
## set_allowed() interactivity gate, hover-state reset when the allowed
## set changes (Phase 6's "hover state must reset when objects move,
## disconnect, reconnect, or disappear"), and sync_full_state() actually
## deriving every visual transform from the state it's given (not from
## whatever was on screen before).
##
## Mouse-driven clicking itself cannot be simulated through Godot's real
## OS/SubViewportContainer input pipeline in this headless environment
## (confirmed: SubViewport.push_input() with an InputEventMouseMotion/
## InputEventMouseButton does not reproduce the coordinate mapping a
## real SubViewportContainer delivers -- the viewport's own tracked
## mouse position does not update to match). screen_position_for() /
## _raycast_action()'s optional override exist specifically so this can
## still be tested deterministically: compute the exact screen position
## a real click at an object's location would use (via the camera's own
## unproject_position, the mathematical inverse of what a real click
## resolves through), then resolve it the same way _unhandled_input()
## would. This proves the ray-picking math itself is correct; the
## remaining, platform-level "does SubViewportContainer actually
## forward OS mouse events" question is a manual playtest item (see the
## final report).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var view := player.get_node("HUD/ElectricalRepairView")
	var diorama := view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama")

	# ============================================================
	# 1. Raycast resolves each interactable type to the correct action
	# key, and resolves to nothing where there is nothing clickable.
	# ============================================================
	diorama.set_allowed([&"wire:supply", &"wire:return", &"wire:service", &"wire:backup", &"wire:ground", &"replacement", &"breaker", &"screw:0", &"screw:1", &"screw:2", &"screw:3"])
	for role in [&"supply", &"return", &"service", &"backup", &"ground"]:
		var pos: Vector2 = diorama.screen_position_for(diorama._wire_colliders[role].global_position)
		_check("raycast hits wire:%s at its own screen position" % role, diorama._raycast_action(pos) == StringName("wire:%s" % role))

	var breaker_pos: Vector2 = diorama.screen_position_for(diorama._breaker_collider.global_position)
	_check("raycast hits breaker at its screen position", diorama._raycast_action(breaker_pos) == &"breaker")

	for i in 4:
		var screw_pos: Vector2 = diorama.screen_position_for(diorama._screw_colliders[i].global_position)
		_check("raycast hits screw:%d at its screen position" % i, diorama._raycast_action(screw_pos) == StringName("screw:%d" % i))

	var empty_pos := Vector2(-500, -500) # well outside any collider's projection
	_check("raycast misses entirely at an empty position", diorama._raycast_action(empty_pos) == &"")

	# ============================================================
	# 2. set_allowed() actually gates what resolves -- a real collider
	# under the cursor that is NOT in the allowed set must not resolve
	# to an action (this is what stops clicking the breaker during,
	# say, the Replace stage).
	# ============================================================
	diorama.set_allowed([&"wire:supply"])
	var return_pos: Vector2 = diorama.screen_position_for(diorama._wire_colliders[&"return"].global_position)
	_check("disallowed collider under the cursor does not resolve to an action", diorama._raycast_action(return_pos) == &"")
	_check("allowed collider under the cursor still resolves", diorama._raycast_action(diorama.screen_position_for(diorama._wire_colliders[&"supply"].global_position)) == &"wire:supply")

	# ============================================================
	# 3. Hover state resets when the allowed set changes out from under
	# a currently-hovered object (e.g. a stage transition) -- it must
	# not keep reporting a stale hover for something no longer valid.
	# ============================================================
	diorama.set_allowed([&"wire:supply", &"wire:return"])
	diorama._hovered_action = &"wire:return" # simulate "was hovering this"
	diorama.set_allowed([&"wire:supply"]) # stage changed; return is no longer offered
	_check("hover clears when the previously-hovered action is no longer allowed", diorama._hovered_action == &"")

	diorama.set_active(false)
	diorama._hovered_action = &"wire:supply"
	diorama.set_active(false) # already inactive -- must still clear, not error
	_check("set_active(false) clears hover", diorama._hovered_action == &"")

	# ============================================================
	# 4. sync_full_state() derives every wire's pose and every screw's
	# position purely from the arrays it's given -- re-opening after a
	# cancel must show the ACTUAL saved state, not whatever was left on
	# screen from a previous session.
	# ============================================================
	# ROUND 13: the connect/disconnect POSE lives on each wire's
	# "VisualGroup" child, not the wire's own root node -- the root
	# stays at identity rotation always, since it also parents the
	# (now permanently fixed, never-animated) Collision click target.
	# See electrical_repair_diorama.gd's _tween_wire_pitch() for why.
	diorama.sync_full_state(&"service", [&"supply"], [], false, true, [0, 0, 0, 0], 3)
	_check("sync: disconnected-only supply wire swings free", diorama._wire_nodes[&"supply"].get_node("VisualGroup").rotation.x != 0.0)
	_check("sync: untouched return wire stays connected (no rotation)", diorama._wire_nodes[&"return"].get_node("VisualGroup").rotation.x == 0.0)
	_check("sync: untouched service wire stays connected (no rotation)", diorama._wire_nodes[&"service"].get_node("VisualGroup").rotation.x == 0.0)
	_check("sync: replacement wire hidden before the service wire is replaced", not diorama._replacement_wire.visible)
	_check("sync: wire root nodes never rotate (Collision's fixed reference frame)", diorama._wire_nodes[&"supply"].rotation.x == 0.0)

	diorama.sync_full_state(&"service", [&"supply", &"return", &"service"], [&"service", &"return"], true, false, [3, 3, 3, 3], 3)
	_check("sync: service wire hidden once replaced", not diorama._wire_nodes[&"service"].visible)
	_check("sync: replacement wire shown once replaced", diorama._replacement_wire.visible)
	_check("sync: replacement wire connected once reconnected", diorama._replacement_wire.get_node("VisualGroup_service").rotation.x == 0.0)
	_check("sync: supply NOT YET reconnected still swings free (not in the reconnected list)", diorama._wire_nodes[&"supply"].get_node("VisualGroup").rotation.x != 0.0)
	_check("sync: all four screws fully backed out", diorama._screw_nodes[0].position.z > diorama._screw_base_z[0])
	_check("sync: replacement wire root never rotates either", diorama._replacement_wire.rotation.x == 0.0)

	diorama.sync_full_state(&"service", [], [], false, false, [0, 0, 0, 0], 3)
	_check("sync: screws fully seated again at base position", is_equal_approx(diorama._screw_nodes[0].position.z, diorama._screw_base_z[0]))
	_check("sync: a fresh (never-disconnected) state shows every wire connected", diorama._wire_nodes[&"supply"].get_node("VisualGroup").rotation.x == 0.0 and diorama._wire_nodes[&"return"].get_node("VisualGroup").rotation.x == 0.0)
	_check("sync: service wire visible again once service_replaced is false", diorama._wire_nodes[&"service"].visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
