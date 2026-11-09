extends "res://scripts/station/equipment_base.gd"
## Round 35 Priority 7: the POWER DISTRIBUTION panel (Engineering). Three
## fixed channels, each with a 0-4 output setting adjusted by physical
## ▲/▼ controls, a load bar and a status lamp, plus a bus voltmeter.
## Model (authoritative, deterministic):
##   demand r_i (1..3)  -- the day's required level per channel (seeded)
##   setting s_i (0..4) -- what the player set
##   bus voltage        = 28.0 - 0.6 x sum|s_i - r_i|  (- 1.0 if overloaded)
##   UNDER (s < r)      -- that channel's equipment is under-powered
##                         (LS-FANS under -> Life Support airflow x0.75)
##   OVER (s > r)       -- excess load; total excess >= 2 = OVERLOAD, which
##                         trips breaker B-03 after 45 s if left unresolved
##   balanced           -- all s == r, held stable for the verification time
## The machine layout never changes; only the day's fault does. Every
## configuration is solvable (s_i can always be set to r_i).
## Difficulty: EASY shows the target level, NORMAL shows UNDER/OK/OVER,
## HARD shows only the load bars and the voltmeter.

const CHANNELS := ["LS-FANS", "ENG-AUX", "COMMS"]
## Round 37: 90 s from overload to the B-03 trip. Route lengths from every
## room to this panel are 1-16 m (estimated along the doorway waypoints,
## MILESTONE1_DESIGN Round 37): <= 9 s at the 1.8 m/s walking speed, plus
## getting up / doorways and ~10 s to correct the channels -- actionable
## from anywhere on the station, still urgent. (Was 45 s.)
const OVERLOAD_TRIP_S := 90.0
const VERIFY_S := 4.0
@export var breaker_path: NodePath = ^"../BreakerPanel"

var demand: Array = [2, 2, 2]
var setting: Array = [2, 2, 2]
var verified: bool = true
var _stable_s: float = VERIFY_S
var _overload_s: float = 0.0
var _bars: Array = []
var _lamps: Array = []
var _status: Array = []
var _meter: Label3D
var _hint: Label3D
var _solar: Label3D
var _solar_bar: CSGBox3D
var _solar_bar_bg: CSGBox3D


func _arrays() -> Node:
	return get_tree().get_first_node_in_group(&"solar_arrays") if is_inside_tree() else null


