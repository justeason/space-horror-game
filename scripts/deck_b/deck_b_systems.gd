extends Node
## Round 49: the AUTHORITATIVE models behind Deck B (one source of truth;
## every gauge, lamp, readout and work order reads these numbers; only a
## registered story event may DISPLAY something else, never write here).
##
## Time: models advance with DayPlan.gameplay_delta() (the shift clock's
## own pacing: ~1.5 station minutes per real second; frozen while the clock
## is held), and catch up the night in one pass at the new day.
##
## WATER (B-02)     raw (wastewater / condensate) tank -> pump P-201 ->
##                  MF-2 multifiltration bed -> potable tank; batch cycles
##                  (the pump runs while the raw tank is above its low mark
##                  -- an automatic cycle that can start on its own).
##                  Consumption: drinks, tea, meals, brushing, the basil
##                  (QuartersLife's real routine events); ~60 % returns as
##                  hygiene water / condensate. Product conductivity grows
##                  as the bed wears; a spent bed raises ΔP.
## THERMAL (B-03)   pump P-301 (+ standby P-302) -> branches V1 (Engineering
##                  + battery), V2 (Lab + Archive), V3 (bypass) -> radiator
##                  loops RAD-1 / RAD-2 -> supply. Heat loads come from the
##                  real equipment (Bus A power settings, the payload, the
##                  archive). Engineering / battery / lab / archive
##                  temperatures follow their branch with real lag.
## POWER (Bus B)    four lower-deck circuits B1..B4 behind breakers, fed
##                  from Bus A's ENG-AUX channel (FEED-1: B1, B2) and the
##                  essential bus (FEED-2: B3, B4); B2 can be rerouted to
##                  FEED-2 at Engineering's BUS B TRANSFER switch. Loads are
##                  the real running equipment; a sustained overload trips.
## HYDROPONICS      three trays (moisture, health, growth), reservoir EC/pH,
##                  grow-light banks (power on B3), irrigation lines.
## LAB / MEDICAL / CARGO / ARCHIVE  -- their rooms own most of their state;
##                  shared numbers (payload power, incubator, dose) live here.
## SERVICE HISTORY  every closed Deck B job: time, room, equipment, fault,
##                  action, verification, outcome -> station log (SERVICE)
##                  and the Archive.

const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const Tasks = preload("res://scripts/deck_b/deck_b_tasks.gd")
const SIM_MIN_PER_S := 1.5          # station minutes per real gameplay second

var water := {"raw_l": 22.0, "potable_l": 128.0, "pot_cond": 14.0, "turb": 0.3, "filter_life": 0.66, "filter_kind": "mf_bed",
	"pump_on": true, "auto": true, "processing": false, "pump_fault": "", "v_in": 1.0, "v_out": 1.0, "v_rc": 0.0,
	"bleed": false, "level_bias": 0.0, "starts": [], "drawn_l": 0.0}
var thermal := {"speed": 1.0, "fault": "", "standby": false, "v1": 0.75, "v2": 0.5, "v3": 0.25, "rad": [1.0, 1.0], "rad_fault": "",
	"supply": 7.0, "ret_eng": 11.0, "ret_lab": 10.5, "eng_T": 24.0, "batt_T": 23.0, "lab_T": 21.0, "arch_T": 22.0, "accum": 205.0, "charge_limit": 1.0}
var power := {"on": [true, true, true, true], "trip_s": [0.0, 0.0, 0.0, 0.0], "feed1_fault": "", "b2_source": "F1", "dropout": false, "last_trip": "",
	"short": -1, "short_cause": "", "lockout": [false, false, false, false], "fault_trips": 0}
var hydro := {"trays": [{"moist": 0.62, "health": 0.86, "growth": 0.45, "clean": 0.9}, {"moist": 0.6, "health": 0.84, "growth": 0.4, "clean": 0.85}, {"moist": 0.64, "health": 0.88, "growth": 0.5, "clean": 0.9}],
	"ec": 1.6, "ph": 6.0, "light": [1.0, 1.0, 1.0], "light_ok": [true, true, true], "line": ["", "", ""], "sensor_bias": [0.0, 0.0, 0.0], "pump_ok": true, "log": []}
var lab := {"incubator_set": 37.0, "incubator_T": 37.0, "heater_ok": true, "pdu": [true, true, true], "fuse": [true, true, true]}
var med := {"badge_usv": 0.0, "total_msv": 11.8, "reader_gain": 1.0, "exercise_days": [], "checks": []}
## Round 50 (L10): the lower deck's air. CO2 comes from the technician
## (more while exercising), the lit grow trays take some up, the CDRA-B
## scrubber (two amine beds, one adsorbing while the other regenerates; on
## B3 HABITAT) removes it -- only as well as the spine vent VF-B2 moves air
## through it. The CS-B cabin sensor can drift (a SENSOR fault).
var air := {"co2": 2900.0, "beds": [0.82, 0.95], "active": 0, "regen": -1.0, "swap_stuck": false,
	"vent_switch": true, "fan_cutout": false, "sensor_bias": 0.0, "recovering": false}
## Round 50 (L09 / A06): the station's PRESSURE NETWORK -- a handful of
## gas volumes joined by real openings (see the pressure section below).
## p: kPa per compartment; hatch: compartment hatch OPEN; eq: its
## equalisation valve OPEN; duct: the inter-deck ventilation isolation
## valve IV-AB OPEN; leaks: the physical defects [{id, comp, kind, c
## (m³/s at the defect), state active|temp|repaired, sev, day, found}];
## makeup: the pressure control system's gas reserve (kPa·m³).
var press := {"p": {"A": 101.3, "BC": 101.3, "B03": 101.3, "B04": 101.3, "B08": 101.3},
	"trend": {"A": 0.0, "BC": 0.0, "B03": 0.0, "B04": 0.0, "B08": 0.0},
	"hatch": {"B03": true, "B04": true, "B08": true}, "eq": {"B03": false, "B04": false, "B08": false},
	"duct": true, "leaks": [], "makeup": 26000.0, "makeup_flow": 0.0, "alarm": 0, "roll_day": -1}
var service_log: Array = []          # [{day, t, room, equipment, fault, action, verify, outcome, type}]
var visits: Dictionary = {}          # day -> [rooms]
var part_seq: int = 0
var faults_rolled_day: int = -1
var tier1_day: int = -1
var shipments_due: Array = []        # days a resupply vehicle berths
## Parts the technician placed on Deck B racks (a player-established fact
## the Chapter Two "missing part" beat may contradict): [{day, rack, item, room}]
var player_stows: Array = []


func note_stow(rack_name: String, item_name: String, room_id: String) -> void:
	player_stows.append({"day": day(), "rack": rack_name, "item": item_name, "room": room_id})
	if player_stows.size() > 20:
		player_stows.pop_front()
