extends SceneTree
## Round 48 Priorities 7-12: the redesigned WINDOW FIGURE, measured from the
## real observation spot (the player's eye, normal FOV).
##  - a human body, not a mannequin cut-out: SHADED dark materials with a
##    figure-only rim light, a head deeper than it is wide (turning it
##    changes the silhouette), ordinary arm length, clavicle pivots so a
##    shoulder hitches without detaching, unlit face (no identity);
##  - staging: off-centre in the port, body turned three-quarters away, head
##    turned further away to begin with;
##  - A stillness -> B recognition (head turns far too fast, torso does not
##    follow) -> C impossible posture (chest twisted vs the hips, one shoulder
##    up one down, a sideways bend with the head held level) -> D four
##    deliberate snapped key poses (not vibration) -> E a slide whose speed
##    changes abruptly, head kept on the viewer -> F gone behind the far
##    frame (never in open view);
##  - reduced effects soften every snap; variants exist for developer
##    comparison only (default "B"); gating, reset and status unchanged.
var _ok := true
var main: Node
var se: Node
var dp: Node
var cam: Camera3D
var fb: Node
var player: Node3D
var lp: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	se = main.get_node("StoryEvents")
	dp = main.get_node("DayPlan")
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	main.get_node("StationAI").set_enabled(false)
	await _body()
	await _staging()
	_sequence()
	_reduced()
	_dev()
	_labels()
	print("")
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


func _vh() -> float:
	return float(cam.get_viewport().get_visible_rect().size.y)


## Horizontal facing (deg, world yaw) of a node's +X axis.
func _yaw_of(n: Node3D) -> float:
	var x: Vector3 = n.global_basis.x
	return rad_to_deg(atan2(-x.z, x.x))


