extends SceneTree
## Round 48 Priorities 23-27: the dedicated SHIFT HANDOVER laptop app.
##  - the desktop shortcut opens its own reader (no Files browser, no path /
##    breadcrumb): entry header, historical date, author line, NEW / READ;
##  - < PREVIOUS / NEXT > through the archive in chronological order (the
##    previous technician's shift notes, then the handover note written for
##    the incoming technician); ends are disabled, never wrap;
##  - released by game day (day k: notes 1..k), older ones stay, future ones
##    are never listed, all dated in the previous rotation (2026-09);
##  - read flags are the same saved handover_read (save/load), the handover
##    note is still the story discovery, the Files folder lists the same
##    records (no second copy);
##  - Simplified Chinese chrome + text, wraps inside the screen.
var _ok := true
var main: Node
var dp: Node
var scr: Node
var se: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	dp = main.get_node("DayPlan")
	se = main.get_node("StoryEvents")
	scr = main.get_node("Player/LaptopView")._log_screen
	main.get_node("StationAI").set_enabled(false)
	_app()
	_progression()
	await _language()
	_save_load()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _press(id: StringName) -> void:
	(scr.button(id) as Button).pressed.emit()


func _app() -> void:
	var Files: Script = scr.Files
	dp.day_number = 3
	scr.handover_read = {}
	scr.set_editing(true)
	scr._on_app(&"handover")
	_check("the shortcut opens the dedicated app (view '%s'), not Files" % scr.current_view(), scr.current_view() == &"handover" and scr._handover_box.visible and not scr._files_box.visible and not scr._report.visible)
	var shown: String = scr._ho_head.text + scr._ho_meta.text + scr._ho_text.text
	_check("no file path / breadcrumb on screen", shown.find("Work/") == -1 and shown.find(".txt") == -1 and shown.find("/Shift") == -1)
	_check("opens on the handover note first (unread): '%s'" % scr._ho_head.text, scr._ho_head.text.contains("HANDOVER NOTE") and scr._ho_text.text.contains("Welcome aboard"))
	_check("...which is the story discovery, as before", se.investigations.has("_handover_early") or se.has_milestone("handover_read"))
	var es: Array = scr.handover_entries()
	_check("archive on day 3: 3 shift notes + the handover note (%d)" % es.size(), es.size() == 4)
	_check("chronological: shift notes oldest first, then the handover note", int(es[0]["idx"]) == 1 and int(es[1]["idx"]) == 2 and int(es[2]["idx"]) == 3 and int(es[3]["idx"]) == 0 and String(es[0]["date"]) < String(es[2]["date"]) and String(es[2]["date"]) < String(es[3]["date"]))
	_check("NEXT disabled at the newest entry", (scr.button(&"handover_next") as Button).disabled)
	_press(&"handover_prev")
	_check("PREVIOUS -> entry 03 (today's), header + date + author + NEW (%s / %s)" % [scr._ho_head.text, scr._ho_meta.text], scr._ho_head.text.contains("ENTRY 03") and scr._ho_meta.text.contains("2026-09-17") and scr._ho_meta.text.contains("R.V.") and scr._ho_meta.text.contains("NEW"))
	_check("...and it is now marked read", scr.handover_read.has(3))
	_press(&"handover_prev")
	_press(&"handover_prev")
	_check("back to entry 01; PREVIOUS disabled at the oldest (%s)" % scr._ho_pos.text, scr._ho_head.text.contains("ENTRY 01") and (scr.button(&"handover_prev") as Button).disabled and scr._ho_pos.text == "1 / 4")
	_press(&"handover_prev")
	_check("never wraps past the ends", scr._ho_head.text.contains("ENTRY 01"))
	_press(&"handover_next")
	_check("NEXT -> entry 02", scr._ho_head.text.contains("ENTRY 02"))
	scr._on_app(&"handover")
	_check("re-opening with all read: the newest entry, marked READ", scr._ho_meta.text.contains("READ") and scr.handover_unread() == 0)
	_check("home button available (clear Back/Home)", (scr.button(&"home") as Button).visible)
	# Same records as Files (one authoritative collection).
	var n_welcome := 0
	for k in Files.FILES:
		for r in Files.FILES[k]:
			if String(r.get("story", "")) == "handover_read":
				n_welcome += 1
	_check("no duplicate handover documents (%d)" % n_welcome, n_welcome == 1)
	scr.folder = Files.HANDOVER_PATH
	scr._show_view(&"files")
	var names: Array = []
	for b in scr._files_box.find_children("Entry_*", "Button", true, false):
		names.append((b as Button).text)
	_check("the Files folder still lists the same notes (%d entries)" % names.size(), names.any(func(n): return String(n).contains("shift_note_03")))
	scr.open_app(&"home")


