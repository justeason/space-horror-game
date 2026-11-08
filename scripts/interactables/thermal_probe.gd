extends StaticBody3D
## Round 36 Priority 7: PORTABLE THERMAL PROBE TP-3 -- a handheld contact
## thermometer (rugged body, sensing tip, small readout). A real carried
## item (one-item rule, save/load ownership like the data module). It lives
## in its charging/data dock in the Control Room (ThermalSurvey owns the
## dock); in Engineering it measures the power terminal block TB-A. Its
## memory (`payload.readings`: point -> {temp, sig, day}) is uploaded when
## it is docked again.

@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var item_id: StringName = &"thermal_probe"
var payload: Dictionary = {}       # {"readings": {"0": {...}, ...}}
var _carry_system: Node
var _resting_parent: Node
var _resting_transform: Transform3D
var _screen: Label3D


func _ready() -> void:
	add_to_group(&"thermal_probe")
	_carry_system = get_node_or_null(carry_system_path)
	_resting_parent = get_parent()
	_resting_transform = transform
	# Body along local -Z (the sensing tip points forward, away from the hand).
	var body := CSGBox3D.new()
	body.size = Vector3(0.05, 0.035, 0.13)
	body.material = _mat(Color(0.2, 0.22, 0.24), 0.4)
	add_child(body)
	var grip := CSGBox3D.new()
	grip.size = Vector3(0.054, 0.04, 0.06)
	grip.position = Vector3(0, -0.002, 0.045)
	grip.material = _mat(Color(0.85, 0.55, 0.1), 0.1)
	add_child(grip)
	var nose := CSGCylinder3D.new()
	nose.radius = 0.012
	nose.height = 0.05
	nose.rotation_degrees.x = 90.0
	nose.position = Vector3(0, 0, -0.09)
	nose.material = _mat(Color(0.55, 0.57, 0.6), 0.8)
	add_child(nose)
	var tip := CSGCylinder3D.new()
	tip.radius = 0.004
	tip.height = 0.035
	tip.rotation_degrees.x = 90.0
	tip.position = Vector3(0, 0, -0.13)
	tip.material = _mat(Color(0.8, 0.6, 0.35), 0.9)
	add_child(tip)
	var bezel := CSGBox3D.new()
	bezel.size = Vector3(0.04, 0.004, 0.034)
	bezel.position = Vector3(0, 0.0185, -0.02)
	bezel.material = _mat(Color(0.04, 0.05, 0.05), 0.2)
	add_child(bezel)
	_screen = Label3D.new()
	_screen.position = Vector3(0, 0.021, -0.02)
	_screen.rotation_degrees.x = -90.0
	_screen.font_size = 12
	_screen.pixel_size = 0.0006
	_screen.modulate = Color(0.95, 0.7, 0.35)
	add_child(_screen)
	var label := Label3D.new()
	label.text = "TP-3"
	label.position = Vector3(0.0255, 0.0, 0.0)
	label.rotation_degrees.y = 90.0
	label.font_size = 12
	label.pixel_size = 0.0007
	add_child(label)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.07, 0.06, 0.2)
	cs.shape = bs
	add_child(cs)
	refresh()


func _mat(c: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.55
	return m


func readings() -> Dictionary:
	return payload.get("readings", {})


func set_reading(point: int, rec: Dictionary) -> void:
	var r: Dictionary = readings().duplicate(true)
	r[str(point)] = rec
	payload["readings"] = r
	payload["last"] = point
	refresh()


func clear_readings() -> void:
	payload = {}
	refresh()


func refresh() -> void:
	if _screen == null:
		return
	var r: Dictionary = readings()
	if r.is_empty():
		_screen.text = "TP-3\n-- °C"
	else:
		var last: String = str(payload.get("last", r.keys()[0]))
		var rec: Dictionary = r.get(last, {})
		_screen.text = "A%d %d°C\n%d/3 pts" % [int(last) + 1, roundi(float(rec.get("temp", 0.0))), r.size()]


func interact() -> void:
	if _carry_system == null or _carry_system.is_carrying():
		return
	_carry_system.pick_up(self)


func get_interact_prompt() -> String:
	if _carry_system != null and _carry_system.is_carrying():
		return ""
	var n: int = readings().size()
	return "Click: Take thermal probe TP-3 (%s)" % ("no readings" if n == 0 else "%d reading%s stored" % [n, "" if n == 1 else "s"])


func get_display_name() -> String:
	return "Thermal Probe"


## Held like a tool: tip forward, a little lower and inboard.
func held_offset() -> Vector3:
	return Vector3(0.0, 0.02, -0.04)


func set_rest_global(global_xf: Transform3D, parent: Node = null) -> void:
	if parent != null:
		_resting_parent = parent
	_resting_transform = (_resting_parent as Node3D).global_transform.affine_inverse() * global_xf if _resting_parent is Node3D else global_xf


func return_to_rest() -> void:
	reparent(_resting_parent, false)
	transform = _resting_transform


func place_in_world(world_transform: Transform3D) -> void:
	var inter: Node = get_tree().current_scene.get_node_or_null("Interactables") if get_tree().current_scene != null else null
	reparent(inter if inter != null else _resting_parent, false)
	global_transform = world_transform
	_resting_parent = get_parent()
	_resting_transform = transform
