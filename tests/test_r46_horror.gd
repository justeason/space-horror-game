extends SceneTree
## Round 46 horror presentation (Priorities 5-12, 15-21).
## Runs WINDOWED (run_tests.sh WINDOWED_TESTS): the peripheral figure's
## edge-of-view placement depends on the real 16:9 view, which headless
## mode does not provide (it reports a square viewport).
var _ok := true
var main: Node
var se: Node
var net: Node
var dp: Node
var fb: Node
var lp: Node3D
var player: Node3D
var cam: Camera3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	se = main.get_node("StoryEvents")
	net = main.get_node("CameraNetwork")
	dp = main.get_node("DayPlan")
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	cam = lp.get_node("PitchPivot/Camera3D")
	main.get_node("DayPlan/Clearance").dev_set(3)
	await _junction_camera()
	await _crossing()
	_mismatch()
	await _wrong_reading()
	await _hatch()
	await _peripheral()
	await _window_figure()
	await _guidance()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _space() -> PhysicsDirectSpaceState3D:
	return (fb as Node3D).get_world_3d().direct_space_state


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return _space().intersect_ray(q).is_empty()


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
	await process_frame


# ------------------------------------------------------------ INT-02
func _junction_camera() -> void:
	var c: Camera3D = net.camera("INT-02")
	var targets := {"Communications opening": Vector3(1.1, 1.2, 4.5), "Engineering opening": Vector3(-1.5, 1.2, 6.1), "Junction floor": Vector3(-0.2, 0.3, 5.4), "Control Room approach": Vector3(-0.2, 1.2, 2.6)}
	for k in targets:
		var p: Vector3 = targets[k]
		_check("INT-02 sees the %s (clear ray + in frame)" % k, _clear(c.global_position, p) and net.sees("INT-02", p, 0.0))
	_check("INT-02 is an ordinary wide lens (%.0f deg vertical), not a fisheye" % c.fov, c.fov >= 40.0 and c.fov <= 60.0)


func _crossing() -> void:
	var pn: Node3D = se.presence_node()
	se.dev_trigger(&"corridor_presence")
	await process_frame
	pn.set_process(false)
	_check("crossing: starts inside the Communications passage", pn.global_position.x > 1.2 and absf(pn.global_position.z - 4.5) < 0.2)
	var seen_on_feed := 0
	var c: Camera3D = net.camera("INT-02")
	var xs: Array = []
	var off0: Array = pn.joint_offsets()
	var min_h := 9999.0
	var max_h := 0.0
	var t := 0.0
	while pn.state == "walk" and t < 20.0:
		pn.step(1.0 / 30.0)
		t += 1.0 / 30.0
		var head: Vector3 = pn.head_point()
		if net.sees("INT-02", head, 0.0) and net.sees("INT-02", pn.global_position + Vector3(0, 0.9, 0), 0.0):
			seen_on_feed += 1
			var top: Vector2 = c.unproject_position(head)
			var feet: Vector2 = c.unproject_position(pn.global_position)
			var hpx: float = absf(feet.y - top.y) / float(c.get_viewport().size.y)
			min_h = minf(min_h, hpx)
			max_h = maxf(max_h, hpx)
		xs.append(pn.global_position.x)
	_check("crossing: walks Comms -> Engineering (x %.1f -> %.1f) and is gone after" % [xs[0], xs.back()], xs[0] > 1.5 and xs.back() < -1.5 and not pn.visible)
	_check("crossing: on the feed long enough to recognise (%.1f s)" % (seen_on_feed / 30.0), seen_on_feed / 30.0 >= 2.5)
	_check("crossing: walk speed is human, not a sprint (%.1f s total)" % t, t >= 4.0 and t <= 9.0)
	_check("crossing: real perspective -- its height on the feed changes with distance (%.2f..%.2f of frame)" % [min_h, max_h], max_h > min_h * 1.15 and max_h < 1.2)
	_check("crossing: limbs stay attached", pn.joint_offsets() == off0)
	var lay_ok := true
	for v in pn.find_children("*", "VisualInstance3D", true, false):
		lay_ok = lay_ok and (v as VisualInstance3D).layers == se.CAMERA_ONLY
	_check("crossing: camera-only (never the player's eyes), no collision", lay_ok and cam.cull_mask & se.CAMERA_ONLY == 0 and pn.find_children("*", "CollisionObject3D", true, false).is_empty())
	var path: Array = se.PRESENCE_PATH
	var walls_ok := true
	for i in path.size() - 1:
		walls_ok = walls_ok and _clear(path[i] + Vector3(0, 1.0, 0), path[i + 1] + Vector3(0, 1.0, 0))
	_check("crossing: the path never passes through a wall", walls_ok)
	se.dev_cancel()
	# Story: walking to the Junction afterwards is the physical check.
	se._pending_investigation["corridor_presence"] = 60.0
	await _aim(Vector3(-0.2, 1.6, 5.4), Vector3(-0.2, 1.6, 3.0))
	for i in 4: await process_frame
	_check("going to the Junction afterwards = a physical check", se.investigation_state("corridor_presence") in ["checked", "contradicted"])
	var link: Dictionary = se.RECORD_LINKS["access_log"]
	_check("the door records don't explain it (no one through either door)", String(link["by_event"]["corridor_presence"]).find("Neither") != -1)


