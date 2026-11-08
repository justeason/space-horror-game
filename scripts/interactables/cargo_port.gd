extends StaticBody3D
## Round 32 Priority 3: the airlock CARGO TRANSFER PORT.
##
## A pressure-safe transfer compartment recessed into the airlock tunnel's
## west wall beside the EVA bulkhead (the station's only path to the
## outside). Shipments arrive here from outside on DayPlan's deterministic
## cargo schedule; parts enter the station ONLY through this port, in finite
## manifests, and reach Storage only when the player physically carries them.
##
## Receiving procedure (one physical step per click on the ID panel):
##   ARRIVED      -> "Check Shipment ID"        (manifest shown on the panel)
##   ID_CHECKED   -> "Unlock & Open Hatch"      (latches turn, pressure
##                                               equalises, hatch slides up)
##   OPEN         -> "Release Cargo Restraint"  (strap lifts; parts usable)
##   UNLOADING    -> carry each part to Storage (reserve crate or shelf)
##   EMPTY        -> "Confirm Receipt"          (shipment RECEIVED, logged)
##   RECEIVED     -> "Close & Secure Hatch"     -> SECURED (idle)
## The hatch slides UP inside the wall (a swinging hatch would obstruct the
## 0.8 m tunnel at head height).

signal shipment_received(shipment_id: String)

enum PortState { SECURED, ARRIVED, ID_CHECKED, OPEN, UNLOADING, EMPTY, RECEIVED }

@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var sfx_path: NodePath
@export var day_plan_path: NodePath
@export var wall_path: NodePath

const _CARRIER := preload("res://scripts/interactables/cargo_carrier.gd")
## Round 33: where the parts carrier docks (port-local, on the floor).
const CARRIER_DOCK := Vector3(-0.31, Y0 + 0.012, 0.0)
var carrier: Node3D = null
const _FILTER_SCENE := preload("res://scenes/interactables/filter_cartridge.tscn")
const _WIRE_SCENE := preload("res://scenes/interactables/wire_component.tscn")
const PART_NAMES = preload("res://scripts/station/part_names.gd")
## Compartment interior (port-local: +X toward the tunnel, the wall face at
## x = 0, the compartment extends into the hull to x = -DEPTH).
const DEPTH := 0.62
const Y0 := 0.85
const Y1 := 1.36
const HALF_W := 0.31
## Typed cargo slots: 3 filters standing in the back row, 2 power harnesses
## and 2 shielded signal cables flat in the front row.
const SLOTS := [
	[&"filter_cartridge", Vector3(-0.45, Y0 + 0.012 + 0.093, -0.18)],
	[&"filter_cartridge", Vector3(-0.45, Y0 + 0.012 + 0.093, 0.0)],
	[&"filter_cartridge", Vector3(-0.45, Y0 + 0.012 + 0.093, 0.18)],
	[&"wire_control_16ga", Vector3(-0.17, Y0 + 0.012 + 0.0096, -0.22)],
	[&"wire_control_16ga", Vector3(-0.17, Y0 + 0.012 + 0.0096, -0.075)],
	[&"wire_signal_22ga", Vector3(-0.17, Y0 + 0.012 + 0.0096, 0.075)],
	[&"wire_signal_22ga", Vector3(-0.17, Y0 + 0.012 + 0.0096, 0.22)],
]

var state: int = PortState.SECURED
var shipment_id: String = ""
var manifest: Dictionary = {}       # item_id -> count delivered
var received_shipments: Array = []  # ids, in order
var _parts: Array = []              # parts delivered and still in the port
var _slot_of: Dictionary = {}       # part -> global slot position
var _hatch: Node3D
var _strap: Node3D
var _latches: Array = []
var _lamp_mat: StandardMaterial3D
var _panel: Label3D
var _shape: CollisionShape3D
var _tween: Tween
var _shipment_seq: int = 0
@onready var _sfx: Node = get_node_or_null(sfx_path)
@onready var _msg: Label = get_node_or_null(message_label_path)
@onready var _day_plan: Node = get_node_or_null(day_plan_path)