func _body() -> void:
	var f: Node3D = se.window.figure
	var meshes: Array = f.find_children("*", "MeshInstance3D", true, false)
	_check("articulated body (%d parts): legs, arms with forearm + hand, clavicles" % meshes.size(), meshes.size() >= 20 and f._legs.size() == 2 and f._arms[-1].size() == 3 and f._clav.size() == 2)
	var shaded := true
	for m in meshes:
		var mat: Material = (m as GeometryInstance3D).material_override
		shaded = shaded and mat is StandardMaterial3D and (mat as StandardMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and (mat as StandardMaterial3D).albedo_color.v < 0.06
	_check("SHADED near-black materials (not a flat unshaded cut-out)", shaded)
	var albedos := {}
	for m in meshes:
		albedos[(((m as GeometryInstance3D).material_override as StandardMaterial3D).albedo_color.to_html())] = true
	_check("subtle material variation (%d dark tones)" % albedos.size(), albedos.size() >= 3)
	var rim: OmniLight3D = f.get_node("FigureRim")
	_check("a figure-only rim light (cull mask = eye-only layer, no shadow)", rim.light_cull_mask == f.DIRECT_ONLY and not rim.shadow_enabled)
	_check("eye-only, no collision, no shadows", meshes.all(func(m): return (m as GeometryInstance3D).layers == f.DIRECT_ONLY and (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) and f.find_children("*", "CollisionObject3D", true, false).is_empty())
	var skull: MeshInstance3D = null
	for m in f._head.get_children():
		if m is MeshInstance3D and (m as MeshInstance3D).mesh is SphereMesh and skull == null:
			skull = m
	_check("head deeper than wide (%.2f) -- turning it changes the silhouette" % skull.scale.x, skull.scale.x > skull.scale.z * 1.15)
	var face_unlit := false
	for m in f._head.get_children():
		if m is MeshInstance3D and not ((m as MeshInstance3D).material_override as StandardMaterial3D).rim_enabled:
			face_unlit = true
	_check("no facial identity: the face parts never catch the rim", face_unlit)
	f.appear()
	f.set_process(false)
	f.step_pose(0.0)
	var head_top: float = f.head_point().y
	var reach: float = (f.hand_point(1) - f._arms[1][0].global_position).length() + 0.12
	_check("human height (head %.2f m) and ordinary arm length (%.2f m, not cartoon-long)" % [head_top, reach], head_top > 1.65 and head_top < 1.9 and reach > 0.6 and reach < 0.82)
	var neck_r: float = 0.0
	for m in f._neck.get_children():
		if m is MeshInstance3D and (m as MeshInstance3D).mesh is CapsuleMesh:
			neck_r = ((m as MeshInstance3D).mesh as CapsuleMesh).radius
	_check("a neck of real thickness (r %.3f m, was a 0.036 stick)" % neck_r, neck_r >= 0.045)
	f.reset()


func _staging() -> void:
	var we: Node = se.window
	var f: Node3D = we.figure
	await _aim(we.OBS_SPOT, we.FIGURE_POS + Vector3(0, 1.45, 0))
	f.appear()
	f.set_process(false)
	f.step_pose(0.0)
	_check("observable from the real observation spot", we.observable())
	var eb: Script = load("res://scripts/exterior/exterior_builder.gd")
	var eye: Vector3 = cam.global_position
	var hp: Vector3 = f.head_point()
	var d: Vector3 = hp - eye
	var k: float = (eb.TUNNEL_PORT_CENTRE.x - eye.x) / d.x
	var at_port: Vector3 = eye + d * k
	var off: float = at_port.z - eb.TUNNEL_PORT_CENTRE.z
	_check("off-centre in the port (head %.2f m from the centre line, still inside)" % off, absf(off) > 0.1 and absf(off) < eb.TUNNEL_PORT_SIZE.x * 0.5 - 0.08)
	var to_eye: float = rad_to_deg(atan2(-(eye - f.global_position).z, (eye - f.global_position).x))
	var body_off: float = absf(wrapf(_yaw_of(f._hips) - to_eye, -180.0, 180.0))
	var head_off: float = absf(wrapf(_yaw_of(f._head) - to_eye, -180.0, 180.0))
	_check("body turned three-quarters away (%.0f deg), head turned further (%.0f deg)" % [body_off, head_off], body_off > 30.0 and head_off > body_off + 15.0)
	var torso_frac: float = absf(cam.unproject_position(f.head_point()).y - cam.unproject_position(f._hips.global_position).y) / _vh()
	_check("readable at the normal FOV (head-to-hips %.1f%% of the view)" % (torso_frac * 100.0), torso_frac > 0.06)
	# idle is not frozen: breathing / a weight shift, but tiny
	var c0: Vector3 = f._chest.scale
	f.step_pose(1.0)
	_check("ordinary stillness: breathing, nothing more", not f._chest.scale.is_equal_approx(c0) and absf(f._chest.scale.x - 1.0) < 0.02)


func _sequence() -> void:
	var we: Node = se.window
	var f: Node3D = we.figure
	f.watch_point = cam.global_position
	f.state = "react"
	f.t = 0.0
	var dt := 1.0 / 60.0
	var tt := 0.0
	var names: Array = []
	var rec := []    # [t, head yaw, chest yaw, head px, hips z, ...]
	while f.state == "react" and tt < 5.0:
		f.t = tt
		f.step_pose(tt)
		var nm: String = f.stage_name()
		if names.is_empty() or names.back() != nm:
			names.append(nm)
		rec.append({"t": tt, "head": _yaw_of(f._head), "chest": _yaw_of(f._chest), "hips": _yaw_of(f._hips),
			"px": cam.unproject_position(f.head_point()), "sh": [(f._chest.global_transform.affine_inverse() * f._arms[f.RAISED][0].global_position).y, (f._chest.global_transform.affine_inverse() * f._arms[f.DEAD][0].global_position).y],
			"roll_head": f._head.global_basis.y.angle_to(Vector3.UP), "roll_chest": f._chest.global_basis.y.angle_to(Vector3.UP)})
		tt += dt
	if f.state == "retreat" and names.back() != "retreat":
		names.append("retreat")
	_check("stages in order: %s" % str(names), names == ["noticed", "recognition", "posture", "shudder", "retreat"])
	# B: the head comes round far too fast; the torso does not follow.
	var i0: int = int(f.TURN_AT / dt) - 1
	var i1: int = int((f.TURN_AT + 0.15) / dt)
	var head_turn: float = absf(wrapf(rec[i1]["head"] - rec[i0]["head"], -180.0, 180.0))
	var chest_turn: float = absf(wrapf(rec[i1]["chest"] - rec[i0]["chest"], -180.0, 180.0))
	_check("recognition: the head turns %.0f deg in 0.15 s while the torso turns %.1f deg" % [head_turn, chest_turn], head_turn > 55.0 and chest_turn < 3.0)
	_check("...after a beat of total stillness (%.2f s)" % f.TURN_AT, f.TURN_AT >= 0.3 and rec[0]["px"].distance_to(rec[i0]["px"]) < 1.0)
	# C: impossible posture at the end of the posture stage.
	var ip: int = int((f.SHUDDER_AT - 0.05) / dt)
	var twist: float = absf(wrapf(rec[ip]["chest"] - rec[ip]["hips"], -180.0, 180.0))
	_check("posture: chest twisted %.0f deg against the hips" % twist, twist > 40.0)
	var hitch: float = float(rec[ip]["sh"][0]) - float(rec[ip]["sh"][1])
	var hitch0: float = float(rec[0]["sh"][0]) - float(rec[0]["sh"][1])
	_check("...one shoulder hitched up, the other dropped (chest frame: %.2f m -> %.2f m apart)" % [hitch0, hitch], hitch - hitch0 > 0.07)
	_check("...the body bends sideways (%.0f deg) while the head stays near level (%.0f deg)" % [rad_to_deg(rec[ip]["roll_chest"]), rad_to_deg(rec[ip]["roll_head"])], rec[ip]["roll_chest"] > deg_to_rad(15.0) and rec[ip]["roll_head"] < rec[ip]["roll_chest"] * 0.6)
	# D: four deliberate snapped key poses, each HELD (not vibration).
	var is0: int = int(f.SHUDDER_AT / dt)
	var events := 0
	var moving := false
	var holds_ok := true
	var still_run := 99
	for i in range(is0 + 1, rec.size()):
		var mv: bool = (rec[i]["px"] as Vector2).distance_to(rec[i - 1]["px"]) > 1.5
		if mv and not moving:
			events += 1
			holds_ok = holds_ok and still_run >= 4
			still_run = 0
		if not mv:
			still_run += 1
		moving = mv
	_check("shudder: %d deliberate snaps, each followed by a held beat" % events, events >= 3 and events <= 5 and holds_ok)
	# E/F: the retreat.
	var zs: Array = []
	var head_on := true
	var gone_in_view := false
	var r := 0.0
	var eb: Script = load("res://scripts/exterior/exterior_builder.gd")
	while f.state == "retreat" and r < 3.0:
		r += dt
		f.t = r
		f.step_pose(r)
		if f.state != "retreat":
			# the frame it vanished: was its head still inside the opening?
			gone_in_view = _inside_port(last_head, eb)
			break
		last_head = f.head_point()
		zs.append(f.position.z)
		if f.retreat_travel(r) > 0.05:
			var to: Vector3 = (cam.global_position - f.head_point()).normalized()
			var fwd: Vector3 = f._head.global_basis.x
			head_on = head_on and rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))) < 30.0
	var held: bool = absf(float(zs[3]) - float(zs[0])) < 0.001
	var v_slow: float = (float(zs[int(0.3 / dt)]) - float(zs[int(0.2 / dt)])) / 0.1
	var v_fast: float = (float(zs[zs.size() - 2]) - float(zs[zs.size() - 6])) / (4.0 * dt)
	_check("retreat: a held beat, a slow slide (%.1f m/s), then the speed jumps (%.1f m/s)" % [v_slow, v_fast], held and v_slow > 0.2 and v_fast > v_slow * 4.0 and v_fast > 4.0)
	var mono := true
	for i in range(1, zs.size()):
		mono = mono and float(zs[i]) >= float(zs[i - 1]) - 0.0001
	_check("...one way only, feet still (no walk cycle)", mono and f._legs[1][1].rotation.is_equal_approx(Vector3.ZERO))
	_check("...the head stays turned to the viewer as the body is carried off", head_on)
	_check("F: gone only once behind the far frame (never mid-glass)", not gone_in_view and not f.visible)


