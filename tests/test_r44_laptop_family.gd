extends SceneTree
## Round 44 Priorities 1-5 / 14: the personal laptop.
##  - the WHOLE focused laptop holds gameplay time (desktop, Today,
##    messages, journal, files, games), switching apps keeps it held,
##    leaving resumes with no jump; focus is refused during an emergency
##    and an emergency starting during focus ends it; never saved;
##  - one place per kind of information (Today absorbs Schedule; shift
##    reports are archived files; Journal holds private notes);
##  - the automatic journal: real events only, no duplicates, private
##    notes (the old typed log) preserved;
##  - family letters with replies: next-day answers by choice, no double
##    send, honest options (no anomaly talk before an anomaly was seen),
##    save/load never rerolls;
##  - the screen renders at 2x and clicks land on the visible button.
var _ok := true
var main: Node
var dp: Node
var scr: SubViewport
var ss: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	ss = main.get_node("SleepState")
	scr = main.find_child("LaptopView", true, false)._log_screen
	await _focus_pause()
	await _structure()
	await _journal()
	await _family()
	await _resolution()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _enter_focus() -> void:
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	for i in 4: await physics_frame
	ss.begin_sitting()
	await create_timer(2.0).timeout
	ss.open_laptop(false)
	await create_timer(2.4).timeout
	ss.begin_editing()
	await create_timer(1.2).timeout


func _focus_pause() -> void:
	await _enter_focus()
	_check("focused laptop (via the bunk): gameplay time held under 'laptop'", ss.is_editing() and dp.is_held(&"laptop"))
	for app in [&"home", &"note", &"messages", &"journal", &"files", &"photos", &"game", &"holdout"]:
		scr.open_app(app)
		await process_frame
		var a: float = dp.shift_elapsed_s
		var o: float = float(main.get_node("Equipment/OrbitalCycle")._clock_s())
		await create_timer(0.35).timeout
		_check("%s: shift clock + orbit frozen" % app, dp.shift_elapsed_s == a and float(main.get_node("Equipment/OrbitalCycle")._clock_s()) == o and dp.is_held(&"laptop"))
	var env: Node = main.get_node("EnvironmentModel")
	var o2: float = env.o2_kpa
	await create_timer(0.4).timeout
	_check("ordinary environment drift paused while focused", env.o2_kpa == o2)
	scr.open_app(&"home")
	ss.end_editing()
	await create_timer(1.0).timeout
	var b: float = dp.shift_elapsed_s
	await create_timer(0.4).timeout
	_check("focus left: time resumes cleanly (+%.2f s in 0.4 s)" % (dp.shift_elapsed_s - b), not dp.is_held(&"laptop") and dp.shift_elapsed_s - b > 0.2 and dp.shift_elapsed_s - b < 0.6)
	# Emergency: zoom-in refused.
	dp.fire_emergency("overload", 7)
	await process_frame
	ss.begin_editing()
	await process_frame
	_check("during an emergency: focused laptop use is refused", not ss.is_editing() and not dp.is_held(&"laptop"))
	main.get_node("Equipment/PowerDistribution").load_dict({"demand": [2, 2, 2], "setting": [2, 2, 2], "verified": true})
	dp.emergency_plan = {}
	await process_frame
	ss.begin_editing()
	await create_timer(1.0).timeout
	_check("emergency over: focus allowed again", ss.is_editing() and dp.is_held(&"laptop"))
	dp.fire_emergency("overload", 8)
	for i in 6: await process_frame
	_check("an emergency starting during focus ends the focus and restores time", not ss.is_editing() and not dp.is_held(&"laptop"))
	_check("...and the critical countdown is running (not frozen)", not main.get_node("StationStatus").emergency().is_empty() and not dp.clock_paused())
	main.get_node("Equipment/PowerDistribution").load_dict({"demand": [2, 2, 2], "setting": [2, 2, 2], "verified": true})
	dp.emergency_plan = {}
	await process_frame
	ss.begin_editing()
	await create_timer(1.0).timeout
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("a save taken during focus stores no hold", not JSON.stringify(data["day_plan"]).contains("laptop"))
	# Bedtime grace is paused too.
	dp.end_shift_now()
	var aw: float = dp.awake_after_shift_s
	await create_timer(0.5).timeout
	_check("bedtime grace paused while focused", dp.awake_after_shift_s == aw)
	ss.end_editing()
	await create_timer(0.8).timeout
	_check("...and resumes after", dp.awake_after_shift_s > aw)
	dp.reset_for_new_day()
	await create_timer(0.3).timeout