# ------------------------------------------------------------ mismatch
func _mismatch() -> void:
	var od: Node = get_first_node_in_group(&"observation_discrepancy")
	var normal: Node3D = od.case_normal
	_check("normal play: the maintenance case sits on bracket A, visible to every view", normal.visible and normal.global_position.distance_to(od.BRACKET_A + Vector3(0.17, 0.17, 0)) < 0.01 and (normal.find_children("*", "VisualInstance3D", true, false)[0] as VisualInstance3D).layers == od.EXTERIOR)
	od.trigger("displaced", 30.0, "debug")
	var d: Node3D = od._objs["bag_direct"]
	var c: Node3D = od._objs["bag_camera"]
	var only_direct := true
	for v in d.find_children("*", "VisualInstance3D", true, false):
		only_direct = only_direct and (v as VisualInstance3D).layers == od.DIRECT_ONLY
	var only_cam := true
	for v in c.find_children("*", "VisualInstance3D", true, false):
		only_cam = only_cam and (v as VisualInstance3D).layers == od.CAMERA_ONLY
	_check("anomaly: the eye copy is EXACTLY eye-only (the old OR-ed EXTERIOR bit made it show on cameras)", only_direct and not normal.visible)
	_check("anomaly: the camera copy is EXACTLY camera-only", only_cam)
	_check("each copy is SEATED on a bracket shelf (no floating object)", absf(d.global_position.y - (od.BRACKET_A.y + 0.17)) < 0.01 and absf(c.global_position.y - (od.BRACKET_B.y + 0.17)) < 0.01 and absf(c.global_position.x - (od.WALL_X + 0.17)) < 0.01)
	_check("EXT-03 sees both brackets (so the case is visibly somewhere else)", net.sees("EXT-03", od.BRACKET_A + Vector3(0.15, 0.1, 0), 0.0) and net.sees("EXT-03", od.BRACKET_B + Vector3(0.15, 0.1, 0), 0.0))
	_check("the sun lights the story layers (lit like the hull)", main.find_child("Sun", true, false).light_cull_mask & od.DIRECT_ONLY != 0 and main.find_child("Sun", true, false).light_cull_mask & od.CAMERA_ONLY != 0)
	_check("brackets / case add no collision (no hull or EVA obstacle)", od.find_children("*", "CollisionObject3D", true, false).is_empty())
	od.clear()
	_check("cleared: back on bracket A for everyone", normal.visible and not d.visible and not c.visible)


