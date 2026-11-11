extends Node
## Round 46 Priorities 15-18: the PERIPHERAL FIGURE.
##
## After a FAST turn of the technician's head, a dark figure stands for a
## moment near the EDGE of the view -- a real 3D apparition (apparition.gd,
## DIRECT_ONLY: the eyes only, never a camera feed) at a real floor spot,
## so its size, perspective and occlusion come from the actual camera, FOV
## and distance. Looking back toward it (or ~half a second) and it is gone.
## No sound by default (silence is stronger), no collision, no shadow.
##
## Placement: authored floor spots (doorways, corridor edges, the far side
## of rooms) validated at runtime (floor under it, a body-sized clearance,
## clear line of sight to head AND hips), on the side the view turned AWAY
## from, between EDGE_MIN and EDGE_MAX of the half horizontal FOV.
## Gating: story phase >= 2, not day 1, free walking only (no laptop /
## workstation / focused view / EVA / modal UI), at most once a day, never
## the same room as the last two, and only some fast turns (deterministic).
## Reduced visual effects: never closer than REDUCED_MIN_D.

const FAST_DEG_S := 170.0          # a fast head turn
const FAST_MIN_SWEEP := 45.0       # degrees swept fast before it counts
const SETTLE_DEG_S := 70.0         # the turn has ended
const SHOW_MAX_S := 0.55
const LOOK_BACK_DEG := 20.0        # gaze within this of the figure: gone
const EDGE_MIN := 0.45
const EDGE_MAX := 0.92
const MIN_D := 1.8
const MAX_D := 13.0
const REDUCED_MIN_D := 4.0
const CHANCE := 0.4
## Floor spots (x, z) at doorways / corridor edges / far sides of rooms.
const SPOTS := [
	Vector2(-0.2, 3.0), Vector2(-0.2, 2.0), Vector2(-0.25, 5.6), Vector2(1.5, 4.5), Vector2(-2.1, 6.06),
	Vector2(-0.4, 8.3), Vector2(-0.35, 9.7), Vector2(-3.4, 5.2), Vector2(-4.3, 4.2), Vector2(-2.6, 10.4),
	Vector2(-1.6, 11.0), Vector2(3.3, 0.6), Vector2(4.3, 1.4), Vector2(-6.4, 8.1), Vector2(2.2, 7.0),
	Vector2(0.9, -1.4), Vector2(-0.6, -0.6), Vector2(2.6, -0.4),
]

var se: Node                       # story_events
var fig: Node3D
var valid: Array = []              # validated world spots (Vector3)
var shown_t: float = -1.0
var seen_day: int = -1
var rooms_recent: Array = []       # last rooms it appeared in
var plays: int = 0
var force_next: bool = false       # developer: the next fast turn triggers
var dev_preview: bool = false      # developer show: never counted
var _last_yaw: float = NAN
var _sweep: float = 0.0
var _turn_dir: float = 0.0
var _fast_end_t: float = -1.0
var _turns: int = 0
var last_spot: Vector3 = Vector3.INF
var last_side: float = 0.0
signal appeared(spot: Vector3)
signal vanished(reason: String)


func _ready() -> void:
	add_to_group(&"peripheral_watch")
	add_to_group(&"r35_equipment")      # SaveGame persists state_dict()/load_dict()
	fig = load("res://scripts/story/apparition.gd").new(1 << 19)
	fig.name = "PeripheralFigure"
	_main().add_child.call_deferred(fig)
	_validate.call_deferred()


func _main() -> Node:
	return se._root() if se != null and se.has_method("_root") else get_tree().current_scene


func _space() -> PhysicsDirectSpaceState3D:
	var n: Node3D = _main().get_node_or_null("FreeMoveBody") as Node3D
	return n.get_world_3d().direct_space_state if n != null else null


## Keeps only spots with a floor and a body-sized clearance (no walls).
func _validate() -> void:
	valid = []
	var sp: PhysicsDirectSpaceState3D = _space()
	if sp == null:
		return
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.6
	for s in SPOTS:
		var p := Vector3(s.x, 0.0, s.y)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -0.4, 0))
		q.collision_mask = 1
		var r: Dictionary = sp.intersect_ray(q)
		if r.is_empty() or absf(float(r["position"].y)) > 0.25:
			continue
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = cap
		sq.collision_mask = 1
		sq.transform = Transform3D(Basis(), Vector3(p.x, float(r["position"].y) + 0.95, p.z))
		if not sp.intersect_shape(sq, 1).is_empty():
			continue
		valid.append(Vector3(p.x, float(r["position"].y), p.z))


func _cam() -> Camera3D:
	return _main().get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") as Camera3D


