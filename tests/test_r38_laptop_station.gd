extends SceneTree
## Round 38: laptop computer (zoom keeps every app, folders/files, photos,
## Cargo Drop), workstation CAMERAS tab, technician proficiency, interior
## decor obeying power, quarters activities.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true
var main: Node
var dp: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	await _laptop()
	await _cameras_tab()
	_proficiency()
	await _decor()
	await _quarters()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _laptop() -> void:
	var lv: Node = main.get_node("Player/LaptopView")
	var scr: Node = lv._log_screen
	# Round 44: Schedule / Shift Report folded into TODAY / Files, Personal
	# Log into JOURNAL (private notes) -- the desktop shows the new set.
	_check("desktop shows every app icon", [&"note", &"journal", &"messages", &"photos", &"files", &"game", &"holdout", &"handover"].all(func(a): return scr.button(a) != null and scr.button(a).is_visible_in_tree()))
	# ZOOM BUG (root cause: zoom == the log editor): zoomed, every app stays.
	scr._pending_app = &"messages"
	scr.set_editing(true)
	_check("zooming in on an app shows THAT app (Messages), not the log", scr.is_zoomed() and scr.current_view() == &"messages")
	scr._on_app(&"home")
	_check("zoomed: the desktop with all apps is reachable", scr.current_view() == &"home" and scr.button(&"files").is_visible_in_tree())
	scr._on_app(&"log")
	_check("zoomed: the Personal Log opens editable", scr.current_view() == &"log" and scr._entry_field.editable)
	scr._on_app(&"home")
	_check("leaving the log: entry no longer editable", not scr._entry_field.editable)
	# Files: folders and files.
	scr._on_app(&"files")
	await process_frame
	_check("Files: the six top folders", scr._files_box.get_child_count() == 2 and scr._files_box.get_child(1).get_child_count() == 6)
	# Round 43: "Documents" became Work/ with subfolders (Training, Station
	# Procedures, Shift Handover, Archived Reports) + its own 2 files.
	scr.open_entry({"kind": "dir", "target": "Work"})
	await process_frame
	_check("open Work/ (.. + 4 subfolders + 2 files)", scr.folder == "Work" and scr._files_box.get_child(1).get_child_count() == 7)
	var doc: Dictionary = scr.Files.list("Work")[0]
	scr.open_entry({"kind": "txt", "rec": doc})
	_check("open a text file: '%s'" % scr.open_file, scr.current_view() == &"file" and scr._report.text.find("ROTATION SUMMARY") != -1)
	scr._on_app(&"files")
	scr.open_entry({"kind": "dir", "target": "Photos"})
	scr.open_entry({"kind": "img", "rec": scr.Files.list("Photos")[2]})
	_check("open a photo from Files -> Photos viewer at that photo (%s)" % scr._photo_caption.text, scr.current_view() == &"photos" and scr._photo_caption.text.find("Pip") != -1)
	var tex: Texture2D = scr._photo.texture
	_check("photos are original images generated in-project (%dx%d)" % [tex.get_width(), tex.get_height()], tex is ImageTexture and tex.get_width() == 200)
	scr._on_app(&"photo_next")
	_check("next photo", scr._photo_caption.text.find("Coast") != -1)
	# Cargo Drop: a real playable loop.
	scr._on_app(&"files")
	scr.open_entry({"kind": "dir", "target": "Entertainment"})
	scr.open_entry({"kind": "app", "rec": scr.Files.list("Entertainment")[0]})
	var g: Node = scr._game
	_check("Cargo Drop opens from Entertainment/", scr.current_view() == &"game" and g.is_visible_in_tree())
	var x0: int = g.piece_pos.x
	g.action("left")
	_check("move left by button", g.piece_pos.x == x0 - 1)
	var e := InputEventKey.new()
	e.keycode = KEY_RIGHT
	e.pressed = true
	g._gui_input(e)
	_check("move right by keyboard", g.piece_pos.x == x0)
	# Fill a row by hand -> it ships and scores.
	g.restart()
	for c in g.COLS:
		g.grid[g.ROWS - 1][c] = 0
	g.grid[g.ROWS - 1][0] = -1
	g.piece = [Vector2i(0, 0)]
	g.piece_pos = Vector2i(0, 0)
	g.action("drop")
	# Round 41: score = 100 x level for the row + the hard-drop bonus (2/row fallen).
	_check("a full row is shipped (score %d)" % g.score, g.score == 100 + 2 * (g.ROWS - 1) and g.grid[g.ROWS - 1].all(func(v): return int(v) == -1))
	_check("best score kept (%d)" % scr.game_best, scr.game_best >= 100)
	g.action("exit")
	_check("Exit returns to the desktop", scr.current_view() == &"home")
	scr.set_editing(false)
	_check("zooming out keeps the computer usable (desktop)", not scr.is_zoomed() and scr.current_view() == &"home")
	# Save / load: read messages + game best.
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r38_laptop.json"
	sg.save_game()
	scr.game_best = 0
	sg.apply_state(sg.read_save()["data"])
	_check("load restores the game's best score", scr.game_best >= 100)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r38_laptop.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r38_laptop.json.bak"))


