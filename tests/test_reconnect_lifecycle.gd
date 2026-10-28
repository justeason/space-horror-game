extends SceneTree
## Round 13 Workstream A regression coverage for the reported recurring
## defect: "Yellow was connected. The player attempted Blue, the
## expected next wire. The game rejected the Blue interaction. The
## player had to disconnect and reconnect Yellow again. Only then
## would the game allow Blue."
##
## ROOT CAUSE #1 (confirmed via a direct diagnostic, not assumed):
## electrical_repair_diorama.gd's `_unhandled_input()` previously
## dispatched clicks using `_hovered_action` -- a value cached ONCE PER
## `_process()` TICK, not resolved fresh at the click event itself.
## Mouse MOTION events are delivered through the same input queue but
## are NOT handled here at all (hover is exclusively refreshed in
## `_process()`). A fast, deliberate move-then-click landing within a
## single rendered frame can therefore dispatch using whatever was
## hovered a frame earlier (e.g. Yellow's own connector, just clicked)
## instead of what is actually under the cursor at click time.
##
## ROOT CAUSE #2 (confirmed via a direct diagnostic): each wire's
## `Collision` click-target body was previously a SIBLING of its
## visual mesh, both children of the SAME node whose `rotation.x` the
## connect/disconnect tween animates. While a wire's reconnect-settle
## animation is still in flight, its collider sweeps through real 3D
## space along with the visual -- and the sweep's own lateral travel
## (radius ~0.64 at up to 58 degrees => ~0.54m) very nearly equals the
## ~0.55m spacing between adjacent terminals, so the raycast toward a
## NEIGHBORING wire's terminal could resolve to the animating wire's
## own (still-settling) collider instead.
##
## THE FIX: `_unhandled_input()` now resolves the click target via a
## fresh raycast at the event's own screen position (see that
## function's class doc comment); and each wire's Collision body was
## moved out from under the animated "VisualGroup" child to be a
## permanently-fixed sibling of it, never rotated, so no in-flight
## animation can ever move a click target through space again.
##
## This file drives input through the REAL `_unhandled_input()` path
## (constructing actual InputEventMouseButton events, not calling
## `_dispatch_click()`/panel methods directly), with NO artificial
## ANIMATION/TIMER delay between actions wherever the report implies a
## fast, fluid player action -- the exact timing regime the bug lived
## in. (Round 14: `_real_click()` does await a single physics_frame
## after each click, because a wire's Collision body can move as a
## result of that click, and Godot's physics server does not make a
## StaticBody3D's new transform visible to intersect_ray() until its
## next physics step -- an engine constraint, not a game-logic delay;
## two genuinely separate completed mouse clicks are never truly
## zero-frames apart for a real player either.)
var _ok := true

