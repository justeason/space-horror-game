extends Node3D
## Round 35: shared helpers for the physical maintenance equipment built in
## code (boxes, labels, lamps, clickable parts, sounds, HUD messages) and
## the DayPlan work-order hookup. Each subclass owns its own authoritative
## state; DayPlan only asks it order_done()/order_next()/order_progress().

const ClickPart = preload("res://scripts/interactables/click_part.gd")
const Hud = preload("res://scripts/ui/hud_message.gd")
@export var day_plan_path: NodePath = ^"../../DayPlan"
@export var sfx_path: NodePath = ^"../../Player/HUD/MechanicalSfx"
@export var message_label_path: NodePath = ^"../../Player/HUD/TaskMessageLabel"
var _dp: Node
var _sfx: Node


func _base_ready(order_type: StringName) -> void:
	add_to_group(&"r35_equipment")   # SaveGame persists state_dict()/load_dict()
	_dp = get_node_or_null(day_plan_path)
	_sfx = get_node_or_null(sfx_path)
	if _dp != null and order_type != &"" and _dp.has_method("register_order_equipment"):
		_dp.register_order_equipment(order_type, self)


func box(size: Vector3, pos: Vector3, color: Color, parent: Node3D = null, metallic: float = 0.3) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = 0.6
	b.material = m
	(parent if parent != null else self).add_child(b)
	return b


func label(text: String, pos: Vector3, size: int = 18, color: Color = Color(0.9, 0.9, 0.85), parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.0009
	l.modulate = color
	l.outline_size = 4
	(parent if parent != null else self).add_child(l)
	return l


func lamp(pos: Vector3, parent: Node3D = null, r: float = 0.012) -> StandardMaterial3D:
	var s := CSGSphere3D.new()
	s.radius = r
	s.position = pos
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission_energy_multiplier = 2.0
	s.material = m
	(parent if parent != null else self).add_child(s)
	return m


static func set_lamp(m: StandardMaterial3D, c: Color, on: bool = true) -> void:
	m.albedo_color = c * (0.6 if on else 0.15)
	m.emission = c if on else Color(0, 0, 0)


func part(id: StringName, size: Vector3, pos: Vector3, parent: Node3D = null) -> StaticBody3D:
	return ClickPart.make(self, id, size, parent if parent != null else self, pos)


func sfx(kind: StringName) -> void:
	if _sfx != null and _sfx.has_method("play_kind"):
		_sfx.play_kind(kind)


func say(text: String, seconds: float = 3.0) -> void:
	var ml: Label = get_node_or_null(message_label_path) as Label
	Hud.show(ml, get_instance_id(), text, seconds)


func difficulty() -> int:
	return preload("res://scripts/station/game_settings.gd").get_difficulty()


## Round 36: tells the station assistant about a real event (interlock,
## wrong part, ...). No-op when there is no assistant.
func ai_event(key: StringName) -> void:
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(&"station_ai"):
			n.event(key)
