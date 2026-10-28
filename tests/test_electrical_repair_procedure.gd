extends SceneTree
const GameSettings = preload("res://scripts/station/game_settings.gd")
## Coverage for the visual-interaction milestone's Workstream A: the
## full electrical repair procedure (isolate -> disconnect -> replace
## -> reconnect -> restore), now driven through
## scripts/ui/electrical_repair_view.gd's CLICK dispatch handlers
## (_on_wire_clicked/_on_breaker_clicked/_on_screw_clicked/
## _on_replacement_clicked) instead of the previous round's numbered-
## key simulation -- these handlers are exactly what a real mouse click
## on the 3D diorama (scripts/ui/electrical_repair_diorama.gd) resolves
## to (see test_electrical_repair_diorama.gd for coverage of the
## raycast/hover mapping itself, which is the one piece that can't be
## driven through real OS mouse input in this headless environment).
## Also covers difficulty-gated hint visibility, incorrect-order
## recovery, the four-screw HARD variation, and task/watch/map/
## workstation synchronization through the single e05_status flag --
## none of that backend contract changed this round, only how the
## player's input reaches it.
var _ok := true

func _init() -> void:
	_set_global_difficulty(GameSettings.Difficulty.NORMAL) # isolate from any other test's persisted setting
	await _test_normal_difficulty_full_procedure()
	await _test_wrong_order_recovery()
	await _test_easy_difficulty_hints()
	await _test_hard_difficulty_no_hints_and_screws()
	await _test_sync_across_watch_map_workstation()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _make_main() -> Node:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for i in 5: await process_frame
	return main


## Round 10: difficulty is a global GameSettings value, not a per-panel
## field -- there is no direct setter, only cycle_difficulty(), so this
## cycles until the live value matches. Must be called before the
## target panel's door is ever opened (electrical_panel.gd locks in
## whatever the global value is at that moment and ignores later
## changes for the rest of that repair).
func _set_global_difficulty(target: int) -> void:
	while GameSettings.get_difficulty() != target:
		GameSettings.cycle_difficulty()


func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame


## The two-click Replace gesture: click the damaged wire (begins the
## shrink-out/replacement-staged tween sequence), wait for it to finish,
## then click the replacement to install.
func _do_replace(view: Node) -> void:
	view._on_wire_clicked(&"service")
	await create_timer(0.35).timeout
	view._on_replacement_clicked()


## Opens the panel/terminal up through TRACED, picks up the wire, and
## opens the focused procedure for real (terminal click) -- shared setup
## for every scenario below.
func _setup_at_procedure_start(main: Node) -> Dictionary:
	var player: Node = main.get_node("Player")
	var free_body: Node = main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var day_plan: Node = main.get_node("DayPlan")
	var carry: Node = player.get_node("CarrySystem")
	var wire: Node = main.get_node("Interactables/WireComponent")
	var repair_view: Node = player.get_node("HUD/ElectricalRepairView")
	var focused: Node = main.get_node("FocusedInteractionState")

	day_plan.trigger_fault()
	if not panel.is_door_open():
		panel.interact() # open door (may already be open, e.g. HARD-difficulty screw test)
	# Round 16 Priority 3: electrical_panel.gd now RANDOMLY selects which
	# wire is at fault for each repair instance (see its own
	# _REPAIR_CONFIGS). This entire file hardcodes the fixed, pre-Round-16
	# supply/return/service disconnect order and assumes "service"
	# (Yellow) is the one replaced -- forcing the deterministic default
	# config here (the brief's own "use deterministic seeds for testing"
	# requirement) keeps every scenario below meaningful without needing
	# to rewrite each one to branch on whichever role got picked.
	# tests/test_electrical_wire_randomization.gd is the file that
	# actually exercises the alternate (Blue/return) configuration.
	panel.debug_force_fault_role(&"service")
	var terminal: Node = panel.get_node("Terminal")
	terminal.interact() # E01
	terminal.interact() # E02
	carry.pick_up(wire)
	terminal.interact() # opens the focused procedure for real
	await process_frame

	return {
		"player": player, "free_body": free_body, "panel": panel, "day_plan": day_plan,
		"carry": carry, "wire": wire, "view": repair_view, "focused": focused, "terminal": terminal,
	}


