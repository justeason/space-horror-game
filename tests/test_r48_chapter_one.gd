extends SceneTree
## Round 48 Priority 34: a CHAPTER ONE pass through the REAL entry points
## (no story variables set by hand): new day in the bunk -> wake at 08:00 ->
## laptop SHIFT HANDOVER app -> morning routine -> workstation CHECK IN
## button -> camera feeds on the CAMERAS page -> station access rises ->
## days pass through the bunk -> familiarity -> the handover note read as
## a deliberate act -> Phase 2 -> the window encounter cued in the Control
## Room, the figure seen from the observation spot by GAZE, the physical
## check at the tunnel port -> the chapter ends.
## Not automated here (each has its own end-to-end tests): the physical
## repair sequences themselves -- a closed work order is signalled through
## DayPlan's own order_closed event (exactly what its equipment poll emits).
## The clock between steps is fast-forwarded with DayPlan's own
## end_shift_now() (the passage of time, not a story shortcut).
var _ok := true
var main: Node
var dp: Node
var ss: Node
var se: Node
var scr: Node
var fb: Node
var player: Node3D
var lp: Node3D
var cam: Camera3D
var q: Node
var findings: Array = []


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame
	dp = main.get_node("DayPlan")
	ss = main.get_node("SleepState")
	se = main.get_node("StoryEvents")
	scr = main.get_node("Player/LaptopView")._log_screen
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	q = main.get_node("Equipment/QuartersLife")
	main.get_node("StationAI").set_enabled(false)
	await _day_one()
	for d in range(2, 5):
		await _ordinary_day(d)
	await _window_climax()
	print("")
	print("  FINDINGS: " + ("; ".join(findings) if not findings.is_empty() else "none"))
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _aim(eye: Vector3, target: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for k in 2:
		for i in 3: await physics_frame
		var d: Vector3 = target - cam.global_position
		lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
		lp._target_yaw = lp.rotation.y
		var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
		lp.get_node("PitchPivot").rotation.x = pitch
		lp._target_pitch = pitch
	for i in 3: await process_frame


func _wait_up() -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await process_frame
		if ss.is_up():
			return true
	return false


func _laptop_handover() -> void:
	await _aim(Vector3(4.0, 1.6, -0.3), Vector3(4.0, 1.0, -1.2))
	ss.begin_sitting()
	await create_timer(1.8).timeout
	ss.open_laptop(true)
	await create_timer(2.6).timeout
	if not ss.is_editing() and ss.has_method("begin_editing"):
		ss.begin_editing()
	(scr.button(&"handover") as Button).pressed.emit()
	await create_timer(1.6).timeout             # the laptop zooms in, then opens the app
	_check_soft("the handover button opens the SHIFT HANDOVER app (view %s)" % scr.current_view(), scr.current_view() == &"handover")
	scr._on_app(&"close")
	await create_timer(2.2).timeout
	ss.end_sitting()
	await _wait_up()


func _workstation(feeds: Array) -> void:
	var console: Node3D = main.get_node("Interactables/WorkstationConsole")
	var pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	await _aim(pos, console.global_position)
	console.interact()
	await create_timer(1.2).timeout
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen").shell
	if not dp.is_task_done(&"c01"):
		(shell.action_buttons["checkin"] as Button).pressed.emit()
	shell.show_page(shell.Page.CAMERAS)
	for f in feeds:
		shell.select_camera(f)
		await create_timer(0.7).timeout
	shell.show_page(shell.Page.OPS)
	main.get_node("WorkstationState").end_use()
	await create_timer(1.6).timeout


func _sleep() -> void:
	var bunk: Node = main.get_node("Interactables/Bunk")
	await _aim(Vector3(4.6, 1.6, -0.6), bunk.global_position)
	dp.end_shift_now()
	bunk.interact()
	await create_timer(2.0).timeout
	ss.begin_sleep()
	for i in 200:
		if not ss.is_sleeping():
			break
		await create_timer(0.05).timeout
	ss.end_sitting()
	await _wait_up()


func _day_one() -> void:
	_check("a new game starts on day 1, Phase 1, orientation access", dp.day_number == 1 and se.phase() == 1 and int(main.get_node("DayPlan/Clearance").level) == 0)
	ss.start_day_in_bed()
	await create_timer(1.0).timeout
	for i in 200:                                # eyes open first (as in play)
		if not ss.is_sleeping():
			break
		await create_timer(0.05).timeout
	_check("day 1: in the bunk at 08:00, nothing counting", dp.clock_text_hhmm() == "08:00" and not dp.day_active)
	ss.end_sitting()
	var up: bool = await _wait_up()
	_check("day 1: up and in control at %s" % dp.clock_text_hhmm(), up and dp.clock_text_hhmm().begins_with("08:0"))
	var cal: Node = main.find_child("WallCalendar", true, false)
	_check("the calendar shows day 1 circled", int(cal.marks()["today"]) == 1)
	await _laptop_handover()
	_check("laptop: the SHIFT HANDOVER app shows the handover note first", scr.handover_read.has(0))
	_check("...read on day 1: remembered, no phase change yet", se.phase() == 1 and se.investigations.has("_handover_early"))
	q.on_part(&"meal")
	await create_timer(EAT_S()).timeout
	q.on_part(&"water")
	await create_timer(q.DRINK_S + 0.4).timeout
	_check("morning routine: breakfast + a drink (through the galley)", q.ate_today() and q.drank_today())
	await _workstation(["INT-02", "EXT-01"])
	_check("workstation: CHECK IN done through its button", dp.is_task_done(&"c01"))
	_check("...which opens MAINTENANCE access (level %d)" % int(main.get_node("DayPlan/Clearance").level), int(main.get_node("DayPlan/Clearance").level) >= 1)
	var open: Array = dp.open_orders()
	_check("no required work behind a locked door (%d open orders)" % open.size(), open.all(func(o): return main.get_node("DayPlan/Clearance").allows_order(StringName(o["type"]))))
	dp.order_closed.emit(&"breaker")
	await _sleep()
	_check("slept -> day 2, 08:00", dp.day_number == 2 and dp.clock_text_hhmm().begins_with("08:0"))


func EAT_S() -> float:
	return q.EAT_S + 0.4


func _ordinary_day(d: int) -> void:
	_check("day %d begins (calendar %d)" % [d, int(main.find_child("WallCalendar", true, false).marks()["today"])], dp.day_number == d)
	await _workstation(["INT-02", "EXT-03"])
	for t in [&"vent", &"thermal", &"data"]:
		dp.order_closed.emit(t)
	await _laptop_handover()
	if se.phase() < 2:
		findings.append("day %d: still phase %d (familiar %s)" % [d, se.phase(), str(se.familiar_progress())])
	if d < 4:
		await _sleep()


func _window_climax() -> void:
	_check("Phase 2 reached through play (familiarity + the handover read on purpose): phase %d, milestones %s" % [se.phase(), str(se.milestones)], se.phase() >= 2 and se.has_milestone("handover_read"))
	var we: Node = se.window
	# A first small anomaly is noticed / or the phase-2 grace passes.
	var waited := 0
	await process_frame
	while we.stage == "locked" and not we.is_ready_now() and waited < 6:
		await _sleep()
		await process_frame
		waited += 1
	_check("the window encounter becomes ready on its own (day %d = Phase 2 day %d + %d)" % [dp.day_number, int(se.phase2_day), dp.day_number - int(se.phase2_day)], (we.is_ready_now() or we.stage == "ready") and dp.day_number <= int(se.phase2_day) + 3)
	await _aim(Vector3(0.6, 1.6, -0.4), Vector3(0.6, 1.6, -1.4))
	var t0: int = Time.get_ticks_msec()
	while we.stage in ["locked", "ready"] and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	_check("in the Control Room: the cue comes (stage %s)" % we.stage, we.stage == "cued")
	await _aim(we.OBS_SPOT, we.FIGURE_POS + Vector3(0, 1.55, 0))
	t0 = Time.get_ticks_msec()
	while we.stage != "done" and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
		# keep looking at the head as the real player would
		var d: Vector3 = we.figure.head_point() - cam.global_position if we.figure.visible else Vector3.ZERO
		if d != Vector3.ZERO and we.figure.state != "retreat":
			lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
			lp._target_yaw = lp.rotation.y
	_check("seen by gaze from the observation spot, then gone (stage %s)" % we.stage, we.stage == "done" and we.witnessed_day == dp.day_number)
	await _aim(we.TUNNEL_CHECK, we.TUNNEL_CHECK + Vector3(0.5, 0, 0))
	await create_timer(0.5).timeout
	_check("the physical check at the tunnel port", se.investigation_state("window_figure") in ["checked", "contradicted"])
	se._check_chapter()
	_check("Chapter One completes (milestone + card)", se.chapter_one_complete())


func _check_soft(name: String, cond: bool) -> void:
	_check(name, cond)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
		findings.append(name)
