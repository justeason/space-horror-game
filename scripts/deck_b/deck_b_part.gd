extends StaticBody3D
## Round 49: a physical Deck B COMPONENT -- a real carried item in the
## station's one inventory (SaveGame lists it with every other part, by its
## stable name; ownership: a rack slot, the service hoist, loose, held).
## Its `payload` is the authoritative component instance state:
##   serial, condition (0..1), grade (A/B/C), calibrated, state (new |
##   serviceable | repair | failed | spent | quarantined), history [...]
## Installing a part into a machine CONSUMES the item (the machine records
## the instance); removing one CREATES the old part as an item -- nothing
## is ever duplicated or conjured.

const KINDS := {
	&"mf_bed": {"name": "MF-2 filter bed", "shape": "cyl", "size": Vector3(0.11, 0.3, 0.11), "col": Color(0.86, 0.86, 0.82), "accent": Color(0.2, 0.5, 0.9)},
	&"ix_bed": {"name": "IX-1 ion-exchange bed", "shape": "cyl", "size": Vector3(0.11, 0.3, 0.11), "col": Color(0.86, 0.84, 0.78), "accent": Color(0.95, 0.6, 0.12)},
	&"mf_bed_spent": {"name": "MF-2 filter bed (spent)", "shape": "cyl", "size": Vector3(0.11, 0.3, 0.11), "col": Color(0.55, 0.5, 0.42), "accent": Color(0.3, 0.3, 0.3)},
	&"pump_seal_kit": {"name": "Pump seal kit PS-7", "shape": "box", "size": Vector3(0.14, 0.05, 0.1), "col": Color(0.2, 0.22, 0.25), "accent": Color(0.9, 0.75, 0.2)},
	&"coolant_sensor": {"name": "Coolant sensor CS-4", "shape": "cyl", "size": Vector3(0.035, 0.14, 0.035), "col": Color(0.7, 0.72, 0.74), "accent": Color(0.2, 0.6, 0.9)},
	&"valve_actuator": {"name": "Valve actuator VA-3", "shape": "box", "size": Vector3(0.12, 0.1, 0.1), "col": Color(0.3, 0.33, 0.36), "accent": Color(0.85, 0.3, 0.2)},
	&"relay_module": {"name": "Relay module RM-2", "shape": "box", "size": Vector3(0.08, 0.06, 0.1), "col": Color(0.15, 0.16, 0.18), "accent": Color(0.9, 0.9, 0.85)},
	&"bearing_cartridge": {"name": "Pump bearing cartridge", "shape": "cyl", "size": Vector3(0.07, 0.08, 0.07), "col": Color(0.6, 0.62, 0.65), "accent": Color(0.3, 0.3, 0.32)},
	&"pump_cartridge": {"name": "Coolant pump cartridge", "shape": "box", "size": Vector3(0.36, 0.3, 0.3), "col": Color(0.32, 0.35, 0.4), "accent": Color(0.95, 0.72, 0.1), "bulky": true},
	&"data_cartridge": {"name": "Archive data cartridge", "shape": "box", "size": Vector3(0.1, 0.03, 0.14), "col": Color(0.12, 0.13, 0.16), "accent": Color(0.3, 0.8, 0.9)},
	&"grow_light_module": {"name": "Grow-light module GL-6", "shape": "box", "size": Vector3(0.22, 0.03, 0.1), "col": Color(0.8, 0.8, 0.82), "accent": Color(0.8, 0.3, 0.9)},
	&"sample_carrier": {"name": "Sealed sample container", "shape": "cyl", "size": Vector3(0.045, 0.12, 0.045), "col": Color(0.85, 0.9, 0.95), "accent": Color(0.2, 0.7, 0.4)},
	&"dosimeter_badge": {"name": "Dosimeter badge", "shape": "box", "size": Vector3(0.05, 0.012, 0.07), "col": Color(0.9, 0.9, 0.88), "accent": Color(0.9, 0.2, 0.2)},
	&"bracket": {"name": "Fabricated bracket", "shape": "box", "size": Vector3(0.1, 0.02, 0.06), "col": Color(0.85, 0.85, 0.8), "accent": Color(0.85, 0.85, 0.8)},
	&"cable_guide": {"name": "Fabricated cable guide", "shape": "box", "size": Vector3(0.12, 0.02, 0.03), "col": Color(0.85, 0.85, 0.8), "accent": Color(0.85, 0.85, 0.8)},
	&"med_pack": {"name": "Medical supply pack", "shape": "box", "size": Vector3(0.12, 0.05, 0.08), "col": Color(0.92, 0.92, 0.9), "accent": Color(0.85, 0.15, 0.15)},
	&"lamp_module": {"name": "Emergency lamp module", "shape": "box", "size": Vector3(0.1, 0.025, 0.03), "col": Color(0.85, 0.86, 0.8), "accent": Color(0.3, 0.9, 0.4)},
	# Round 50: emergency repair stock.
	&"leak_patch": {"name": "Temporary leak patch LP-2 (clamp plate)", "shape": "box", "size": Vector3(0.16, 0.03, 0.16), "col": Color(0.85, 0.5, 0.12), "accent": Color(0.15, 0.15, 0.15)},
	&"gland_packing": {"name": "Feedthrough gland packing set", "shape": "box", "size": Vector3(0.1, 0.04, 0.1), "col": Color(0.25, 0.27, 0.3), "accent": Color(0.3, 0.7, 0.95)},
	&"berth_seal_kit": {"name": "Berthing seal kit BP-1", "shape": "box", "size": Vector3(0.18, 0.04, 0.14), "col": Color(0.12, 0.12, 0.13), "accent": Color(0.95, 0.75, 0.2)},
	&"hull_patch_kit": {"name": "EVA hull patch kit HP-4", "shape": "box", "size": Vector3(0.2, 0.05, 0.16), "col": Color(0.82, 0.82, 0.8), "accent": Color(0.95, 0.4, 0.1)},
	&"seam_seal_kit": {"name": "EVA seam sealant kit SS-1", "shape": "cyl", "size": Vector3(0.05, 0.2, 0.05), "col": Color(0.85, 0.85, 0.82), "accent": Color(0.2, 0.55, 0.95)},
	&"hull_panel": {"name": "MMOD cover panel MP-3", "shape": "box", "size": Vector3(0.36, 0.02, 0.28), "col": Color(0.88, 0.88, 0.86), "accent": Color(0.6, 0.62, 0.65), "bulky": true},
	&"hull_panel_damaged": {"name": "MMOD cover panel (impact damaged)", "shape": "box", "size": Vector3(0.36, 0.02, 0.28), "col": Color(0.55, 0.52, 0.48), "accent": Color(0.25, 0.22, 0.2), "bulky": true},
	&"suit_seal_kit": {"name": "Suit seal kit (neck / wrist O-rings)", "shape": "box", "size": Vector3(0.1, 0.03, 0.08), "col": Color(0.15, 0.16, 0.18), "accent": Color(0.9, 0.2, 0.2)},
}

