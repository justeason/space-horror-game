extends Node
## Round 45 Priorities 7-12: the WINDOW ENCOUNTER -- Chapter One's climax.
##
## STAGES (never run where the player can't see them):
##   locked   -> READY when the story allows: phase 2 has begun AND at least
##               one anomaly was seen (or two quiet days of phase 2 passed),
##               not on day 1, not yet witnessed;
##   ready    -> CUED once the technician is in the Control Room: a soft hull
##               tick from the courtyard and one thought ("Wait a second…
##               what's that?"); the figure is still NOT shown;
##   cued     -> SHOWING only while it is genuinely OBSERVABLE: the eye is
##               inside the Control Room, the line eye -> figure passes
##               through the Control Room port's glass and nothing solid
##               blocks it out to the tunnel port (physics ray). Looking
##               away hides it again (still pending);
##   showing  -> REACTING after a short direct-gaze dwell (eye pointing at
##               the head within ~5 deg for 0.6 s): convulsion, unnatural
##               retreat out of the frame (window_figure.gd);
##   done     -> witnessed: observation evidence, journal memory, thoughts;
##               going to the tunnel port = a physical check; the ACCESS /
##               CAMERA records = the contradiction (nobody was logged).
## GUIDANCE if the player lingers in the Control Room without looking
## (cue given, 20 s): only when SAFE (free-walking, no laptop / focused view
## / workstation / EVA / emergency), at most once per station day: the body
## walks a few real steps to the observation spot (normal movement physics,
## cancelled instantly by any WASD), then the view eases toward the far port
## (1.6 s). With "Reduce visual effects" on, there is no camera control:
## only the thought and a soft directional marker. After two ignored days
## TODAY lists "Check the observation port" -- an ordinary duty that brings
## the player there. Nothing is lost by cancelling.

## Round 46: ON the line of sight from the observation spot through the
## tunnel port (0.6 m behind the glass), turned to face the Control Room --
## it used to stand square behind the port, i.e. at the frame's edge for an
## oblique viewer, mostly hidden.
const FIGURE_POS := Vector3(-4.72, 0.0, 2.65)
const FIGURE_YAW_DEG := 19.6
## Gentle FOCUS while staring at the far port (squinting): the field of
## view narrows so the figure's movement reads. Never with reduced effects.
const FOCUS_FOV_K := 0.42
const FOCUS_S := 0.7
const PORT_CENTRE := Vector3(-1.2, 1.5, 1.4)       # Control Room port (glass plane x -1.2)
const PORT_R := 0.30
## Round 46: from here the sight line to the tunnel port passes through the
## CENTRE of the Control Room port (it grazed the rim from z 1.45).
const OBS_SPOT := Vector3(-0.45, 1.6, 1.13)
const CONTROL_RECT := Rect2(-1.15, -1.1, 2.3, 3.1)   # x, z of the Control Room interior
const GAZE_DOT := 0.996
const GAZE_S := 0.6
const GUIDE_AFTER_S := 20.0
const TUNNEL_CHECK := Vector3(-4.8, 1.6, 2.5)

var stage: String = "locked"
var witnessed_day: int = -1
var guide_days: Array = []
var cue_day: int = -1
var port_duty: bool = false
var figure: Node3D
var _gaze: float = 0.0
var _in_room_s: float = 0.0
var _away: float = 0.0
var _guiding: bool = false
var _guide_tw: Tween
var _marker: Label
var _se: Node


func _ready() -> void:
	add_to_group(&"window_encounter")
	add_to_group(&"r35_equipment")
	_se = get_parent()
	_spawn_figure.call_deferred()


func _main() -> Node:
	return _se.get_parent()


func _spawn_figure() -> void:
	figure = load("res://scripts/story/window_figure.gd").new()
	figure.name = "WindowFigure"
	figure.position = FIGURE_POS
	figure.rotation_degrees.y = FIGURE_YAW_DEG
	_main().add_child(figure)
	figure.finished.connect(_on_figure_gone)


func _dp() -> Node:
	return _se.get("_dp")


func _cam() -> Camera3D:
	return _main().get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") as Camera3D


func _day() -> int:
	return int(_dp().day_number) if _dp() != null else 1