func _ready() -> void:
	_base_ready(&"power")
	box(Vector3(0.62, 0.6, 0.06), Vector3(0, 0, -0.03), Color(0.2, 0.23, 0.25))
	box(Vector3(0.64, 0.05, 0.08), Vector3(0, 0.32, -0.02), Color(0.85, 0.55, 0.1))
	label("POWER DISTRIBUTION  ·  BUS A", Vector3(0, 0.25, 0.005), 20)
	_meter = label("", Vector3(0, 0.18, 0.006), 22, Color(0.55, 0.95, 0.75))
	for i in CHANNELS.size():
		var x: float = -0.2 + 0.2 * i
		label(CHANNELS[i], Vector3(x, 0.11, 0.006), 14)
		box(Vector3(0.05, 0.16, 0.01), Vector3(x - 0.05, -0.02, 0.0), Color(0.06, 0.07, 0.08))
		var bar := box(Vector3(0.04, 0.15, 0.012), Vector3(x - 0.05, -0.02, 0.004), Color(0.3, 0.85, 0.4))
		_bars.append(bar)
		_lamps.append(lamp(Vector3(x + 0.05, 0.06, 0.01)))
		_status.append(label("", Vector3(x + 0.03, -0.13, 0.006), 12))
		box(Vector3(0.05, 0.035, 0.02), Vector3(x + 0.04, 0.0, 0.01), Color(0.75, 0.78, 0.8))
		label("+", Vector3(x + 0.04, 0.0, 0.022), 16, Color(0.1, 0.1, 0.1))
		part(StringName("up%d" % i), Vector3(0.06, 0.045, 0.05), Vector3(x + 0.04, 0.0, 0.02))
		box(Vector3(0.05, 0.035, 0.02), Vector3(x + 0.04, -0.06, 0.01), Color(0.75, 0.78, 0.8))
		label("-", Vector3(x + 0.04, -0.06, 0.022), 16, Color(0.1, 0.1, 0.1))
		part(StringName("dn%d" % i), Vector3(0.06, 0.045, 0.05), Vector3(x + 0.04, -0.06, 0.02))
	_hint = label("", Vector3(0, -0.23, 0.006), 12, Color(0.7, 0.75, 0.75))
	# Round 41: the solar arrays feed Bus A -- one more readout line and a
	# SOLAR check button (the VERIFY OUTPUT step of the solar orders).
	# (Inside the panel face, between the channel status row and the
	# STABLE hint -- below the panel sits the thermal terminal block.)
	_solar = label("", Vector3(-0.06, -0.172, 0.006), 13, Color(0.6, 0.85, 1.0))
	_solar_bar_bg = box(Vector3(0.36, 0.014, 0.008), Vector3(-0.06, -0.197, 0.0), Color(0.05, 0.06, 0.07))
	_solar_bar = box(Vector3(0.36, 0.012, 0.01), Vector3(-0.06, -0.197, 0.003), Color(0.4, 0.75, 1.0))
	box(Vector3(0.1, 0.045, 0.02), Vector3(0.235, -0.185, 0.0), Color(0.2, 0.4, 0.6))
	label("SOLAR", Vector3(0.235, -0.185, 0.012), 12, Color(0.95, 0.95, 0.9))
	part(&"solar", Vector3(0.11, 0.055, 0.05), Vector3(0.235, -0.185, 0.01))
	_hint.position.y = -0.255
	_refresh()


func _process(delta: float) -> void:
	if balanced():
		if not verified:
			_stable_s += delta
			if _stable_s >= VERIFY_S:
				verified = true
				sfx(&"success")
				say("Bus A balanced and stable.")
				if _dp != null:
					_dp.log_event("Power distribution balanced")
	else:
		_stable_s = 0.0
	if is_overloaded():
		var was_due: bool = overload_trip_due()
		_overload_s += delta
		if not was_due and overload_trip_due():
			sfx(&"warn")
	else:
		_overload_s = 0.0
	_refresh()


func balanced() -> bool:
	for i in CHANNELS.size():
		if int(setting[i]) != int(demand[i]):
			return false
	return true


func excess() -> int:
	var e := 0
	for i in CHANNELS.size():
		e += maxi(int(setting[i]) - int(demand[i]), 0)
	return e


func is_overloaded() -> bool:
	return excess() >= 2


func overload_trip_due() -> bool:
	return is_overloaded() and _overload_s >= OVERLOAD_TRIP_S


func bus_voltage() -> float:
	var dev := 0
	for i in CHANNELS.size():
		dev += absi(int(setting[i]) - int(demand[i]))
	var droop: float = 0.0
	var sa: Node = _arrays()
	if sa != null:
		droop = sa.bus_droop()     # Round 41: only a low reserve + deficit
	return 28.0 - 0.6 * dev - (1.0 if is_overloaded() else 0.0) - droop


func channel_state(i: int) -> String:
	var s: int = int(setting[i])
	var r: int = int(demand[i])
	return "UNDER" if s < r else ("OVER" if s > r else "OK")


## Life Support airflow factor from the fans' power (and their breaker).
func fan_factor() -> float:
	var f := 1.0
	if channel_state(0) == "UNDER":
		f *= 0.75
	var b: Node = get_node_or_null(breaker_path)
	if b != null and b.has_method("zone_powered") and not b.zone_powered(&"life_support"):
		f *= 0.6
	return f


