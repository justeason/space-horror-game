extends StaticBody3D
## Round 35 Priority 9: a removable DIAGNOSTIC DATA MODULE -- a rugged,
## handled cartridge (not a consumer USB stick). A real carried item (the
## one-item rule, ownership tracked by save/load). Its PAYLOAD is a
## snapshot of real equipment readings taken at the Engineering capture
## port, plus the station-state signature at capture time (stale detection).

@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var item_id: StringName = &"data_module"
var payload: Dictionary = {}
var _carry_system: Node
var _resting_parent: Node
var _resting_transform: Transform3D
var _screen: Label3D


func _ready() -> void:
	add_to_group(&"data_module")
	_carry_system = get_node_or_null(carry_system_path)
	_resting_parent = get_parent()
	_resting_transform = transform
	var body := CSGBox3D.new()
	body.size = Vector3(0.09, 0.05, 0.16)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.28, 0.3)
	m.metallic = 0.6
	body.material = m
	add_child(body)
	var grip := CSGBox3D.new()
	grip.size = Vector3(0.07, 0.03, 0.03)
	grip.position = Vector3(0, 0.0, 0.09)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.55, 0.1)
	grip.material = gm
	add_child(grip)
	var pins := CSGBox3D.new()
	pins.size = Vector3(0.06, 0.012, 0.012)
	pins.position = Vector3(0, 0, -0.085)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.8, 0.7, 0.3)
	pm.metallic = 0.9
	pins.material = pm
	add_child(pins)
	_screen = Label3D.new()
	_screen.position = Vector3(0, 0.027, 0.0)
	_screen.rotation_degrees.x = -90.0
	_screen.font_size = 14
	_screen.pixel_size = 0.0008
	_screen.modulate = Color(0.55, 0.95, 0.75)
	add_child(_screen)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.1, 0.06, 0.2)
	cs.shape = bs
	add_child(cs)
	refresh()


func refresh() -> void:
	if _screen != null:
		var st: String = data_state() if is_inside_tree() else ("empty" if payload.is_empty() else "data")
		var d: int = int(payload.get("day", 0))
		var word: String = "EMPTY"
		match st:
			"stale": word = "STALE D%d" % d
			"uploaded": word = "SENT D%d" % d
			"ready", "data": word = "DATA D%d" % d
		_screen.text = "DM-7\n" + word


func interact() -> void:
	if _carry_system == null or _carry_system.is_carrying():
		return
	# Round 36: the module sits in the port's SLOT node, so the port is the
	# grandparent (the old get_parent() check never reached it, and the
	# module could be pulled out mid-transfer).
	var port: Node = _port()
	if port != null and port.has_method("module_removed"):
		if not port.module_removed(self):
			return
	_carry_system.pick_up(self)


func _port() -> Node:
	var n: Node = get_parent()
	for i in 3:
		if n == null:
			return null
		if n.has_method("module_removed"):
			return n
		n = n.get_parent()
	return null


## Round 36: "empty" | "ready" (valid for the open request) | "stale" (the
## station changed since capture, or captured before today's request) |
## "uploaded" | "data" (holds data, no transfer requested).
func data_state() -> String:
	if payload.is_empty():
		return "empty"
	for p in get_tree().get_nodes_in_group(&"data_port"):
		if p.role == "upload":
			return p.payload_state(payload)
	return "data"


const _STATE_WORDS := {"empty": "empty", "ready": "data ready for upload", "stale": "STALE - recapture required", "uploaded": "uploaded", "data": "holds data"}


func get_interact_prompt() -> String:
	if _carry_system != null and _carry_system.is_carrying():
		return ""
	return "Click: Take data module (%s)" % _STATE_WORDS.get(data_state(), "data")


func get_display_name() -> String:
	return "Data Module"


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
