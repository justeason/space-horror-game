extends SceneTree
## Round 14 Priority 0 regression coverage for the manual-playtest report:
## "after reconnecting yellow wire, reconnecting blue wire incorrectly
## reports an error; only after clicking yellow again can blue
## reconnect." This is the SAME user-visible symptom
## test_reconnect_lifecycle.gd already covers, but THIS file is the one
## that actually reproduces it, because of a subtle difference in how
## the two files compute where to click.
##
## WHY test_reconnect_lifecycle.gd (Round 13) DID NOT CATCH THIS:
## its `_real_click()` helper computes the click position from
## `collider.global_position` -- the wire's "Collision" StaticBody3D,
## which is the AUTHORITATIVE click target by construction. Clicking
## exactly where the collider sits will always "work" regardless of
## whether the collider has actually moved to track the wire's real
## visual swing, so that test structurally could never observe the
## bug -- it was testing against its own ground truth, not the
## player's.
##
## A real player aims at the WIRE THEY CAN SEE ON SCREEN. This file's
## `_visual_click()` helper instead computes the click position from
## each wire's `VisualGroup/Cap` -- the actual rendered mesh endpoint --
## exactly like `screen_position_for()` + `_raycast_action()` do for a
## genuine mouse event arriving through `_unhandled_input()`. Before the
## Round 14 fix (see electrical_repair_diorama.gd's `_snap_collision_to_pose()`
## and its extensive doc comment on `_tween_wire_pitch()`), a disconnected
## wire's Collision body never moved from its connected-pose rest
## position at all, so a click at the wire's real visual position (which
## had swung away) missed the collider entirely -- reproducing the exact
## reported defect end-to-end through the real `_unhandled_input()` path.
var _ok := true