func _ready() -> void:
	add_to_group(&"cargo_port")
	_cut_wall_opening()
	_build()
	if _day_plan != null and _day_plan.has_method("register_cargo_port"):
		_day_plan.register_cargo_port(self)
	# Round 33: the parts carrier starts docked in the compartment.
	carrier = StaticBody3D.new()
	carrier.set_script(_CARRIER)
	carrier.name = "CargoCarrier"
	var cs: Node = get_node_or_null(carry_system_path)
	var ml: Node = get_node_or_null(message_label_path)
	carrier.carry_system_path = cs.get_path() if cs != null else NodePath()
	carrier.message_label_path = ml.get_path() if ml != null else NodePath()
	add_child(carrier)
	carrier.position = CARRIER_DOCK
	carrier.dock(self, dock_global())
	_refresh()


# ---------------------------------------------------------------- geometry
func _cut_wall_opening() -> void:
	var wall: Node = get_node_or_null(wall_path)
	if not (wall is CSGShape3D):
		return
	var cut := CSGBox3D.new()
	cut.name = "CargoPortOpening"
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	cut.size = Vector3(0.5, Y1 - Y0 + 0.02, HALF_W * 2.0 + 0.02)
	wall.add_child(cut)
	cut.global_position = to_global(Vector3(-0.1, (Y0 + Y1) * 0.5, 0.0))


func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool, parent: Node = self) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	b.use_collision = collide
	parent.add_child(b)
	return b


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.42, 0.45, 0.47)
	shell.metallic = 0.4
	shell.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.17, 0.18)
	dark.metallic = 0.5
	var hazard := StandardMaterial3D.new()
	hazard.albedo_color = Color(0.8, 0.6, 0.1)
	var strap_mat := StandardMaterial3D.new()
	strap_mat.albedo_color = Color(0.85, 0.35, 0.1)
	var h: float = Y1 - Y0
	# Pressure-safe compartment shell (in the hull space behind the wall).
	_box(Vector3(0.02, h + 0.04, HALF_W * 2.0 + 0.04), Vector3(-DEPTH, (Y0 + Y1) * 0.5, 0), shell, true)
	_box(Vector3(DEPTH, 0.024, HALF_W * 2.0 + 0.04), Vector3(-DEPTH * 0.5, Y0, 0), shell, true)
	_box(Vector3(DEPTH, 0.024, HALF_W * 2.0 + 0.04), Vector3(-DEPTH * 0.5, Y1, 0), shell, true)
	for zz in [-1.0, 1.0]:
		_box(Vector3(DEPTH, h + 0.04, 0.02), Vector3(-DEPTH * 0.5, (Y0 + Y1) * 0.5, zz * (HALF_W + 0.01)), shell, true)
	# Pressure frame + hazard banding around the opening (on the wall face).
	_box(Vector3(0.025, 0.05, HALF_W * 2.0 + 0.14), Vector3(0.0125, Y1 + 0.04, 0), dark, false)
	_box(Vector3(0.025, 0.05, HALF_W * 2.0 + 0.14), Vector3(0.0125, Y0 - 0.04, 0), dark, false)
	for zz in [-1.0, 1.0]:
		_box(Vector3(0.025, h + 0.13, 0.05), Vector3(0.0125, (Y0 + Y1) * 0.5, zz * (HALF_W + 0.045)), dark, false)
	_box(Vector3(0.006, 0.018, HALF_W * 2.0 + 0.14), Vector3(0.028, Y0 - 0.075, 0), hazard, false)
	# Sliding pressure hatch (slides UP into the wall above the opening).
	_hatch = Node3D.new()
	_hatch.name = "Hatch"
	add_child(_hatch)
	_box(Vector3(0.03, h + 0.02, HALF_W * 2.0 + 0.02), Vector3(0.015, (Y0 + Y1) * 0.5, 0), dark, true, _hatch)
	var window := _box(Vector3(0.004, 0.1, 0.3), Vector3(0.032, (Y0 + Y1) * 0.5 + 0.08, 0), hazard, false, _hatch)
	window.name = "HatchStripe"
	# Two latch handles (turn 90 deg when unlocked).
	for zz in [-1.0, 1.0]:
		var l := Node3D.new()
		l.position = Vector3(0.04, (Y0 + Y1) * 0.5, zz * (HALF_W - 0.06))
		_hatch.add_child(l)
		_box(Vector3(0.02, 0.12, 0.025), Vector3(0.01, 0, 0), shell, false, l)
		_latches.append(l)
	# Cargo restraint strap across the contents.
	_strap = Node3D.new()
	_strap.name = "Restraint"
	add_child(_strap)
	_box(Vector3(0.012, 0.035, HALF_W * 2.0 - 0.02), Vector3(-0.06, Y0 + 0.12, 0), strap_mat, false, _strap)
	# Status lamp + shipment identification panel (beside the opening).
	var lamp := CSGSphere3D.new()
	lamp.radius = 0.02
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission_energy_multiplier = 2.0
	lamp.material = _lamp_mat
	lamp.position = Vector3(0.02, Y1 + 0.12, HALF_W + 0.04)
	add_child(lamp)
	_panel = Label3D.new()
	_panel.name = "ShipmentPanel"
	_panel.font_size = 24
	_panel.pixel_size = 0.0011
	_panel.position = Vector3(0.03, Y1 + 0.2, 0)
	_panel.rotation_degrees = Vector3(0, 90, 0)
	_panel.modulate = Color(0.88, 0.92, 0.85)
	add_child(_panel)
	# Interaction volume: the ID panel / control strip above the opening
	# (never covers the opening, so delivered parts stay clickable).
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.05, 0.22, HALF_W * 2.0 + 0.1)
	_shape.shape = bs
	_shape.position = Vector3(0.03, Y1 + 0.17, 0)
	add_child(_shape)


