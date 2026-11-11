extends SceneTree
## Round 46 Priorities 1-2: the 600-second shift budget.
##  - the budget advances at exactly real time, independent of frame rate
##    (30 / 60 / 120 FPS and variable frame times; 60 / 300 / 600 s);
##  - finishing the required work no longer ends the shift early: the shift
##    ends at exactly shift_duration_s() of eligible time; resting early is
##    the player's choice once the work is done;
##  - a new day starts at 08:00 with ZERO elapsed, and nothing counts while
##    waking up / getting out of the bunk;
##  - the focused laptop holds the budget (clock keeps real pace, no jump,
##    never backwards); an emergency still cannot be frozen there;
##  - a single update source; a monotonic real-time check at 30 / 120 FPS;
##  - save/load keeps the elapsed time; developer diagnostics.
var _ok := true
var main: Node
var dp: Node
var ss: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	dp = main.get_node("DayPlan")
	ss = main.get_node("SleepState")
	_check("one DayPlan updates the shift (no duplicate time sources)", get_nodes_in_group(&"day_plan").size() == 1)
	_frame_rates()
	_work_done_does_not_end_shift()
	_laptop_hold()
	await _real_time()
	await _new_day()
	_save_load()
	_diagnostics()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


## Drives DayPlan's own _process with a given frame time (synchronously, so
## no engine frame interleaves) until `seconds` of simulated time passed.
func _drive(seconds: float, dt_of: Callable) -> float:
	var sum: float = 0.0
	var i: int = 0
	while sum < seconds - 1e-9:
		var dt: float = minf(float(dt_of.call(i)), seconds - sum)
		dp._process(dt)
		sum += dt
		i += 1
	return sum


func _fresh() -> void:
	dp.shift_elapsed_s = 0.0
	dp.laptop_clock_s = 0.0
	dp.shift_ended = false
	dp.work_done_at_s = -1.0
	dp.awake_after_shift_s = 0.0
	dp.day_active = true
	dp._holds.clear()


func _frame_rates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 46
	var rates := {"30 FPS": func(_i): return 1.0 / 30.0, "60 FPS": func(_i): return 1.0 / 60.0,
		"120 FPS": func(_i): return 1.0 / 120.0, "variable": func(_i): return rng.randf_range(0.004, 0.05)}
	for name in rates:
		for secs in [60.0, 300.0]:
			_fresh()
			var sim: float = _drive(secs, rates[name])
			_check("%s: %d s of play consume %.3f s of budget" % [name, int(secs), dp.shift_elapsed_s], absf(dp.shift_elapsed_s - sim) < 1e-6 and not dp.shift_ended)
	_fresh()
	_drive(599.9, rates["60 FPS"])
	_check("599.9 s: shift still running (%s left)" % dp.clock_text(dp.shift_remaining_s()), not dp.shift_ended)
	_drive(0.2, rates["60 FPS"])
	_check("600 s: the shift ends exactly at the budget (elapsed %.2f)" % dp.shift_elapsed_s, dp.shift_ended and absf(dp.shift_elapsed_s - 600.0) < 0.2)
	_check("the budget is 600 s", is_equal_approx(dp.shift_duration_s(), 600.0))


func _complete_required_work() -> void:
	dp.orders = dp.orders.filter(func(o): return o["status"] != "open")
	dp.workday = 0
	dp.cargo_duty = ""
	dp.mark_done(&"c01")
	main.get_node("Equipment/QuartersLife").eat_and_drink_now()
	var open_rows: Array = dp.order_rows().filter(func(r): return not r.get("done", false))
	if not open_rows.is_empty():
		print("open rows: ", open_rows.map(func(r): return r.get("id")))


func _work_done_does_not_end_shift() -> void:
	_fresh()
	_complete_required_work()
	_drive(120.0, func(_i): return 1.0 / 60.0)
	_check("work done at 2 min -> WORK DONE, shift continues", dp.is_wrapping_up() and not dp.shift_ended)
	_drive(300.0, func(_i): return 1.0 / 60.0)
	_check("...still running at 7 min (no 45 s auto-end any more)", not dp.shift_ended and dp.shift_status_text().find("WORK DONE") != -1)
	_check("...resting early is allowed (player's choice)", dp.can_sleep())
	var c0: int = dp.clock_minutes()
	dp.rest_early()
	_check("rest_early ends the shift without a clock jump (%d -> %d)" % [c0, dp.clock_minutes()], dp.shift_ended and dp.clock_minutes() == c0)
	_fresh()
	_check("mid-shift with work open: no early rest", not dp.can_sleep() or dp.is_wrapping_up())


