extends "res://scripts/station/equipment_base.gd"
## Round 49: shared base of the Deck B room equipment, and the REUSABLE
## TASK-MECHANIC LIBRARY the rooms are built from (so twenty procedures are
## not twenty copy-pasted scripts -- yet each one keeps its own equipment,
## geometry and consequence):
##   tasks          several work orders per room (TaskAdapter per type ->
##                  DayPlan's equipment API, with the type passed through)
##   Procedure      ordered steps with prerequisites and a reason on refusal
##   handwheel()    a valve / knob that physically turns with its value
##   readout()      an instrument display (short labels: READY / LOW FLOW /
##                  FAULT / PASS / HOLD / ISOLATED)
##   rack()         a parts rack / tray (real items, real slots)
##   probe points   test-point reading (multimeter / vibration / IR)
##   classify       sound / evidence classification against real state
##   loop sounds    a running machine's positional loop (fault-dependent)
##   record()       service history -> station log + Deck B service record
## Each subclass owns its equipment; the authoritative numbers live in
## deck_b_systems.gd.

const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const Tasks = preload("res://scripts/deck_b/deck_b_tasks.gd")
const Part = preload("res://scripts/deck_b/deck_b_part.gd")
const Foley = preload("res://scripts/audio/foley_synth.gd")
const LAYER := 1 << 13

var room_id: StringName = &""
var outcome: Dictionary = {}        # type -> outcome id when closed
var _loops: Array = []              # AudioStreamPlayer3D running machines
var _occl_t: float = 0.0


class TaskAdapter extends Node:
	var room: Node
	var type: StringName
	func order_rearm(seed: int) -> void:
		room.outcome.erase(type)
		room.task_rearm(type, seed)
	func order_done() -> bool:
		return room.task_done(type)
	func order_next() -> Dictionary:
		return room.task_next(type)
	func order_progress() -> String:
		return room.task_progress(type)
	func order_detail() -> Array:
		return room.task_detail(type)
	func order_feasible() -> bool:
		return room.task_feasible(type)
	func order_severity() -> int:
		return room.task_severity(type)
	func order_outcome() -> String:
		return String(room.outcome.get(type, ""))


func _room_ready(types: Array) -> void:
	add_to_group(&"r35_equipment")
	add_to_group(&"deck_b_room")
	_dp = get_tree().current_scene.get_node_or_null("DayPlan") if get_tree().current_scene != null else null
	if _dp == null:
		var n: Node = self
		while n != null and _dp == null:
			_dp = n.get_node_or_null("DayPlan")
			n = n.get_parent()
	var main: Node = _dp.get_parent() if _dp != null else null
	_sfx = main.get_node_or_null("Player/HUD/MechanicalSfx") if main != null else null
	for t in types:
		var a := TaskAdapter.new()
		a.name = "Task_" + String(t)
		a.room = self
		a.type = t
		add_child(a)
		if _dp != null and _dp.has_method("register_order_equipment"):
			_dp.register_order_equipment(t, a)


func _ready_message_label() -> Label:
	var main: Node = _dp.get_parent() if _dp != null else null
	return main.get_node_or_null("Player/HUD/TaskMessageLabel") as Label if main != null else null


func say(text: String, seconds: float = 3.2) -> void:
	Hud.show(_ready_message_label(), get_instance_id(), text, seconds)


func sys() -> Node:
	return get_tree().get_first_node_in_group(&"deck_b_systems") if is_inside_tree() else null


func day() -> int:
	return int(_dp.day_number) if _dp != null else 1


func clock() -> String:
	return _dp.clock_text_hhmm() if _dp != null and _dp.has_method("clock_text_hhmm") else "--:--"


## Proficiency in a family -> how much the equipment explains:
## 0 = novice (targets and next step printed), 1 = practised (bands only),
## 2 = senior (raw instruments only).
func hint_level(family: String) -> int:
	var n: int = int(_dp.proficiency_level(family)) if _dp != null and _dp.has_method("proficiency_level") else 0
	var d: int = difficulty()
	var lvl: int = 0 if n <= 2 else (1 if n <= 6 else 2)
	if d == 0:
		lvl = maxi(lvl - 1, 0)
	elif d >= 2:
		lvl = mini(lvl + 1, 2)
	return lvl