func _test_normal_difficulty_full_procedure() -> void:
	var main := await _make_main()
	var s: Dictionary = await _setup_at_procedure_start(main)
	var panel: Node = s["panel"]
	var day_plan: Node = s["day_plan"]
	var carry: Node = s["carry"]
	var wire: Node = s["wire"]
	var focused: Node = s["focused"]
	var view: Node = s["view"]

	_check("NORMAL: starts at ISOLATE", panel.procedure_stage() == &"isolate")
	_check("NORMAL: not isolated yet", not panel.is_isolated())

	# Disconnecting before isolating must be rejected cleanly -- clicking
	# a wire is only even offered as "allowed" once isolated, but the
	# panel's own method is still the real backstop, so call it directly
	# here to confirm the backstop itself (not just the UI gating) holds.
	panel.disconnect_wire(&"supply")
	_check("NORMAL: disconnect before isolating is rejected", panel.disconnected_roles().is_empty())

	view._on_breaker_clicked() # toggle breaker -> isolated, advances to DISCONNECT
	_check("NORMAL: isolated after clicking the breaker", panel.is_isolated())
	_check("NORMAL: advanced to DISCONNECT", panel.procedure_stage() == &"disconnect")
	_check("NORMAL: hint IS shown during disconnect", not panel.current_hint_sequence().is_empty())

	view._on_wire_clicked(&"supply")
	view._on_wire_clicked(&"return")
	view._on_wire_clicked(&"service")
	_check("NORMAL: all three disconnected in order", panel.disconnected_roles() == [&"supply", &"return", &"service"])
	_check("NORMAL: advanced to REPLACE", panel.procedure_stage() == &"replace")
	_check("NORMAL: not repaired merely from disconnecting", not panel.is_repaired())
	_check("NORMAL: still carrying the wire before confirming install", carry.is_carrying())

	await _do_replace(view) # click damaged wire, then the replacement
	_check("NORMAL: wire consumed only now, at explicit install", not carry.is_carrying())
	_check("NORMAL: wire marked installed", wire.is_installed())
	_check("NORMAL: advanced to RECONNECT", panel.procedure_stage() == &"reconnect")
	_check("NORMAL: hint is HIDDEN during reconnect (must recall)", panel.current_hint_sequence().is_empty())
	_check("NORMAL: e05 still not done mid-procedure", not day_plan.is_task_done(&"e05"))

	# Wrong order during reconnect: forward order (supply first) is
	# wrong -- must be reverse of disconnect (service, return, supply).
	view._on_wire_clicked(&"supply") # wrong, service must be first
	_check("NORMAL: wrong reconnect order rejected", panel.reconnected_roles().is_empty())

	view._on_wire_clicked(&"service")
	view._on_wire_clicked(&"return")
	view._on_wire_clicked(&"supply")
	_check("NORMAL: reconnected in exact reverse order", panel.reconnected_roles() == [&"service", &"return", &"supply"])
	_check("NORMAL: advanced to RESTORE", panel.procedure_stage() == &"restore")

	view._on_breaker_clicked() # restore power
	_check("NORMAL: repaired after restore", panel.is_repaired())
	_check("NORMAL: e05 marked done only now", day_plan.is_task_done(&"e05"))
	_check("NORMAL: advanced to COMPLETE", panel.procedure_stage() == &"complete")

	await _press(KEY_ENTER) # close (the one key still handled directly, at COMPLETE only)
	_check("NORMAL: session closes on completion confirm", not focused.is_active())


func _test_wrong_order_recovery() -> void:
	var main := await _make_main()
	var s: Dictionary = await _setup_at_procedure_start(main)
	var panel: Node = s["panel"]
	var carry: Node = s["carry"]
	var view: Node = s["view"]

	view._on_breaker_clicked() # isolate
	view._on_wire_clicked(&"return") # wrong -- supply must be first
	_check("RECOVERY: wrong disconnect leaves nothing disconnected", panel.disconnected_roles().is_empty())
	_check("RECOVERY: still isolated after a wrong attempt (no destructive reset)", panel.is_isolated())
	_check("RECOVERY: still carrying the wire after a wrong attempt", carry.is_carrying())

	view._on_wire_clicked(&"supply") # correct now
	_check("RECOVERY: correct wire accepted after a wrong attempt", panel.disconnected_roles() == [&"supply"])
	view._on_wire_clicked(&"supply") # already disconnected -- rejected, not duplicated
	_check("RECOVERY: re-disconnecting an already-disconnected wire is rejected, not duplicated", panel.disconnected_roles() == [&"supply"])

	view._on_wire_clicked(&"return")
	view._on_wire_clicked(&"service")
	await _do_replace(view)
	# Wrong reconnect order, verify recoverable.
	view._on_wire_clicked(&"return") # wrong -- service must be first
	_check("RECOVERY: wrong reconnect leaves nothing reconnected", panel.reconnected_roles().is_empty())
	view._on_wire_clicked(&"service")
	_check("RECOVERY: correct reconnect accepted after a wrong attempt", panel.reconnected_roles() == [&"service"])

	main.get_node("FocusedInteractionState").end()
	_check("RECOVERY: canceling mid-reconnect does not complete the repair", not panel.is_repaired())


