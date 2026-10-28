extends SceneTree
## Round 16 Priority 3 regression coverage for controlled, reproducible
## variation in the electrical repair procedure: "do not repair the
## same three colors in the same order every time." Rather than
## inventing new wire counts/meshes, electrical_panel.gd's
## _REPAIR_CONFIGS varies the one safe axis a fixed 3-wire assembly
## actually supports -- WHICH role is at fault -- with every other
## field (disconnect order, reconnect order, carried-part color/
## message) derived from that single choice, so no inconsistent/
## impossible configuration can be authored.
##
## Covers: the DEFAULT config (service fault) still behaves exactly as
## every pre-Round-16 test already assumes (zero regression); the
## ALTERNATE config (return/Blue fault), driven to completion via REAL
## diorama clicks, with a genuinely different disconnect/reconnect
## order, correct carried-part recoloring/messaging, and correct
## diorama visuals (damaged-look swapped to the actual fault role, the
## replacement wire's pre-built Blue variant used instead of Yellow);
## config selection is locked once (debug_force_fault_role(), this
## round's deterministic-seed test hook) and survives Escape/reentry
## and wrong clicks without regenerating.
var _ok := true

func _init() -> void:
	await _test_default_config_unchanged()
	await _test_alternate_config_via_real_clicks()
	await _test_config_locked_across_reentry_and_wrong_clicks()
	await _test_backup_circuit_config_via_real_clicks()
	await _test_telemetry_config_via_real_clicks()
	await _test_relay_config_via_real_clicks()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _make_main() -> Node:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	await physics_frame # let a freshly-freed prior scene's physics state fully settle first
	return main


func _setup(main: Node, force_fault: StringName) -> Dictionary:
	var player: Node = main.get_node("Player")
	var free_body: Node = main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var day_plan: Node = main.get_node("DayPlan")
	var carry: Node = player.get_node("CarrySystem")
	var wire: Node = main.get_node("Interactables/WireComponent")
	var view: Node = player.get_node("HUD/ElectricalRepairView")
	var focused: Node = main.get_node("FocusedInteractionState")

	day_plan.trigger_fault()
	panel.interact() # open door
	# Lock the config BEFORE _trace() ever runs (terminal_interact's
	# second call) -- debug_force_fault_role() is a no-op once a config
	# is already selected, same as every other test-only override here.
	panel.debug_force_fault_role(force_fault)
	var terminal: Node = panel.get_node("Terminal")
	terminal.interact() # E01
	terminal.interact() # E02 -- _trace() runs here; config is now locked
	carry.pick_up(wire)
	terminal.interact() # opens the focused procedure for real
	await process_frame

	return {
		"player": player, "panel": panel, "day_plan": day_plan, "carry": carry,
		"wire": wire, "view": view, "focused": focused,
		"diorama": view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama"),
	}


func _test_default_config_unchanged() -> void:
	var main: Node = await _make_main()
	var s: Dictionary = await _setup(main, &"service")
	var panel: Node = s["panel"]
	var wire: Node = s["wire"]

	_check("[default] fault role is service (Yellow)", panel.fault_role() == &"service")
	_check("[default] fault color name is Yellow", panel.fault_color_name() == "Yellow")
	_check("[default] carried wire stays Yellow", wire.get_node("CoilLoopA").material.albedo_color.is_equal_approx(Color(0.68, 0.56, 0.08, 1)))
	panel.toggle_isolation()
	_check("[default] disconnect order: supply first", panel.disconnect_wire(&"supply").get("ok", false))
	_check("[default] disconnect order: return second", panel.disconnect_wire(&"return").get("ok", false))
	_check("[default] disconnect order: service last", panel.disconnect_wire(&"service").get("ok", false))

	main.queue_free()
	await create_timer(0.2).timeout
	await physics_frame