func has_open(t: StringName) -> bool:
	return _dp != null and _dp.has_open_order(t)


## Closes a task with an explicit OUTCOME (verified_normal | repaired |
## sensor_fault | fluctuation | inconclusive | not_reproduced | deferred |
## no_part | needs_clearance) and writes the service record.
func close_task(t: StringName, result: String, equipment: String, fault: String, action: String, verification: String) -> void:
	outcome[t] = result
	record(equipment, fault, action, verification, result, t)


func record(equipment: String, fault: String, action: String, verification: String, result: String, t: StringName = &"") -> void:
	var s: Node = sys()
	if s != null:
		s.record_service({"day": day(), "t": clock(), "room": String(room_id), "equipment": equipment, "fault": fault, "action": action, "verify": verification, "outcome": result, "type": String(t)})


# ------------------------------------------------------------ geometry
## A box on Deck B's visual layer (base box() is CSG with no collision).
func dbox(size: Vector3, pos: Vector3, col: Color, parent: Node3D = null, metal: float = 0.35, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.55
	mi.material_override = m
	mi.position = pos
	mi.layers = LAYER
	(parent if parent != null else self).add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func dcyl(r: float, h: float, pos: Vector3, col: Color, parent: Node3D = null, rot: Vector3 = Vector3.ZERO, metal: float = 0.5, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.45
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.layers = LAYER
	(parent if parent != null else self).add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = h
		cs.shape = cy
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func glow(mi: MeshInstance3D, c: Color, energy: float = 1.5) -> void:
	var m: StandardMaterial3D = mi.material_override
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy


func text(t: String, pos: Vector3, size: int = 14, col: Color = Color(0.9, 0.92, 0.88), parent: Node3D = null, yaw: float = 0.0) -> Label3D:
	var l := label(t, pos, size, col, parent)
	l.rotation_degrees.y = yaw
	l.layers = LAYER
	return l


## An instrument display: a dark bezel + a monospace-ish readout label.
func readout(pos: Vector3, size: Vector2, parent: Node3D = null, font: int = 13, col: Color = Color(0.55, 0.95, 0.75), yaw: float = 0.0) -> Label3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw
	(parent if parent != null else self).add_child(holder)
	dbox(Vector3(size.x, size.y, 0.012), Vector3(0, 0, -0.006), Color(0.03, 0.04, 0.05), holder, 0.1)
	var l := text("", Vector3(0, 0, 0.002), font, col, holder)
	l.width = size.x / 0.0009
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## A handwheel / knob that visibly turns with its value (0..1 = 0..270 deg)
## and two click parts (open / close) -- or one (`single`) that steps.
func handwheel(id: String, pos: Vector3, r: float, parent: Node3D = null, axis_z: bool = true, col: Color = Color(0.75, 0.2, 0.15)) -> Node3D:
	var p: Node3D = parent if parent != null else self
	var root := Node3D.new()
	root.name = "Wheel_" + id
	root.position = pos
	p.add_child(root)
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	dcyl(r, 0.025, Vector3.ZERO, col, spin, Vector3(90, 0, 0) if axis_z else Vector3.ZERO)
	for k in 3:
		var a: float = TAU * k / 3.0
		dbox(Vector3(r * 1.9, 0.012, 0.012) if axis_z else Vector3(r * 1.9, 0.012, 0.012), Vector3.ZERO, col.darkened(0.3), spin).rotation = Vector3(0, 0, a) if axis_z else Vector3(0, a, 0)
	dbox(Vector3(0.012, r * 0.5, 0.02), Vector3(0, r * 0.75, 0.015) if axis_z else Vector3(0, 0.015, r * 0.75), Color(0.95, 0.95, 0.9), spin)
	part(StringName(id + "_up"), Vector3(r, r * 2.0, 0.08) if axis_z else Vector3(r * 2.0, 0.08, r), Vector3(r * 0.5, 0, 0.02) if axis_z else Vector3(r * 0.5, 0.02, 0), root)
	part(StringName(id + "_dn"), Vector3(r, r * 2.0, 0.08) if axis_z else Vector3(r * 2.0, 0.08, r), Vector3(-r * 0.5, 0, 0.02) if axis_z else Vector3(-r * 0.5, 0.02, 0), root)
	return root


static func set_wheel(root: Node3D, v: float, axis_z: bool = true) -> void:
	if root == null:
		return
	var spin: Node3D = root.get_node("Spin")
	if axis_z:
		spin.rotation_degrees.z = -270.0 * clampf(v, 0.0, 1.0)
	else:
		spin.rotation_degrees.y = -270.0 * clampf(v, 0.0, 1.0)


## A push button with a lamp. Returns the lamp material.
func button(id: String, pos: Vector3, col: Color, parent: Node3D = null, size: Vector3 = Vector3(0.05, 0.035, 0.02)) -> StandardMaterial3D:
	var mi := dbox(size, pos, col.darkened(0.4), parent, 0.1)
	glow(mi, col, 0.4)
	part(StringName(id), size + Vector3(0.02, 0.02, 0.04), pos + Vector3(0, 0, 0.01), parent)
	return mi.material_override


static func light(m: StandardMaterial3D, c: Color, on: bool) -> void:
	if m == null:
		return
	m.emission_enabled = true
	m.emission = c if on else c * 0.08
	m.emission_energy_multiplier = 1.8 if on else 0.3
	m.albedo_color = c * (0.6 if on else 0.2)


# --------------------------------------------------------------- racks
## A parts rack: `n` slots in a row along local +x. Real items sit in slot
## nodes; occupancy = the slot's child. Clicking an empty slot while
## carrying a matching part stows it (Space = stow / click_part protocol).
class Rack extends Node3D:
	var accepts: Array = []          # item kinds ([] = anything small)
	var slots: Array = []
	var label_txt: String = ""
	var owner_room: Node
	var locked: bool = false         # e.g. a strapped cargo container
	func item_removed(_it: Node) -> bool:
		if locked and owner_room != null and owner_room.has_method("say"):
			owner_room.say("Release its restraint first.")
		return not locked
	func setup(n: int, spacing: float) -> void:
		add_to_group(&"deck_b_rack")
		for i in n:
			var s := Node3D.new()
			s.name = "Slot%d" % i
			s.position = Vector3(i * spacing, 0, 0)
			add_child(s)
			slots.append(s)
	func item_in(i: int) -> Node3D:
		for c in slots[i].get_children():
			if "item_id" in c:
				return c
		return null
	func items() -> Array:
		var out: Array = []
		for i in slots.size():
			var it: Node3D = item_in(i)
			if it != null:
				out.append(it)
		return out
	func count(kind: StringName = &"") -> int:
		var n := 0
		for it in items():
			if kind == &"" or it.item_id == kind:
				n += 1
		return n
	func free_slot() -> int:
		for i in slots.size():
			if item_in(i) == null:
				return i
		return -1
	func slot_index_of(it: Node) -> int:
		for i in slots.size():
			if it.get_parent() == slots[i]:
				return i
		return -1
	func accepts_item(item: Node) -> bool:
		if locked or item == null or not ("item_id" in item) or free_slot() == -1:
			return false
		if item.get("bulky") == true:
			return false
		return accepts.is_empty() or accepts.has(item.item_id)
	func place(item: Node3D, i: int) -> void:
		item.reparent(slots[i], false)
		item.transform = Transform3D.IDENTITY
		item.visible = true
		var c: Node = item.get_node_or_null("Collision")
		if c != null:
			c.disabled = false
		if item is CollisionObject3D:
			(item as CollisionObject3D).collision_layer = 16
		if item.has_method("set_rest_global"):
			item.set_rest_global(item.global_transform, slots[i])
	func persist_place(item: Node3D, i: int) -> bool:
		if i < 0 or i >= slots.size():
			return false
		place(item, i)
		return true
	func stow(item: Node3D) -> bool:
		var i: int = free_slot()
		if i == -1 or not accepts_item(item):
			return false
		place(item, i)
		if owner_room != null and owner_room.has_method("on_rack_stowed"):
			owner_room.on_rack_stowed(self, item)
		return true


func rack(rack_name: String, pos: Vector3, n: int, spacing: float, accepts: Array, title: String, parent: Node3D = null, yaw: float = 0.0, shelf: bool = true) -> Rack:
	var r := Rack.new()
	r.name = rack_name
	r.accepts = accepts
	r.label_txt = title
	r.owner_room = self
	r.position = pos
	r.rotation_degrees.y = yaw
	(parent if parent != null else self).add_child(r)
	r.setup(n, spacing)
	if shelf:
		var w: float = spacing * n
		dbox(Vector3(w + 0.06, 0.02, 0.2), Vector3(w * 0.5 - spacing * 0.5, -0.03 - 0.12, 0), Color(0.4, 0.42, 0.45), r)
		dbox(Vector3(w + 0.06, 0.03, 0.01), Vector3(w * 0.5 - spacing * 0.5, -0.12, 0.1), Color(0.95, 0.72, 0.1), r)
		var tl := text(title, Vector3(w * 0.5 - spacing * 0.5, -0.17, 0.106), 10, Color(0.95, 0.95, 0.9), r)
		tl.name = "RackLabel"
	# The receptacle: one click box over the whole rack.
	var w2: float = spacing * n
	part(StringName("rack_" + rack_name), Vector3(w2 + 0.04, 0.3, 0.24), Vector3(w2 * 0.5 - spacing * 0.5, 0.0, 0.0), r)
	return r


## New physical part (unique, deterministic name from the Deck B counter).
func spawn_part(kind: StringName, into: Rack, pl: Dictionary = {}) -> Node3D:
	var s: Node = sys()
	var nm: String = s.next_part_name(kind) if s != null else "DBPart_%s_%d" % [kind, randi() % 100000]
	var p: StaticBody3D = Part.make(kind, nm, pl)
	var i: int = into.free_slot() if into != null else -1
	if into != null and i != -1:
		into.slots[i].add_child(p)
		into.place(p, i)
	else:
		var inter: Node = get_tree().current_scene.get_node_or_null("Interactables")
		(inter if inter != null else self).add_child(p)
	return p


## Remove a part from the world for good (installed into a machine).
func consume_part(it: Node3D) -> void:
	var carry: Node = _carry()
	if carry != null and carry.is_holding(it):
		carry._carried_item = null
		if "_carried_item_id" in carry:
			carry._carried_item_id = &""
	if it.get_parent() != null:
		it.get_parent().remove_child(it)
	it.queue_free()


func _carry() -> Node:
	var main: Node = _dp.get_parent() if _dp != null else null
	return main.get_node_or_null("Player/CarrySystem") if main != null else null


func held() -> Node3D:
	var c: Node = _carry()
	return c._carried_item if c != null and c.is_carrying() else null


func held_kind() -> StringName:
	var h: Node3D = held()
	return h.item_id if h != null else &""


# Receptacle forwarding for racks (click_part -> owner).
func part_accepts_item(id: StringName, item: Node) -> bool:
	var s: String = String(id)
	if s.begins_with("rack_"):
		var r: Rack = find_child(s.substr(5), true, false) as Rack
		return r != null and r.accepts_item(item)
	return accepts_part(id, item)


func part_stow(id: StringName, item: Node3D) -> bool:
	var s: String = String(id)
	if s.begins_with("rack_"):
		var r: Rack = find_child(s.substr(5), true, false) as Rack
		if r == null or not r.accepts_item(item):
			return false
		var carry: Node = _carry()
		if carry != null and carry.is_holding(item):
			carry._carried_item = null
			if "_carried_item_id" in carry:
				carry._carried_item_id = &""
		r.stow(item)
		sfx(&"click")
		var s2: Node = sys()
		if s2 != null and s2.has_method("note_stow"):
			s2.note_stow(String(r.name), String(item.name), String(room_id))
		return true
	return stow_part(id, item)


func part_stow_hint(id: StringName, item: Node) -> String:
	var s: String = String(id)
	if s.begins_with("rack_"):
		var r: Rack = find_child(s.substr(5), true, false) as Rack
		return "Put %s on %s" % [item.get_display_name() if item.has_method("get_display_name") else "it", r.label_txt.split("\n")[0] if r != null else "the rack"]
	return stow_hint(id, item)


## Overridables for machine receptacles.
func accepts_part(_id: StringName, _item: Node) -> bool:
	return false


func stow_part(_id: StringName, _item: Node3D) -> bool:
	return false


func stow_hint(_id: StringName, _item: Node) -> String:
	return ""


# ---------------------------------------------------------- procedures
## Ordered procedure steps: [{id, text, needs: [ids]}]; done flags saved.
class Procedure extends RefCounted:
	var steps: Array = []
	var done: Dictionary = {}
	func _init(s: Array = []) -> void:
		steps = s
	func reset() -> void:
		done = {}
	func can(id: String) -> String:
		for st in steps:
			if st["id"] == id:
				for nd in st.get("needs", []):
					if not done.get(nd, false):
						return _text_of(nd)
		return ""
	func mark(id: String) -> void:
		done[id] = true
	func is_done(id: String) -> bool:
		return bool(done.get(id, false))
	func next() -> Dictionary:
		for st in steps:
			if not done.get(st["id"], false):
				return st
		return {}
	func count() -> int:
		return done.keys().filter(func(k): return done[k]).size()
	func _text_of(id: String) -> String:
		for st in steps:
			if st["id"] == id:
				return st["text"]
		return id


# ---------------------------------------------------------------- audio
## A machine's running sound at its real position (Deck B layer of the
## world): looping, attenuated with distance, muffled through walls and
## decks by the station's acoustic path (updated a few times a second).
func machine_loop(stream: AudioStream, pos: Vector3, db: float, parent: Node3D = null) -> AudioStreamPlayer3D:
	var ap := AudioStreamPlayer3D.new()
	ap.stream = stream
	ap.position = pos
	ap.volume_db = db
	ap.unit_size = 1.4
	ap.max_distance = 14.0
	ap.attenuation_filter_cutoff_hz = 9000.0
	ap.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	ap.set_meta(&"base_db", db)
	(parent if parent != null else self).add_child(ap)
	_loops.append(ap)
	return ap


func set_loop(ap: AudioStreamPlayer3D, stream: AudioStream, on: bool) -> void:
	if ap == null:
		return
	if stream != null and ap.stream != stream:
		ap.stream = stream
		if on:
			ap.play()
	if on and not ap.playing and ap.is_inside_tree():
		ap.play()
	elif not on and ap.playing:
		ap.stop()


func _update_occlusion(delta: float) -> void:
	_occl_t += delta
	if _occl_t < 0.4 or _loops.is_empty():
		return
	_occl_t = 0.0
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds")
	if snd == null or not snd.has_method("acoustic_path"):
		return
	for ap in _loops:
		if not (ap as AudioStreamPlayer3D).playing:
			continue
		var path: Dictionary = snd.acoustic_path((ap as Node3D).global_position)
		ap.volume_db = float(ap.get_meta(&"base_db", 0.0)) + float(path["wall_db"])
		ap.attenuation_filter_cutoff_hz = float(path["cutoff"])


## Builds a seamless loop of `seconds` from a per-sample generator.
static func loop_stream(seconds: float, gen: Callable) -> AudioStreamWAV:
	var b := Foley._buf(seconds)
	for i in b.size():
		b[i] = float(gen.call(float(i) / Foley.SR, i))
	var s: AudioStreamWAV = Foley.to_wav(b, 0.6)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = b.size()
	return s


# ------------------------------------------------- default task API
func task_rearm(_t: StringName, _seed: int) -> void:
	pass


func task_done(_t: StringName) -> bool:
	return true


func task_next(_t: StringName) -> Dictionary:
	return {}


func task_progress(_t: StringName) -> String:
	return ""


func task_detail(_t: StringName) -> Array:
	return []


func task_feasible(_t: StringName) -> bool:
	return true


func task_severity(_t: StringName) -> int:
	return 1


func next(action: String, short: String) -> Dictionary:
	return {"action": action, "short": short, "room": room_id}
