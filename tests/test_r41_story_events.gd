extends SceneTree
## Round 41 Priorities 12-17: the STORY EVENT director and the first two
## controlled anomalies, plus the re-aimed corridor camera.
##  - INT-02 now looks FROM the Junction TOWARD the Control Room and sees
##    the seated workstation position through the doorway;
##  - phases / gating (Round 42: story-driven, not days): phase 1 never
##    arms anything; arming is
##    deterministic (a reload re-derives the same day), one event per day,
##    cooldowns and max plays respected; future beats registered disabled;
##  - corridor_presence: only after watching INT-02 (familiar from an
##    earlier day) while seated; CAMERA_ONLY layer (never in the player's
##    eyes / mirror), no collision, seen on the feed, gone the moment the
##    technician stands up / turns / leaves the feed; recorded once;
##  - window_mismatch: the window and EXT-03 disagree for a short while
##    (displaced tool bag), then agree again;
##  - save / load of seen / played state; no transient state saved.
var _ok := true
var main: Node
var se: Node
var dp: Node
var net: Node
var ws: Node
var shell: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	se = main.get_node("StoryEvents")
	dp = main.get_node("DayPlan")
	net = main.get_node("CameraNetwork")
	ws = main.get_node("WorkstationState")
	shell = main.get_node("Interactables/WorkstationConsole/WorkstationScreen/Shell")
	_corridor_camera()
	_gating()
	await _presence()
	await _window()
	_save_load()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _corridor_camera() -> void:
	var cam: Camera3D = net.camera("INT-02")
	var p: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_basis.z
	# Round 46: remounted on the JUNCTION side of the Life Support doorway
	# header, looking north into the Junction (both side openings + the
	# Control Room approach; see test_r46_horror for the sightlines).
	_check("INT-02 is mounted on the Life Support doorway header (z %.2f), under the ceiling" % p.z, p.z > 6.9 and p.z < 7.4 and p.y < 2.6 and absf(p.x) < 1.0)
	_check("INT-02 looks north into the Junction (forward z %.2f)" % fwd.z, fwd.z < -0.7)
	_check("sees the Control Room doorway", net.sees("INT-02", Vector3(0.0, 1.2, 2.1), 0.3))
	_check("sees the seated operator position (stool / head height)", net.sees("INT-02", Vector3(0.0, 1.15, -0.25), 0.4))
	_check("blind spot documented", String(net.info("INT-02")["blind"]).length() > 10)


func _gating() -> void:
	# Round 42: phases are NARRATIVE (story_events.gd milestones), never the
	# calendar: twenty uneventful days stay in phase 1 and arm nothing.
	se.story_phase = 1
	se.milestones = []
	var early := 0
	for d in range(1, 21):
		dp.day_number = d
		se.armed_for_day = -1
		se._arm_today()
		for id in se.state:
			if se.is_armed(id):
				early += 1
	_check("phase 1 for days 1-20: nothing ever armed (%d), phase still %d" % [early, se.phase()], early == 0 and se.phase() == 1)
	se.story_phase = 2
	var a1: Array = []
	var a2: Array = []
	for run in [a1, a2]:
		for id in se.state:
			se.state[id] = {"plays": 0, "last_day": -99, "armed_day": -1, "seen": false}
		for d in range(7, 25):
			dp.day_number = d
			se.armed_for_day = -1
			se._arm_today()
			var armed: Array = se.state.keys().filter(func(id): return se.is_armed(id))
			run.append(armed)
	_check("deterministic arming (same days -> same events)", a1 == a2)
	_check("at most one event armed per day", a1.all(func(x): return x.size() <= 1))
	_check("early phase-2 anomalies get armed on some later day", a1.any(func(x): return x.has(&"corridor_presence")) and a1.any(func(x): return x.has(&"window_mismatch")))
	_check("late-phase-2 beats (hatch handle) never arm in EARLY phase 2", not a1.any(func(x): return x.has(&"hatch_handle")))
	var dormant: Array = se.EVENTS.keys().filter(func(k): return not se.EVENTS[k]["implemented"])
	_check("future beats registered but unavailable %s" % str(dormant), dormant.size() >= 3 and a1.all(func(x): return x.all(func(id): return se.EVENTS[id]["implemented"])))
	for id in se.state:
		se.state[id] = {"plays": 0, "last_day": -99, "armed_day": -1, "seen": false}


