extends "res://scripts/station/equipment_base.gd"
## Round 35 Priority 5: the ENGINEERING BREAKER PANEL. Four labelled
## breakers with physical levers, trip lamps and a "fault present" lamp.
## Each feeds a real LIGHTING ZONE (its room's main light goes out; a dim
## red emergency light comes on so the room stays navigable). B-02 also
## feeds the Life Support fans (EnvironmentModel airflow drops).
## A breaker can only be reset once its CAUSE has cleared:
##   "surge"    -- a transient trip (already cleared: reset works)
##   "overload" -- the power distribution panel is overloaded (clears when
##                 the loads are balanced)
##   wiring     -- B-03 cannot be reset while the Engineering wiring fault
##                 is unrepaired (reset re-trips; repair the panel first)
## Interacting with an ON breaker switches it off (a real, recoverable
## mistake). The order is done when every breaker is on and no cause holds.

## Round 36 Priority 4: each lighting circuit now owns EVERY normal light
## inside its room ("lights") plus the room's volume ("zone_box": centre,
## size in world space). While the breaker is off, a ReflectionProbe over
## that volume overrides the global ambient fill there (ambient_mode COLOR,
## a fraction of the WorldEnvironment ambient) -- the ambient was the main
## reason an unpowered room still looked lit. The override exists only
## during an outage, so normal lighting is untouched, and only inside the
## affected room, so no other room darkens. A dim red emergency light
## remains, plus a battery-backed locator light on this panel.
const BREAKERS := [
	{"id": "B-01", "circuit": "QUARTERS LTG", "lights": ["Light_Living", "Light_LivingBed"], "zone": &"living_quarters",
		"zone_box": [Vector3(3.7, 1.5, 0.5), Vector3(4.4, 3.4, 4.4)], "emergency_at": Vector3(3.7, 2.55, -1.2)},
	{"id": "B-02", "circuit": "LIFE SUP AUX", "lights": ["Light_LifeSupport"], "zone": &"life_support",
		"zone_box": [Vector3(-2.9, 1.5, 10.8), Vector3(3.6, 3.4, 2.8)], "emergency_at": Vector3(-2.9, 2.55, 11.7)},
	{"id": "B-03", "circuit": "ENGINEERING LTG", "lights": ["Light_Engineering"], "zone": &"engineering",
		"zone_box": [Vector3(-4.2, 1.5, 5.0), Vector3(3.6, 3.4, 4.2)], "emergency_at": Vector3(-4.2, 2.55, 6.6)},
	{"id": "B-04", "circuit": "COMMS LTG", "lights": ["Light_Comms"], "zone": &"communications",
		"zone_box": [Vector3(2.4, 1.5, 7.1), Vector3(4.2, 3.4, 2.8)], "emergency_at": Vector3(2.0, 2.55, 8.1)},
]
## Ambient left inside an unpowered room, as a fraction of the normal fill.
const OUTAGE_AMBIENT_FRACTION := 0.18
const EMERGENCY_ENERGY := 0.32
const EMERGENCY_RANGE := 3.6
@export var lights_path: NodePath = ^"../../Lights"
@export var panel_path: NodePath = ^"../../Geometry/EngineeringCabinet1"
@export var power_path: NodePath = ^"../PowerDistribution"

var on: Array = [true, true, true, true]
var cause: Array = ["", "", "", ""]
var _levers: Array = []
var _trip_lamps: Array = []
var _fault_lamps: Array = []
var _light_energy: Dictionary = {}     # light name -> authored energy
var _emergency: Array = []             # per breaker: OmniLight3D
var _dark_probes: Array = []           # per breaker: ReflectionProbe (outage ambient)
var _locator: OmniLight3D              # battery locator light at this panel
var _env_ambient: Color = Color(0.25, 0.3, 0.35)
var _env_ambient_energy: float = 0.25


