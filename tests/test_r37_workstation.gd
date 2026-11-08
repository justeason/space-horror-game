extends SceneTree
## Round 37 Priorities 7-9: the map-first, three-section, clickable
## workstation. All clicks are REAL mouse events pushed into the screen's
## SubViewport at the button's position (as the seated cursor does); the
## seated cursor -> monitor ray mapping is checked separately.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true
var main: Node
var dp: Node
var screen: SubViewport
var shell: Control
var stn: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	screen = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	shell = screen.shell
	stn = main.get_node("StationStatus")
	_check("four visible sections (Round 38: OPERATIONS / CAMERAS / RECORDS / SYSTEM)", shell.tab_buttons.size() == 4 and shell.tab_buttons.map(func(b): return b.text) == ["OPERATIONS", "CAMERAS", "RECORDS", "SYSTEM"])
	_check("the old seven-section layout is not shown", not screen.get_node("Control").visible)
	_check("Operations (map) is the default page", shell.page == shell.Page.OPS and shell._map.visible)
	_check("map has all eight rooms of the real topology", shell.room_buttons.size() == 8)
	# Day 1: check in from the map page, by clicking.
	_check("CHECK IN button offered before check-in", shell.action_buttons["checkin"].visible)
	_check("map: Control Room ROUTINE (orange) before check-in", stn.room_severity(&"control_room") == 1)
	await _click(shell.action_buttons["checkin"])
	_check("clicking CHECK IN checks in (c01) and assigns the first task", dp.is_task_done(&"c01") and dp.assignment_task_id == &"e06")
	_check("map: Engineering now ROUTINE (orange); Control clear", stn.room_severity(&"engineering") == 1 and stn.room_severity(&"control_room") == 0)
	# Several orders in one room: highest severity wins.
	_open(&"breaker", 1)       # trips a lighting breaker -> WARNING (Engineering)
	_open(&"thermal", 4)       # routine survey, next step in Control
	await process_frame
	_check("Engineering with routine + warning duties shows WARNING", stn.room_severity(&"engineering") == 2 and stn.rooms()[&"engineering"]["duties"].size() >= 2)
	dp.fire_emergency("overload", 2)
	await create_timer(0.3).timeout
	_check("an emergency makes Engineering EMERGENCY (red)", stn.room_severity(&"engineering") == 3)
	_check("the emergency strip shows on the workstation ('%s')" % shell._emerg.text, shell._emerg.visible and shell._emerg.text.find("POWER OVERLOAD") != -1)
	var red: Color = (shell.room_buttons[&"engineering"].get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	var orange_border: Color = (shell.room_buttons[&"control_room"].get_theme_stylebox("normal") as StyleBoxFlat).border_color
	_check("red room is visibly red (%s)" % str(red), red.r > red.g * 3.0)
	# Click a room -> its duties, one line each.
	await _click(shell.room_buttons[&"engineering"])
	_check("clicking Engineering selects it", shell.selected_room == &"engineering")
	_check("its duties listed one line each (%d)" % shell.duty_buttons.size(), shell.duty_buttons.size() >= 3 and shell.duty_buttons.all(func(b): return b.text.find("\n") == -1))
	await _click(shell.duty_buttons[0])
	_check("clicking a duty shows its details ('%s')" % shell._detail.text.left(60).replace("\n", " / "), shell._detail.text != "")
	await _click(shell.room_buttons[&"control_room"])
	_check("clicking another room switches selection", shell.selected_room == &"control_room")
	# Clear the emergency so it doesn't trip mid-test.
	var pw: Node = main.get_node("Equipment/PowerDistribution")
	pw.setting = pw.demand.duplicate()
	# Keyboard alternative still works: [3] diagnostics, [7] records.
	screen.show_section(screen.Section.DIAGNOSTICS)
	_check("[3] opens the diagnostic panel inside Operations", shell.page == shell.Page.OPS and shell._diag.visible)
	await _click(shell.action_buttons["diag"])
	_check("clicking DIAGNOSTIC again closes it", not shell._diag.visible)
	await _click(shell.tab_buttons[2])
	_check("RECORDS page by click (log shown)", shell.page == shell.Page.RECORDS and shell._records.text.find("TODAY") != -1)
	# SYSTEM: settings by click, save / load by click.
	await _click(shell.tab_buttons[3])
	_check("SYSTEM page by click", shell.page == shell.Page.SYSTEM)
	var rows: Array = screen.settings_rows()
	var ri: int = rows.map(func(r): return r[0]).find("invert_y")
	var before: bool = bool(GS.get_value("invert_y"))
	await _click(shell.setting_buttons[ri][0])
	_check("clicking a setting row changes it (invert Y %s -> %s)" % [before, GS.get_value("invert_y")], bool(GS.get_value("invert_y")) != before)
	await _click(shell.setting_buttons[ri][0])
	screen.show_section(screen.Section.SAVE_LOAD)
	_check("[5] opens SYSTEM (Save/Load lives there)", shell.page == shell.Page.SYSTEM)
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r37_ws.json"
	await _click(shell.action_buttons["save"])
	_check("clicking SAVE GAME saves ('%s')" % screen._save_status, FileAccess.file_exists("user://test_r37_ws.json") and screen._save_status.find("saved") != -1)
	# Seated cursor mapping: a window position over the monitor maps back to
	# the same SubViewport pixel.
	var ws: Node = main.get_node("WorkstationState")
	var console: Node = main.get_node("Interactables/WorkstationConsole")
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	ws.begin_use()
	await create_timer(1.6).timeout
	var target_uv := Vector2(0.73, 0.06)
	var wp: Vector2 = cam.unproject_position(console.screen_point(target_uv))
	var px: Variant = ws.screen_pixel_at(wp)
	_check("seated cursor -> monitor mapping round-trips (%s)" % str(px), px != null and (px as Vector2).distance_to(target_uv * Vector2(screen.size)) < 2.0)
	var b_sys: Button = shell.tab_buttons[0]
	var c_uv: Vector2 = b_sys.get_global_rect().get_center() / Vector2(screen.size)
	var wp2: Vector2 = cam.unproject_position(console.screen_point(c_uv))
	shell.show_page(shell.Page.SYSTEM)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = wp2
	ws._input(ev)
	var up: InputEventMouseButton = ev.duplicate()
	up.pressed = false
	ws._input(up)
	await process_frame
	_check("a seated click at OPERATIONS' place on the monitor presses it", shell.page == shell.Page.OPS)
	ws.end_use()
	await create_timer(1.5).timeout
	# LOAD through the clickable System page (safe deferred path).
	screen.show_section(screen.Section.SAVE_LOAD)
	await _click(shell.action_buttons["load"])
	for i in 12: await process_frame
	var newmain: Node = current_scene
	_check("LOAD GAME by click reloads the station safely (new scene, day %d)" % (newmain.get_node("DayPlan").day_number if newmain != null and newmain.has_node("DayPlan") else -1), newmain != null and newmain != main and newmain.has_node("DayPlan"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_ws.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_ws.json.bak"))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _open(t: StringName, seed: int) -> void:
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": String(t), "category": "B", "priority": int(dp.ORDER_TYPES[t]["priority"]), "day": dp.day_number, "seed": seed, "status": "open", "carried_from": -1})
	dp.order_equipment(t).order_rearm(seed)


## A real click on a control inside the workstation SubViewport.
func _click(c: Control) -> void:
	shell.refresh()
	await process_frame
	var p: Vector2 = c.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		screen.push_input(ev)
	await process_frame
	await process_frame


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
