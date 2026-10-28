extends SceneTree
## Coverage for scripts/player/focused_interaction_state.gd -- the
## reusable "take exclusive control for a maintenance minigame"
## boundary (this milestone's Phase 2): focus entry/exit, movement/look
## gating, cursor restoration, input routing (Escape is reserved
## globally while active), cancel behavior, and repeated open/close
## never leaving a stuck state. Uses electrical_panel.gd's real
## terminal-click entry point as the trigger (there is no other way to
## open a session than through a real interactable), but the
## assertions here are about the STATE BOUNDARY itself, not the
## electrical procedure's own content (see test_electrical_repair_procedure.gd
## for that).
var _ok := true

const GameSettings = preload("res://scripts/station/game_settings.gd")

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty() # isolate from any stray persisted difficulty
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var focused := main.get_node("FocusedInteractionState")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var day_plan := main.get_node("DayPlan")
	var carry := player.get_node("CarrySystem")
	var wire := main.get_node("Interactables/WireComponent")
	var interaction_controller := player.get_node("LookPivot/PitchPivot/Camera3D")
	var look_pivot := player.get_node("LookPivot")
	var repair_view := player.get_node("HUD/ElectricalRepairView")

	_check("not active at start", not focused.is_active())

	# ============================================================
	# 1. Opening a session gates movement/look/interaction exactly like
	# the existing workstation/laptop exclusive states, and the player
	# cannot move through the station while focused (free_body
	# deactivated).
	# ============================================================
	day_plan.trigger_fault()
	panel.interact() # open door
	var terminal := panel.get_node("Terminal")
	terminal.interact(); terminal.interact() # E01, E02
	carry.pick_up(wire)
	terminal.interact() # opens the focused repair procedure for real
	await process_frame

	_check("focused session active after opening the procedure", focused.is_active())
	_check("active_view is the repair view", focused.active_view() == repair_view)
	_check("free movement disabled while focused", not free_body.active)
	_check("raycast interaction disabled while focused", not interaction_controller.interactions_enabled)
	_check("look escape handling disabled while focused", not look_pivot.escape_enabled)
	_check("look input disabled while focused", not look_pivot.input_enabled)
	_check("mouse mode set visible for the focused UI", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)

	# ============================================================
	# 2. WASD/E/C/G and other gameplay keys must not leak through to
	# movement/carry/etc. while focused -- free_body itself is
	# deactivated (checked above), which is the actual mechanism that
	# makes WASD inert; carry_system.gd's Space pickup/drop is gated on
	# interactions_enabled (also checked above).
	# ============================================================
	var carrying_before: bool = carry.is_carrying()
	var ev_g := InputEventKey.new()
	ev_g.keycode = KEY_SPACE
	ev_g.pressed = true
	Input.parse_input_event(ev_g)
	await process_frame
	_check("Space (pickup/drop) does not fire while focused", carry.is_carrying() == carrying_before)

	# ============================================================
	# 3. A second begin() attempt while already active is refused (the
	# one-session-at-a-time safety net).
	# ============================================================
	_check("a second begin() while active is refused", not focused.begin(repair_view))

	# ============================================================
	# 4. Escape is reserved globally while active and restores
	# everything end() restores, exactly once.
	# ============================================================
	var ev_esc := InputEventKey.new()
	ev_esc.keycode = KEY_ESCAPE
	ev_esc.pressed = true
	Input.parse_input_event(ev_esc)
	await process_frame

	_check("focused session ends on Escape", not focused.is_active())
	_check("free movement restored", free_body.active)
	_check("raycast interaction restored", interaction_controller.interactions_enabled)
	_check("look escape handling restored", look_pivot.escape_enabled)
	_check("look input restored", look_pivot.input_enabled)
	# NOTE: DisplayServerHeadless does not actually honor Input.mouse_mode
	# changes (confirmed empirically in a prior round -- reading it back
	# immediately after assignment always reports MOUSE_MODE_VISIBLE
	# regardless of what was set), so an exact "restored to the specific
	# prior value" assertion cannot be verified in this environment. This
	# only confirms end() runs the restore call without erroring; the
	# actual round-trip fidelity of focused_interaction_state.gd's
	# _prior_mouse_mode is a real-desktop-only manual check (see the
	# final report's manual playtest checklist).
	_check("mouse mode property is still a valid value after restore", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	_check("repair view hidden after Escape", not repair_view.visible)
	_check("canceling did not accidentally complete the repair", not panel.is_repaired())
	_check("canceling did not consume the carried wire", carry.is_carrying())
	free_body.set_active(false) # restore this test's own positioning invariant

	# ============================================================
	# 5. Repeated open/close never leaves a stuck state -- reopen,
	# close again via end() directly (as if the view itself called
	# close()), reopen once more.
	# ============================================================
	terminal.interact() # reopen -- procedure state (isolate stage) preserved from before
	await process_frame
	_check("reopens cleanly", focused.is_active())
	focused.end()
	_check("end() closes cleanly", not focused.is_active())
	_check("free movement restored again", free_body.active)
	free_body.set_active(false)

	terminal.interact()
	await process_frame
	_check("reopens a second time with no stuck state", focused.is_active())
	_check("interactions still disabled while focused (not double-restored)", not interaction_controller.interactions_enabled)
	focused.end()
	free_body.set_active(false)

	# ============================================================
	# 6. end() is always safe to call when already inactive (no-op,
	# never errors, never double-restores into a wrong state).
	# ============================================================
	focused.end()
	_check("end() when already inactive is a harmless no-op", not focused.is_active())
	_check("still not active after the redundant end()", not focused.is_active())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