func is_ready_now() -> bool:
	if stage != "locked" or witnessed_day >= 0 or _day() <= 1:
		return false
	if int(_se.story_phase) < 2 and int(_se.dev_phase_override) < 2:
		return false
	# Round 46 pacing: the major moment never shares a day with a medium one.
	if _se.has_method("medium_played_on") and _se.medium_played_on(_day()):
		return false
	var p2: int = int(_se.get("phase2_day"))
	var noticed: bool = int(_se.seen_count()) >= 1 or Array(_se.evidence).any(func(e): return String(e["kind"]) == "observation" and String(e["event"]) != "window_figure")
	return noticed or (p2 > 0 and _day() >= p2 + 2)


func in_control_room() -> bool:
	var c: Camera3D = _cam()
	return c != null and CONTROL_RECT.has_point(Vector2(c.global_position.x, c.global_position.z)) and c.global_position.y < 2.6


## Is the figure (its head) genuinely visible from the eye right now?
func observable() -> bool:
	var c: Camera3D = _cam()
	if c == null or figure == null or not in_control_room():
		return false
	var eye: Vector3 = c.global_position
	var target: Vector3 = FIGURE_POS + Vector3(0, 1.62, 0)
	var dir: Vector3 = target - eye
	if absf(dir.x) < 0.01:
		return false
	var k: float = (PORT_CENTRE.x - eye.x) / dir.x
	if k <= 0.0 or k >= 1.0:
		return false
	var hit: Vector3 = eye + dir * k
	if Vector2(hit.y - PORT_CENTRE.y, hit.z - PORT_CENTRE.z).length() > PORT_R:
		return false
	# Outside: nothing solid between the hull and the tunnel port.
	var space: PhysicsDirectSpaceState3D = c.get_world_3d().direct_space_state
	var from: Vector3 = eye + dir * (k + 0.3 / dir.length())
	var q := PhysicsRayQueryParameters3D.create(from, target)
	q.collision_mask = 1
	var glass: Node = _main().find_child("TunnelPortGlass", true, false)
	if glass is CollisionObject3D:
		q.exclude = [(glass as CollisionObject3D).get_rid()]
	return space.intersect_ray(q).is_empty()


func looking_at_figure() -> bool:
	var c: Camera3D = _cam()
	if c == null or figure == null:
		return false
	var to: Vector3 = (figure.head_point() - c.global_position).normalized()
	return (-c.global_basis.z).dot(to) >= GAZE_DOT


func _safe_for_guidance() -> bool:
	var m: Node = _main()
	var ss: Node = m.get_node_or_null("SleepState")
	var ws: Node = m.get_node_or_null("WorkstationState")
	var fb: Node = m.get_node_or_null("FreeMoveBody")
	var eva: Node = m.get_tree().get_first_node_in_group(&"eva_system")
	var fis: Node = m.find_child("FocusedInteractionState", true, false)
	if ss != null and (ss.is_sitting() or ss.is_lying_in_bed() or ss.is_laptop_open()):
		return false
	if ws != null and ws.is_in_use():
		return false
	if fis != null and fis.has_method("is_active") and fis.is_active():
		return false
	if eva != null and (bool(eva.get("suited")) or eva.is_eva_active()):
		return false
	if _se.has_method("_emergency") and _se._emergency():
		return false
	return fb != null and bool(fb.get("active"))


func _thought(id: String, en: String, zh: String) -> void:
	var iv: Node = _se.get("inner")
	if iv != null:
		iv.think(id, en, zh)


# ---------------------------------------------------------------- loop
var focus_k: float = 1.0          # 1 = normal view; FOCUS_FOV_K = focused
var _base_fov: float = -1.0


## Round 46: while the technician stares at the far port during the
## encounter, the view narrows a little (eased, never snapping); released
## as soon as they look away or it is over. Reduced effects: never.
func _update_focus(delta: float) -> void:
	var c: Camera3D = _cam()
	if c == null:
		return
	var want: float = 1.0
	if stage in ["showing", "reacting"] and figure.visible and not bool(preload("res://scripts/station/game_settings.gd").get_value("reduce_effects")):
		var to: Vector3 = (FIGURE_POS + Vector3(0, 1.5, 0) - c.global_position).normalized()
		if (-c.global_basis.z).dot(to) > 0.985:
			want = FOCUS_FOV_K
	if want < 1.0 and _base_fov < 0.0:
		_base_fov = c.fov
	if _base_fov < 0.0:
		return
	focus_k = move_toward(focus_k, want, delta * (1.0 - FOCUS_FOV_K) / FOCUS_S)
	c.fov = _base_fov * focus_k
	if focus_k >= 1.0 and want >= 1.0:
		c.fov = _base_fov
		_base_fov = -1.0


