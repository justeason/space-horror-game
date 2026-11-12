extends Node3D
## Round 49: B-00 VERTICAL ACCESS SHAFT + the SERVICE HOIST.
##
## A pressurised tube between Deck A (a floor hatch in the shaft vestibule
## off Engineering's north wall) and Deck B (it lands in the Lower
## Junction). The station is in MICROGRAVITY: "down" is only the magnetic
## boots' floor plane. In the shaft the boots RELEASE (no floor to hold
## to); the technician moves hand-over-hand on the rungs with the feet
## braced on them, and the boots ENGAGE again on the other deck's floor.
##
## TRAVERSAL = a controlled GRIP-TO-GRIP state (no teleport, no free
## climbing physics): six grip stations, real positions along the tube;
##   0 top landing (Deck A)  1 mount (hands on the hatch stanchions)
##   2 / 3 hand-over-hand    4 bottom (feet on Deck B)  5 bottom landing.
## Each transition is a short animated motion (~1 s) of the camera, both
## hands (reach -> grip on the next rung) and both feet. Controls stay in
## the click / WASD family: CLICK the ladder to start, then W (or a click)
## continues, S reverses, nothing pauses (holding on is safe). The hatch
## lid is pushed open / pulled shut by hand on the way; it is shut whenever
## nobody is in the shaft (the floor stays walkable, nothing can fall).
## INTERRUPTIONS: save mid-shaft stores the nearest landing (never empty
## space); an emergency never drops the climber; abort_to_landing() puts
## the technician safely on the nearest landing; a bulky part cannot be
## carried on the ladder (the SERVICE HOIST carries it).
##
## SERVICE HOIST: a compact sealed component lift in its own column (Deck A
## in Engineering's north wall, Deck B in the Lower Junction's south wall):
## load one part on the tray, press SEND, it arrives on the other deck in
## a few seconds. One item at a time, no duplication (the item itself
## travels; save/load knows where it is).

const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const Foley = preload("res://scripts/audio/foley_synth.gd")
const ClickPart = preload("res://scripts/interactables/click_part.gd")
const STEP_S := 1.05
const LOOK_RANGE := deg_to_rad(70.0)
const RUNG_Z := L.SHAFT_Z + 0.42
const HOIST_TRAVEL_S := 5.0

var climbing: bool = false
var grip: int = 0
var dir: int = 1                    # +1 toward Deck B, -1 toward Deck A
var moving: bool = false
var lid_open: bool = false
var transitions: int = 0           # completed grip-to-grip motions (tests)
var events: Array = []                # [{t, event}] (tests)
var _t: float = 0.0
var _from: int = 0
var _to: int = 0
var _lid_hinge: Node3D
var _lid_angle: float = 0.0
var _status_lamp: StandardMaterial3D
var _status_label: Label3D
var _grips: Array = []
var _prompt_owner: bool = false
var _queued: int = 0                # buffered continue presses
var _saved_interact: bool = true
var _rungs_y: Array = []
# Hoist
var hoist_item: Node3D = null
var hoist_at: String = "A"          # where the cage (and its item) is: A | B | moving
var _hoist_t: float = 0.0
var _hoist_to: String = "A"
var _tray := {}                     # "A"/"B" -> Node3D
var _hoist_lamps := {}
signal climb_finished(deck: String)


func _ready() -> void:
	add_to_group(&"vertical_shaft")
	add_to_group(&"r35_equipment")
	_build_tube()
	_build_top()
	_build_hoist()
	_make_grips()
	_refresh_status()


