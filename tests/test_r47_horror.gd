extends SceneTree
## Round 47 horror quality (Priorities 2-16, 24, 32):
##   WINDOW FIGURE   articulated silhouette (separate legs, long arms with
##                   hands, uneven shoulders, long neck), six readable
##                   stages, the movement MEASURED from the real
##                   observation spot (on-screen size and travel), retreat
##                   behind real geometry, gating unchanged, developer
##                   replay / slow motion / status;
##   WINDOW HAND     a separate registered event: real 3D hand outside
##                   the Control Room glass, structure-borne knocks FROM the
##                   port, brief visibility, withdrawal behind the rim, no
##                   collision, pacing / gating, investigation, dev reset;
##   CORRIDOR        odd walk, then an impossible surge (speed measured),
##                   still on INT-02 long enough, camera-only;
##   MISMATCHES      three NEW distinct variants with stable ids, exact
##                   layers, no real environment change, family pacing.
## Runs WINDOWED (needs the real 16:9 view for on-screen measurements).
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
	main.get_node("StationAI").set_enabled(false)
	await _window_figure()
	await _window_hand()
	_corridor()
	await _mismatches()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _space() -> PhysicsDirectSpaceState3D:
	return (fb as Node3D).get_world_3d().direct_space_state


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


## Fraction of the view height a world segment spans on screen.
func _screen_frac(a: Vector3, b: Vector3) -> float:
	return absf(cam.unproject_position(a).y - cam.unproject_position(b).y) / float(cam.get_viewport().get_visible_rect().size.y)


func _screen_dist(a: Vector3, b: Vector3) -> float:
	return cam.unproject_position(a).distance_to(cam.unproject_position(b)) / float(cam.get_viewport().get_visible_rect().size.y)


