extends SceneTree
const GameSettings = preload("res://scripts/station/game_settings.gd")
## Milestone 1 (Hands-On Electrical Repair) regression coverage for the
## new door/terminal mechanism that replaced the old "clicking near the
## panel makes the wire disappear" behavior:
##   - the cabinet's own click only opens/closes the door and never
##     touches task state or the carried item;
##   - the correct terminal is a genuinely separate, independently
##     reachable target (not swallowed by the cabinet's own collider);
##   - a wrong terminal preserves the carried wire with explanatory
##     feedback, never silently consuming it;
##   - a successful install visibly/statefully persists across a
##     door close+reopen, and the installed wire can never be picked
##     up again as loose inventory;
##   - a dropped loose wire can still be picked back up and installed;
##   - repeated interaction after repair does not duplicate the
##     installation or re-fire completion.
var _ok := true

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty() # isolate from any stray persisted difficulty
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var carry := player.get_node("CarrySystem")
	var wire := main.get_node("Interactables/WireComponent")
	var dp := main.get_node("DayPlan")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var terminal := panel.get_node("Terminal")
	var intact_terminal := panel.get_node("IntactTerminal")

	# ============================================================
	# 1. Door open/close is a real, independent toggle: it does not
	# touch task state, and closing then reopening does not reset
	# diagnostic progress already made.
	# ============================================================
	_check("panel starts closed", not panel.is_door_open())
	panel.interact()
	_check("first cabinet click opens the door", panel.is_door_open())
	_check("opening the door alone does not start the repair chain", not dp.is_task_done(&"e01"))

	# Round 16 Priority 3: force the deterministic default config -- this
	# file hardcodes the fixed supply/return/service order (see
	# tests/test_electrical_wire_randomization.gd for the alternate one).
	panel.debug_force_fault_role(&"service")
	panel.terminal_interact(&"damaged") # E01
	panel.terminal_interact(&"damaged") # E02
	_check("E01/E02 progressed via the terminal", dp.is_task_done(&"e01") and dp.is_task_done(&"e02"))

	panel.interact() # close
	_check("second cabinet click closes the door", not panel.is_door_open())
	_check("closing the door does not undo diagnostic progress", dp.is_task_done(&"e02"))
	panel.interact() # reopen
	_check("door reopens", panel.is_door_open())
	_check("diagnostic progress survived a close/reopen cycle", dp.is_task_done(&"e02"))

	# ============================================================
	# 2. Terminal is a genuinely separate target: it has its own
	# collider, distinct from the cabinet's, and the cabinet's own
	# collider cannot be used to drive terminal_interact() (there is
	# no such path -- the cabinet's interact() only toggles the door,
	# confirmed structurally: calling it again here must close the
	# door, not advance the repair stage).
	# ============================================================
	panel.interact() # closes
	panel.interact() # reopens -- still just toggling, never advancing stage
	_check("repeated cabinet clicks never advance the repair stage past E02", dp.is_task_done(&"e02") and not panel.is_repaired())
	# The cabinet itself (a CSGBox3D with use_collision=true) has no
	# literal "Collision" child node of its own -- its collider is
	# generated internally. Terminal/IntactTerminal are genuinely
	# separate StaticBody3D bodies with their own explicit
	# CollisionShape3D, which is the actual fix (see
	# terminal_connector.gd's class doc comment for why a CSG-nested
	# child could not be used for this).
	_check("terminal has its own explicit CollisionShape3D", terminal.get_node("Collision") is CollisionShape3D)
	_check("terminal's collider is a different object from the intact terminal's", terminal.get_node("Collision") != intact_terminal.get_node("Collision"))
	_check("terminal is reachable while open", not terminal.get_node("Collision").disabled)

	# ============================================================
	# 3. Wrong terminal preserves the carried wire and explains why.
	# ============================================================
	panel.terminal_interact(&"damaged") # advance to TRACED
	wire.interact()
	_check("wire picked up before attempting the wrong terminal", carry.is_carrying())
	intact_terminal.interact() # wrong terminal, via its own real interact()
	_check("wrong terminal does not consume the wire", carry.is_carrying() and carry.carried_item_id() == &"wire_control_16ga")
	_check("wrong terminal does not repair the panel", not panel.is_repaired())

	# ============================================================
	# 4. Drop the loose wire, pick it back up, THEN install at the
	# correct terminal -- the carry/drop system is reused as-is, and
	# installation still only happens through the correct terminal.
	# ============================================================
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	player.global_position = Vector3(0.0, 1.6, 0.5) # Control Room floor, see test_carry_drop.gd
	player.rotation.y = 0.0
	player.get_node("LookPivot").rotation.y = 0.0
	await process_frame
	_send_key(KEY_SPACE)
	await process_frame
	_check("wire dropped on the floor", not carry.is_carrying())
	_check("dropped wire is not installed", not wire.is_installed())
	wire.interact()
	_check("dropped wire can be picked back up", carry.is_carrying() and carry.carried_item_id() == &"wire_control_16ga")

	terminal.interact() # correct terminal, via its own real interact() -- opens the focused repair procedure (Phase 3 milestone)
	_check("terminal click opens the multi-stage repair procedure", panel.procedure_stage() == &"isolate")
	panel.toggle_isolation()
	panel.disconnect_wire(&"supply")
	panel.disconnect_wire(&"return")
	panel.disconnect_wire(&"service")
	panel.install_replacement_wire()
	panel.reconnect_wire(&"service")
	panel.reconnect_wire(&"return")
	panel.reconnect_wire(&"supply")
	panel.restore_power()
	# Close the real focused session the terminal click above opened
	# (see electrical_panel.gd's _open_procedure()) now that the
	# procedure is complete -- same as pressing Enter/Escape -- so
	# interactions_enabled/free movement/look input are restored for
	# the rest of this test.
	main.get_node("FocusedInteractionState").end()
	_check("install succeeds at the correct terminal", panel.is_repaired())
	_check("e05 marked done", dp.is_task_done(&"e05"))
	_check("wire no longer carried after install", not carry.is_carrying())
	_check("wire is marked installed (persistent, not freed)", is_instance_valid(wire) and wire.is_installed())
	_check("installed wire is parented at the correct terminal", wire.get_parent() == terminal)

	# ============================================================
	# 5. Installed wire cannot be picked up as loose inventory again.
	# ============================================================
	wire.interact() # a stray click on the now-installed wire
	_check("clicking the installed wire does not start carrying it", not carry.is_carrying())
	_check("installed wire prompt is empty (not offered as a pickup)", wire.get_interact_prompt() == "")

	# ============================================================
	# 6. Installation persists across a door close/reopen.
	# ============================================================
	panel.interact() # close
	_check("door closed after install", not panel.is_door_open())
	_check("still marked repaired while closed", panel.is_repaired())
	panel.interact() # reopen
	_check("door reopened after install", panel.is_door_open())
	_check("installed wire still present and still installed after reopening", is_instance_valid(wire) and wire.is_installed() and wire.get_parent() == terminal)

	# ============================================================
	# 7. Repeated interaction after repair does not duplicate the
	# installation or re-fire completion.
	# ============================================================
	var e05_done_before: bool = dp.is_task_done(&"e05")
	terminal.interact()
	terminal.interact()
	_check("repeated terminal clicks after repair stay idempotent (still marked done, not re-triggered)", dp.is_task_done(&"e05") == e05_done_before)
	var wire_count := 0
	for child in terminal.get_children():
		if child.has_method("get_display_name"):
			wire_count += 1
	_check("exactly one installed wire exists at the terminal (no duplication)", wire_count == 1)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _send_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
