extends SceneTree
## Round 45 Priorities 3-12: story-driven access + the window encounter.
##  ACCESS: L0 at a new game (Engineering / Life Support / Comms gates shut,
##    the technician's body really stops at them; EVA refused at the
##    locker and the airlock), earned levels from real progress, no work
##    scheduled behind a gate, old saves never soft-locked, dev override.
##  WINDOW: a real second port (cut, glass collider, hull still sealed),
##    true line of sight from the Control Room port, the figure is
##    DIRECT-only (never on cameras), the event never runs where the
##    player can't see it, the gaze dwell triggers a real animated
##    convulsion + retreat out of the frame, guidance is safe and
##    cancellable (and has a reduced-motion form), investigation + chapter
##    progress, developer reset, save/load.
var _ok := true
var main: Node
var dp: Node
var se: Node
var we: Node
var clr: Node
var fb: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame
	dp = main.get_node("DayPlan")
	se = main.get_node("StoryEvents")
	we = se.window
	clr = dp.get_node("Clearance")
	fb = main.get_node("FreeMoveBody")
	main.get_node("StationAI").set_enabled(false)
	await _access()
	await _window_geometry()
	await _window_event()
	await _guidance()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _walk(from: Vector3, dir: Vector3, frames: int) -> Vector3:
	fb.sync_to_eye_position(from)
	for i in 4: await physics_frame
	fb.guide_target = from + dir * 4.0
	for i in frames:
		await physics_frame
	fb.guide_target = Vector3.INF
	return fb.current_eye_position()


func _access() -> void:
	_check("new game: ORIENTATION clearance", clr.effective() == 0 and clr.earned() == 0)
	_check("Engineering / Life Support / Comms closed, Control + Quarters open", not clr.room_open(&"engineering") and not clr.room_open(&"life_support") and not clr.room_open(&"communications") and clr.room_open(&"control_room") and clr.room_open(&"living_quarters"))
	var stop: Vector3 = await _walk(Vector3(0.0, 1.6, 6.06), Vector3(-1, 0, 0), 120)
	_check("the body stops at the closed Engineering gate (x %.2f)" % stop.x, stop.x > -1.6)
	var eva: Node = main.get_node("EvaSystem")
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, 0.9))
	await physics_frame
	eva.on_part(&"locker")
	_check("EVA locker refused without EVA clearance", not eva.suited)
	_check("airlock cycle refused without EVA clearance", not main.get_node("AirlockChamber").begin_cycle_out())
	dp.mark_done(&"c01")
	await process_frame
	_check("orientation check-in -> MAINTENANCE clearance (gates for Engineering / LS open)", clr.effective() == 1 and clr.gate_open("engineering") and clr.gate_open("life_support") and not clr.gate_open("communications"))
	_check("the grant is on record (access log)", main.get_tree().get_first_node_in_group(&"station_log").has_entry("access", "CLEARANCE MAINTENANCE"))
	var through: Vector3 = await _walk(Vector3(0.0, 1.6, 6.06), Vector3(-1, 0, 0), 120)
	_check("...and the body now walks through (x %.2f)" % through.x, through.x < -1.8)
	_check("no Comms / EVA work can be scheduled at L1", not clr.allows_order(&"patch_bay") and not clr.allows_order(&"antenna") and clr.allows_order(&"vent"))
	var bad := 0
	for d in 6:
		dp.end_shift_now()
		dp.reset_for_new_day()
		for o in dp.orders:
			if o["status"] == "open" and not clr.allows_order(StringName(o["type"])):
				bad += 1
		if int(dp.workday) == dp.Workday.COMMS_CHECK and not clr.allows("comms"):
			bad += 1
	_check("six simulated days: no open order / workday behind a gate (%d) · level %d" % [bad, clr.effective()], bad == 0)
	clr.load_dict({"level": 0})
	dp.day_number = 9
	clr.refresh()
	_check("an old save with real progress is never soft-locked (L%d)" % clr.effective(), clr.effective() == 3)
	clr.dev_set(0)
	_check("developer override is transient (L0 now, saved level %d)" % int(clr.state_dict()["level"]), clr.effective() == 0 and int(clr.state_dict()["level"]) == 3)
	clr.dev_set(-1)
	_check("override cleared", clr.effective() == 3)


