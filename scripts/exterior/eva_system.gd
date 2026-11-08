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
	_visor_label = Label.new()
	_visor_label.anchor_left = 0.5
	_visor_label.anchor_right = 0.5
	_visor_label.anchor_top = 1.0
	_visor_label.anchor_bottom = 1.0
	_visor_label.offset_left = -260
	_visor_label.offset_right = 260
	_visor_label.offset_top = -78
	_visor_label.offset_bottom = -56
	_visor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_visor_label.add_theme_font_size_override("font_size", 13)
	_visor_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.9, 0.9))
	_visor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor.add_child(_visor_label)
	_visor.visible = false


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
			_say("EVA suit %s." % ("on — step into the airlock chamber and press EXIT" if suited else "stowed"))
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
	[Vector3(-4.35, 1.05, -2.74), "A1 (hatch)"],
	[Vector3(-3.25, 1.0, -0.6), "A2 (walkway)"],
	[Vector3(-3.3, 1.0, 1.95), "A3 (mast)"],
]
const TETHER_LEN := 5.5
var anchor_index: int = -1        # -1 = not clipped (inside)
var tether_length: float = 0.0
var _tether_mesh: MeshInstance3D
var _anchor_nodes: Array = []


func _feet() -> Vector3:
	var fb: Node3D = _n("FreeMoveBody")
	return fb.global_position if fb != null else Vector3.ZERO


func _eye() -> Vector3:
	var fb: Node = _n("FreeMoveBody")
	return fb.current_eye_position() if fb != null and fb.has_method("current_eye_position") else Vector3.ZERO


## Outside the pressure hull: beyond the outer hatch plane, or anywhere not
## over an interior floor footprint.
func _is_outside(p: Vector3) -> bool:
	var ext: Node = get_tree().get_first_node_in_group(&"exterior")
	if p.z < -2.68 and p.x > -5.6 and p.x < -2.0:
		return true
	return ext != null and ext.has_method("is_interior") and not ext.is_interior(p.x, p.z)


func _process(delta: float) -> void:
	_t += delta
	var a: Node = _airlock()
	var vac: bool = outside or (a != null and a.is_vacuum() and a.in_chamber(_feet()))
	_set_vacuum_audio(vac)
	_refresh()
	if suited:
		_update_visor()
	_update_tether_visual()


func _physics_process(delta: float) -> void:
	var fb: CharacterBody3D = _n("FreeMoveBody") as CharacterBody3D
	if fb == null:
		return
	var p: Vector3 = fb.global_position
	var now_out: bool = _is_outside(p) and suited
	if now_out != outside:
		_set_outside(now_out)
	if not outside:
		return
	# Tether: a soft, inelastic limit from the clipped ring.
	var anchor: Vector3 = ANCHORS[anchor_index][0] if anchor_index >= 0 else ANCHORS[0][0]
	var eye: Vector3 = fb.current_eye_position()
	var hip: Vector3 = eye - Vector3(0, 0.7, 0)
	var d: Vector3 = hip - anchor
	tether_length = d.length()
	if tether_length > TETHER_LEN:
		var dir: Vector3 = d / tether_length
		var out_v: float = fb.velocity.dot(dir)
		if out_v > 0.0:
			fb.velocity -= dir * out_v * 1.2
		fb.global_position -= dir * minf(tether_length - TETHER_LEN, 0.05)
	# Failsafe (should never trigger with the tether): back to the hatch.
	if tether_length > TETHER_LEN + 2.0 or p.y < -4.0:
		_place(ANCHORS[0][0] + Vector3(-0.45, 0.6, -0.35), PI)
		_say("Tether retracted — back at the hatch.")
		eva_log.append({"event": "tether_return", "t": _t})


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
	if out:
		anchor_index = 0
		_sfx(&"click")
		_say("Tether clipped to ring A1. You're floating — W/S push, Space/C rise/sink.", 4.0)
		_ai(&"eva_outside")
		eva_log.append({"event": "outside", "t": _t})
	else:
		anchor_index = -1
		eva_log.append({"event": "inside", "t": _t})
	_set_presentation(out)