# ------------------------------------------------------------- geometry
func _box(size: Vector3, pos: Vector3, c: Color, layers: int, collide: bool, parent: Node3D = null, metal: float = 0.5, emit: Color = Color(0, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
	if emit != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 1.6
	mi.material_override = m
	mi.layers = layers
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func _cyl(r: float, h: float, pos: Vector3, c: Color, layers: int, rot: Vector3 = Vector3.ZERO, parent: Node3D = null, metal: float = 0.7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.35
	mi.material_override = m
	mi.layers = layers
	mi.position = pos
	mi.rotation_degrees = rot
	(parent if parent != null else self).add_child(mi)
	return mi


func _build_tube() -> void:
	var top: float = -0.2
	var bottom: float = L.FLOOR_Y
	var n := 14
	var r_mid: float = L.SHAFT_R + 0.06
	var w: float = 2.0 * r_mid * tan(PI / n) + 0.02
	var wall := Color(0.3, 0.32, 0.35)
	for k in n:
		var a: float = TAU * float(k) / float(n)
		var dirv := Vector3(cos(a), 0, sin(a))
		# The bottom opening faces EAST (+x) into the Lower Junction.
		var opening: bool = absf(wrapf(a, -PI, PI)) < 0.62
		var y0: float = bottom + (L.DOOR_H if opening else 0.0)
		var h: float = top - y0
		var mi := _box(Vector3(0.06, h, w), Vector3(L.SHAFT_X, (top + y0) * 0.5, L.SHAFT_Z) + dirv * r_mid, wall, L.LAYER, true)
		mi.rotation.y = -a
	# Exit frame + sign at the bottom opening.
	var ex: float = L.SHAFT_X + r_mid + 0.02
	_box(Vector3(0.1, 0.08, 0.95), Vector3(ex, bottom + L.DOOR_H, L.SHAFT_Z), Color(0.95, 0.72, 0.1), L.LAYER, false)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.1, L.DOOR_H, 0.06), Vector3(ex, bottom + L.DOOR_H * 0.5, L.SHAFT_Z + s * 0.45), Color(0.45, 0.47, 0.5), L.LAYER, false)
	_label("B-00  VERTICAL ACCESS\n▲ DECK A · ENGINEERING", Vector3(ex + 0.06, bottom + L.DOOR_H + 0.22, L.SHAFT_Z), -90.0, 16, L.LAYER)
	# Rungs (north side) and the two side rails.
	var y: float = bottom + 0.3
	while y < top - 0.15:
		_cyl(0.016, 0.42, Vector3(L.SHAFT_X, y, RUNG_Z), Color(0.75, 0.76, 0.78), L.LAYER, Vector3(0, 0, 90))
		_rungs_y.append(y)
		y += 0.3
	for s in [-1.0, 1.0]:
		_cyl(0.022, top - bottom, Vector3(L.SHAFT_X + s * 0.22, (top + bottom) * 0.5, RUNG_Z + 0.02), Color(0.55, 0.56, 0.58), L.LAYER)
	# Safety light strips + directional stencils + a small access panel.
	for s in [-1.0, 1.0]:
		var a2: float = PI * 0.5 + s * 1.1
		var p := Vector3(L.SHAFT_X, (top + bottom) * 0.5 + 0.4, L.SHAFT_Z) + Vector3(cos(a2), 0, sin(a2)) * (L.SHAFT_R + 0.02)
		_box(Vector3(0.025, (top - bottom) - 2.6, 0.025), p, Color(0.9, 0.95, 1.0), L.LAYER, false, null, 0.0, Color(0.85, 0.92, 1.0))
	_label("DECK A ▲", Vector3(L.SHAFT_X - 0.38, -1.0, L.SHAFT_Z + 0.24), 125.0, 18, L.LAYER)
	_label("DECK B ▼", Vector3(L.SHAFT_X - 0.38, -2.4, L.SHAFT_Z + 0.24), 125.0, 18, L.LAYER)
	_label("HOLD THE RAIL · BOOTS RELEASE IN THE SHAFT", Vector3(L.SHAFT_X - 0.36, -1.6, L.SHAFT_Z - 0.25), 55.0, 12, L.LAYER)
	_box(Vector3(0.02, 0.3, 0.24), Vector3(L.SHAFT_X - L.SHAFT_R - 0.02, -1.9, L.SHAFT_Z - 0.18), Color(0.4, 0.42, 0.45), L.LAYER, false)
	# A small fill light in the inter-deck section (range < its depth below
	# Deck A's floor: it cannot reach the vestibule above).
	var fill := OmniLight3D.new()
	fill.position = Vector3(L.SHAFT_X, -0.75, L.SHAFT_Z - 0.15)
	fill.omni_range = 0.85
	fill.light_energy = 0.9
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)
	# Downward lights inside the tube (a downward cone never reaches Deck A).
	for yy in [-0.35, -2.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(L.SHAFT_X, yy, L.SHAFT_Z - 0.1)
		sl.rotation_degrees.x = -90.0
		sl.spot_angle = 60.0
		sl.spot_range = 2.4
		sl.light_energy = 1.1
		sl.light_color = Color(0.85, 0.9, 1.0)
		add_child(sl)


func _label(text: String, pos: Vector3, yaw: float, size: int, layers: int, col: Color = Color(0.95, 0.92, 0.75)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0011
	l.modulate = col
	l.outline_size = 3
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = pos
	l.rotation_degrees.y = yaw
	l.layers = layers
	add_child(l)
	return l


## Deck A: the hatch, its coaming, the two grab stanchions (the ladder rails
## continue 1 m above the floor so the technician has something to hold
## while stepping on and off), the status lamp and signs.
func _build_top() -> void:
	var c := Vector3(L.SHAFT_X, 0.0, L.SHAFT_Z)
	var hh: float = L.HATCH_HALF
	for e in [[Vector3(0, 0.012, -hh - 0.04), Vector3(hh * 2 + 0.16, 0.024, 0.08)], [Vector3(0, 0.012, hh + 0.04), Vector3(hh * 2 + 0.16, 0.024, 0.08)],
			[Vector3(-hh - 0.04, 0.012, 0), Vector3(0.08, 0.024, hh * 2)], [Vector3(hh + 0.04, 0.012, 0), Vector3(0.08, 0.024, hh * 2)]]:
		_box(e[1], c + e[0], Color(0.95, 0.72, 0.1), 1, false)
	# The lid, hinged on its WEST edge.
	_lid_hinge = Node3D.new()
	_lid_hinge.name = "HatchLidHinge"
	_lid_hinge.position = c + Vector3(-hh, 0.0, 0.0)
	add_child(_lid_hinge)
	var lid := _box(Vector3(hh * 2 - 0.02, 0.05, hh * 2 - 0.02), Vector3(hh, -0.025, 0), Color(0.42, 0.44, 0.47), 1, true, _lid_hinge)
	lid.name = "HatchLid"
	_cyl(0.14, 0.03, Vector3(hh, 0.012, 0), Color(0.2, 0.21, 0.22), 1, Vector3.ZERO, _lid_hinge)
	_box(Vector3(0.18, 0.025, 0.03), Vector3(hh, 0.03, 0), Color(0.75, 0.6, 0.15), 1, false, _lid_hinge)
	_label_on(_lid_hinge, "B-00 ▼  LOWER SERVICE DECK", Vector3(hh, 0.004, -0.3), 15)
	# Grab stanchions (the rails above the floor) with a top bar.
	for s in [-1.0, 1.0]:
		_cyl(0.022, 1.05, Vector3(L.SHAFT_X + s * 0.22, 0.525, RUNG_Z + 0.02), Color(0.95, 0.72, 0.1), 1)
	_cyl(0.02, 0.46, Vector3(L.SHAFT_X, 1.05, RUNG_Z + 0.02), Color(0.95, 0.72, 0.1), 1, Vector3(0, 0, 90))
	# Status lamp + sign on the vestibule's north wall.
	var lamp := _box(Vector3(0.07, 0.07, 0.03), Vector3(L.SHAFT_X + 0.42, 1.7, L.VESTIBULE.end.y - 0.12), Color(0.2, 0.2, 0.2), 1, false, null, 0.0, Color(1, 0.2, 0.1))
	_status_lamp = lamp.material_override
	_status_label = _label("", Vector3(L.SHAFT_X - 0.05, 1.95, L.VESTIBULE.end.y - 0.115), 180.0, 18, 1)
	# Click targets: the ladder from the top landing, and from the bottom.
	var top_part: StaticBody3D = ClickPart.make(self, &"climb_down", Vector3(0.9, 1.1, 0.6), self, Vector3(L.SHAFT_X, 0.55, L.SHAFT_Z + 0.2))
	top_part.name = "Click_climb_down"
	var bot_part: StaticBody3D = ClickPart.make(self, &"climb_up", Vector3(0.1, 1.9, 0.7), self, Vector3(L.SHAFT_X + L.SHAFT_R - 0.05, L.FLOOR_Y + 1.0, L.SHAFT_Z))
	bot_part.name = "Click_climb_up"


func _label_on(parent: Node3D, text: String, pos: Vector3, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0011
	l.modulate = Color(0.08, 0.08, 0.08)
	l.position = pos
	l.rotation_degrees.x = -90.0
	parent.add_child(l)


# ------------------------------------------------------------------ hoist
func _build_hoist() -> void:
	var hx: float = L.HOIST_X
	var hz: float = L.HOIST_Z
	# Deck A housing (in Engineering, against the north wall, door south).
	var a := Node3D.new()
	a.name = "HoistDeckA"
	a.position = Vector3(hx, 0.0, hz - 0.03)
	add_child(a)
	_box(Vector3(0.44, 1.25, 0.4), Vector3(0, 0.625, 0.02), Color(0.38, 0.4, 0.43), 1, true, a)
	_box(Vector3(0.34, 0.36, 0.02), Vector3(0, 0.82, -0.19), Color(0.08, 0.09, 0.1), 1, false, a)
	_box(Vector3(0.46, 0.05, 0.42), Vector3(0, 1.27, 0.02), Color(0.95, 0.72, 0.1), 1, false, a)
	_label_on_wall(a, "SERVICE HOIST\nDECK A ⇅ DECK B\nONE PART · 15 kg MAX", Vector3(0, 1.12, -0.205), 11, 1)
	_tray["A"] = _hoist_tray(a, Vector3(0, 0.74, -0.08), "A", 1)
	part_at(a, &"hoist_send_A", Vector3(0.1, 0.07, 0.05), Vector3(0.14, 0.52, -0.21))
	_hoist_lamps["A"] = _hoist_button_visual(a, Vector3(0.14, 0.52, -0.205), 1)
	# Deck B column (in the Lower Junction's south wall, door north).
	var b := Node3D.new()
	b.name = "HoistDeckB"
	b.position = Vector3(hx, L.FLOOR_Y, hz + 0.05)
	add_child(b)
	var col_h: float = -0.9 - L.FLOOR_Y
	_box(Vector3(0.44, col_h, 0.36), Vector3(0, col_h * 0.5, -0.06), Color(0.36, 0.38, 0.41), L.LAYER, true, b)
	_box(Vector3(0.34, 0.36, 0.02), Vector3(0, 0.82, 0.13), Color(0.08, 0.09, 0.1), L.LAYER, false, b)
	_label_on_wall(b, "SERVICE HOIST\nDECK B ⇅ DECK A", Vector3(0, 1.12, 0.125), 11, L.LAYER, 180.0)
	_tray["B"] = _hoist_tray(b, Vector3(0, 0.74, 0.06), "B", L.LAYER)
	part_at(b, &"hoist_send_B", Vector3(0.1, 0.07, 0.05), Vector3(-0.14, 0.52, 0.14))
	_hoist_lamps["B"] = _hoist_button_visual(b, Vector3(-0.14, 0.52, 0.135), L.LAYER)


func _label_on_wall(parent: Node3D, text: String, pos: Vector3, size: int, layers: int, yaw: float = 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.001
	l.modulate = Color(0.95, 0.92, 0.75)
	l.outline_size = 3
	l.position = pos
	l.rotation_degrees.y = yaw + (180.0 if yaw == 0.0 else 0.0)
	l.layers = layers
	parent.add_child(l)


func _hoist_tray(parent: Node3D, pos: Vector3, which: String, layers: int) -> Node3D:
	var t := Node3D.new()
	t.name = "HoistTray" + which
	t.position = pos
	parent.add_child(t)
	_box(Vector3(0.3, 0.015, 0.22), Vector3(0, -0.09, 0), Color(0.55, 0.56, 0.58), layers, false, t)
	var p: StaticBody3D = ClickPart.make(self, StringName("hoist_tray_" + which), Vector3(0.3, 0.2, 0.22), t, Vector3.ZERO)
	p.name = "Click_hoist_tray_" + which
	return t


func _hoist_button_visual(parent: Node3D, pos: Vector3, layers: int) -> StandardMaterial3D:
	var mi := _box(Vector3(0.08, 0.05, 0.015), pos, Color(0.15, 0.3, 0.15), layers, false, parent, 0.0, Color(0.3, 0.9, 0.4))
	return mi.material_override


func part_at(parent: Node3D, id: StringName, size: Vector3, pos: Vector3) -> StaticBody3D:
	return ClickPart.make(self, id, size, parent, pos)


# -------------------------------------------------------------- grips
func _make_grips() -> void:
	var sx: float = L.SHAFT_X
	var sz: float = L.SHAFT_Z
	var z_on: float = sz + 0.12
	_grips = [
		{"eye": Vector3(sx, 1.6, sz - 0.82), "yaw": PI, "deck": "A"},
		{"eye": Vector3(sx, 1.0, z_on), "yaw": PI, "deck": "shaft"},
		{"eye": Vector3(sx, -0.2, z_on), "yaw": PI, "deck": "shaft"},
		{"eye": Vector3(sx, -1.4, z_on), "yaw": PI, "deck": "shaft"},
		{"eye": Vector3(sx, L.EYE_Y, z_on), "yaw": PI, "deck": "shaft"},
		{"eye": Vector3(sx + 0.92, L.EYE_Y, sz), "yaw": -PI * 0.5, "deck": "B"},
	]


func grip_eye(i: int) -> Vector3:
	return _grips[i]["eye"]


func grip_count() -> int:
	return _grips.size()


## The nearest SAFE standing place (a landing) to the climber.
func safe_landing() -> Vector3:
	if not climbing:
		return Vector3.INF
	var eye: Vector3 = _player().global_position if _player() != null else grip_eye(0)
	return grip_eye(0) if eye.y > (L.EYE_Y + 1.6) * 0.5 else grip_eye(5)


func is_climbing() -> bool:
	return climbing


# ------------------------------------------------------------- access
func _clearance() -> Node:
	return get_tree().get_first_node_in_group(&"clearance") if is_inside_tree() else null


func deck_b_open() -> bool:
	var c: Node = _clearance()
	return c == null or (c.has_method("deck_b_tier") and int(c.deck_b_tier()) >= 1)


func _refresh_status() -> void:
	var open: bool = deck_b_open()
	if _status_lamp != null:
		var c: Color = Color(0.25, 0.95, 0.4) if open else Color(1.0, 0.18, 0.12)
		_status_lamp.albedo_color = c
		_status_lamp.emission = c
	if _status_label != null:
		_status_label.text = "B-00  LOWER SERVICE DECK\n%s" % ("CLEARED · TECH-1" if open else "ACCESS RESTRICTED")
		_status_label.modulate = Color(0.75, 1.0, 0.8) if open else Color(1.0, 0.55, 0.45)


func _main() -> Node:
	var n: Node = self
	while n != null and n.get_node_or_null("Player") == null:
		n = n.get_parent()
	return n


func _player() -> Node3D:
	var m: Node = _main()
	return m.get_node_or_null("Player") as Node3D if m != null else null


func _carry() -> Node:
	var m: Node = _main()
	return m.get_node_or_null("Player/CarrySystem") if m != null else null


func _say(text: String) -> void:
	var m: Node = _main()
	var ml: Label = m.get_node_or_null("Player/HUD/TaskMessageLabel") as Label if m != null else null
	preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), text, 3.0)


## Why a climb cannot start now ("" = it can).
func refusal(down: bool) -> String:
	if climbing:
		return "already in the shaft"
	if down and not deck_b_open():
		return "ACCESS RESTRICTED — LOWER SERVICE DECK (specialist clearance required)"
	var m: Node = _main()
	var carry: Node = _carry()
	if carry != null and carry.is_carrying():
		var it: Object = carry._carried_item
		if it != null and it.get("bulky") == true:
			return "Too bulky to carry on the ladder — send it on the SERVICE HOIST."
	if m != null:
		var body: Node = m.get_node_or_null("Player/PlayerBody")
		if body != null and body.get("eva_suit") == true:
			return "Stow the EVA suit before using the shaft."
		var ss: Node = m.get_node_or_null("SleepState")
		if ss != null and ss.has_method("is_sitting") and (ss.is_sitting() or ss.is_laptop_open()):
			return "Stand up first."
		var ws: Node = m.get_node_or_null("WorkstationState")
		if ws != null and ws.has_method("is_in_use") and ws.is_in_use():
			return "Step away from the workstation first."
	return ""


# ------------------------------------------------------------ clicks
func on_part(id: StringName) -> void:
	match String(id):
		"climb_down":
			begin(true)
		"climb_up":
			begin(false)
		"hoist_send_A":
			hoist_send("A")
		"hoist_send_B":
			hoist_send("B")
		"hoist_tray_A", "hoist_tray_B":
			var which: String = String(id).right(1)
			if hoist_item != null and hoist_at == which:
				var carry: Node = _carry()
				if carry != null and not carry.is_carrying() and hoist_item.has_method("interact"):
					var it: Node3D = hoist_item
					hoist_item = null
					it.interact()
					_play(&"hoist_latch", _tray[which].global_position)
			elif hoist_at == "moving":
				_say("The hoist is travelling.")
			else:
				_say("Hoist tray %s is empty. Carry a part here and press Space to load it." % which)


func part_prompt(id: StringName) -> String:
	match String(id):
		"climb_down":
			if climbing:
				return ""
			var r: String = refusal(true)
			return "Click: Climb down to Deck B (Lower Service Deck)" if r == "" else r
		"climb_up":
			if climbing:
				return ""
			var r2: String = refusal(false)
			return "Click: Climb up to Deck A (Engineering)" if r2 == "" else r2
		"hoist_send_A", "hoist_send_B":
			var which: String = String(id).right(1)
			if hoist_at == "moving":
				return "Hoist travelling…"
			if hoist_item != null and hoist_at == which:
				return "Click: SEND %s to Deck %s" % [_name_of(hoist_item), "B" if which == "A" else "A"]
			if hoist_at != which:
				return "Click: CALL the hoist to Deck %s" % which
			return "Hoist here (tray empty)"
		"hoist_tray_A", "hoist_tray_B":
			var w2: String = String(id).right(1)
			if hoist_item != null and hoist_at == w2:
				return "Click: Take %s from the hoist" % _name_of(hoist_item)
			return "Hoist tray (load a part: Space)" if hoist_at == w2 else ""
	return ""


func _name_of(it: Node) -> String:
	return it.get_display_name() if it != null and it.has_method("get_display_name") else "part"


# Carry protocol (the trays are receptacles).
func part_accepts_item(id: StringName, item: Node) -> bool:
	var which: String = String(id).right(1)
	return String(id).begins_with("hoist_tray_") and hoist_item == null and hoist_at == which and item != null and not item.has_method("is_carrier")


func part_stow(id: StringName, item: Node3D) -> bool:
	if not part_accepts_item(id, item):
		return false
	var which: String = String(id).right(1)
	var carry: Node = _carry()
	if carry != null and carry.is_holding(item):
		carry._carried_item = null
		if "_carried_item_id" in carry:
			carry._carried_item_id = &""
	put_on_tray(item, which)
	_play(&"hoist_latch", _tray[which].global_position)
	return true


func part_stow_hint(id: StringName, _item: Node) -> String:
	return "Load hoist tray %s" % String(id).right(1)


func put_on_tray(item: Node3D, which: String) -> void:
	hoist_item = item
	hoist_at = which
	item.reparent(_tray[which], false)
	item.transform = Transform3D(Basis(), Vector3(0, -0.04, 0))
	item.visible = true
	var c: Node = item.get_node_or_null("Collision")
	if c != null:
		c.disabled = false
	if item is CollisionObject3D:
		(item as CollisionObject3D).collision_layer = 16
	if item.has_method("set_rest_global"):
		item.set_rest_global(item.global_transform, _tray[which])


func hoist_send(from: String) -> void:
	if hoist_at == "moving":
		return
	if hoist_at != from:
		# Call the empty (or loaded) cage to this deck.
		_hoist_to = from
	else:
		_hoist_to = "B" if from == "A" else "A"
	hoist_at = "moving"
	_hoist_t = 0.0
	if hoist_item != null:
		hoist_item.visible = false
	_play(&"hoist_motor", _tray[from].global_position)
	events.append({"t": Time.get_ticks_msec(), "event": "hoist_send_" + _hoist_to})


func _tick_hoist(delta: float) -> void:
	for k in _hoist_lamps:
		var m: StandardMaterial3D = _hoist_lamps[k]
		var on: bool = hoist_at == "moving" and int(Time.get_ticks_msec() / 300) % 2 == 0
		m.emission = Color(1.0, 0.7, 0.2) if on else (Color(0.3, 0.9, 0.4) if hoist_at == k else Color(0.1, 0.2, 0.1))
	if hoist_at != "moving":
		return
	_hoist_t += delta
	if _hoist_t >= HOIST_TRAVEL_S:
		hoist_at = _hoist_to
		if hoist_item != null:
			put_on_tray(hoist_item, hoist_at)
		_play(&"hoist_latch", _tray[hoist_at].global_position)
		events.append({"t": Time.get_ticks_msec(), "event": "hoist_arrived_" + hoist_at})


# ------------------------------------------------------------- climbing
## Start a climb from the landing the technician is on.
func begin(down: bool) -> bool:
	var r: String = refusal(down)
	if r != "":
		_say(r)
		return false
	var m: Node = _main()
	var player: Node3D = _player()
	if m == null or player == null:
		return false
	climbing = true
	grip = 0 if down else 5
	dir = 1 if down else -1
	moving = false
	_queued = 1
	var fb: Node = m.get_node_or_null("FreeMoveBody")
	if fb != null:
		fb.velocity = Vector3.ZERO
		fb.set_active(false)
	var gfm: Node = m.get_node_or_null("GlobalFreeMove")
	if gfm != null:
		gfm.mirror_enabled = false
	var ic: Node = m.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D")
	if ic != null and "interactions_enabled" in ic:
		_saved_interact = ic.interactions_enabled
		ic.interactions_enabled = false
	_prompt("W / click: climb %s     S: back" % ("down" if down else "up"))
	events.append({"t": Time.get_ticks_msec(), "event": "begin_" + ("down" if down else "up")})
	_play(&"boot_release", player.global_position + Vector3(0, -1.5, 0))
	var dp: Node = m.get_node_or_null("DayPlan")
	if dp != null and dp.has_method("log_event"):
		dp.log_event("Vertical access shaft: climbing %s" % ("down to Deck B" if down else "up to Deck A"))
	return true


func _prompt(text: String) -> void:
	var m: Node = _main()
	var lab: Label = m.get_node_or_null("Player/HUD/InteractionPrompt") as Label if m != null else null
	if lab == null:
		var ic: Node = m.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") if m != null else null
		lab = ic.get("_prompt_label") as Label if ic != null else null
	if lab != null:
		lab.text = text
		lab.visible = text != ""


## Developer / tests / save safety: put the climber on the nearest landing.
func abort_to_landing() -> void:
	if not climbing:
		return
	var land: int = 0 if safe_landing() == grip_eye(0) else 5
	grip = land
	_finish(land)


## Continue one grip in the current direction (buffered).
func step(direction: int = 0) -> void:
	if not climbing:
		return
	if direction != 0 and direction != dir:
		dir = direction
		_queued = 0
	_queued = mini(_queued + 1, 2)


func _unhandled_input(event: InputEvent) -> void:
	if not climbing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		step(0)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S:
			step(-dir)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_W:
			step(0)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick_hoist(delta)
	_animate_lid(delta)
	if Engine.get_process_frames() % 30 == 0:
		_refresh_status()
	if not climbing:
		return
	var player: Node3D = _player()
	if player == null:
		return
	if not moving:
		# Holding W keeps going (one motion at a time).
		if Input.is_key_pressed(KEY_W) and _queued == 0:
			_queued = 1
		if _queued > 0:
			var nxt: int = grip + dir
			if nxt < 0 or nxt >= _grips.size():
				_queued = 0
				return
			_queued -= 1
			_start_motion(grip, nxt)
		else:
			_apply_pose(float(grip), 0.0)
	if moving:
		_t += delta / STEP_S
		var t: float = clampf(_t, 0.0, 1.0)
		var e: float = t * t * (3.0 - 2.0 * t)
		var a: Vector3 = grip_eye(_from)
		var b: Vector3 = grip_eye(_to)
		var p: Vector3 = a.lerp(b, e)
		# Mount / dismount arcs: over the coaming, out of the tube.
		if (_from == 0 and _to == 1) or (_from == 1 and _to == 0):
			p.y += sin(e * PI) * 0.12
		player.global_position = p
		_face(lerp_angle(float(_grips[_from]["yaw"]), float(_grips[_to]["yaw"]), e), delta)
		_apply_pose(lerpf(float(_from), float(_to), e), sin(t * PI))
		if _t >= 1.0:
			moving = false
			grip = _to
			transitions += 1
			_arrive(_to)
	else:
		_face(float(_grips[grip]["yaw"]), delta)


func _start_motion(a: int, b: int) -> void:
	_from = a
	_to = b
	_t = 0.0
	moving = true
	var mid: Vector3 = (grip_eye(a) + grip_eye(b)) * 0.5
	# The lid: pushed open on the way in / up, pulled shut once below it.
	if (a == 0 and b == 1) or (a == 2 and b == 1):
		set_lid(true)
	if a == 2 and b == 3 and lid_open:
		set_lid(false)
	_play(&"grip", mid + Vector3(0, -0.2, 0.35))
	_play(&"rung", mid + Vector3(0, -1.2, 0.35))
	if b in [2, 3, 4] or a in [2, 3, 4]:
		_play(&"cloth", mid)
	events.append({"t": Time.get_ticks_msec(), "event": "motion_%d_%d" % [a, b]})


func _arrive(i: int) -> void:
	events.append({"t": Time.get_ticks_msec(), "event": "grip_%d" % i})
	if i == 0 or i == 5:
		_finish(i)
	elif i == 4 and dir > 0:
		_play(&"boot_engage", grip_eye(4) + Vector3(0, -1.55, 0))
	elif i == 1 and dir < 0:
		_play(&"creak", grip_eye(1))


func _finish(i: int) -> void:
	var m: Node = _main()
	var player: Node3D = _player()
	climbing = false
	moving = false
	_queued = 0
	if player != null:
		player.global_position = grip_eye(i)
	set_lid(false)
	if m != null:
		var fb: Node = m.get_node_or_null("FreeMoveBody")
		if fb != null and player != null:
			fb.sync_to_eye_position(player.global_position)
			fb.set_active(true)
		var gfm: Node = m.get_node_or_null("GlobalFreeMove")
		if gfm != null:
			gfm.mirror_enabled = true
		var ic: Node = m.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D")
		if ic != null and "interactions_enabled" in ic:
			ic.interactions_enabled = _saved_interact
	_clear_pose()
	_prompt("")
	if i == 5 or i == 0:
		_play(&"boot_engage", grip_eye(i) + Vector3(0, -1.55, 0))
	var deck: String = "B" if i == 5 else "A"
	events.append({"t": Time.get_ticks_msec(), "event": "landed_" + deck})
	if deck == "B":
		get_tree().call_group(&"deck_b_systems", &"on_player_arrived_deck_b")
	climb_finished.emit(deck)


func _face(yaw: float, delta: float) -> void:
	var player: Node3D = _player()
	if player == null:
		return
	var lp: Node3D = player.get_node_or_null("LookPivot")
	if lp == null:
		return
	var want: float = wrapf(yaw - player.rotation.y, -PI, PI)
	var cur: float = lp.rotation.y
	var off: float = wrapf(cur - want, -PI, PI)
	if moving:
		# Ease the view toward the climbing direction during a motion.
		off = move_toward(off, 0.0, delta * 2.2)
	off = clampf(off, -LOOK_RANGE, LOOK_RANGE)
	lp.rotation.y = want + off
	if "_target_yaw" in lp:
		lp._target_yaw = lp.rotation.y


func set_lid(open: bool) -> void:
	if open == lid_open:
		return
	lid_open = open
	_play(&"hatch_open" if open else &"hatch_close", Vector3(L.SHAFT_X, 0.0, L.SHAFT_Z))


func _animate_lid(delta: float) -> void:
	var goal: float = 100.0 if lid_open else 0.0
	_lid_angle = move_toward(_lid_angle, goal, delta * 160.0)
	if _lid_hinge != null:
		_lid_hinge.rotation_degrees.z = _lid_angle


# ------------------------------------------------------------- the body
## Hands on rungs / stanchions and feet braced on rungs for a position
## along the grip chain (fractional during a motion). `swing` 0..1 lifts
## the moving hand / foot off its hold mid-motion.
func _apply_pose(gpos: float, swing: float) -> void:
	var m: Node = _main()
	var body: Node = m.get_node_or_null("Player/PlayerBody") if m != null else null
	if body == null or not body.has_method("set_climb_pose"):
		return
	var player: Node3D = _player()
	var eye: Vector3 = player.global_position
	var on_ladder: float = clampf(minf(gpos, 5.0 - gpos), 0.0, 1.0)
	if on_ladder <= 0.001:
		body.set_climb_pose({})
		return
	var lead_right: bool = int(floor(gpos)) % 2 == 0
	var hands: Array = []
	for s in [-1.0, 1.0]:
		var is_right: bool = s > 0.0
		var hy: float = eye.y - (0.32 if is_right == lead_right else 0.58)
		var hold := Vector3(L.SHAFT_X + s * 0.12, _snap_rung(hy, 1.05), RUNG_Z - 0.02)
		if is_right == lead_right and swing > 0.0:
			hold += Vector3(0, swing * 0.12, -swing * 0.1)
		hands.append(hold)
	var feet: Array = []
	for s in [-1.0, 1.0]:
		var is_right2: bool = s > 0.0
		var fy: float = eye.y - (1.38 if is_right2 != lead_right else 1.12)
		var f := Vector3(L.SHAFT_X + s * 0.1, maxf(_snap_rung(fy, -0.25), L.FLOOR_Y + 0.08), RUNG_Z - 0.12)
		if is_right2 != lead_right and swing > 0.0:
			f += Vector3(0, swing * 0.1, -swing * 0.06)
		feet.append(f)
	body.set_climb_pose({"hand_l": hands[0], "hand_r": hands[1], "foot_l": feet[0], "foot_r": feet[1], "blend": on_ladder})


func _snap_rung(y: float, top_hold: float) -> float:
	if y > -0.25:
		return minf(maxf(y, -0.2), top_hold)       # the stanchions above the floor
	var best: float = y
	var bd: float = INF
	for r in _rungs_y:
		if absf(float(r) - y) < bd:
			bd = absf(float(r) - y)
			best = float(r)
	return best


func _clear_pose() -> void:
	var m: Node = _main()
	var body: Node = m.get_node_or_null("Player/PlayerBody") if m != null else null
	if body != null and body.has_method("set_climb_pose"):
		body.set_climb_pose({})


# --------------------------------------------------------------- sounds
static var _streams: Dictionary = {}


static func stream(kind: StringName) -> AudioStream:
	if _streams.has(kind):
		return _streams[kind]
	var b: PackedFloat32Array
	match kind:
		&"grip":
			b = Foley._buf(0.22)
			Foley._contact(b, 0.0, 0.05, 1100.0, 1.1, 0.5, 11)
			Foley._modes(b, 0.004, [[310.0, 0.035, 0.25], [760.0, 0.03, 0.18]])
		&"rung":
			b = Foley._buf(0.5)
			Foley._contact(b, 0.0, 0.02, 2400.0, 1.5, 0.5, 12)
			Foley._modes(b, 0.002, [[640.0, 0.11, 0.5], [1470.0, 0.07, 0.28], [2590.0, 0.035, 0.14]])
		&"boot_release", &"boot_engage":
			b = Foley._buf(0.45)
			var up: bool = kind == &"boot_engage"
			for i in b.size():
				var t: float = float(i) / Foley.SR
				if t < 0.18:
					var f: float = lerpf(90.0, 180.0, t / 0.18) if up else lerpf(180.0, 90.0, t / 0.18)
					b[i] += sin(TAU * f * t) * 0.25 * (1.0 - t / 0.18)
			Foley._contact(b, 0.16 if up else 0.0, 0.03, 600.0, 1.2, 0.7, 13)
			Foley._modes(b, 0.16 if up else 0.0, [[220.0, 0.05, 0.4], [540.0, 0.03, 0.2]])
		&"cloth":
			b = Foley._buf(0.35)
			Foley._shaped(b, 0.0, 0.35, 2600.0, 0.7, 0.25, 14, func(u, _t): return sin(u * PI) * (0.6 + 0.4 * sin(u * 31.0)))
		&"creak":
			b = Foley._buf(0.7)
			Foley._modes(b, 0.0, [[96.0, 0.3, 0.4], [143.0, 0.22, 0.25], [311.0, 0.08, 0.1]])
		&"hatch_open", &"hatch_close":
			b = Foley._buf(0.9)
			Foley._contact(b, 0.0, 0.03, 900.0, 1.0, 0.8, 15)
			Foley._modes(b, 0.0, [[180.0, 0.08, 0.6], [420.0, 0.06, 0.3]])
			Foley._shaped(b, 0.08, 0.6, 340.0, 2.0, 0.15, 16, func(u, _t): return sin(u * PI))
			if kind == &"hatch_close":
				Foley._contact(b, 0.62, 0.04, 500.0, 1.0, 1.0, 17)
				Foley._modes(b, 0.62, [[150.0, 0.12, 0.8], [380.0, 0.08, 0.4]])
		&"hoist_motor":
			b = Foley._buf(HOIST_TRAVEL_S)
			for i in b.size():
				var t2: float = float(i) / Foley.SR
				var env: float = minf(t2 / 0.4, 1.0) * minf((HOIST_TRAVEL_S - t2) / 0.5, 1.0)
				b[i] = (sin(TAU * 118.0 * t2) * 0.4 + sin(TAU * 236.0 * t2) * 0.15) * env
			Foley._shaped(b, 0.0, HOIST_TRAVEL_S, 900.0, 1.0, 0.08, 18, func(_u, _t): return 1.0)
		&"hoist_latch":
			b = Foley._buf(0.4)
			Foley._contact(b, 0.0, 0.02, 1600.0, 1.2, 0.8, 19)
			Foley._modes(b, 0.0, [[520.0, 0.06, 0.4], [1240.0, 0.04, 0.2]])
		_:
			return null
	var s: AudioStream = Foley.to_wav(b, 0.7)
	_streams[kind] = s
	return s


func _play(kind: StringName, pos: Vector3) -> void:
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds") if is_inside_tree() else null
	if snd != null and snd.has_method("play_custom"):
		snd.play_custom(StringName("shaft_" + String(kind)), stream(kind), pos)


# ------------------------------------------------------------ save/load
func state_dict() -> Dictionary:
	return {"hoist_at": hoist_at if hoist_at != "moving" else _hoist_to, "hoist_item": String(hoist_item.get_meta(&"persist_id", hoist_item.name)) if hoist_item != null else ""}


func load_dict(d: Dictionary) -> void:
	var at: String = String(d.get("hoist_at", "A"))
	hoist_at = at if at in ["A", "B"] else "A"
	# The item itself is restored by SaveGame (owner kind "hoist").
	climbing = false
	moving = false
	lid_open = false
	_lid_angle = 0.0
	_refresh_status()