func _window_geometry() -> void:
	var port: Node = main.find_child("TunnelPort", true, false)
	var wall: Node = main.get_node("Geometry/AirlockTunnelEastWall")
	_check("second port exists with a real cut in the tunnel wall", port != null and wall.get_node_or_null("TunnelPortCut") != null)
	await physics_frame
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(-4.8, 1.55, 2.5), Vector3(-2.5, 1.55, 2.5))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	_check("hull stays sealed: a ray out through the port hits its glass", not hit.is_empty() and String(hit["collider"].name) == "TunnelPortGlass")
	var fig: Node3D = we.figure
	_check("figure is DIRECT-only (never on surveillance feeds)", fig.find_children("*", "GeometryInstance3D", true, false).all(func(g): return (g as GeometryInstance3D).layers == fig.DIRECT_ONLY))
	var net: Node = main.get_node("CameraNetwork")
	var cam_ok := true
	for id in net.cams:
		if (net.camera(id).cull_mask & fig.DIRECT_ONLY) != 0:
			cam_ok = false
	_check("no surveillance camera renders the DIRECT-only layer", cam_ok)
	we.dev_goto()
	for i in 4: await physics_frame
	_check("true line of sight from the Control Room port to the figure", we.observable())
	fb.sync_to_eye_position(Vector3(0.8, 1.6, -0.6))
	for i in 3: await physics_frame
	_check("...not from the back of the Control Room (out of the port's cone)", not we.observable())


func _window_event() -> void:
	se.story_phase = 2
	se.observe("phantom_cycle", "seen")
	dp.day_number = maxi(dp.day_number, 3)
	we.dev_reset()
	_check("READY once phase 2 + one anomaly seen", we.is_ready_now())
	fb.sync_to_eye_position(Vector3(4.0, 1.6, 0.5))         # Living Quarters
	await create_timer(4.0).timeout
	_check("player elsewhere: the event stays pending, figure never shown", we.stage == "ready" and not we.figure.visible and we.witnessed_day < 0)
	fb.sync_to_eye_position(Vector3(0.6, 1.6, -0.4))
	var lp: Node3D = main.get_node("Player/LookPivot")
	lp.rotation.y = 0.0
	lp._target_yaw = 0.0
	await create_timer(3.2).timeout
	var iv: Node = main.get_tree().get_first_node_in_group(&"inner_voice")
	_check("in the Control Room: a cue (thought), figure still hidden until visible", we.stage == "cued" and not we.figure.visible and iv.said.keys().any(func(k): return String(k).begins_with("window_cue")))
	we.dev_goto()
	await create_timer(0.3).timeout
	_check("observable -> the figure appears (still)", we.stage == "showing" and we.figure.visible and we.figure.state == "idle")
	var hr0: Vector3 = we.figure._head.rotation
	var lpp: Node3D = we.figure._arms[1][0]
	var arm_pos0: Vector3 = lpp.position
	await create_timer(0.7).timeout
	_check("direct gaze for 0.6 s triggers the reaction", we.stage == "reacting")
	var fig: Node3D = we.figure
	# Sample the animation (convulsion, then retreat): rotations change,
	# limbs stay attached, the body slides along the tunnel out of frame.
	var max_head := 0.0
	var zs: Array = []
	# Round 46: the sequence is longer (1.15 s reaction + 0.9 s retreat):
	# sample until it is over.
	var t0 := Time.get_ticks_msec()
	while fig.state != "gone" and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
		max_head = maxf(max_head, absf(fig._head.rotation.x))
		if fig.state == "retreat":
			zs.append(fig.position.z)
	_check("convulsion: head snaps far and fast (max %.0f deg)" % rad_to_deg(max_head), max_head > deg_to_rad(20.0))
	_check("limbs stay attached (joint offsets unchanged)", lpp.position == arm_pos0)
	await create_timer(1.2).timeout
	var mono := true
	for i in range(1, zs.size()):
		if float(zs[i]) < float(zs[i - 1]) - 0.0001:
			mono = false
	_check("retreat: accelerating slide along the tunnel (%d samples), then gone" % zs.size(), mono and not fig.visible and fig.state == "gone")
	_check("witnessed: observation evidence + journal memory + thought", we.stage == "done" and se.investigation_state("window_figure") == "observed" and main.get_tree().get_first_node_in_group(&"journal").has("obs:window_figure") and iv.said.has("window_after"))
	fb.sync_to_eye_position(we.TUNNEL_CHECK)
	await create_timer(0.4).timeout
	_check("going to the tunnel port = a physical check", se.investigation_state("window_figure") == "checked")
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen").shell
	shell.select_record_tab("camera")
	_check("the CAMERA record contradicts it", se.investigation_state("window_figure") == "contradicted" and iv.said.has("window_record"))
	var sd: Dictionary = JSON.parse_string(JSON.stringify(we.state_dict()))
	we.load_dict({})
	we.load_dict(sd)
	_check("save/load: witnessed day kept, never replays", we.stage == "done" and we.witnessed_day >= 0 and not we.is_ready_now())
	se.milestones.erase("chapter_1")
	dp.end_shift_now()
	dp.reset_for_new_day()
	await process_frame
	_check("Chapter One concludes after the encounter + follow-up", se.chapter_one_complete())
	_check("...without forcing phase 3", se.story_phase == 2)
	we.dev_reset()
	_check("developer reset clears the encounter", we.stage == "locked" and we.witnessed_day < 0 and not we.figure.visible)