func _cameras_tab() -> void:
	var screen: SubViewport = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var shell: Control = screen.shell
	var net: Node = main.get_node("CameraNetwork")
	_check("four workstation sections: OPERATIONS / CAMERAS / RECORDS / SYSTEM", shell.tab_buttons.map(func(b): return b.text) == ["OPERATIONS", "CAMERAS", "RECORDS", "SYSTEM"])
	var ws: Node = main.get_node("WorkstationState")
	ws.begin_use()
	await create_timer(1.6).timeout
	await _click(screen, shell.tab_buttons[1])
	_check("CAMERAS tab by click", shell.page == shell.Page.CAMERAS)
	_check("Round 42: the 7 curated cameras listed as buttons (EXT-01 retired)", shell.cam_buttons.size() == 7 and not shell.cam_buttons.has("EXT-01"))
	await _click(screen, shell.cam_buttons["EXT-03"])
	_check("click EXT-03: selected, its LIVE feed shown", shell.selected_cam == "EXT-03" and shell._feed.texture == net.feed("EXT-03") and shell._cam_info.text.find("OBSERVATION") != -1)
	_check("only the shown camera renders", net.is_rendering("EXT-03") and not net.is_rendering("EXT-02"))
	await _click(screen, shell.cam_buttons["INT-04"])
	_check("switch to INT-04 ENGINEERING", shell.selected_cam == "INT-04" and net.is_rendering("INT-04") and not net.is_rendering("EXT-03"))
	screen.show_section(screen.Section.SURVEILLANCE)
	_check("[4] key path opens CAMERAS", shell.page == shell.Page.CAMERAS)
	await _click(screen, shell.action_buttons["back_to_map"])
	_check("MAP returns to Operations; the feed stops rendering", shell.page == shell.Page.OPS and not net.is_rendering("INT-04"))
	ws.end_use()
	await create_timer(1.5).timeout


func _proficiency() -> void:
	_check("new technician: all families Trainee", dp.FAMILIES.all(func(f): return dp.proficiency_level(f) == 0))
	dp._order_seq += 1
	var o := {"id": "WO-P1", "type": "vent", "category": "B", "priority": 2, "day": dp.day_number, "seed": 3, "status": "open", "carried_from": -1}
	dp.orders.append(o)
	var vent: Node = main.get_node("Equipment/VentGrille")
	vent.order_rearm(3)
	vent.dirt = [0.0, 0.0, 0.0, 0.0]
	vent.airflow_checked = true
	vent.clips_released = [false, false]
	vent.cover_open = false
	dp._poll_orders()
	_check("closing a real order credits its family (life support 1)", dp.proficiency_level("life_support") == 1)
	dp._poll_orders()
	dp.credit("WO-P1", ["life_support"])
	_check("no double counting", dp.proficiency_level("life_support") == 1)
	_check("rank names", dp.rank_name(0) == "Trainee" and dp.rank_name(4) == "Qualified")
	dp.proficiency["electrical"] = 0
	dp.day_number = 5
	var any := false
	for d in range(5, 60):
		dp.day_number = d
		dp.plan_emergency()
		any = any or not dp.emergency_plan.is_empty()
	_check("no emergencies before any electrical experience", not any)
	dp.proficiency["electrical"] = 1
	for d in range(5, 60):
		dp.day_number = d
		dp.plan_emergency()
		any = any or not dp.emergency_plan.is_empty()
	_check("...emergencies possible once practised", any)
	dp.day_number = 1
	dp.emergency_plan = {}


func _decor() -> void:
	var decor: Node = main.get_node("StationDecor")
	_check("interior structure: %d ribs, %d decor parts, %d light strips" % [decor.rib_count, decor.decor_count, decor.strips.size()], decor.rib_count > 10 and decor.strips.size() > 20)
	var cols := 0
	for n in decor.find_children("*", "CollisionObject3D", true, false):
		cols += 1
	_check("decor has NO collision (navigation untouched)", cols == 0)
	var br: Node = main.get_node("Equipment/BreakerPanel")
	await create_timer(0.6).timeout
	_check("Life Support strips lit when powered", decor.strip_lit(&"life_support"))
	br.trip(1, "surge")
	await create_timer(0.6).timeout
	_check("...and dark when B-02 trips (obey their circuit)", not decor.strip_lit(&"life_support"))
	br.on_part(&"b1")
	await create_timer(0.6).timeout
	_check("...lit again after reset", decor.strip_lit(&"life_support"))


func _quarters() -> void:
	var q: Node = main.get_node("Equipment/QuartersLife")
	q.on_part(&"meal")
	await create_timer(q.EAT_S + 0.4).timeout     # Round 39: the eat gesture plays first
	_check("meal (Round 39: after the eating gesture): logged, once per day", q.meal_day == dp.day_number)
	q.on_part(&"meal")
	q.brewing = 3.1
	q._process(0.0)
	_check("tea made: mug on the counter", q.tea_day == dp.day_number and q._mug.visible)
	q.on_part(&"mug")
	_check("drink it: mug gone", not q._mug.visible)
	await create_timer(q.DRINK_S + 0.4).timeout
	var sd: Dictionary = q.state_dict()
	q.load_dict({})
	q.load_dict(sd)
	_check("activities persist for the day", q.tea_day == dp.day_number and q.drank_day == dp.day_number)


func _click(screen: SubViewport, c: Control) -> void:
	screen.shell.refresh()
	await process_frame
	# Round 42: the monitor renders at 2x its 640x400 layout; a real click
	# arrives in RENDER pixels (uv * size), so map layout units through the
	# viewport's stretch transform.
	var p: Vector2 = screen.get_final_transform() * c.get_global_rect().get_center()
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
