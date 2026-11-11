extends SceneTree
## Round 45 Priorities 13-27: laptop, workstation, basil, Holdout retheme.
##  - ONE close action (CLOSE LAPTOP) from any laptop state, autosaving the
##    private notes; no Save / Save & Back buttons;
##  - station clock keeps moving on the laptop (real pace, no PAUSED label)
##    while the shift budget is held; 08:00 -> ~23:00 over the active day;
##    past midnight wraps without a new day;
##  - interactive journal: any key writes a few characters of a page
##    composed from REAL events; Backspace / chords ignored; bounded; saved
##    with its typed position; never restarts;
##  - Today vs Journal: no diary in Today, no job list in Journal;
##  - handover archive: one note per day, unread badge, Today tick, saved;
##  - console toggles drive real state (diag detail, comms routing on the
##    real receiver, emergency-light test, room light, camera monitor);
##  - reduced Operations text; short diagnostic labels;
##  - basil watering is a real gesture with a watering-can prop;
##  - Holdout: space presentation, same mechanics, old saves load.
var _ok := true
var main: Node
var dp: Node
var ss: Node
var scr: SubViewport


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame
	dp = main.get_node("DayPlan")
	ss = main.get_node("SleepState")
	scr = main.find_child("LaptopView", true, false)._log_screen
	main.get_node("StationAI").set_enabled(false)
	await _close_and_clock()
	await _journal()
	_handover()
	await _toggles()
	await _basil()
	_holdout()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _focus() -> void:
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	for i in 4: await physics_frame
	ss.begin_sitting()
	await create_timer(2.0).timeout
	ss.open_laptop(false)
	await create_timer(2.4).timeout
	ss.begin_editing()
	await create_timer(1.2).timeout


func _key(k: int, uni: int = 0, ctrl: bool = false, echo: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.unicode = uni
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.echo = echo
	scr.journal_key(e)


func _close_and_clock() -> void:
	await _focus()
	_check("CLOSE LAPTOP is the one visible close control (no Save / Save & Back)", scr.button(&"close").visible and scr.button(&"close").text == "CLOSE LAPTOP" and not scr.button(&"save").visible and not scr.button(&"back").visible)
	scr.open_app(&"journal")
	var lv: Node = main.find_child("LaptopView", true, false)
	scr._on_app(&"journal_notes")
	scr.show_entry("A private note typed before closing.")
	var sh0: float = dp.shift_elapsed_s
	var lc0: float = dp.laptop_clock_s
	var m0: int = dp.clock_minutes()
	await create_timer(1.5).timeout
	_check("on the laptop: shift budget held (%.3f -> %.3f)" % [sh0, dp.shift_elapsed_s], dp.shift_elapsed_s == sh0)
	_check("...station clock keeps running at real pace (+%.2f s)" % (dp.laptop_clock_s - lc0), dp.laptop_clock_s - lc0 > 1.2 and dp.laptop_clock_s - lc0 < 1.8)
	_check("no PAUSED label on the laptop clock ('%s')" % scr._clock.text, scr._clock.text.find("PAUSED") == -1 and scr._clock.text.find(dp.clock_text_hhmm()) != -1)
	scr._on_app(&"close")
	await create_timer(2.0).timeout
	_check("CLOSE LAPTOP from the focused view closes the laptop", not ss.is_laptop_open() and not ss.is_editing())
	_check("...private notes saved automatically", String(lv._saved_entry) == "A private note typed before closing.")
	# After closing, the normal accelerated clock runs during the 2 s wait:
	# no more than that (+ the 1.5 s of real-pace laptop time) may pass.
	var rate: float = float(dp.CLOCK_DAY_SPAN_MIN) / dp.shift_duration_s()
	_check("...clock continuous, no jump / no backwards (%d -> %d, max +%d)" % [m0, dp.clock_minutes(), ceili(2.3 * rate) + 1], dp.clock_minutes() >= m0 and dp.clock_minutes() <= m0 + ceili(2.3 * rate) + 1)
	ss.end_sitting()
	await create_timer(2.6).timeout
	var dur: float = dp.shift_duration_s()
	var save_e: float = dp.shift_elapsed_s
	var save_l: float = dp.laptop_clock_s
	dp.laptop_clock_s = 0.0
	dp.shift_elapsed_s = 0.0
	_check("day starts 08:00", dp.clock_text_hhmm() == "08:00")
	dp.shift_elapsed_s = dur
	_check("end of the active day ~23:00 (%s)" % dp.clock_text_hhmm(), dp.clock_text_hhmm() == "23:00")
	dp.shift_elapsed_s = dur * 1.1
	var d0: int = dp.day_number
	_check("overtime past midnight wraps (%s) without a new day" % dp.clock_text_hhmm(), dp.clock_text_hhmm().begins_with("00:") and dp.day_number == d0)
	dp.shift_elapsed_s = save_e
	dp.laptop_clock_s = save_l
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("laptop clock offset is saved (no time drift on load)", data["day_plan"].has("laptop_clock_s"))


func _journal() -> void:
	var j: Node = main.get_tree().get_first_node_in_group(&"journal")
	var d: int = dp.day_number
	dp.order_closed.emit(&"vent")
	scr.set_editing(true)
	scr.open_app(&"journal")
	var p: Dictionary = j.pending_page(d)
	_check("today's page is composed from real events (vent job)", not p.is_empty() and String(p["text"]).find("vent grille") != -1 and int(p["typed"]) == 0)
	_check("journal invites typing", scr._report.text.find("type any keys") != -1)
	_key(KEY_Q, 113)
	_check("one key press writes a few characters (%d)" % int(p["typed"]), int(p["typed"]) == j.CHARS_PER_KEY)
	var t0: int = int(p["typed"])
	_key(KEY_BACKSPACE, 8)
	_key(KEY_S, 115, true)
	_check("Backspace and Ctrl+key never touch the text", int(p["typed"]) == t0)
	_check("the typed part appears on screen", scr._report.text.find(String(p["text"]).left(t0)) != -1)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(j.state_dict()))
	j.load_dict(sd)
	var p2: Dictionary = j.pending_page(d)
	_check("save/load resumes at the typed position (%d)" % int(p2["typed"]), int(p2["typed"]) == t0)
	for i in 400:
		_key(KEY_A + (i % 20), 97 + (i % 20))
	_check("bounded: the page completes (no infinite writing)", j.page_done(p2) and j.pending_page(d).is_empty())
	var len0: int = String(p2["text"]).length()
	_key(KEY_A, 97)
	_check("a finished entry is never restarted", int(p2["typed"]) == len0)
	_check("no false memory: no anomaly sentence without a seen anomaly", String(p2["text"]).find("airlock cycle") == -1 and String(p2["text"]).find("someone behind") == -1)
	scr.open_app(&"note")
	var today: String = scr._report.text
	scr.open_app(&"journal")
	var jtext: String = scr._report.text
	_check("Today is operational (no diary text)", today.find("vent grille") == -1 and today.find("Priority") != -1)
	_check("Journal is reflection (no job list)", jtext.find("Jobs:") == -1 and jtext.find("Priority") == -1)
	scr.set_editing(false)


