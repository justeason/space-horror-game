extends SceneTree
## Round 43 Priorities 1 / 7 / 9-13 / 22: the shift clock and the laptop.
##  - personal GAMES (Cargo Drop, Holdout) hold the shift clock while played;
##    productivity apps do not; leaving resumes with no jump; never double
##    held; refused (and released) during a real emergency;
##  - a new day reads exactly 08:00 and stays there while lying in the bunk
##    (waking never consumes work time); it starts once the technician is up;
##  - desktop: SHIFT HANDOVER shortcut opens the ONE real record (story
##    discovery fires), TODAY'S NOTE with an auto-derived checklist, the
##    original grass-and-sky wallpaper at render resolution;
##  - Files: top folders + subfolders (Personal/Family, Work/...), new photos;
##  - the note anomaly is PRESENTATION ONLY: the Personal Log and the save
##    are untouched; the archive (History) contradicts it -> evidence.
var _ok := true
var main: Node
var dp: Node
var scr: SubViewport


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	scr = main.find_child("LaptopView", true, false)._log_screen
	await _clock_holds()
	await _new_day_0800()
	await _desktop_and_files()
	await _note_anomaly()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _clock_holds() -> void:
	# Round 44 Priority 1 supersedes the Round 43 games-only policy: the
	# WHOLE focused laptop holds gameplay time (any app); leaving focus
	# resumes it. (test_r44_laptop_family covers it in depth.)
	_check("day is active once nobody is lying in the bunk", dp.day_active and not dp.clock_paused())
	for app in [&"log", &"game", &"holdout"]:
		scr.set_editing(true)
		scr.open_app(app)
		await process_frame
		await process_frame
		var a: float = dp.shift_elapsed_s
		await create_timer(0.8).timeout
		_check("%s open on the focused laptop: shift clock held (%.3f -> %.3f)" % [app, a, dp.shift_elapsed_s], scr.entertainment_hold and dp.is_held(&"laptop") and absf(dp.shift_elapsed_s - a) < 0.0001)
		# Round 45: the station clock keeps running on the laptop (no PAUSED label).
		_check("%s: a normal running clock (no PAUSED label)" % app, scr._clock.text.find("PAUSED") == -1)
		scr.set_editing(false)
		await process_frame
		await process_frame
		var b: float = dp.shift_elapsed_s
		_check("focus left: hold released, no time jump (%.3f vs %.3f)" % [b, a], not dp.is_held(&"laptop") and b - a < 0.1)
		await create_timer(0.4).timeout
		_check("...and the clock runs again (single update, no double count)", dp.shift_elapsed_s > b + 0.2 and dp.shift_elapsed_s < b + 0.6)
	scr.set_editing(true)
	scr.open_app(&"holdout")
	await process_frame
	await process_frame
	# Zooming out / closing also releases.
	scr.open_app(&"holdout")
	await process_frame
	await process_frame
	scr.set_editing(false)
	await process_frame
	_check("zooming out of a game releases the hold", not dp.is_held(&"laptop"))
	# Emergency policy.
	scr.set_editing(true)
	dp.fire_emergency("overload", 3)
	await process_frame
	var ok: Dictionary = dp.entertainment_allowed()
	_check("during an emergency games are refused: '%s'" % ok["reason"], not ok["ok"] and String(ok["reason"]).find("ALERT") != -1)
	scr.open_app(&"holdout")
	await process_frame
	_check("opening Holdout during the emergency: refused, desktop shows the alert, no hold", scr.current_view() == &"home" and scr.blocked_reason != "" and not dp.is_held(&"laptop"))
	main.get_node("Equipment/PowerDistribution").load_dict({"demand": [2, 2, 2], "setting": [2, 2, 2], "verified": true})
	await process_frame
	scr.open_app(&"holdout")
	await process_frame
	await process_frame
	_check("emergency over: the game opens and holds the clock again", scr.current_view() == &"holdout" and dp.is_held(&"laptop"))
	scr.holdout.start_seeded(2)
	dp.fire_emergency("overload", 4)
	await process_frame
	await process_frame
	_check("an emergency starting MID-GAME pauses the game and releases the hold", scr.holdout.mode != "play" and not dp.is_held(&"laptop") and scr.current_view() == &"home")
	main.get_node("Equipment/PowerDistribution").load_dict({"demand": [2, 2, 2], "setting": [2, 2, 2], "verified": true})
	dp.emergency_plan = {}
	scr.open_app(&"home")
	scr.set_editing(false)
	await process_frame
	# Save/load never stores a hold.
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("holds are never saved", not JSON.stringify(data["day_plan"]).contains("_holds"))


func _new_day_0800() -> void:
	var ss: Node = main.get_node("SleepState")
	dp.end_shift_now()
	dp.reset_for_new_day()
	ss.start_day_in_bed()
	await create_timer(1.2).timeout
	_check("new day: exactly 08:00 while waking / lying (%s)" % dp.clock_text_hhmm(), dp.clock_text_hhmm() == "08:00" and dp.shift_elapsed_s == 0.0 and not dp.day_active)
	_check("the hold is reported as waking", &"waking" in dp.clock_hold_reasons())
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("autosave after waking records zero elapsed shift time", float(data["day_plan"]["shift_elapsed_s"]) == 0.0)
	ss._sit_up_then_get_up()
	await create_timer(2.5).timeout
	_check("up and about: the day is active, the clock runs from 08:00 (%s)" % dp.clock_text_hhmm(), dp.day_active and dp.shift_elapsed_s > 0.0 and dp.clock_minutes() < 8 * 60 + 10)