## Free walking only: nothing else owns the view.
func can_happen() -> bool:
	if se == null or se._dp == null:
		return false
	var fb: Node = _main().get_node_or_null("FreeMoveBody")
	if fb == null or not bool(fb.get("active")) or Vector3(fb.get("guide_target")) != Vector3.INF:
		return false
	if se._ws_in_use() or se._eva_busy():
		return false
	var ss: Node = _main().get_node_or_null("SleepState")
	if ss != null and ss.has_method("is_up") and not ss.is_up():
		return false
	for o in get_tree().get_nodes_in_group(&"mouse_overlay"):
		if o.has_method("owns_mouse") and o.owns_mouse():
			return false
	return true


func eligible_today() -> bool:
	return force_next or (se.phase() >= 2 and se.day() > 1 and seen_day != se.day())


func _process(delta: float) -> void:
	var cam: Camera3D = _cam()
	if cam == null or delta <= 0.0:
		return
	var yaw: float = cam.global_rotation.y
	if is_nan(_last_yaw):
		_last_yaw = yaw
	var dyaw: float = rad_to_deg(wrapf(yaw - _last_yaw, -PI, PI))
	_last_yaw = yaw
	if shown_t >= 0.0:
		_track_shown(delta, cam)
		return
	feed_turn(dyaw / delta, absf(dyaw), delta)


## One frame of head-turn tracking (tests drive it with synthetic rates).
func feed_turn(rate_deg_s: float, swept_deg: float, delta: float) -> void:
	if absf(rate_deg_s) >= FAST_DEG_S:
		if signf(rate_deg_s) != _turn_dir:
			_sweep = 0.0
		_turn_dir = signf(rate_deg_s)
		_sweep += swept_deg
		_fast_end_t = -1.0
		return
	if _sweep >= FAST_MIN_SWEEP and absf(rate_deg_s) <= SETTLE_DEG_S:
		# The fast turn just ended: maybe something at the edge behind it.
		var sweep: float = _sweep
		_sweep = 0.0
		_turns += 1
		if can_happen() and eligible_today() and (force_next or _roll()):
			try_show(-_turn_dir, sweep)
		return
	if absf(rate_deg_s) < SETTLE_DEG_S:
		_sweep = maxf(_sweep - 90.0 * delta, 0.0)


func _roll() -> bool:
	return float(absi(hash("peri:%d:%d" % [se.day(), _turns])) % 1000) / 1000.0 < CHANCE


## Place the figure near the edge on `side` (+1 = screen right, -1 = left)
## in the current view. Returns true when shown.
func try_show(side: float, _sweep_deg: float = 0.0, min_d: float = -1.0, max_d: float = -1.0) -> bool:
	var cam: Camera3D = _cam()
	if cam == null:
		return false
	var spot: Vector3 = pick_spot(cam, side, min_d, max_d)
	if spot == Vector3.INF:
		return false
	force_next = false
	var face: Vector3 = cam.global_position
	fig.show_still(spot, Vector3(face.x, spot.y, face.z))
	shown_t = 0.0
	last_spot = spot
	last_side = side
	plays += 1
	seen_day = se.day() if se != null else 0
	var room: String = _room_of(spot)
	rooms_recent.push_front(room)
	rooms_recent = rooms_recent.slice(0, 2)
	appeared.emit(spot)
	return true


func _room_of(p: Vector3) -> String:
	var br: Node = _main().get_node_or_null("Equipment/BreakerPanel")
	return String(br.zone_at(p + Vector3(0, 1.0, 0))) if br != null and br.has_method("zone_at") else ""


