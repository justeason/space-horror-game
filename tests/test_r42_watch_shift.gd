extends SceneTree
## Round 42 Priorities 31-32: the wristwatch is a WATCH; shift / sleep
## consistency around EVA.
##  - four separate quantities: station clock (08:00 at the start of the
##    shift, 16:00 nominal end, continuous through overtime), shift length,
##    work progress (Operations only), emergency countdown;
##  - the watch's first line is DAY + station time -- never a work %;
##  - a new day starts at 08:00 again (no stale value);
##  - an emergency countdown appears UNDER the clock, never replacing it;
##  - shift ending while suited / outside: no bunk push, no tiredness until
##    safely back inside; the day never ends by itself.
var _ok := true
var main: Node
var dp: Node
var ww: Node


func _face() -> String:
	ww._refresh_text()
	return ww._watch_rig._watch_face_text.text


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	ww = main.get_node("Player/Wristwatch")
	var dur: float = dp.shift_duration_s()
	dp.shift_elapsed_s = 0.0
	_check("start of shift reads 08:00 (%s)" % dp.clock_text_hhmm(), dp.clock_text_hhmm() == "08:00")
	dp.shift_elapsed_s = dur * 0.5
	# Round 45: the active day spans 08:00 -> 23:00 (15 h). Round 48 paces it
	# with DayPlan.CLOCK_CURVE (a slower morning): half the real shift = 13:30.
	_check("halfway through the shift duration: 13:30 (%s)" % dp.clock_text_hhmm(), dp.clock_text_hhmm() == "13:30")
	var f: String = _face()
	_check("watch line 1 is DAY + time ('%s')" % f.replace("\n", " / "), f.begins_with("DAY %02d  13:30" % dp.day_number))
	_check("no work percentage on the watch", f.find("%") == -1)
	_check("work progress still lives in the shift status (Operations): '%s'" % dp.shift_status_text(), dp.shift_status_text().find("WORK") != -1 and dp.shift_status_text().find("13:30") != -1)
	var m0: int = dp.clock_minutes()
	dp.shift_elapsed_s += 30.0
	_check("time advances with the shift (%d -> %d min)" % [m0, dp.clock_minutes()], dp.clock_minutes() > m0)
	# Emergency: countdown under the clock.
	dp.fire_emergency("overload", 1)
	await process_frame
	f = _face()
	_check("emergency: clock stays on top, countdown below ('%s')" % f.replace("\n", " / "), f.begins_with("DAY ") and f.find("!") != -1 and f.split("\n").size() == 3)
	main.get_node("Equipment/PowerDistribution").load_dict({"demand": [2, 2, 2], "setting": [2, 2, 2], "verified": true})
	dp.emergency_plan = {}
	# Shift end while suited: grace preserved.
	var eva: Node = main.get_node("EvaSystem")
	eva.set_suited(true)
	dp.end_shift_now()
	var a0: float = dp.awake_after_shift_s
	await create_timer(0.6).timeout
	_check("shift over while suited: no tiredness accrues, no bunk push (%.2f s)" % dp.awake_after_shift_s, absf(dp.awake_after_shift_s - a0) < 0.01 and dp.tiredness() == 0.0)
	_check("the day does not end by itself (still day %d, waiting for the bunk)" % dp.day_number, dp.shift_ended and dp.can_sleep())
	eva.set_suited(false)
	await create_timer(0.6).timeout
	_check("back out of the suit: the post-shift grace clock runs", dp.awake_after_shift_s > a0)
	var mo: int = dp.clock_minutes()
	_check("overtime keeps the clock going past the end of the work (%s)" % dp.clock_text_hhmm(), mo >= 12 * 60)
	f = _face()
	_check("after the shift the watch still shows the time + bunk", f.begins_with("DAY ") and f.find("BUNK") != -1)
	# New day.
	var d0: int = dp.day_number
	dp.reset_for_new_day()
	await process_frame
	_check("new day %d -> %d starts at 08:00 (%s), no stale value" % [d0, dp.day_number, dp.clock_text_hhmm()], dp.clock_text_hhmm() == "08:00" and _face().find("08:00") != -1)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