func _desktop_and_files() -> void:
	var Files = scr.Files
	_check("desktop: SHIFT HANDOVER and TODAY'S NOTE shortcuts", scr.APPS.any(func(a): return a[0] == &"handover") and scr.APPS.any(func(a): return a[0] == &"note"))
	var se: Node = main.get_node("StoryEvents")
	scr.set_editing(true)
	scr._on_app(&"handover")
	_check("the shortcut opens the ONE real handover record", scr.current_view() == &"file" and scr._report.text.find("HANDOVER NOTE") != -1 and scr.open_file == Files.HANDOVER_PATH + "/" + Files.HANDOVER_FILE)
	_check("reading it via the shortcut is the story discovery", se.investigations.has("_handover_early") or se.has_milestone("handover_read"))
	var n_handover := 0
	for k in Files.FILES:
		for r in Files.FILES[k]:
			if String(r.get("story", "")) == "handover_read":
				n_handover += 1
	_check("no duplicate / conflicting handover documents (%d)" % n_handover, n_handover == 1)
	scr.open_app(&"note")
	var txt: String = scr._report.text
	_check("TODAY'S NOTE: day, author, priority, checklist", txt.find("SHIFT NOTE · DAY %d" % dp.day_number) != -1 and txt.find("Ines") != -1 and txt.find("Priority:") != -1 and txt.find("[ ] Breakfast") != -1)
	var q: Node = main.get_node("Equipment/QuartersLife")
	q.meal_day = dp.day_number
	q.brush_day = dp.day_number
	scr.open_app(&"note")
	_check("checklist ticks itself from the real routine state", scr._report.text.find("[x] Breakfast") != -1 and scr._report.text.find("[x] Brush teeth") != -1 and scr._report.text.find("[ ] Dinner") != -1)
	var wp: Texture2D = scr._wallpaper.texture
	_check("wallpaper: original generated landscape at render resolution (%dx%d)" % [wp.get_width(), wp.get_height()], wp is ImageTexture and wp.get_width() >= 960 and wp.get_height() >= 540)
	var img: Image = wp.get_image()
	var sky: Color = img.get_pixel(480, 30)
	var hill: Color = img.get_pixel(400, 520)
	_check("blue sky above, green hill below", sky.b > sky.r + 0.2 and hill.g > hill.r + 0.15 and hill.g > hill.b + 0.15)
	_check("six top folders", Files.folders() == ["Personal", "Work", "Photos", "Messages", "Journal", "Entertainment"])
	_check("subfolders: Personal/{Family, Travel, Old Messages}", Files.subfolders("Personal") == ["Family", "Travel", "Old Messages"])
	_check("Work/ subfolders incl. Shift Handover and Archived Reports", Files.subfolders("Work").has("Shift Handover") and Files.subfolders("Work").has("Archived Reports"))
	scr.open_app(&"files")
	scr.open_entry({"kind": "dir", "target": "Personal/Family"})
	scr.open_entry({"kind": "up"})
	_check("'..' from a subfolder goes to its parent", scr.folder == "Personal")
	_check("new photos (childhood cat, hill picnic)", Files.list("Photos").size() == 7)
	scr.open_app(&"home")
	scr.set_editing(false)


func _note_anomaly() -> void:
	var se: Node = main.get_node("StoryEvents")
	var lv: Node = main.find_child("LaptopView", true, false)
	lv._saved_entry = "My own words. Nothing else."
	scr.show_entry(lv._saved_entry)
	se.story_phase = 2
	se.armed_for_day = -1
	se.debug_arm(&"note_extra_item")
	scr.set_editing(true)
	scr.open_app(&"note")
	_check("armed note anomaly: one extra checklist line on this opening", se.active == &"note_extra_item" and scr._report.text.find("corridor feed") != -1)
	_check("presentation only: the Personal Log text is untouched", scr.get_entry_text() == "My own words. Nothing else." and lv._saved_entry == "My own words. Nothing else.")
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("the save contains no altered document text", not JSON.stringify(data).contains("corridor feed before bed"))
	scr._on_app(&"note_history")
	_check("History: the archive shows the authentic note (no such line)", scr._report.text.find("edits since issue: none") != -1 and scr._report.text.find("corridor feed") == -1)
	_check("the record contradicts what was seen -> evidence + investigation", se.investigation_state("note_extra_item") == "contradicted" and se.investigations.has("note_extra_item"))
	scr.open_app(&"note")
	_check("opened again: the line is simply not there (event over, seen)", se.active == &"" and scr._report.text.find("corridor feed") == -1 and bool(se.state[&"note_extra_item"]["seen"]))
	var sd: Dictionary = JSON.parse_string(JSON.stringify(se.state_dict()))
	se.evidence = []
	se.load_dict(sd)
	_check("evidence survives save/load (%d entries)" % se.evidence.size(), se.evidence.size() >= 2 and se.investigation_state("note_extra_item") == "contradicted")
	se.dev_trigger(&"note_extra_item", "normal")
	scr.open_app(&"note")
	_check("developer preview shows the line on the next opening", scr._report.text.find("corridor feed") != -1)
	se.dev_cancel()
	scr.open_app(&"note")
	_check("developer cancel removes it", scr._report.text.find("corridor feed") == -1)
	scr.set_editing(false)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
