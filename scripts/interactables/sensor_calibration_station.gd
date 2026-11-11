extends StaticBody3D
## Life Support's environmental sensor calibration unit -- implements
## L07 Environmental Sensor Calibration, the ONE locked task in
## GAME_DESIGN.md's Task Database (Section 29) whose own documented
## description -- "Adjust dial/knob until readings converge" -- already
## matches this milestone's contrasting calibration prototype
## (continuous adjustment + convergence) with no invented task
## identity. No other candidate task in the catalog is described this
## way; L07 was chosen for that reason, not arbitrarily (see
## MILESTONE1_DESIGN.md's record of this round).
##
## One small prop, one duck-typed interact() -- same "each physical
## object owns its own small state" convention as every other
## interactable in this project (GAME_DESIGN.md Section 48). The only
## state this script itself owns is a thin pass-through to DayPlan's
## l07_status; the actual calibration gameplay lives entirely in
## scripts/ui/sensor_calibration_view.gd.

@export var day_plan_path: NodePath
@export var calibration_view_path: NodePath

## Round 16 Priority 8: how many of the three chambers start faulted --
## a property of THIS WORK-ORDER instance/scenario, exported per
## station rather than looked up from global difficulty. Round 15 kept
## this mechanic (fault count scaling with the number of simultaneous
## problems the player must manage) but implemented it by keying
## straight off GameSettings.get_difficulty() (1 fault on EASY, 2 on
## NORMAL, 3 on HARD) -- which conflates two things the brief asks to
## stay separate: global difficulty (how forgiving the tolerance/
## coupling/stability-hold requirement are, still difficulty-keyed
## below in sensor_calibration_view.gd) and task PROGRESSION (how many
## simultaneous problems this particular assignment presents). An EASY-
## difficulty player and a HARD-difficulty player attempting this same
## station now face the identical fault count (this export's value) --
## only how forgiving the attempt is differs by difficulty, exactly as
## the brief's own "allow early assignments to be simple on any global
## difficulty, with advanced assignments becoming more complex through
## progression" describes. This project has no actual day/assignment
## progression system yet (day_plan.gd's own doc comment: "no
## calendar, no day counter" -- and this round explicitly does not add
## one), so for now this is a single exported value on the one L07
## station instance rather than something a real scenario-selector
## picks; the seam is real (a future second station/scenario would
## just export a different value here), even though only one scenario
## exists today.
## Round 18 Priority 3: no longer read by sensor_calibration_view.gd --
## the player's own explicit instruction this round ties the required-
## calibration count to DIFFICULTY (randomized within a per-difficulty
## range each attempt), superseding this export's whole premise. Left
## in place (not deleted) only because it is still a harmless, unused
## @export; a future round could repurpose or remove it.
@export_range(1, 3, 1) var fault_count: int = 2

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _calibration_view: Node = get_node_or_null(calibration_view_path)


## Round 30 Priority 8: the first system that genuinely RECURS. Registered
## with DayPlan's service re-arm hook: once the calibration is due again
## (DayPlan.SERVICE_INTERVAL_DAYS) and every system has been serviced at
## least once, a new Calibration work order starts with a recorded sensor
## drift whose required-chamber count comes from the day's variant seed
## (stable within the day, different across days). The minigame itself is
## unchanged; completion is still DayPlan's l07.
var _drift_day: int = -1
var _drift_required: int = 0


func _ready() -> void:
	add_to_group(&"r35_equipment")   # SaveGame persists state_dict()/load_dict()
	if _day_plan != null and _day_plan.has_method("register_service_rearm"):
		_day_plan.register_service_rearm(_day_plan.Workday.CALIBRATION, _rearm_for_service)
	_build_gauges()
	_refresh_gauges()
	# Round 46: the instrument's own true calibration status.
	preload("res://scripts/interactables/cal_status_plate.gd").attach(self, &"l07", _day_plan, Vector3(0, 0.27, 0.115))


