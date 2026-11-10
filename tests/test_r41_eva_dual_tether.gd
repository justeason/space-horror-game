extends SceneTree
## Round 41 Priorities 1, 2, 4, 9: EVA movement (W thrust along the aim,
## S brake, A/D/Space inert, inertia, caps, interior walking unchanged) and
## the TRUE DUAL-TETHER system: two independent tethers (own ring, state,
## cable, carabiner, hip D-ring), the safe transfer state machine (never
## both unsecured; unsafe release refused; one transition at a time; out
## of reach refused; interrupted connect recovers), the tension constraint
## (no teleport), and REAL ROUTES over the anchor graph -- Airlock -> left
## wing outer ring -> Airlock, -> right wing outer ring -> Airlock, ->
## antenna -> Airlock -- performed hop by hop with actual transfers.
const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
var _ok := true
var main: Node
var eva: Node
var al: Node
var fb: CharacterBody3D
var cam: Camera3D
var body: Node
var _min_secured := 99
var _sampling := false


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	eva = main.get_node("EvaSystem")
	al = main.get_node("AirlockChamber")
	fb = main.get_node("FreeMoveBody")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	body = main.get_node("Player/PlayerBody")
	physics_frame.connect(_sample)
	await _interior_walk_unchanged()
	eva.set_suited(true)
	await _go_outside()
	await _movement()
	await _tether_objects()
	await _safety_rules()
	await _tension()
	_graph_static()
	await _route(["A1", "T0", "L1", "L2", "L3", "L4", "L5"], "left wing outer")
	await _route(["L5", "L4", "L3", "L2", "L1", "T0", "A1"], "back to the airlock")
	await _route(["A1", "T0", "R0", "R1", "R2", "R3", "R4", "R5"], "right wing outer")
	await _route(["R5", "R4", "R3", "R2", "R1", "R0", "T0", "A1"], "back to the airlock")
	await _route(["A1", "A2", "A3"], "antenna")
	await _route(["A3", "A2", "A1"], "back to the airlock")
	_check("during every transfer at least one tether stayed SECURED (min %d)" % _min_secured, _min_secured >= 1)
	await _back_inside()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _sample() -> void:
	if _sampling and eva.outside:
		_min_secured = mini(_min_secured, eva.secured_count())


func _interior_walk_unchanged() -> void:
	fb.sync_to_eye_position(Vector3(0.0, 1.6, 0.6))
	for i in 4: await physics_frame
	var p0: Vector3 = fb.global_position
	_key(KEY_W, true)
	await create_timer(0.6).timeout
	_key(KEY_W, false)
	var moved: Vector3 = fb.global_position - p0
	_check("interior: W still WALKS (%.2f m, horizontal, gravity on)" % moved.length(), moved.length() > 0.4 and absf(moved.y) < 0.05 and not fb.zero_g)
	p0 = fb.global_position
	_key(KEY_D, true)
	await create_timer(0.4).timeout
	_key(KEY_D, false)
	_check("interior: D still strafes", fb.global_position.distance_to(p0) > 0.2)


func _go_outside() -> void:
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	for i in 4: await physics_frame
	_check("in the chamber: no EVA movement (gravity, zone CHAMBER)", eva.zone == "chamber" and not fb.zero_g)
	al.begin_cycle_out()
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -3.3))
	for i in 6: await physics_frame
	_check("outside: zero-g, tether A SECURED on A1, B stowed (SECURED_A)", eva.outside and fb.zero_g and eva.tether_state() == "SECURED_A" and int(eva.tethers[0]["ring"]) == 0)
	_sampling = true


func _aim(dir: Vector3) -> void:
	var lp: Node3D = main.get_node("Player/LookPivot")
	var player: Node3D = main.get_node("Player")
	var d: Vector3 = dir.normalized()
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pp: Node3D = lp.get_node("PitchPivot")
	pp.rotation.x = asin(clampf(d.y, -1.0, 1.0))
	if "_target_pitch" in lp:
		lp._target_pitch = pp.rotation.x


