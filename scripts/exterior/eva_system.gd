extends Node
## Round 38/39: EVA. Round 39 Priority 6 replaced the Round 38 "click and
## appear outside, then walk the walkway on mag boots" with:
##   1. SUIT LOCKER (airlock tunnel): the technician visibly puts the suit
##      on (player_body set_eva_suit: white suit, pack, helmet + gold visor
##      in the mirror / on cameras; a visor frame + suit status in view).
##   2. The REAL AIRLOCK CHAMBER (airlock_chamber.gd): walk in, EXIT ->
##      inner hatch closes, 14.7 -> 0 psi, outer hatch opens.
##   3. OUTSIDE = beyond the outer hatch / off the pressure hull: ZERO-G
##      tethered floating (free_move_controller zero_g). The tether is
##      clipped to ring A1 at the hatch automatically and can be moved to
##      rings A2 / A3 along the hull (click a ring within reach); it is a
##      visible cable with an inelastic 5.5 m limit -- the technician can
##      drift but never away.
##   4. Back in the chamber: ENTER -> outer hatch closes, repressurize,
##      inner hatch opens. The outside panel opens the outer hatch from
##      the hull (cycling the chamber down first if needed).
## SAFETY: never stranded (outside panel always works; tether; failsafe
## return); cargo port and seal inspection refuse during EVA; saving is
## refused while outside / cycling (the suit itself is saved).

const Hud = preload("res://scripts/ui/hud_message.gd")
const EXTERIOR := 1 << 11
const AirlockChamber = preload("res://scripts/exterior/airlock_chamber.gd")
const LOCKER_POS := Vector3(-5.3, 0.0, 1.05)     # recessed into the west wall

var suited: bool = false          # saved
var outside: bool = false
var eva_log: Array = []           # [{event, t}]
var _locker_suit: Node3D
var _visor: CanvasLayer
var _visor_label: Label
var _t: float = 0.0
var _lowpass_added: bool = false


func _ready() -> void:
	add_to_group(&"eva_system")
	add_to_group(&"r35_equipment")   # SaveGame persists state_dict()/load_dict()
	_build_locker()
	_build_visor()
	_build_anchors()
	_refresh()


func _root() -> Node:
	return get_parent()


func _n(path: String) -> Node:
	return _root().get_node_or_null(path)


func _say(text: String, s: float = 3.0) -> void:
	Hud.show(_n("Player/HUD/TaskMessageLabel") as Label, get_instance_id(), text, s)


func _sfx(kind: StringName) -> void:
	var s: Node = _n("Player/HUD/MechanicalSfx")
	if s != null and s.has_method("play_kind"):
		s.play_kind(kind)


func _ai(key: StringName) -> void:
	for a in get_tree().get_nodes_in_group(&"station_ai"):
		a.event(key)