# ---------------------------------------------------------- window figure
func _window_figure() -> void:
	var we: Node = se.window
	var f: Node3D = we.figure
	var meshes: Array = f.find_children("*", "MeshInstance3D", true, false)
	_check("articulated body: separate legs, arms with forearm + wrist + fingers (%d parts)" % meshes.size(), f._legs.size() == 2 and f._arms[-1].size() == 3 and f._arms[1].size() == 3 and meshes.size() >= 20)
	_check("uneven shoulders (one side drops more)", absf(float(f.SHOULDER_SLOPE[-1]) - float(f.SHOULDER_SLOPE[1])) >= 5.0)
	f.appear()
	f.set_process(false)
	f.step_pose(0.0)
	var head_top: float = f.head_point().y
	var reach: float = (f.hand_point(1) - f._arms[1][0].global_position).length() + 0.15
	_check("believable height (head %.2f m), arms slightly too long (%.2f m)" % [head_top, reach], head_top > 1.7 and head_top < 1.95 and reach > 0.82)
	_check("eye-only, no collision, no shadow", meshes.all(func(m): return (m as GeometryInstance3D).layers == f.DIRECT_ONLY and (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) and f.find_children("*", "CollisionObject3D", true, false).is_empty())
	await _aim(we.OBS_SPOT, we.FIGURE_POS + Vector3(0, 1.4, 0))
	_check("observable from the real observation spot (through both ports)", we.observable())
	# How large it reads (normal FOV, before any focus zoom).
	var torso_frac: float = _screen_frac(f.head_point(), f._hips.global_position)
	_check("readable: head-to-hips spans %.1f%% of the view at the normal FOV" % (torso_frac * 100.0), torso_frac > 0.06)
	# The body is visible through the tunnel port (not only head + shoulders).
	var hip: Vector3 = f._hips.global_position + Vector3(0, 0.1, 0)
	var eye: Vector3 = cam.global_position
	var d: Vector3 = hip - eye
	var k: float = (-4.2 - eye.x) / d.x
	var at_port: Vector3 = eye + d * k
	var eb: Script = load("res://scripts/exterior/exterior_builder.gd")
	var sill: float = eb.TUNNEL_PORT_CENTRE.y - eb.TUNNEL_PORT_SIZE.y * 0.5
	_check("the torso down to the hips is inside the tunnel port's frame (sight line at y %.2f > sill %.2f)" % [at_port.y, sill], at_port.y > sill)
	# Stages, in order, with measured on-screen movement.
	var names: Array = []
	var head_px: Array = []
	var hand_px: Array = []
	f.state = "react"
	f.t = 0.0
	var dt := 1.0 / 60.0
	var tt := 0.0
	while f.state == "react" and tt < 5.0:
		f.t = tt
		f.step_pose(tt)
		var nm: String = f.stage_name()
		if names.is_empty() or names.back() != nm:
			names.append(nm)
		head_px.append(cam.unproject_position(f.head_point()))
		hand_px.append(cam.unproject_position(f.hand_point(f.RAISED)))
		tt += dt
	_check("stages in order: %s" % str(names), names == ["recognition", "first_movement", "shudder", "retreat"])
	_check("recognition is a real PAUSE (%.2f s) before anything happens" % f.RECOG_END, f.RECOG_END >= 0.6)
	# First movement: a SNAP -- most of it within ~70 ms.
	var i0: int = int(f.RECOG_END / dt)
	var snap_px: float = head_px[i0 + 5].distance_to(head_px[i0 - 1]) / float(cam.get_viewport().get_visible_rect().size.y)
	_check("first movement is abrupt: the head jumps %.1f%% of the view in 80 ms" % (snap_px * 100.0), snap_px > 0.02)
	# Shudder: stepped jerks -- many large frame-to-frame jumps.
	var i1: int = int(f.FIRST_END / dt)
	var jumps := 0
	var hand_travel := 0.0
	for i in range(i1 + 1, head_px.size()):
		if head_px[i].distance_to(head_px[i - 1]) > 2.0:
			jumps += 1
		hand_travel = maxf(hand_travel, hand_px[i].distance_to(hand_px[i1]))
	_check("shudder: %d visible head jerks (stepped, not a smooth sway)" % jumps, jumps >= 8)
	_check("one arm rises out of sync: the hand travels %.0f px on screen" % hand_travel, hand_travel / float(cam.get_viewport().get_visible_rect().size.y) > 0.05)
	_check("...while the other hangs (dead arm %.0f deg max)" % rad_to_deg(absf(f._arms[f.DEAD][0].rotation.x)), absf(f._arms[f.DEAD][0].rotation.x) < deg_to_rad(15.0))
	# The shudder's end hands over to the retreat.
	_check("then the impossible retreat", f.state == "retreat" and f.t == 0.0)
	var zs: Array = []
	var visible_at_end := true
	var r := 0.0
	while f.state == "retreat" and r < 2.0:
		r += dt
		f.t = r
		f.step_pose(r)
		zs.append(f.position.z)
		if f.state == "retreat" and r > f.RETREAT_S * 0.9:
			var hp: Vector3 = f.head_point()
			var dv: Vector3 = hp - cam.global_position
			var kk: float = (-4.2 - cam.global_position.x) / dv.x
			var hit: Vector3 = cam.global_position + dv * kk
			visible_at_end = absf(hit.z - 2.5) < eb.TUNNEL_PORT_SIZE.x * 0.5 + 0.02
	var speed: float = (float(zs[-2]) - float(zs[-6])) / (4.0 * dt) if zs.size() > 6 else 0.0
	_check("retreat glides at an inhuman speed at the end (%.1f m/s)" % speed, speed > 4.0)
	var accel := true
	for i in range(2, zs.size() - 1):
		accel = accel and (float(zs[i]) - float(zs[i - 1])) >= (float(zs[i - 1]) - float(zs[i - 2])) - 0.0005
	_check("...accelerating, feet still (no walk cycle)", accel)
	_check("disappears behind the port frame (sight line leaves the opening), never mid-glass", not visible_at_end and not f.visible)
	# Reduced effects: the slow shudder.
	f.reset()
	f.appear()
	f.reduced = true
	f.state = "react"
	var rj := 0
	var last: Vector2 = Vector2.ZERO
	for i in 60:
		var t2: float = f.FIRST_END + i * dt
		f.step_pose(t2)
		var p: Vector2 = cam.unproject_position(f.head_point())
		if i > 0 and p.distance_to(last) > 2.0:
			rj += 1
		last = p
	_check("reduced effects: far fewer jerks per second (%d in 1 s)" % rj, rj <= 4)
	f.reduced = false
	f.reset()
	# Developer: replay, slow motion, status; gating unchanged.
	we.dev_replay_slow()
	_check("developer slow-motion replay (x%.2f), reacting" % f.time_scale, is_equal_approx(f.time_scale, 0.25) and we.stage == "reacting" and f.state == "react")
	_check("developer status line shows the true stage", we.dev_status().find("recognition") != -1)
	we.dev_reset()
	_check("reset: figure hidden, time scale normal", not f.visible and is_equal_approx(f.time_scale, 1.0) and we.stage == "locked")
	dp.day_number = 1
	_check("gating unchanged: never on day 1", not we.is_ready_now())


# ------------------------------------------------------------ window hand
func _window_hand() -> void:
	_check("registered event with a stable id, medium tier, implemented", se.EVENTS.has(&"window_hand") and se.tier(&"window_hand") == "medium" and se.is_enabled(&"window_hand"))
	se.story_phase = 1
	se.dev_set_phase_override(0)
	_check("never during orientation: phase 1 cannot arm it ('%s')" % se.eligibility(&"window_hand"), se.eligibility(&"window_hand").begins_with("needs phase 2"))
	se.story_phase = 2
	# Live conditions.
	dp.day_number = 4
	se.feed_days = {}
	se.dev_set_phase_override(2)
	dp.shift_elapsed_s = 120.0
	await _aim(Vector3(0.3, 1.6, 0.4), Vector3(1.5, 1.4, -0.8))      # in the Control Room, facing away
	_check("needs the window known from an earlier day", not se._hand_ready())
	se.feed_days["PORT"] = [3]
	_check("ready: Control Room, facing away, window known, after the first minute", se._hand_ready())
	await _aim(Vector3(0.3, 1.6, 0.4), Vector3(-1.2, 1.5, 1.4))
	_check("...not while already looking at the port (the knock must make you turn)", not se._hand_ready())
	se.window.witnessed_day = 4
	await _aim(Vector3(0.3, 1.6, 0.4), Vector3(1.5, 1.4, -0.8))
	_check("...never on the day of the window-figure encounter", not se._hand_ready())
	se.window.witnessed_day = -1
	# The event itself.
	var snd: Node = main.get_tree().get_first_node_in_group(&"station_sounds")
	snd.heard = []
	se.dev_trigger(&"window_hand")
	se.set_process(false)
	var h: Node3D = se.hand_node()
	var parts: Array = h.find_children("*", "MeshInstance3D", true, false)
	_check("a real 3D hand (palm, 8 finger segments, thumb, forearm: %d parts), eye-only, no collision" % parts.size(), parts.size() >= 11 and parts.all(func(m): return (m as GeometryInstance3D).layers == h.DIRECT_ONLY) and h.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("on the EXTERIOR side of the outer pane (x %.3f < -1.547)" % h.focus_point().x, h.focus_point().x < -1.547 and h.focus_point().x > -1.7)
	for i in 40:
		h.tick(1.0 / 30.0, false)
	var knocks: Array = snd.heard.filter(func(e): return e["kind"] == "glass_knock")
	_check("three soft taps, structure-borne, FROM the port (%d)" % knocks.size(), knocks.size() == 3 and knocks.all(func(e): return (e["pos"] as Vector3).distance_to(Vector3(-1.47, 1.4, 1.5)) < 0.05))
	_check("...not an airborne knock beside the player (they come from %.1f m away)" % float(knocks[0]["dist"]), float(knocks[0]["dist"]) > 1.2)
	_check("still pressed to the glass while unseen", h.state == "wait" and h.visible)
	# Look at it: brief, then withdraws behind the rim.
	await _aim(Vector3(0.3, 1.6, 1.2), h.focus_point())
	_check("seen through the opening", h.is_seen_by(cam))
	h.tick(1.0 / 30.0, true)
	var t := 0.0
	var vis_t := 0.0
	while h.state != "gone" and t < 3.0:
		h.tick(1.0 / 30.0, false)
		t += 1.0 / 30.0
		if h.visible:
			vis_t += 1.0 / 30.0
	_check("visible only for a moment after being seen (%.2f s)" % vis_t, vis_t > 0.4 and vis_t < 1.2)
	h.state = "withdraw"
	h._seen_t = h.WITHDRAW_S * 0.98
	h._pose(0.0)
	_check("withdraws BEHIND the rim / hull (no sight line through the port at the end)", not h.sight_through_port(cam.global_position, h.focus_point()))
	h.state = "gone"
	se.set_process(true)
	se.dev_cancel()
	_check("cancel frees the hand (no hidden actor left behind)", se.hand_node() == null)
	# A real (counted) play -> investigation.
	se.dev_trigger(&"window_hand", "normal", true)
	var h2: Node3D = se.hand_node()
	h2.seen = true
	h2.state = "gone"
	await process_frame
	await process_frame
	_check("seen -> observation + a pending physical check", se.investigation_state("window_hand") == "observed" and se._pending_investigation.has("window_hand"))
	await _aim(Vector3(-0.55, 1.55, 1.42), Vector3(-1.2, 1.45, 1.42))
	# The check needs ~1 s of looking (game time), not a frame count.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and se.investigation_state("window_hand") != "checked":
		await process_frame
	_check("going right up to the glass = checked (a quiet thought)", se.investigation_state("window_hand") == "checked" and se.inner.said.has("hand_check"))
	se.on_record_checked("airlock_log")
	_check("the airlock record: no EVA today (contradiction, no narration)", se.investigation_state("window_hand") == "contradicted" and String(se.RECORD_LINKS["airlock_log"]["by_event"]["window_hand"]).find("No EVA") != -1)
	_check("journal remembers it", main.get_tree().get_first_node_in_group(&"journal").has("obs:window_hand"))
	se.dev_reset(&"window_hand")
	_check("developer reset", int(se.state[&"window_hand"]["plays"]) == 0)
	se.dev_set_phase_override(0)
	dp.day_number = 1



# ------------------------------------------------------------- corridor
func _corridor() -> void:
	se.dev_trigger(&"corridor_presence")
	var pn: Node3D = se.presence_node()
	pn.set_process(false)
	var dt := 1.0 / 60.0
	var t := 0.0
	var walk_v: Array = []
	var surge_v: Array = []
	var on_feed := 0.0
	var prev: float = pn.travelled
	while pn.state == "walk" and t < 20.0:
		pn.step(dt)
		t += dt
		var v: float = (pn.travelled - prev) / dt
		prev = pn.travelled
		if pn._post_t < 0.0 and v > 0.0:
			walk_v.append(v)
		elif pn._post_t > pn.SURGE_RAMP_S:
			surge_v.append(v)
		if net.sees("INT-02", pn.head_point(), 0.0):
			on_feed += dt
	var wmax: float = walk_v.max() if not walk_v.is_empty() else 0.0
	var smean: float = 0.0
	for v in surge_v:
		smean += v
	smean = smean / maxf(surge_v.size(), 1)
	_check("begins as an odd walk (max %.2f m/s, a human pace)" % wmax, wmax > 0.6 and wmax < 1.3)
	_check("then an impossible surge (%.1f m/s)" % smean, smean > 2.8)
	_check("still on INT-02 long enough to recognise (%.1f s), never in one frame (total %.1f s)" % [on_feed, t], on_feed >= 2.5 and t >= 3.5)
	_check("Comms -> Engineering, gone afterwards", pn.global_position.x < -1.5 and not pn.visible)
	_check("camera-only throughout", pn.find_children("*", "VisualInstance3D", true, false).all(func(v): return (v as VisualInstance3D).layers == se.CAMERA_ONLY))
	_check("a lit body, not a flat cut-out (specular sheen)", pn._mat.metallic_specular > 0.1 and pn._mat.roughness < 0.9)
	se.dev_cancel()


# ----------------------------------------------------------- mismatches
func _mismatches() -> void:
	var od: Node = main.get_tree().get_first_node_in_group(&"observation_discrepancy")
	for id in [&"mismatch_shadow", &"mismatch_daynight", &"mismatch_eva"]:
		_check("registered with a stable id: %s" % id, se.EVENTS.has(id) and se.is_enabled(id) and se.MISMATCH_FAMILY.has(String(id)))
	_check("the maintenance-case mismatch is kept", od.MODES.has("displaced") and se.EVENTS.has(&"window_mismatch"))
	var oc: Node = main.get_node("Equipment/OrbitalCycle")
	var sun: DirectionalLight3D = main.find_child("Sun", true, false)
	oc.load_dict({"phase_s": 120.0})
	await process_frame
	var sun_e: float = sun.light_energy
	var sun_r: Vector3 = sun.rotation
	var orbit_off: float = float(oc.offset_s)
	# SHADOW
	od.trigger("shadow", 30.0, "debug")
	var sh: Node = od._objs["shadow_cam"]
	_check("shadow: a projected decal (wraps the hull), EXACTLY camera-only", sh is Decal and (sh as VisualInstance3D).layers == od.CAMERA_ONLY and (sh as Node3D).visible)
	_check("shadow: the reference case shadow is shown to every view", od.case_shadow.visible and od.case_shadow.layers == od.EXTERIOR)
	_check("shadow: EXT-03 sees the wall where it falls; the player's eyes cannot render it", net.sees("EXT-03", od.SHADOW_CENTRE + Vector3(0.1, 0.3, 0), 0.0) and cam.cull_mask & od.CAMERA_ONLY == 0)
	od.clear()
	_check("shadow cleared", not (sh as Node3D).visible)
	# DAY / NIGHT
	od.trigger("daynight", 30.0, "debug")
	var c3: Camera3D = net.camera("EXT-03")
	_check("day/night: EXT-03 alone gets the graded environment", od.ext03_night() and c3.environment != null and net.camera("EXT-02").environment == null and cam.environment == null)
	_check("day/night: NOT black -- landmarks kept (brightness %.2f)" % c3.environment.adjustment_brightness, c3.environment.adjustment_brightness >= 0.5)
	_check("day/night: the real sun / orbit untouched", is_equal_approx(sun.light_energy, sun_e) and sun.rotation.is_equal_approx(sun_r) and is_equal_approx(float(oc.offset_s), orbit_off))
	od.clear()
	_check("day/night cleared: EXT-03's own environment restored", not od.ext03_night() and c3.environment == null)
	# EVA WORKER
	od.trigger("eva_window", 30.0, "debug")
	var w: Node3D = od._objs["eva_worker"]
	var wparts: Array = w.find_children("*", "MeshInstance3D", true, false)
	_check("phantom EVA worker: a suited figure, window-only, no collision", w.visible and wparts.size() >= 12 and wparts.all(func(m): return (m as VisualInstance3D).layers == od.DIRECT_ONLY) and w.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("...standing in the real A1 foot restraints, facing the feed box", w.global_position.distance_to(od.WORKER_POS) < 0.01)
	var eva: Node = main.get_tree().get_first_node_in_group(&"eva_system")
	var al: Node = main.get_tree().get_first_node_in_group(&"airlock")
	_check("...no real EVA / airlock state (not suited, no EVA, outer hatch shut)", not bool(eva.get("suited")) and not eva.is_eva_active() and not bool(al.get("outer_open")))
	for i in 20:
		await process_frame
	od.clear()
	# Story: family pacing, no developer labels.
	dp.day_number = 10
	se.dev_set_phase_override(2)
	se.state[&"mismatch_shadow"]["plays"] = 1
	se.state[&"mismatch_shadow"]["last_day"] = 9
	_check("never two window/camera contradictions within 2 days ('%s')" % se.eligibility(&"mismatch_eva"), se.eligibility(&"mismatch_eva").begins_with("pacing"))
	se.state[&"mismatch_shadow"] = se._blank()
	se.dev_trigger(&"mismatch_daynight")
	_check("developer can force each variant", se.active == &"mismatch_daynight" and od.active_mode == "daynight")
	se.dev_cancel()
	_check("cancel clears it", od.active_mode == "" and not od.ext03_night())
	var labels_ok := true
	for l in main.find_children("*", "Label3D", true, false):
		if String((l as Label3D).text).find("MISMATCH") != -1:
			labels_ok = false
	_check("no developer label in the world ('MISMATCH ACTIVE' never shown)", labels_ok)
	se.dev_set_phase_override(0)
	dp.day_number = 1


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
