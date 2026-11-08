extends StaticBody3D
## Round 31 Priority 2: the Storage RESERVE supply crate.
##
## Shelf stock (storage_cabinet.gd) is finite. Restocking is a real
## transfer: this secured crate holds a separate reserve of PHYSICAL parts
## (real filter_cartridge / wire_component instances, created once at
## load -- never re-created on open). Open the lid, pick a part up, carry
## it to the cabinet that stocks that type and stow it (Space): the
## cabinet adopts it into a free slot, so shelf stock goes up by one
## exactly when reserve stock goes down by one. Nothing is conjured.
##
## Future cargo deliveries would call deliver(item_scene, count) to add
## real parts to the reserve (documented in MILESTONE1_DESIGN.md, Round 31).

@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var sfx_path: NodePath
@export var reserve_filters: int = 2
@export var reserve_wires: int = 3
@export var reserve_signal: int = 2
@export var lid_open_degrees: float = -105.0
@export var open_duration: float = 0.45

const _FILTER_SCENE := preload("res://scenes/interactables/filter_cartridge.tscn")
const _WIRE_SCENE := preload("res://scenes/interactables/wire_component.tscn")
const SIZE := Vector3(0.62, 0.34, 0.46)
const WALL := 0.02

var _items: Array = []
var _slots: Dictionary = {}          # item -> global slot position
var _slots_def: Array = []           # [type, crate-local position]
var _open := false
var _gate_open := false
var _tween: Tween
var _hinge: Node3D
var _lid: CSGBox3D
var _label: Label3D
var _shape: CollisionShape3D
var _last_counts: String = ""
@onready var _sfx: Node = get_node_or_null(sfx_path)


func _ready() -> void:
	add_to_group(&"supply_reserve")
	_build_shell()
	var cs: Node = get_node_or_null(carry_system_path)
	var ml: Node = get_node_or_null(message_label_path)
	# Reserve layout: filters standing in the left half, wires flat in the
	# right half (crate-local, origin at the base centre).
	# Round 32: typed reserve SLOTS (capacity), so delivered cargo can be
	# transferred in: 4 filters (2x2, left bay), 3 power harnesses (right
	# bay), 3 shielded signal cables (on the divider above them).
	for x in [-0.2, -0.03]:
		for z in [-0.11, 0.11]:
			_slots_def.append([&"filter_cartridge", Vector3(x, WALL + 0.093, z)])
	for z in [-0.14, 0.0, 0.14]:
		_slots_def.append([&"wire_control_16ga", Vector3(0.17, WALL + 0.011, z)])
	for z in [-0.14, 0.0, 0.14]:
		_slots_def.append([&"wire_signal_22ga", Vector3(0.17, WALL + 0.078 + 0.0096, z)])
	var counts := {&"filter_cartridge": reserve_filters, &"wire_control_16ga": reserve_wires, &"wire_signal_22ga": reserve_signal}
	var made := {}
	for sd in _slots_def:
		var t: StringName = sd[0]
		if made.get(t, 0) >= counts.get(t, 0):
			continue
		made[t] = made.get(t, 0) + 1
		var part: Node3D = (_FILTER_SCENE if t == &"filter_cartridge" else _WIRE_SCENE).instantiate()
		if t == &"wire_signal_22ga":
			part.item_id = t
			part.cable_type = "signal"
		var base: String = {&"filter_cartridge": "ReserveFilter", &"wire_control_16ga": "ReserveWire", &"wire_signal_22ga": "ReserveSignal"}[t]
		_add_existing(part, sd[1], cs, ml, "%s%d" % [base, made[t]])
	_apply_gating()
	_refresh_label()


func _add_part(scene: PackedScene, local: Vector3, cs: Node, ml: Node, n: String) -> void:
	_add_existing(scene.instantiate(), local, cs, ml, n)