# ======================================================================
# Round 37 Priority 2: ONE AUTHORITATIVE SENSOR STATE. The six chambers'
# setpoints / readings / velocities, the damping, the coupling matrix and
# the active-chamber count live HERE, on the physical station. The focused
# view (sensor_calibration_view.gd) adopts these very Dictionary objects
# while open (shared references) and writes the damping back every frame;
# with the view closed this station keeps integrating the SAME damped,
# coupled springs, and its six physical dials always show `cal.reading`.
# Opening, closing and reopening therefore show identical values. The
# state is saved (state_dict) and restored exactly.
# A real calibration TASK (a calibration workday) is one persistent
# instance keyed by day + drift seed: never re-rolled on reopen. Outside a
# task (no assignment) an open still starts a fresh practice attempt, as
# before -- written into this same state, so the dials stay truthful.
# ======================================================================
const _VIEW = preload("res://scripts/ui/sensor_calibration_view.gd")
var cal: Dictionary = {}          # {key, setpoint, reading, velocity, damping, coupling, active_count}
var _dials: Array = []            # [{needle: Node3D, lamp: StandardMaterial3D, mark: Node3D}]


## "" when no calibration task is active (non-persistent practice opens).
func calibration_instance_key() -> String:
	if _day_plan == null:
		return ""
	if int(_day_plan.workday) == int(_day_plan.Workday.CALIBRATION):
		return "d%d_s%d" % [int(_day_plan.day_number), service_seed()]
	return ""


func has_calibration_state(key: String) -> bool:
	return key != "" and String(cal.get("key", "")) == key and cal.has("setpoint")


func store_calibration(key: String, setpoint: Dictionary, reading: Dictionary, velocity: Dictionary, damping: float, coupling: Array, active_count: int) -> void:
	cal = {"key": key, "setpoint": setpoint, "reading": reading, "velocity": velocity, "damping": damping, "coupling": coupling, "active_count": active_count}
	_refresh_gauges()


func reading_of(ch: StringName) -> float:
	var r: Dictionary = cal.get("reading", {})
	return float(r.get(ch, _VIEW._TARGETS[ch]))


func _view_owns_state() -> bool:
	return _calibration_view != null and _calibration_view.visible and _calibration_view._station == self


func _process(delta: float) -> void:
	if cal.has("setpoint") and not _view_owns_state() and not cal.get("coupling", []).is_empty():
		_step(minf(delta, _VIEW.MAX_PHYSICS_STEP))
	_refresh_gauges()


## The same damped coupled spring integration as the focused view.
func _step(delta: float) -> void:
	var sp: Dictionary = cal["setpoint"]
	var rd: Dictionary = cal["reading"]
	var vel: Dictionary = cal["velocity"]
	var coupling: Array = cal["coupling"]
	var chs: Array = _VIEW.CHAMBERS
	for i in chs.size():
		var row: Array = coupling[i]
		var target := 0.0
		for j in chs.size():
			target += float(row[j]) * float(sp[chs[j]])
		var ch: StringName = chs[i]
		var accel: float = _VIEW.RESPONSE_STRENGTH * (target - float(rd[ch])) - float(cal["damping"]) * float(vel[ch])
		vel[ch] = float(vel[ch]) + accel * delta
		rd[ch] = float(rd[ch]) + float(vel[ch]) * delta