func _structure() -> void:
	var ids: Array = scr.APPS.map(func(a): return a[0])
	_check("desktop: Today, Shift Handover, Journal, Messages, Photos, Files, games", ids == [&"note", &"handover", &"journal", &"messages", &"photos", &"files", &"game", &"holdout"])
	_check("no Schedule / Shift Report / Personal Log icons competing with Today", not ids.has(&"schedule") and not ids.has(&"report") and not ids.has(&"log"))
	scr.set_editing(true)
	scr.open_app(&"note")
	var t: String = scr._report.text
	_check("TODAY: status (time + work %%), priority, checklist in one view", t.find("DAY %d ·" % dp.day_number) != -1 and t.find("WORK") != -1 and t.find("Priority:") != -1 and t.find("TODAY") != -1)
	scr.open_app(&"schedule")
	_check("old Schedule id opens TODAY", scr.current_view() == &"note")
	scr.open_app(&"report")
	_check("old Shift Report id opens the archived report file", scr.current_view() == &"file" and scr.open_file.begins_with("Work/Archived Reports/shift_report_day_"))
	scr.open_app(&"files")
	scr.open_entry({"kind": "dir", "target": "Work/Archived Reports"})
	await process_frame
	var names: Array = []
	for b in scr._files_box.get_child(1).get_children():
		names.append((b as Button).text)
	_check("archive lists this rotation's shift reports (%d entries)" % names.size(), names.any(func(n): return String(n).begins_with("shift_report_day_")))
	_check("DayPlan stays the only work authority (TODAY reads order_rows)", load("res://scripts/ui/daily_note.gd").build(dp, null)["items"].any(func(it): return it["id"] == "work"))
	scr.open_app(&"home")


func _journal() -> void:
	var j: Node = main.get_tree().get_first_node_in_group(&"journal")
	var se: Node = main.get_node("StoryEvents")
	var n0: int = j.entries.size()
	dp.end_shift_now()
	dp.reset_for_new_day()
	await process_frame
	_check("a finished day writes a dated first-person entry", j.entries.size() == n0 + 1 and String(j.entries.back()["key"]).begins_with("shift:"))
	dp.order_closed.emit(&"vent")
	_check("first job of a kind -> its entry", j.has("first:vent"))
	var n1: int = j.entries.size()
	dp.order_closed.emit(&"vent")
	scr.set_editing(true)
	scr.open_app(&"journal")
	scr.open_app(&"journal")
	_check("no duplicates (same event twice, reopening the app)", j.entries.size() == n1)
	_check("no false memories: no anomaly entry without a seen anomaly", not j.entries.any(func(e): return String(e["kind"]) == "odd"))
	se.observe("phantom_cycle", "test")
	_check("a SEEN anomaly writes its observation entry", j.has("obs:phantom_cycle") and String(j.entries.back()["text"]).find("airlock") != -1)
	se.evidence = []
	var sd: Dictionary = JSON.parse_string(JSON.stringify(j.state_dict()))
	j.load_dict(sd)
	j.load_dict(sd)
	_check("save/load: entries kept, never doubled", j.entries.size() == n1 + 1)
	var lv: Node = main.find_child("LaptopView", true, false)
	lv._saved_entry = "Typed by the player, day 3."
	scr.show_entry(lv._saved_entry)
	scr._on_app(&"journal_notes")
	_check("the old Personal Log lives on as PRIVATE NOTES, untouched", scr.current_view() == &"log" and scr.get_entry_text() == "Typed by the player, day 3.")
	scr.open_app(&"journal")
	_check("Journal view shows entries newest first", scr._report.text.find("JOURNAL") == 0 and scr._report.text.find("DAY") != -1)
	scr.open_app(&"home")