var last_head: Vector3 = Vector3.ZERO


func _inside_port(p: Vector3, eb: Script) -> bool:
	var eye: Vector3 = cam.global_position
	var d: Vector3 = p - eye
	var k: float = (eb.TUNNEL_PORT_CENTRE.x - eye.x) / d.x
	var hit: Vector3 = eye + d * k
	return absf(hit.z - eb.TUNNEL_PORT_CENTRE.z) < eb.TUNNEL_PORT_SIZE.x * 0.5 - 0.05


func _max_shudder_step(f: Node3D) -> float:
	var dt := 1.0 / 60.0
	var mx := 0.0
	var last := Vector2.ZERO
	for i in 60:
		f.state = "react"
		f.step_pose(f.SHUDDER_AT + i * dt)
		var p: Vector2 = cam.unproject_position(f.head_point())
		if i > 0:
			mx = maxf(mx, p.distance_to(last))
		last = p
	return mx


func _reduced() -> void:
	var f: Node3D = se.window.figure
	f.reset()
	f.appear()
	f.reduced = false
	var normal: float = _max_shudder_step(f)
	f.reduced = true
	var soft: float = _max_shudder_step(f)
	_check("reduced effects: snaps softened (max %.1f px/frame vs %.1f)" % [soft, normal], soft < normal * 0.5)
	f.reduced = false
	f.reset()


