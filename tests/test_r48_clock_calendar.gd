extends SceneTree
## Round 48 Priorities 2-6: the NEW-DAY CLOCK and the WALL CALENDAR.
##  Diagnosis (documented in MILESTONE1_DESIGN.md): nothing advanced the
##  clock while waking (no hidden elapsed time, one update source); "09:00
##  shortly after waking" was the LINEAR mapping -- 15 station hours over
##  600 s = one hour every 40 s. Now a piecewise, strictly increasing curve
##  (08:00 -> 09:15 over the first 120 s) that still ends at 23:00 at 600 s.
##  - real sleep -> new day: 08:00, 0 elapsed, unchanged while lying /
##    getting up / paused; the FIRST controllable frame's watch reads 08:00;
##  - snapshots 0/5/15/30/40/60/300/600 s (station clock + budget);
##  - monotonic, no jumps, frame-rate independent, laptop real pace, early
##    rest, loading a morning save;
##  - the calendar marks the authoritative day (past slashed, today circled,
##    future blank), turns pages (Nov, the new year), survives save/load,
##    and its anomaly hook is presentation only (never Phase 1 play).
var _ok := true
var main: Node
var dp: Node
var ss: Node
var cal: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame
	dp = main.get_node("DayPlan")
	ss = main.get_node("SleepState")
	cal = main.find_child("WallCalendar", true, false)
	main.get_node("StationAI").set_enabled(false)
	_snapshots()
	_pacing()
	await _real_wake()
	_early_rest_and_load()
	_calendar()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _fresh() -> void:
	dp.shift_elapsed_s = 0.0
	dp.laptop_clock_s = 0.0
	dp.shift_ended = false
	dp.work_done_at_s = -1.0
	dp.awake_after_shift_s = 0.0
	dp.day_active = true
	dp._holds.clear()


func _drive(seconds: float, dt: float) -> void:
	var sum := 0.0
	while sum < seconds - 1e-9:
		var d: float = minf(dt, seconds - sum)
		dp._process(d)
		sum += d


func _snapshots() -> void:
	_fresh()
	var marks := [0, 5, 15, 30, 40, 60, 300, 600]
	var at := 0.0
	var rows: Array = []
	for m in marks:
		_drive(float(m) - at, 1.0 / 60.0)
		at = float(m)
		rows.append("%4d s  station %s  budget %5.1f / %5.1f s left%s" % [m, dp.clock_text_hhmm(), dp.shift_elapsed_s, dp.shift_remaining_s(), "  (shift ended)" if dp.shift_ended else ""])
	print("  CLOCK SNAPSHOTS (eligible seconds):")
	for r in rows:
		print("   ", r)
	_fresh()
	_check("0 s: 08:00, 0 elapsed, 600 s left", dp.clock_text_hhmm() == "08:00" and dp.shift_elapsed_s == 0.0 and is_equal_approx(dp.shift_remaining_s(), 600.0))
	_drive(40.0, 1.0 / 60.0)
	_check("40 s: still early morning (%s, was 09:00 in Round 47)" % dp.clock_text_hhmm(), dp.clock_minutes() < 8 * 60 + 30)
	_drive(80.0, 1.0 / 60.0)
	_check("120 s: 09:15 (%s)" % dp.clock_text_hhmm(), dp.clock_text_hhmm() == "09:15")
	_drive(480.02, 1.0 / 60.0)
	_check("600 s: the shift ends exactly at 23:00 (%s, ended %s)" % [dp.clock_text_hhmm(), dp.shift_ended], dp.clock_text_hhmm() == "23:00" and dp.shift_ended)