@export var item_id: StringName = &"mf_bed"
var carry_system_path: NodePath
var message_label_path: NodePath
var payload: Dictionary = {}
var bulky: bool = false
var _carry_system: Node
var _resting_parent: Node
var _resting_transform: Transform3D
var _tag: Label3D


static func make(kind: StringName, node_name: String, pl: Dictionary = {}) -> StaticBody3D:
	var p := StaticBody3D.new()
	p.set_script(load("res://scripts/deck_b/deck_b_part.gd"))
	p.item_id = kind
	p.name = node_name
	p.payload = pl.duplicate(true)
	return p


func _ready() -> void:
	add_to_group(&"deck_b_part")
	collision_layer = 16
	collision_mask = 0
	var k: Dictionary = KINDS.get(item_id, KINDS[&"relay_module"])
	bulky = bool(k.get("bulky", false))
	var defaults := {"serial": "%s-%04d" % [String(item_id).to_upper().left(4), absi(hash(String(name))) % 10000], "condition": 1.0, "grade": "A", "calibrated": true, "state": "new", "history": []}
	for dk in defaults:
		if not payload.has(dk):
			payload[dk] = defaults[dk]
	var size: Vector3 = k["size"]
	var mi := MeshInstance3D.new()
	if k["shape"] == "cyl":
		var cm := CylinderMesh.new()
		cm.top_radius = size.x
		cm.bottom_radius = size.x
		cm.height = size.y
		mi.mesh = cm
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = k["col"]
	m.metallic = 0.35
	m.roughness = 0.5
	mi.material_override = m
	mi.layers = 1 | (1 << 13)
	add_child(mi)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(size.x * (2.05 if k["shape"] == "cyl" else 1.02), maxf(size.y * 0.18, 0.01), size.z * (2.05 if k["shape"] == "cyl" else 1.02))
	band.mesh = bb
	var am := StandardMaterial3D.new()
	am.albedo_color = k["accent"]
	band.material_override = am
	band.layers = mi.layers
	band.position.y = size.y * 0.22
	add_child(band)
	_tag = Label3D.new()
	_tag.font_size = 10
	_tag.pixel_size = 0.0007
	_tag.modulate = Color(0.1, 0.1, 0.1) if (k["col"] as Color).v > 0.5 else Color(0.9, 0.9, 0.85)
	_tag.position = Vector3(0, size.y * 0.5 + 0.002, 0) if k["shape"] == "box" else Vector3(0, 0, size.x + 0.002)
	_tag.rotation_degrees.x = -90.0 if k["shape"] == "box" else 0.0
	_tag.layers = mi.layers
	add_child(_tag)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x * 2.0, size.y, size.x * 2.0) if k["shape"] == "cyl" else size
	bs.size = bs.size.max(Vector3(0.06, 0.04, 0.06))
	cs.shape = bs
	add_child(cs)
	var root: Node = get_tree().current_scene if is_inside_tree() else null
	if root != null and carry_system_path.is_empty():
		var c: Node = root.get_node_or_null("Player/CarrySystem")
		if c != null:
			carry_system_path = c.get_path()
	_carry_system = get_node_or_null(carry_system_path) if not carry_system_path.is_empty() else null
	if _resting_parent == null:
		_resting_parent = get_parent()
		_resting_transform = transform
	refresh()