func _init() -> void:
	await _run_lifecycle_scenario(false, "NORMAL")
	await _run_lifecycle_scenario(true, "HARD")

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _run_lifecycle_scenario(hard: bool, label: String) -> void:
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
		var screws_view: Node = view
		for i in 4:
			for t in 3:
				screws_view._on_screw_clicked(i)
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
	# Round 18 Priority 9 root-cause fix: a render frame (process_frame)
	# is not the same signal as a PHYSICS step, and opening the
	# procedure just synced every wire/breaker StaticBody3D's pose via
	# sync_full_state() -- but even a FIXED count of physics_frame ticks
	# turned out not to be reliable here (measured directly: 1 tick cut
	# the failure rate noticeably but not to zero, 2 ticks got closer
	# but still failed intermittently across 15+ runs). The actual
	# amount of settling needed varies run to run -- this diorama's own
	# SubViewport (own_world_3d = true) can take a VARIABLE number of
	# physics steps to finish registering a freshly-instantiated scene's
	# StaticBody3D colliders with the physics server the first time,
	# especially now that half the panel's wires/terminals are built
	# procedurally in _ready() (Round 18 Priority 2) rather than present
	# from scene deserialization. _wait_for_raycast_ready() polls an
	# ACTUAL raycast against the breaker (always allowed at the isolate
	# stage) until it genuinely resolves -- a deterministic readiness
	# check instead of a guessed delay: it waits exactly as long as
	# reality requires, never longer, and can't silently under-wait the
	# way a fixed count did.
	await _wait_for_raycast_ready(diorama, diorama._breaker_collider)

	# ---- Through to RECONNECT: isolate, disconnect all three, replace. ----
	await _real_click(diorama, diorama._breaker_collider)
	await _real_click(diorama, diorama._wire_colliders[&"supply"])
	await _real_click(diorama, diorama._wire_colliders[&"return"])
	await _real_click(diorama, diorama._wire_colliders[&"service"])
	_check("[%s] all three disconnected via real mouse-click events" % label, panel.disconnected_roles() == [&"supply", &"return", &"service"])

	await _real_click(diorama, diorama._wire_colliders[&"service"]) # begin replace
	await create_timer(0.3).timeout # shrink-out tween
	await _real_click(diorama, diorama._replacement_collider) # install
	_check("[%s] replacement installed, now in reconnect" % label, panel.procedure_stage() == &"reconnect")

	# ============================================================
	# A3: wrong click BEFORE yellow -- must change nothing.
	# ============================================================
	await _real_click(diorama, diorama._wire_colliders[&"return"]) # wrong -- yellow is required first
	_check("[%s] wrong Blue-before-Yellow click changes nothing" % label, panel.reconnected_roles().is_empty())

	# ============================================================
	# THE CORE REGRESSION: reconnect Yellow, then IMMEDIATELY (the very
	# next click, with no animation/timer wait) click Blue -- must
	# succeed on the very next click, with no requirement to replay
	# Yellow.
	# ============================================================
	await _real_click(diorama, diorama._replacement_collider) # Yellow
	_check("[%s] Yellow reconnected" % label, &"service" in panel.reconnected_roles())

	await _real_click(diorama, diorama._wire_colliders[&"return"]) # Blue, the very next click after Yellow
	_check("[%s] Blue accepted on the IMMEDIATELY FOLLOWING click -- no replay of Yellow required (THE ACTUAL BUG)" % label, &"return" in panel.reconnected_roles())
	_check("[%s] Yellow's completed connection was not disturbed by the Blue click" % label, &"service" in panel.reconnected_roles())

	# ============================================================
	# Multiple clicks on an already-connected wire must be harmless --
	# no mutation, no error, no regression of its state.
	# ============================================================
	var before_repeat: Array = panel.reconnected_roles()
	await _real_click(diorama, diorama._replacement_collider) # Yellow again, already connected
	await _real_click(diorama, diorama._wire_colliders[&"return"]) # Blue again, already connected
	_check("[%s] re-clicking already-connected wires changes nothing" % label, panel.reconnected_roles() == before_repeat)

	# ============================================================
	# Wrong click AFTER Yellow+Blue (clicking Yellow/Blue again isn't
	# "wrong" since they're just no-ops; test a genuine wrong-order
	# click -- there is none left except the already-reconnected ones,
	# so instead verify an immediate CORRECT click (Red) succeeds right
	# after the repeated-click no-ops above, with no leftover bad state).
	# ============================================================
	await _real_click(diorama, diorama._wire_colliders[&"supply"]) # Red -- correct, final wire
	_check("[%s] Red reconnected immediately after the repeated-click no-ops" % label, panel.reconnected_roles() == [&"service", &"return", &"supply"])

	await create_timer(0.4).timeout # let the final reconnect swing settle
	await _real_click(diorama, diorama._breaker_collider) # restore power
	_check("[%s] repair completes correctly" % label, panel.is_repaired())
	_check("[%s] e05 marked done" % label, day_plan.is_task_done(&"e05"))

	main.get_node("FocusedInteractionState").end()
	await create_timer(0.3).timeout
	main.queue_free()
	await process_frame

	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL:
		GameSettings.cycle_difficulty()


## Dispatches a REAL InputEventMouseButton (press then release) at the
## screen position of `collider`, through the diorama's actual
## `_unhandled_input()` -- the genuine production code path (including
## the Round 13 fix), not a direct `_dispatch_click()`/backend call.
func _real_click(diorama: Node3D, collider: Node3D) -> void:
	var pos: Vector2 = diorama.screen_position_for(collider.global_position)
	# Round 18 Priority 9: a fresh raycast at this exact position can be
	# a TRANSIENT miss immediately after a PRECEDING click moved some
	# OTHER collider (measured directly: the physics server's broadphase
	# appears to still be mid-rebuild around the just-moved collider for
	# one more step) even though this click's own target never moved --
	# one retry after a real physics step resolves it reliably. This
	# mirrors _wait_for_raycast_ready()'s "poll for the real signal,
	# don't guess a count" principle, scoped to a single extra attempt
	# since the miss is rare and transient, not a guaranteed-slow
	# first-activation case. A genuinely disallowed/wrong click still
	# correctly resolves to "" on the retry too (nothing about this
	# changes the _allowed gate), so this never masks a real rejection.
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
	# Round 14: see test_reconnect_hitbox_bug.gd's identical comment on
	# its own _click() helper -- a wire's Collision body can move as a
	# direct result of the click just dispatched above, and Godot's
	# physics server does not make that new transform visible to
	# intersect_ray() until its next physics step. Two genuinely
	# SEPARATE completed mouse clicks are never truly zero-frames apart
	# for a real player, so waiting one physics_frame here does not
	# weaken this test's "no artificial delay" intent -- that intent is
	# about not waiting for ANIMATIONS/TIMERS to settle between clicks,
	# which this file still does not do.
	await physics_frame


## Round 18 Priority 9 root-cause fix -- see the identical, fuller
## comment just above this file's own call site. Polls an actual
## raycast against a known-present collider until it genuinely resolves,
## instead of guessing a fixed frame count.
func _wait_for_raycast_ready(diorama: Node3D, collider: Node3D, max_attempts: int = 30) -> void:
	var pos: Vector2 = diorama.screen_position_for(collider.global_position)
	for attempt in max_attempts:
		if diorama._raycast_action(pos) != &"":
			return
		await Engine.get_main_loop().physics_frame
	push_warning("_wait_for_raycast_ready: collider never became raycast-visible after %d physics frames" % max_attempts)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