func _pacing() -> void:
	_fresh()
	var prev: int = dp.clock_minutes()
	var mono := true
	var max_step := 0
	var first_hour_s := -1.0
	for s in 600:
		_drive(1.0, 1.0 / 30.0)
		var m: int = dp.clock_minutes()
		mono = mono and m >= prev
		max_step = maxi(max_step, m - prev)
		if first_hour_s < 0.0 and m >= 9 * 60:
			first_hour_s = float(s + 1)
		prev = m
	_check("never backwards, never a jump (largest 1-s step %d station min)" % max_step, mono and max_step <= 2)
	_check("the first station hour takes %.0f s (was 40 s)" % first_hour_s, first_hour_s >= 80.0)
	# Frame-rate independence of the CLOCK itself.
	var res := {}
	for fps in [30.0, 60.0, 144.0]:
		_fresh()
		_drive(237.0, 1.0 / fps)
		res[fps] = dp.clock_minutes()
	_check("same station time at 30 / 60 / 144 FPS (%s)" % str(res.values()), res[30.0] == res[60.0] and res[60.0] == res[144.0])
	# Laptop: budget held, station clock at real pace (1 min per 60 s).
	_fresh()
	_drive(30.0, 1.0 / 60.0)
	var m0: int = dp.clock_minutes()
	var e0: float = dp.shift_elapsed_s
	dp.hold_clock(&"laptop", true)
	_drive(120.0, 1.0 / 60.0)
	dp.hold_clock(&"laptop", false)
	_check("laptop: budget held (%.1f), clock real pace (+%d min in 120 s)" % [dp.shift_elapsed_s, dp.clock_minutes() - m0], is_equal_approx(dp.shift_elapsed_s, e0) and dp.clock_minutes() - m0 == 2)
	# Routine timings stay sensible: dinner (18:00) after the work day's midpoint.
	var dinner_s := -1.0
	_fresh()
	for s in 600:
		_drive(1.0, 0.5)
		if dinner_s < 0.0 and dp.clock_minutes() >= 18 * 60:
			dinner_s = float(s + 1)
	_check("18:00 (dinner) comes at %.0f s of 600" % dinner_s, dinner_s > 380.0 and dinner_s < 520.0)


func _watch_text() -> String:
	var wv: Node = main.get_node_or_null("Player/Wristwatch")
	if wv != null and wv.has_method("_clock_line"):
		return String(wv._clock_line())          # what the watch face shows
	return "DAY %02d  %s" % [dp.day_number, dp.clock_text_hhmm()]


func _real_wake() -> void:
	var bunk: Node = main.get_node("Interactables/Bunk") if main.has_node("Interactables/Bunk") else main.find_child("Bunk", true, false)
	var fb: Node = main.get_node("FreeMoveBody")
	var near := Vector3(4.6, 1.6, -0.6)
	fb.sync_to_eye_position(near)
	main.get_node("Player").global_position = near
	await create_timer(0.3).timeout
	dp.shift_elapsed_s = 300.0
	bunk.interact()
	await create_timer(2.5).timeout
	ss.begin_sleep()
	for i in 200:
		if not ss.is_sleeping():
			break
		await create_timer(0.05).timeout
	_check("woke into a new day: 08:00 and exactly 0 elapsed (%s, %.3f)" % [dp.clock_text_hhmm(), dp.shift_elapsed_s], dp.clock_text_hhmm() == "08:00" and dp.shift_elapsed_s == 0.0)
	await create_timer(1.5).timeout
	_check("...lying in the bunk: nothing counts (%.3f)" % dp.shift_elapsed_s, dp.shift_elapsed_s == 0.0 and not dp.day_active)
	ss.end_sitting()
	# Pause the game for a moment in the middle of getting up.
	await create_timer(0.4).timeout
	paused = true
	var pt: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - pt < 800:
		await process_frame
	paused = false
	var first_up_text := ""
	var max_during := 0.0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await process_frame
		if ss.is_up():
			first_up_text = _watch_text()
			break
		max_during = maxf(max_during, dp.shift_elapsed_s)
	_check("...getting up (with a pause in the middle) consumed nothing (%.3f)" % max_during, max_during == 0.0)
	_check("the first controllable frame's watch reads 08:00 ('%s')" % first_up_text, first_up_text.ends_with("08:00"))
	await create_timer(1.0).timeout
	_check("...then the clock runs (%.2f s, %s)" % [dp.shift_elapsed_s, dp.clock_text_hhmm()], dp.day_active and dp.shift_elapsed_s > 0.5 and dp.clock_text_hhmm().begins_with("08:0"))


func _early_rest_and_load() -> void:
	_fresh()
	_drive(200.0, 1.0 / 60.0)
	dp.end_shift_now()
	dp.reset_for_new_day()
	_check("sleeping early: the next day starts at 08:00, 0 elapsed", dp.clock_text_hhmm() == "08:00" and dp.shift_elapsed_s == 0.0 and not dp.day_active)
	var sg: Node = main.get_node("SaveGame")
	var data: Dictionary = JSON.parse_string(JSON.stringify(sg.collect_state()))
	dp.shift_elapsed_s = 333.0
	dp.laptop_clock_s = 50.0
	sg.apply_state(data)
	_check("loading a start-of-day save: 08:00, 0 elapsed (%s, %.2f)" % [dp.clock_text_hhmm(), dp.shift_elapsed_s], dp.clock_text_hhmm() == "08:00" and dp.shift_elapsed_s == 0.0)