func _build_gauges() -> void:
	for n in ["GaugeFace", "GaugeNeedle"]:
		var old: Node3D = get_node_or_null(n)
		if old != null:
			old.visible = false   # replaced by the six chamber dials
	var panel := Node3D.new()
	panel.name = "ChamberGauges"
	add_child(panel)
	var face_m := StandardMaterial3D.new()
	face_m.albedo_color = Color(0.88, 0.87, 0.82)
	face_m.roughness = 0.5
	var rim_m := StandardMaterial3D.new()
	rim_m.albedo_color = Color(0.25, 0.27, 0.29)
	rim_m.metallic = 0.7
	var needle_m := StandardMaterial3D.new()
	needle_m.albedo_color = Color(0.85, 0.12, 0.08)
	var band_m := StandardMaterial3D.new()
	band_m.albedo_color = Color(0.15, 0.6, 0.25)
	var tick_m := StandardMaterial3D.new()
	tick_m.albedo_color = Color(0.15, 0.15, 0.15)
	for i in _VIEW.CHAMBERS.size():
		var ch: StringName = _VIEW.CHAMBERS[i]
		var root := Node3D.new()
		root.name = "Gauge_%s" % String(ch).to_upper()
		root.position = Vector3(-0.155 + 0.155 * (i % 3), 0.155 - 0.165 * (i / 3), 0.112)
		panel.add_child(root)
		var rim := CSGCylinder3D.new()
		rim.radius = 0.07
		rim.height = 0.012
		rim.sides = 28
		rim.rotation_degrees.x = 90.0
		rim.material = rim_m
		root.add_child(rim)
		var face := CSGCylinder3D.new()
		face.radius = 0.06
		face.height = 0.004
		face.sides = 28
		face.rotation_degrees.x = 90.0
		face.position.z = 0.006
		face.material = face_m
		root.add_child(face)
		# Scale ticks every 10 units over the same 280-degree sweep.
		for k in 11:
			var t := Node3D.new()
			t.rotation.z = -deg_to_rad(k * 28.0 - 140.0)
			t.position.z = 0.0085
			root.add_child(t)
			var tb := CSGBox3D.new()
			tb.size = Vector3(0.0025, 0.012 if k % 5 == 0 else 0.007, 0.001)
			tb.position.y = 0.05
			tb.material = tick_m
			t.add_child(tb)
		# Target mark (green) at this chamber's real target.
		var mark := Node3D.new()
		mark.rotation.z = -deg_to_rad(_VIEW._TARGETS[ch] / _VIEW.GAUGE_MAX * 280.0 - 140.0)
		mark.position.z = 0.009
		root.add_child(mark)
		var mb := CSGBox3D.new()
		mb.size = Vector3(0.012, 0.016, 0.0015)
		mb.position.y = 0.049
		mb.material = band_m
		mark.add_child(mb)
		var needle := Node3D.new()
		needle.name = "Needle"
		needle.position.z = 0.0105
		root.add_child(needle)
		var nb := CSGBox3D.new()
		nb.size = Vector3(0.004, 0.05, 0.0015)
		nb.position.y = 0.021
		nb.material = needle_m
		needle.add_child(nb)
		var cap := CSGCylinder3D.new()
		cap.radius = 0.006
		cap.height = 0.004
		cap.rotation_degrees.x = 90.0
		cap.position.z = 0.012
		cap.material = rim_m
		root.add_child(cap)
		var lbl := Label3D.new()
		lbl.text = String(ch).to_upper()
		lbl.font_size = 26
		lbl.pixel_size = 0.0009
		lbl.modulate = Color(0.12, 0.12, 0.12)
		lbl.outline_size = 0
		lbl.position = Vector3(0, -0.028, 0.0095)
		root.add_child(lbl)
		var lamp_s := CSGSphere3D.new()
		lamp_s.radius = 0.008
		lamp_s.position = Vector3(0.058, 0.058, 0.004)
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lamp_s.material = lm
		root.add_child(lamp_s)
		_dials.append({"needle": needle, "lamp": lm})


