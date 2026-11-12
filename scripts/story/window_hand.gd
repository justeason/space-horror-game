extends Node3D
## Round 47: the HAND AT THE GLASS -- a separate event at the Control Room
## observation port (story id "window_hand", see story_events.gd).
##
## A real articulated 3D hand (palm, four two-segment fingers a little too
## long, a thumb, a forearm stub leaving the frame below) pressed against
## the EXTERIOR face of the port's outer pane. DIRECT_ONLY: the eyes see
## it, no camera feed does. No collision, no shadow, created when the event
## starts and freed when it ends (no permanent hidden actor).
##
## Sequence (deterministic; story_events drives it with tick()):
##   knock     three taps (0.00 / 0.62 / 0.86 s: one, a pause, two) -- the index finger
##             lifts and taps the glass on each one. In vacuum there is no
##             airborne knock: the sound is STRUCTURE-BORNE ("glass_knock",
##             a dull thud through the frame) from the port itself, through
##             station_sounds' acoustic path;
##   wait      the hand stays pressed to the glass (up to WAIT_S);
##   seen      the technician looks at the port: for SEEN_HOLD_S the
##             fingers draw in one after another, knuckles lifting off the
##             glass, the ring finger bending the wrong way, the wrist
##             turning;
##   withdraw  WITHDRAW_S: down and away from the hull, accelerating --
##             it leaves behind the port's own rim / hull plate (real
##             occlusion), never a fade in the middle of the glass;
##   gone      hidden. If nobody looked within WAIT_S it withdraws unseen
##             (the taps were only heard).

signal finished(seen: bool)
const DIRECT_ONLY := 1 << 19
## The palm's contact point on the outer pane (lower-left of the port as
## seen from inside); the outer glass face is at x ~ -1.547.
const CONTACT := Vector3(-1.562, 1.36, 1.53)
const PORT_CENTRE := Vector3(-1.2, 1.5, 1.4)
const PORT_R := 0.3
const OUTER_X := -1.52
const OUTER_R := 0.33
## Round 48: knock ... (pause) ... knock-knock. The sound source is the
## pane's CABIN face: the knock is on the glass itself, which radiates into
## the Control Room -- Round 47 placed it outside the pane, so the pane
## counted as a wall (-7 dB + low-pass) on top of having no stream at all.
const KNOCK_TIMES := [0.0, 0.62, 0.86]
const KNOCK_POS := Vector3(-1.16, 1.4, 1.5)
const WAIT_S := 9.0
const SEEN_HOLD_S := 0.55
const WITHDRAW_S := 0.3
const WITHDRAW_MOVE := Vector3(-0.28, -0.52, 0.06)

var state: String = "idle"
var t: float = 0.0
var seen: bool = false
var knocks_played: int = 0
var _seen_t: float = 0.0
var _wrist: Node3D
var _fingers: Array = []          # [[knuckle, mid], ...] index..little
var _thumb: Node3D
var _mat: StandardMaterial3D


func _ready() -> void:
	name = "WindowHand"
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.6, 0.55, 0.51)        # bloodless skin -- and no glove, in vacuum
	_mat.roughness = 0.85
	global_position = CONTACT
	_wrist = Node3D.new()
	_wrist.position = Vector3(0, -0.06, 0)
	add_child(_wrist)
	_part(_wrist, BoxMesh, Vector3(0, 0.055, 0), Vector3(0.022, 0.1, 0.086))                 # palm
	_part(_wrist, CapsuleMesh, Vector3(-0.07, -0.14, -0.015), Vector3(0.029, 0.34, 0), Vector3(0, 0, -24))   # forearm, leaving below
	var lens := [[0.052, 0.046], [0.058, 0.05], [0.055, 0.047], [0.044, 0.038]]
	for i in 4:
		var z: float = -0.03 + i * 0.02
		var kn := Node3D.new()
		kn.position = Vector3(0, 0.104, z)
		_wrist.add_child(kn)
		_part(kn, CapsuleMesh, Vector3(0, lens[i][0] * 0.5, 0), Vector3(0.0088, lens[i][0], 0))
		var md := Node3D.new()
		md.position = Vector3(0, lens[i][0], 0)
		kn.add_child(md)
		_part(md, CapsuleMesh, Vector3(0, lens[i][1] * 0.5, 0), Vector3(0.0082, lens[i][1], 0))
		_fingers.append([kn, md])
	_thumb = Node3D.new()
	_thumb.position = Vector3(0, 0.03, -0.046)
	_thumb.rotation_degrees.x = -42.0
	_wrist.add_child(_thumb)
	_part(_thumb, CapsuleMesh, Vector3(0, 0.03, 0), Vector3(0.0095, 0.06, 0))
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = DIRECT_ONLY
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pose(0.0)


func _part(parent: Node3D, mesh_type, pos: Vector3, dims: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m: Mesh = mesh_type.new()
	if m is CapsuleMesh:
		(m as CapsuleMesh).radius = dims.x
		(m as CapsuleMesh).height = maxf(dims.y, dims.x * 2.0)
	elif m is BoxMesh:
		(m as BoxMesh).size = dims
	mi.mesh = m
	mi.material_override = _mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)


func begin() -> void:
	state = "knock"
	t = 0.0
	seen = false
	knocks_played = 0
	visible = true
	global_position = CONTACT
	_pose(0.0)


## The point the technician has to see (the palm).
func focus_point() -> Vector3:
	return _wrist.global_position + Vector3(0, 0.06, 0)