func _process(delta: float) -> void:
	if figure == null:
		return
	_update_focus(delta)
	if stage == "locked" and is_ready_now():
		stage = "ready"
	match stage:
		"ready":
			if in_control_room():
				_in_room_s += delta
				if _in_room_s > 2.5:
					_cue()
			else:
				_in_room_s = 0.0
		"cued":
			if observable():
				_away = 0.0
				if not figure.visible:
					figure.appear()
					_stop_guidance()
				stage = "showing"
			elif in_control_room():
				_in_room_s += delta
				if _in_room_s > GUIDE_AFTER_S and not _guiding and not guide_days.has(_day()) and _safe_for_guidance():
					start_guidance()
			else:
				_in_room_s = 0.0
		"showing":
			if not observable():
				_away += delta
				if _away > 1.5:
					figure.reset()
					stage = "cued"
				_gaze = 0.0
			else:
				_away = 0.0
				if looking_at_figure():
					_gaze += delta
					if _gaze >= GAZE_S:
						figure.react()
						stage = "reacting"
				else:
					_gaze = maxf(_gaze - delta, 0.0)
		"done":
			if _se.get("_pending_investigation") != null and _se._pending_investigation.has("window_figure"):
				var c: Camera3D = _cam()
				if c != null and c.global_position.distance_to(TUNNEL_CHECK) < 1.3:
					_se._pending_investigation.erase("window_figure")
					_se._investigated("window_figure")
					_thought("window_checked", "Was someone standing there?", "刚才有人站在那里吗？")


func _cue() -> void:
	stage = "cued"
	_in_room_s = 0.0
	if cue_day != _day():
		cue_day = _day()
		var snd: Node = _main().get_tree().get_first_node_in_group(&"station_sounds")
		if snd != null:
			snd.play_at(&"creak", Vector3(-3.2, 1.6, 2.2), false)
		_thought("window_cue_%d" % _day(), "Wait a second… what's that?", "等一下……那是什么？")


func _on_figure_gone() -> void:
	if stage != "reacting":
		return
	stage = "done"
	witnessed_day = _day()
	port_duty = false
	var st: Dictionary = _se.state[&"window_figure"]
	st["seen"] = true
	st["plays"] = int(st["plays"]) + 1
	st["last_day"] = _day()
	_se.observe("window_figure", "A figure behind the airlock-tunnel port; it convulsed and was gone.")
	_se._pending_investigation["window_figure"] = 99999.0
	_se.history.append({"id": "window_figure", "day": _day(), "event": "witnessed"})
	_thought("window_after", "That movement wasn't normal.", "那动作不正常。")
	_se._check_milestones()


# ------------------------------------------------------------ guidance
func start_guidance(force: bool = false) -> bool:
	if _guiding or not _safe_for_guidance() or (guide_days.has(_day()) and not force):
		return false
	guide_days.append(_day())
	_guiding = true
	if guide_days.size() >= 2:
		port_duty = true
	var reduce: bool = bool(preload("res://scripts/station/game_settings.gd").get_value("reduce_effects"))
	_thought("window_cue_%d" % _day(), "Wait a second… what's that?", "等一下……那是什么？")
	if reduce:
		_show_marker()
		_guiding = false
		return true
	var fb: Node = _main().get_node("FreeMoveBody")
	if "guide_target" in fb:
		fb.guide_cancelled = false
		# Round 46: a real route around the desk / console (never a straight
		# line that slides along furniture).
		var route: Array = route_to(fb.current_eye_position(), OBS_SPOT)
		if route.is_empty():
			_show_marker()                   # no safe walk: guidance by marker only
			_guiding = false
			return true
		fb.guide_target = route[0]
		fb.guide_path = route.slice(1)
	_ease_view.call_deferred()
	return true


