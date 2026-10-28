extends SceneTree
## Round 16 Priority 5 regression coverage for the ALTERNATE Coolant
## Loop Valve Routing configuration (DUAL_OUTLET, config index 1): same
## three valves/pipes as the STANDARD config (test_valve_routing.gd),
## but V3 is a genuine second outlet rather than a drain, and
## completion requires V2 (the primary outlet) to have been opened
## before V3 (the secondary) -- "a pressure-loss problem requiring
## careful valve sequencing," not just a different arrangement of
## identical button clicks. Covers: the config is genuinely different
## (both branches must end up live, not one sealed); opening V3 before
## V2 is harmless/recoverable but does NOT by itself complete the task
## even once both branches are live; a warning is surfaced for that
## out-of-order attempt; correcting the order (close V3, open V2 first,
## reopen V3) does complete it; the diorama shows BOTH branches as live/
## teal (never the leak/red tint this config doesn't use); and the
## DRAIN label is swapped to "OUTLET B" in both the 3D label and the
## schematic text.
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

	station.debug_force_config(1) # DUAL_OUTLET
	_check("config is dual-outlet", station.is_dual_outlet())
	_check("branch3 is NOT a leak in this config", not station.branch3_is_leak())
	_check("drain label reads OUTLET B", station.drain_label_text() == "OUTLET B")

	station.interact()
	await process_frame
	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/ValveRoutingDiorama")
	_check("3D drain label swapped to OUTLET B", diorama.get_node("Labels/DrainLabel").text == "OUTLET B")

	# ============================================================
	# V3 starts OPEN (the same "deliberate trap, real work required"
	# policy as every config) -- close it first so opening it again
	# later is a genuine transition. Then: open V1 (live feed), open V3
	# again BEFORE V2 -- the out-of-order case. Both branches end up
	# live once V2 also opens, but this must NOT complete the task, and
	# a warning must surface at the moment V3 was opened out of order.
	# ============================================================
	await _click(diorama, 3) # close the initially-open V3
	await _click(diorama, 1) # open the live feed
	var flow_v1_only: Dictionary = station.flow_state()
	_check("V1 alone: neither branch live yet", not flow_v1_only["outlet_live"] and not flow_v1_only["drain_live"])
	await _click(diorama, 3) # open V3 BEFORE V2 -- out-of-order
	var flow_wrong: Dictionary = station.flow_state()
	_check("wrong order: secondary branch live, primary still not", not flow_wrong["outlet_live"] and flow_wrong["drain_live"])
	# The view's own _on_valve_clicked() handler already consumed the
	# warning (same handler a real player's click goes through) and
	# surfaced it in the flow label -- checking the view's own displayed
	# text, not calling consume_sequence_warning() again here, which
	# would just find it already drained.
	var flow_label: Label = view.get_node("Panel/VBox/FlowLabel")
	_check("out-of-order open surfaces a recoverable pressure-loss warning", flow_label.text.findn("PRESSURE LOSS") != -1)
	_check("the station-side warning flag is already drained by the view (no double-surfacing)", not station.consume_sequence_warning())
	await _click(diorama, 2) # now open V2 too
	var flow_both_live: Dictionary = station.flow_state()
	_check("both branches live after opening V2 second", flow_both_live["outlet_live"] and flow_both_live["drain_live"])
	_check("task NOT complete despite both branches live -- wrong order", not day_plan.is_task_done(&"l08"))
	_check("world diorama's V3 segment reads LIVE (teal), not leak/red, in this config", not diorama._leak_segments.has(&"v3_drain"))

	# ============================================================
	# Correct the order: close V3, confirm V2 is open with V3 closed,
	# reopen V3 -- now the sequencing requirement is satisfied.
	# ============================================================
	await _click(diorama, 3) # close V3
	_check("V3 closed again", not station.is_valve_open(3))
	_check("V2 still open, V3 now closed -- correct order re-established", station.is_valve_open(2) and not station.is_valve_open(3))
	await _click(diorama, 3) # reopen V3, now correctly after V2
	var flow_correct: Dictionary = station.flow_state()
	_check("both branches live again, now correctly sequenced", flow_correct["outlet_live"] and flow_correct["drain_live"])
	_check("task completes once correctly sequenced", day_plan.is_task_done(&"l08"))

	main.get_node("FocusedInteractionState").end()
	await process_frame
	main.queue_free()
	await process_frame

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


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