# ---------------------------------------------------------------- shipments
## Called by DayPlan's cargo schedule: a finite shipment arrives from
## outside into the (secured) compartment. Returns false if the port is
## still busy with a previous shipment (nothing is created).
func receive_shipment(id: String, wanted: Dictionary) -> bool:
	if state != PortState.SECURED:
		return false
	var cs: Node = get_node_or_null(carry_system_path)
	var ml: Node = get_node_or_null(message_label_path)
	manifest = {}
	var used := {}
	for sd in SLOTS:
		var t: StringName = sd[0]
		if used.get(t, 0) >= int(wanted.get(t, 0)):
			continue
		used[t] = used.get(t, 0) + 1
		var part: Node3D = (_FILTER_SCENE if t == &"filter_cartridge" else _WIRE_SCENE).instantiate()
		if t != &"filter_cartridge":
			part.item_id = t
			if t == &"wire_signal_22ga":
				part.cable_type = "signal"
		_shipment_seq += 1
		part.name = "Cargo%s_%d" % [id.replace("-", ""), _shipment_seq]
		if cs != null:
			part.carry_system_path = cs.get_path()
		if ml != null:
			part.message_label_path = ml.get_path()
		var ci: int = carrier.free_cradle(t) if carrier_docked() else -1
		if ci != -1:
			# Round 33: packed into the docked parts carrier.
			carrier.put(part, ci)
		else:
			part.position = sd[1]
			add_child(part)
		_parts.append(part)
		_slot_of[part] = part.global_position
		manifest[t] = manifest.get(t, 0) + 1
	if _parts.is_empty():
		return false
	shipment_id = id
	state = PortState.ARRIVED
	_gate(false)
	_refresh()
	return true


## Round 33 save/load helpers.
func slot_index_of(p: Node) -> int:
	if not in_port(p):
		return -1
	for i in SLOTS.size():
		if to_global(SLOTS[i][1]).distance_to(_slot_of[p]) < 0.03:
			return i
	return -1


func persist_clear() -> void:
	_parts = []
	_slot_of = {}


## Save/load: a part restored into the docked carrier is also in the port.
func persist_track(p: Node3D) -> void:
	if not _parts.has(p):
		_parts.append(p)
	_slot_of[p] = p.global_position


func persist_place(p: Node3D, idx: int) -> bool:
	if idx < 0 or idx >= SLOTS.size():
		return false
	var g: Vector3 = to_global(SLOTS[idx][1])
	if p.has_method("set_rest_global"):
		p.set_rest_global(Transform3D(global_basis, g), self)
	p.return_to_rest()
	_parts.append(p)
	_slot_of[p] = g
	return true