## The physical dials always show the authoritative readings.
func _refresh_gauges() -> void:
	if _dials.is_empty():
		return
	var tol: float = 4.0
	if _calibration_view != null and "_tolerance" in _calibration_view:
		tol = _calibration_view._tolerance
	for i in _VIEW.CHAMBERS.size():
		var ch: StringName = _VIEW.CHAMBERS[i]
		var v: float = clampf(reading_of(ch), _VIEW.GAUGE_MIN - 4.0, _VIEW.GAUGE_MAX + 4.0)
		(_dials[i]["needle"] as Node3D).rotation.z = -deg_to_rad(v / _VIEW.GAUGE_MAX * 280.0 - 140.0)
		var ok: bool = absf(v - _VIEW._TARGETS[ch]) <= tol
		var m: StandardMaterial3D = _dials[i]["lamp"]
		m.albedo_color = Color(0.2, 0.9, 0.3) if ok else Color(1.0, 0.6, 0.1)
		m.emission = m.albedo_color * 0.8


## Needle angle (degrees, view convention) a dial currently shows -- tests.
func dial_value(i: int) -> float:
	var deg: float = -rad_to_deg((_dials[i]["needle"] as Node3D).rotation.z)
	return (deg + 140.0) / 280.0 * _VIEW.GAUGE_MAX


func state_dict() -> Dictionary:
	if not cal.has("setpoint"):
		return {}
	return {"key": cal["key"], "setpoint": _str_keys(cal["setpoint"]), "reading": _str_keys(cal["reading"]), "damping": cal["damping"], "coupling": cal["coupling"], "active_count": cal["active_count"]}


func load_dict(d: Dictionary) -> void:
	if not d.has("setpoint"):
		cal = {}
		_refresh_gauges()
		return
	var sp := {}
	var rd := {}
	var vel := {}
	for ch in _VIEW.CHAMBERS:
		sp[ch] = float(d["setpoint"].get(String(ch), _VIEW._TARGETS[ch]))
		rd[ch] = float(d["reading"].get(String(ch), _VIEW._TARGETS[ch]))
		vel[ch] = 0.0
	cal = {"key": String(d.get("key", "")), "setpoint": sp, "reading": rd, "velocity": vel, "damping": float(d.get("damping", _VIEW.START_DAMPING)), "coupling": Array(d.get("coupling", [])), "active_count": int(d.get("active_count", 0))}
	_refresh_gauges()


static func _str_keys(dd: Dictionary) -> Dictionary:
	var o := {}
	for k in dd:
		o[String(k)] = float(dd[k])
	return o


var _drift_seed: int = 0


func _rearm_for_service(seed: int) -> void:
	_drift_day = _day_plan.day_number
	_drift_required = 1 + int(absi(seed) % 3)
	# Round 31: WHICH chambers drift also comes from the day's seed (the
	# calibration view shuffles its chamber list with it).
	_drift_seed = seed


## Today's drift seed (0 = no recorded drift today).
func service_seed() -> int:
	return _drift_seed if _drift_day == _day_plan.day_number else 0


## Equipment condition (Round 31 Priority 8), from real state only.
func condition() -> StringName:
	if is_complete():
		return &"restored" if _drift_day == _day_plan.day_number else &"nominal"
	if has_recorded_drift() or (_day_plan.workday == _day_plan.Workday.CALIBRATION):
		return &"service_due"
	return &"nominal"


func has_recorded_drift() -> bool:
	return _drift_day == _day_plan.day_number and not is_complete()


func service_required_count() -> int:
	return _drift_required if _drift_day == _day_plan.day_number else 0


func active_fault_count() -> int:
	return clampi(fault_count, 1, 3)


func interact() -> void:
	if _calibration_view == null:
		return
	_calibration_view.open_station(self)


func get_interact_prompt() -> String:
	if _day_plan.is_task_done(&"l07"):
		return "Click: Check Sensor Calibration (Nominal)"
	if has_recorded_drift():
		return "Click: Calibrate Environmental Sensor (drift detected)"
	return "Click: Calibrate Environmental Sensor"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"l07")


## Called by sensor_calibration_view.gd once the reading has stabilized
## inside tolerance for the required duration -- the one and only
## commit point; opening the view, or any amount of unstable adjusting,
## never calls this.
func mark_complete() -> void:
	_day_plan.mark_done(&"l07")
