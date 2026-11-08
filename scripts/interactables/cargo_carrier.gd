extends StaticBody3D
## Round 33 Priority 5: the removable CARGO CARRIER -- a shallow sealed
## parts tray that lives in the airlock cargo port. A shipment is packed
## INTO the docked carrier (its parts sit in the tray's own cradles), so a
## whole delivery can be lifted out and carried to Storage as ONE item
## (the one-item hand rule still holds: the carrier is the item). At an
## open reserve crate or cabinet, Space unloads every part that has a free
## compatible slot -- each through that container's own stow(), so stock
## changes exactly at the physical transfer. Parts that do not fit stay in
## the tray. The empty carrier is carried back and docked in the port (Space
## at the open port) for the next shipment. Parts can still be taken out
## one by one while the carrier is docked.
##
## Parts in the carrier are "in transit": counted by DayPlan's cargo needs
## and every audit, owned by exactly one place (the carrier), never stock.

@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var item_id: StringName = &"cargo_carrier"

const W := 0.46
const D := 0.58
const H := 0.035
## Carrier-local cradle positions, same layout and types as the port's own
## floor slots (3 filters at the back, 2 + 2 cables in front).
const CRADLES := [
	[&"filter_cartridge", Vector3(-0.14, 0.012 + 0.093, -0.18)],
	[&"filter_cartridge", Vector3(-0.14, 0.012 + 0.093, 0.0)],
	[&"filter_cartridge", Vector3(-0.14, 0.012 + 0.093, 0.18)],
	[&"wire_control_16ga", Vector3(0.11, 0.012 + 0.0096, -0.22)],
	[&"wire_control_16ga", Vector3(0.11, 0.012 + 0.0096, -0.075)],
	[&"wire_signal_22ga", Vector3(0.11, 0.012 + 0.0096, 0.075)],
	[&"wire_signal_22ga", Vector3(0.11, 0.012 + 0.0096, 0.22)],
]

var _carry_system: Node = null
var _resting_parent: Node
var _resting_transform: Transform3D
var _parts: Array = []            # parts currently in the tray
var _cradle_of: Dictionary = {}   # part -> cradle index
var _docked_in: Node = null       # the cargo port while docked


func _ready() -> void:
	add_to_group(&"supply_carrier")
	_carry_system = get_node_or_null(carry_system_path)
	_resting_parent = get_parent()
	_resting_transform = transform
	_build()


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.36, 0.4)
	mat.metallic = 0.5
	mat.roughness = 0.5
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.85, 0.55, 0.1)
	var base := CSGBox3D.new()
	base.name = "Base"
	base.size = Vector3(W, 0.012, D)
	base.position = Vector3(0, 0.006, 0)
	base.material = mat
	add_child(base)
	for side in [[Vector3(0, H * 0.5, D * 0.5), Vector3(W, H, 0.01)], [Vector3(0, H * 0.5, -D * 0.5), Vector3(W, H, 0.01)],
			[Vector3(W * 0.5, H * 0.5, 0), Vector3(0.01, H, D)], [Vector3(-W * 0.5, H * 0.5, 0), Vector3(0.01, H, D)]]:
		var b := CSGBox3D.new()
		b.size = side[1]
		b.position = side[0]
		b.material = mat
		add_child(b)
	# Front grab handle (tunnel side) with a hazard-orange band.
	var handle := CSGBox3D.new()
	handle.name = "Handle"
	handle.size = Vector3(0.02, 0.02, 0.22)
	handle.position = Vector3(W * 0.5 + 0.025, H + 0.01, 0)
	handle.material = stripe
	add_child(handle)
	var tag := Label3D.new()
	tag.text = "PARTS CARRIER"
	tag.font_size = 18
	tag.pixel_size = 0.001
	tag.position = Vector3(W * 0.5 + 0.007, H * 0.5, 0)
	tag.rotation_degrees = Vector3(0, 90, 0)
	tag.modulate = Color(0.9, 0.9, 0.85)
	add_child(tag)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(W + 0.06, H + 0.01, D)
	cs.shape = bs
	cs.position = Vector3(0.015, (H + 0.01) * 0.5, 0)
	add_child(cs)


# ----------------------------------------------------------- carry protocol
func interact() -> void:
	if _carry_system == null or _carry_system.is_carrying():
		return
	if _docked_in != null and _docked_in.has_method("carrier_can_leave") and not _docked_in.carrier_can_leave():
		_say("Release the cargo restraint first.")
		return
	if _carry_system.pick_up(self):
		_say("Picked up: Parts Carrier (%d part%s). Unload it at the Storage reserve crate (Space)." % [_parts.size(), "" if _parts.size() == 1 else "s"])