var _dp: Node
var _feed_t: float = 0.0
var _poll: float = 0.0
signal service_recorded(entry: Dictionary)


func _ready() -> void:
	add_to_group(&"deck_b_systems")
	add_to_group(&"r35_equipment")
	_dp = _find_dp()
	if _dp != null:
		if _dp.has_signal(&"day_started"):
			_dp.day_started.connect(_on_day_started)
	_hook_quarters.call_deferred()


func _find_dp() -> Node:
	var n: Node = self
	while n != null:
		var d: Node = n.get_node_or_null("DayPlan")
		if d != null:
			return d
		n = n.get_parent()
	return null


func _hook_quarters() -> void:
	var q: Node = get_tree().get_first_node_in_group(&"quarters_life") if is_inside_tree() else null
	if q != null and q.has_signal(&"consumed") and not q.consumed.is_connected(on_consumed):
		q.consumed.connect(on_consumed)


func day() -> int:
	return int(_dp.day_number) if _dp != null else 1


# ------------------------------------------------------------------ time
## The models advance in fixed 0.25 s ticks (a reload never lands
## half-way through a step; a saved state is restored exactly).
const TICK_S := 0.25
var _acc: float = 0.0


func _process(delta: float) -> void:
	var gd: float = _dp.gameplay_delta(delta) if _dp != null and _dp.has_method("gameplay_delta") else delta
	# Round 50: a live pressure emergency is a CRITICAL timer -- it is never
	# held by focused laptop use (and focus is refused / ended during one).
	if int(press.get("alarm", 0)) > 0:
		gd = delta
	_acc += gd
	while _acc >= TICK_S:
		_acc -= TICK_S
		step(TICK_S)
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		_track_visit()
		_check_faults()


## Advance every model by `dt` real gameplay seconds.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	var hours: float = dt * SIM_MIN_PER_S / 60.0
	_step_power(dt)
	_step_water(hours)
	_step_thermal(dt)
	_step_hydro(hours)
	_step_lab(dt)
	_step_air(dt)
	_step_press(dt)


## The night: ~9 station hours of processing, growth and drift at once.
func catch_up_night(hours: float = 9.0) -> void:
	var real_s: float = hours * 60.0 / SIM_MIN_PER_S
	var chunk: float = 20.0
	var left: float = real_s
	while left > 0.0:
		var d: float = minf(chunk, left)
		_step_water(d * SIM_MIN_PER_S / 60.0)
		_step_hydro(d * SIM_MIN_PER_S / 60.0)
		left -= d
	for k in ["eng_T", "batt_T", "lab_T", "arch_T"]:
		thermal[k] = _equip_target(k)
	# Overnight the technician sleeps on Deck A: the lower deck settles.
	air["co2"] = co2_equilibrium(CO2_BASE * 0.4)
	_night_pressure(real_s)
	air["regen"] = -1.0
	var other: int = 1 - int(air["active"])
	air["beds"][other] = 1.0


# ----------------------------------------------------------------- power
const CIRCUITS := [["B1", "PUMPS", 1.5], ["B2", "LAB / ARCHIVE", 1.4], ["B3", "HABITAT", 0.9], ["B4", "LOGISTICS", 1.1]]
const FEED2_RATING := 2.4
var _extra_load := {}                 # circuit -> {source: kW} (rooms report)


func set_load(circuit: int, source: String, kw: float) -> void:
	if not _extra_load.has(circuit):
		_extra_load[circuit] = {}
	_extra_load[circuit][source] = kw


func feed_factor(i: int) -> float:
	if not power["on"][i]:
		return 0.0
	var on_feed1: bool = i == 0 or (i == 1 and power["b2_source"] == "F1")
	if on_feed1:
		if power["dropout"]:
			return 0.0
		var pd: Node = _power_dist()
		if pd != null and pd.has_method("channel_state") and String(pd.channel_state(1)) == "UNDER":
			return 0.8
	return 1.0


func powered(i: int) -> bool:
	return feed_factor(i) > 0.5


func load_kw(i: int) -> float:
	var kw: float = 0.0
	match i:
		0:
			kw += 0.35 if (water["processing"] and powered(0)) else 0.0
			kw += 0.6 * float(thermal["speed"]) if not thermal["standby"] else 0.0
			kw += 0.45 if thermal["standby"] else 0.0
		1:
			for k in 3:
				if lab["pdu"][k] and lab["fuse"][k]:
					kw += [0.25, 0.3, 0.1][k]
			kw += 0.45
		2:
			for k in 3:
				kw += 0.2 * float(hydro["light"][k]) * (1.0 if hydro["light_ok"][k] else 0.35)
			kw += 0.12
		3:
			kw += 0.08
	for src in _extra_load.get(i, {}):
		kw += float(_extra_load[i][src])
	return kw


func feed2_load() -> float:
	var kw: float = load_kw(2) + load_kw(3)
	if power["b2_source"] == "F2":
		kw += load_kw(1)
	return kw


func _step_power(dt: float) -> void:
	# FEED-1 contactor CHATTER (an intermittent fault): drops out ~1.5 s in
	# every ~7 s -- not every observation catches it.
	if power["feed1_fault"] == "chatter":
		_feed_t += dt
		var ph: float = fmod(_feed_t + float(absi(hash(day())) % 5), 7.0)
		power["dropout"] = ph > 5.5
	else:
		power["dropout"] = false
	for i in 4:
		if not power["on"][i]:
			power["trip_s"][i] = 0.0
			continue
		# Round 50 (E12): a ground fault trips its breaker at once.
		if int(power["short"]) == i:
			power["on"][i] = false
			power["trip_s"][i] = 0.0
			power["last_trip"] = CIRCUITS[i][0]
			power["fault_trips"] = int(power["fault_trips"]) + 1
			_log("Bus B breaker %s (%s) TRIPPED — ground fault" % [CIRCUITS[i][0], CIRCUITS[i][1]])
			if is_inside_tree():
				for a in get_tree().get_nodes_in_group(&"station_ai"):
					a.event(&"bus_b_fault")
			continue
		var over: bool = load_kw(i) > float(CIRCUITS[i][2])
		if i == 1 and power["b2_source"] == "F2" and feed2_load() > FEED2_RATING:
			over = true
		power["trip_s"][i] = float(power["trip_s"][i]) + dt if over else 0.0
		if float(power["trip_s"][i]) > 4.0:
			power["on"][i] = false
			power["trip_s"][i] = 0.0
			power["last_trip"] = CIRCUITS[i][0]
			_log("Bus B breaker %s (%s) TRIPPED — overload" % [CIRCUITS[i][0], CIRCUITS[i][1]])


func _power_dist() -> Node:
	var main: Node = _dp.get_parent() if _dp != null else null
	return main.get_node_or_null("Equipment/PowerDistribution") if main != null else null


