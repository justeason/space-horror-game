extends SceneTree
## Round 20 Priority 5 regression coverage: the wristwatch's new
## "GET PART\nSTORAGE" hint (scripts/player/wristwatch_view.gd), shown
## in place of the normal room+action text whenever the electrical
## task's required component has been diagnosed (DayPlan.
## required_component_id set by electrical_panel.gd's trace step) but
## the player is not yet carrying it. Confirms: no hint before the
## trace step sets the field; the hint appears once traced and the
## player is empty-handed; it disappears the instant the matching part
## is picked up; and -- the actual regression this test exists to
## catch -- it does NOT reappear after the repair is fully completed,
## even though required_component_id is never reset mid-day (see
## day_plan.gd's reset_for_new_day() class doc comment), because the
## hint is explicitly gated on e05 still being outstanding.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var watch := player.get_node("Wristwatch")
	var rig := player.get_node("LookPivot/PitchPivot/Camera3D/FirstPersonWatchRig")
	var watch_face: Label3D = rig.get_node("ArmGroup/WatchAssembly/WatchFaceText")
	var dp := main.get_node("DayPlan")
	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var carry := player.get_node("CarrySystem")
	var wire := main.get_node("Interactables/WireComponent")
	var focused := main.get_node("FocusedInteractionState")

	panel.debug_force_fault_role(&"service")

	await _press(KEY_C)
	await create_timer(0.3).timeout
	_check("before diagnosis: no part hint yet", watch_face.text.findn("GET PART") == -1)
	await _release(KEY_C)

	# Reach TRACED (two terminal interacts) -- sets required_component_id.
	panel.interact() # open the door
	panel.terminal_interact(&"damaged") # inspect -> e01
	panel.terminal_interact(&"damaged") # trace -> e02, sets required_component_id
	_check("precondition: required component now known", dp.required_component_id != &"")
	_check("precondition: not carrying it yet", not carry.is_carrying())

	await _press(KEY_C)
	await create_timer(0.3).timeout
	_check("after diagnosis, empty-handed: hint shows GET PART STORAGE", watch_face.text.findn("GET PART") != -1 and watch_face.text.findn("STORAGE") != -1)
	await _release(KEY_C)

	wire.interact() # pick up the correct spare
	await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
	_check("now carrying the matching part", carry.is_carrying() and carry.carried_item_id() == dp.required_component_id)

	await _press(KEY_C)
	await create_timer(0.3).timeout
	_check("once carrying the matching part, hint is gone", watch_face.text.findn("GET PART") == -1)
	await _release(KEY_C)

	# Drive the rest of the repair to completion via the real procedure
	# (same direct-method-call technique test_electrical_panel_chain.gd
	# already uses).
	panel.terminal_interact(&"damaged") # open procedure
	panel.toggle_isolation()
	panel.disconnect_wire(&"supply")
	panel.disconnect_wire(&"return")
	panel.disconnect_wire(&"service")
	panel.install_replacement_wire()
	panel.reconnect_wire(&"service")
	panel.reconnect_wire(&"return")
	panel.reconnect_wire(&"supply")
	panel.restore_power()
	_check("precondition: e05 actually marked done", dp.is_task_done(&"e05"))

	# Close the focused repair session (KEY_ENTER confirm at COMPLETE,
	# same as test_electrical_repair_procedure.gd) -- interactions,
	# including the watch's own C poll, are gated off while it's open.
	await _press(KEY_ENTER)
	await _release(KEY_ENTER)
	_check("precondition: focused session closed", not focused.is_active())

	await _press(KEY_C)
	await create_timer(0.3).timeout
	_check("REGRESSION CHECK: hint does not reappear after the repair is done, even though required_component_id lingers", watch_face.text.findn("GET PART") == -1)
	await _release(KEY_C)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame

func _release(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
