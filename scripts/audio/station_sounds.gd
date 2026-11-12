extends Node
## Round 44 Priorities 7-8: the station SOUNDS LIKE A MACHINE, from where
## the machine is.
##   play_at(kind, pos)   positional 3D sound (SFX bus, a small pool of
##                        AudioStreamPlayer3D) -- the airlock's latches /
##                        hiss come from the airlock, a breaker from the
##                        breaker panel. Every play is remembered in
##                        `heard` (kind, position, real or not) for tests
##                        and investigations.
##   ORDINARY OPERATIONS  a few times per day (deterministic per day,
##                        gameplay time only, never during emergencies):
##                        a ventilation fan changing speed in Life Support,
##                        a relay self-test in Engineering, the comms
##                        receiver's auto-calibration, hull ticking at an
##                        eclipse transition. Each one is REAL: it writes
##                        the matching station-log line, so an odd noise
##                        usually has an ordinary explanation on record.
##   phantom_cycle()      the story layer's one deliberate lie: the airlock
##                        latch + vent hiss + latch, from the airlock, with
##                        NOTHING commanded, NO state change and NO log
##                        entry (the record is what contradicts it).
## Sound settings are respected through the buses; nothing plays in
## bursts (one operation at a time, minimum spacing).

const OPS := [
	{"id": "fan", "pos": Vector3(-2.9, 2.4, 10.8), "kind": &"fan", "log": ["environment", "Life Support fan %s (auto, airflow trim)"]},
	{"id": "relay", "pos": Vector3(-5.6, 1.5, 3.75), "kind": &"relay", "log": ["environment", "Engineering relay self-test OK"]},
	{"id": "rx_cal", "pos": Vector3(2.0, 1.7, 8.1), "kind": &"power_up", "log": ["camera", "RX-A auto-calibration (comms rack)"]},
]
## Round 47: the ACOUSTIC PATH. A sound reaches the technician through the
## station, not through one open room: inverse-distance falloff from
## UNIT_SIZE, and every wall / bulkhead between the listener and the source
## (physics ray on the world layer) costs WALL_DB and lowers the low-pass
## cutoff -- a knock at the airlock heard from the Control Room is distant
## and muffled; next to the hatch it is close and sharp. Per-kind base
## levels keep quiet sounds quiet.
const UNIT_SIZE := 1.6
const WALL_DB := -7.0
const MAX_WALLS := 4
const OPEN_CUTOFF := 9000.0
## Round 48: per-kind levels. Mouth / hand foley is QUIET (it plays a few
## centimetres from the ears); impacts on the hull read across a room.
const KIND_DB := {&"hatch_knock": -1.0, &"glass_knock": -1.0, &"creak": -3.0, &"fan": -4.0,
	&"sip": -17.0, &"swallow": -20.0, &"liquid_tilt": -22.0, &"cup_lift": -16.0, &"cup_down": -9.0,
	&"pouch_crinkle": -15.0, &"pouch_tear": -13.0, &"bite": -19.0, &"chew": -22.0, &"fork_clink": -13.0,
	&"tray_down": -9.0, &"brush_tap": -14.0, &"brush_scrub": -18.0, &"trickle": -11.0}
const Foley = preload("res://scripts/audio/foley_synth.gd")
## Kinds with several recorded-style takes (no machine-gun repetition).
const TAKES := {&"glass_knock": 3, &"hatch_knock": 3}
var _take: Dictionary = {}
const MIN_GAP_S := 120.0
const MAX_OPS_PER_DAY := 4
const AIRLOCK_POS := Vector3(-4.8, 1.6, -2.0)

var heard: Array = []              # [{kind, pos, real, day, t_ms}]
var ops_today: int = 0
var _gap: float = 0.0
var _day: int = -1
var _pool: Array = []
var _streams: Dictionary = {}
var _phantom_steps: Array = []
var _phantom_t: float = 0.0
var _last_eclipse: int = -1
var _fan_level: int = 2


