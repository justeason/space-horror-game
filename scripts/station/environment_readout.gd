extends Node3D
## Round 33 Priority 6: the Control Room ENVIRONMENT READOUT -- a small
## wall panel beside the workstation whose numbers are derived from the
## real equipment state (never decorative random values):
##   CABIN AIRFLOW  filter housing: isolated -> 0 %, cartridge due -> 86 %,
##                  otherwise 100 %
##   FILTER dP      1.9 kPa while a service is due (clogged), 0.7 kPa clean,
##                  "--" while isolated
##   MAIN BUS T-2   11.4 V while the Engineering power fault is open, 24.1 V
##   COOLANT LOOP   from the valve manifold's live flow state
##   SENSOR ARRAY   recorded drift (chambers) or "calibrated"
##   CARGO PORT     the port's own status word
## Updated twice a second; text() is readable by tests.

@export var filter_path: NodePath = ^"../Interactables/FilterHousingStation"
@export var panel_path: NodePath = ^"../Geometry/EngineeringCabinet1"
@export var valve_path: NodePath = ^"../Interactables/ValveRoutingStation"
@export var calib_path: NodePath = ^"../Interactables/SensorCalibrationStation"
@export var port_path: NodePath = ^"../Interactables/CargoPort"
@export var day_plan_path: NodePath = ^"../DayPlan"
@export var env_path: NodePath = ^"../EnvironmentModel"
@export var power_path: NodePath = ^"../Equipment/PowerDistribution"
@export var breaker_path: NodePath = ^"../Equipment/BreakerPanel"

var _label: Label3D
var _t := 0.0


func _ready() -> void:
	var back := CSGBox3D.new()
	back.size = Vector3(0.02, 0.36, 0.56)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.08, 0.09)
	back.material = m
	add_child(back)
	var frame := CSGBox3D.new()
	frame.size = Vector3(0.012, 0.39, 0.59)
	frame.position = Vector3(-0.006, 0, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.32, 0.35)
	fm.metallic = 0.6
	frame.material = fm
	add_child(frame)
	_label = Label3D.new()
	# Label3D anchors LEFT-aligned text at its origin: start at the panel's
	# left edge (world +z, seen from the room).
	_label.position = Vector3(0.012, 0, 0.25)
	_label.rotation_degrees = Vector3(0, 90, 0)
	_label.font_size = 22
	_label.pixel_size = 0.0008
	_label.modulate = Color(0.55, 0.95, 0.75)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# width only applies with autowrap on: a 0.5 m text block, left-aligned
	# inside the 0.56 m panel.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 625
	add_child(_label)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		_update()


func _update() -> void:
	_label.text = text()


func text() -> String:
	var f: Node = get_node_or_null(filter_path)
	var p: Node = get_node_or_null(panel_path)
	var v: Node = get_node_or_null(valve_path)
	var c: Node = get_node_or_null(calib_path)
	var port: Node = get_node_or_null(port_path)
	var dp: Node = get_node_or_null(day_plan_path)
	var lines: Array[String] = ["STATION ENVIRONMENT — LIVE"]
	var env: Node = get_node_or_null(env_path)
	if f != null:
		var cond: StringName = f.condition()
		# Round 35: airflow from the EnvironmentModel (filter x vent x fans).
		var air: int = roundi(env.airflow() * 100.0) if env != null else (0 if f.is_isolated() else (86 if cond == &"service_due" else 100))
		var dpk: String = "--" if f.is_isolated() else ("1.9 kPa  HIGH" if cond == &"service_due" else "0.7 kPa")
		lines.append("CABIN AIRFLOW   %3d %%" % air)
		lines.append("FILTER dP       %s" % dpk)
	if p != null and dp != null:
		var fault: bool = dp.fault_target == &"engineering_power" and not p.is_repaired()
		lines.append("MAIN BUS T-2    %s" % ("11.4 V  LOW" if fault else "24.1 V"))
	if v != null:
		var fl: Dictionary = v.flow_state()
		var word := "NO FLOW"
		if fl["outlet_live"] and fl["drain_live"]:
			word = "OUTLET + BRANCH 3" + ("  LEAK" if v.branch3_is_leak() else "")
		elif fl["outlet_live"]:
			word = "OUTLET OK"
		elif fl["drain_live"]:
			word = "BRANCH 3 ONLY" + ("  LEAK" if v.branch3_is_leak() else "")
		lines.append("COOLANT LOOP    %s" % word)
	if c != null:
		lines.append("SENSOR ARRAY    %s" % (("DRIFT %d CH" % c.service_required_count()) if c.has_recorded_drift() else "CALIBRATED"))
	if port != null:
		lines.append("CARGO PORT      %s" % port.status_word())
	# Round 35: cabin pressure, O2 partial pressure, power bus, lighting.
	if env != null:
		lines.append("CABIN PRESSURE  %.1f kPa%s" % [env.pressure_kpa, "  LOW" if env.pressure_kpa < 100.3 else ""])
		lines.append("O2 PARTIAL      %.1f kPa%s" % [env.o2_kpa, "  LOW" if env.o2_kpa < 20.2 else ""])
	var pw: Node = get_node_or_null(power_path)
	if pw != null:
		lines.append("POWER BUS A     %.1f V%s" % [pw.bus_voltage(), "  OVERLOAD" if pw.is_overloaded() else ("" if pw.balanced() else "  UNBALANCED")])
	var br: Node = get_node_or_null(breaker_path)
	if br != null and not br.tripped_ids().is_empty():
		lines.append("BREAKERS        TRIPPED %s" % ", ".join(br.tripped_ids()))
	return "\n".join(lines)