func on_part(id: StringName) -> void:
	if id == &"solar":
		sfx(&"click")
		var sa: Node = _arrays()
		say(sa.readout() if sa != null else "No solar data.", 5.0)
		get_tree().call_group(&"solar_task", &"on_output_checked")
		return
	var s := String(id)
	var i: int = int(s.substr(s.length() - 1))
	var up: bool = s.begins_with("up")
	var v: int = clampi(int(setting[i]) + (1 if up else -1), 0, 4)
	if v == int(setting[i]):
		sfx(&"click")
		return
	setting[i] = v
	verified = false
	_stable_s = 0.0
	sfx(&"ratchet")
	_refresh()


func part_prompt(id: StringName) -> String:
	if id == &"solar":
		return "Click: check solar output"
	var s := String(id)
	var i: int = int(s.substr(s.length() - 1))
	return "Click: %s %s (now %d)" % ["Raise" if s.begins_with("up") else "Lower", CHANNELS[i], int(setting[i])]


func _refresh() -> void:
	if _meter == null:
		return
	var d: int = difficulty()
	_meter.text = "BUS  %.1f V%s" % [bus_voltage(), "   OVERLOAD" if is_overloaded() else ""]
	_meter.modulate = Color(0.55, 0.95, 0.75) if balanced() else (Color(1.0, 0.35, 0.25) if is_overloaded() else Color(1.0, 0.75, 0.3))
	for i in CHANNELS.size():
		var frac: float = clampf(float(setting[i]) / 4.0, 0.02, 1.0)
		var bar: CSGBox3D = _bars[i]
		bar.size.y = 0.15 * frac
		bar.position.y = -0.095 + bar.size.y * 0.5
		var st: String = channel_state(i)
		var c: Color = Color(0.3, 0.85, 0.4) if st == "OK" else (Color(1.0, 0.3, 0.2) if st == "OVER" else Color(1.0, 0.75, 0.25))
		(bar.material as StandardMaterial3D).albedo_color = c
		set_lamp(_lamps[i], c, true)
		var txt := ""
		if d == 0:
			txt = "%s  %d>%d" % [st, int(setting[i]), int(demand[i])]
		elif d == 1:
			txt = "%s  %d" % [st, int(setting[i])]
		else:
			txt = "%d" % int(setting[i])
		(_status[i] as Label3D).text = txt
	var sa: Node = _arrays()
	if sa != null and _solar != null:
		_solar.text = "SOLAR %.1f kW  LOAD %.1f  RES %d%%" % [sa.generation(), sa.load_kw(), roundi(sa.reserve * 100.0)]
		_solar.modulate = Color(0.6, 0.85, 1.0) if sa.margin() >= 0.0 else (Color(1.0, 0.35, 0.25) if sa.reserve_low() else Color(1.0, 0.75, 0.3))
		var f: float = clampf(sa.generation() / (2.0 * sa.WING_KW), 0.02, 1.0)
		_solar_bar.size.x = 0.36 * f
		_solar_bar.position.x = -0.24 + _solar_bar.size.x * 0.5
	_hint.text = "STABLE" if verified else ("Stabilising %.0f s" % maxf(VERIFY_S - _stable_s, 0.0) if balanced() else "Adjust channels to demand")


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in CHANNELS.size():
		demand[i] = 1 + rng.randi() % 3
	# Start out of balance: at least one channel off by 1-2.
	for i in CHANNELS.size():
		setting[i] = clampi(int(demand[i]) + [-1, 0, 1, 2][rng.randi() % 4], 0, 4)
	if balanced():
		setting[0] = clampi(int(demand[0]) + (1 if int(demand[0]) < 4 else -1), 0, 4)
	# Round 37: a ROUTINE balancing order never starts overloaded (that
	# used to start the trip timer while the player was still asleep).
	# Overloads are emergencies, raised only by surge() mid-shift.
	while is_overloaded():
		for i in CHANNELS.size():
			if int(setting[i]) > int(demand[i]):
				setting[i] = int(setting[i]) - 1
				break
	if balanced():
		setting[0] = clampi(int(demand[0]) - 1, 0, 4) if int(demand[0]) > 0 else 1
	verified = false
	_stable_s = 0.0
	_overload_s = 0.0
	_refresh()