# ----------------------------------------------------------------- water
const RAW_LOW := 12.0
const RAW_HIGH := 26.0


func pump_factor() -> float:
	match String(water["pump_fault"]):
		"air_lock":
			return 0.1
		"seal_leak":
			return 0.72
		"worn_bearing":
			return 0.93
	return 1.0


## Process flow through the bed, L/h (0 when idle / unpowered).
func water_flow() -> float:
	if not water["processing"] or not water["pump_on"]:
		return 0.0
	var f: float = 12.0 * pump_factor() * feed_factor(0) * float(water["v_in"]) * float(water["v_out"])
	f *= 0.35 + 0.65 * float(water["filter_life"])
	if water["filter_kind"] != "mf_bed":
		f *= 0.4
	return f


func water_pressure() -> float:
	if not water["processing"] or not water["pump_on"] or not powered(0):
		return 0.0
	var p: float = 175.0 * pump_factor() * feed_factor(0)
	if water["pump_fault"] == "air_lock":
		p = 45.0 + sin(Time.get_ticks_msec() * 0.011) * 22.0
	if float(water["v_out"]) < 0.2:
		p *= 1.18           # dead-headed: pressure rises, nothing flows
	return p


func filter_dp() -> float:
	if water_flow() <= 0.0:
		return 0.0
	return 18.0 + 72.0 * (1.0 - float(water["filter_life"]))


## Product (processed) water conductivity, µS/cm.
func product_cond() -> float:
	var life: float = float(water["filter_life"])
	var c: float = 6.0 + 90.0 * pow(1.0 - life, 2.0)
	if water["filter_kind"] != "mf_bed":
		c += 40.0
	return c


func _step_water(hours: float) -> void:
	# Humidity condensate keeps arriving.
	water["raw_l"] = minf(float(water["raw_l"]) + 0.25 * hours, 60.0)
	if water["auto"]:
		if float(water["raw_l"]) > RAW_HIGH and not water["processing"] and water["pump_on"]:
			water["processing"] = true
			_pump_start("auto cycle")
		elif float(water["raw_l"]) < RAW_LOW and water["processing"]:
			water["processing"] = false
	var f: float = water_flow()
	if f > 0.0:
		var vol: float = minf(f * hours, float(water["raw_l"]))
		water["raw_l"] = float(water["raw_l"]) - vol
		var back: float = vol * 0.6 * float(water["v_rc"])
		var out: float = vol - back
		water["raw_l"] = float(water["raw_l"]) + back
		var pv: float = float(water["potable_l"])
		water["pot_cond"] = (float(water["pot_cond"]) * pv + product_cond() * out) / maxf(pv + out, 0.001)
		water["potable_l"] = minf(pv + out, 200.0)
		water["filter_life"] = maxf(float(water["filter_life"]) - vol / 380.0, 0.0)
		if water["v_rc"] > 0.4:
			# Recirculating potable water through a good bed polishes it.
			var pc: float = float(water["pot_cond"])
			water["pot_cond"] = maxf(pc - (pc - product_cond()) * 0.08 * hours * 4.0, product_cond())


func _pump_start(why: String) -> void:
	var st: Array = water["starts"]
	st.append({"day": day(), "t": _dp.clock_text_hhmm() if _dp != null and _dp.has_method("clock_text_hhmm") else "--:--", "why": why})
	if st.size() > 20:
		st.pop_front()


## QuartersLife consumed something real: draw potable water, return part.
func on_consumed(kind: String) -> void:
	var draw: float = {"water": 0.35, "tea": 0.3, "meal": 0.35, "dinner": 0.4, "brush": 0.15, "pour": 0.2}.get(kind, 0.0)
	if draw <= 0.0:
		return
	water["potable_l"] = maxf(float(water["potable_l"]) - draw, 0.0)
	water["raw_l"] = minf(float(water["raw_l"]) + draw * 0.6, 60.0)
	water["drawn_l"] = float(water["drawn_l"]) + draw


func water_status() -> String:
	if float(water["potable_l"]) < 20.0:
		return "RESERVE LOW"
	if float(water["pot_cond"]) > 45.0:
		return "QUALITY HOLD"
	if water["pump_fault"] != "" and water["processing"]:
		return "PUMP FAULT"
	if filter_dp() > 62.0:
		return "FILTER"
	return "OK"


func tank_level_reading(potable: bool) -> float:
	var v: float = float(water["potable_l"]) if potable else float(water["raw_l"])
	return v + (float(water["level_bias"]) if potable else 0.0)


# --------------------------------------------------------------- thermal
func coolant_flow() -> float:
	var f: float
	if thermal["standby"]:
		f = 22.0
	else:
		f = 30.0 * float(thermal["speed"]) * feed_factor(0)
		match String(thermal["fault"]):
			"restriction":
				f *= 0.6
			"cavitation":
				f *= 0.78 + sin(Time.get_ticks_msec() * 0.004) * 0.06
			"bearing":
				f *= 0.95
			"speed_drop":
				f *= 0.22
	return maxf(f, 0.0)


func branch_flows() -> Array:
	var g1: float = float(thermal["v1"])
	var g2: float = float(thermal["v2"])
	var g3: float = float(thermal["v3"])
	var tot: float = g1 + g2 + g3 + 0.05
	var f: float = coolant_flow()
	return [f * g1 / tot, f * g2 / tot, f * g3 / tot]


func heat_loads() -> Array:
	var eng: float = 2.3
	var pd: Node = _power_dist()
	if pd != null and "setting" in pd:
		for s in pd.setting:
			eng += 0.12 * float(s)
	var batt: float = 0.9 * float(thermal.get("charge_limit", 1.0))
	var lab_kw: float = load_kw(1) * 0.85
	return [eng + batt, lab_kw + 0.4]


func rad_eff() -> float:
	return (float(thermal["rad"][0]) + float(thermal["rad"][1])) * 0.5


func _step_thermal(dt: float) -> void:
	var loads: Array = heat_loads()
	var q: float = float(loads[0]) + float(loads[1])
	var fl: Array = branch_flows()
	var c: float = 0.0697
	var supply_t: float = 3.0 + q / maxf(rad_eff() * 0.95, 0.15)
	var ftot: float = coolant_flow()
	if ftot < 4.0:
		supply_t += (4.0 - ftot) * 1.6       # stagnant loop: heat not carried away
	var ret_eng: float = supply_t + float(loads[0]) / maxf(float(fl[0]) * c, 0.05)
	var ret_lab: float = supply_t + float(loads[1]) / maxf(float(fl[1]) * c, 0.05)
	var k: float = 1.0 - exp(-dt / 20.0)
	thermal["supply"] = lerpf(float(thermal["supply"]), supply_t, k)
	# (A branch with no flow stalls near the hot side's limit; equipment
	# protection holds it below ~40 °C -- recoverable, never destroyed.)
	thermal["ret_eng"] = lerpf(float(thermal["ret_eng"]), minf(ret_eng, 32.0), k)
	thermal["ret_lab"] = lerpf(float(thermal["ret_lab"]), minf(ret_lab, 32.0), k)
	var ke: float = 1.0 - exp(-dt / 45.0)
	for key in ["eng_T", "batt_T", "lab_T", "arch_T"]:
		thermal[key] = lerpf(float(thermal[key]), _equip_target(key), ke)