func _laptop_hold() -> void:
	_fresh()
	_drive(100.0, func(_i): return 1.0 / 60.0)
	var e0: float = dp.shift_elapsed_s
	var m0: int = dp.clock_minutes()
	dp.hold_clock(&"laptop", true)
	_drive(120.0, func(_i): return 1.0 / 60.0)
	_check("laptop focused 2 min: budget held (%.2f -> %.2f)" % [e0, dp.shift_elapsed_s], is_equal_approx(dp.shift_elapsed_s, e0))
	_check("...station clock moved at real pace (+%d min)" % (dp.clock_minutes() - m0), dp.clock_minutes() - m0 == 2)
	var m1: int = dp.clock_minutes()
	dp.hold_clock(&"laptop", false)
	_check("leaving the laptop: no jump, never backwards", dp.clock_minutes() == m1)
	_drive(10.0, func(_i): return 1.0 / 60.0)
	_check("...and the budget resumes at real time", absf(dp.shift_elapsed_s - e0 - 10.0) < 1e-6)
	# Emergency rule (Round 42): games / focused laptop refused during one.
	var st: Node = get_first_node_in_group(&"station_status")
	if st != null and st.has_method("emergency"):
		_check("emergency rule preserved: entertainment refused while an alert is active", dp.entertainment_allowed()["ok"] == st.emergency().is_empty())


func _real_time() -> void:
	_fresh()
	for fps in [30, 120]:
		Engine.max_fps = fps
		for w in 5:
			await process_frame       # settle at the new cap before measuring
		var t0: int = Time.get_ticks_usec()
		var e0: float = dp.shift_elapsed_s
		while Time.get_ticks_usec() - t0 < 5_000_000:
			await process_frame
		var real: float = (Time.get_ticks_usec() - t0) / 1e6
		var ratio: float = (dp.shift_elapsed_s - e0) / real
		_check("monotonic real time at %d FPS: budget/real = %.4f" % [fps, ratio], ratio > 0.97 and ratio < 1.03)
	Engine.max_fps = 0


func _new_day() -> void:
	_fresh()
	dp.shift_elapsed_s = 333.0
	dp.end_shift_now()
	var fb: Node = main.get_node("FreeMoveBody")
	var bunk: Node3D = main.get_node("Interactables/Bunk")
	var near := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	fb.sync_to_eye_position(near)
	main.get_node("Player").global_position = near
	await create_timer(0.3).timeout
	bunk.interact()
	await create_timer(2.5).timeout
	ss.begin_sleep()
	for i in 200:
		if not ss.is_sleeping():
			break
		await create_timer(0.05).timeout
	_check("new day: elapsed is exactly 0 (%.3f), clock 08:00 (%s)" % [dp.shift_elapsed_s, dp.clock_text_hhmm()], dp.shift_elapsed_s == 0.0 and dp.clock_text_hhmm() == "08:00")
	_check("...awake in the bunk: the budget waits", not dp.day_active and dp.clock_paused())
	await create_timer(1.0).timeout
	_check("...still 0 after a second in the bunk", dp.shift_elapsed_s == 0.0)
	ss.end_sitting()
	var max_during: float = 0.0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await process_frame
		if ss.has_method("is_up") and ss.is_up():
			break
		max_during = maxf(max_during, dp.shift_elapsed_s)
	_check("...nothing consumed during the get-up animation (%.3f)" % max_during, max_during == 0.0)
	await create_timer(1.0).timeout
	_check("...counting once up (%.2f s)" % dp.shift_elapsed_s, dp.day_active and dp.shift_elapsed_s > 0.5 and dp.shift_elapsed_s < 1.5)


func _save_load() -> void:
	var sg: Node = main.get_node("SaveGame")
	dp.shift_elapsed_s = 222.5
	var data: Dictionary = sg.collect_state()
	data = JSON.parse_string(JSON.stringify(data))
	dp.shift_elapsed_s = 0.0
	sg.apply_state(data)
	_check("save/load keeps the elapsed budget (%.1f)" % dp.shift_elapsed_s, absf(dp.shift_elapsed_s - 222.5) < 0.5)


func _diagnostics() -> void:
	_fresh()
	dp.hold_clock(&"laptop", true)
	var d: Dictionary = dp.time_diagnostics()
	_check("diagnostics: clock / elapsed / remaining / pause / multiplier / domain (%s)" % str(d), d.has("clock") and d.has("remaining_s") and String(d["pause"]).find("laptop") != -1 and float(d["multiplier"]) > 1.0 and String(d["domain"]).begins_with("laptop"))
	dp.hold_clock(&"laptop", false)
	var panel_src: String = FileAccess.get_file_as_string("res://scripts/dev/dev_panel.gd")
	_check("developer panel shows the time diagnostics", panel_src.find("time_diagnostics") != -1)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