func order_feasible() -> bool:
	return verified


func order_done() -> bool:
	return verified and balanced()


func order_next() -> Dictionary:
	if balanced():
		return {"action": "Hold stable (verifying)", "short": "HOLD", "room": &"engineering"}
	for i in CHANNELS.size():
		if channel_state(i) == "OVER":
			return {"action": "Lower %s" % CHANNELS[i], "short": "LOWER %s" % CHANNELS[i], "room": &"engineering"}
	for i in CHANNELS.size():
		if channel_state(i) == "UNDER":
			return {"action": "Raise %s" % CHANNELS[i], "short": "RAISE %s" % CHANNELS[i], "room": &"engineering"}
	return {"action": "Balance loads", "short": "BALANCE", "room": &"engineering"}


func order_progress() -> String:
	var ok: int = 0
	for i in CHANNELS.size():
		if channel_state(i) == "OK":
			ok += 1
	return "%d/3" % ok


func order_detail() -> Array:
	var lines: Array = ["Power distribution, Bus A (Engineering, south wall).", "Bus %.1f V%s" % [bus_voltage(), " — OVERLOAD (B-03 trips in %.0f s)" % maxf(OVERLOAD_TRIP_S - _overload_s, 0.0) if is_overloaded() else ""]]
	for i in CHANNELS.size():
		lines.append("%s  set %d  %s" % [CHANNELS[i], int(setting[i]), channel_state(i)])
	return lines


# ------------------------------------------------- Round 37 emergencies
## A downstream load on one channel drops out mid-shift: that channel's
## set output now exceeds its demand by 2 -> Bus A OVERLOAD (the real
## overload model above), and B-03 trips after OVERLOAD_TRIP_S unless the
## channel output is reduced at this panel.
func surge(seed: int) -> int:
	var c: int = posmod(seed, CHANNELS.size())
	if int(setting[c]) < 2:
		setting[c] = 2
	demand[c] = maxi(int(setting[c]) - 2, 0)
	verified = false
	_stable_s = 0.0
	_overload_s = 0.0
	_refresh()
	return c


## Severity of this equipment's state (0 normal .. 3 emergency).
func order_severity() -> int:
	if is_overloaded():
		return 3
	if channel_state(0) == "UNDER":
		return 2   # Life Support fans under-powered: airflow reduced
	return 0 if balanced() else 1


## The real timed consequence, or {} when none is pending.
func emergency_info() -> Dictionary:
	if not is_overloaded():
		return {}
	var b: Node = get_node_or_null(breaker_path)
	if b != null and not b.on[2]:
		return {}   # already tripped: the consequence has happened
	var worst := 0
	for i in CHANNELS.size():
		if int(setting[i]) - int(demand[i]) > int(setting[worst]) - int(demand[worst]):
			worst = i
	return {"id": "overload", "title": "POWER OVERLOAD", "room": &"engineering", "seconds": maxf(OVERLOAD_TRIP_S - _overload_s, 0.0),
		"action": "Reduce %s output" % CHANNELS[worst], "consequence": "B-03 trip", "zone": &"engineering"}


func state_dict() -> Dictionary:
	return {"demand": demand.duplicate(), "setting": setting.duplicate(), "verified": verified, "overload_s": _overload_s}


func load_dict(d: Dictionary) -> void:
	demand = Array(d.get("demand", demand)).duplicate()
	setting = Array(d.get("setting", setting)).duplicate()
	verified = bool(d.get("verified", verified))
	_overload_s = float(d.get("overload_s", 0.0))
	_stable_s = VERIFY_S if verified else 0.0
	_refresh()