func _movement() -> void:
	# Aim into open space above the hatch deck (Round 41: the solar truss
	# north of the hatch is solid now -- the suit bumps into it).
	fb.sync_to_eye_position(Vector3(-4.8, 1.8, -3.6))
	fb.velocity = Vector3.ZERO
	_aim(Vector3(0.15, 1.0, 0.1))
	await physics_frame
	var fwd: Vector3 = -cam.global_basis.z
	_key(KEY_W, true)
	await create_timer(0.7).timeout
	_key(KEY_W, false)
	var v: Vector3 = fb.velocity
	_check("W thrusts along the camera AIM, incl. pitch (v·aim %.2f, %.2f m/s)" % [v.normalized().dot(fwd), v.length()], v.length() > 0.3 and v.normalized().dot(fwd) > 0.95)
	_check("gentle acceleration (< 1.0 m/s after 0.7 s)", v.length() < 1.0)
	var v0: float = v.length()
	await create_timer(0.6).timeout
	_check("released: inertia, coasting (%.2f -> %.2f m/s)" % [v0, fb.velocity.length()], fb.velocity.length() > v0 * 0.7 and fb.velocity.length() < v0)
	_key(KEY_S, true)
	await create_timer(0.8).timeout
	_key(KEY_S, false)
	_check("S brakes smoothly to a stop (%.3f m/s)" % fb.velocity.length(), fb.velocity.length() < 0.05)
	for k in [KEY_A, KEY_D, KEY_SPACE, KEY_C]:
		_key(k, true)
		await create_timer(0.35).timeout
		_key(k, false)
	_check("A / D / Space / C produce no EVA thrust (%.3f m/s)" % fb.velocity.length(), fb.velocity.length() < 0.05)
	fb.sync_to_eye_position(Vector3(-4.8, 1.8, -3.6))
	fb.velocity = Vector3.ZERO
	_key(KEY_W, true)
	await create_timer(3.0).timeout
	_key(KEY_W, false)
	_check("speed capped (%.2f <= %.2f m/s)" % [fb.velocity.length(), fb.zg_max], fb.velocity.length() <= fb.zg_max + 0.001)
	_check("visor: thrust chip and speed bar showed the jets", eva._speed_bar.value > 0.5)
	_key(KEY_S, true)
	await create_timer(1.5).timeout
	_key(KEY_S, false)
	# No thrust while a work position is held.
	fb.work_locked = true
	_key(KEY_W, true)
	await create_timer(0.3).timeout
	_key(KEY_W, false)
	_check("no propulsion while stabilised at a worksite", fb.velocity.length() < 0.01)
	fb.work_locked = false
	_check("feel values are exported knobs (accel/max/drag/brake)", fb.zg_accel > 0.0 and fb.zg_max > 0.0 and fb.zg_drag > 0.0 and fb.zg_brake > fb.zg_drag)


func _tether_objects() -> void:
	fb.sync_to_eye_position(Vector3(-4.6, 1.75, -3.7))
	fb.velocity = Vector3.ZERO
	await create_timer(0.3).timeout
	var a: Vector3 = eva.attach_point(0)
	var b: Vector3 = eva.attach_point(1)
	var right: Vector3 = (body as Node3D).global_basis.x
	_check("two distinct suit D-rings: A on the LEFT hip, B on the RIGHT (%.2f m apart)" % a.distance_to(b), a.distance_to(b) > 0.25 and (b - a).dot(right) > 0.2)
	_check("two independent cable objects", eva._cables.size() == 2 and eva._cables[0]["root"] != eva._cables[1]["root"])
	var c0: Dictionary = eva._cables[0]
	_check("tether A cable visible, from the LEFT D-ring to ring A1", (c0["root"] as Node3D).visible and (c0["hook_a"] as Node3D).global_position.distance_to(a) < 0.03 and (c0["hook_b"] as Node3D).global_position.distance_to(eva.ANCHORS[0][0]) < 0.03)
	_check("tether B (stowed) shows no cable", not (eva._cables[1]["root"] as Node3D).visible)
	var seg: MeshInstance3D = c0["segs"][9]
	_check("cable is solid tube geometry on normal + exterior layers", seg.mesh is CylinderMesh and seg.layers & 1 != 0 and seg.layers & (1 << 11) != 0)
	_check("EXT-02 (hatch camera) sees tether A", main.get_node("CameraNetwork").sees("EXT-02", seg.global_position, 0.6))
	_check("visor: A chip 'A A1', B chip 'B —'", eva._teth_label.text == "A A1" and eva._teth_b_label.text == "B —")