## The best valid spot at the edge of the CURRENT view on `side`.
func pick_spot(cam: Camera3D, side: float, min_d: float = -1.0, max_d: float = -1.0) -> Vector3:
	var reduced: bool = bool(preload("res://scripts/station/game_settings.gd").get_value("reduce_effects"))
	var lo_d: float = maxf(MIN_D if min_d < 0.0 else min_d, REDUCED_MIN_D if reduced else 0.0)
	var hi_d: float = MAX_D if max_d < 0.0 else max_d
	var vp: Vector2 = Vector2(cam.get_viewport().get_visible_rect().size)
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	var half_h: float = atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect)
	var fwd: Vector3 = -cam.global_basis.z
	var right: Vector3 = cam.global_basis.x
	var best := Vector3.INF
	var best_score: float = INF
	for p in valid:
		var head: Vector3 = p + Vector3(0, 1.62, 0)
		var to: Vector3 = head - cam.global_position
		var d: float = Vector2(to.x, to.z).length()
		if d < lo_d or d > hi_d:
			continue
		var h_ang: float = atan2(to.dot(right), to.dot(fwd))
		if to.dot(fwd) <= 0.0 or signf(h_ang) != signf(side):
			continue
		var frac: float = absf(h_ang) / half_h
		if frac < EDGE_MIN or frac > EDGE_MAX:
			continue
		if cam.is_position_behind(p + Vector3(0, 0.1, 0)):
			continue
		var feet: Vector2 = cam.unproject_position(p + Vector3(0, 0.1, 0))
		var top: Vector2 = cam.unproject_position(head)
		if top.y < 0.0 or feet.y > vp.y * 1.15:
			continue
		if not line_clear(cam.global_position, head) or not line_clear(cam.global_position, p + Vector3(0, 1.0, 0)):
			continue
		if _room_of(p) in rooms_recent:
			continue
		var score: float = absf(frac - 0.75) + d * 0.01
		if score < best_score:
			best_score = score
			best = p
	if best == Vector3.INF:
		best = _sample_edge(cam, side, half_h, lo_d, hi_d, vp)
	return best


## Fallback: walk back along the EDGE-of-view ray (chest height) from the
## first obstacle toward the camera; the first point with a floor, a
## body-sized clearance and a clear line of sight to head + hips wins.
func _sample_edge(cam: Camera3D, side: float, half_h: float, lo_d: float, hi_d: float, vp: Vector2) -> Vector3:
	var sp: PhysicsDirectSpaceState3D = _space()
	if sp == null:
		return Vector3.INF
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.6
	var fwd: Vector3 = -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for frac in [0.75, 0.66, 0.84, 0.55]:
		var dir: Vector3 = fwd.rotated(Vector3.UP, -side * frac * half_h)
		var o: Vector3 = cam.global_position
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * hi_d)
		q.collision_mask = 1
		var r: Dictionary = sp.intersect_ray(q)
		var reach: float = (Vector3(r["position"]) - o).length() - 0.45 if not r.is_empty() else hi_d
		var d: float = minf(reach, hi_d)
		while d >= lo_d:
			var flat: Vector3 = o + dir * d
			var fq := PhysicsRayQueryParameters3D.create(Vector3(flat.x, o.y, flat.z), Vector3(flat.x, -0.4, flat.z))
			fq.collision_mask = 1
			var fr: Dictionary = sp.intersect_ray(fq)
			if not fr.is_empty() and absf(float(fr["position"].y)) < 0.25:
				var p := Vector3(flat.x, float(fr["position"].y), flat.z)
				var sq := PhysicsShapeQueryParameters3D.new()
				sq.shape = cap
				sq.collision_mask = 1
				sq.transform = Transform3D(Basis(), p + Vector3(0, 0.95, 0))
				var head: Vector3 = p + Vector3(0, 1.62, 0)
				if sp.intersect_shape(sq, 1).is_empty() and line_clear(o, head) and line_clear(o, p + Vector3(0, 1.0, 0)) \
						and not cam.is_position_behind(head) and cam.unproject_position(head).y >= 0.0 and not _room_of(p) in rooms_recent:
					return p
			d -= 0.5
	return Vector3.INF


func line_clear(a: Vector3, b: Vector3) -> bool:
	var sp: PhysicsDirectSpaceState3D = _space()
	if sp == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return sp.intersect_ray(q).is_empty()


func _track_shown(delta: float, cam: Camera3D) -> void:
	shown_t += delta
	var to: Vector3 = fig.head_point() - cam.global_position
	var gaze: float = rad_to_deg((-cam.global_basis.z).angle_to(to))
	if gaze <= LOOK_BACK_DEG:
		hide_figure("looked")
	elif shown_t >= SHOW_MAX_S:
		hide_figure("time")
	elif Vector2(to.x, to.z).length() < 1.2:
		hide_figure("close")


func hide_figure(reason: String) -> void:
	if shown_t < 0.0:
		return
	shown_t = -1.0
	fig.hide_now()
	vanished.emit(reason)


func is_shown() -> bool:
	return shown_t >= 0.0 and fig.is_shown()


func dev_reset() -> void:
	hide_figure("reset")
	seen_day = -1
	rooms_recent = []
	force_next = false
	_sweep = 0.0


func state_dict() -> Dictionary:
	return {"seen_day": seen_day, "rooms": rooms_recent.duplicate(), "plays": plays}


func load_dict(d: Dictionary) -> void:
	hide_figure("load")
	seen_day = int(d.get("seen_day", -1))
	rooms_recent = Array(d.get("rooms", [])).map(func(x): return String(x))
	plays = int(d.get("plays", 0))
