extends "res://scripts/station/equipment_base.gd"
## Round 38 Priority 11: the INSTRUMENT RACK (Storage, east wall) holding
## the AFM-2 airflow meter and the LD-5 leak detector, plus the airflow
## TEST PORTS (vent LS-2 outlet, filter housing outlet) and the leak
## detector's live reading. Each tool has its own docking slot (an item
## dock: SaveGame owner kind "dataport", the rack's name); either can be
## returned unused at any time.

const Meter = preload("res://scripts/interactables/portable_meter.gd")
@export var carry_system_path: NodePath = ^"../../Player/CarrySystem"
@export var vent_path: NodePath = ^"../VentGrille"
@export var power_path: NodePath = ^"../PowerDistribution"
@export var seal_path: NodePath = ^"../HatchSeal"
@export var filter_path: NodePath = ^"../../Interactables/FilterHousingStation"
## Airflow test ports: id -> [world position, yaw facing, label].
const PORTS := {
	&"air_vent": [Vector3(-4.33, 0.74, 11.3), 90.0, "AIRFLOW TEST PORT · VENT LS-2"],
	&"air_filter": [Vector3(-1.64, 0.8, 10.9), -90.0, "AIRFLOW TEST PORT · FILTER OUT"],
}
const NOMINAL_MS := {&"air_vent": 2.4, &"air_filter": 3.1}

var slots: Dictionary = {}         # item_id -> Node3D slot
var last_reading: Dictionary = {}  # port -> m/s (this session; also on the meter)
var leak_signal: float = 0.0
var _beep_t: float = 0.0


func _ready() -> void:
	add_to_group(&"item_dock")
	add_to_group(&"tool_rack")
	_base_ready(&"")
	box(Vector3(0.5, 0.42, 0.05), Vector3(0, 0, -0.025), Color(0.2, 0.22, 0.25))
	box(Vector3(0.52, 0.035, 0.07), Vector3(0, 0.22, -0.01), Color(0.25, 0.75, 0.85))
	label("INSTRUMENT RACK", Vector3(0, 0.17, 0.004), 15)
	var cs: Node = get_node_or_null(carry_system_path)
	var ml: Node = get_node_or_null(message_label_path)
	for i in 2:
		var id: StringName = [&"airflow_meter", &"leak_detector"][i]
		var x: float = -0.12 + 0.24 * i
		box(Vector3(0.12, 0.05, 0.06), Vector3(x, -0.12, 0.02), Color(0.06, 0.07, 0.08))
		label(["AFM-2 AIRFLOW", "LD-5 LEAK"][i], Vector3(x, -0.17, 0.004), 10, Color(0.75, 0.8, 0.8))
		var slot := Node3D.new()
		slot.name = "Slot_%s" % String(id)
		slot.position = Vector3(x, -0.02, 0.06)
		slot.rotation_degrees = Vector3(-80.0, 0.0, 0.0)
		add_child(slot)
		slots[id] = slot
		part(StringName("dock_%d" % i), Vector3(0.16, 0.3, 0.08), Vector3(x, -0.02, 0.04))
		var m := StaticBody3D.new()
		m.set_script(Meter)
		m.name = "AirflowMeter" if i == 0 else "LeakDetector"
		m.kind = "airflow" if i == 0 else "leak"
		m.item_id = id
		m.carry_system_path = cs.get_path() if cs != null else NodePath()
		m.message_label_path = ml.get_path() if ml != null else NodePath()
		slot.add_child(m)
		seat(m)
	_build_ports.call_deferred()


func _build_ports() -> void:
	for id in PORTS:
		var p := Node3D.new()
		p.name = "TestPort_%s" % String(id)
		get_parent().add_child(p)
		p.global_position = PORTS[id][0]
		p.rotation_degrees.y = PORTS[id][1]
		var ring := CSGCylinder3D.new()
		ring.radius = 0.05
		ring.height = 0.03
		ring.rotation_degrees.x = 90.0
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.25, 0.75, 0.85)
		rm.emission_enabled = true
		rm.emission = Color(0.1, 0.35, 0.4)
		ring.material = rm
		p.add_child(ring)
		label(PORTS[id][2], Vector3(0, 0.08, 0.0), 10, Color(0.8, 0.95, 0.95), p)
		preload("res://scripts/interactables/click_part.gd").make(self, id, Vector3(0.16, 0.16, 0.08), p, Vector3(0, 0, 0.02))


# ------------------------------------------------------------- docking
func seat(item: Node3D) -> void:
	var slot: Node3D = slots.get(item.item_id, null)
	if slot == null:
		return
	if item.has_method("set_rest_global"):
		item.set_rest_global(slot.global_transform, slot)
	item.return_to_rest()
	item.transform = Transform3D()
	item.visible = true
	var c: Node = item.get_node_or_null("Collision")
	if c != null:
		c.disabled = false


func docked(id: StringName) -> Node3D:
	var slot: Node3D = slots.get(id, null)
	if slot == null:
		return null
	for c in slot.get_children():
		if "item_id" in c and c.item_id == id:
			return c
	return null


func tool_anywhere(id: StringName) -> Node3D:
	for n in get_tree().get_nodes_in_group(&"portable_meter"):
		if n.item_id == id and not n.is_queued_for_deletion():
			return n
	return null


func _held() -> Node3D:
	var cs: Node = get_node_or_null(carry_system_path)
	if cs != null and cs.is_carrying() and cs._carried_item != null and cs._carried_item.is_in_group(&"portable_meter"):
		return cs._carried_item
	return null