# ------------------------------------------------------------ wrong reading
func _wrong_reading() -> void:
	var stn: Node = main.get_node("StationStatus")
	var plate: Node = main.get_node("Interactables/SensorCalibrationStation/CalStatusPlate")
	dp.l07_status = dp.TaskStatus.PENDING
	plate._process(0.0)
	_check("instrument plate (true state) says CAL DUE before calibration", plate.text == "CAL DUE")
	dp.mark_done(&"l07")                             # the player really calibrated
	_check("calibration completion recorded for the story", se._cal_done.has("l07"))
	se._cal_done["l07"]["t"] = float(dp.shift_elapsed_s) - 30.0
	_check("...and recognised as today's recent calibration", se._recent_cal_task() == "l07")
	se.dev_trigger(&"wrong_reading", "normal", true)
	await process_frame
	var duty: Array = stn.duties().filter(func(x): return String(x["id"]) == "STORY-CAL")
	_check("back at the workstation: 'SENSORS NOT CALIBRATED' (Life Support)", duty.size() == 1 and String(duty[0]["short"]) == "SENSORS NOT CALIBRATED" and duty[0]["room"] == &"life_support")
	plate._process(0.0)
	_check("...while the instrument says CALIBRATED and the task stays done", plate.text.begins_with("CALIBRATED") and dp.is_task_done(&"l07"))
	_check("...and no work order was reopened", not dp.order_rows().any(func(r): return String(r.get("id", "")) == "STORY-CAL"))
	se._on_screen_s = se.CAL_SEEN_S
	await _aim(Vector3(-2.9, 1.6, 10.6), Vector3(-2.9, 1.6, 11.78))
	for i in 4: await process_frame
	_check("checking the instrument in person = investigated, the anomaly ends", se.active == &"" and se.investigation_state("wrong_reading") in ["checked", "contradicted"])
	# Premature AI announcement (variant B).
	dp.l07_status = dp.TaskStatus.PENDING
	var ai: Node = get_first_node_in_group(&"station_ai")
	se.dev_trigger(&"wrong_reading", "abnormal")
	await process_frame
	_check("variant B: the assistant announces a calibration nobody did (story-only line)", ai.LINES.has(&"story_cal_premature") and (ai.taught.has(&"story_cal_premature") or not ai.enabled()))
	plate._process(0.0)
	_check("...the instrument still says CAL DUE (truth intact)", plate.text == "CAL DUE")
	se.dev_cancel()
	dp.l07_status = dp.TaskStatus.PENDING


# ------------------------------------------------------------ hatch
func _hatch() -> void:
	var a: Node = get_first_node_in_group(&"airlock")
	var h: Node3D = a.outer_handles()[0]
	var c: Camera3D = net.camera("EXT-02")
	var hp: Vector2 = c.unproject_position(h.global_position)
	var vs: Vector2 = Vector2(c.get_viewport().size)
	_check("EXT-02 frames the outer hatch handle near the middle (%s of %s)" % [str(hp.round()), str(vs)], absf(hp.x / vs.x - 0.5) < 0.25 and absf(hp.y / vs.y - 0.5) < 0.3)
	var l0: Vector2 = c.unproject_position(h.global_transform * Vector3(-0.22, 0, 0))
	var l1: Vector2 = c.unproject_position(h.global_transform * Vector3(0.22, 0, 0))
	_check("the lever reads on the feed (%.0f px of %d)" % [l0.distance_to(l1), int(vs.y)], l0.distance_to(l1) / vs.y > 0.12)
	var pressure0: float = float(a.get("pressure_kpa")) if "pressure_kpa" in a else 0.0
	se.dev_trigger(&"hatch_handle")
	var copies_ok := true
	for cl in se._hatch_clones:
		for v in (cl as Node).find_children("*", "VisualInstance3D", true, false):
			copies_ok = copies_ok and (v as VisualInstance3D).layers == se.CAMERA_ONLY
	_check("the turning copy is EXACTLY camera-only (the eye never sees it move)", copies_ok and not se._hatch_clones.is_empty())
	var peak := 0.0
	for t in range(0, 140):
		se._active_t = t * 0.1
		peak = maxf(peak, se.hatch_twist_deg())
	se._active_t = 11.0
	_check("a clear turn toward OPEN (peak %.0f deg) and back" % peak, peak >= 75.0 and absf(se.hatch_twist_deg()) < 2.0)
	_check("the REAL latch never moves: no cycle, hatch closed, pressure kept", a.sequence == "" and not a.outer_open and (not "pressure_kpa" in a or is_equal_approx(float(a.get("pressure_kpa")), pressure0)))
	se.dev_cancel()
	await process_frame
	_check("reset: copies removed", se._hatch_clones.is_empty())


# ------------------------------------------------------------ peripheral
const POSES := [[Vector3(-3.0, 1.6, 4.4), Vector3(-0.2, 1.4, 6.6)], [Vector3(-3.6, 1.6, 6.6), Vector3(-4.6, 1.3, 3.4)], [Vector3(-2.2, 1.6, 11.2), Vector3(-0.5, 1.4, 8.0)],
		[Vector3(-1.4, 1.6, 9.9), Vector3(-3.6, 1.3, 11.6)], [Vector3(3.8, 1.6, 2.2), Vector3(2.6, 1.3, -0.8)], [Vector3(0.3, 1.6, -1.0), Vector3(-0.2, 1.4, 3.5)],
		[Vector3(-5.8, 1.6, 9.2), Vector3(-3.4, 1.3, 6.4)], [Vector3(1.6, 1.6, 7.6), Vector3(3.6, 1.3, 7.0)], [Vector3(-0.3, 1.6, 2.4), Vector3(-0.2, 1.4, 7.0)]]