## True when `eye` has a clear sight line through the port's opening to
## the hand (both the cabin face and the outer face of the bore).
static func sight_through_port(eye: Vector3, target: Vector3) -> bool:
	var dir: Vector3 = target - eye
	if absf(dir.x) < 0.01 or eye.x < PORT_CENTRE.x:
		return false
	for plane in [[PORT_CENTRE.x, PORT_R], [OUTER_X, OUTER_R]]:
		var k: float = (float(plane[0]) - eye.x) / dir.x
		if k <= 0.0 or k >= 1.0:
			return false
		var hit: Vector3 = eye + dir * k
		if Vector2(hit.y - PORT_CENTRE.y, hit.z - PORT_CENTRE.z).length() > float(plane[1]):
			return false
	return true


## Is the technician looking at it right now (through the port, near the
## centre of the view, within a few metres)?
func is_seen_by(cam: Camera3D) -> bool:
	if cam == null or not visible:
		return false
	var p: Vector3 = focus_point()
	var eye: Vector3 = cam.global_position
	if eye.distance_to(p) > 5.0 or not sight_through_port(eye, p):
		return false
	return (-cam.global_basis.z).dot((p - eye).normalized()) > 0.95


## One step. `looking`: the technician is looking at it this frame.
func tick(delta: float, looking: bool) -> void:
	if state in ["idle", "gone"]:
		return
	t += delta
	match state:
		"knock", "wait":
			while knocks_played < KNOCK_TIMES.size() and t >= float(KNOCK_TIMES[knocks_played]):
				_knock()
			if state == "knock" and knocks_played >= KNOCK_TIMES.size() and t > 1.0:
				state = "wait"
			if looking:
				seen = true
				state = "seen"
				_seen_t = 0.0
			elif t >= WAIT_S:
				state = "withdraw"
				_seen_t = 0.0
		"seen":
			# Round 48: the knock sequence always completes (looking during
			# it never cuts the last knocks); the hold starts after it.
			while knocks_played < KNOCK_TIMES.size() and t >= float(KNOCK_TIMES[knocks_played]):
				_knock()
			if knocks_played >= KNOCK_TIMES.size():
				_seen_t += delta
			if _seen_t >= SEEN_HOLD_S:
				state = "withdraw"
				_seen_t = 0.0
		"withdraw":
			_seen_t += delta
			if _seen_t >= WITHDRAW_S:
				state = "gone"
				visible = false
				finished.emit(seen)
	_pose(t)


func _knock() -> void:
	knocks_played += 1
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds") if is_inside_tree() else null
	if snd != null:
		snd.play_at(&"glass_knock", KNOCK_POS, false)


func _pose(tt: float) -> void:
	if _wrist == null:
		return
	global_position = CONTACT
	_wrist.rotation = Vector3.ZERO
	# Splayed, pressed flat to the glass.
	var spread := [-11.0, -3.5, 3.5, 12.0]
	for i in 4:
		(_fingers[i][0] as Node3D).rotation = Vector3(deg_to_rad(spread[i]), 0, 0)
		(_fingers[i][1] as Node3D).rotation = Vector3.ZERO
	_thumb.rotation_degrees = Vector3(-42.0, 0, 0)
	match state:
		"knock", "wait":
			# The index finger lifts off the glass and taps on each knock.
			var lift := 0.0
			for kt in KNOCK_TIMES:
				var u: float = tt - float(kt)
				if u > -0.14 and u < 0.06:
					lift = maxf(lift, 1.0 - absf(u + 0.04) / 0.1)
			(_fingers[0][0] as Node3D).rotation.z = deg_to_rad(-38.0) * clampf(lift, 0.0, 1.0)
			if state == "wait":
				# Almost nothing: the little finger creeps a few degrees.
				(_fingers[3][0] as Node3D).rotation.x = deg_to_rad(12.0 + 4.0 * smoothstep(1.0, WAIT_S, tt))
		"seen":
			if knocks_played < KNOCK_TIMES.size():
				var lift2 := 0.0
				for kt in KNOCK_TIMES:
					var u2: float = tt - float(kt)
					if u2 > -0.14 and u2 < 0.06:
						lift2 = maxf(lift2, 1.0 - absf(u2 + 0.04) / 0.1)
				(_fingers[0][0] as Node3D).rotation.z = deg_to_rad(-38.0) * clampf(lift2, 0.0, 1.0)
			else:
				_pose_drawn(clampf(_seen_t / SEEN_HOLD_S, 0.0, 1.0))
		"withdraw":
			_pose_drawn(1.0)
			var w: float = clampf(_seen_t / WITHDRAW_S, 0.0, 1.0)
			global_position = CONTACT + WITHDRAW_MOVE * (w * w)
			_wrist.rotation.z += deg_to_rad(-35.0) * w


## The fingers draw in one after another (knuckles lift away from the
## glass, tips drag down it); the ring finger bends the WRONG way; the
## wrist turns.
func _pose_drawn(u: float) -> void:
	for i in 4:
		var k: float = smoothstep(0.12 * i, 0.12 * i + 0.45, u)
		if i == 2:
			(_fingers[i][0] as Node3D).rotation.z = deg_to_rad(28.0) * k      # hyper-extends
			(_fingers[i][1] as Node3D).rotation.z = deg_to_rad(-20.0) * k
		else:
			(_fingers[i][0] as Node3D).rotation.z = deg_to_rad(-55.0) * k
			(_fingers[i][1] as Node3D).rotation.z = deg_to_rad(70.0) * k
	_wrist.rotation.x = deg_to_rad(18.0) * smoothstep(0.2, 1.0, u)