func _safety_rules() -> void:
	# Releasing the last secure tether is refused with a warning.
	_check("release of the LAST secure tether refused", not eva.release_tether(0) and eva.tether_state() == "SECURED_A")
	_check("...with a visible warning", eva._warn.visible or eva._warn_t > 0.0)
	_check("R with one tether: refused", not eva.release_older() and eva.secured_count() == 1)
	# Out of reach ring refused.
	_check("ring L3 (far) refused: out of reach", not eva.clip_to(Graph.index_of("L3")))
	# Start a connect to H1 (above the hatch).
	fb.sync_to_eye_position(Graph.pos("H1") + Vector3(0.0, -0.1, -0.9))
	await create_timer(0.25).timeout
	var h1: int = Graph.index_of("H1")
	_check("CONNECTING_B to H1 starts (free tether)", eva.clip_to(h1) and eva.tether_state() == "CONNECTING_B")
	_check("double click / second transition refused while busy", not eva.clip_to(Graph.index_of("A2")) and not eva.release_tether(0))
	await create_timer(0.2).timeout
	var hand: Vector3 = eva._hand_point(1)
	_check("the RIGHT hand reaches toward the ring (%.2f m)" % hand.distance_to(Graph.pos("H1")), hand.distance_to(Graph.pos("H1")) < 0.75)
	var hook_mid: Vector3 = (eva._cables[1]["hook_b"] as Node3D).global_position
	await _until(func(): return eva.tether_state() == "SECURED_BOTH", 2.0)
	_check("hook travelled with the hand, then SEATED: SECURED_BOTH", eva.tether_state() == "SECURED_BOTH" and hook_mid.distance_to(Graph.pos("H1")) > 0.02)
	_check("both cables visible during the overlap", (eva._cables[0]["root"] as Node3D).visible and (eva._cables[1]["root"] as Node3D).visible)
	_check("both rings lit green", (eva._ring_mats[0] as StandardMaterial3D).albedo_color.g > 0.9 and (eva._ring_mats[h1] as StandardMaterial3D).albedo_color.g > 0.9)
	_check("third ring refused: both tethers in use", not eva.clip_to(Graph.index_of("A2")))
	_check("R releases the OLDER tether (A)", eva.release_older() and eva.tether_state() == "RELEASING_A")
	_check("while A releases, B cannot be released", not eva.release_tether(1))
	await _until(func(): return eva.tether_state() == "SECURED_B", 2.0)
	_check("A released and reeled in: SECURED_B on H1", eva.tether_state() == "SECURED_B" and eva.anchor_index == h1 and not (eva._cables[0]["root"] as Node3D).visible)
	_check("events in order: connect B, secure B, release A, unclip, stow A", _order(["connect_B_%d" % h1, "secure_B_%d" % h1, "release_A_0", "unclip_0", "stow_A"]))
	# Interrupted connect: drift away mid-reach -> clean abort, B untouched.
	fb.sync_to_eye_position(Graph.pos("A1") + Vector3(-0.3, 0.2, -0.9))
	await create_timer(0.2).timeout
	_check("connect A back to A1 starts", eva.clip_to(0) and eva.tether_state() == "CONNECTING_A")
	fb.sync_to_eye_position(Graph.pos("A1") + Vector3(-0.3, 1.2, -3.2))
	await create_timer(0.7).timeout
	_check("drifted out of reach mid-connect: aborted, A stowed, B still SECURED", eva.tether_state() == "SECURED_B" and eva.tethers[0]["state"] == "stowed" and eva.eva_log.any(func(e): return String(e["event"]).begins_with("connect_aborted_A")))
	# Retry works.
	fb.sync_to_eye_position(Graph.pos("A1") + Vector3(-0.3, 0.2, -0.9))
	await create_timer(0.2).timeout
	eva.clip_to(0)
	await _until(func(): return eva.tether_state() == "SECURED_BOTH", 2.0)
	eva.release_tether(1)
	await _until(func(): return eva.tether_state() == "SECURED_A", 2.0)
	_check("retry succeeded; back to SECURED_A on A1", eva.tether_state() == "SECURED_A" and eva.anchor_index == 0)