func _peripheral() -> void:
	var pw: Node = se.peripheral
	pw.dev_reset()
	se.dev_set_phase_override(2)
	dp.day_number = 3
	await _aim(Vector3(-3.0, 1.6, 4.4), Vector3(-0.2, 1.4, 6.6))
	pw.set_process(false)
	_check("valid spots validated (floor + clearance): %d" % pw.valid.size(), pw.valid.size() >= 10)
	# Slow turns never trigger.
	for i in 60:
		pw.feed_turn(60.0, 2.0, 1.0 / 30.0)
	pw.feed_turn(0.0, 0.0, 1.0 / 30.0)
	_check("slow head turns never trigger it", not pw.is_shown())
	# A fast turn (forced roll for determinism) does.
	pw.force_next = true
	for i in 8:
		pw.feed_turn(-300.0, 10.0, 1.0 / 30.0)
	pw.feed_turn(0.0, 0.0, 1.0 / 30.0)
	_check("a FAST turn: a figure near the edge", pw.is_shown())
	var spot: Vector3 = pw.last_spot
	var half_h: float = atan(tan(deg_to_rad(cam.fov) * 0.5) * float(cam.get_viewport().get_visible_rect().size.x) / float(cam.get_viewport().get_visible_rect().size.y))
	var to: Vector3 = spot + Vector3(0, 1.62, 0) - cam.global_position
	var frac: float = absf(atan2(to.dot(cam.global_basis.x), to.dot(-cam.global_basis.z))) / half_h
	_check("...on the side turned AWAY from, near the edge (%.2f of half-FOV)" % frac, signf(to.dot(cam.global_basis.x)) == signf(pw.last_side) and frac >= pw.EDGE_MIN and frac <= pw.EDGE_MAX)
	_check("...a clear line of sight (not in / behind a wall)", pw.line_clear(cam.global_position, spot + Vector3(0, 1.62, 0)))
	var lay_ok := true
	for v in pw.fig.find_children("*", "VisualInstance3D", true, false):
		lay_ok = lay_ok and (v as VisualInstance3D).layers == (1 << 19) and (v as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check("...eyes only, no shadow, no collision", lay_ok and pw.fig.find_children("*", "CollisionObject3D", true, false).is_empty())
	await _aim(cam.global_position, spot + Vector3(0, 1.4, 0))
	pw._track_shown(0.016, cam)
	_check("looking back at it: gone", not pw.is_shown())
	_check("once a day only", not pw.eligible_today())
	pw.dev_reset()
	# Perspective: same edge, near vs far -> apparent height ~ 1/distance.
	var hs: Array = []
	for rng in [[1.8, 3.2], [5.0, 13.0]]:
		var found := false
		for pose in POSES:
			for side in [1.0, -1.0]:
				if found:
					break
				await _aim(pose[0], pose[1])
				pw.rooms_recent = []
				var sp: Vector3 = pw.pick_spot(cam, side, rng[0], rng[1])
				if sp != Vector3.INF:
					var top: Vector2 = cam.unproject_position(sp + Vector3(0, 1.72, 0))
					var bot: Vector2 = cam.unproject_position(sp)
					var dd: float = Vector2(sp.x - cam.global_position.x, sp.z - cam.global_position.z).length()
					hs.append([dd, absf(bot.y - top.y)])
					found = true
			if found:
				break
	_check("near and far placements found (%s)" % str(hs), hs.size() == 2)
	if hs.size() == 2:
		var ratio_h: float = hs[0][1] / hs[1][1]
		var ratio_d: float = hs[1][0] / hs[0][0]
		_check("perspective-correct size: near/far height %.2f ~ distance ratio %.2f" % [ratio_h, ratio_d], absf(ratio_h - ratio_d) / ratio_d < 0.35)
	# Different FOV settings: still within the edge band.
	for f in [60.0, 90.0]:
		var f0: float = cam.fov
		cam.fov = f
		var ok := false
		for pose in POSES:
			if ok:
				break
			await _aim(pose[0], pose[1])
			pw.rooms_recent = []
			var sp2: Vector3 = pw.pick_spot(cam, 1.0)
			if sp2 != Vector3.INF:
				var hh: float = atan(tan(deg_to_rad(cam.fov) * 0.5) * float(cam.get_viewport().get_visible_rect().size.x) / float(cam.get_viewport().get_visible_rect().size.y))
				var t2: Vector3 = sp2 + Vector3(0, 1.62, 0) - cam.global_position
				var fr2: float = absf(atan2(t2.dot(cam.global_basis.x), t2.dot(-cam.global_basis.z))) / hh
				ok = fr2 >= pw.EDGE_MIN and fr2 <= pw.EDGE_MAX
		_check("FOV %.0f: placed in the edge band (some view)" % f, ok)
		cam.fov = f0
	# Gating + save/load.
	pw.dev_reset()
	se.dev_set_phase_override(1)
	_check("not in phase 1", not pw.eligible_today())
	se.dev_set_phase_override(2)
	fb.guide_target = Vector3(0, 1.6, 0)
	_check("never while something else owns movement (guided walk)", not pw.can_happen())
	fb.guide_target = Vector3.INF
	var reduced_old: bool = bool(preload("res://scripts/station/game_settings.gd").get_value("reduce_effects"))
	preload("res://scripts/station/game_settings.gd")._values["reduce_effects"] = true
	await _aim(Vector3(-3.0, 1.6, 4.4), Vector3(-0.2, 1.4, 6.6))
	var spr: Vector3 = pw.pick_spot(cam, 1.0, 1.0, 3.5)
	_check("reduced effects: never close (no near spot accepted)", spr == Vector3.INF or Vector2(spr.x - cam.global_position.x, spr.z - cam.global_position.z).length() >= pw.REDUCED_MIN_D)
	preload("res://scripts/station/game_settings.gd")._values["reduce_effects"] = reduced_old
	pw.seen_day = 3
	pw.rooms_recent = ["engineering"]
	var sd: Dictionary = JSON.parse_string(JSON.stringify(pw.state_dict()))
	pw.dev_reset()
	pw.load_dict(sd)
	_check("save/load keeps the day + recent rooms (no repeats)", pw.seen_day == 3 and pw.rooms_recent == ["engineering"])
	pw.dev_reset()
	pw.set_process(true)
	se.dev_set_phase_override(0)
	dp.day_number = 1


# ------------------------------------------------------------ window figure
func _window_figure() -> void:
	var we: Node = se.window
	var f: Node3D = we.figure
	f.appear()
	f.set_process(false)
	await _aim(we.OBS_SPOT, Vector3(-4.3, 1.55, 2.5))
	for i in 3: await process_frame
	_check("the figure stands ON the sight line through both ports (observable from the spot)", we.observable())
	var eb: Vector2 = load("res://scripts/exterior/exterior_builder.gd").TUNNEL_PORT_SIZE
	_check("the tunnel port was enlarged to read at distance (%s)" % str(eb), eb.x >= 0.7 and eb.y >= 0.55)
	# Round 48: the sequence was redesigned (see test_r48_window_figure for
	# the full measured timeline); the Round 46 intents, re-expressed:
	f.state = "idle"
	f.step_pose(0.3)
	var h0: Vector3 = f._head.global_basis.x
	f.state = "react"
	f.step_pose(f.TURN_AT + 0.2)
	_check("1-4: still, then the head turns at unnatural speed (%.0f deg)" % rad_to_deg(h0.angle_to(f._head.global_basis.x)), rad_to_deg(h0.angle_to(f._head.global_basis.x)) > 50.0)
	var off0: Array = [f._arms[1][1].position, f._head.position]
	f.state = "react"
	f.step_pose(f.SHUDDER_AT - 0.05)
	var up: float = (f._chest.global_transform.affine_inverse() * f._arms[f.RAISED][0].global_position).y
	var dn: float = (f._chest.global_transform.affine_inverse() * f._arms[f.DEAD][0].global_position).y
	_check("5-6: asymmetric -- one shoulder hitched %.2f m above the other" % (up - dn), up - dn > 0.05)
	_check("limbs stay attached", [f._arms[1][1].position, f._head.position] == off0)
	var ebc: Vector3 = load("res://scripts/exterior/exterior_builder.gd").TUNNEL_PORT_CENTRE
	f.state = "retreat"
	f.step_pose(f.RETREAT_HOLD + f.RETREAT_SLOW_S * 0.5)
	var z_early: float = f.position.z
	f.state = "retreat"
	f.step_pose(f.RETREAT_HOLD + f.RETREAT_SLOW_S)
	var z_mid: float = f.position.z
	f.state = "retreat"
	f.step_pose(f.RETREAT_S * 0.97)
	var hp: Vector3 = f.head_point()
	_check("7: abrupt sideways retreat, speed jumps (%.2f -> %.2f -> %.2f)" % [z_early, z_mid, f.position.z], (f.position.z - z_mid) > (z_mid - z_early) * 3.0 and f.position.z - we.FIGURE_POS.z > 0.6)
	var dirv: Vector3 = hp - cam.global_position
	var kk: float = (ebc.x - cam.global_position.x) / dirv.x
	var hit: Vector3 = cam.global_position + dirv * kk
	_check("8: it ends up behind the frame (sight line misses the port opening)", absf(hit.z - ebc.z) > eb.x * 0.5)
	f.reset()
	# Focus (squint) while staring at it; never with reduced effects.
	we.stage = "showing"
	f.appear()
	var fov0: float = cam.fov
	for i in 60:
		we._update_focus(1.0 / 30.0)
	_check("staring at the far port: the view narrows gently (%.0f -> %.0f deg)" % [fov0, cam.fov], cam.fov < fov0 * 0.6)
	we.stage = "done"
	f.reset()
	for i in 60:
		we._update_focus(1.0 / 30.0)
	_check("...and returns exactly when it is over", is_equal_approx(cam.fov, fov0))
	preload("res://scripts/station/game_settings.gd")._values["reduce_effects"] = true
	we.stage = "showing"
	f.appear()
	for i in 30:
		we._update_focus(1.0 / 30.0)
	_check("reduced effects: no focus zoom", is_equal_approx(cam.fov, fov0))
	preload("res://scripts/station/game_settings.gd")._values["reduce_effects"] = false
	we.stage = "locked"
	f.reset()


# ------------------------------------------------------------ guidance
func _guidance() -> void:
	var we: Node = se.window
	var starts := [Vector3(0.6, 1.6, -0.4), Vector3(0.9, 1.6, 0.9), Vector3(-0.8, 1.6, -0.7), Vector3(0.2, 1.6, 1.7)]
	for s in starts:
		await _aim(s, Vector3(-1.2, 1.5, 1.2))
		var route: Array = we.route_to(fb.current_eye_position(), we.OBS_SPOT)
		var legs_ok: bool = not route.is_empty()
		var prev: Vector3 = fb.current_eye_position()
		for wp in route:
			legs_ok = legs_ok and we._capsule_free(_space(), prev, wp, [fb.get_rid()], prev == fb.current_eye_position())
			prev = wp
		_check("route from %s: %d waypoint(s), every leg clear of furniture" % [str(s), route.size()], legs_ok and (route.back() as Vector3).distance_to(we.OBS_SPOT) < 0.05)
	# Furniture in the straight line: the route must go AROUND it.
	var crate := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.7, 1.0, 0.7)
	cs.shape = bx
	crate.add_child(cs)
	main.add_child(crate)
	crate.global_position = Vector3(0.08, 0.5, 0.37)
	await physics_frame
	await physics_frame
	await _aim(Vector3(0.6, 1.6, -0.4), Vector3(-1.2, 1.5, 1.2))
	var route2: Array = we.route_to(fb.current_eye_position(), we.OBS_SPOT)
	var legs2: bool = route2.size() >= 2
	var pv: Vector3 = fb.current_eye_position()
	for wp in route2:
		legs2 = legs2 and we._capsule_free(_space(), pv, wp, [fb.get_rid()], pv == fb.current_eye_position())
		pv = wp
	_check("an obstacle in the straight line: routed around it (%d waypoints, every leg clear)" % route2.size(), legs2)
	fb.guide_cancelled = false
	fb.guide_target = route2[0]
	fb.guide_path = route2.slice(1)
	var t := 0.0
	while fb.guide_target != Vector3.INF and t < 12.0:
		await physics_frame
		t += 1.0 / 60.0
	var end: Vector3 = fb.current_eye_position()
	_check("the guided walk (real physics) gets round it and arrives (%.2f m, %.1f s)" % [Vector2(end.x - we.OBS_SPOT.x, end.z - we.OBS_SPOT.z).length(), t], Vector2(end.x - we.OBS_SPOT.x, end.z - we.OBS_SPOT.z).length() < 0.3 and t > 0.5)
	crate.queue_free()
	fb.guide_target = Vector3(0.6, 1.6, -0.4)
	fb.guide_path = [Vector3(0.0, 1.6, 0.0)]
	var e := InputEventKey.new()
	e.keycode = KEY_S
	e.physical_keycode = KEY_S
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	await physics_frame
	e.pressed = false
	Input.parse_input_event(e)
	_check("any movement key cancels the guided walk and its whole route", fb.guide_target == Vector3.INF and fb.guide_path.is_empty())


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