func _add_existing(part: Node3D, local: Vector3, cs: Node, ml: Node, n: String) -> void:
	part.name = n
	if cs != null:
		part.carry_system_path = cs.get_path()
	if ml != null:
		part.message_label_path = ml.get_path()
	part.position = local
	add_child(part)
	_items.append(part)
	_slots[part] = part.global_position


func _build_shell() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.35, 0.3)
	mat.roughness = 0.7
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.75, 0.55, 0.12)
	trim.roughness = 0.6
	var h: float = SIZE.y
	for spec in [
		[Vector3(0, WALL * 0.5, 0), Vector3(SIZE.x, WALL, SIZE.z)],
		[Vector3(-SIZE.x * 0.5 + WALL * 0.5, h * 0.5, 0), Vector3(WALL, h, SIZE.z)],
		[Vector3(SIZE.x * 0.5 - WALL * 0.5, h * 0.5, 0), Vector3(WALL, h, SIZE.z)],
		[Vector3(0, h * 0.5, -SIZE.z * 0.5 + WALL * 0.5), Vector3(SIZE.x, h, WALL)],
		[Vector3(0, h * 0.5, SIZE.z * 0.5 - WALL * 0.5), Vector3(SIZE.x, h, WALL)],
	]:
		var b := CSGBox3D.new()
		b.size = spec[1]
		b.position = spec[0]
		b.material = mat
		b.use_collision = true    # solid: blocks the player and rests parts
		add_child(b)
	# Divider shelf over the harness bay: the shielded signal cables rest on it.
	var divider := CSGBox3D.new()
	divider.name = "SignalDivider"
	divider.size = Vector3(0.2, 0.008, SIZE.z - 2.0 * WALL)
	divider.position = Vector3(0.17, WALL + 0.074, 0)
	divider.material = mat
	divider.use_collision = true
	add_child(divider)
	for zz in [-1.0, 1.0]:
		var band := CSGBox3D.new()
		band.size = Vector3(SIZE.x + 0.006, 0.03, 0.006)
		band.position = Vector3(0, h * 0.62, zz * (SIZE.z * 0.5 + 0.003))
		band.material = trim
		add_child(band)
	# Lid on a hinge along the back (+X) edge.
	_hinge = Node3D.new()
	_hinge.name = "LidHinge"
	_hinge.position = Vector3(SIZE.x * 0.5, h, 0)
	add_child(_hinge)
	_lid = CSGBox3D.new()
	_lid.name = "Lid"
	_lid.size = Vector3(SIZE.x + 0.02, 0.025, SIZE.z + 0.02)
	_lid.position = Vector3(-SIZE.x * 0.5, 0.0125, 0)
	_lid.material = mat
	_hinge.add_child(_lid)
	_label = Label3D.new()
	_label.name = "ReserveLabel"
	_label.font_size = 26
	_label.pixel_size = 0.0011
	_label.position = Vector3(-SIZE.x * 0.5 - 0.004, h * 0.42, 0)
	_label.rotation_degrees = Vector3(0, -90, 0)
	_label.modulate = Color(0.92, 0.9, 0.82)
	add_child(_label)
	# The interaction volume is the lid itself (follows it when opened).
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = _lid.size
	_shape.shape = bs
	add_child(_shape)
	_sync_shape()
	# Round 33: the crate's inner FLOOR is part of its body too, so looking
	# into the open crate targets it (Space stows / unloads the carrier);
	# parts lying on that floor are still hit first.
	var floor_cs := CollisionShape3D.new()
	floor_cs.name = "InnerFloor"
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(SIZE.x - 2.0 * WALL, WALL, SIZE.z - 2.0 * WALL)
	floor_cs.shape = fbs
	floor_cs.position = Vector3(0, WALL * 0.5, 0)
	add_child(floor_cs)


func _process(_delta: float) -> void:
	_sync_shape()
	_refresh_label()


func _sync_shape() -> void:
	if _shape != null and _lid != null:
		_shape.global_transform = _lid.global_transform


