extends Node
## Round 38/39/40/41: EVA.
##   1. SUIT LOCKER (airlock tunnel): the technician visibly puts the suit
##      on (player_body set_eva_suit: pressure suit, life-support pack,
##      helmet + gold visor in the mirror / on cameras; a visor frame and a
##      compact status strip in view).
##   2. The REAL AIRLOCK CHAMBER (airlock_chamber.gd): OUT -> inner hatch
##      closes, 14.7 -> 0 psi, outer hatch opens. IN reverses it.
##   3. OUTSIDE (Round 40 zone state: only through the OPEN outer hatch):
##      zero-g floating. Round 41 controls: W pushes along the aim, S
##      brakes (free_move_controller.gd).
##   4. Round 41: TWO SAFETY TETHERS (A on the left hip D-ring, B on the
##      right), each an independent object with its own ring, state, cable
##      and carabiner. States per tether:
##         stowed -> connecting -> secured -> releasing -> stowed
##      The pair is always in one of SECURED_A / SECURED_B / SECURED_BOTH /
##      CONNECTING_x / RELEASING_x. RULES (never both unsecured outside):
##        * stepping out clips A to the hatch ring A1 (clipped in the
##          chamber before the outer hatch opened);
##        * clicking a ring in reach sends the FREE tether to it (the arm
##          reaches, the hook seats with a latch click);
##        * a tether can only be RELEASED (click its ring, or R = release
##          the older one) while the OTHER one is SECURED -- releasing the
##          last secure tether is refused with a warning;
##        * one tether transition at a time (no double-click duplication);
##        * a connect interrupted by drifting out of reach aborts cleanly
##          (hook reels back, the other tether never changed).
##      Each secured tether is an inelastic TETHER_LEN cable: outward motion
##      past it is removed and the suit is eased back a few mm per frame --
##      a taut cable, never a teleport.
##   5. Round 41: WORKSITES -- a handhold / foot restraint next to equipment
##      outside. Click it within reach to STABILISE (the body eases the last
##      metre into a working stance, thrust is locked, both hands free);
##      click again or press W to push off. Worksite tasks can require it.
## SAFETY: the outside panel always opens the hatch; the dual-tether
## invariant; a last-resort failsafe that can only act OUTSIDE; saving is
## refused while outside / cycling (the suit itself is saved).

const Hud = preload("res://scripts/ui/hud_message.gd")
const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
const EXTERIOR := 1 << 11
const AirlockChamber = preload("res://scripts/exterior/airlock_chamber.gd")
const LOCKER_POS := Vector3(-5.3, 0.0, 1.05)     # recessed into the west wall

var suited: bool = false          # saved
var outside: bool = false
var eva_log: Array = []           # [{event, t}]
var _locker_suit: Node3D
var locker_rig: Node3D
var _locker_straps: Node3D
var _locker_open: Node3D
var _locker_lamp: StandardMaterial3D
var _locker_status: Label3D
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
	_build_audio()
	_refresh()
	_register_antenna_worksite.call_deferred()


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
	# Round 42 Priority 14: the STOWED suit is the real worn suit -- the
	# same technician_rig.gd garment, helmet, pack and harness meshes --
	# hung on a shoulder yoke, held by two restraint straps, on its service
	# umbilical, with a status lamp. Not a second simplified model; and
	# never shown in two places (hidden while worn: the empty yoke, open
	# straps and an amber IN USE lamp remain).
	_locker_suit = Node3D.new()
	_locker_suit.name = "StowedSuit"
	root.add_child(_locker_suit)
	var rig: Node3D = preload("res://scripts/character/technician_rig.gd").new()
	rig.name = "SuitRig"
	rig.position = Vector3(0, 0.04, 0.36)
	rig.rotation_degrees.y = 180.0          # front faces out of the locker
	_locker_suit.add_child(rig)
	rig.build()
	rig.set_eva_suit(true)
	if rig.head_mesh != null:
		rig.head_mesh.visible = false       # an EMPTY suit (the helmet is closed)
	if rig.watch_mount != null:
		rig.watch_mount.visible = false
	# Round 43 Priority 6: ROOT CAUSE of the "headless" stored suit -- the
	# rig puts the helmet (like the wearer's head) on the MIRROR-ONLY layer,
	# which the first-person camera never renders. The STOWED suit is an
	# ordinary object: every mesh goes on the normal world layer.
	for v in rig.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = v
		if vi.layers & 4:
			vi.layers = 1
	# Hanging pose: arms a little away from the torso, elbows soft.
	rig.set_local("LeftUpperArm", Quaternion(Vector3(0, 0, 1), -0.22))
	rig.set_local("RightUpperArm", Quaternion(Vector3(0, 0, 1), 0.22))
	rig.set_local("LeftLowerArm", Quaternion(Vector3(1, 0, 0), -0.25))
	rig.set_local("RightLowerArm", Quaternion(Vector3(1, 0, 0), -0.25))
	rig.apply_to_skeleton()
	locker_rig = rig
	var metal := _mat(Color(0.62, 0.63, 0.66), 0.8)
	var strapm := _mat(Color(0.12, 0.13, 0.15), 0.1)
	# Shoulder yoke (always there) on two stand-offs from the backplate.
	_csg(Vector3(0.5, 0.045, 0.06), Vector3(0, 1.47, 0.2), metal, root)
	for sx in [-0.2, 0.2]:
		_csg(Vector3(0.035, 0.035, 0.22), Vector3(sx, 1.47, 0.09), metal, root)
	# Side rails the straps buckle to.
	for sx in [-0.33, 0.33]:
		_csg(Vector3(0.03, 1.6, 0.03), Vector3(sx, 0.95, 0.12), metal, root)
	# Restraint straps across the suit (chest + thighs) with buckles.
	_locker_straps = Node3D.new()
	_locker_suit.add_child(_locker_straps)
	for sy in [1.16, 0.72]:
		_csg(Vector3(0.66, 0.045, 0.012), Vector3(0, sy, 0.6 if sy > 1.0 else 0.52), strapm, _locker_straps)
		_csg(Vector3(0.05, 0.06, 0.02), Vector3(0.0, sy, 0.61 if sy > 1.0 else 0.53), metal, _locker_straps)
	# Open straps hanging from the rails (shown while the suit is out).
	_locker_open = Node3D.new()
	root.add_child(_locker_open)
	for sx in [-0.33, 0.33]:
		for sy in [1.16, 0.72]:
			_csg(Vector3(0.012, 0.22, 0.04), Vector3(sx + (0.03 if sx < 0 else -0.03), sy - 0.1, 0.14), strapm, _locker_open)
	_locker_open.visible = false
	# Service umbilical: wall port -> the suit's chest connector.
	_csg(Vector3(0.06, 0.06, 0.05), Vector3(0.24, 1.02, 0.03), metal, root)
	var hose := CSGCylinder3D.new()
	hose.radius = 0.014
	hose.height = 0.42
	hose.material = _mat(Color(0.2, 0.22, 0.26), 0.2)
	hose.position = Vector3(0.17, 1.08, 0.24)
	hose.rotation_degrees = Vector3(65.0, 0.0, 25.0)
	_locker_suit.add_child(hose)
	# Status lamp + label on the header.
	var lamp := CSGSphere3D.new()
	lamp.radius = 0.018
	lamp.position = Vector3(0.28, 1.88, 0.07)
	_locker_lamp = _mat(Color(0.3, 0.95, 0.45), 0.0, Color(0.3, 0.95, 0.45))
	lamp.material = _locker_lamp
	root.add_child(lamp)
	_locker_status = Label3D.new()
	_locker_status.font_size = 14
	_locker_status.pixel_size = 0.001
	_locker_status.position = Vector3(0.28, 1.83, 0.07)
	_locker_status.text = "SUIT READY"
	root.add_child(_locker_status)
	_click(root, &"locker", Vector3(0.7, 1.9, 0.1), Vector3(0, 1.0, 0.08))