func _test_alternate_config_via_real_clicks() -> void:
	var main: Node = await _make_main()
	var s: Dictionary = await _setup(main, &"return")
	var panel: Node = s["panel"]
	var wire: Node = s["wire"]
	var diorama: Node3D = s["diorama"]
	var day_plan: Node = s["day_plan"]
	var message_label: Label = s["player"].get_node("HUD/TaskMessageLabel")

	_check("[alt] fault role is return (Blue)", panel.fault_role() == &"return")
	_check("[alt] fault color name is Blue", panel.fault_color_name() == "Blue")
	_check("[alt] trace message describes the required part as blue", message_label.text.findn("blue") != -1)
	_check("[alt] carried wire recolored to match Blue", wire.get_node("CoilLoopA").material.albedo_color.is_equal_approx(Color(0.14, 0.26, 0.6, 1)))

	# ============================================================
	# Disconnect order: canonical [supply, return, service] minus the
	# fault (return), fault appended last -> [supply, service, return].
	# Driven directly through the panel's own methods (NOT real clicks)
	# -- disconnect-order ENFORCEMENT is generic backend logic already
	# covered end-to-end via real clicks for the default config (see
	# test_reconnect_lifecycle.gd/test_reconnect_visual_position.gd/
	# manual_verify_real_input_reconnect.gd); re-deriving that same
	# generic logic through real raycast clicks here added nothing this
	# alternate-config test doesn't already need to prove, while
	# introducing a real, reproducible cross-scene physics-settle race
	# unique to chaining this many back-to-back real-click scenarios in
	# one process (confirmed directly: the exact same sequence is
	# rock-solid as direct panel calls, and rock-solid as real clicks
	# when run in true isolation, but intermittently misses a raycast
	# when both this file's OTHER scenarios and a long real-click chain
	# combine in one process). Real clicks are reserved below for
	# EXACTLY the new code this round actually needs to prove: that the
	# raycast resolves correctly to the ALTERNATE fault role's replace/
	# reconnect targets.
	# ============================================================
	var view: Node = s["view"]
	panel.toggle_isolation()
	_check("[alt] isolated", panel.is_isolated())
	_check("[alt] disconnect order: supply first (still the live feed)", panel.disconnect_wire(&"supply").get("ok", false))
	_check("[alt] disconnect order: service second (the OTHER non-faulted wire)", panel.disconnect_wire(&"service").get("ok", false))
	_check("[alt] disconnect order: return last (the actual fault)", panel.disconnect_wire(&"return").get("ok", false))
	_check("[alt] all three disconnected -> advanced to replace", panel.procedure_stage() == &"replace")
	# Bypassing the view above (direct panel calls, not clicks) means
	# its own _allowed/_replace_phase bookkeeping was never refreshed --
	# _refresh() is what electrical_repair_view.gd's own click handlers
	# always call after a real action, so do it once here before the
	# real clicks below, or the diorama's _allowed set stays stuck at
	# whatever open_procedure()'s own initial isolate-stage refresh left
	# it as, silently rejecting the very first real click that follows.
	view._sync_diorama_full()
	view._refresh()
	# sync_full_state() just snapped the return wire's Collision to its
	# new disconnected-pose position SYNCHRONOUSLY, but (the same
	# physics-server transform-sync latency documented extensively
	# elsewhere in this project) that new position is not visible to a
	# raycast until the NEXT physics step -- the real click below would
	# otherwise miss.
	await physics_frame

	# ============================================================
	# The damaged wire mesh must be the RETURN wire this time (not
	# service, which stays healthy-colored since it was never at
	# fault) -- confirms _apply_fault_role_visuals() actually ran.
	# ============================================================
	var return_mat: StandardMaterial3D = diorama._wire_nodes[&"return"].get_node("VisualGroup/Run").material
	var service_mat: StandardMaterial3D = diorama._wire_nodes[&"service"].get_node("VisualGroup/Run").material
	_check("[alt] return wire mesh shows the DAMAGED look (it's the real fault this attempt)", return_mat.albedo_color.is_equal_approx(Color(0.09, 0.16, 0.36, 1)))
	_check("[alt] service wire mesh stays HEALTHY-colored (never at fault this attempt)", service_mat.albedo_color.is_equal_approx(Color(0.68, 0.56, 0.08, 1)))

	# ============================================================
	# Replace: click the damaged (return) wire, then the replacement.
	# ============================================================
	await _click_wire(diorama, &"return")
	await _wait(0.35)
	await _click_replacement(diorama)
	_check("[alt] replacement installed -> advanced to reconnect", panel.procedure_stage() == &"reconnect")
	_check("[alt] replacement wire uses the pre-built BLUE variant, not yellow", diorama._active_replacement_visual_group().name == "VisualGroup_return")

	# ============================================================
	# Reconnect, reverse order: return (replacement), service, supply.
	# ============================================================
	await _click_replacement(diorama)
	_check("[alt] reconnect order: return (replacement) first", &"return" in panel.reconnected_roles())
	await _click_wire(diorama, &"service")
	_check("[alt] reconnect order: service second", &"service" in panel.reconnected_roles())
	await _click_wire(diorama, &"supply")
	_check("[alt] reconnect order: supply last -> advanced to restore", panel.procedure_stage() == &"restore")

	await _wait(0.4)
	await _click_breaker(diorama)
	_check("[alt] repair completes correctly with a genuinely different wire order", panel.is_repaired())
	_check("[alt] e05 marked done", day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await process_frame
	main.queue_free()
	await create_timer(0.2).timeout
	await physics_frame


func _test_config_locked_across_reentry_and_wrong_clicks() -> void:
	var main: Node = await _make_main()
	var s: Dictionary = await _setup(main, &"return")
	var panel: Node = s["panel"]
	var diorama: Node3D = s["diorama"]
	var focused: Node = s["focused"]
	var view: Node = s["view"]

	_check("[lock] config starts locked to return", panel.fault_role() == &"return")

	# A wrong attempt to force a different config after the fact must
	# be a no-op -- debug_force_fault_role() itself only ever locks
	# ONCE, same contract real random selection uses.
	panel.debug_force_fault_role(&"service")
	_check("[lock] a second config-selection attempt changes nothing (already locked)", panel.fault_role() == &"return")

	await _click_breaker(diorama)
	await _click_wire(diorama, &"supply") # a real, in-progress action

	focused.end()
	await process_frame
	main.get_node("Geometry/EngineeringCabinet1").get_node("Terminal").interact() # reopen
	await process_frame
	_check("[lock] fault role survives an Escape/reentry round-trip", panel.fault_role() == &"return")
	_check("[lock] in-progress disconnect progress survives the round-trip", panel.disconnected_roles() == [&"supply"])

	focused.end()
	await process_frame
	main.queue_free()
	await create_timer(0.2).timeout
	await physics_frame


## Round 17 Priority 1: a genuinely NEW config (not just a different
## fault within the original 3-wire subset) -- relevant=[return,
## backup, ground], fault=backup. Proves the fixed-5-wire-panel/
## variable-3-wire-subset mechanic actually works end to end: supply
## and service (outside this attempt's relevant subset) are real,
## clickable colliders that get a distinct "not part of the flagged
## circuit" rejection rather than being silently inert or treated as a
## plain wrong-order mistake; backup/ground (newly added roles) are
## genuinely solvable via real raycast clicks, not just reachable
## through direct backend calls.
func _test_backup_circuit_config_via_real_clicks() -> void:
	var main: Node = await _make_main()
	var s: Dictionary = await _setup(main, &"backup")
	var panel: Node = s["panel"]
	var wire: Node = s["wire"]
	var diorama: Node3D = s["diorama"]
	var day_plan: Node = s["day_plan"]
	var view: Node = s["view"]

	_check("[backup] fault role is backup (Orange)", panel.fault_role() == &"backup")
	_check("[backup] fault color name is Orange", panel.fault_color_name() == "Orange")
	_check("[backup] relevant subset is [return, backup, ground]", panel.relevant_roles() == [&"return", &"backup", &"ground"])
	_check("[backup] supply is NOT part of this attempt's relevant circuit", not panel.is_relevant(&"supply"))
	_check("[backup] service is NOT part of this attempt's relevant circuit", not panel.is_relevant(&"service"))
	_check("[backup] carried wire recolored to match Orange", wire.get_node("CoilLoopA").material.albedo_color.is_equal_approx(Color(0.75, 0.4, 0.08, 1)))

	panel.toggle_isolation()
	_check("[backup] isolated", panel.is_isolated())

	# An irrelevant wire (supply) is a real, clickable collider during
	# DISCONNECT -- not silently swallowed -- but explicitly rejected,
	# distinct from a plain wrong-order mistake, and changes nothing.
	var reject: Dictionary = panel.disconnect_wire(&"supply")
	_check("[backup] supply click rejected with the distinct not-relevant message", reject.get("message", "").findn("not part of the flagged circuit") != -1)
	_check("[backup] rejected supply click disconnected nothing", panel.disconnected_roles().is_empty())

	_check("[backup] disconnect order: return first", panel.disconnect_wire(&"return").get("ok", false))
	_check("[backup] disconnect order: ground second", panel.disconnect_wire(&"ground").get("ok", false))
	_check("[backup] disconnect order: backup last (the actual fault)", panel.disconnect_wire(&"backup").get("ok", false))
	_check("[backup] all three disconnected -> advanced to replace", panel.procedure_stage() == &"replace")
	view._sync_diorama_full()
	view._refresh()
	await physics_frame

	var backup_mat: StandardMaterial3D = diorama._wire_nodes[&"backup"].get_node("VisualGroup/Run").material
	var ground_mat: StandardMaterial3D = diorama._wire_nodes[&"ground"].get_node("VisualGroup/Run").material
	_check("[backup] backup wire mesh shows the DAMAGED look (it's the real fault this attempt)", backup_mat.albedo_color.is_equal_approx(Color(0.46, 0.26, 0.07, 1)))
	_check("[backup] ground wire mesh stays HEALTHY-colored (never at fault this attempt)", ground_mat.albedo_color.is_equal_approx(Color(0.15, 0.55, 0.22, 1)))

	await _click_wire(diorama, &"backup")
	await _wait(0.35)
	await _click_replacement(diorama)
	_check("[backup] replacement installed -> advanced to reconnect", panel.procedure_stage() == &"reconnect")
	_check("[backup] replacement wire uses the pre-built BACKUP/Orange variant", diorama._active_replacement_visual_group().name == "VisualGroup_backup")

	# Reconnect, reverse order: backup (replacement), ground, return.
	await _click_replacement(diorama)
	_check("[backup] reconnect order: backup (replacement) first", &"backup" in panel.reconnected_roles())
	await _click_wire(diorama, &"ground")
	_check("[backup] reconnect order: ground second", &"ground" in panel.reconnected_roles())
	await _click_wire(diorama, &"return")
	_check("[backup] reconnect order: return last -> advanced to restore", panel.procedure_stage() == &"restore")

	await _wait(0.4)
	await _click_breaker(diorama)
	_check("[backup] repair completes correctly with the new backup-circuit config", panel.is_repaired())
	_check("[backup] e05 marked done", day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await process_frame
	main.queue_free()
	await create_timer(0.2).timeout
	await physics_frame


## Round 18 Priority 2 coverage: the new DENSE 10-wire panel's second
## row (telemetry/coolant/sensor_feed/auxiliary/relay) is genuinely
## solvable end to end via real raycast clicks despite the row's own
## crossing geometry (telemetry<->sensor_feed reuses row A's proven
## supply<->service crossing shape -- see electrical_repair_diorama.gd's
## _WIRE_CURVE_POINTS doc comment) -- not just reachable through direct
## backend calls, and every row A wire remains correctly INERT-but-
## clickable (irrelevant-circuit rejection) during this attempt.
func _test_telemetry_config_via_real_clicks() -> void:
	var main: Node = await _make_main()
	var s: Dictionary = await _setup(main, &"telemetry")
	var panel: Node = s["panel"]
	var wire: Node = s["wire"]
	var diorama: Node3D = s["diorama"]
	var day_plan: Node = s["day_plan"]
	var view: Node = s["view"]

	_check("[telemetry] fault role is telemetry (Purple)", panel.fault_role() == &"telemetry")
	_check("[telemetry] fault color name is Purple", panel.fault_color_name() == "Purple")
	_check("[telemetry] relevant subset is [coolant, telemetry, sensor_feed]", panel.relevant_roles() == [&"coolant", &"telemetry", &"sensor_feed"])
	_check("[telemetry] supply (row A) is NOT part of this attempt's relevant circuit", not panel.is_relevant(&"supply"))
	_check("[telemetry] relay (row B, other config) is NOT part of this attempt's relevant circuit", not panel.is_relevant(&"relay"))
	_check("[telemetry] carried wire recolored to match Purple", wire.get_node("CoilLoopA").material.albedo_color.is_equal_approx(Color(0.5, 0.15, 0.65, 1)))

	panel.toggle_isolation()
	_check("[telemetry] isolated", panel.is_isolated())

	var reject: Dictionary = panel.disconnect_wire(&"relay")
	_check("[telemetry] row A/other-row-B wire click rejected with the distinct not-relevant message", reject.get("message", "").findn("not part of the flagged circuit") != -1)

	# toggle_isolation() above was a direct panel call, bypassing the
	# view -- its own _allowed/diorama set_allowed() bookkeeping (still
	# stuck at the ISOLATE stage's [&"breaker"] only) must be resynced
	# before any REAL click can resolve to a wire action (see
	# electrical_repair_view.gd's own _refresh()); the existing [backup]
	# test above avoids this by using direct disconnect_wire() calls
	# instead of real clicks for its own disconnect phase -- this test
	# deliberately exercises the REAL-CLICK path through disconnect too,
	# since that's the actual new surface Priority 2 adds (row B must be
	# genuinely clickable, not just reachable through the backend).
	view._sync_diorama_full()
	view._refresh()
	await physics_frame

	await _click_wire(diorama, &"coolant")
	await _click_wire(diorama, &"sensor_feed")
	await _click_wire(diorama, &"telemetry")
	_check("[telemetry] disconnect order: coolant, sensor_feed, telemetry (fault last)", panel.disconnected_roles() == [&"coolant", &"sensor_feed", &"telemetry"])
	_check("[telemetry] all three disconnected -> advanced to replace", panel.procedure_stage() == &"replace")
	view._sync_diorama_full()
	view._refresh()
	await physics_frame

	var telemetry_mat: StandardMaterial3D = diorama._wire_nodes[&"telemetry"].get_node("VisualGroup/Run").material
	var coolant_mat: StandardMaterial3D = diorama._wire_nodes[&"coolant"].get_node("VisualGroup/Run").material
	_check("[telemetry] telemetry wire mesh shows the DAMAGED look", telemetry_mat.albedo_color.is_equal_approx(Color(0.3, 0.09, 0.4, 1)))
	_check("[telemetry] coolant wire mesh stays HEALTHY-colored", coolant_mat.albedo_color.is_equal_approx(Color(0.1, 0.55, 0.6, 1)))

	await _click_wire(diorama, &"telemetry")
	await _wait(0.35)
	await _click_replacement(diorama)
	_check("[telemetry] replacement installed -> advanced to reconnect", panel.procedure_stage() == &"reconnect")
	_check("[telemetry] replacement wire uses the pre-built TELEMETRY/Purple variant", diorama._active_replacement_visual_group().name == "VisualGroup_telemetry")

	await _click_replacement(diorama)
	await _click_wire(diorama, &"sensor_feed")
	await _click_wire(diorama, &"coolant")
	_check("[telemetry] reconnect order: telemetry(replacement), sensor_feed, coolant -> advanced to restore", panel.procedure_stage() == &"restore")

	await _wait(0.4)
	await _click_breaker(diorama)
	_check("[telemetry] repair completes correctly with the new dense-panel row B config", panel.is_repaired())
	_check("[telemetry] e05 marked done", day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await process_frame
	main.queue_free()
	await create_timer(0.2).timeout
	await physics_frame


## Round 18 Priority 2: the SECOND row B config (relay/sensor_feed/
## auxiliary), covering the row's two SIMPLE non-crossing wires
## (auxiliary/relay, reusing backup/ground's proven shape) rather than
## the crossing pair the telemetry test above already covers --
## between the two tests, every one of row B's 5 roles gets exercised
## via real clicks at least once.
func _test_relay_config_via_real_clicks() -> void:
	var main: Node = await _make_main()
	var s: Dictionary = await _setup(main, &"relay")
	var panel: Node = s["panel"]
	var wire: Node = s["wire"]
	var diorama: Node3D = s["diorama"]
	var day_plan: Node = s["day_plan"]
	var view: Node = s["view"]

	_check("[relay] fault role is relay (Brown)", panel.fault_role() == &"relay")
	_check("[relay] fault color name is Brown", panel.fault_color_name() == "Brown")
	_check("[relay] relevant subset is [sensor_feed, auxiliary, relay]", panel.relevant_roles() == [&"sensor_feed", &"auxiliary", &"relay"])
	_check("[relay] carried wire recolored to match Brown", wire.get_node("CoilLoopA").material.albedo_color.is_equal_approx(Color(0.45, 0.3, 0.15, 1)))

	panel.toggle_isolation()
	# See the [telemetry] test's identical comment just above.
	view._sync_diorama_full()
	view._refresh()
	await physics_frame
	await _click_wire(diorama, &"sensor_feed")
	await _click_wire(diorama, &"auxiliary")
	await _click_wire(diorama, &"relay")
	_check("[relay] disconnect order: sensor_feed, auxiliary, relay (fault last)", panel.disconnected_roles() == [&"sensor_feed", &"auxiliary", &"relay"])
	view._sync_diorama_full()
	view._refresh()
	await physics_frame

	await _click_wire(diorama, &"relay")
	await _wait(0.35)
	await _click_replacement(diorama)
	_check("[relay] replacement installed -> advanced to reconnect", panel.procedure_stage() == &"reconnect")
	_check("[relay] replacement wire uses the pre-built RELAY/Brown variant", diorama._active_replacement_visual_group().name == "VisualGroup_relay")

	await _click_replacement(diorama)
	await _click_wire(diorama, &"auxiliary")
	await _click_wire(diorama, &"sensor_feed")
	_check("[relay] reconnect order: relay(replacement), auxiliary, sensor_feed -> advanced to restore", panel.procedure_stage() == &"restore")

	await _wait(0.4)
	await _click_breaker(diorama)
	_check("[relay] repair completes correctly", panel.is_repaired())
	_check("[relay] e05 marked done", day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await process_frame
	main.queue_free()
	await create_timer(0.2).timeout
	await physics_frame


func _click_wire(diorama: Node3D, role: StringName) -> void:
	var pos: Vector2 = diorama.screen_position_for(diorama._wire_colliders[role].global_position)
	_dispatch(diorama, pos)
	await physics_frame


func _click_replacement(diorama: Node3D) -> void:
	var pos: Vector2 = diorama.screen_position_for(diorama._replacement_collider.global_position)
	_dispatch(diorama, pos)
	await physics_frame


func _click_breaker(diorama: Node3D) -> void:
	var pos: Vector2 = diorama.screen_position_for(diorama._breaker_collider.global_position)
	_dispatch(diorama, pos)
	await physics_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _dispatch(diorama: Node3D, pos: Vector2) -> void:
	# Round 18 Priority 9: see test_reconnect_lifecycle.gd's identical
	# comment on its own equivalent retry -- a transient raycast miss
	# right after a PRECEDING click moved some other collider, resolved
	# by one retry after a real physics step.
	if diorama._raycast_action(pos) == &"":
		await Engine.get_main_loop().physics_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