func _equip_target(key: String) -> float:
	match key:
		"eng_T":
			return float(thermal["ret_eng"]) + 11.0
		"batt_T":
			return float(thermal["ret_eng"]) + 9.5
		"lab_T":
			return float(thermal["ret_lab"]) + 9.0
		"arch_T":
			return float(thermal["ret_lab"]) + 10.5
	return 22.0


func pump_vibration() -> float:
	if thermal["standby"]:
		return 1.4
	match String(thermal["fault"]):
		"bearing":
			return 7.8
		"loose_mount":
			return 9.5
		"cavitation":
			return 4.6
		"restriction":
			return 2.2
		"speed_drop":
			return 1.0
	return 1.8


func thermal_status() -> String:
	if float(thermal["batt_T"]) > 33.0 or float(thermal["eng_T"]) > 35.0:
		return "OVERHEAT"
	if float(thermal["supply"]) > 9.5:
		return "SUPPLY HIGH"
	if thermal["fault"] != "":
		return "PUMP"
	return "OK"


# ----------------------------------------------------------- hydroponics
func _step_hydro(hours: float) -> void:
	var lights_on: bool = powered(2)
	for i in 3:
		var t: Dictionary = hydro["trays"][i]
		t["moist"] = maxf(float(t["moist"]) - 0.035 * hours, 0.0)
		var feeding: bool = hydro["pump_ok"] and hydro["line"][i] != "blocked" and lights_on
		if feeding and float(t["moist"]) < 0.72:
			var add: float = 0.06 * hours * (0.45 if hydro["line"][i] == "leak" else 1.0)
			t["moist"] = minf(float(t["moist"]) + add, 0.78)
		var ok_moist: bool = float(t["moist"]) > 0.38 and float(t["moist"]) < 0.85
		var ok_ec: bool = float(hydro["ec"]) > 1.1 and float(hydro["ec"]) < 2.3
		var ok_ph: bool = float(hydro["ph"]) > 5.4 and float(hydro["ph"]) < 6.7
		var lux: float = float(hydro["light"][i]) * (1.0 if hydro["light_ok"][i] else 0.35) * (1.0 if lights_on else 0.0)
		var target: float = 0.95 * (1.0 if ok_moist else 0.45) * (1.0 if ok_ec else 0.7) * (1.0 if ok_ph else 0.75) * clampf(lux / 0.8, 0.4, 1.0) * (0.8 + 0.2 * float(t["clean"]))
		t["health"] = move_toward(float(t["health"]), target, 0.02 * hours)
		t["growth"] = minf(float(t["growth"]) + 0.003 * hours * float(t["health"]), 1.0)
		t["clean"] = maxf(float(t["clean"]) - 0.002 * hours, 0.0)
	hydro["ec"] = maxf(float(hydro["ec"]) - 0.008 * hours, 0.4)
	hydro["ph"] = minf(float(hydro["ph"]) + 0.006 * hours, 7.5)


func moisture_reading(i: int) -> float:
	return clampf(float(hydro["trays"][i]["moist"]) + float(hydro["sensor_bias"][i]), 0.0, 1.0)


func light_output(i: int) -> float:
	if not powered(2):
		return 0.0
	return float(hydro["light"][i]) * (1.0 if hydro["light_ok"][i] else 0.35)


# ---------------------------------------------------------- air (L10)
const CO2_OUTSIDE := 400.0             # what the inter-deck exchange tends to
const CO2_BASE := 10.0                 # ppm/s from one technician at work
const CO2_EXERCISE := 7.0              # extra ppm/s on the ergometer
const CO2_CAUTION := 5000.0            # CS-B caution (order raised)
const K_SCRUB := 0.004                 # per s, a fresh bed with full airflow
const K_LEAK := 0.0004                 # per s, exchange with Deck A
const REGEN_S := 45.0


func vent_flow() -> bool:
	return bool(air["vent_switch"]) and not bool(air["fan_cutout"])


func scrubber_powered() -> bool:
	return powered(2)


## 0..1: how much of K_SCRUB the scrubber achieves right now.
func scrub_eff() -> float:
	if not scrubber_powered():
		return 0.0
	var bed: float = float(air["beds"][int(air["active"])])
	return clampf(bed * 1.25, 0.0, 1.0) * (1.0 if vent_flow() else 0.15)


func co2_production() -> float:
	var p: float = CO2_BASE
	var med: Node = get_parent().get_node_or_null("Rooms/MedicalBay") if get_parent() != null else null
	if med != null and med.get("exercising") == true:
		p += CO2_EXERCISE
	for k in 3:
		p -= light_output(k) * 1.5
	return maxf(p, 0.0)


func co2_equilibrium(prod: float) -> float:
	return CO2_OUTSIDE + prod / (K_SCRUB * scrub_eff() + K_LEAK)


## What the CS-B cabin sensor shows (true value + its drift).
func co2_reading() -> float:
	return float(air["co2"]) + float(air["sensor_bias"])


func _step_air(dt: float) -> void:
	var k: float = K_SCRUB * scrub_eff() + K_LEAK
	air["co2"] = maxf(float(air["co2"]) + (co2_production() - k * (float(air["co2"]) - CO2_OUTSIDE)) * dt, CO2_OUTSIDE)
	if not scrubber_powered():
		return
	var a: int = int(air["active"])
	# The adsorbing bed loads slowly; the auto-cycle swaps beds at 30 %
	# (unless the swap valve sticks) and regenerates the loaded one.
	air["beds"][a] = maxf(float(air["beds"][a]) - 0.00004 * dt * (float(air["co2"]) / 3000.0), 0.0)
	if float(air["regen"]) >= 0.0:
		air["regen"] = float(air["regen"]) + dt
		if float(air["regen"]) >= REGEN_S:
			air["regen"] = -1.0
			air["beds"][1 - a] = 1.0
			_log("CDRA-B: bed %s regenerated" % ["A", "B"][1 - a])
	elif float(air["beds"][a]) < 0.3 and not air["swap_stuck"] and float(air["beds"][1 - a]) > 0.9:
		swap_beds("auto-cycle")