func _presence() -> void:
	se.story_phase = 2
	dp.day_number = 8
	dp.shift_elapsed_s = 200.0
	se.feed_days = {"INT-02": [7]}
	_check("debug arm presence for day 8", se.debug_arm(&"corridor_presence") and se.is_armed(&"corridor_presence"))
	ws.begin_use()
	await _until(func(): return ws.is_in_use(), 5.0)
	shell.show_page(shell.Page.OPS)
	await create_timer(1.0).timeout
	_check("not on the Cameras page: nothing happens", not se.presence_visible())
	shell.show_page(shell.Page.CAMERAS)
	shell.select_camera("INT-04")
	await create_timer(1.5).timeout
	_check("another camera: nothing happens", not se.presence_visible())
	shell.select_camera("INT-02")
	await create_timer(3.0).timeout
	_check("watching INT-02 briefly: not yet", not se.presence_visible())
	await _until(func(): return se.presence_visible(), 6.0)
	_check("after watching INT-02 a while: a presence on the feed", se.presence_visible())
	var pn: Node3D = se.presence_node()
	await _until(func(): return pn.travelled > 1.6, 4.0)      # out on the Junction floor
	var p: Vector3 = pn.global_position + Vector3(0, 1.2, 0)
	_check("it is in the Junction (Round 46 crossing), seen by INT-02", net.sees("INT-02", p, 0.5) and p.z > -0.35)
	var lay_ok := true
	for m in pn.find_children("*", "VisualInstance3D", true, false):
		lay_ok = lay_ok and (m as VisualInstance3D).layers == se.CAMERA_ONLY
	_check("CAMERA_ONLY layer on every part", lay_ok)
	var pc: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_check("the player's own eyes never render CAMERA_ONLY", pc.cull_mask & se.CAMERA_ONLY == 0)
	var mir_ok := true
	for c in main.get_node("Mirrors").find_children("*", "Camera3D", true, false):
		mir_ok = mir_ok and (c as Camera3D).cull_mask & se.CAMERA_ONLY == 0
	_check("mirrors never render it", mir_ok)
	_check("INT-02 renders it", net.camera("INT-02").cull_mask & se.CAMERA_ONLY != 0)
	_check("no collision / physics body", pn.find_children("*", "CollisionObject3D", true, false).is_empty())
	await create_timer(1.6).timeout
	ws.end_use()
	await create_timer(0.3).timeout
	_check("the technician stands up -> gone", not se.presence_visible() and se.active == &"")
	var st: Dictionary = se.state[&"corridor_presence"]
	_check("recorded once: played 1, SEEN (it was on screen while watched)", int(st["plays"]) == 1 and bool(st["seen"]) and int(st["last_day"]) == 8)
	await _until(func(): return not ws._transitioning, 4.0)
	ws.begin_use()
	await _until(func(): return ws.is_in_use(), 5.0)
	shell.show_page(shell.Page.CAMERAS)
	shell.select_camera("INT-02")
	await create_timer(8.0).timeout
	_check("not again the same day", not se.presence_visible())
	ws.end_use()
	await _until(func(): return not ws._transitioning and not ws.is_in_use(), 5.0)
	dp.day_number = 9
	se.armed_for_day = -1
	se._arm_today()
	_check("cooldown: not armed the next day", not se.is_armed(&"corridor_presence"))
	_check("no station-AI announcement (events never call the assistant)", _only_false_announcement())


func _window() -> void:
	dp.day_number = 10
	se.feed_days["EXT-03"] = [9]
	var od: Node = main.get_node("Exterior/ObservationDiscrepancy")
	od.clear()
	_check("normal play: window and EXT-03 agree (no discrepancy)", not od.is_active())
	se.debug_arm(&"window_mismatch")
	var fb: Node = main.get_node("FreeMoveBody")
	var win: Node3D = main.get_node("Interactables/WallWatchWindow")
	fb.sync_to_eye_position(win.global_position + Vector3(1.4, 0.0, 0.0))
	var lp: Node3D = main.get_node("Player/LookPivot")
	var player: Node3D = main.get_node("Player")
	lp.rotation.y = atan2(1.0, 0.0) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	lp.get_node("PitchPivot").rotation.x = 0.0
	if "_target_pitch" in lp:
		lp._target_pitch = 0.0
	await _until(func(): return od.is_active(), 6.0)
	_check("gazing out of the port: the views start to disagree (%s)" % od.active_mode, od.active_mode == "displaced")
	var bag_d: Node3D = od._objs["bag_direct"]
	var bag_c: Node3D = od._objs["bag_camera"]
	# Round 46: the maintenance case on bracket A for the eyes, on bracket B for the cameras.
	_check("window-only case on bracket A, camera-only case on bracket B", bag_d.visible and bag_c.visible and bag_d.global_position.distance_to(bag_c.global_position) > 1.5 and absf(bag_d.global_position.x - bag_c.global_position.x) < 0.05)
	_check("EXT-03 never renders the window-only object", net.camera("EXT-03").cull_mask & od.DIRECT_ONLY == 0)
	od._left = 0.05
	await create_timer(0.4).timeout
	_check("short duration: back to agreement, event recorded", not od.is_active() and se.active == &"" and int(se.state[&"window_mismatch"]["plays"]) == 1)


func _save_load() -> void:
	var d: Dictionary = se.state_dict()
	for id in se.state:
		se.state[id] = {"plays": 0, "last_day": -99, "armed_day": -1, "seen": false}
	se.feed_days = {}
	se.load_dict(JSON.parse_string(JSON.stringify(d)))
	_check("load: played / seen / last-day restored", int(se.state[&"corridor_presence"]["plays"]) == 1 and bool(se.state[&"corridor_presence"]["seen"]) and int(se.state[&"window_mismatch"]["plays"]) == 1)
	_check("load: feed familiarity restored as day numbers", se.watched_before_today("INT-02"))
	_check("transient state is not saved", not d.has("active") and not se.presence_visible())


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame


## Round 46: story code never makes the assistant EXPLAIN anything; its one
## assistant call is the deliberate false "calibration complete" line
## (the task-linked wrong reading, abnormal variant).
func _only_false_announcement() -> bool:
	var src: String = FileAccess.get_file_as_string("res://scripts/story/story_events.gd")
	return src.count("station_ai") == 1 and src.count("say_key(") == 1 and src.contains("story_cal_premature")


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