# ------------------------------------------- Round 46: Control Room navigation
## A* over a 0.25 m grid of the Control Room floor: a node exists where the
## technician's capsule (r 0.3, 1.8 m) fits; an edge exists where a capsule
## SWEEP between the two nodes is clear. The path is then pulled tight (any
## waypoint whose neighbours see each other is dropped). Eye-height points.
const NAV_STEP := 0.25
const NAV_R := 0.3


func _capsule_free(sp: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, exclude: Array, leaving: bool = false) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = NAV_R
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	q.exclude = exclude
	q.transform = Transform3D(Basis(), Vector3(a.x, 0.95, a.z))
	if not sp.intersect_shape(q, 1).is_empty():
		if not leaving:
			return false
		# The technician may be touching furniture where they stand: a
		# leg that LEAVES must end clear and move away (judged at the far end).
		q.transform = Transform3D(Basis(), Vector3(b.x, 0.95, b.z))
		return sp.intersect_shape(q, 1).is_empty()
	if a.distance_to(b) < 0.001:
		return true
	q.motion = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var r: PackedFloat32Array = sp.cast_motion(q)
	return r.size() == 2 and r[0] >= 0.999


func route_to(from_eye: Vector3, to_eye: Vector3) -> Array:
	var c: Camera3D = _cam()
	if c == null:
		return []
	var sp: PhysicsDirectSpaceState3D = c.get_world_3d().direct_space_state
	var fb: CollisionObject3D = _main().get_node_or_null("FreeMoveBody") as CollisionObject3D
	var ex: Array = [fb.get_rid()] if fb != null else []
	var y: float = to_eye.y
	var a := Vector3(from_eye.x, y, from_eye.z)
	var b := Vector3(to_eye.x, y, to_eye.z)
	if _capsule_free(sp, a, b, ex, true):
		return [b]
	# Grid nodes inside the room.
	var nodes: Array = []
	var x := CONTROL_RECT.position.x + NAV_STEP * 0.5
	while x < CONTROL_RECT.end.x:
		var z := CONTROL_RECT.position.y + NAV_STEP * 0.5
		while z < CONTROL_RECT.end.y:
			var p := Vector3(x, y, z)
			if _capsule_free(sp, p, p, ex):
				nodes.append(p)
			z += NAV_STEP
		x += NAV_STEP
	nodes.append(a)
	nodes.append(b)
	var start: int = nodes.size() - 2
	var goal: int = nodes.size() - 1
	# A*.
	var open: Array = [start]
	var g: Dictionary = {start: 0.0}
	var came: Dictionary = {}
	while not open.is_empty():
		var cur: int = open[0]
		var best_f: float = INF
		for n in open:
			var f: float = float(g[n]) + (nodes[n] as Vector3).distance_to(b)
			if f < best_f:
				best_f = f
				cur = n
		if cur == goal:
			break
		open.erase(cur)
		for j in nodes.size():
			if j == cur:
				continue
			var d: float = (nodes[j] as Vector3).distance_to(nodes[cur])
			if d > NAV_STEP * 1.5 and not (j == goal and d < 0.6) and not (cur == start and d < 0.6):
				continue
			var ng: float = float(g[cur]) + d
			if ng < float(g.get(j, INF)) and _capsule_free(sp, nodes[cur], nodes[j], ex, cur == start):
				g[j] = ng
				came[j] = cur
				if not open.has(j):
					open.append(j)
	if not came.has(goal):
		return []
	var path: Array = [nodes[goal]]
	var k: int = goal
	while came.has(k):
		k = came[k]
		path.push_front(nodes[k])
	# String-pull: keep only turning points.
	var tight: Array = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var far: int = i + 1
		for j in range(path.size() - 1, i, -1):
			if _capsule_free(sp, path[i], path[j], ex, i == 0):
				far = j
				break
		tight.append(path[far])
		i = far
	tight.pop_front()                   # the start point itself
	return tight


func dev_guide() -> void:
	start_guidance(true)