func _ready() -> void:
	_base_ready(&"breaker")
	box(Vector3(0.56, 0.62, 0.06), Vector3(0, 0, -0.03), Color(0.22, 0.24, 0.27))
	box(Vector3(0.58, 0.05, 0.08), Vector3(0, 0.33, -0.02), Color(0.85, 0.55, 0.1))
	label("BREAKER PANEL  ·  EPS-2", Vector3(0, 0.25, 0.005), 20)
	for i in BREAKERS.size():
		var x: float = -0.195 + 0.13 * i
		box(Vector3(0.09, 0.2, 0.02), Vector3(x, 0.03, 0.005), Color(0.1, 0.11, 0.12))
		var lever := box(Vector3(0.03, 0.08, 0.04), Vector3(x, 0.07, 0.03), Color(0.85, 0.85, 0.8))
		_levers.append(lever)
		label(BREAKERS[i]["id"], Vector3(x, -0.1, 0.006), 18)
		label(BREAKERS[i]["circuit"], Vector3(x, -0.14, 0.006), 11, Color(0.7, 0.75, 0.75))
		_trip_lamps.append(lamp(Vector3(x - 0.025, 0.17, 0.01)))
		_fault_lamps.append(lamp(Vector3(x + 0.025, 0.17, 0.01)))
		part(StringName("b%d" % i), Vector3(0.1, 0.22, 0.08), Vector3(x, 0.03, 0.03))
	label("TRIP     FAULT", Vector3(0, 0.205, 0.006), 10, Color(0.6, 0.65, 0.65))
	var lights: Node = get_node_or_null(lights_path)
	var we: WorldEnvironment = get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment if get_tree().current_scene != null else null
	if we == null and get_parent() != null and get_parent().get_parent() != null:
		we = get_parent().get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		_env_ambient = we.environment.ambient_light_color
		_env_ambient_energy = we.environment.ambient_light_energy
	for b in BREAKERS:
		var em := OmniLight3D.new()
		em.name = "Emergency_%s" % b["id"]
		em.light_color = Color(1.0, 0.16, 0.1)
		em.light_energy = 0.0
		em.omni_range = EMERGENCY_RANGE
		em.omni_attenuation = 1.4
		em.shadow_enabled = false
		add_child(em)
		em.global_position = b["emergency_at"]
		_emergency.append(em)
		var pr := ReflectionProbe.new()
		pr.name = "OutageAmbient_%s" % b["id"]
		pr.size = b["zone_box"][1]
		pr.interior = true
		pr.box_projection = false
		pr.intensity = 0.25
		pr.blend_distance = 0.4
		pr.update_mode = ReflectionProbe.UPDATE_ONCE
		pr.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		pr.ambient_color = _env_ambient
		pr.ambient_color_energy = _env_ambient_energy * OUTAGE_AMBIENT_FRACTION
		pr.visible = false
		add_child(pr)
		pr.global_position = b["zone_box"][0]
		pr.global_rotation = Vector3.ZERO
		_dark_probes.append(pr)
		for n in b["lights"]:
			var l: Light3D = lights.get_node_or_null(n) if lights != null else null
			if l != null:
				_light_energy[n] = l.light_energy
	_locator = OmniLight3D.new()
	_locator.name = "PanelLocatorLight"
	_locator.light_color = Color(1.0, 0.72, 0.4)
	_locator.light_energy = 0.0
	_locator.omni_range = 1.3
	_locator.shadow_enabled = false
	_locator.position = Vector3(0, 0.42, 0.25)
	add_child(_locator)
	_apply()


func _process(_d: float) -> void:
	# Only a SUSTAINED power overload trips a breaker by itself (B-03, after
	# the distribution panel's delay). An unrepaired wiring fault does not
	# trip anything -- it only BLOCKS resetting B-03.
	var pw: Node = get_node_or_null(power_path)
	if on[2] and pw != null and pw.has_method("overload_trip_due") and pw.overload_trip_due():
		trip(2, "overload")
	for i in BREAKERS.size():
		set_lamp(_fault_lamps[i], Color(1.0, 0.55, 0.1), cause_active(i))


func _wiring_fault() -> bool:
	var p: Node = get_node_or_null(panel_path)
	return p != null and _dp != null and _dp.fault_target == &"engineering_power" and not p.is_repaired()


## Whether a TRIPPED breaker's cause is still present (reset would re-trip).
func cause_active(i: int) -> bool:
	if on[i]:
		return false
	if i == 2 and _wiring_fault():
		return true
	if String(cause[i]) == "overload":
		var pw: Node = get_node_or_null(power_path)
		return pw != null and pw.has_method("is_overloaded") and pw.is_overloaded()
	return false


func _cause_word(i: int) -> String:
	return "wiring fault" if i == 2 and _wiring_fault() else "overload"


func trip(i: int, why: String) -> void:
	if not on[i]:
		cause[i] = why
		return
	on[i] = false
	cause[i] = why
	# Round 44: a trip is heard FROM the breaker panel.
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds") if is_inside_tree() else null
	if snd != null:
		snd.play_at(&"breaker", global_position, true)
	else:
		sfx(&"breaker")
	_apply()
	if _dp != null:
		_dp.log_event("Breaker %s tripped (%s)" % [BREAKERS[i]["id"], why])


## Round 47: a breaker thrown by hand is heard FROM the panel too
## (positional, like a trip), not as an interface click.
func _panel_sfx(kind: StringName) -> void:
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds") if is_inside_tree() else null
	if snd != null:
		snd.play_at(kind, global_position, true)
	else:
		sfx(kind)