func refresh() -> void:
	if _tag != null:
		var st: String = String(payload.get("state", "new")).to_upper()
		_tag.text = "%s\n%s" % [String(payload.get("serial", "")), st if st != "NEW" else ""]


func _carry() -> Node:
	if _carry_system == null and is_inside_tree():
		_carry_system = get_tree().current_scene.get_node_or_null("Player/CarrySystem") if get_tree().current_scene != null else null
	return _carry_system


func interact() -> void:
	var c: Node = _carry()
	if c == null or c.is_carrying():
		return
	var holder: Node = _holder()
	if holder != null and holder.has_method("item_removed") and not holder.item_removed(self):
		return
	c.pick_up(self)


## A rack / tray that holds this item (it may refuse, e.g. a locked rack).
func _holder() -> Node:
	var n: Node = get_parent()
	for i in 3:
		if n == null:
			return null
		if n.has_method("item_removed"):
			return n
		n = n.get_parent()
	return null


func get_interact_prompt() -> String:
	var c: Node = _carry()
	if c != null and c.is_carrying():
		return ""
	var cond: float = float(payload.get("condition", 1.0))
	var extra: String = ""
	if String(payload.get("state", "")) in ["failed", "repair", "spent", "quarantined"]:
		extra = " — %s" % String(payload.get("state", "")).to_upper()
	elif cond < 0.6:
		extra = " — worn"
	return "Click: Take %s%s%s" % [get_display_name(), extra, "  (bulky: hoist only on the ladder)" if bulky else ""]


func get_display_name() -> String:
	return String(KINDS.get(item_id, {}).get("name", "Component"))


func set_rest_global(global_xf: Transform3D, parent: Node = null) -> void:
	if parent != null:
		_resting_parent = parent
	_resting_transform = (_resting_parent as Node3D).global_transform.affine_inverse() * global_xf if _resting_parent is Node3D else global_xf


func return_to_rest() -> void:
	if _resting_parent == null or not is_instance_valid(_resting_parent):
		return
	reparent(_resting_parent, false)
	transform = _resting_transform


func place_in_world(world_transform: Transform3D) -> void:
	var inter: Node = get_tree().current_scene.get_node_or_null("Interactables") if get_tree().current_scene != null else null
	reparent(inter if inter != null else _resting_parent, false)
	global_transform = world_transform
	_resting_parent = get_parent()
	_resting_transform = transform


func note(text: String, day: int) -> void:
	var h: Array = payload.get("history", [])
	h.append({"day": day, "text": text})
	if h.size() > 12:
		h.pop_front()
	payload["history"] = h