func _handover() -> void:
	var Files = scr.Files
	dp.day_number = 1
	_check("day 1: one archived note released", Files.handover_records(1).size() == 1)
	_check("day 3: three; never all at once (%d of %d)" % [Files.handover_records(3).size(), Files.HANDOVER_NOTES.size()], Files.handover_records(3).size() == 3 and Files.HANDOVER_NOTES.size() >= 8)
	_check("notes are dated in the PREVIOUS rotation", Files.handover_records(10).all(func(r): return String(r["date"]).begins_with("2026-09")))
	scr.handover_read = {}
	dp.day_number = 2
	scr._refresh_unread()
	_check("unread badge on the desktop shortcut ('%s')" % scr.button(&"handover").text, scr.button(&"handover").text.find("(3)") != -1)
	_check("Today: 'Review handover' unticked", "\n".join(scr.daily_note_lines()).find("[ ] Review handover") != -1)
	scr.set_editing(true)
	scr._on_app(&"handover")
	_check("shortcut opens the welcome handover first", scr._report.text.find("HANDOVER NOTE") != -1)
	scr._on_app(&"handover")
	_check("...then today's newest note", scr._report.text.find("day 34") != -1 and scr.handover_read.has(2))
	_check("Today ticks 'Review handover' automatically", "\n".join(scr.daily_note_lines()).find("[x] Review handover") != -1)
	dp.day_number = 5
	scr._refresh_unread()
	_check("skipped days: earlier notes stay available (%d unread)" % scr.handover_unread(), scr.handover_unread() == 4)
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("read notes are saved", Array(data["laptop"]["handover_read"]).has(2))
	scr.set_editing(false)
	dp.day_number = 1