func _test_easy_difficulty_hints() -> void:
	var main := await _make_main()
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	_set_global_difficulty(GameSettings.Difficulty.EASY)
	var s: Dictionary = await _setup_at_procedure_start(main)
	panel = s["panel"] # re-fetch (same node, kept for clarity)
	var view: Node = s["view"]

	view._on_breaker_clicked()
	_check("EASY: hint shown during disconnect", not panel.current_hint_sequence().is_empty())
	view._on_wire_clicked(&"supply"); view._on_wire_clicked(&"return"); view._on_wire_clicked(&"service")
	await _do_replace(view)
	_check("EASY: hint ALSO shown during reconnect (more explicit guidance)", not panel.current_hint_sequence().is_empty())
	_check("EASY: reconnect hint is the reverse of the disconnect order", panel.current_hint_sequence() == [&"service", &"return", &"supply"])


func _test_hard_difficulty_no_hints_and_screws() -> void:
	var main := await _make_main()
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	_set_global_difficulty(GameSettings.Difficulty.HARD)
	var player: Node = main.get_node("Player")
	var view: Node = player.get_node("HUD/ElectricalRepairView")
	var focused: Node = main.get_node("FocusedInteractionState")

	_check("HARD: door starts closed", not panel.is_door_open())
	panel.interact() # should open the screws view, not the door
	await process_frame
	_check("HARD: door still closed -- screws required first", not panel.is_door_open())
	_check("HARD: focused session active (screws)", focused.is_active())
	_check("HARD: repair view visible for screws", view.visible)

	for i in 4:
		for t in 3: # SCREW_TURNS_TO_REMOVE
			view._on_screw_clicked(i)
	_check("HARD: door opens once all four screws are out", panel.is_door_open())
	_check("HARD: focused session auto-closes once screws finish", not focused.is_active())

	var s: Dictionary = await _setup_at_procedure_start(main)
	panel = s["panel"]
	view._on_breaker_clicked()
	_check("HARD: no hint during disconnect", panel.current_hint_sequence().is_empty())
	view._on_wire_clicked(&"supply"); view._on_wire_clicked(&"return"); view._on_wire_clicked(&"service")
	await _do_replace(view)
	_check("HARD: no hint during reconnect either", panel.current_hint_sequence().is_empty())
	view._on_wire_clicked(&"service"); view._on_wire_clicked(&"return"); view._on_wire_clicked(&"supply")
	view._on_breaker_clicked()
	_check("HARD: repair completes without any hints", panel.is_repaired())
	await _press(KEY_ENTER)

	# Reinstall screws to close.
	panel.interact() # should open screws view in reinstall mode, not close directly
	await process_frame
	_check("HARD: door still open -- reinstall screws required to close", panel.is_door_open())
	for i in 4:
		for t in 3:
			view._on_screw_clicked(i)
	_check("HARD: door closes once all four screws are reinstalled", not panel.is_door_open())


func _test_sync_across_watch_map_workstation() -> void:
	_set_global_difficulty(GameSettings.Difficulty.NORMAL) # undo the HARD test's change -- this scenario doesn't care about difficulty and expects a plain door-open
	var main := await _make_main()
	var s: Dictionary = await _setup_at_procedure_start(main)
	var panel: Node = s["panel"]
	var day_plan: Node = s["day_plan"]
	var player: Node = s["player"]
	var view: Node = s["view"]

	view._on_breaker_clicked()
	view._on_wire_clicked(&"supply"); view._on_wire_clicked(&"return"); view._on_wire_clicked(&"service")
	await _do_replace(view)
	view._on_wire_clicked(&"service"); view._on_wire_clicked(&"return"); view._on_wire_clicked(&"supply")
	view._on_breaker_clicked()
	await _press(KEY_ENTER)

	# Watch, map, and workstation all read the SAME day_plan/panel state
	# -- no second independent "repaired" flag anywhere.
	var work_order_lines: Array = day_plan.get_work_order_lines(panel.is_repaired())
	_check("SYNC: work order line reports REPAIRED once e05 is done", work_order_lines[0].findn("REPAIRED") != -1)

	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var console: Node = main.get_node("Interactables/WorkstationConsole")
	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	var free_body: Node = main.get_node("FreeMoveBody")
	free_body.set_active(false)
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	console.interact()
	await create_timer(1.0).timeout
	screen.show_section(screen.Section.OVERVIEW)
	await create_timer(0.05).timeout
	_check("SYNC: outstanding task room no longer points at Engineering once repaired", day_plan.get_outstanding_task_room() != &"engineering")


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