func _guidance() -> void:
	se.milestones.erase("chapter_1")
	we.dev_prepare()
	fb.sync_to_eye_position(Vector3(0.6, 1.6, -0.4))
	var lp: Node3D = main.get_node("Player/LookPivot")
	lp.rotation.y = 0.0
	lp._target_yaw = 0.0
	await create_timer(3.0).timeout
	_check("cued, not looking", we.stage == "cued" and not we.observable())
	var ss: Node = main.get_node("SleepState")
	var ws: Node = main.get_node("WorkstationState")
	ws.begin_use()
	await create_timer(1.6).timeout
	_check("never takes control while the workstation is in use", not we.start_guidance())
	ws.end_use()
	await create_timer(1.8).timeout
	fb.sync_to_eye_position(Vector3(0.6, 1.6, -0.4))
	await create_timer(0.3).timeout
	_check("safe: guided walk starts (real movement, no teleport)", we.start_guidance() and fb.guide_target != Vector3.INF)
	var p0: Vector3 = fb.current_eye_position()
	await create_timer(0.5).timeout
	_check("...the body walks toward the observation spot", fb.current_eye_position().distance_to(we.OBS_SPOT) < p0.distance_to(we.OBS_SPOT) - 0.1)
	var e := InputEventKey.new()
	e.keycode = KEY_S
	e.physical_keycode = KEY_S
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	await physics_frame
	_check("any movement key cancels the guidance at once", fb.guide_target == Vector3.INF)
	e.pressed = false
	Input.parse_input_event(e)
	await create_timer(0.2).timeout
	_check("not repeated the same day (no hijacking)", not we.guide_days.is_empty() and not we.start_guidance())
	dp.day_number += 1
	var GS = load("res://scripts/station/game_settings.gd")
	var old: bool = bool(GS.get_value("reduce_effects"))
	GS._values["reduce_effects"] = true
	var yaw0: float = lp.rotation.y
	_check("reduced motion: thought + marker only, no camera / body control", we.start_guidance() and fb.guide_target == Vector3.INF and we._marker != null and we._marker.visible)
	await create_timer(0.3).timeout
	_check("...the view was not rotated", absf(lp.rotation.y - yaw0) < 0.001)
	GS._values["reduce_effects"] = old
	_check("after two ignored days TODAY lists an ordinary duty to check the port", we.port_duty and we.today_items().size() == 1)
	we.dev_reset()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