# ------------------------------------------------------------- building
func _mat(c: Color, metal: float = 0.3, em: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.55
	if em != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = em
	return m


func _csg(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	parent.add_child(b)
	return b


func _click(parent: Node3D, id: StringName, size: Vector3, pos: Vector3) -> void:
	preload("res://scripts/interactables/click_part.gd").make(self, id, size, parent, pos)


func _build_locker() -> void:
	var root := Node3D.new()
	root.name = "SuitLocker"
	root.position = LOCKER_POS
	root.rotation_degrees.y = 90.0   # faces +X, into the tunnel
	_root().add_child.call_deferred(root)
	var frame := _mat(Color(0.25, 0.27, 0.29), 0.6)
	_csg(Vector3(0.7, 2.0, 0.12), Vector3(0, 1.0, -0.02), frame, root)
	_csg(Vector3(0.74, 0.06, 0.3), Vector3(0, 2.0, 0.1), _mat(Color(0.9, 0.7, 0.1)), root)
	var lbl := Label3D.new()
	lbl.text = "EVA SUIT  A-1"
	lbl.font_size = 22
	lbl.pixel_size = 0.0012
	lbl.position = Vector3(0, 1.88, 0.06)
	root.add_child(lbl)
	_locker_suit = Node3D.new()
	root.add_child(_locker_suit)
	var white := _mat(Color(0.88, 0.88, 0.86), 0.1)
	_csg(Vector3(0.42, 0.55, 0.26), Vector3(0, 1.25, 0.15), white, _locker_suit)
	var helmet := CSGSphere3D.new()
	helmet.radius = 0.16
	helmet.position = Vector3(0, 1.67, 0.17)
	helmet.material = white
	_locker_suit.add_child(helmet)
	var visor := CSGSphere3D.new()
	visor.radius = 0.12
	visor.position = Vector3(0, 1.67, 0.27)
	visor.material = _mat(Color(0.75, 0.55, 0.15), 0.9)
	_locker_suit.add_child(visor)
	for s in [-1, 1]:
		_csg(Vector3(0.12, 0.5, 0.14), Vector3(s * 0.28, 1.2, 0.15), white, _locker_suit)
		_csg(Vector3(0.15, 0.62, 0.16), Vector3(s * 0.11, 0.66, 0.15), white, _locker_suit)
	_click(root, &"locker", Vector3(0.7, 1.9, 0.1), Vector3(0, 1.0, 0.08))


func _build_visor() -> void:
	_visor = CanvasLayer.new()
	_visor.layer = 3
	_visor.name = "EvaVisor"
	add_child(_visor)
	var frame := ColorRect.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = (UV - 0.5) * vec2(1.6, 1.0); float r = length(d); COLOR = vec4(0.0, 0.01, 0.02, smoothstep(0.62, 0.86, r) * 0.92); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	frame.material = sm
	_visor.add_child(frame)
	# Round 40: a compact, mostly VISUAL status strip:
	#   [ZONE]  [ring A1 ▮▮▮▮▯ range]  [O2 ▮▮▮▮▮]  4.3 psi
	var strip := HBoxContainer.new()
	strip.name = "Strip"
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = -270
	strip.offset_right = 270
	strip.offset_top = -86
	strip.offset_bottom = -60
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 14)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor.add_child(strip)
	_zone_chip = _hud_label(strip, "STATION", 13, Color(0.1, 0.12, 0.12))
	var zb := StyleBoxFlat.new()
	zb.bg_color = Color(0.5, 0.95, 0.85, 0.85)
	zb.set_content_margin_all(3)
	zb.set_corner_radius_all(3)
	_zone_chip.add_theme_stylebox_override("normal", zb)
	_teth_label = _hud_label(strip, "A1", 13, Color(0.95, 0.85, 0.35))
	_teth_bar = _hud_bar(strip, Color(0.3, 0.95, 0.45))
	_hud_label(strip, "O2", 13, Color(0.5, 0.95, 0.9))
	_o2_bar = _hud_bar(strip, Color(0.5, 0.95, 0.9))
	_psi_label = _hud_label(strip, "4.3 psi", 12, Color(0.5, 0.95, 0.9, 0.85))
	_visor_label = Label.new()        # kept: full text (tests / screen readers)
	_visor_label.visible = false
	_visor.add_child(_visor_label)
	# First-EVA control hint: key caps + one word each.
	_hint = VBoxContainer.new()
	_hint.name = "Hint"
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 0.62
	_hint.anchor_bottom = 0.62
	_hint.offset_left = -170
	_hint.offset_right = 170
	_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor.add_child(_hint)
	for row in [["SPACE", "push toward  +"], ["S", "brake"], ["A / D", "drift sideways"], ["CLICK RING", "re-clip tether"]]:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		_hint.add_child(h)
		var cap := _hud_label(h, row[0], 14, Color(0.05, 0.08, 0.08))
		var cb := StyleBoxFlat.new()
		cb.bg_color = Color(0.85, 0.95, 0.92, 0.92)
		cb.set_content_margin_all(4)
		cb.set_corner_radius_all(4)
		cap.add_theme_stylebox_override("normal", cb)
		cap.custom_minimum_size = Vector2(96, 0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud_label(h, row[1], 15, Color(0.85, 0.98, 0.95))
	_hint.visible = false
	_visor.visible = false


var _zone_chip: Label
var _teth_label: Label
var _teth_bar: ProgressBar
var _o2_bar: ProgressBar
var _psi_label: Label
var _hint: VBoxContainer
var _hint_t: float = 0.0
var _hint_shown: bool = false
const HINT_S := 9.0


func _hud_label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _hud_bar(parent: Control, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(70, 10)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.border_color = col * 0.8
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


# ------------------------------------------------------------ interaction
func on_part(id: StringName) -> void:
	match id:
		&"locker":
			if outside or (_airlock() != null and _airlock().sequence != ""):
				return
			if suited and not _in_station_air():
				return
			set_suited(not suited)
			_sfx(&"latch")
			_say("EVA suit %s." % ("on — step into the airlock chamber and press OUT" if suited else "stowed"))
			eva_log.append({"event": "suit_on" if suited else "suit_off", "t": _t})
			if suited:
				_ai(&"eva_suit")
		_:
			if String(id).begins_with("anchor_"):
				clip_to(int(String(id).get_slice("_", 1)))
	_refresh()


func part_prompt(id: StringName) -> String:
	match id:
		&"locker":
			if outside:
				return ""
			return "Click: %s EVA suit" % ("Stow" if suited else "Put on")
	if String(id).begins_with("anchor_"):
		var i: int = int(String(id).get_slice("_", 1))
		return "" if (not outside or i == anchor_index) else "Click: clip tether to ring %s" % ANCHORS[i][1]
	return ""


func set_suited(on: bool) -> void:
	suited = on
	var body: Node = _n("Player/PlayerBody")
	if body != null and body.has_method("set_eva_suit"):
		body.set_eva_suit(on)
	_visor.visible = on
	_refresh()


func _airlock() -> Node:
	return get_tree().get_first_node_in_group(&"airlock") if is_inside_tree() else null


func _in_station_air() -> bool:
	var a: Node = _airlock()
	return not outside and (a == null or a.is_pressurized() or not a.in_chamber(_feet()))


## Why the technician cannot go out right now ("" = clear). Round 39: the
## airlock chamber owns the interlocks (suit, cargo, seal, in chamber).
func cycle_out_blocker() -> String:
	var a: Node = _airlock()
	if outside:
		return "busy"
	if a == null:
		return "no airlock"
	return a.exit_blocker()


## Round 38 API kept: EXIT / ENTER sequences of the real chamber.
func request_cycle_out() -> bool:
	var a: Node = _airlock()
	return a != null and a.begin_cycle_out()


func request_cycle_in() -> bool:
	var a: Node = _airlock()
	if a == null:
		return false
	if outside:
		return a.begin_open_from_outside()
	return a.begin_cycle_in()


var cycling: String:
	get:
		var a: Node = _airlock()
		return a.sequence if a != null else ""


func is_eva_active() -> bool:
	var a: Node = _airlock()
	return outside or (a != null and not a.is_default_state())


# ------------------------------------------------------------------- loop
const ANCHORS := [
	[Vector3(-4.35, 1.05, -2.74), "A1"],
	[Vector3(-3.25, 1.0, -0.6), "A2"],
	[Vector3(-3.3, 1.0, 1.95), "A3"],
]
const TETHER_LEN := 5.5
const CLIP_REACH := 1.8
const SWITCH_REACH_S := 0.5       # new cable reaches the ring
const SWITCH_HOLD_S := 0.35       # both clipped (two-tether rule)
const SWITCH_RELEASE_S := 0.5     # old cable reels in
var anchor_index: int = -1        # -1 = not clipped (inside)
var tether_length: float = 0.0
var _anchor_nodes: Array = []
var _ring_mats: Array = []

## Round 40 Priority 1: an explicit ZONE state -- the tether, zero-g and the
## failsafe only ever act in "outside". Round 39 derived "outside" from the
## floor footprints every frame, so a suited technician standing in a
## doorway gap or on the outer-hatch sill (hatch shut!) counted as outside;
## the tether then saw a huge distance and the failsafe teleported them to
## the hatch exterior. Now:
##   station -> chamber   by walking into the chamber;
##   chamber -> outside   ONLY through the OPEN outer hatch (suited);
##   outside -> chamber   only by floating back into the chamber;
##   chamber -> station   through the inner hatch.
var zone: String = "station"      # station | chamber | outside


func _feet() -> Vector3:
	var fb: Node3D = _n("FreeMoveBody")
	return fb.global_position if fb != null else Vector3.ZERO


func _eye() -> Vector3:
	var fb: Node = _n("FreeMoveBody")
	return fb.current_eye_position() if fb != null and fb.has_method("current_eye_position") else Vector3.ZERO


func _update_zone(p: Vector3) -> void:
	var a: Node = _airlock()
	if a == null:
		return
	var in_ch: bool = a.in_chamber(p)
	match zone:
		"outside":
			if in_ch:
				_set_zone("chamber")
		"chamber":
			if a.outer_open and suited and p.z < a.Z_OUTER - 0.1 and absf(p.x - (-4.8)) < 0.7:
				_set_zone("outside")
			elif not in_ch and p.z > a.Z_INNER + 0.05:
				_set_zone("station")
		_:
			if in_ch:
				_set_zone("chamber")


func _set_zone(z: String) -> void:
	if z == zone:
		return
	var was: String = zone
	zone = z
	eva_log.append({"event": "zone_" + z, "from": was, "t": _t})
	if z == "outside":
		_set_outside(true)
	elif was == "outside":
		_set_outside(false)


func _process(delta: float) -> void:
	_t += delta
	var a: Node = _airlock()
	var vac: bool = outside or (a != null and a.is_vacuum() and zone == "chamber")
	_set_vacuum_audio(vac)
	_refresh()
	if suited:
		_update_visor(delta)
		if outside and Input.is_key_pressed(KEY_H):
			show_hint()
	_update_switch(delta)
	_update_tether_visual()


func _physics_process(_delta: float) -> void:
	var fb: CharacterBody3D = _n("FreeMoveBody") as CharacterBody3D
	if fb == null:
		return
	_update_zone(fb.global_position)
	if zone != "outside" or not outside:
		return
	# Tether: a soft, inelastic limit from every clipped ring (two during a
	# re-clip). Only ever applied OUTSIDE.
	var hip: Vector3 = _harness_point()
	tether_length = 0.0
	for i in _clipped_rings():
		var d: Vector3 = hip - (ANCHORS[i][0] as Vector3)
		var L: float = d.length()
		if i == anchor_index:
			tether_length = L
		if L > TETHER_LEN:
			var dir: Vector3 = d / L
			var out_v: float = fb.velocity.dot(dir)
			if out_v > 0.0:
				fb.velocity -= dir * out_v * 1.2
			fb.global_position -= dir * minf(L - TETHER_LEN, 0.05)
	# Failsafe (should never trigger with the tether): back to the hatch,
	# OUTSIDE it -- never applies in the station or the chamber.
	if tether_length > TETHER_LEN + 2.0 or fb.global_position.y < -4.0:
		_place(ANCHORS[0][0] + Vector3(-0.45, 0.6, -0.35), PI)
		_say("Tether reeled in — back at the hatch.")
		eva_log.append({"event": "tether_return", "t": _t})


## Rings the suit is clipped to right now (during a re-clip: both).
func _clipped_rings() -> Array:
	var out: Array = []
	if anchor_index >= 0:
		out.append(anchor_index)
	if _switch.has("to") and _switch["t"] >= SWITCH_REACH_S and not out.has(int(_switch["to"])):
		out.append(int(_switch["to"]))
	return out


func _set_outside(out: bool) -> void:
	outside = out
	var fb: Node = _n("FreeMoveBody")
	if fb != null and "zero_g" in fb:
		fb.zero_g = out
		if out:
			fb.velocity = fb.velocity * 0.3
	var body: Node = _n("Player/PlayerBody")
	if body != null and body.has_method("set_floating"):
		body.set_floating(out)
	_switch = {}
	if out:
		anchor_index = 0
		_clip_in_t = 0.0             # the cable visibly runs out to ring A1
		_sfx(&"click")
		_ai(&"eva_outside")
		eva_log.append({"event": "outside", "t": _t})
		if not _hint_shown:
			_hint_shown = true
			_hint_t = HINT_S
	else:
		anchor_index = -1
		eva_log.append({"event": "inside", "t": _t})
	_set_presentation(out)


# ------------------------------------------------------------ re-clipping
## Round 40: a STAGED re-clip (never an instant "magic" swap): the new
## cable reaches out from the suit to the ring (0.5 s), clicks on (the ring
## light turns green -- both tethers held for a moment, the two-tether
## rule), then the old cable unclips and reels in (0.5 s).
var _switch: Dictionary = {}      # {to, from, t}
var _clip_in_t: float = -1.0


func clip_to(i: int) -> bool:
	if not outside or i < 0 or i >= ANCHORS.size() or i == anchor_index or not _switch.is_empty():
		return false
	if _harness_point().distance_to(ANCHORS[i][0]) > CLIP_REACH:
		_say("Ring %s: out of reach." % ANCHORS[i][1])
		_sfx(&"fail")
		return false
	_switch = {"to": i, "from": anchor_index, "t": 0.0, "clicked": false}
	eva_log.append({"event": "clip_start_%d" % i, "t": _t})
	return true


func is_switching() -> bool:
	return not _switch.is_empty()


func _update_switch(delta: float) -> void:
	if _clip_in_t >= 0.0:
		_clip_in_t += delta
		if _clip_in_t >= SWITCH_REACH_S:
			_clip_in_t = -1.0
	if _switch.is_empty():
		return
	_switch["t"] += delta
	var t: float = _switch["t"]
	if t >= SWITCH_REACH_S and not _switch["clicked"]:
		_switch["clicked"] = true
		_sfx(&"click")
		eva_log.append({"event": "clip_%d" % int(_switch["to"]), "t": _t})
		if not _taught_switch:
			_taught_switch = true
			_ai(&"tether_switch")
	if t >= SWITCH_REACH_S + SWITCH_HOLD_S and anchor_index != int(_switch["to"]):
		eva_log.append({"event": "unclip_%d" % int(_switch["from"]), "t": _t})
		anchor_index = int(_switch["to"])
		_sfx(&"latch")
	if t >= SWITCH_REACH_S + SWITCH_HOLD_S + SWITCH_RELEASE_S:
		_switch = {}
var _taught_switch: bool = false


## Instantly complete a pending re-clip (tests / loads).
func finish_switch() -> void:
	while not _switch.is_empty():
		_update_switch(0.1)


# --------------------------------------------------------- tether visuals
## The suit's tether attachment (a harness D-ring at the front of the hip,
## from the real rig) -- where the cable is clipped on.
func _harness_point() -> Vector3:
	var body: Node = _n("Player/PlayerBody")
	if body != null and body.get("_rig") != null:
		var rig: Node3D = body._rig
		return rig.global_transform * (rig.bone_pos("Hips") + Vector3(0.1, 0.02, -0.12))
	return _eye() - Vector3(-0.1, 0.7, 0.1)


func _build_anchors() -> void:
	var root := Node3D.new()
	root.name = "TetherAnchors"
	_root().add_child.call_deferred(root)
	for i in ANCHORS.size():
		var a := Node3D.new()
		a.name = "Anchor%d" % i
		a.position = ANCHORS[i][0]
		root.add_child(a)
		var rm := _mat(Color(0.95, 0.75, 0.15), 0.6, Color(0.95, 0.75, 0.15) * 0.25)
		_ring_mats.append(rm)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.035
		tm.outer_radius = 0.06
		ring.mesh = tm
		ring.material_override = rm
		ring.rotation_degrees.x = 90.0
		a.add_child(ring)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.05, 0.1)
		base.mesh = bm
		base.material_override = _mat(Color(0.3, 0.3, 0.32), 0.6)
		base.position.y = -0.07
		a.add_child(base)
		var lbl := Label3D.new()
		lbl.text = String(ANCHORS[i][1])
		lbl.font_size = 26
		lbl.pixel_size = 0.0012
		lbl.position = Vector3(0, 0.14, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(0.95, 0.8, 0.3)
		a.add_child(lbl)
		for v in a.find_children("*", "VisualInstance3D", true, false):
			(v as VisualInstance3D).layers = 1 | EXTERIOR
		_click(a, StringName("anchor_%d" % i), Vector3(0.22, 0.22, 0.22), Vector3.ZERO)
		_anchor_nodes.append(a)
	for k in 2:
		var c := _build_cable("TetherCable%d" % k)
		root.add_child(c["root"])
		_cables.append(c)


## A real TUBE cable (segments) with a carabiner at each end -- a solid
## mesh, so the player camera, the exterior cameras and the mirror all
## see it (Round 39's camera-facing ribbon was edge-on to other cameras).
var _cables: Array = []           # [{root, segs:[MeshInstance3D], hook_a, hook_b}]
const CABLE_SEGS := 18


func _build_cable(name: String) -> Dictionary:
	var root := Node3D.new()
	root.name = name
	var cm := _mat(Color(0.95, 0.8, 0.2), 0.1)
	cm.roughness = 0.7
	var segs: Array = []
	for k in CABLE_SEGS:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.011
		cyl.bottom_radius = 0.011
		cyl.height = 1.0
		cyl.radial_segments = 6
		cyl.rings = 1
		mi.mesh = cyl
		mi.material_override = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 | EXTERIOR
		root.add_child(mi)
		segs.append(mi)
	var hooks: Array = []
	for k in 2:
		var h := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.018
		tm.outer_radius = 0.032
		h.mesh = tm
		h.material_override = _mat(Color(0.78, 0.8, 0.82), 0.85)
		h.layers = 1 | EXTERIOR
		h.scale = Vector3(1.0, 1.0, 1.6)
		root.add_child(h)
		hooks.append(h)
	root.visible = false
	return {"root": root, "segs": segs, "hook_a": hooks[0], "hook_b": hooks[1]}


## Draw cable `c` from the harness to ring `i`, `ext` (0..1) of the way
## (a cable reaching out / reeling in), sagging and gently swaying.
func _draw_cable(c: Dictionary, i: int, ext: float) -> void:
	var root: Node3D = c["root"]
	if i < 0 or ext <= 0.01:
		root.visible = false
		return
	root.visible = true
	var a: Vector3 = _harness_point()
	var b: Vector3 = a.lerp(ANCHORS[i][0], ext)
	var span: float = a.distance_to(b)
	var slack: float = clampf((TETHER_LEN - span) / TETHER_LEN, 0.0, 1.0) * 0.45 * ext
	var sway: float = sin(_t * 1.3 + float(i)) * 0.04 * ext
	var pts: Array = []
	for k in CABLE_SEGS + 1:
		var u: float = float(k) / CABLE_SEGS
		pts.append(a.lerp(b, u) + Vector3(sway * sin(u * PI), -sin(u * PI) * slack, sway * 0.5 * sin(u * TAU)))
	for k in CABLE_SEGS:
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var seg: MeshInstance3D = c["segs"][k]
		var dv: Vector3 = p1 - p0
		var L: float = maxf(dv.length(), 0.001)
		var y: Vector3 = dv / L
		var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		seg.global_transform = Transform3D(Basis(x, y * L, x.cross(y)), (p0 + p1) * 0.5)
	(c["hook_a"] as Node3D).global_position = a
	(c["hook_b"] as Node3D).global_position = b


func _update_tether_visual() -> void:
	if _cables.is_empty():
		return
	for k in _ring_mats.size():
		var col: Color = Color(0.95, 0.75, 0.15)
		if outside and k == anchor_index:
			col = Color(0.3, 0.95, 0.4)
		if _switch.has("to") and k == int(_switch["to"]):
			col = Color(0.3, 0.95, 0.4) if _switch["clicked"] else Color(0.95, 0.95, 0.4).lerp(Color(0.95, 0.75, 0.15), 0.5 + 0.5 * sin(_t * 18.0))
		(_ring_mats[k] as StandardMaterial3D).albedo_color = col
		(_ring_mats[k] as StandardMaterial3D).emission = col * 0.6
	if not outside:
		_draw_cable(_cables[0], -1, 0.0)
		_draw_cable(_cables[1], -1, 0.0)
		return
	var main_ext: float = 1.0 if _clip_in_t < 0.0 else smoothstep(0.0, SWITCH_REACH_S, _clip_in_t)
	if _switch.is_empty():
		_draw_cable(_cables[0], anchor_index, main_ext)
		_draw_cable(_cables[1], -1, 0.0)
		return
	var t: float = _switch["t"]
	var new_ext: float = smoothstep(0.0, SWITCH_REACH_S, t)
	var old_i: int = int(_switch["from"])
	var old_ext: float = 1.0 - smoothstep(SWITCH_REACH_S + SWITCH_HOLD_S, SWITCH_REACH_S + SWITCH_HOLD_S + SWITCH_RELEASE_S, t)
	_draw_cable(_cables[0], old_i, old_ext)
	_draw_cable(_cables[1], int(_switch["to"]), new_ext)


func _set_vacuum_audio(vac: bool) -> void:
	var amb: int = AudioServer.get_bus_index("Ambient")
	if amb == -1:
		return
	if vac and not _lowpass_added:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 500.0
		AudioServer.add_bus_effect(amb, lp)
		_lowpass_added = true
	elif not vac and _lowpass_added:
		AudioServer.remove_bus_effect(amb, AudioServer.get_bus_effect_count(amb) - 1)
		_lowpass_added = false


func _place(eye: Vector3, yaw: float) -> void:
	var fb: Node = _n("FreeMoveBody")
	var player: Node3D = _n("Player")
	var lp: Node3D = _n("Player/LookPivot")
	fb.sync_to_eye_position(eye)
	if "velocity" in fb:
		fb.velocity = Vector3.ZERO
	player.global_position = eye
	if lp != null:
		lp.rotation.y = yaw - player.rotation.y
		lp._target_yaw = lp.rotation.y


## Sunlit body outside (the exterior light layer). Mirror-only parts (head,
## helmet) are left alone: adding a layer the first-person camera renders
## would show the inside of the helmet.
func _set_presentation(out: bool) -> void:
	var body: Node = _n("Player")
	if body != null:
		for v in body.find_children("*", "VisualInstance3D", true, false):
			var vi: VisualInstance3D = v
			if vi.layers & 4 and not (vi.layers & 1):
				continue
			vi.layers = (vi.layers | EXTERIOR) if out else (vi.layers & ~EXTERIOR)


func zone_word() -> String:
	if zone == "outside":
		var to_hatch: float = _eye().distance_to(ANCHORS[0][0])
		return "RETURN" if to_hatch < 1.6 else "OUTSIDE"
	if zone == "chamber":
		var a: Node = _airlock()
		return "CHAMBER" if a == null else ("CHAMBER · VAC" if a.is_vacuum() else "CHAMBER")
	return "STATION"


func _update_visor(delta: float = 0.0) -> void:
	var a: Node = _airlock()
	var o2: float = 1.0 - minf(_t / 30.0, 40.0) / 100.0
	_zone_chip.text = zone_word()
	var zcol: Color = Color(1.0, 0.55, 0.3) if zone == "outside" else (Color(0.95, 0.8, 0.3) if zone == "chamber" else Color(0.5, 0.95, 0.85))
	(_zone_chip.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = Color(zcol, 0.88)
	var ring: String = String(ANCHORS[anchor_index][1]) if outside and anchor_index >= 0 else "—"
	if _switch.has("to"):
		ring = "%s>%s" % [String(ANCHORS[int(_switch["from"])][1]), String(ANCHORS[int(_switch["to"])][1])]
	_teth_label.text = ring
	var r: float = clampf(tether_length / TETHER_LEN, 0.0, 1.0) if outside else 0.0
	_teth_bar.value = r
	(_teth_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.3, 0.95, 0.45).lerp(Color(1.0, 0.3, 0.2), smoothstep(0.65, 1.0, r))
	_o2_bar.value = o2
	_psi_label.text = "%.1f psi" % AirlockChamber.SUIT_PSI
	var amb: String = ("%.1f psi" % a.psi) if a != null and not outside else "VACUUM"
	_visor_label.text = "SUIT %.1f psi O2   ·   O2 %d %%   ·   TETHER %s %.1f/%.1f m   ·   AMB %s   ·   %s" % [AirlockChamber.SUIT_PSI, roundi(o2 * 100.0), ring, tether_length, TETHER_LEN, amb, zone_word()]
	if _hint_t > 0.0:
		_hint_t -= delta
	_hint.visible = outside and _hint_t > 0.0


## Show the EVA control hint again (H while outside).
func show_hint() -> void:
	_hint_t = HINT_S


func _refresh() -> void:
	if _locker_suit != null:
		_locker_suit.visible = not suited


func _exit_tree() -> void:
	if _lowpass_added:
		_set_vacuum_audio(false)
	if outside:
		_set_presentation(false)


# ------------------------------------------------------------ save / load
func state_dict() -> Dictionary:
	return {"suited": suited}


func load_dict(d: Dictionary) -> void:
	set_suited(bool(d.get("suited", false)))
	if outside:
		_set_outside(false)
	zone = "station"
	var al: Node = _airlock()
	if al != null:
		al.reset_default()
	_set_vacuum_audio(false)
	_refresh()