func _progression() -> void:
	var Files: Script = scr.Files
	for d in [1, 2, 5, 10, 14]:
		dp.day_number = d
		var es: Array = scr.handover_entries()
		var notes: Array = es.filter(func(e): return int(e["idx"]) > 0)
		_check("day %d: %d shift notes released, none from the future" % [d, notes.size()], notes.size() == mini(d, Files.HANDOVER_NOTES.size()) and notes.all(func(e): return int(e["idx"]) <= d))
	_check("every note dated in the previous rotation (2026-09)", Files.handover_archive(14).filter(func(e): return int(e["idx"]) > 0).all(func(e): return String(e["date"]).begins_with("2026-09")))
	# Catching up after skipped days: oldest unread first (after today's).
	dp.day_number = 5
	scr.handover_read = {0: true, 1: true, 5: true}
	scr.set_editing(true)
	scr._on_app(&"handover")
	_check("skipped days: opens on the oldest unread (%s)" % scr._ho_head.text, scr._ho_head.text.contains("ENTRY 02"))
	scr.handover_read = {0: true}
	scr._on_app(&"handover")
	_check("today's newly released note comes first when unread (%s)" % scr._ho_head.text, scr._ho_head.text.contains("ENTRY 05"))
	scr.open_app(&"home")


func _language() -> void:
	var GS: Script = load("res://scripts/station/game_settings.gd")
	var lang0: String = String(GS.get_value("language"))
	GS._values["language"] = "zh_CN"
	dp.day_number = 3
	var read0: Dictionary = scr.handover_read.duplicate()
	scr.set_editing(true)
	scr._on_app(&"handover")
	scr.handover_index = 1
	scr._render_handover()
	_check("Chinese: header / buttons / text (%s | %s)" % [scr._ho_head.text, scr._ho_text.text.left(16)], scr._ho_head.text.contains("第 02 条") and (scr.button(&"handover_next") as Button).text.contains("下一条") and scr._ho_text.text.contains("通讯"))
	_check("switching language changes no story gating / read state", scr.handover_entries().size() == 4 and scr.handover_read.keys().all(func(k): return read0.has(k) or int(k) in [2, 3]))
	await process_frame
	await process_frame
	var box: Control = scr._handover_box
	var txt: Label = scr._ho_text
	_check("the text wraps inside the screen (%.0f <= %.0f px)" % [txt.size.x, box.size.x], txt.autowrap_mode != TextServer.AUTOWRAP_OFF and txt.size.x <= box.size.x + 1.0 and txt.get_line_count() >= 2)
	GS._values["language"] = lang0
	scr.open_app(&"home")


func _save_load() -> void:
	scr.handover_read = {0: true, 2: true}
	var data: Dictionary = JSON.parse_string(JSON.stringify(main.get_node("SaveGame").collect_state()))
	_check("read flags are saved", Array(data["laptop"]["handover_read"]).map(func(x): return int(x)).has(2))
	scr.handover_read = {}
	main.get_node("SaveGame").apply_state(data)
	_check("...and restored on load (%s)" % str(scr.handover_read.keys()), scr.handover_read.has(2) and scr.handover_read.has(0))
	scr.set_editing(false)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