func _ready() -> void:
	add_to_group(&"station_sounds")
	add_to_group(&"r35_equipment")
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
		p.unit_size = UNIT_SIZE
		p.max_distance = 30.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_db = -18.0
		add_child(p)
		_pool.append(p)


func _dp() -> Node:
	return get_parent()


func _main() -> Node:
	return get_parent().get_parent()


func _stream(kind: StringName) -> AudioStream:
	# Round 48: physical foley (foley_synth.gd). Round 47 left glass_knock /
	# hatch_knock WITHOUT any stream: play_at() logged them and played
	# nothing -- the "inaudible knocks". Every kind used now has a stream
	# (test_r48_audio checks it).
	if TAKES.has(kind):
		var n: int = int(_take.get(kind, 0))
		_take[kind] = n + 1
		var key := StringName("%s#%d" % [kind, n % int(TAKES[kind])])
		if not _streams.has(key):
			_streams[key] = Foley.glass_knock(n % 3) if kind == &"glass_knock" else Foley.hatch_knock(n % 3)
		return _streams[key]
	if _streams.has(kind):
		return _streams[kind]
	var fs: AudioStream = null
	match kind:
		&"sip": fs = Foley.sip()
		&"swallow": fs = Foley.swallow()
		&"liquid_tilt": fs = Foley.liquid_tilt()
		&"cup_lift": fs = Foley.cup_lift()
		&"cup_down": fs = Foley.cup_down()
		&"pouch_crinkle": fs = Foley.pouch_crinkle()
		&"pouch_tear", &"wrapper": fs = Foley.pouch_tear()
		&"bite": fs = Foley.bite()
		&"chew": fs = Foley.chew()
		&"fork_clink": fs = Foley.fork_clink()
		&"tray_down", &"tray": fs = Foley.tray_down()
		&"brush_tap": fs = Foley.brush_tap()
		&"trickle": fs = Foley.trickle()
	if fs != null:
		_streams[kind] = fs
		return fs
	var mech: Node = _main().get_node_or_null("Player/HUD/MechanicalSfx")
	var s: AudioStream = null
	if mech != null:
		match kind:
			&"fan":
				s = mech._tone(1.6, func(t, i): return (sin(t * TAU * (60.0 + 40.0 * t)) * 0.35 + (fmod(sin(float(i) * 3.1) * 917.0, 1.0) - 0.5) * 0.12) * minf(t * 3.0, 1.0) * (1.0 - t * 0.4))
			&"cal_confirm":
				# Round 46: a calibration instrument's own two-tone confirm
				# (learned in ordinary play; a false announcement lacks it).
				s = mech._tone(0.42, func(t, _i): return sin(t * 0.42 * TAU * (880.0 if t < 0.5 else 1320.0)) * 0.22 * (1.0 if fmod(t, 0.5) < 0.38 else 0.0))
			# Round 47: ORDINARY LIFE SOUNDS -- each tied to a real action at
			# its real place (quarters_life.gd), so the player learns what
			# normal sounds like.
			&"dispense":            # water filling a cup at the dispenser
				s = mech._tone(0.9, func(t, i): return (fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.3 * minf(t * 12.0, 1.0) * (1.0 - smoothstep(0.8, 1.0, t)) * (0.7 + 0.3 * sin(t * TAU * (30.0 + 40.0 * t))))
			&"kettle":              # the hot-water unit heating: rumble rising to a hiss
				s = mech._tone(2.9, func(t, i): return (sin(t * 2.9 * TAU * 70.0) * 0.12 * (1.0 - t) + (fmod(sin(float(i) * 2.71) * 1777.0, 1.0) - 0.5) * 0.3 * t * t) * minf(t * 10.0, 1.0) * minf((1.0 - t) * 12.0, 1.0))
			&"kettle_done":         # its thermostat switching off
				s = mech._tone(0.12, func(t, _i): return sin(t * 0.12 * TAU * 1700.0) * 0.4 * exp(-t * 30.0) + sin(t * 0.12 * TAU * 220.0) * 0.3 * exp(-t * 20.0))
			&"creak":
				s = mech._tone(0.7, func(t, i): return sin(t * TAU * (140.0 - 60.0 * t)) * 0.3 * pow(1.0 - t, 2.0) + (fmod(sin(float(i) * 7.7) * 311.0, 1.0) - 0.5) * 0.08 * (1.0 - t))
			_:
				s = mech._streams.get(kind, null)
	_streams[kind] = s
	return s


## A positional sound from `pos`. real = caused by actual equipment.
func play_at(kind: StringName, pos: Vector3, real: bool = true) -> void:
	var dp: Node = _dp()
	var path: Dictionary = acoustic_path(pos)
	var db: float = float(KIND_DB.get(kind, 0.0)) + float(path["wall_db"])
	heard.append({"kind": String(kind), "pos": pos, "real": real, "day": int(dp.day_number) if dp != null else 1, "t_ms": Time.get_ticks_msec(),
		"walls": int(path["walls"]), "dist": float(path["dist"]), "db": db + float(path["dist_db"]), "cutoff": float(path["cutoff"])})
	if heard.size() > 60:
		heard.pop_front()
	var s: AudioStream = _stream(kind)
	# Round 48: record whether a sound REALLY started (stream + free voice),
	# so a silent event can never pass for an audible one again.
	heard.back()["played"] = false
	if s == null:
		push_warning("station_sounds: no stream for '%s' (silent)" % kind)
		return
	var ap: AudioStreamPlayer3D = null
	for p in _pool:
		if not (p as AudioStreamPlayer3D).playing:
			ap = p
			break
	if ap == null:
		# all voices busy: take the one closest to finishing
		var best := INF
		for p in _pool:
			var q: AudioStreamPlayer3D = p
			var left: float = q.stream.get_length() - q.get_playback_position() if q.stream != null else 0.0
			if left < best:
				best = left
				ap = q
	ap.stop()
	ap.global_position = pos
	ap.stream = s
	ap.volume_db = db
	ap.attenuation_filter_cutoff_hz = float(path["cutoff"])
	ap.pitch_scale = randf_range(0.97, 1.03)
	ap.play()
	heard.back()["played"] = true
	heard.back()["len"] = s.get_length()
	heard.back()["bus"] = String(ap.bus)


## Round 48: a one-off stream (e.g. a brush scrub phase-locked to the
## animation) through the same positional / acoustic path.
func play_custom(kind: StringName, stream: AudioStream, pos: Vector3) -> void:
	_streams[kind] = stream
	play_at(kind, pos, true)
	_streams.erase(kind)


## Developer / tests: the stream a kind resolves to (null = would be silent).
func stream_for(kind: StringName) -> AudioStream:
	return _stream(kind)


func _listener() -> Node3D:
	var vp: Viewport = get_viewport()
	return vp.get_camera_3d() if vp != null else null


## Distance and occlusion from the technician's ears to `pos`:
## {dist, dist_db (inverse-distance, as the 3D player applies it), walls,
## wall_db, cutoff}.
func acoustic_path(pos: Vector3) -> Dictionary:
	var out := {"dist": 0.0, "dist_db": 0.0, "walls": 0, "wall_db": 0.0, "cutoff": OPEN_CUTOFF}
	var cam: Node3D = _listener()
	if cam == null or not cam.is_inside_tree():
		return out
	var ear: Vector3 = cam.global_position
	var d: float = ear.distance_to(pos)
	out["dist"] = d
	out["dist_db"] = 20.0 * log(UNIT_SIZE / maxf(d, UNIT_SIZE)) / log(10.0)
	var w: int = count_walls(ear, pos)
	out["walls"] = w
	out["wall_db"] = WALL_DB * w
	out["cutoff"] = OPEN_CUTOFF / pow(3.2, w)
	return out


## Solid world surfaces (layer 1) crossed on the straight line a -> b.
func count_walls(a: Vector3, b: Vector3) -> int:
	var w3d: World3D = _main().get_viewport().world_3d if _main() != null and _main().get_viewport() != null else null
	if w3d == null:
		return 0
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var ex: Array = []
	var fb: Node = _main().get_node_or_null("FreeMoveBody")
	if fb is CollisionObject3D:
		ex.append((fb as CollisionObject3D).get_rid())
	var n := 0
	var from: Vector3 = a
	while n < MAX_WALLS:
		var q := PhysicsRayQueryParameters3D.create(from, b)
		q.collision_mask = 1
		q.exclude = ex
		q.hit_back_faces = false
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break
		n += 1
		ex.append(hit["rid"])
		from = (hit["position"] as Vector3) + (b - a).normalized() * 0.01
	return n


func _log() -> Node:
	return get_tree().get_first_node_in_group(&"station_log")


func _process(delta: float) -> void:
	_step_phantom(delta)
	var dp: Node = _dp()
	if dp == null or not dp.has_method("gameplay_delta"):
		return
	if int(dp.day_number) != _day:
		_day = int(dp.day_number)
		ops_today = 0
		_gap = 60.0 + float(absi(hash([_day, "ops"])) % 90)
	_eclipse_ticks()
	var g: float = dp.gameplay_delta(delta)
	if g <= 0.0 or ops_today >= MAX_OPS_PER_DAY:
		return
	var ss: Node = get_tree().get_first_node_in_group(&"station_status")
	if ss != null and ss.has_method("emergency") and not ss.emergency().is_empty():
		return
	_gap -= g
	if _gap > 0.0:
		return
	run_operation(OPS[absi(hash([_day, ops_today, "op"])) % OPS.size()]["id"])


## Performs one REAL ordinary operation now: the sound at its equipment
## and its station-log line.
func run_operation(id: String) -> void:
	for op in OPS:
		if op["id"] != id:
			continue
		ops_today += 1
		_gap = MIN_GAP_S + float(absi(hash([_day, ops_today, "gap"])) % 120)
		var text: String = String(op["log"][1])
		if id == "fan":
			_fan_level = 3 if _fan_level == 2 else 2
			text = text % ("2 -> 3" if _fan_level == 3 else "3 -> 2")
		var lg: Node = _log()
		if lg != null:
			lg.record(String(op["log"][0]), text)
		play_at(op["kind"], op["pos"], true)
		return


## Hull ticking at eclipse entry / exit (thermal), logged.
func _eclipse_ticks() -> void:
	var oc: Node = _main().get_node_or_null("Equipment/OrbitalCycle")
	if oc == null or not oc.has_method("sun_factor"):
		return
	var dark: int = 1 if float(oc.sun_factor()) < 0.2 else 0
	if _last_eclipse == -1:
		_last_eclipse = dark
		return
	if dark != _last_eclipse:
		_last_eclipse = dark
		var lg: Node = _log()
		if lg != null:
			lg.record("environment", "Eclipse %s · hull temperature %s" % ["entry" if dark == 1 else "exit", "falling" if dark == 1 else "rising"])
		play_at(&"creak", Vector3(0.0, 2.6, 0.5), true)


# ------------------------------------------------------------- phantom
## The airlock seems to cycle: latch, vent hiss, latch -- from the airlock.
## Nothing is commanded, nothing changes, nothing is logged.
func phantom_cycle() -> void:
	_phantom_steps = [[0.0, &"latch"], [0.9, &"hiss"], [3.2, &"hiss"], [4.6, &"latch"]]
	_phantom_t = 0.0


func phantom_active() -> bool:
	return not _phantom_steps.is_empty()


func _step_phantom(delta: float) -> void:
	if _phantom_steps.is_empty():
		return
	_phantom_t += delta
	while not _phantom_steps.is_empty() and _phantom_t >= float(_phantom_steps[0][0]):
		var st: Array = _phantom_steps.pop_front()
		play_at(st[1], AIRLOCK_POS, false)


func stop_phantom() -> void:
	_phantom_steps = []


func state_dict() -> Dictionary:
	return {"day": _day, "ops": ops_today, "fan": _fan_level}


func load_dict(d: Dictionary) -> void:
	_day = int(d.get("day", -1))
	ops_today = int(d.get("ops", 0))
	_fan_level = int(d.get("fan", 2))
	_gap = MIN_GAP_S
	_phantom_steps = []
