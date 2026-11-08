extends StaticBody3D
## Round 38 Priority 11: a PORTABLE INSTRUMENT carried by hand (one-item
## rule; saved ownership like the data module / thermal probe):
##   kind "airflow": AFM-2 vane anemometer -- hold it to a marked
##     measuring point (vent LS-2 outlet, filter housing outlet) and click:
##     reads the REAL airflow there (m/s) from the vent's cleanliness, the
##     LS fan power and the filter state;
##   kind "leak": LD-5 ultrasonic leak detector -- reads CONTINUOUSLY while
##     held: signal = real seal leak x proximity to the faulty seal section
##     (falls off with distance). A strong signal marks that section as
##     found.
## The rack in Storage (tool_rack.gd) docks them; they can be returned
## unused at any time.

@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var item_id: StringName = &"airflow_meter"
var kind: String = "airflow"
var payload: Dictionary = {}       # {"last": {...}, "readings": {...}}
var _carry_system: Node
var _resting_parent: Node
var _resting_transform: Transform3D
var _screen: Label3D


func _ready() -> void:
	add_to_group(&"portable_meter")
	_carry_system = get_node_or_null(carry_system_path)
	_resting_parent = get_parent()
	_resting_transform = transform
	var body := CSGBox3D.new()
	body.size = Vector3(0.07, 0.04, 0.14)
	body.material = _mat(Color(0.18, 0.2, 0.22) if kind == "airflow" else Color(0.2, 0.18, 0.15), 0.4)
	add_child(body)
	var band := CSGBox3D.new()
	band.size = Vector3(0.074, 0.044, 0.04)
	band.position.z = 0.05
	band.material = _mat(Color(0.25, 0.65, 0.85) if kind == "airflow" else Color(0.85, 0.35, 0.15), 0.1)
	add_child(band)
	if kind == "airflow":
		var ring := CSGCylinder3D.new()
		ring.radius = 0.045
		ring.height = 0.03
		ring.rotation_degrees.x = 90.0
		ring.position.z = -0.09
		ring.material = _mat(Color(0.6, 0.62, 0.64), 0.7)
		add_child(ring)
		for k in 4:
			var vane := CSGBox3D.new()
			vane.size = Vector3(0.075, 0.008, 0.004)
			vane.rotation_degrees.z = 45.0 * k
			vane.position.z = -0.09
			vane.material = _mat(Color(0.85, 0.85, 0.8), 0.3)
			add_child(vane)
	else:
		var wand := CSGCylinder3D.new()
		wand.radius = 0.008
		wand.height = 0.14
		wand.rotation_degrees.x = 90.0
		wand.position.z = -0.13
		wand.material = _mat(Color(0.55, 0.57, 0.6), 0.8)
		add_child(wand)
		var tip := CSGSphere3D.new()
		tip.radius = 0.014
		tip.position.z = -0.2
		tip.material = _mat(Color(0.1, 0.1, 0.1), 0.3)
		add_child(tip)
	_screen = Label3D.new()
	_screen.position = Vector3(0, 0.0215, 0.0)
	_screen.rotation_degrees.x = -90.0
	_screen.font_size = 12
	_screen.pixel_size = 0.0006
	_screen.modulate = Color(0.55, 0.95, 0.75)
	add_child(_screen)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.09, 0.07, 0.24)
	cs.shape = bs
	add_child(cs)
	show_text("AFM-2\nREADY" if kind == "airflow" else "LD-5\nREADY")


func _mat(c: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.55
	return m


func show_text(t: String) -> void:
	if _screen != null:
		_screen.text = t


## Shows the last stored reading (after a load).
func refresh() -> void:
	var last: Dictionary = payload.get("last", {})
	if kind == "airflow" and not last.is_empty():
		show_text("AFM-2\n%.2f m/s" % float(last.get("ms", 0.0)))


func display_name() -> String:
	return "Airflow Meter" if kind == "airflow" else "Leak Detector"


func get_display_name() -> String:
	return display_name()


func interact() -> void:
	if _carry_system == null or _carry_system.is_carrying():
		return
	_carry_system.pick_up(self)


func get_interact_prompt() -> String:
	if _carry_system != null and _carry_system.is_carrying():
		return ""
	return "Click: Take %s" % display_name().to_lower()


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