func _ease_view() -> void:
	# Turn first (smooth 1.6 s ease toward the far port), walking in
	# parallel -- the technician never walks backwards into position.
	var fb: Node = _main().get_node("FreeMoveBody")
	var player: Node3D = _main().get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var pp: Node3D = lp.get_node("PitchPivot")
	var target: Vector3 = FIGURE_POS + Vector3(0, 1.62, 0)
	var d: Vector3 = target - OBS_SPOT
	var yaw: float = atan2(-d.x, -d.z) - player.rotation.y
	yaw = lp.rotation.y + wrapf(yaw - lp.rotation.y, -PI, PI)
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	_guide_tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_guide_tw.tween_property(lp, "rotation:y", yaw, 1.6)
	_guide_tw.tween_property(lp, "_target_yaw", yaw, 1.6)
	_guide_tw.tween_property(pp, "rotation:x", pitch, 1.6)
	_guide_tw.tween_property(lp, "_target_pitch", pitch, 1.6)
	for i in 240:
		if not _guiding:
			return
		if "guide_cancelled" in fb and fb.guide_cancelled:
			if _guide_tw != null and _guide_tw.is_valid():
				_guide_tw.kill()       # the player took over: release the view
			_guiding = false
			return
		if (not "guide_target" in fb or fb.guide_target == Vector3.INF) and not (_guide_tw != null and _guide_tw.is_running()):
			break
		await get_tree().process_frame
	_guiding = false


func _stop_guidance() -> void:
	_guiding = false
	var fb: Node = _main().get_node_or_null("FreeMoveBody")
	if fb != null and "guide_target" in fb:
		fb.guide_target = Vector3.INF
		fb.guide_path = []
	if _guide_tw != null and _guide_tw.is_valid():
		_guide_tw.kill()
	if _marker != null:
		_marker.visible = false


func is_guiding() -> bool:
	return _guiding


func _show_marker() -> void:
	if _marker == null:
		var hud: Node = _main().get_node_or_null("Player/HUD")
		if hud == null:
			return
		_marker = Label.new()
		_marker.text = "◂  window"
		_marker.add_theme_font_size_override("font_size", 18)
		_marker.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78, 0.8))
		_marker.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		_marker.position = Vector2(24, 0)
		hud.add_child(_marker)
	_marker.visible = true
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(func(): _marker.visible = false)


## TODAY duty after two ignored days (read by the laptop's Today view).
func today_items() -> Array:
	if port_duty and stage in ["ready", "cued", "showing"]:
		return [{"id": "port", "label": "Check the observation port", "done": false}]
	return []


# -------------------------------------------------------- developer API
func dev_prepare() -> void:
	witnessed_day = -1
	stage = "ready"
	_in_room_s = 0.0


func dev_cue() -> void:
	dev_prepare()
	_cue()


func dev_goto() -> void:
	var fb: Node = _main().get_node("FreeMoveBody")
	fb.sync_to_eye_position(OBS_SPOT)
	var player: Node3D = _main().get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var c: Camera3D = _cam()
	var d: Vector3 = (FIGURE_POS + Vector3(0, 1.62, 0)) - OBS_SPOT
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	lp.get_node("PitchPivot").rotation.x = pitch
	lp._target_pitch = pitch


func dev_spawn() -> void:
	stage = "showing"
	figure.appear()


func dev_react() -> void:
	if figure.state != "idle":
		figure.appear()
	stage = "reacting"
	figure.react()


func dev_reset() -> void:
	_stop_guidance()
	figure.reset()
	stage = "locked"
	witnessed_day = -1
	guide_days = []
	cue_day = -1
	port_duty = false
	_se._pending_investigation.erase("window_figure")


func state_dict() -> Dictionary:
	return {"stage": "done" if stage == "done" else ("ready" if stage in ["ready", "cued", "showing", "reacting"] else "locked"), "witnessed_day": witnessed_day, "guide_days": guide_days.duplicate(), "port_duty": port_duty}


func load_dict(d: Dictionary) -> void:
	_stop_guidance()
	if figure != null:
		figure.reset()
	stage = String(d.get("stage", "locked"))
	if not stage in ["locked", "ready", "done"]:
		stage = "locked"
	witnessed_day = int(d.get("witnessed_day", -1))
	guide_days = Array(d.get("guide_days", [])).map(func(x): return int(x))
	port_duty = bool(d.get("port_duty", false))
	cue_day = -1
	_in_room_s = 0.0