func get_interact_prompt() -> String:
	if _carry_system != null and _carry_system.is_carrying():
		return ""
	return "Click: Pick Up Parts Carrier (%d part%s)" % [_parts.size(), "" if _parts.size() == 1 else "s"]


func get_display_name() -> String:
	return "Parts Carrier"


func is_carrier() -> bool:
	return true


## Held low in front of the body, like a tray.
func held_offset() -> Vector3:
	return Vector3(0.0, -0.32, -0.42)


func set_rest_global(global_xf: Transform3D, parent: Node = null) -> void:
	if parent != null:
		_resting_parent = parent
	_resting_transform = _resting_parent.global_transform.affine_inverse() * global_xf if _resting_parent is Node3D else global_xf


func return_to_rest() -> void:
	reparent(_resting_parent, false)
	transform = _resting_transform


func place_in_world(world_transform: Transform3D) -> void:
	_undock()
	reparent(get_tree().current_scene.get_node("Interactables") if get_tree().current_scene != null else _resting_parent, false)
	global_transform = world_transform
	_resting_parent = get_parent()
	_resting_transform = transform


# ----------------------------------------------------------------- contents
func parts() -> Array:
	_parts = _parts.filter(func(p): return is_instance_valid(p) and p.get_parent() == self)
	return _parts.duplicate()


func part_count(id: StringName = &"") -> int:
	var n := 0
	for p in parts():
		if id == &"" or p.item_id == id:
			n += 1
	return n


func contains(p: Node) -> bool:
	return parts().has(p)


func cradle_index_of(p: Node) -> int:
	return int(_cradle_of.get(p, -1)) if contains(p) else -1


func free_cradle(id: StringName) -> int:
	var used := {}
	for p in parts():
		used[_cradle_of[p]] = true
	for i in CRADLES.size():
		if CRADLES[i][0] == id and not used.has(i):
			return i
	return -1


## Packs `p` into cradle `idx` (a shipment arriving, or a save restore).
func put(p: Node3D, idx: int) -> void:
	if p.get_parent() != self:
		if p.get_parent() != null:
			p.reparent(self, false)
		else:
			add_child(p)
	p.transform = Transform3D(Basis(), CRADLES[idx][1])
	if p.has_method("set_rest_global"):
		p.set_rest_global(p.global_transform, self)
	if not _parts.has(p):
		_parts.append(p)
	_cradle_of[p] = idx
	_gate_part(p)


## Parts ride along (not individually clickable) unless the carrier is
## docked in the open port.
func _gate_part(p: Node) -> void:
	var c: Node = p.get_node_or_null("Collision")
	if c != null:
		c.disabled = not (_docked_in != null and _docked_in.carrier_parts_clickable())


func regate() -> void:
	for p in parts():
		_gate_part(p)


## A part taken out by hand leaves the tray.
func release_part(p: Node) -> void:
	_parts.erase(p)
	_cradle_of.erase(p)


## Space at an open container while holding the carrier: every part with a
## free compatible slot goes in through the container's own stow().
func unload_into(target: Node) -> int:
	var moved := 0
	for p in parts():
		var c: Node = p.get_node_or_null("Collision")
		if c != null:
			c.disabled = false
		if target.accepts_item(p):
			release_part(p)
			target.stow(p)
			moved += 1
		else:
			_gate_part(p)
	return moved


func can_unload_into(target: Node) -> bool:
	for p in parts():
		var c: Node = p.get_node_or_null("Collision")
		var was: bool = c != null and c.disabled
		if c != null:
			c.disabled = false
		var ok: bool = target.accepts_item(p)
		if c != null:
			c.disabled = was
		if ok:
			return true
	return false


# ---------------------------------------------------------------- docking
func dock(port: Node, xf: Transform3D) -> void:
	_docked_in = port
	set_rest_global(xf, port)
	return_to_rest()
	regate()


func _undock() -> void:
	_docked_in = null
	regate()


func is_docked() -> bool:
	return _docked_in != null and get_parent() == _docked_in


func _claimed_by_hand() -> void:
	_undock()


func _say(t: String) -> void:
	var ml: Label = get_node_or_null(message_label_path)
	if ml == null:
		return
	preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), t, 3.0)