## Move the tether to another ring (must be within reach).
func clip_to(i: int) -> bool:
	if not outside or i < 0 or i >= ANCHORS.size():
		return false
	var hip: Vector3 = _eye() - Vector3(0, 0.7, 0)
	if hip.distance_to(ANCHORS[i][0]) > 1.8:
		_say("Ring %s is out of reach." % ANCHORS[i][1])
		return false
	anchor_index = i
	_sfx(&"click")
	_say("Tether clipped to ring %s." % ANCHORS[i][1])
	eva_log.append({"event": "clip_%d" % i, "t": _t})
	return true


func _build_anchors() -> void:
	var root := Node3D.new()
	root.name = "TetherAnchors"
	_root().add_child.call_deferred(root)
	var ring_m := _mat(Color(0.95, 0.75, 0.15), 0.6)
	for i in ANCHORS.size():
		var a := Node3D.new()
		a.name = "Anchor%d" % i
		a.position = ANCHORS[i][0]
		root.add_child(a)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.035
		tm.outer_radius = 0.06
		ring.mesh = tm
		ring.material_override = ring_m
		ring.rotation_degrees.x = 90.0
		ring.layers = 1 | EXTERIOR
		a.add_child(ring)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.05, 0.08)
		base.mesh = bm
		base.material_override = _mat(Color(0.3, 0.3, 0.32), 0.6)
		base.position.y = -0.06
		base.layers = 1 | EXTERIOR
		a.add_child(base)
		var lbl := Label3D.new()
		lbl.text = String(ANCHORS[i][1]).get_slice(" ", 0)
		lbl.font_size = 22
		lbl.pixel_size = 0.0012
		lbl.position = Vector3(0, 0.13, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(0.95, 0.8, 0.3)
		lbl.layers = 1 | EXTERIOR
		a.add_child(lbl)
		_click(a, StringName("anchor_%d" % i), Vector3(0.18, 0.18, 0.18), Vector3.ZERO)
		_anchor_nodes.append(a)
	_tether_mesh = MeshInstance3D.new()
	_tether_mesh.name = "TetherLine"
	_tether_mesh.mesh = ImmediateMesh.new()
	var tm2 := _mat(Color(0.95, 0.85, 0.3), 0.1)
	tm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tether_mesh.material_override = tm2
	_tether_mesh.layers = 1 | EXTERIOR
	_tether_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_tether_mesh)


## A thin sagging cable (camera-facing ribbon) ring -> suit hip.
func _update_tether_visual() -> void:
	if _tether_mesh == null:
		return
	var im: ImmediateMesh = _tether_mesh.mesh
	im.clear_surfaces()
	if not outside or anchor_index < 0:
		return
	var a: Vector3 = ANCHORS[anchor_index][0]
	var b: Vector3 = _eye() - Vector3(-0.12, 0.72, 0.05)
	var slack: float = clampf((TETHER_LEN - a.distance_to(b)) / TETHER_LEN, 0.0, 1.0) * 0.6
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	var cp: Vector3 = cam.global_position if cam != null else b + Vector3(0, 0, 1)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := 24
	for k in n + 1:
		var u: float = float(k) / n
		var p: Vector3 = a.lerp(b, u) + Vector3(0, -sin(u * PI) * slack, 0) + Vector3(0, 0, sin(u * TAU) * slack * 0.15)
		var side: Vector3 = ((b - a).cross(cp - p)).normalized() * 0.016
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(p + side)
	im.surface_end()


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


func _update_visor() -> void:
	var a: Node = _airlock()
	var amb: String = ("%.1f psi" % a.psi) if a != null and not outside else "VACUUM"
	var teth: String = ("TETHER %s %.1f/%.1f m" % [String(ANCHORS[anchor_index][1]).get_slice(" ", 0), tether_length, TETHER_LEN]) if outside and anchor_index >= 0 else "TETHER —"
	_visor_label.text = "SUIT %.1f psi O2   ·   O2 %d %%   ·   %s   ·   AMB %s" % [AirlockChamber.SUIT_PSI, 100 - mini(int(_t / 30.0), 40), teth, amb]


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
	var al: Node = _airlock()
	if al != null:
		al.reset_default()
	_set_vacuum_audio(false)
	_refresh()