# --------------------------------------------------------------- visor HUD
## Round 41 compact strip (bottom of the visor):
##   [ZONE]  [A A1 ●] [B — ○]  [range ▮▮▮▯]  [▲ jets  0.4 m/s ◎]  [O2 ▮▮▮▮]  4.3 psi
var _zone_chip: Label
var _teth_label: Label             # tether A chip (kept name: tests / older code)
var _teth_b_label: Label           # tether B chip
var _teth_bar: ProgressBar         # tightest secured tether, fraction of TETHER_LEN
var _o2_bar: ProgressBar
var _psi_label: Label
var _jet_chip: Label
var _speed_bar: ProgressBar
var _motion: Control               # velocity direction relative to the view
var _warn: Label
var _warn_t: float = 0.0
var _hint: VBoxContainer
var _hint_t: float = 0.0
var _hint_shown: bool = false
const HINT_S := 9.0
const HINT_ROWS := [["W", "thrust toward  +"], ["S", "brake"], ["CLICK RING", "clip the free tether"], ["R", "release the older tether"]]


class MotionDot extends Control:
	var dir := Vector2.ZERO     # view-space (x right, y up), length 0..1
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.45
		draw_arc(c, r, 0.0, TAU, 24, Color(0.6, 0.95, 0.9, 0.7), 1.5)
		draw_line(c - Vector2(r * 0.3, 0), c + Vector2(r * 0.3, 0), Color(0.6, 0.95, 0.9, 0.4), 1.0)
		draw_line(c - Vector2(0, r * 0.3), c + Vector2(0, r * 0.3), Color(0.6, 0.95, 0.9, 0.4), 1.0)
		if dir.length() > 0.02:
			draw_circle(c + Vector2(dir.x, -dir.y) * r * 0.85, 3.0, Color(1.0, 0.8, 0.35))


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
	var strip := HBoxContainer.new()
	strip.name = "Strip"
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = -330
	strip.offset_right = 330
	strip.offset_top = -88
	strip.offset_bottom = -58
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 10)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor.add_child(strip)
	_zone_chip = _hud_chip(strip, "STATION", Color(0.5, 0.95, 0.85))
	_teth_label = _hud_chip(strip, "A —", Color(0.35, 0.38, 0.4))
	_teth_b_label = _hud_chip(strip, "B —", Color(0.35, 0.38, 0.4))
	_teth_bar = _hud_bar(strip, Color(0.3, 0.95, 0.45), 54)
	_jet_chip = _hud_chip(strip, "▲", Color(0.35, 0.38, 0.4))
	_speed_bar = _hud_bar(strip, Color(1.0, 0.8, 0.35), 44)
	_motion = MotionDot.new()
	_motion.custom_minimum_size = Vector2(28, 28)
	_motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_motion)
	_hud_label(strip, "O2", 13, Color(0.5, 0.95, 0.9))
	_o2_bar = _hud_bar(strip, Color(0.5, 0.95, 0.9), 50)
	_psi_label = _hud_label(strip, "4.3 psi", 12, Color(0.5, 0.95, 0.9, 0.85))
	_visor_label = Label.new()        # kept: full text (tests / screen readers)
	_visor_label.visible = false
	_visor.add_child(_visor_label)
	# Short warning line just above the strip (unsafe release, out of reach).
	_warn = _hud_label(_visor, "", 15, Color(1.0, 0.55, 0.35))
	_warn.anchor_left = 0.5
	_warn.anchor_right = 0.5
	_warn.anchor_top = 1.0
	_warn.anchor_bottom = 1.0
	_warn.offset_left = -300
	_warn.offset_right = 300
	_warn.offset_top = -118
	_warn.offset_bottom = -94
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# First-EVA control hint: key caps + one phrase each.
	_hint = VBoxContainer.new()
	_hint.name = "Hint"
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 0.62
	_hint.anchor_bottom = 0.62
	_hint.offset_left = -190
	_hint.offset_right = 190
	_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor.add_child(_hint)
	for row in HINT_ROWS:
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
		cap.custom_minimum_size = Vector2(104, 0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud_label(h, row[1], 15, Color(0.85, 0.98, 0.95))
	_hint.visible = false
	_visor.visible = false


func _hud_label(parent: Node, text: String, size: int, col: Color) -> Label:
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


func _hud_chip(parent: Control, text: String, bg: Color) -> Label:
	var l := _hud_label(parent, text, 13, Color(0.06, 0.08, 0.08))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg, 0.88)
	sb.set_content_margin_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.set_corner_radius_all(3)
	l.add_theme_stylebox_override("normal", sb)
	return l


