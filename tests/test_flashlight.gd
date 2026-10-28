extends SceneTree
## Round 14 Priority 4 regression coverage for the first-pass flashlight:
## starts off; KEY_L toggles it on/off; the beam hides (but the on/off
## state is preserved) while a focused interaction session (e.g. the
## electrical repair procedure) is active, since the player's hands are
## occupied with that close-up task; pressing the toggle key while
## focused is ignored outright, so a stray press can't leave the beam in
## a surprising state once the session ends; and the beam reappears
## automatically once focus ends, with no extra input required.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var flashlight := player.get_node("LookPivot/PitchPivot/Camera3D/Flashlight")
	var light: SpotLight3D = flashlight.get_node("SpotLight3D")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var day_plan: Node = main.get_node("DayPlan")
	var terminal: Node = panel.get_node("Terminal")
	var carry: Node = player.get_node("CarrySystem")
	var wire: Node = main.get_node("Interactables/WireComponent")
	var focused := main.get_node("FocusedInteractionState")

	_check("starts off", not flashlight.is_on())
	_check("beam hidden at start", not light.visible)

	_press_l(main)
	await process_frame
	_check("first L press turns it on", flashlight.is_on())
	_check("beam visible once on", light.visible)

	_press_l(main)
	await process_frame
	_check("second L press turns it back off", not flashlight.is_on())
	_check("beam hidden once off", not light.visible)

	_press_l(main)
	await process_frame
	_check("on again for the focused-session check", flashlight.is_on())

	day_plan.trigger_fault()
	panel.interact()
	terminal.interact()
	terminal.interact()
	carry.pick_up(wire)
	terminal.interact()
	await process_frame
	_check("focused session is actually active", focused.is_active())
	_check("on/off state preserved while focused", flashlight.is_on())
	_check("beam hidden while focused (hands occupied)", not light.visible)

	_press_l(main)
	await process_frame
	_check("L press while focused is ignored (state unchanged)", flashlight.is_on())

	focused.end()
	await process_frame
	_check("still on after focus ends (state was preserved, not reset)", flashlight.is_on())
	_check("beam visible again once focus ends", light.visible)

	main.queue_free()
	await process_frame

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _press_l(main: Node) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_L
	ev.pressed = true
	main.get_viewport().push_input(ev)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