func swap_beds(why: String) -> void:
	air["active"] = 1 - int(air["active"])
	air["regen"] = 0.0
	_log("CDRA-B: bed %s adsorbing, bed %s regenerating (%s)" % [["A", "B"][int(air["active"])], ["A", "B"][1 - int(air["active"])], why])


func air_status() -> String:
	var r: float = co2_reading()
	return "CAUTION" if r > CO2_CAUTION else ("ELEVATED" if r > 4200.0 else "NORMAL")


# ----------------------------------------------------- pressure (L09)
## Round 50: the PRESSURE NETWORK. One authoritative abstraction of the
## station's atmosphere as five connected gas volumes (no fluid dynamics):
##   A    Deck A (the whole upper habitat, ~190 m³)
##   BC   Deck B core: the junction, spine, corridors and every lower room
##        without its own sealing hatch
##   B03 / B04 / B08  Thermal Control, the Workshop and Cargo (+ the B-11
##        stub) -- each behind a real pressure hatch with an equalisation
##        valve (pressure_hatches.gd)
## Links (conductance G, m³/s; flow = G x ΔP, kPa·m³/s):
##   A <-> BC   the inter-deck ventilation duct (isolation valve IV-AB on
##              the PCP-B panel) + the shaft lid while it is open
##   BC <-> X   the compartment's hatch (open) or its EQ valve
## Leaks to vacuum: flow = c x p (choked through a small defect), c in m³/s.
## The pressure control system (PCS) feeds make-up gas into Deck A from a
## finite reserve, up to MAKEUP_MAX: a small leak is held, a big one is not.
## Deck A's cabin pressure (EnvironmentModel) follows A's deficit.
const P_NOM := 101.3
const P_CAUTION := 99.5           # kPa: below the normal control band
const P_WARNING := 97.0           # kPa: makeup cannot hold the station
const P_CRITICAL := 90.0          # kPa: leave / isolate now (still survivable)
const TREND_CAUTION := -0.25      # kPa/min sustained
const MAKEUP_MAX := 1.4           # kPa·m³/s
const MAKEUP_K := 3.0             # kPa·m³/s per kPa below the setpoint
const G_DUCT := 6.0
const G_SHAFT := 20.0
const G_HATCH := 25.0
const G_EQ := 4.0
const HATCH_DP_MAX := 3.5         # kPa: a hatch cannot be pulled open above this
const TEMP_FACTOR := 0.04         # a temporary patch / clamp leaves 4 % of the flow
const COMP_ROOM := {"A": &"", "BC": &"b01", "B03": &"b03", "B04": &"b04", "B08": &"b08"}
const COMP_NAME := {"A": "DECK A", "BC": "DECK B CORE", "B03": "B-03 THERMAL", "B04": "B-04 WORKSHOP", "B08": "B-08 CARGO"}
## The defect catalogue: id -> [compartment, kind, c by severity 1..3, where].
const LEAK_SITES := {
	"b03_feed": ["B03", "pipe", [0.02, 0.035, 0.05], "coolant-line hull feedthrough FT-3 (packing gland)"],
	"b08_seal": ["B08", "seal", [0.035, 0.06, 0.09], "berthing port seal BP-1"],
	"hull_b04": ["B04", "hull", [0.04, 0.075, 0.12], "hull penetration, B-04 south wall"],
	"hull_seam": ["A", "hull", [0.004, 0.006, 0.009], "panel seam beside the airlock (exterior)"],
}
const A_VOLUME := 190.0
var _vol: Dictionary = {}


func comp_volume(c: String) -> float:
	if _vol.is_empty():
		_vol = {"A": A_VOLUME, "BC": 0.0, "B03": 0.0, "B04": 0.0, "B08": 0.0}
		for sp in L.SPACES:
			if sp[1] == "sealed":
				continue
			var k: String = comp_of_space(String(sp[0]))
			_vol[k] = float(_vol[k]) + (float(sp[3]) - float(sp[2])) * (float(sp[5]) - float(sp[4])) * (float(sp[6]) - L.FLOOR_Y)
	return float(_vol.get(c, 1.0))


static func comp_of_space(sp: String) -> String:
	match sp:
		"B03": return "B03"
		"B04": return "B04"
		"B08", "B11": return "B08"
	return "BC"


## The compartment a world point is in ("" outside every volume).
func comp_at(p: Vector3) -> String:
	if not L.is_lower(p):
		return "A"
	var sp: String = L.space_at(p.x, p.z)
	return comp_of_space(sp) if sp != "" else "BC"


func pressure(c: String) -> float:
	return float(press["p"].get(c, P_NOM))


func trend(c: String) -> float:
	return float(press["trend"].get(c, 0.0))


func hatch_open(c: String) -> bool:
	return bool(press["hatch"].get(c, true))


func hatch_dp(c: String) -> float:
	return pressure("BC") - pressure(c)


func _shaft_open() -> bool:
	var sh: Node = get_parent().get_node_or_null("VerticalShaft") if get_parent() != null else null
	return sh != null and sh.get("lid_open") == true


func link_g(c: String) -> float:
	if c == "BC":
		return (G_DUCT if bool(press["duct"]) else 0.0) + (G_SHAFT if _shaft_open() else 0.0)
	if hatch_open(c):
		return G_HATCH
	return G_EQ if bool(press["eq"].get(c, false)) else 0.0


func leak_c(lk: Dictionary) -> float:
	match String(lk.get("state", "active")):
		"repaired":
			return 0.0
		"temp":
			return float(lk["c"]) * TEMP_FACTOR
	return float(lk["c"])


func leak(id: String) -> Dictionary:
	for lk in press["leaks"]:
		if String(lk["id"]) == id:
			return lk
	return {}


## Gas lost through every defect right now (kPa·m³/s).
func leak_flow(comp: String = "") -> float:
	var q := 0.0
	for lk in press["leaks"]:
		if comp == "" or String(lk["comp"]) == comp:
			q += leak_c(lk) * pressure(String(lk["comp"]))
	return q


func _step_press(dt: float) -> void:
	var p: Dictionary = press["p"]
	var f := {"A": 0.0, "BC": 0.0, "B03": 0.0, "B04": 0.0, "B08": 0.0}
	for lk in press["leaks"]:
		var c: String = String(lk["comp"])
		f[c] -= leak_c(lk) * float(p[c])
	for c in ["BC", "B03", "B04", "B08"]:
		var up: String = "A" if c == "BC" else "BC"
		var q: float = link_g(c) * (float(p[up]) - float(p[c]))
		f[up] -= q
		f[c] += q
	var m := 0.0
	if float(press["makeup"]) > 0.0 and float(p["A"]) < P_NOM:
		m = minf(MAKEUP_MAX, MAKEUP_K * (P_NOM - float(p["A"])))
		f["A"] += m
		press["makeup"] = maxf(float(press["makeup"]) - m * dt, 0.0)
	press["makeup_flow"] = m
	for c in f:
		var old: float = float(p[c])
		p[c] = clampf(old + float(f[c]) / comp_volume(c) * dt, 0.0, P_NOM + 0.5)
		var rate: float = (float(p[c]) - old) / dt * 60.0
		press["trend"][c] = lerpf(float(press["trend"][c]), rate, 1.0 - exp(-dt / 12.0))
	press["alarm"] = press_alarm()