func _init() -> void:
	await _run_scenario(false, "NORMAL")
	await _run_scenario(true, "HARD")

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _run_scenario(hard: bool, label: String) -> void:
	const GameSettings = preload("res://scripts/station/game_settings.gd")
	var target_difficulty: int = GameSettings.Difficulty.HARD if hard else GameSettings.Difficulty.NORMAL
	while GameSettings.get_difficulty() != target_difficulty:
		GameSettings.cycle_difficulty()

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

	day_plan.trigger_fault()
	if hard:
		panel.interact() # opens the screw-removal focused view instead
		for i in 4:
			for t in 3:
				view._on_screw_clicked(i)
		await process_frame
		_check("[%s] door open after screws removed" % label, panel.is_door_open())
	else:
		panel.interact()
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
	# Round 18 Priority 9: see _wait_for_raycast_ready()'s own comment --
	# a freshly-active SubViewport's colliders need a variable number of
	# physics steps (not a fixed count) before intersect_ray() reliably
	# finds them.
	await _wait_for_raycast_ready(diorama, diorama._breaker_collider)

	# ---- Isolate + disconnect all three, via each wire's REAL VISUAL position. ----
	_visual_click_node(diorama, diorama._breaker_collider) # breaker's own collider tracks its hinge correctly
	_visual_click_wire(diorama, &"supply")
	_visual_click_wire(diorama, &"return")
	_visual_click_wire(diorama, &"service")
	_check("[%s] all three disconnected via clicks at their real visual positions" % label, panel.disconnected_roles() == [&"supply", &"return", &"service"])

	_visual_click_wire(diorama, &"service") # begin replace (still the original wire's swung-away visual)
	await create_timer(0.3).timeout # shrink-out tween
	_visual_click_replacement(diorama) # install, at the staged replacement's swung-away visual
	_check("[%s] replacement installed, now in reconnect" % label, panel.procedure_stage() == &"reconnect")

	# ============================================================
	# ROUND 16 regression (the recurring "extra Yellow click" report):
	# install_replacement_wire() committing is NOT the same backend
	# event as reconnect_wire(&"service") -- that only happens on the
	# player's NEXT, separate click on this now-installed wire. The
	# indicator must still read OFF right here, immediately after
	# install and before that next click, matching reconnected_roles()
	# still being empty for service. A diagnostic proved the previous
	# behavior (animate_install_replacement() lighting the indicator
	# green at install time, before reconnect_wire() was ever called)
	# is EXACTLY why a player would click Blue next (trusting the
	# falsely-green indicator), get correctly rejected, and only then
	# go back and click Yellow -- which reads as "the game demands an
	# extra Yellow click" even though the backend only ever needed the
	# one click it was always going to need. This is the test that
	# would have caught it: every previous reconnect test checked the
	# indicator AFTER a real reconnect_wire() call succeeded, never at
	# this specific install-vs-reconnect boundary.
	# ============================================================
	_check("[%s] service NOT yet in reconnected_roles() right after install (reconnect_wire() not yet called)" % label, not (&"service" in panel.reconnected_roles()))
	_check("[%s] indicator reads OFF right after install -- must not lie about an unconnected wire" % label, not _indicator_is_on(diorama, &"service"))

	# ============================================================
	# A wrong click BEFORE yellow (at Blue's real swung-away visual
	# position) must change nothing -- this is precisely the mistaken
	# click a player would make if the indicator above were (wrongly)
	# already green.
	# ============================================================
	_visual_click_wire(diorama, &"return")
	_check("[%s] wrong Blue-before-Yellow click (at Blue's real visual position) changes nothing" % label, panel.reconnected_roles().is_empty())

	# ============================================================
	# THE EXACT REPORTED SEQUENCE: reconnect Yellow (the replacement
	# wire, clicked at ITS real swung-away visual position), then
	# IMMEDIATELY click Blue at BLUE'S real swung-away visual position
	# -- this is what a real player, aiming at what they can see on
	# screen, actually does. Must succeed on the very next click.
	# ============================================================
	_visual_click_replacement(diorama) # Yellow
	_check("[%s] Yellow reconnected" % label, &"service" in panel.reconnected_roles())
	_check("[%s] sync: Yellow's indicator light reads ON immediately after its own reconnect" % label, _indicator_is_on(diorama, &"service"))

	# ============================================================
	# Round 15 Priority 0: click DURING Yellow's own settle animation
	# (its tween is still in flight at this point -- no artificial wait
	# was inserted above) at a WRONG wire's position, between Yellow and
	# Blue -- must change nothing, proving an in-flight animation on one
	# wire cannot be mistaken for a different wire's click target.
	# ============================================================
	_visual_click_wire(diorama, &"supply") # Red -- wrong, Blue is still required next
	_check("[%s] wrong click (Red) between Yellow and Blue, during Yellow's settle animation, changes nothing" % label, panel.reconnected_roles() == [&"service"])

	_visual_click_wire(diorama, &"return") # Blue, at Blue's own real visual position, immediately after
	_check("[%s] Blue accepted on the IMMEDIATELY FOLLOWING click, aimed at Blue's real visual position -- no replay of Yellow required (THE ACTUAL REPORTED BUG)" % label, &"return" in panel.reconnected_roles())
	_check("[%s] Yellow's completed connection was not disturbed by the Blue click" % label, &"service" in panel.reconnected_roles())
	_check("[%s] sync: Blue's indicator light reads ON immediately after its own reconnect" % label, _indicator_is_on(diorama, &"return"))

	# ============================================================
	# Round 15 Priority 0: Escape out of the focused session right after
	# Yellow+Blue, then reenter -- the backend state (DayPlan-authoritative,
	# owned by electrical_panel.gd) must survive the round-trip unchanged,
	# and Blue's visual/collider must still read as reconnected (not
	# reset to the disconnected pose) on reentry, with Red still clickable
	# immediately, no replay required.
	# ============================================================
	var reconnected_before_escape: Array = panel.reconnected_roles()
	main.get_node("FocusedInteractionState").end()
	await process_frame
	terminal.interact() # reopen the focused procedure
	await process_frame
	_check("[%s] reconnected roles survive an Escape/reentry round-trip" % label, panel.reconnected_roles() == reconnected_before_escape)
	_check("[%s] procedure stage still reconnect after reentry" % label, panel.procedure_stage() == &"reconnect")
	_check("[%s] sync: Blue's indicator still reads ON after reentry (visual resynced from authoritative state)" % label, _indicator_is_on(diorama, &"return"))

	# ============================================================
	# Re-clicking already-connected wires (at their NEW, connected-pose
	# visual positions) must be harmless.
	# ============================================================
	var before_repeat: Array = panel.reconnected_roles()
	_visual_click_replacement(diorama) # Yellow again, already connected
	_visual_click_wire(diorama, &"return") # Blue again, already connected
	_check("[%s] re-clicking already-connected wires at their current visual positions changes nothing" % label, panel.reconnected_roles() == before_repeat)

	# ============================================================
	# Final wire (Red), at its real visual position, completes reconnect.
	# ============================================================
	_visual_click_wire(diorama, &"supply") # Red
	_check("[%s] Red reconnected via its real visual position" % label, panel.reconnected_roles() == [&"service", &"return", &"supply"])

	await create_timer(0.4).timeout # let the final reconnect swing settle
	_visual_click_node(diorama, diorama._breaker_collider) # restore power
	_check("[%s] repair completes correctly" % label, panel.is_repaired())
	_check("[%s] e05 marked done" % label, day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await create_timer(0.3).timeout
	main.queue_free()
	await process_frame

	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()


## The wire's actual rendered endpoint right now -- NOT its collider --
## exactly what a real player aims at. Service resolves to the
## replacement wire once it is visible/installed, matching
## `_resolve_wire_node()`'s own role-resolution logic in the diorama.
func _wire_visual_cap(diorama: Node3D, role: StringName) -> Node3D:
	if role == &"service" and diorama._replacement_wire.visible:
		return diorama._replacement_wire.get_node("VisualGroup_service/Cap")
	return diorama._wire_nodes[role].get_node("VisualGroup/Cap")


func _wire_visual_screen_pos(diorama: Node3D, role: StringName) -> Vector2:
	return diorama.screen_position_for(_wire_visual_cap(diorama, role).global_position)


func _visual_click_wire(diorama: Node3D, role: StringName) -> void:
	_dispatch_real_click(diorama, _wire_visual_screen_pos(diorama, role))


func _visual_click_replacement(diorama: Node3D) -> void:
	var pos: Vector2 = diorama.screen_position_for(diorama._replacement_wire.get_node("VisualGroup_service/Cap").global_position)
	_dispatch_real_click(diorama, pos)


## For non-wire click targets (the breaker) whose Collision correctly
## tracks its own visual already (see electrical_repair_diorama.tscn --
## Breaker/Hinge/Collision is a CHILD of the very node the tween
## rotates, not a frozen sibling), the collider's own position IS the
## real visual position.
func _visual_click_node(diorama: Node3D, node: Node3D) -> void:
	_dispatch_real_click(diorama, diorama.screen_position_for(node.global_position))


## Dispatches a REAL InputEventMouseButton (press then release) through
## the diorama's actual `_unhandled_input()` -- the genuine production
## code path, not a direct `_dispatch_click()`/backend call.
func _dispatch_real_click(diorama: Node3D, pos: Vector2) -> void:
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
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	diorama._unhandled_input(up)


## Round 18 Priority 9 root-cause fix for this project's long-standing
## "first real click after opening a freshly-instantiated procedure
## intermittently misses" flakiness (test_reconnect_hitbox_bug.gd/
## test_reconnect_lifecycle.gd/this file). ROOT CAUSE (confirmed via
## direct measurement across 25+ repeated runs, not assumed): a fixed
## frame-count wait (even two explicit physics_frame ticks) after
## opening the procedure is not reliable -- the diorama's own
## SubViewport (own_world_3d = true) can take a VARIABLE number of
## physics steps to finish registering its StaticBody3D colliders with
## the physics server the first time a freshly-instantiated scene
## activates it, especially now that the panel builds half its wire/
## terminal geometry procedurally in _ready() (Round 18 Priority 2) --
## more node construction work in that one frame means more state that
## can still be mid-flight when a fixed-count wait elapses. Polling an
## ACTUAL raycast against a KNOWN-present collider (the breaker, always
## allowed at the isolate stage) until it genuinely resolves is a
## deterministic readiness check instead of a guessed delay: it waits
## exactly as long as reality requires, never longer, and never
## "passes" on a lucky guess the way a fixed wait can fail to catch.
func _wait_for_raycast_ready(diorama: Node3D, collider: Node3D, max_attempts: int = 30) -> void:
	var pos: Vector2 = diorama.screen_position_for(collider.global_position)
	for attempt in max_attempts:
		if diorama._raycast_action(pos) != &"":
			return
		await Engine.get_main_loop().physics_frame
	push_warning("_wait_for_raycast_ready: collider never became raycast-visible after %d physics frames" % max_attempts)


func _indicator_is_on(diorama: Node3D, role: StringName) -> bool:
	var indicator: CSGBox3D = diorama._terminal_indicators[role]
	var mat: StandardMaterial3D = indicator.material
	return mat.emission.is_equal_approx(diorama.LIGHT_ON_COLOR)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
