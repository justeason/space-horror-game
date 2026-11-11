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
		p.unit_size = 4.0
		p.max_distance = 28.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)


func _dp() -> Node:
	return get_parent()


func _main() -> Node:
	return get_parent().get_parent()


func _stream(kind: StringName) -> AudioStream:
	if _streams.has(kind):
		return _streams[kind]
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
			&"creak":
				s = mech._tone(0.7, func(t, i): return sin(t * TAU * (140.0 - 60.0 * t)) * 0.3 * pow(1.0 - t, 2.0) + (fmod(sin(float(i) * 7.7) * 311.0, 1.0) - 0.5) * 0.08 * (1.0 - t))
			_:
				s = mech._streams.get(kind, null)
	_streams[kind] = s
	return s


## A positional sound from `pos`. real = caused by actual equipment.
func play_at(kind: StringName, pos: Vector3, real: bool = true) -> void:
	var dp: Node = _dp()
	heard.append({"kind": String(kind), "pos": pos, "real": real, "day": int(dp.day_number) if dp != null else 1, "t_ms": Time.get_ticks_msec()})
	if heard.size() > 60:
		heard.pop_front()
	var s: AudioStream = _stream(kind)
	if s == null:
		return
	for p in _pool:
		var ap: AudioStreamPlayer3D = p
		if not ap.playing:
			ap.global_position = pos
			ap.stream = s
			ap.pitch_scale = randf_range(0.97, 1.03)
			ap.play()
			return


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