## Station alarm level from the real network: 0 none, 1 CAUTION,
## 2 WARNING, 3 CRITICAL -- over every compartment someone could be in.
func press_alarm() -> int:
	var lvl := 0
	for c in press["p"]:
		var pc: float = float(press["p"][c])
		if c != "A" and c != "BC" and not hatch_open(c):
			continue      # an isolated compartment alarms on its own panel
		if pc < P_CRITICAL:
			lvl = maxi(lvl, 3)
		elif pc < P_WARNING:
			lvl = maxi(lvl, 2)
		elif pc < P_CAUTION or float(press["trend"][c]) < TREND_CAUTION:
			lvl = maxi(lvl, 1)
	return lvl


static func alarm_word(lvl: int) -> String:
	return ["NORMAL", "CAUTION", "WARNING", "CRITICAL"][clampi(lvl, 0, 3)]


## Open / close a compartment hatch. Refused (with the reason) above the
## safe differential: the physical seal of a real pressure door.
func set_hatch(c: String, open: bool) -> String:
	if open and absf(hatch_dp(c)) > HATCH_DP_MAX:
		return "ΔP %.1f kPa — equalise first (EQ valve)" % absf(hatch_dp(c))
	press["hatch"][c] = open
	_log("Hatch %s %s (%.1f / %.1f kPa)" % [COMP_NAME[c], "OPENED" if open else "CLOSED", pressure("BC"), pressure(c)])
	return ""


func set_eq(c: String, open: bool) -> void:
	press["eq"][c] = open
	_log("Hatch %s EQ valve %s" % [COMP_NAME[c], "OPEN" if open else "CLOSED"])


func set_duct(open: bool) -> void:
	press["duct"] = open
	_log("Inter-deck duct IV-AB %s" % ("OPEN" if open else "CLOSED"))


## A real defect appears (daily roll, an order rearm, a hull strike, the
## developer). Never twice: an existing one only escalates.
func inject_leak(id: String, sev: int = 2) -> Dictionary:
	if not LEAK_SITES.has(id):
		return {}
	var e: Array = LEAK_SITES[id]
	var lk: Dictionary = leak(id)
	if lk.is_empty() or String(lk["state"]) == "repaired":
		press["leaks"] = press["leaks"].filter(func(x): return String(x["id"]) != id)
		lk = {"id": id, "comp": e[0], "kind": e[1], "c": float(e[2][clampi(sev, 1, 3) - 1]), "state": "active", "sev": clampi(sev, 1, 3), "day": day(), "found": false}
		press["leaks"].append(lk)
		_log("PRESSURE: %s — %s" % [COMP_NAME[e[0]], e[3]])
	return lk


func set_leak_state(id: String, state: String) -> void:
	var lk: Dictionary = leak(id)
	if lk.is_empty():
		return
	lk["state"] = state
	_log("PRESSURE: %s %s" % [LEAK_SITES[id][3], {"temp": "temporarily sealed", "repaired": "repaired", "active": "leaking"}.get(state, state)])


## Developer / tests: every defect gone, every hatch and valve normal,
## every volume back at nominal. Never touches inventory or progression.
func clear_pressure() -> void:
	press["leaks"] = []
	for c in press["p"]:
		press["p"][c] = P_NOM
		press["trend"][c] = 0.0
	for c in press["hatch"]:
		press["hatch"][c] = true
		press["eq"][c] = false
	press["duct"] = true
	press["alarm"] = 0


## The open defects (not repaired) in a compartment / of a kind.
func active_leaks(kind: String = "") -> Array:
	return press["leaks"].filter(func(x): return String(x["state"]) != "repaired" and (kind == "" or String(x["kind"]) == kind))


## Where pressure is being lost right now, for the L09 order.
func leaking_comp() -> String:
	var best := ""
	var q := 0.0
	for lk in press["leaks"]:
		var lq: float = leak_c(lk) * pressure(String(lk["comp"]))
		if lq > q:
			q = lq
			best = String(lk["comp"])
	return best


func press_status() -> String:
	return "%s · A %.1f · B %.1f kPa · makeup %.2f" % [alarm_word(int(press["alarm"])), pressure("A"), pressure("BC"), float(press["makeup_flow"])]


## Story-gated anomaly hook (Round 50 FOUNDATION, never active in normal
## play): a transient pressure drop that exists only in the RECORDS -- the
## workstation trend / archive line shows it, the physical compartment and
## this model do not (the authoritative pressure is never written). Only a
## registered story beat may call it with preview = false; the developer
## preview returns the record and stores nothing.
var press_ghosts: Array = []


func pressure_anomaly(preview: bool) -> Dictionary:
	var rec := {"day": day(), "comp": "B04", "shown_kpa": snappedf(pressure("B04") - 4.7, 0.1), "actual_kpa": snappedf(pressure("B04"), 0.1), "preview": preview,
		"text": "TRANSIENT ΔP B-04: -4.7 kPa in 0.8 s (no hatch / leak event)"}
	if not preview:
		press_ghosts.append(rec)
	return rec


## Deck A's cabin pressure deficit from the network (EnvironmentModel).
func deck_a_deficit() -> float:
	return maxf(P_NOM - pressure("A"), 0.0)


## The technician's local air (EnvironmentModel's symptoms): pressure of
## the compartment they are in, and CO2 when on Deck B.
func local_air(p: Vector3) -> Dictionary:
	var c: String = comp_at(p)
	return {"comp": c, "kpa": pressure(c), "co2": float(air["co2"]) if L.is_lower(p) else 600.0}


## Overnight: the pressure control system's AUTOMATIC isolation closes any
## sealable compartment still losing gas (logged -- the technician is
## asleep on Deck A), the isolated volume decays on its own, and make-up
## gas covers whatever small loss is left (from the finite reserve).
func _night_pressure(real_s: float) -> void:
	for lk in active_leaks():
		var c: String = String(lk["comp"])
		if press["hatch"].has(c) and hatch_open(c) and leak_c(lk) > 0.003:
			press["hatch"][c] = false
			press["eq"][c] = false
			_log("PCS: %s isolated automatically overnight (pressure loss)" % COMP_NAME[c])
	for c in ["B03", "B04", "B08"]:
		if not hatch_open(c):
			var k: float = leak_flow(c) / maxf(pressure(c), 0.01) / comp_volume(c)
			press["p"][c] = pressure(c) * exp(-k * real_s) if not bool(press["eq"][c]) else pressure("BC")
		else:
			press["p"][c] = P_NOM
	var q: float = leak_flow("A") + leak_flow("BC")
	press["makeup"] = maxf(float(press["makeup"]) - q * real_s, 0.0)
	press["p"]["A"] = P_NOM if float(press["makeup"]) > 0.0 else press["p"]["A"]
	press["p"]["BC"] = pressure("A")
	for c in press["trend"]:
		press["trend"][c] = 0.0