func _calendar() -> void:
	_check("the wall calendar exists in the Living Quarters", cal != null and cal.get_parent() != null and String(cal.get_path()).contains("QuartersLife"))
	var d0: int = dp.day_number
	var cases := {1: [[], 1], 2: [[1], 2], 5: [[1, 2, 3, 4], 5]}
	for d in cases:
		dp.day_number = d
		cal.refresh(true)
		var m: Dictionary = cal.marks()
		_check("day %d: past %s slashed, today %d circled (got %s / %d)" % [d, str(cases[d][0]), cases[d][1], str(m["past"]), int(m["today"])], m["past"] == cases[d][0] and int(m["today"]) == cases[d][1] and m["page"]["month"] == 10)
	dp.day_number = 31
	cal.refresh(true)
	var m31: Dictionary = cal.marks()
	_check("day 31: 30 days slashed, the 31st circled", (m31["past"] as Array).size() == 30 and int(m31["today"]) == 31)
	dp.day_number = 32
	cal.refresh(true)
	var m32: Dictionary = cal.marks()
	_check("day 32: the page turns to November, the 1st circled (%s)" % str(m32["page"]), m32["page"]["month"] == 11 and int(m32["today"]) == 1 and (m32["past"] as Array).is_empty())
	dp.day_number = 93
	cal.refresh(true)
	var m93: Dictionary = cal.marks()
	_check("day 93: January 2027 (%s), no Day-31 limit" % str(m93["page"]), m93["page"]["year"] == 2027 and m93["page"]["month"] == 1 and int(m93["today"]) == 1)
	_check("weekdays real: 1 Oct 2026 is a Thursday", int(cal.date_of(1)["weekday"]) == 3)
	dp.day_number = 6
	var future_ok := true
	cal.refresh(true)
	for x in cal.marks()["past"]:
		future_ok = future_ok and int(x) < 6
	_check("future days stay unmarked", future_ok and int(cal.marks()["today"]) == 6)
	# It follows the day on its own (no manual refresh).
	dp.day_number = 7
	cal._poll_t = 1.0
	cal._process(0.0)
	_check("updates by itself when the day changes (today %d)" % int(cal.marks()["today"]), int(cal.marks()["today"]) == 7)
	# Save / load: the marks come from the saved day.
	var sg: Node = main.get_node("SaveGame")
	var data: Dictionary = JSON.parse_string(JSON.stringify(sg.collect_state()))
	dp.day_number = 2
	cal.refresh(true)
	sg.apply_state(data)
	cal.refresh()
	_check("save/load: the loaded day's marks (today %d)" % int(cal.marks()["today"]), int(cal.marks()["today"]) == 7 and (cal.marks()["past"] as Array).size() == 6)
	# Anomaly hook: presentation only, never the authoritative day.
	cal.set_anomaly(&"tomorrow_marked", true)
	var ma: Dictionary = cal.marks()
	_check("anomaly preview draws tomorrow circled by someone else (%s)" % str(ma["foreign"]), ma["foreign"] == [8] and dp.day_number == 7 and cal.anomaly_dev)
	cal.set_anomaly(&"mark_missing", true)
	_check("...or a missing mark (yesterday unslashed: %s)" % str(cal.marks()["past"]), not (cal.marks()["past"] as Array).has(6) and dp.day_number == 7)
	cal.set_anomaly(&"")
	_check("cleared: trustworthy again", int(cal.marks()["today"]) == 7 and (cal.marks()["past"] as Array).size() == 6 and not cal.anomaly_dev)
	var se_src: String = FileAccess.get_file_as_string("res://scripts/story/story_events.gd")
	_check("story never drives it in Phase 1 (only the developer preview calls set_anomaly)", se_src.find("set_anomaly") == -1)
	_check("never the computer's date (fixed fiction start)", FileAccess.get_file_as_string("res://scripts/station/wall_calendar.gd").find("get_datetime_dict_from_system") == -1)
	dp.day_number = d0


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
