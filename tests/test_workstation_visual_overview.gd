extends SceneTree
## Coverage for this milestone's Workstream C: the Overview section's
## paragraph-of-subsystem-text was replaced with a row of status
## lights, and the Diagnostics section gained a small terminal-status
## light pairing alongside its existing (unchanged) evidence text. Both
## are driven by real DayPlan/panel state, not invented readings.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var console := main.get_node("Interactables/WorkstationConsole")
	var screen := console.get_node("WorkstationScreen")
	var day_plan := main.get_node("DayPlan")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)

	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	free_body.sync_to_eye_position(console_pos)
	player.global_position = console_pos
	console.interact()
	await create_timer(1.0).timeout

	screen.show_section(screen.Section.OVERVIEW)
	await create_timer(0.05).timeout
	var lights := screen.get_node("Control/VBox/Content/Overview/StatusLights")
	_check("overview no longer has the old text paragraph node", screen.get_node("Control/VBox/Content/Overview").get_node_or_null("Rows") == null)
	_check("status lights row exists", lights != null)
	_check("status lights row has all eight subsystem indicators", lights.get_child_count() == 8)
	for child in lights.get_children():
		var light: ColorRect = child.get_node("Light")
		_check("%s light reads a real color (not unset/black)" % child.name, light.color != Color(0, 0, 0, 0))

	screen.show_section(screen.Section.DIAGNOSTICS)
	await create_timer(0.05).timeout
	var terminal_lights := screen.get_node("Control/VBox/Content/Diagnostics/TerminalLights")
	_check("terminal lights hidden before any diagnostic has run", not terminal_lights.visible)

	day_plan.mark_done(&"c02")
	day_plan.trigger_fault()
	screen.show_section(screen.Section.DIAGNOSTICS)
	await create_timer(0.05).timeout
	_check("terminal lights visible once a fault exists", terminal_lights.visible)
	var t1_light: ColorRect = terminal_lights.get_node("T1/Light")
	var t2_light: ColorRect = terminal_lights.get_node("T2/Light")
	_check("T-1 (nominal terminal) light is green", t1_light.color.g > t1_light.color.r)
	_check("T-2 (faulted terminal) light is red", t2_light.color.r > t2_light.color.g)
	_check("diagnostic evidence text is still present (visual pairing, not a replacement)", screen.get_node("Control/VBox/Content/Diagnostics/Status").text.findn("Terminal T-2") != -1)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