# ------------------------------------------------------------------- lab
func payload_powered() -> bool:
	return powered(1)


func _step_lab(dt: float) -> void:
	var heater: bool = lab["heater_ok"] and lab["fuse"][0] and lab["pdu"][0] and payload_powered()
	var ambient: float = float(thermal["lab_T"])
	var target: float = float(lab["incubator_set"]) if heater else ambient
	var f2: float = float(branch_flows()[1])
	if heater and f2 > 12.0:
		# An over-fed lab coolant branch pulls more heat out of the
		# incubator's cold plate than its heater can make up.
		target -= (f2 - 12.0) * 0.15
	lab["incubator_T"] = lerpf(float(lab["incubator_T"]), target, 1.0 - exp(-dt / 30.0))


# --------------------------------------------------------------- medical
## The technician's measured condition, from the REAL state: fatigue,
## nutrition, hydration, cabin O2 / pressure, exercise.
func vitals() -> Dictionary:
	var tired: float = float(_dp.tiredness()) if _dp != null and _dp.has_method("tiredness") else 0.0
	var underfed: bool = _dp != null and _dp.get("underfed") == true
	var q: Node = get_tree().get_first_node_in_group(&"quarters_life") if is_inside_tree() else null
	var drank: bool = q == null or not q.has_method("drank_today") or q.drank_today()
	var ate: bool = q == null or not q.has_method("ate_today") or q.ate_today()
	var env: Node = _dp.get_parent().get_node_or_null("EnvironmentModel") if _dp != null else null
	var o2: float = float(env.o2_kpa) if env != null else 21.2
	var exercised: bool = med["exercise_days"].has(day()) or med["exercise_days"].has(day() - 1)
	var hr: float = 64.0 + tired * 18.0 + (6.0 if underfed else 0.0) + (4.0 if not drank else 0.0) - (3.0 if exercised else 0.0)
	var spo2: float = clampf(97.5 - maxf(21.0 - o2, 0.0) * 2.2, 85.0, 99.0)
	var temp: float = 36.7 + (0.2 if not drank else 0.0)
	var glucose: float = 5.2 - (1.3 if underfed else 0.0) - (0.4 if not ate else 0.0)
	var flags: Array = []
	if hr > 85.0:
		flags.append("HR HIGH")
	if spo2 < 94.0:
		flags.append("SpO2 LOW")
	if glucose < 4.0:
		flags.append("GLUCOSE LOW")
	# Round 50: sustained high CO2 on the lower deck raises the breathing /
	# heart rate a little (never a collapse).
	var co2: float = float(air["co2"])
	if co2 > 5000.0:
		hr += minf((co2 - 5000.0) / 1000.0 * 2.0, 10.0)
		flags.append("CO2 HIGH")
	if not drank:
		flags.append("HYDRATION")
	return {"hr": hr, "spo2": spo2, "temp": temp, "glucose": glucose, "flags": flags, "rest": 1.0 - tired}


## Expected dose since a day, µSv (orbital background ~0.35 mSv/day; EVA
## adds through the suit). Deterministic from the real days elapsed.
func expected_dose_usv(days: float, eva_hours: float = 0.0) -> float:
	return days * 350.0 + eva_hours * 60.0


# ---------------------------------------------------------- service log
func record_service(e: Dictionary) -> void:
	service_log.append(e)
	if service_log.size() > 120:
		service_log.pop_front()
	var lg: Node = get_tree().get_first_node_in_group(&"station_log") if is_inside_tree() else null
	if lg != null:
		lg.record("maintenance", "%s · %s · %s → %s · %s" % [L.ROOMS.get(StringName(e.get("room", "")), ["", e.get("room", "")])[1] if L.ROOMS.has(StringName(e.get("room", ""))) else String(e.get("room", "")).to_upper(), e.get("equipment", ""), e.get("action", ""), String(e.get("outcome", "")).to_upper().replace("_", " "), e.get("verify", "")])
	service_recorded.emit(e)


func _log(text: String) -> void:
	if _dp != null and _dp.has_method("log_event"):
		_dp.log_event(text)


func next_part_name(kind: StringName) -> String:
	part_seq += 1
	return "DBPart_%s_%d" % [String(kind), part_seq]


# ---------------------------------------------------------------- visits
func _track_visit() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	var room: StringName = L.room_at(cam.global_position)
	if room == &"":
		return
	var d: int = day()
	if not visits.has(d):
		visits[d] = []
	if not visits[d].has(String(room)):
		visits[d].append(String(room))
		var lg: Node = get_tree().get_first_node_in_group(&"station_log")
		if lg != null:
			lg.record("access", "%s %s · entered · TECH-1" % ["B-" + String(room).substr(1), L.ROOMS[room][1]])


func on_player_arrived_deck_b() -> void:
	_track_visit()


func rooms_visited_total() -> Array:
	var out: Array = []
	for d in visits:
		for r in visits[d]:
			if not out.has(r):
				out.append(r)
	return out


func deck_b_days() -> int:
	return visits.keys().size()


