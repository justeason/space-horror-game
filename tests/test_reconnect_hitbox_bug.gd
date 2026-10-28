extends SceneTree
## Round 11 Workstream B1 regression coverage for the reported bug:
## "During Stage 4 reconnect, I clicked the wires in reverse order, but
## after a wrong-order click it told me to reconnect yellow first, and
## I could no longer click yellow."
##
## Drives clicks through the REAL raycast/hover resolution path
## (diorama._raycast_action(), via screen_position_for() -- see
## test_electrical_repair_diorama.gd's own class doc comment for why
## this is necessary and sufficient in this headless environment),
## not direct _on_wire_clicked() backend calls -- the previous test
## suite only ever did the latter, which is exactly why it never
## caught this: the backend dispatch handlers are each individually
## correct, but the ALLOWED-ACTION LIST and the diorama's own role ->
## collider mapping disagreed about which collider represents the
## service/yellow wire once it has been replaced.
##
## ROOT CAUSE (confirmed by reading the code, not assumed): once
## install_replacement_wire() commits, the diorama hides the ORIGINAL
## "Service" wire node and shows "ReplacementWire" instead (confirmed
## in sync_full_state()/begin_replace_sequence()) -- so the real,
## visible, clickable collider for the service role is
## `_replacement_collider` (action &"replacement"), not
## `_wire_colliders[&"service"]` (action &"wire:service", now pointing
## at an invisible node). electrical_repair_view.gd's
## _update_allowed() for the RECONNECT stage listed &"wire:service" in
## its allowed set and never &"replacement" -- so a real click on the
## visibly-yellow wire resolved to an action that was never in
## `_allowed`, and _raycast_action() returned "" (nothing). Separately,
## even if it had been allowed, clicking the replacement collider
## dispatches the `replacement_clicked` signal, routed to
## _on_replacement_clicked(), which only ever handled the REPLACE-stage
## install click and returned early for every other stage -- so the
## click would still have done nothing.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var day_plan: Node = main.get_node("DayPlan")
	var carry: Node = player.get_node("CarrySystem")
	var wire: Node = main.get_node("Interactables/WireComponent")
	var view: Node = player.get_node("HUD/ElectricalRepairView")
	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama")
	var free_body: Node = main.get_node("FreeMoveBody")
	free_body.set_active(false)

	# ---- Standard setup through to the start of RECONNECT, driven via
	# real diorama clicks the whole way so this exercises the actual
	# allowed-list/dispatch path end to end, not a shortcut. ----
	day_plan.trigger_fault()
	panel.interact() # open door
	# Round 16 Priority 3: force the deterministic default config -- this
	# file hardcodes the fixed supply/return/service order (see
	# tests/test_electrical_wire_randomization.gd for the alternate one).
	panel.debug_force_fault_role(&"service")
	var terminal: Node = panel.get_node("Terminal")
	terminal.interact() # E01
	terminal.interact() # E02
	carry.pick_up(wire)
	terminal.interact() # opens the focused procedure for real
	await process_frame

	await _click(diorama, diorama._breaker_collider) # isolate
	await _click(diorama, diorama._wire_colliders[&"supply"])
	await _click(diorama, diorama._wire_colliders[&"return"])
	await _click(diorama, diorama._wire_colliders[&"service"])
	_check("all three disconnected via real raycast clicks", panel.disconnected_roles() == [&"supply", &"return", &"service"])

	await _click(diorama, diorama._wire_colliders[&"service"]) # click damaged wire to begin replace
	await create_timer(0.4).timeout # begin_replace_sequence()'s tween
	await _click(diorama, diorama._replacement_collider) # install the replacement
	_check("replacement installed via real raycast clicks", wire.is_installed())
	_check("now in the reconnect stage", panel.procedure_stage() == &"reconnect")

	# ============================================================
	# THE ACTUAL REPORTED SEQUENCE: a wrong-order click first (clicking
	# supply/red when yellow/service is actually required first), then
	# attempting to click the visibly-yellow wire -- which must now
	# succeed, not silently do nothing.
	# ============================================================
	var before_reconnected: Array = panel.reconnected_roles()
	await _click(diorama, diorama._wire_colliders[&"supply"]) # wrong order -- supply is not allowed at all during reconnect
	_check("a disallowed wrong click changes nothing", panel.reconnected_roles() == before_reconnected)

	var yellow_action: StringName = diorama._raycast_action(diorama.screen_position_for(diorama._replacement_collider.global_position))
	_check("the visibly-yellow (replacement) wire resolves to a real, allowed action during reconnect -- THE ACTUAL BUG", yellow_action != &"")

	await _click(diorama, diorama._replacement_collider)
	_check("clicking the visibly-yellow wire during reconnect actually reconnects service (the fix)", &"service" in panel.reconnected_roles())

	# ---- Finish the procedure normally to confirm nothing else broke. ----
	await _click(diorama, diorama._wire_colliders[&"return"])
	await _click(diorama, diorama._wire_colliders[&"supply"])
	_check("reconnected in the correct reverse order", panel.reconnected_roles() == [&"service", &"return", &"supply"])
	await create_timer(0.4).timeout # let the supply-wire reconnect swing tween settle before raycasting the breaker
	await _click(diorama, diorama._breaker_collider) # restore power
	_check("repair completes correctly after the fix", panel.is_repaired())
	_check("e05 marked done", day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await create_timer(0.3).timeout

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Resolves the real screen position for `collider`'s own location and
## drives it through the exact same path a real click would take
## (_raycast_action() -> _dispatch_click()), rather than calling a
## backend/view handler function directly -- see class doc comment for
## why that distinction is the entire point of this test file.
func _click(diorama: Node3D, collider: Node3D) -> void:
	var pos: Vector2 = diorama.screen_position_for(collider.global_position)
	var action: StringName = diorama._raycast_action(pos)
	if action != &"":
		diorama._dispatch_click(action)
	# Round 14: a wire's Collision body can move (see
	# electrical_repair_diorama.gd's _snap_collision_to_pose()) as a
	# direct result of the click just dispatched above. Godot's physics
	# server does not make a StaticBody3D's new transform visible to
	# intersect_ray() until its next physics step -- confirmed directly
	# via diagnostic, independent of this test's own logic -- so the
	# NEXT _click() call's raycast needs one physics_frame to have
	# passed first, exactly as any real player's click already would
	# (two separate completed mouse clicks are never truly zero-frames
	# apart). This does not reintroduce the original hover-cache bug:
	# that fix lives in _unhandled_input() always raycasting fresh at
	# its own event position, unaffected by how much time elapses
	# between separate clicks.
	await physics_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