## True while the hatch is animating (an unsafe moment to save).
func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Snap the hatch/strap/latches/lamp/gating to `state` (no animation, no
## sounds) after a restore.
func persist_refresh() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var open: bool = state in [PortState.OPEN, PortState.UNLOADING, PortState.EMPTY, PortState.RECEIVED]
	_hatch.position.y = (Y1 - Y0 + 0.06) if open else 0.0
	for l in _latches:
		l.rotation_degrees.x = 90.0 if open else 0.0
	_strap.position.y = 0.2 if state in [PortState.UNLOADING, PortState.EMPTY, PortState.RECEIVED] else 0.0
	_gate(state in [PortState.UNLOADING, PortState.EMPTY, PortState.RECEIVED])
	_refresh()


func parts_in_port(item_id: StringName = &"") -> int:
	var n := 0
	for p in _parts:
		if in_port(p) and (item_id == &"" or p.item_id == item_id):
			n += 1
	return n


## A delivered part still sitting in its cargo slot (not held/moved).
func in_port(p) -> bool:
	if not is_instance_valid(p) or not _slot_of.has(p):
		return false
	var cs: Variant = p.get("_carry_system")
	if cs != null and cs.has_method("is_holding") and (cs.is_holding(p) or cs.is_reserved(p)):
		return false
	return (p as Node3D).global_position.distance_to(_slot_of[p]) < 0.05


func is_busy() -> bool:
	return state != PortState.SECURED


# ---------------------------------------------------------------- procedure
func interact() -> void:
	_update_empty()   # an emptied compartment is confirmable immediately
	# Round 35 interlock: the airlock hatch in INSPECTION mode blocks cargo
	# operations (and vice versa, see hatch_seal.gd).
	var hs: Node = get_tree().get_first_node_in_group(&"hatch_seal") if is_inside_tree() else null
	# Round 38: no cargo operation while the airlock is in EVA use.
	var eva: Node = get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null
	if eva != null and eva.is_eva_active():
		_say("Airlock in EVA use — cargo operations locked out.")
		return
	if hs != null and hs.inspection_mode and state != PortState.SECURED:
		_say("Airlock hatch is in inspection mode — secure it first.")
		for n in get_tree().get_nodes_in_group(&"station_ai"):
			n.event(&"interlock_seal")
		return
	if hs != null and hs.inspection_mode and state == PortState.SECURED:
		return
	match state:
		PortState.ARRIVED:
			state = PortState.ID_CHECKED
			_say("Shipment %s verified: %s." % [shipment_id, _manifest_text(", ")])
			_click(&"click")
		PortState.ID_CHECKED:
			_open_hatch()
		PortState.OPEN:
			state = PortState.UNLOADING
			_click(&"ratchet")
			_anim(_strap, "position:y", 0.2, 0.35)
			_gate(true)
			_say("Cargo restraint released. Transfer the parts to Storage.")
		PortState.EMPTY:
			state = PortState.RECEIVED
			received_shipments.append(shipment_id)
			_click(&"success")
			_say("Receipt of %s confirmed." % shipment_id)
			if _day_plan != null:
				if _day_plan.has_method("record_fact"):
					_day_plan.record_fact(&"received:cargo")
				if _day_plan.has_method("log_event"):
					_day_plan.log_event("Received cargo %s (%s)" % [shipment_id, _manifest_text(", ")], &"cargo_parts", _manifest_total())
			shipment_received.emit(shipment_id)
		PortState.RECEIVED:
			_close_hatch()
		PortState.UNLOADING:
			_say("%d part(s) still to transfer to Storage." % parts_in_port())
	_refresh()


func get_interact_prompt() -> String:
	match state:
		PortState.ARRIVED: return "Click: Check Shipment ID"
		PortState.ID_CHECKED: return "Click: Unlock & Open Transfer Hatch"
		PortState.OPEN: return "Click: Release Cargo Restraint"
		PortState.UNLOADING: return "Transfer parts to Storage (%d left)" % parts_in_port()
		PortState.EMPTY: return "Click: Confirm Receipt"
		PortState.RECEIVED: return "Click: Close & Secure Hatch"
	return "Cargo Transfer Port — secured"


func _open_hatch() -> void:
	_click(&"clunk")
	for l in _latches:
		_anim(l, "rotation_degrees:x", 90.0, 0.25)
	# Pressure equalisation, then the hatch slides up into the wall.
	_set_lamp(Color(1.0, 0.65, 0.1))
	_tween = create_tween()
	_tween.tween_interval(0.8)
	_tween.tween_property(_hatch, "position:y", Y1 - Y0 + 0.06, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func():
		state = PortState.OPEN
		_refresh())


func _close_hatch() -> void:
	_click(&"clunk")
	_anim(_strap, "position:y", 0.0, 0.3)
	_tween = create_tween()
	_tween.tween_property(_hatch, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func():
		for l in _latches:
			_anim(l, "rotation_degrees:x", 0.0, 0.25)
		state = PortState.SECURED
		shipment_id = ""
		manifest = {}
		_parts = _parts.filter(func(p): return is_instance_valid(p) and in_port(p))
		_refresh())


func _process(_d: float) -> void:
	_update_empty()


func _update_empty() -> void:
	if state == PortState.UNLOADING and parts_in_port() == 0:
		state = PortState.EMPTY
		_say("Compartment empty. Confirm receipt at the panel.")
		_refresh()


func _gate(open: bool) -> void:
	for p in _parts:
		if in_port(p):
			p.visible = open
			var c: Node = p.get_node_or_null("Collision")
			if c != null:
				c.disabled = not open
	if carrier != null:
		carrier.regate()


# ------------------------------------------------------- Round 33: carrier
func carrier_docked() -> bool:
	return carrier != null and is_instance_valid(carrier) and carrier.is_docked()


func carrier_can_leave() -> bool:
	return state in [PortState.UNLOADING, PortState.EMPTY, PortState.RECEIVED]


func carrier_parts_clickable() -> bool:
	return state in [PortState.UNLOADING, PortState.EMPTY, PortState.RECEIVED]


func dock_global() -> Transform3D:
	return Transform3D(global_basis, to_global(CARRIER_DOCK))


## The empty (or not) carrier can be docked back while the hatch is open.
func accepts_item(item: Node) -> bool:
	return item != null and item.has_method("is_carrier") and item == carrier and not carrier_docked() and carrier_can_leave()


func stow(item: Node3D) -> bool:
	if not accepts_item(item):
		return false
	carrier.dock(self, dock_global())
	for p in carrier.parts():
		if not _parts.has(p):
			_parts.append(p)
		_slot_of[p] = p.global_position
	_say("Parts carrier docked in the cargo port.")
	return true


# ---------------------------------------------------------------- feedback
func _manifest_text(sep: String) -> String:
	var bits: Array = []
	for t in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
		if manifest.get(t, 0) > 0:
			bits.append("%d %s" % [manifest[t], PART_NAMES.short(t)])
	return sep.join(bits) if not bits.is_empty() else "empty"


func _manifest_total() -> int:
	var n := 0
	for t in manifest:
		n += int(manifest[t])
	return n


func status_word() -> String:
	return ["SECURED", "SHIPMENT ARRIVED", "ID VERIFIED", "HATCH OPEN", "UNLOADING", "EMPTY — CONFIRM", "RECEIVED"][state]


func _refresh() -> void:
	var line2: String = "NO SHIPMENT" if shipment_id == "" else "%s  %s" % [shipment_id, _manifest_text(" · ")]
	if state == PortState.UNLOADING:
		line2 += "  (%d LEFT)" % parts_in_port()
	_panel.text = "CARGO TRANSFER PORT\n%s\n%s" % [line2, status_word()]
	match state:
		PortState.SECURED, PortState.RECEIVED:
			_set_lamp(Color(0.9, 0.2, 0.15) if shipment_id == "" else Color(0.3, 0.9, 0.4))
		PortState.ARRIVED, PortState.ID_CHECKED:
			_set_lamp(Color(0.3, 0.6, 1.0))
		_:
			_set_lamp(Color(0.3, 0.9, 0.4))


func _set_lamp(c: Color) -> void:
	_lamp_mat.albedo_color = c * 0.6
	_lamp_mat.emission = c


func _anim(n: Node, prop: String, v: float, d: float) -> void:
	var t := create_tween()
	t.tween_property(n, prop, v, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _click(kind: StringName) -> void:
	if _sfx != null and _sfx.has_method("play_kind"):
		_sfx.play_kind(kind)


func _say(t: String) -> void:
	if _msg != null:
		preload("res://scripts/ui/hud_message.gd").show(_msg, get_instance_id(), t, 4.0)