func on_part(id: StringName) -> void:
	var i: int = int(String(id).substr(1))
	if on[i]:
		on[i] = false
		cause[i] = ""
		_panel_sfx(&"breaker")
		say("%s switched OFF — %s unpowered." % [BREAKERS[i]["id"], BREAKERS[i]["circuit"]])
		_apply()
		return
	if cause_active(i):
		_panel_sfx(&"breaker")
		say("%s re-tripped — %s still present." % [BREAKERS[i]["id"], _cause_word(i)])
		return
	on[i] = true
	cause[i] = ""
	_panel_sfx(&"relay")
	say("%s reset — %s restored." % [BREAKERS[i]["id"], BREAKERS[i]["circuit"]])
	_apply()
	if _dp != null:
		_dp.log_event("Breaker %s reset" % BREAKERS[i]["id"])


func part_prompt(id: StringName) -> String:
	var i: int = int(String(id).substr(1))
	var b: Dictionary = BREAKERS[i]
	if on[i]:
		return "%s %s — ON  (click: switch off)" % [b["id"], b["circuit"]]
	if cause_active(i):
		return "%s TRIPPED — %s present" % [b["id"], _cause_word(i)]
	return "Click: Reset breaker %s" % b["id"]


## Applies every breaker's real consequence: lever, lamps, zone lights,
## emergency lights.
func _apply() -> void:
	var lights: Node = get_node_or_null(lights_path)
	for i in BREAKERS.size():
		var lever: CSGBox3D = _levers[i]
		lever.position.y = 0.07 if on[i] else -0.01
		lever.rotation_degrees.x = 0.0 if on[i] else 25.0
		set_lamp(_trip_lamps[i], Color(1.0, 0.15, 0.1), not on[i])
		for n in BREAKERS[i]["lights"]:
			var l: Light3D = lights.get_node_or_null(n) if lights != null else null
			if l != null:
				l.light_energy = float(_light_energy.get(n, 1.0)) if on[i] else 0.0
		(_emergency[i] as OmniLight3D).light_energy = 0.0 if on[i] else EMERGENCY_ENERGY
		(_dark_probes[i] as ReflectionProbe).visible = not on[i]
	if _locator != null:
		_locator.light_energy = 0.0 if on.all(func(v): return v) else 0.35


## Round 36: the zone (room) a world point lies in, by the circuits' room
## volumes ("" when outside every lighting zone).
func zone_at(p: Vector3) -> StringName:
	for b in BREAKERS:
		var c: Vector3 = b["zone_box"][0]
		var h: Vector3 = b["zone_box"][1] * 0.5
		if absf(p.x - c.x) <= h.x and absf(p.y - c.y) <= h.y and absf(p.z - c.z) <= h.z:
			return b["zone"]
	return &""


## Ambient energy actually left in a zone right now (tests, renders).
func zone_ambient_energy(zone: StringName) -> float:
	for i in BREAKERS.size():
		if BREAKERS[i]["zone"] == zone and not on[i]:
			return (_dark_probes[i] as ReflectionProbe).ambient_color_energy
	return _env_ambient_energy


func zone_powered(zone: StringName) -> bool:
	for i in BREAKERS.size():
		if BREAKERS[i]["zone"] == zone:
			return on[i]
	return true


func tripped_ids() -> Array:
	var out: Array = []
	for i in BREAKERS.size():
		if not on[i]:
			out.append(BREAKERS[i]["id"])
	return out


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	# A transient SURGE trips one lighting breaker (already cleared).
	var i: int = [0, 1, 3, 2][absi(seed) % 4]
	trip(i, "surge")


## Round 37 severity: a tripped breaker (a room without normal light) is a
## WARNING; the timed overload emergency is the power panel's.
func order_severity() -> int:
	return 2 if not on.all(func(v): return v) else 0


func order_feasible() -> bool:
	return on.all(func(v): return v)


func order_done() -> bool:
	for i in BREAKERS.size():
		if not on[i] or cause_active(i):
			return false
	return true


func order_next() -> Dictionary:
	for i in BREAKERS.size():
		if not on[i]:
			if cause_active(i):
				return {"action": "Repair wiring first" if _cause_word(i) == "wiring fault" else "Balance loads first", "short": "FIX CAUSE", "room": &"engineering"}
			return {"action": "Reset breaker %s" % BREAKERS[i]["id"], "short": "RESET %s" % BREAKERS[i]["id"], "room": &"engineering"}
	return {"action": "Verify lighting", "short": "VERIFY", "room": &"engineering"}


func order_progress() -> String:
	var n: int = on.filter(func(v): return v).size()
	return "%d/4" % n


func order_detail() -> Array:
	var lines: Array = ["Breaker panel EPS-2 (Engineering, west wall)."]
	for i in BREAKERS.size():
		lines.append("%s %-15s %s" % [BREAKERS[i]["id"], BREAKERS[i]["circuit"], "ON" if on[i] else ("TRIPPED — cause present" if cause_active(i) else "TRIPPED — cause cleared")])
	return lines


func state_dict() -> Dictionary:
	return {"on": on.duplicate(), "cause": cause.duplicate()}


func load_dict(d: Dictionary) -> void:
	on = Array(d.get("on", on)).duplicate()
	cause = Array(d.get("cause", cause)).duplicate()
	_apply()