# ------------------------------------------------------------ fault roll
## Real faults raise their own orders (once per day roll + live checks).
func _check_faults() -> void:
	var clr: Node = get_tree().get_first_node_in_group(&"clearance") if is_inside_tree() else null
	var tier: int = int(clr.deck_b_tier()) if clr != null and clr.has_method("deck_b_tier") else 0
	if tier < 1 or _dp == null or not _dp.has_method("raise_order"):
		return
	if float(water["filter_life"]) < 0.36:
		_raise(&"b02_filter", "filter ΔP high")
	if float(thermal["batt_T"]) > 33.5:
		_raise(&"e11_battery", "battery temperature high")
	if float(thermal["eng_T"]) > 32.0 and thermal["fault"] == "speed_drop":
		_raise(&"b03_overheat", "coolant pump speed low")
	if tier >= 3 and power["feed1_fault"] == "chatter":
		_raise(&"b05_power", "payload power interruptions")
	if int(power["short"]) >= 0 and int(power["fault_trips"]) > 0:
		_raise(&"e12_short", "breaker %s tripped — ground fault" % CIRCUITS[int(power["short"])][0])
	if bool(air.get("recovering", false)) and (air_fault() != "" or co2_reading() < CO2_CAUTION - 300.0):
		air["recovering"] = false
	if co2_reading() > CO2_CAUTION and not bool(air.get("recovering", false)):
		if not _dp.has_open_order(&"l10_co2"):
			for a in get_tree().get_nodes_in_group(&"station_ai"):
				a.event(&"co2_high")
		_raise(&"l10_co2", "CS-B CO2 %.0f ppm" % co2_reading())
	# L09: a REAL pressure loss the network measures (caution or worse on a
	# connected volume), or a compartment left isolated / patched with its
	# defect still there (a permanent repair is due -- never for a hull
	# defect, whose permanent repair is the A06 EVA job).
	var lc: String = leaking_comp()
	if lc != "" and press_alarm() >= 1:
		_raise(&"l09_pressure", "%s pressure falling (%.1f kPa/min)" % [COMP_NAME[lc], trend(lc)])
	for lk in active_leaks():
		if String(lk["kind"]) != "hull" and day() > int(lk["day"]) and (String(lk["state"]) == "temp" or not hatch_open(String(lk["comp"]))):
			if int(press.get("repair_raised", -1)) != day():
				press["repair_raised"] = day()
				_raise(&"l09_pressure", "%s: permanent repair due" % LEAK_SITES[String(lk["id"])][3])


func _raise(t: StringName, why: String) -> void:
	if _dp.has_open_order(t):
		return
	_dp.raise_order(t, why)


## DayPlan emits day_started on a real new day AND after a load; only a
## REAL new day runs the night (`night_day` is saved).
var night_day: int = 0


func _on_day_started(_d: int) -> void:
	if day() > night_day:
		if night_day > 0:
			catch_up_night()
			water["drawn_l"] = 0.0
			_roll_day_faults()
		night_day = day()


## Deterministic daily faults (a reload never re-rolls: same day, same
## history -> same result), never on the first Deck B days.
func _roll_day_faults() -> void:
	var d: int = day()
	if faults_rolled_day == d:
		return
	faults_rolled_day = d
	var clr: Node = get_tree().get_first_node_in_group(&"clearance") if is_inside_tree() else null
	var tier: int = int(clr.deck_b_tier()) if clr != null and clr.has_method("deck_b_tier") else 0
	if tier < 1:
		return
	if tier1_day < 0:
		tier1_day = d
	if d - tier1_day < 3:
		return
	var roll: int = absi(hash([d, "deckb_fault"])) % 100
	# At most one model fault per day, rarely.
	if roll < 6 and thermal["fault"] == "":
		thermal["fault"] = "speed_drop"
		_log("Coolant pump P-301: speed controller fault (speed limited)")
	elif roll >= 6 and roll < 10 and tier >= 3 and power["feed1_fault"] == "":
		power["feed1_fault"] = "chatter"
		_log("Bus B FEED-1 contactor: intermittent")
	elif roll >= 10 and roll < 13 and int(power["short"]) < 0:
		inject_short(2 + (absi(hash([d, "short"])) % 2), "moisture" if (absi(hash([d, "cause"])) % 3) == 0 else "terminal")
	elif roll >= 13 and roll < 17:
		inject_air_fault(["bed", "airflow", "sensor"][absi(hash([d, "air"])) % 3])
	elif roll >= 17 and roll < 20 and active_leaks().is_empty():
		# L09: a pressure defect inside the hull (never on the first Deck B
		# days; the cargo seal only once Cargo is open to the technician).
		var sev: int = 1 + absi(hash([d, "psev"])) % 2
		inject_leak("b08_seal" if tier >= 2 and (absi(hash([d, "pwhere"])) % 2) == 0 else "b03_feed", sev)
	elif roll >= 20 and roll < 22:
		# A06: a debris strike on the hull (hull_repair.gd places it).
		var hr: Node = get_tree().get_first_node_in_group(&"hull_repair") if is_inside_tree() else null
		if hr != null and hr.has_method("strike_from_roll"):
			hr.strike_from_roll(d, tier)


## Real model faults (daily roll, order rearm, developer panel).
func inject_short(circuit: int, cause: String) -> void:
	power["short"] = circuit
	power["short_cause"] = cause
	power["fault_trips"] = 0
	_log("Bus B %s: insulation resistance low" % CIRCUITS[circuit][0])


func clear_short() -> void:
	power["short"] = -1
	power["short_cause"] = ""
	power["fault_trips"] = 0


func inject_air_fault(kind: String) -> void:
	match kind:
		"bed":
			air["beds"][int(air["active"])] = 0.12
			air["swap_stuck"] = true
			air["regen"] = -1.0
			_log("CDRA-B: auto-cycle swap valve not responding")
		"airflow":
			air["fan_cutout"] = true
			_log("VF-B2: motor thermal cutout")
		"sensor":
			air["sensor_bias"] = 3400.0


## The current CO2 cause the model really has ("" = none).
func air_fault() -> String:
	if float(air["sensor_bias"]) > 500.0:
		return "sensor"
	if not vent_flow():
		return "airflow"
	if air["swap_stuck"] or float(air["beds"][int(air["active"])]) < 0.25:
		return "bed"
	if not scrubber_powered():
		return "power"
	return ""


# -------------------------------------------------------------- persist
func state_dict() -> Dictionary:
	return {"water": water.duplicate(true), "thermal": thermal.duplicate(true), "power": power.duplicate(true), "hydro": hydro.duplicate(true), "air": air.duplicate(true), "press": press.duplicate(true),
		"lab": lab.duplicate(true), "med": med.duplicate(true), "service_log": service_log.duplicate(true), "visits": visits.duplicate(true),
		"part_seq": part_seq, "faults_rolled_day": faults_rolled_day, "tier1_day": tier1_day, "night_day": maxi(night_day, day()), "player_stows": player_stows.duplicate(true), "press_ghosts": press_ghosts.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	if not d.has("press"):
		clear_pressure()         # a pre-Round-50 save: a healthy, unbroken hull
		press["makeup"] = 26000.0
	for key in ["water", "thermal", "power", "hydro", "lab", "med", "air", "press"]:
		if d.has(key) and d[key] is Dictionary:
			var cur: Dictionary = get(key)
			for k in d[key]:
				cur[k] = d[key][k]
	service_log = Array(d.get("service_log", []))
	visits = {}
	var v: Dictionary = d.get("visits", {})
	for k in v:
		visits[int(k)] = Array(v[k])
	part_seq = int(d.get("part_seq", part_seq))
	faults_rolled_day = int(d.get("faults_rolled_day", -1))
	tier1_day = int(d.get("tier1_day", -1))
	night_day = int(d.get("night_day", day()))
	player_stows = Array(d.get("player_stows", []))
	press_ghosts = Array(d.get("press_ghosts", []))
	_acc = 0.0