func _chip_color(l: Label, c: Color) -> void:
	(l.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = Color(c, 0.88)


func _hud_bar(parent: Control, col: Color, w: float = 70.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, 10)
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


func _warning(text: String) -> void:
	_warn.text = text
	_warn_t = 3.0
	_say(text)
	_sfx(&"fail")


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
			_say("EVA suit %s." % ("on — step into the airlock chamber and press OUT<<" if suited else "stowed"))
			eva_log.append({"event": "suit_on" if suited else "suit_off", "t": _t})
			if suited:
				_ai(&"eva_suit")
		_:
			var s := String(id)
			if s.begins_with("anchor_"):
				var i: int = int(s.get_slice("_", 1))
				var k: int = tether_on_ring(i)
				if k >= 0:
					release_tether(k)
				else:
					clip_to(i)
			elif s.begins_with("hold_"):
				var ws: String = s.substr(5)
				if work_site == ws:
					leave_worksite()
				else:
					stabilize(ws)
	_refresh()


func part_prompt(id: StringName) -> String:
	match id:
		&"locker":
			if outside:
				return ""
			return "Click: %s EVA suit" % ("Stow" if suited else "Put on")
	var s := String(id)
	if s.begins_with("anchor_"):
		if not outside:
			return ""
		var i: int = int(s.get_slice("_", 1))
		var k: int = tether_on_ring(i)
		if k >= 0:
			return "Click: release tether %s from %s" % [TETHER_NAMES[k], ANCHORS[i][1]]
		var f: int = free_tether()
		return "Click: clip tether %s to %s" % [TETHER_NAMES[f], ANCHORS[i][1]] if f >= 0 else ""
	if s.begins_with("hold_"):
		if not outside:
			return ""
		return "Click: let go" if work_site == s.substr(5) else "Click: grab handhold (stabilise)"
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


# ------------------------------------------------------------------- zone
## Round 41: the shared anchor graph (eva_anchor_graph.gd) -- [pos, id, kind].
const ANCHORS = Graph.ANCHORS
const TETHER_LEN := 5.5
const CLIP_REACH := 1.8
const TETHER_NAMES := ["A", "B"]
## Tether transition timing (arm reach + carabiner).
const CONNECT_REACH_S := 0.55     # the hand carries the hook out to the ring
const CONNECT_SEAT_S := 0.3       # gate snaps over the ring, latch click
const RELEASE_OPEN_S := 0.35      # the hand goes to the carabiner, gate opens
const RELEASE_REEL_S := 0.45      # the hook reels back to the harness
## Kept for older callers: the full re-clip time scale.
const SWITCH_REACH_S := CONNECT_REACH_S
var anchor_index: int = -1        # the most recently SECURED ring (-1 = none)
var tether_length: float = 0.0    # harness -> primary ring (m)
var tightest: float = 0.0         # the tighter secured tether, fraction of TETHER_LEN
var _anchor_nodes: Array = []
var _ring_mats: Array = []
## Two independent tethers: {ring, state, t, seq, from}
var tethers: Array = [_new_tether(), _new_tether()]
var _seq: int = 0

var zone: String = "station"      # station | chamber | outside


static func _new_tether() -> Dictionary:
	return {"ring": -1, "state": "stowed", "t": 0.0, "seq": 0, "target": -1}


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
		_hatch_reach_t = 0.0        # grab the hatch frame on the way in


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
	_update_tethers(delta)
	_update_tether_visual()
	_update_body_pose(delta)
	_update_audio(delta)


var _r_was_down: bool = false


# ------------------------------------------------------------ float mode
## Round 42 Priority 16: EVA MOVEMENT vs STATION MOVEMENT.
## Air pressure does not make gravity. Walking in the pressurised station
## is the suit's / overalls' MAGNETIC BOOTS on the deck plating (the
## station's established movement mode). In the airlock the suit RELEASES
## its boots for EVA as soon as the chamber starts to vent (the procedure
## stage where the technician must hold on and float out), and only
## re-engages them when the outer hatch is SEALED and the chamber is back
## at station pressure -- then the technician settles gently onto the deck
## (no snap, no teleport). The mode follows the explicit zone + the
## airlock's real hatch / pressure state, never a floor ray.
##   outside                                   -> floating
##   chamber, outer hatch open                 -> floating
##   chamber, venting / vacuum / repressurising -> floating
##   chamber, outer sealed + full pressure     -> boots engage, settle, walk
var float_mode: bool = false


func wants_float() -> bool:
	if zone == "outside" or outside:
		return true
	if zone != "chamber" or not suited:
		return false
	var a: Node = _airlock()
	return a != null and (a.outer_open or a.psi < a.STATION_PSI - 0.25)


func _set_float(on: bool) -> void:
	if on == float_mode:
		return
	float_mode = on
	var fb: Node = _n("FreeMoveBody")
	if fb != null and "zero_g" in fb:
		fb.zero_g = on
		if not on and "settling" in fb:
			fb.settling = true
	var body: Node = _n("Player/PlayerBody")
	if body != null and body.has_method("set_floating"):
		body.set_floating(on)
	eva_log.append({"event": "boots_released" if on else "boots_engaged", "zone": zone, "t": _t})
	if suited and is_inside_tree():
		_say("MAG BOOTS RELEASED — EVA mode." if on else "MAG BOOTS ENGAGED — station mode.")
		_sfx(&"click")


func _physics_process(delta: float) -> void:
	var fb: CharacterBody3D = _n("FreeMoveBody") as CharacterBody3D
	if fb == null:
		return
	_update_zone(fb.global_position)
	if wants_float() != float_mode:
		_set_float(wants_float())
	if "thrust_blocked" in fb:
		var f: Node = _n("FocusedInteractionState")
		fb.thrust_blocked = f != null and f.has_method("is_active") and f.is_active()
	if zone != "outside" or not outside:
		return
	var r_down: bool = Input.is_key_pressed(KEY_R)
	if r_down and not _r_was_down:
		release_older()
	_r_was_down = r_down
	if work_site != "":
		_update_worksite(fb, delta)
		if Input.is_key_pressed(KEY_W) and _work_ease >= 1.0:
			leave_worksite()
	# Each SECURED tether is an inelastic cable from its own hip D-ring:
	# remove outward velocity past the limit and ease back a few mm per
	# frame (a taut cable -- never a scene-position reset).
	tether_length = 0.0
	tightest = 0.0
	for k in 2:
		var ring: int = clipped_ring(k)
		if ring < 0:
			continue
		var d: Vector3 = attach_point(k) - (ANCHORS[ring][0] as Vector3)
		var L: float = d.length()
		if ring == anchor_index:
			tether_length = L
		tightest = maxf(tightest, L / TETHER_LEN)
		if L > TETHER_LEN:
			var dir: Vector3 = d / L
			var out_v: float = fb.velocity.dot(dir)
			if out_v > 0.0:
				fb.velocity -= dir * out_v
			fb.global_position -= dir * minf(L - TETHER_LEN, 0.02)
	# Last-resort failsafe (should never trigger: two tethers, each limits
	# range). Only OUTSIDE, only far past every cable.
	if tightest > (TETHER_LEN + 3.0) / TETHER_LEN or fb.global_position.y < -12.0:
		_place(ANCHORS[0][0] + Vector3(-0.45, 0.6, -0.35), PI)
		_say("Tether reeled in — back at the hatch.")
		eva_log.append({"event": "tether_return", "t": _t})


## Ring tether k is physically holding right now (-1 = none): secured, or
## releasing before its gate has opened.
func clipped_ring(k: int) -> int:
	var tt: Dictionary = tethers[k]
	if tt["state"] == "secured":
		return int(tt["ring"])
	if tt["state"] == "releasing" and float(tt["t"]) < RELEASE_OPEN_S:
		return int(tt["ring"])
	return -1


## Rings the suit is clipped to right now (during a transfer: both).
func _clipped_rings() -> Array:
	var out: Array = []
	for k in 2:
		var r: int = clipped_ring(k)
		if r >= 0 and not out.has(r):
			out.append(r)
	out.sort_custom(func(a, b): return _ring_seq(a) < _ring_seq(b))
	return out


func _ring_seq(r: int) -> int:
	for tt in tethers:
		if int(tt["ring"]) == r:
			return int(tt["seq"])
	return 0


func secured_count() -> int:
	return tethers.filter(func(tt): return tt["state"] == "secured").size()


func tether_on_ring(i: int) -> int:
	for k in 2:
		if int(tethers[k]["ring"]) == i and tethers[k]["state"] in ["secured", "connecting"]:
			return k
	return -1


func free_tether() -> int:
	for k in 2:
		if tethers[k]["state"] == "stowed":
			return k
	return -1


## Combined state machine name, e.g. SECURED_BOTH, CONNECTING_B.
func tether_state() -> String:
	for k in 2:
		if tethers[k]["state"] == "connecting":
			return "CONNECTING_" + TETHER_NAMES[k]
		if tethers[k]["state"] == "releasing":
			return "RELEASING_" + TETHER_NAMES[k]
	var a: bool = tethers[0]["state"] == "secured"
	var b: bool = tethers[1]["state"] == "secured"
	if a and b:
		return "SECURED_BOTH"
	if a:
		return "SECURED_A"
	if b:
		return "SECURED_B"
	return "NONE"


func _set_outside(out: bool) -> void:
	outside = out
	var fb: Node = _n("FreeMoveBody")
	if fb != null and "zero_g" in fb:
		# Round 42: floating is NOT tied to "outside" any more -- it is the
		# suit's EVA mode (_update_float_mode()); crossing the hatch only
		# damps the drift and frees a worksite lock.
		if out:
			_set_float(true)
			fb.velocity = fb.velocity * 0.3
		if "work_locked" in fb:
			fb.work_locked = false
	work_site = ""
	if out:
		# Tether A was clipped to the hatch ring before the outer hatch
		# opened: it is SECURED the moment the technician leaves.
		tethers = [_new_tether(), _new_tether()]
		_seq += 1
		tethers[0] = {"ring": 0, "state": "secured", "t": 1.0, "seq": _seq, "target": -1}
		anchor_index = 0
		_sfx(&"click")
		_ai(&"eva_outside")
		eva_log.append({"event": "outside", "t": _t})
		eva_log.append({"event": "secure_A_0", "t": _t})
		if not _hint_shown:
			_hint_shown = true
			_hint_t = HINT_S
	else:
		for k in 2:
			if tethers[k]["state"] != "stowed":
				eva_log.append({"event": "stow_%s" % TETHER_NAMES[k], "t": _t})
		tethers = [_new_tether(), _new_tether()]
		anchor_index = -1
		eva_log.append({"event": "inside", "t": _t})
	_set_presentation(out)


# ------------------------------------------------------------ tethers
## Send the FREE tether to ring i (staged: reach, seat, click). Never
## touches the tether that is holding the technician.
func clip_to(i: int) -> bool:
	if not outside or i < 0 or i >= ANCHORS.size():
		return false
	if is_switching():
		return false                  # one transition at a time
	if tether_on_ring(i) >= 0:
		return false
	var k: int = free_tether()
	if k < 0:
		_warning("Both tethers in use — release one first (R).")
		return false
	if attach_point(k).distance_to(ANCHORS[i][0]) > CLIP_REACH:
		_warning("Ring %s: out of reach." % ANCHORS[i][1])
		return false
	tethers[k] = {"ring": i, "state": "connecting", "t": 0.0, "seq": tethers[k]["seq"], "target": i}
	eva_log.append({"event": "clip_start_%d" % i, "tether": TETHER_NAMES[k], "t": _t})
	eva_log.append({"event": "connect_%s_%d" % [TETHER_NAMES[k], i], "t": _t})
	return true


## Release tether k -- only while the OTHER tether is secured.
func release_tether(k: int) -> bool:
	if not outside or k < 0 or k > 1 or tethers[k]["state"] != "secured":
		return false
	if is_switching():
		return false
	if tethers[1 - k]["state"] != "secured":
		_warning("Unsafe: tether %s is your last secure tether." % TETHER_NAMES[k])
		eva_log.append({"event": "unsafe_release_refused", "t": _t})
		return false
	tethers[k]["state"] = "releasing"
	tethers[k]["t"] = 0.0
	eva_log.append({"event": "release_%s_%d" % [TETHER_NAMES[k], int(tethers[k]["ring"])], "t": _t})
	return true


## R: release the OLDER of two secured tethers (the usual transfer step).
func release_older() -> bool:
	if secured_count() < 2:
		if outside and secured_count() == 1 and not is_switching():
			_warning("Unsafe: clip the other tether first.")
			eva_log.append({"event": "unsafe_release_refused", "t": _t})
		return false
	var k: int = 0 if int(tethers[0]["seq"]) < int(tethers[1]["seq"]) else 1
	return release_tether(k)


func is_switching() -> bool:
	return tethers.any(func(tt): return tt["state"] in ["connecting", "releasing"])


## Instantly complete any pending transition (tests / loads).
func finish_switch() -> void:
	var guard := 0
	while is_switching() and guard < 100:
		_update_tethers(0.1)
		guard += 1


var _taught_switch: bool = false


func _update_tethers(delta: float) -> void:
	if not outside:
		return
	for k in 2:
		var tt: Dictionary = tethers[k]
		match tt["state"]:
			"connecting":
				tt["t"] = float(tt["t"]) + delta
				# Drifted away mid-reach: abort cleanly (hook reels back).
				if float(tt["t"]) < CONNECT_REACH_S and attach_point(k).distance_to(ANCHORS[int(tt["ring"])][0]) > CLIP_REACH + 0.7:
					eva_log.append({"event": "connect_aborted_%s" % TETHER_NAMES[k], "t": _t})
					tethers[k] = {"ring": -1, "state": "stowed", "t": 0.0, "seq": tt["seq"], "target": -1}
					_warning("Tether %s: missed the ring — try again." % TETHER_NAMES[k])
					continue
				if float(tt["t"]) >= CONNECT_REACH_S + CONNECT_SEAT_S:
					_seq += 1
					tt["state"] = "secured"
					tt["seq"] = _seq
					tt["t"] = 0.0
					anchor_index = int(tt["ring"])
					_sfx(&"latch")
					_sfx(&"click")
					eva_log.append({"event": "clip_%d" % int(tt["ring"]), "t": _t})
					eva_log.append({"event": "secure_%s_%d" % [TETHER_NAMES[k], int(tt["ring"])], "t": _t})
					if not _taught_switch and secured_count() == 2:
						_taught_switch = true
						_ai(&"tether_switch")
			"releasing":
				var before: float = float(tt["t"])
				tt["t"] = before + delta
				if before < RELEASE_OPEN_S and float(tt["t"]) >= RELEASE_OPEN_S:
					_sfx(&"latch")
					eva_log.append({"event": "unclip_%d" % int(tt["ring"]), "t": _t})
				if float(tt["t"]) >= RELEASE_OPEN_S + RELEASE_REEL_S:
					tethers[k] = {"ring": -1, "state": "stowed", "t": 0.0, "seq": tt["seq"], "target": -1}
					eva_log.append({"event": "stow_%s" % TETHER_NAMES[k], "t": _t})
					var other: Dictionary = tethers[1 - k]
					if other["state"] == "secured":
						anchor_index = int(other["ring"])
			"secured":
				tt["t"] = float(tt["t"]) + delta


# --------------------------------------------------------- tether visuals
## The suit's two tether D-rings: on the waist harness, LEFT hip (A) and
## RIGHT hip (B), from the real rig (the rig's suit shows the hardware).
func attach_point(k: int) -> Vector3:
	var body: Node = _n("Player/PlayerBody")
	if body != null and body.get("_rig") != null:
		var rig: Node3D = body._rig
		if rig.has_method("tether_point"):
			return rig.global_transform * rig.tether_point(k)
		return rig.global_transform * (rig.bone_pos("Hips") + Vector3(0.15 if k == 1 else -0.15, 0.02, -0.08))
	return _eye() - Vector3(0.15 if k == 0 else -0.15, 0.7, 0.1)


## Round 40 name: the harness point (tether A's D-ring).
func _harness_point() -> Vector3:
	return attach_point(0)


## The hand a tether's transition uses (A: left, B: right), in world space.
func _hand_point(k: int) -> Vector3:
	var body: Node = _n("Player/PlayerBody")
	if body != null and body.get("_rig") != null:
		var rig: Node3D = body._rig
		var bone: String = "LeftHand" if k == 0 else "RightHand"
		return rig.global_transform * (rig.bone_pos(bone) + rig.bone_basis(bone) * Vector3(0, -0.06, 0))
	return attach_point(k)


func _build_anchors() -> void:
	var root := Node3D.new()
	root.name = "TetherAnchors"
	_root().add_child.call_deferred(root)
	var base_m := _mat(Color(0.3, 0.3, 0.32), 0.6)
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
		base.material_override = base_m
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
		var c := _build_cable("TetherCable%s" % TETHER_NAMES[k], [Color(0.95, 0.8, 0.2), Color(0.95, 0.45, 0.15)][k])
		root.add_child(c["root"])
		_cables.append(c)


## A real TUBE cable (segments) with a carabiner (body + spring gate) at
## the ring end and a small swivel at the suit end -- solid meshes, so the
## player camera, the exterior cameras and the mirror all see it.
var _cables: Array = []           # [{root, segs, hook_a, hook_b, gate}]
const CABLE_SEGS := 18


func _build_cable(name: String, col: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = name
	var cm := _mat(col, 0.1)
	cm.roughness = 0.7
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.011
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	var segs: Array = []
	for k in CABLE_SEGS:
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 | EXTERIOR
		root.add_child(mi)
		segs.append(mi)
	var steel := _mat(Color(0.78, 0.8, 0.82), 0.85)
	# Suit-end swivel.
	var sw := MeshInstance3D.new()
	var swm := CylinderMesh.new()
	swm.top_radius = 0.016
	swm.bottom_radius = 0.016
	swm.height = 0.05
	sw.mesh = swm
	sw.material_override = steel
	sw.layers = 1 | EXTERIOR
	root.add_child(sw)
	# Carabiner: an elongated D body + a gate bar that swings open.
	var hook := Node3D.new()
	hook.name = "Carabiner"
	root.add_child(hook)
	var body := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.022
	tm.outer_radius = 0.034
	body.mesh = tm
	body.material_override = steel
	body.scale = Vector3(1.0, 1.0, 1.7)
	body.rotation_degrees.z = 90.0
	body.layers = 1 | EXTERIOR
	hook.add_child(body)
	var gate_pivot := Node3D.new()
	gate_pivot.position = Vector3(0.0, -0.028, 0.03)
	hook.add_child(gate_pivot)
	var gate := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.008, 0.008, 0.055)
	gate.mesh = gm
	gate.material_override = _mat(Color(0.95, 0.75, 0.15), 0.6)
	gate.position = Vector3(0, 0, -0.028)
	gate.layers = 1 | EXTERIOR
	gate_pivot.add_child(gate)
	root.visible = false
	return {"root": root, "segs": segs, "hook_a": sw, "hook_b": hook, "gate": gate_pivot}


## Draw cable `c` from point a to point b with a slack sag (taut when the
## span reaches TETHER_LEN) and a gentle sway; gate open 0..1.
func _draw_cable(c: Dictionary, a: Vector3, b: Vector3, gate_open: float = 0.0, seed: float = 0.0) -> void:
	var root: Node3D = c["root"]
	root.visible = true
	var span: float = a.distance_to(b)
	var slack: float = clampf((TETHER_LEN - span) / TETHER_LEN, 0.0, 1.0) * 0.45
	var sway: float = sin(_t * 1.3 + seed) * 0.04 * slack / 0.45
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
	var hook: Node3D = c["hook_b"]
	hook.global_position = b
	var last_dir: Vector3 = (pts[CABLE_SEGS] - pts[CABLE_SEGS - 1]).normalized()
	if last_dir.length() > 0.5 and absf(last_dir.dot(Vector3.UP)) < 0.98:
		hook.look_at(b + last_dir, Vector3.UP)
	(c["gate"] as Node3D).rotation_degrees.x = -55.0 * gate_open


## Where tether k's carabiner is right now (stowed: at the hip).
func hook_position(k: int) -> Vector3:
	var tt: Dictionary = tethers[k]
	var hip: Vector3 = attach_point(k)
	match tt["state"]:
		"stowed":
			return hip
		"secured":
			return ANCHORS[int(tt["ring"])][0]
		"connecting":
			var t: float = float(tt["t"])
			var ring: Vector3 = ANCHORS[int(tt["ring"])][0]
			if t < CONNECT_REACH_S:
				return _hand_point(k).lerp(ring, smoothstep(0.6, 1.0, t / CONNECT_REACH_S))
			return ring
		"releasing":
			var t2: float = float(tt["t"])
			var ring2: Vector3 = ANCHORS[int(tt["ring"])][0]
			if t2 < RELEASE_OPEN_S:
				return ring2
			return ring2.lerp(hip, smoothstep(0.0, 1.0, (t2 - RELEASE_OPEN_S) / RELEASE_REEL_S))
	return hip


func _update_tether_visual() -> void:
	if _cables.is_empty():
		return
	for k in _ring_mats.size():
		var col: Color = Color(0.95, 0.75, 0.15)
		if outside:
			for j in 2:
				var tt: Dictionary = tethers[j]
				if int(tt["ring"]) != k:
					continue
				match tt["state"]:
					"secured":
						col = Color(0.3, 0.95, 0.4)
					"connecting":
						col = Color(0.95, 0.95, 0.4).lerp(Color(0.95, 0.75, 0.15), 0.5 + 0.5 * sin(_t * 18.0))
					"releasing":
						col = Color(0.3, 0.95, 0.4) if float(tt["t"]) < RELEASE_OPEN_S else Color(0.95, 0.75, 0.15)
		(_ring_mats[k] as StandardMaterial3D).albedo_color = col
		(_ring_mats[k] as StandardMaterial3D).emission = col * 0.6
	for k in 2:
		var c: Dictionary = _cables[k]
		if not outside or tethers[k]["state"] == "stowed":
			(c["root"] as Node3D).visible = false
			continue
		var tt: Dictionary = tethers[k]
		var gate: float = 0.0
		var t: float = float(tt["t"])
		if tt["state"] == "connecting":
			gate = 1.0 - smoothstep(CONNECT_REACH_S, CONNECT_REACH_S + CONNECT_SEAT_S, t) if t >= CONNECT_REACH_S * 0.6 else 0.0
		elif tt["state"] == "releasing":
			gate = smoothstep(RELEASE_OPEN_S * 0.4, RELEASE_OPEN_S, t) if t < RELEASE_OPEN_S + 0.15 else 0.0
		_draw_cable(c, attach_point(k), hook_position(k), gate, float(k) * 1.7)


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
	# Round 41: the helmet / head are MIRROR_ONLY (layer 3, never in the
	# wearer's own view) and so were never sunlit outside -- the helmet
	# rendered almost black on cameras. While outside, the sun also lights
	# that layer (inside, the station's own lights do).
	var sun: Light3D = get_tree().get_first_node_in_group(&"exterior").get("sun") if get_tree().get_first_node_in_group(&"exterior") != null else null
	if sun != null:
		sun.light_cull_mask = (sun.light_cull_mask | 4) if out else (sun.light_cull_mask & ~4)


# --------------------------------------------------------------- worksites
## Round 41 Priority 7: WORK POSITIONS outside. id -> {stance (eye pos),
## look (work point), anchors (ring ids a secured tether must be on; []
## = any), label}. The handhold is a real click part on the structure.
var worksites: Dictionary = {}
var work_site: String = ""
var _work_from: Vector3
var _work_ease: float = 1.0
const WORK_REACH := 1.7           # the stance must already be within reach
const WORK_EASE_S := 0.6


func register_worksite(id: String, stance: Vector3, look: Vector3, anchors: Array, hold_parent: Node3D, hold_pos: Vector3, label: String) -> void:
	worksites[id] = {"stance": stance, "look": look, "anchors": anchors, "label": label}
	_click(hold_parent, StringName("hold_" + id), Vector3(0.3, 0.3, 0.3), hold_pos)


func _register_antenna_worksite() -> void:
	var ws: Node3D = _n("Exterior/WorksiteA1") as Node3D
	if ws != null:
		register_worksite("antenna", Vector3(-3.55, 1.45, 0.75), Vector3(-3.06, 0.85, 0.75), [], ws, Vector3(-3.75, 1.2, 1.25), "WORKSITE A1")


func stabilize(id: String) -> bool:
	if not outside or not worksites.has(id):
		return false
	var w: Dictionary = worksites[id]
	if _eye().distance_to(w["stance"]) > WORK_REACH:
		_warning("%s: move closer first." % w["label"])
		return false
	var need: Array = w["anchors"]
	if not need.is_empty():
		var ok := false
		for k in 2:
			var r: int = clipped_ring(k)
			if r >= 0 and String(ANCHORS[r][1]) in need:
				ok = true
		if not ok:
			_warning("Clip a tether to %s first." % " or ".join(need))
			return false
	work_site = id
	_work_from = _eye()
	_work_ease = 0.0
	var fb: Node = _n("FreeMoveBody")
	if fb != null and "work_locked" in fb:
		fb.work_locked = true
		fb.velocity = Vector3.ZERO
	_sfx(&"latch")
	eva_log.append({"event": "stabilize_" + id, "t": _t})
	if not _taught_work:
		_taught_work = true
		_ai(&"eva_repair")
	return true
var _taught_work: bool = false


func leave_worksite() -> void:
	if work_site == "":
		return
	eva_log.append({"event": "release_hold_" + work_site, "t": _t})
	work_site = ""
	var fb: Node = _n("FreeMoveBody")
	if fb != null and "work_locked" in fb:
		fb.work_locked = false


func at_worksite(id: String) -> bool:
	return outside and work_site == id and _work_ease >= 1.0


func _update_worksite(fb: Node, delta: float) -> void:
	var w: Dictionary = worksites[work_site]
	if _work_ease < 1.0:
		_work_ease = minf(_work_ease + delta / WORK_EASE_S, 1.0)
		var p: Vector3 = _work_from.lerp(w["stance"], smoothstep(0.0, 1.0, _work_ease))
		fb.sync_to_eye_position(p)
		fb.velocity = Vector3.ZERO


# ------------------------------------------------------------ body poses
## Round 41 Priority 9: the floating body's animation state, sent to
## player_body.gd every frame: idle float / thrust / coast / brake / work,
## plus an arm REACH (tether hand to the ring, or the hatch frame on the
## way back in).
var _hatch_reach_t: float = -1.0
var eva_pose: String = "idle"
var _taught_aim: bool = false


func _update_body_pose(delta: float) -> void:
	var body: Node = _n("Player/PlayerBody")
	if body == null or not body.has_method("set_eva_pose"):
		return
	var fb: Node = _n("FreeMoveBody")
	var reach: Dictionary = {}
	if outside:
		var spd: float = (fb.velocity as Vector3).length() if fb != null else 0.0
		if work_site != "":
			eva_pose = "work"
		elif fb != null and fb.thrusting:
			eva_pose = "thrust"
			if not _taught_aim:
				_taught_aim = true
				_ai(&"eva_aim")
		elif fb != null and fb.braking:
			eva_pose = "brake"
		elif spd > 0.15:
			eva_pose = "coast"
		else:
			eva_pose = "idle"
		for k in 2:
			var tt: Dictionary = tethers[k]
			var t: float = float(tt["t"])
			var ring: Vector3 = ANCHORS[maxi(int(tt["ring"]), 0)][0]
			var w := 0.0
			match tt["state"]:
				"connecting":
					w = smoothstep(0.0, CONNECT_REACH_S * 0.6, t)
				"releasing":
					# Hand to the carabiner, gate opens, then the arm comes back.
					w = smoothstep(0.0, RELEASE_OPEN_S * 0.7, t) if t < RELEASE_OPEN_S else 1.0 - smoothstep(RELEASE_OPEN_S, RELEASE_OPEN_S + RELEASE_REEL_S, t)
				"secured":
					w = 1.0 - smoothstep(0.0, 0.35, t) if t < 0.35 else 0.0
			if w > 0.0:
				reach = {"side": "Left" if k == 0 else "Right", "target": ring, "blend": w}
		if work_site != "":
			reach = {"side": "Both", "target": worksites[work_site]["look"], "blend": _work_ease}
	else:
		eva_pose = "none"
		if _hatch_reach_t >= 0.0:
			_hatch_reach_t += delta
			var w2: float = sin(clampf(_hatch_reach_t / 1.1, 0.0, 1.0) * PI)
			reach = {"side": "Left", "target": Vector3(-5.12, 1.55, -2.62), "blend": w2}
			if _hatch_reach_t >= 1.1:
				_hatch_reach_t = -1.0
	body.set_eva_pose(eva_pose, reach)


# ------------------------------------------------------------------ audio
## Round 41: inside-suit sound only (vacuum carries no air sound): muted
## breathing, the suit's fan hum, the jets as a soft hiss heard through
## the suit, carabiner clicks (MechanicalSfx). All on the SFX bus, so the
## game's audio settings apply.
var _breath: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _jet: AudioStreamPlayer
var _audio_built: bool = false


func _build_audio() -> void:
	_breath = AudioStreamPlayer.new()
	_hum = AudioStreamPlayer.new()
	_jet = AudioStreamPlayer.new()
	for p in [_breath, _hum, _jet]:
		p.bus = "SFX"
		p.volume_db = -80.0
		add_child(p)


static func _loop_wav(seconds: float, build: Callable) -> AudioStreamWAV:
	var rate := 11025
	var n := int(rate * seconds)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var lp := 0.0
	for i in n:
		var v: float = clampf(build.call(float(i) / rate, i), -1.0, 1.0)
		lp = lp * 0.8 + v * 0.2
		bytes.encode_s16(i * 2, int(lp * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = bytes
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


func _ensure_audio() -> void:
	if _audio_built:
		return
	_audio_built = true
	# Breathing: a 4.2 s cycle (inhale, pause, exhale) of soft noise.
	_breath.stream = _loop_wav(4.2, func(t, i):
		var ph: float = t / 4.2
		var env: float = sin(clampf(ph / 0.38, 0.0, 1.0) * PI) * 0.7 + sin(clampf((ph - 0.5) / 0.42, 0.0, 1.0) * PI)
		return (fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.5 * env)
	_hum.stream = _loop_wav(1.0, func(t, _i): return sin(t * TAU * 110.0) * 0.12 + sin(t * TAU * 220.0) * 0.05 + sin(t * TAU * 330.0) * 0.02)
	_jet.stream = _loop_wav(1.0, func(_t, i): return (fmod(sin(float(i) * 78.233) * 43758.5453, 1.0) - 0.5) * 0.6)
	for p in [_breath, _hum, _jet]:
		p.play()


func _update_audio(delta: float) -> void:
	if not suited:
		for p in [_breath, _hum, _jet]:
			if p.playing:
				p.stop()
		_audio_built = _audio_built and _breath.stream != null
		return
	if not _breath.playing:
		_ensure_audio()
		for p in [_breath, _hum, _jet]:
			if not p.playing:
				p.play()
	var fb: Node = _n("FreeMoveBody")
	var jet_on: bool = outside and fb != null and fb.thrusting
	_breath.volume_db = move_toward(_breath.volume_db, -16.0 if outside else -24.0, delta * 30.0)
	_hum.volume_db = move_toward(_hum.volume_db, -22.0 if outside else -30.0, delta * 30.0)
	_jet.volume_db = move_toward(_jet.volume_db, -14.0 if jet_on else -80.0, delta * (120.0 if jet_on else 60.0))


func audio_state() -> Dictionary:
	return {"breath": _breath.playing and _breath.volume_db > -40.0, "hum": _hum.playing, "jet": _jet.playing and _jet.volume_db > -40.0, "bus": _breath.bus}


# ------------------------------------------------------------------- HUD
func zone_word() -> String:
	if zone == "outside":
		var to_hatch: float = _eye().distance_to(ANCHORS[0][0])
		return "RETURN" if to_hatch < 1.6 else "OUTSIDE"
	if zone == "chamber":
		var a: Node = _airlock()
		var w: String = "CHAMBER" if a == null else ("CHAMBER · VAC" if a.is_vacuum() else "CHAMBER")
		return w + (" · BOOTS OFF" if float_mode else "")
	return "STATION"


func tether_word(k: int) -> String:
	var tt: Dictionary = tethers[k]
	var ring: String = String(ANCHORS[int(tt["ring"])][1]) if int(tt["ring"]) >= 0 else "—"
	match tt["state"]:
		"secured": return "%s %s" % [TETHER_NAMES[k], ring]
		"connecting": return "%s >%s" % [TETHER_NAMES[k], ring]
		"releasing": return "%s %s>" % [TETHER_NAMES[k], ring]
	return "%s —" % TETHER_NAMES[k]


func _update_visor(delta: float = 0.0) -> void:
	var a: Node = _airlock()
	var o2: float = 1.0 - minf(_t / 30.0, 40.0) / 100.0
	_zone_chip.text = zone_word()
	_chip_color(_zone_chip, Color(1.0, 0.55, 0.3) if zone == "outside" else (Color(0.95, 0.8, 0.3) if zone == "chamber" else Color(0.5, 0.95, 0.85)))
	for k in 2:
		var l: Label = _teth_label if k == 0 else _teth_b_label
		l.text = tether_word(k)
		var st: String = tethers[k]["state"] if outside else "stowed"
		_chip_color(l, {"secured": Color(0.35, 0.95, 0.45), "connecting": Color(0.95, 0.9, 0.35), "releasing": Color(0.95, 0.65, 0.3)}.get(st, Color(0.45, 0.48, 0.5)))
	var r: float = clampf(tightest, 0.0, 1.0) if outside else 0.0
	_teth_bar.value = r
	(_teth_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.3, 0.95, 0.45).lerp(Color(1.0, 0.3, 0.2), smoothstep(0.65, 1.0, r))
	var fb: Node = _n("FreeMoveBody")
	var v: Vector3 = fb.velocity if fb != null and outside else Vector3.ZERO
	var jets: bool = outside and fb != null and fb.thrusting
	_jet_chip.text = "▲ JET" if jets else ("■ BRAKE" if outside and fb != null and fb.braking else ("● HOLD" if work_site != "" else "▲"))
	_chip_color(_jet_chip, Color(1.0, 0.75, 0.3) if jets else (Color(0.5, 0.8, 1.0) if work_site != "" or (fb != null and fb.braking) else Color(0.45, 0.48, 0.5)))
	_speed_bar.value = clampf(v.length() / 1.1, 0.0, 1.0)
	var cam: Node3D = _n("Player/LookPivot/PitchPivot/Camera3D") as Node3D
	if cam != null and v.length() > 0.03:
		var lv: Vector3 = cam.global_basis.orthonormalized().inverse() * v
		(_motion as MotionDot).dir = Vector2(lv.x, lv.y).limit_length(1.0) * (1.0 if lv.z < 0.0 else 0.6)
	else:
		(_motion as MotionDot).dir = Vector2.ZERO
	_motion.queue_redraw()
	_o2_bar.value = o2
	_psi_label.text = "%.1f psi" % AirlockChamber.SUIT_PSI
	var amb: String = ("%.1f psi" % a.psi) if a != null and not outside else "VACUUM"
	_visor_label.text = "SUIT %.1f psi O2   ·   O2 %d %%   ·   TETHERS %s / %s  %s  %.1f/%.1f m   ·   SPEED %.2f m/s   ·   AMB %s   ·   %s" % [AirlockChamber.SUIT_PSI, roundi(o2 * 100.0), tether_word(0), tether_word(1), tether_state(), tether_length, TETHER_LEN, v.length(), amb, zone_word()]
	if _hint_t > 0.0:
		_hint_t -= delta
	_hint.visible = outside and _hint_t > 0.0
	if _warn_t > 0.0:
		_warn_t -= delta
	_warn.visible = _warn_t > 0.0


## Show the EVA control hint again (H while outside).
func show_hint() -> void:
	_hint_t = HINT_S


func _refresh() -> void:
	if _locker_suit != null:
		_locker_suit.visible = not suited
		if _locker_open != null:
			_locker_open.visible = suited
		if _locker_lamp != null:
			var c: Color = Color(1.0, 0.65, 0.15) if suited else Color(0.3, 0.95, 0.45)
			_locker_lamp.albedo_color = c
			_locker_lamp.emission = c
			_locker_status.text = "SUIT IN USE" if suited else "SUIT READY"


func _exit_tree() -> void:
	if _lowpass_added:
		_set_vacuum_audio(false)
	if outside:
		_set_presentation(false)


# ------------------------------------------------------------ save / load
## Saving is refused outside (save_game.gd), so tether state is never
## persisted mid-EVA: a load always starts inside with both tethers stowed.
func state_dict() -> Dictionary:
	return {"suited": suited}


func load_dict(d: Dictionary) -> void:
	set_suited(bool(d.get("suited", false)))
	if outside:
		_set_outside(false)
	zone = "station"
	_set_float(false)
	work_site = ""
	tethers = [_new_tether(), _new_tether()]
	var al: Node = _airlock()
	if al != null:
		al.reset_default()
	_set_vacuum_audio(false)
	_refresh()