func _toggles() -> void:
	var tg: Node = main.get_tree().get_first_node_in_group(&"console_toggles")
	var sw_diag: Node = main.get_node("Interactables/WsSwitchPower")
	var sw_comms: Node = main.get_node("Interactables/WsSwitchComms")
	var sw_et: Node = main.get_node("Interactables/WsSwitchLifeSupport")
	var sw_l: Node = main.get_node("Interactables/WsSwitchLighting")
	var sw_m: Node = main.get_node("Interactables/ToggleSwitch")
	_check("switches relabelled for their real functions", sw_diag.switch_label == "Diag" and sw_et.switch_label == "E-Test" and sw_m.switch_label == "Monitor")
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen").shell
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	screen._run_c02()
	var short_t: String = screen._diagnostics_status.text
	sw_diag.interact()
	await process_frame
	screen._run_c02()
	var long_t: String = screen._diagnostics_status.text
	_check("DIAG: detail mode on the workstation (short '%s' / long)" % short_t.get_slice("\n", 2), shell.detail_mode() and long_t.find("Terminal T-1") != -1 and short_t.find("T1  24V") != -1)
	sw_diag.interact()
	var rx: Node = main.get_node("Equipment/CommsBackupReceiver")
	_check("COMMS starts on MAIN (switch on)", not rx.on_backup and sw_comms.is_on)
	sw_comms.interact()
	await process_frame
	_check("COMMS off -> the REAL receiver switches to backup", rx.on_backup and not sw_comms.is_on)
	rx.on_part(&"mode")
	await create_timer(0.3).timeout
	_check("flipping the rack lever moves the console switch too (one state)", not rx.on_backup and sw_comms.is_on)
	var el: Node = main.get_node("Equipment/JunctionEmergencyLights")
	sw_et.interact()
	await process_frame
	_check("E-TEST drives the real Junction emergency-light test", el.test_on and sw_et.is_on)
	sw_et.interact()
	await process_frame
	_check("...and ends it", not el.test_on)
	var room: Light3D = main.get_node("Lights/Light_ControlRoom")
	sw_l.interact()
	_check("LIGHTING: Control Room dims for screen work (%.2f)" % room.light_energy, room.light_energy < 0.5)
	sw_l.interact()
	_check("...and back (%.2f)" % room.light_energy, room.light_energy > 0.8)
	sw_m.interact()
	shell.show_page(shell.Page.CAMERAS)
	shell.refresh()
	_check("MONITOR off: no feed, 'MONITOR OFF'", shell._feed.texture == null and shell._feed_tag.text.find("MONITOR OFF") != -1)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(tg.state_dict()))
	tg.load_dict({})
	tg.load_dict(sd)
	_check("toggle state saved (monitor off restored)", not tg.monitor_on and not sw_m.is_on)
	sw_m.interact()
	shell.show_page(shell.Page.OPS)
	shell.refresh()
	_check("Operations: short action labels, no paragraphs", shell._footer.text.find("NEXT:") != -1 or shell._footer.text.find("ALL DONE") != -1)
	_check("...cabin line is compact by default", shell._footer.text.find("(live sensors)") == -1)


func _basil() -> void:
	var q: Node = main.get_node("Equipment/QuartersLife")
	var body: Node = main.get_node("Player/PlayerBody")
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(3.5, 1.6, 1.5))
	for i in 4: await physics_frame
	q.basil_day = -1
	q.on_part(&"basil")
	await process_frame
	_check("watering is a gesture: the 'pour' with a watering can", body.is_consuming() and body._consume_kind == "pour" and body._consume_prop != null and body._consume_prop.get_node_or_null("Drops") != null)
	_check("...not instant (plant updates when the pour finishes)", not q.basil_watered_today())
	for i in 60:
		if not body.is_consuming():
			break
		await create_timer(0.1).timeout
	_check("watered after the pour; prop gone", q.basil_watered_today() and body._consume_prop == null)


func _holdout() -> void:
	var h: Node = scr.holdout
	_check("space presentation: colony landmarks (%s)" % str(h.landmark_names()), "CREW HAB" in h.landmark_names() and "BIODOME" in h.landmark_names() and "MED BAY" in h.landmark_names())
	_check("sci-fi weapon names, same ids", h.WEAPONS["pistol"]["name"] == "SIDEARM" and h.WEAPONS["rifle"]["name"] == "PULSE RIFLE" and h.WEAPONS["arc"]["name"] == "ARC PROJECTOR")
	h.load_state({"best": 77, "credits": 5, "unlocked": ["pistol", "rifle"], "weapon": "rifle"})
	_check("an older save loads (weapon ids unchanged)", h.weapon == "rifle" and h.unlocked.has("rifle") and int(h.best_by["easy"]) == 77)
	h.start_seeded(1)
	_check("gameplay intact: same buildings / doors / enemies", h.buildings.size() == 3 and h.KINDS.size() == 10)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