func accepts_item(item: Node) -> bool:
	return item != null and "item_id" in item and slots.has(item.item_id) and docked(item.item_id) == null


func stow(item: Node3D) -> bool:
	if not accepts_item(item):
		return false
	seat(item)
	sfx(&"insert")
	say("%s returned to the rack." % item.display_name())
	return true


func part_accepts_item(id: StringName, item: Node) -> bool:
	return String(id).begins_with("dock") and accepts_item(item)


func part_stow(id: StringName, item: Node3D) -> bool:
	return String(id).begins_with("dock") and stow(item)


func part_stow_hint(id: StringName, item: Node) -> String:
	return "Return %s to rack" % item.display_name().to_lower() if String(id).begins_with("dock") and item != null and item.has_method("display_name") else ""


# --------------------------------------------------------- measurement
## The REAL airflow at a test port (m/s).
func airflow_at(port: StringName) -> float:
	var f: float = 1.0
	var fh: Node = get_node_or_null(filter_path)
	if fh != null and fh.has_method("is_isolated"):
		if fh.is_isolated():
			f = 0.0
		elif fh.condition() == &"service_due":
			f = 0.86
	var v: Node = get_node_or_null(vent_path)
	var p: Node = get_node_or_null(power_path)
	var fan: float = p.fan_factor() if p != null and p.has_method("fan_factor") else 1.0
	var eff: float = v.efficiency() if v != null and v.has_method("efficiency") else 1.0
	if port == &"air_vent":
		# The grille's own restriction shows up most at its outlet.
		return NOMINAL_MS[port] * fan * f * (1.0 - (1.0 - eff) * 2.0)
	return NOMINAL_MS[port] * fan * f * eff


func on_part(id: StringName) -> void:
	var s := String(id)
	if s.begins_with("dock"):
		var cs: Node = get_node_or_null(carry_system_path)
		var held: Node3D = _held()
		if held != null and accepts_item(held):
			var item: Node3D = cs.take_carried_item_if_matches(held.item_id)
			if item != null:
				stow(item)
		return
	if PORTS.has(id):
		var m: Node3D = _held()
		if m == null or m.kind != "airflow":
			say("Airflow meter AFM-2 needed (instrument rack, Storage).")
			sfx(&"click")
			return
		var ms: float = maxf(airflow_at(id), 0.0)
		last_reading[id] = ms
		var pct: int = roundi(ms / NOMINAL_MS[id] * 100.0)
		m.payload["last"] = {"port": String(id), "ms": snappedf(ms, 0.01)}
		var r: Dictionary = m.payload.get("readings", {})
		r[String(id)] = snappedf(ms, 0.01)
		m.payload["readings"] = r
		m.show_text("AFM-2\n%.2f m/s\n%d %%" % [ms, pct])
		sfx(&"success" if pct >= 90 else &"warn")
		say("Airflow at %s: %.2f m/s (%d %% of nominal)%s." % [PORTS[id][2].get_slice("· ", 1), ms, pct, "" if pct >= 90 else " — restricted"])
		if id == &"air_vent":
			var v: Node = get_node_or_null(vent_path)
			if v != null and "airflow_checked" in v:
				v.airflow_checked = true   # the vent order's flow check
		if _dp != null:
			_dp.log_event("Airflow measured %s %.2f m/s" % [String(id).trim_prefix("air_"), ms])


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s.begins_with("dock"):
		var cs: Node = get_node_or_null(carry_system_path)
		return "" if cs != null and cs.is_carrying() else ("Empty instrument slot" if docked([&"airflow_meter", &"leak_detector"][int(s.substr(5))]) == null else "")
	if PORTS.has(id):
		var m: Node3D = _held()
		return "Click: Measure airflow" if m != null and m.kind == "airflow" else "Airflow test port (meter needed)"
	return ""


## Leak signal at a world point: real leak x proximity to faulty sections.
func leak_signal_at(p: Vector3) -> Dictionary:
	var hs: Node3D = get_node_or_null(seal_path)
	var best := 0.0
	var where := -1
	if hs == null:
		return {"signal": 0.0, "section": -1}
	for i in 4:
		if String(hs.faults[i]) == "":
			continue
		var c: Vector3 = hs.global_transform * hs.POS[i]
		var d: float = c.distance_to(p)
		var s: float = clampf(hs.leak_kpa() / 1.2, 0.5, 1.0) / (1.0 + pow(d / 0.3, 2.0))
		if s > best:
			best = s
			where = i
	return {"signal": best, "section": where}


func _process(delta: float) -> void:
	var m: Node3D = _held()
	if m == null or m.kind != "leak":
		leak_signal = 0.0
		return
	var r: Dictionary = leak_signal_at(m.global_position)
	leak_signal = float(r["signal"])
	m.show_text("LD-5\n%s\n%d dB" % ["#".repeat(clampi(roundi(leak_signal * 8.0), 0, 8)) + ".".repeat(8 - clampi(roundi(leak_signal * 8.0), 0, 8)), roundi(20.0 + leak_signal * 60.0)])
	_beep_t -= delta
	if leak_signal > 0.15 and _beep_t <= 0.0:
		_beep_t = lerpf(0.9, 0.12, leak_signal)
		sfx(&"click")
	if leak_signal > 0.6 and int(r["section"]) >= 0:
		var hs: Node = get_node_or_null(seal_path)
		var i: int = int(r["section"])
		if hs != null and not hs.inspected[i]:
			hs.inspected[i] = true
			hs._refresh()
			say("LD-5: leak at the %s seal section." % hs.NAMES[i])
			if _dp != null:
				_dp.log_event("Leak located: %s seal" % hs.NAMES[i])