func _dev() -> void:
	var we: Node = se.window
	var f: Node3D = we.figure
	_check("variants exist for developer comparison; default B", f.VARIANTS == ["A", "B", "C"] and f.variant == "B" and f.DEFAULT_VARIANT == "B")
	for v in f.VARIANTS:
		f.variant = v
		f.appear()
		f.react()
		var tt := 0.0
		while f.state != "gone" and tt < 6.0:
			tt += 1.0 / 30.0
			f.t = tt if f.state == "react" else f.t + 1.0 / 30.0
			f.step_pose(f.t)
		_check("variant %s plays through to gone" % v, f.state == "gone" and not f.visible)
	f.variant = f.DEFAULT_VARIANT
	we.dev_replay_slow()
	_check("developer slow-motion replay (x%.2f)" % f.time_scale, is_equal_approx(f.time_scale, 0.25) and we.stage == "reacting" and f.state == "react")
	_check("developer status names the true stage", we.dev_status().find("noticed") != -1)
	we.dev_reset()
	_check("reset: hidden, rim light off, time scale normal", not f.visible and not f.get_node("FigureRim").visible and is_equal_approx(f.time_scale, 1.0) and we.stage == "locked")
	dp.day_number = 1
	_check("gating unchanged: never on day 1", not we.is_ready_now())


## Priority 32: no world label draws through walls (the "reversed text"
## seen through the Control Room's walls: no_depth_test + double-sided).
func _labels() -> void:
	var bad: Array = []
	for l in main.find_children("*", "Label3D", true, false):
		var path: String = str(l.get_path())
		if path.contains("/Player/") or path.contains("NavDebug") or path.contains("DevLabel"):
			continue                   # the player's own watch face / developer overlays
		if (l as Label3D).no_depth_test:
			bad.append(path.get_file())
	_check("no world label ignores depth (seen through walls): %s" % str(bad), bad.is_empty())


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
