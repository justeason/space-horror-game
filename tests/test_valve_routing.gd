extends SceneTree
## Round 15 Priority 2 regression coverage for the redesigned Coolant
## Loop Valve Routing manifold: a real 3D diorama (shared between the
## world prop and the focused view, exactly like the electrical
## repair's own world/focused diorama split) with physically rotating
## valve handles, instead of Round 14's flat 2D button schematic.
## Confirms: opening the station alone never completes the task; the
## fixed starting configuration genuinely requires work (drain starts
## open, the real path starts shut); clicking each valve HANDLE through
## the REAL diorama raycast dispatch path (not a direct state mutation)
## correctly toggles it; flow-state computation (no flow / leaking to
## drain / correct routing) matches the physical valve positions;
## completion only fires on the correct configuration; the world-view
## twin stays in sync with every toggle; and reopening after completion
## shows the done state immediately.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/ValveRoutingStation")
	var player := main.get_node("Player")
	var view := player.get_node("HUD/ValveRoutingView")
	var focused := main.get_node("FocusedInteractionState")
	var world_diorama := station.get_node("WorldDiorama")

	_check("l08 not done at start", not day_plan.is_task_done(&"l08"))
	_check("prompt invites routing before completion", station.get_interact_prompt().findn("Route") != -1)
	_check("V1 starts shut (real work required)", not station.is_valve_open(1))
	_check("V2 starts shut (real work required)", not station.is_valve_open(2))
	_check("V3/drain starts OPEN (the deliberate trap)", station.is_valve_open(3))

	# Round 16 Priority 5: force the deterministic STANDARD config (0)
	# -- this whole file assumes the fixed single-outlet/drain topology;
	# see tests/test_valve_routing_dual_outlet.gd for the alternate
	# DUAL_OUTLET (1) configuration.
	station.debug_force_config(0)
	station.interact()
	await process_frame
	_check("focused session active for the valve station", focused.is_active())
	_check("valve view visible", view.visible)
	_check("opening alone does not complete l08", not day_plan.is_task_done(&"l08"))

	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ValveRoutingDiorama")
	_check("diorama is active once the station opens", diorama._active)

	# ============================================================
	# Each valve is clicked through the REAL diorama raycast dispatch
	# path (_unhandled_input -> _raycast_valve -> valve_clicked signal
	# -> station.toggle_valve()), at the valve's real rendered screen
	# position -- not a direct state mutation.
	# ============================================================
	await _click(diorama, 1)
	_check("V1 opens via a real diorama click", station.is_valve_open(1))
	var flow_a: Dictionary = station.flow_state()
	_check("V1 open alone: v1_live true", flow_a["v1_live"])
	_check("V1 open alone: outlet NOT live (V2 still shut)", not flow_a["outlet_live"])
	_check("V1 open alone: drain IS leaking (V3 still open from the start)", flow_a["drain_live"])

	await _click(diorama, 3) # close the drain
	_check("V3 closes via a real diorama click", not station.is_valve_open(3))
	var flow_b: Dictionary = station.flow_state()
	_check("drain closed: no leak, no outlet flow yet", not flow_b["drain_live"] and not flow_b["outlet_live"])
	_check("l08 still not done (outlet not yet routed)", not day_plan.is_task_done(&"l08"))

	await _click(diorama, 2) # open the outlet path -- the correct complete configuration
	_check("V2 opens via a real diorama click", station.is_valve_open(2))
	var flow_c: Dictionary = station.flow_state()
	_check("correct routing: outlet live, drain sealed", flow_c["outlet_live"] and not flow_c["drain_live"])
	_check("l08 marked done once outlet flows and the drain is sealed", day_plan.is_task_done(&"l08"))

	# ============================================================
	# World-view twin must reflect the exact same valve state --
	# confirms the shared-diorama sync path (station._sync_world_diorama())
	# actually ran on every toggle, not just at open_station() time. The
	# world diorama snaps instantly (sync_full_state()); the focused one
	# TWEENS its handle over 0.3s (animate_valve()) -- wait for that
	# tween to settle first so this compares two RESTING poses, not a
	# transient mid-animation frame against an already-snapped one.
	# ============================================================
	await create_timer(0.4).timeout
	for id in [1, 2, 3]:
		_check("world diorama handle %d rotation matches focused handle %d rotation" % [id, id],
			is_equal_approx(world_diorama._valve_handle_roots[id].rotation.z, diorama._valve_handle_roots[id].rotation.z))

	# Re-clicking after completion must be a no-op.
	var before: Dictionary = station.open_state()
	await _click(diorama, 1)
	_check("clicking after completion changes nothing", station.open_state() == before)

	focused.end()
	await process_frame
	_check("prompt now reflects nominal status", station.get_interact_prompt().findn("Nominal") != -1)

	station.interact()
	await process_frame
	_check("reopening after completion shows the done state immediately", view._done)
	_check("l08 still done on reopen (not reset)", day_plan.is_task_done(&"l08"))
	focused.end()
	await process_frame

	main.queue_free()
	await process_frame

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Dispatches a REAL InputEventMouseButton through the diorama's actual
## _unhandled_input() -- the genuine production path -- at the valve's
## real rendered screen position (diorama.valve_screen_position()),
## followed by a physics_frame so the just-toggled handle's collider
## (if its rotation/position changed) is visible to the NEXT raycast,
## matching this project's established convention for clicks that
## immediately follow a collider-moving action (see
## test_reconnect_lifecycle.gd's identical pattern and reasoning).
func _click(diorama: Node3D, id: int) -> void:
	var pos: Vector2 = diorama.valve_screen_position(id)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)
	await physics_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