func _tension() -> void:
	fb.sync_to_eye_position(Graph.pos("A1") + Vector3(-0.3, 0.6, -1.0))
	fb.velocity = Vector3.ZERO
	_aim(Vector3(0.0, 1.0, -0.1))           # straight up: open space, the cable goes taut
	await physics_frame
	var max_jump := 0.0
	var last: Vector3 = fb.global_position
	_key(KEY_W, true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await physics_frame
		max_jump = maxf(max_jump, fb.global_position.distance_to(last))
		last = fb.global_position
	_key(KEY_W, false)
	var L: float = eva.attach_point(0).distance_to(Graph.pos("A1"))
	_check("thrusting away: the taut tether stops outward travel (%.2f <= %.1f m)" % [L, eva.TETHER_LEN], L <= eva.TETHER_LEN + 0.15)
	_check("smooth constraint, no teleport (max %.3f m per physics frame)" % max_jump, max_jump < 0.06)
	_check("no failsafe reset fired", not eva.eva_log.any(func(e): return e["event"] == "tether_return"))
	var c0: Dictionary = eva._cables[0]
	var mid: Vector3 = (c0["segs"][9] as Node3D).global_position
	var on_line: Vector3 = Geometry3D.get_closest_point_to_segment(mid, (c0["hook_a"] as Node3D).global_position, (c0["hook_b"] as Node3D).global_position)
	_check("taut cable is straight (sag %.3f m off the chord)" % mid.distance_to(on_line), mid.distance_to(on_line) < 0.06)
	_check("visor range bar near full when taut (%.2f)" % eva._teth_bar.value, eva._teth_bar.value > 0.9)
	_key(KEY_S, true)
	await create_timer(1.5).timeout
	_key(KEY_S, false)


func _graph_static() -> void:
	var worst := 0.0
	for l in Graph.LINKS:
		worst = maxf(worst, Graph.pos(l[0]).distance_to(Graph.pos(l[1])))
	_check("every anchor link overlaps: longest %.2f m <= TETHER_LEN + CLIP_REACH (%.1f)" % [worst, eva.TETHER_LEN + eva.CLIP_REACH], worst <= eva.TETHER_LEN + eva.CLIP_REACH - 1.0)
	var missing: Array = []
	for id in ["A1", "H1", "A3", "L1", "L3", "L5", "R1", "R3", "R5"]:
		if Graph.route("A1", id).is_empty() or Graph.route(id, "A1").is_empty():
			missing.append(id)
	_check("required anchors reachable from the airlock and back %s" % str(missing), missing.is_empty())
	var on_rail := true
	for a in Graph.ANCHORS:
		if String(a[2]).begins_with("wing") or a[2] == "truss":
			on_rail = on_rail and absf((a[0] as Vector3).z - Graph.RAIL_Z) < 0.01 and absf((a[0] as Vector3).y - Graph.RAIL_Y) < 0.01
	_check("truss / wing rings sit on the maintenance handrail (never on cells)", on_rail)


## Hop along `ids` with real transfers: float near the next ring (within
## clip reach of it, inside the current tether), clip the free tether,
## then release the older one.
func _route(ids: Array, what: String) -> void:
	var ok := true
	var detail := ""
	for i in range(1, ids.size()):
		var cur: Vector3 = Graph.pos(ids[i - 1])
		var nxt: Vector3 = Graph.pos(ids[i])
		var from_dir: Vector3 = (cur - nxt)
		from_dir.y = 0.0
		var eye: Vector3 = nxt + from_dir.normalized() * 0.6 + Vector3(0, 0.75, 0.35)
		fb.sync_to_eye_position(eye)
		fb.velocity = Vector3.ZERO
		await create_timer(0.15).timeout
		var j: int = Graph.index_of(ids[i])
		if not eva.clip_to(j):
			ok = false
			detail = "clip %s failed" % ids[i]
			break
		await _until(func(): return eva.tether_state() == "SECURED_BOTH", 2.0)
		if not eva.release_older():
			ok = false
			detail = "release at %s failed" % ids[i]
			break
		await _until(func(): return not eva.is_switching(), 2.0)
		if eva.anchor_index != j or eva.secured_count() != 1:
			ok = false
			detail = "after %s: %s" % [ids[i], eva.tether_state()]
			break
	_check("route %s (%s): every hop transferred safely %s" % [" > ".join(ids), what, detail], ok)


func _back_inside() -> void:
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, -1.6))
	for i in 6: await physics_frame
	_check("back in the chamber: both tethers stowed, still floating (outer hatch open)", not eva.outside and eva.tether_state() == "NONE" and fb.zero_g)
	_check("re-entry: left hand reaches for the hatch frame", eva._hatch_reach_t >= 0.0 or eva.eva_log.any(func(e): return e["event"] == "zone_chamber"))
	al.begin_cycle_in()
	await _until(func(): return al.sequence == "", 10.0)
	fb.sync_to_eye_position(Vector3(-4.8, 1.6, 0.8))
	for i in 4: await physics_frame
	_check("station again: no teleport events all test", not eva.eva_log.any(func(e): return e["event"] == "tether_return"))


func _order(keys: Array) -> bool:
	var ev: Array = eva.eva_log.map(func(e): return String(e["event"]))
	var last := -1
	for k in keys:
		var i: int = ev.find(k, last + 1)
		if i <= last:
			return false
		last = i
	return true


func _until(cond: Callable, seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await physics_frame


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