func _family() -> void:
	var fm: Node = main.get_tree().get_first_node_in_group(&"family_mail")
	var se: Node = main.get_node("StoryEvents")
	se.evidence = []
	dp.day_number = 2
	_check("Mara's letter arrives on day 2", fm.arrived("mara_eating") and fm.state("mara_eating") == "unread")
	_check("the 'distracted' letter does not arrive before any anomaly was seen", not fm.arrived("mara_distracted"))
	scr.set_editing(true)
	scr.mail_open = ""
	scr.open_app(&"messages")
	scr.open_thread("mara_eating")
	var opts: Array = scr._mail_opts.get_children()
	_check("2-4 reply options shown as buttons (%d)" % opts.size(), opts.size() >= 2 and opts.size() <= 4)
	(opts[1] as Button).pressed.emit()
	_check("reply recorded (B) in the thread", fm.state("mara_eating") == "replied" and fm.threads["mara_eating"]["choice"] == "B" and scr._mail_text.text.find("You (day 2)") != -1)
	_check("no second send", not fm.reply("mara_eating", "A") and fm.threads["mara_eating"]["choice"] == "B")
	_check("answer not yet delivered on the same day", not fm.answer_delivered("mara_eating"))
	dp.day_number = 3
	_check("next day: the answer for B arrives (Pip by the door)", fm.answer_delivered("mara_eating") and fm.answer_text("mara_eating").find("Pip") != -1)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(fm.state_dict()))
	fm.load_dict({})
	fm.load_dict(sd)
	_check("save/load: same choice, same answer, scheduled day kept", fm.threads["mara_eating"]["choice"] == "B" and int(fm.threads["mara_eating"]["answer_day"]) == 3 and fm.answer_delivered("mara_eating"))
	se.observe("corridor_presence", "seen")
	dp.day_number = 4
	_check("after a seen anomaly the 'distracted' letter arrives (next day)", fm.arrived("mara_distracted"))
	_check("...with the honest option to mention it", fm.options("mara_distracted").any(func(o): return String(o["text"]).find("strange") != -1))
	_check("hiding it is a valid choice", fm.reply("mara_distracted", "C") and fm.option_text("mara_distracted", "C").find("rather not") != -1)
	_check("sent letters = the authentic record", "\n".join(fm.sent_lines()).find("Pip") == -1 and "\n".join(fm.sent_lines()).find("miss home") != -1)
	se.evidence = []
	dp.day_number = 1
	scr.open_app(&"home")


func _resolution() -> void:
	_check("laptop renders at 2x (960x560) for a 480x280 layout", scr.size == Vector2i(960, 560) and scr.layout_size() == Vector2(480, 280))
	scr.set_editing(true)
	scr.open_app(&"home")
	await process_frame
	await process_frame
	var b: Button = scr.button(&"files")
	var uv: Vector2 = scr.uv_of(b)
	scr.click_at(uv)
	await process_frame
	_check("click at the visible Files icon (uv %s) opens Files" % uv, scr.current_view() == &"files")
	scr.open_app(&"home")
	await process_frame
	var miss: Vector2 = scr.uv_of(scr.button(&"photos")) + Vector2(0.0, 0.45)
	scr.click_at(Vector2(clampf(miss.x, 0, 1), clampf(miss.y, 0, 0.99)))
	await process_frame
	_check("a click on empty desktop below the icons opens nothing", scr.current_view() == &"home")
	scr.hover_at(scr.uv_of(scr.button(&"journal")))
	await process_frame
	_check("hover lands on the icon under the cursor", scr.button(&"journal").is_hovered())
	scr.set_editing(false)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