func interact() -> void:
	_open = not _open
	if _sfx != null:
		_sfx.play_kind(&"clunk")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not _open:
		_gate_open = false
		_apply_gating()
	_tween = create_tween()
	_tween.tween_property(_hinge, "rotation_degrees:z", -lid_open_degrees if _open else 0.0, open_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func():
		_gate_open = _open
		_apply_gating())


func get_interact_prompt() -> String:
	return "Click: Close Reserve Crate" if _open else "Click: Open Reserve Crate"


func is_open() -> bool:
	return _open


## A reserve part still in its crate slot (not held, not moved, not adopted).
func is_in_reserve(item) -> bool:
	if not is_instance_valid(item) or not _slots.has(item) or not item.is_inside_tree():
		return false
	if item.has_method("is_installed") and item.is_installed():
		return false
	var cs: Variant = item.get("_carry_system")
	if cs != null and cs.has_method("is_holding") and cs.is_holding(item):
		return false
	return (item as Node3D).global_position.distance_to(_slots[item]) < 0.05


## Round 32: delivered (or returned) compatible parts can be stowed INTO
## the reserve while the lid is open and a slot of that type is free.
func accepts_item(item: Node) -> bool:
	if not (_open and _gate_open) or item == null or not ("item_id" in item):
		return false
	if item.has_method("is_carrier"):
		return item.can_unload_into(self)
	if item.has_method("is_installed") and item.is_installed():
		return false
	return _free_slot(item.item_id) != -1


func stow(item: Node3D) -> bool:
	var i: int = _free_slot(item.item_id)
	if i == -1:
		return false
	var g: Vector3 = to_global(_slots_def[i][1])
	if item.has_method("set_rest_global"):
		item.set_rest_global(Transform3D(global_basis, g), self)
	item.return_to_rest()
	if not _items.has(item):
		_items.append(item)
	_slots[item] = g
	reserve_received += 1
	return true


## Round 33 save/load helpers.
func slot_index_of(item: Node) -> int:
	if not is_in_reserve(item):
		return -1
	for i in _slots_def.size():
		if to_global(_slots_def[i][1]).distance_to(_slots[item]) < 0.03:
			return i
	return -1


func persist_place(item: Node3D, idx: int) -> bool:
	if idx < 0 or idx >= _slots_def.size():
		return false
	var g: Vector3 = to_global(_slots_def[idx][1])
	if item.has_method("set_rest_global"):
		item.set_rest_global(Transform3D(global_basis, g), self)
	item.return_to_rest()
	if not _items.has(item):
		_items.append(item)
	_slots[item] = g
	return true


func persist_refresh() -> void:
	_items = _items.filter(func(it): return is_instance_valid(it))
	_apply_gating()
	_refresh_label()


func capacity(item_id: StringName) -> int:
	var n := 0
	for sd in _slots_def:
		if sd[0] == item_id:
			n += 1
	return n


func _free_slot(item_id: StringName) -> int:
	for i in _slots_def.size():
		if _slots_def[i][0] != item_id:
			continue
		var g: Vector3 = to_global(_slots_def[i][1])
		var used := false
		for it in _items:
			if is_in_reserve(it) and _slots[it].distance_to(g) < 0.03:
				used = true
		if not used:
			return i
	return -1


var reserve_received: int = 0


func reserve_count(item_id: StringName) -> int:
	_items = _items.filter(func(it): return is_instance_valid(it))
	var n := 0
	for it in _items:
		if is_in_reserve(it) and it.item_id == item_id:
			n += 1
	return n


func _apply_gating() -> void:
	for it in _items:
		if is_in_reserve(it):
			it.visible = _gate_open
			var c: Node = it.get_node_or_null("Collision")
			if c != null:
				c.disabled = not _gate_open


func _refresh_label() -> void:
	var t := "RESERVE SUPPLY\nFILTERS %d   16GA %d   22GA %d" % [reserve_count(&"filter_cartridge"), reserve_count(&"wire_control_16ga"), reserve_count(&"wire_signal_22ga")]
	if t != _last_counts:
		_last_counts = t
		_label.text = t
