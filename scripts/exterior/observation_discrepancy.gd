extends Node3D
## Round 38 Priority 5: the CAMERA / WINDOW DISCREPANCY foundation (locked
## horror idea). FOUNDATION ONLY -- nothing here ever activates itself.
##
## Shared observation region: the EVA courtyard around antenna mast A1 and
## the outer-hatch walkway. Seen DIRECTLY through the Control Room
## observation port (wall_watch_window.gd, portal render from the player's
## eye) and by cameras EXT-03 OBSERVATION (from the Engineering corner),
## EXT-04 ANTENNA A1 and EXT-02 AIRLOCK HATCH. In normal play they agree.
##
## Mechanism: visual layers. camera_network.gd removes layer 19
## (CAMERA_ONLY) from every DIRECT view (the player's eyes, the observation
## port, mirrors) and layer 20 (DIRECT_ONLY) from every surveillance
## camera. An object on one of those layers exists for one kind of
## observation only -- a real, recognisable inconsistency, not merely a
## different viewpoint. Variants (each prepared hidden):
##   "camera_figure"  a suited figure by the outer hatch: on camera only;
##   "window_object"  the maintenance case on bracket B: window only;
##   "displaced"      the maintenance case on bracket A for the eyes/port,
##                    on bracket B for the cameras (A empty on camera).
##
## Round 46 REDESIGN (the "floating square"). Root causes found:
##   1. the "tool bag" was an orange box + a strap hanging in mid-air with
##      nothing holding it -- through the port it read as a broken square;
##   2. _layer_all() OR-ed the EXTERIOR bit into the story layers, and an
##      object renders where ANY of its bits is in a camera's mask -- so
##      both copies showed in BOTH views: no contradiction at all, just two
##      floating boxes.
## Now: a recognisable EXTERIOR MAINTENANCE CASE (ribbed body, carry handle,
## latches, hazard band, stencil) that normally sits clamped on SERVICE
## BRACKET A on the airlock tunnel's east wall (the wall the Control Room
## port and EXT-03 both face). Bracket B is a second, empty bracket on the
## same wall. Each view is individually believable (the case is always ON a
## bracket); the anomaly is only that the views disagree WHICH bracket.
## Story layers carry no EXTERIOR bit; the sun lights them explicitly
## (exterior_builder.gd).
## Round 47: THREE MORE, DISTINCT contradictions (not copies of the case):
##   "shadow"    IMPOSSIBLE SHADOW. The service lamp throws the maintenance
##               case's small shadow onto the wall under bracket A (painted
##               lamp shadow, every view -- the reference). On EXT-03 only,
##               a tall human shadow also falls across that wall beside the
##               case, where nobody stands; through the window the wall is
##               bare. A soft-edged decal on the CAMERA_ONLY layer: no
##               geometry, nothing floating, the real sun untouched.
##   "daynight"  DAY / NIGHT. EXT-03's own camera is given a "day-for-night"
##               environment (graded exposure / colour, highlights kept): the
##               same courtyard, the same landmarks, the hull lamps still
##               burning -- in eclipse, while the window shows full sun. The
##               orbit, the sun light and solar generation are never touched.
##               Only offered in real daylight.
##   "eva_window" PHANTOM EVA WORKER. A suited technician in the foot
##               restraints at worksite A1, working the feed box with a
##               ratchet -- through the window only (DIRECT_ONLY). EXT-03
##               shows the worksite empty. No collision, no airlock / suit /
##               EVA state, no crew occupancy -- a picture, nothing more.
## Control: trigger(mode, seconds, source) / clear(). `source` must be
## "event" (the future narrative/event system) or "debug" (tests/tools in a
## debug build). Never random, never on early routine days, never saved
## (a load starts clean), no explanation, no identity.

const CAMERA_ONLY := 1 << 18
const DIRECT_ONLY := 1 << 19
const MODES := ["camera_figure", "window_object", "displaced", "shadow", "daynight", "eva_window"]
## Round 47 variant geometry.
const SHADOW_CENTRE := Vector3(-4.066, 1.02, 0.15)  # on the tunnel hull plate (face x -4.08)
const SHADOW_SIZE := Vector2(0.86, 2.04)
const WORKER_POS := Vector3(-3.55, 0.0, 0.75)       # worksite A1 foot restraints
const WORKER_FACE := Vector3(-3.06, 0.85, 0.75)     # the antenna feed box
var _night_env: Environment
var _cam_env_saved: Variant = null
var _worker_arm: Node3D
var _worker_fore: Node3D
var _worker_t: float = 0.0
const EXTERIOR := 1 << 11
## Service brackets on the airlock tunnel's east wall (face x = -4.2,
## facing the Control Room port): shelf height 1.15 m.
const WALL_X := -4.2
const BRACKET_A := Vector3(-4.2, 1.15, 0.9)
const BRACKET_B := Vector3(-4.2, 1.15, -1.15)
var case_normal: Node3D
var case_shadow: Decal

var active_mode: String = ""
var _left: float = 0.0
var _objs: Dictionary = {}       # name -> Node3D
var history: Array = []          # [{mode, source, t}]


func _ready() -> void:
	add_to_group(&"observation_discrepancy")
	_objs["figure"] = _figure(Vector3(-4.35, 0.0, -3.75), CAMERA_ONLY)
	_bracket("BracketA", BRACKET_A)
	_bracket("BracketB", BRACKET_B)
	# A service work-lamp over the brackets (the wall faces away from the
	# sun most of the orbit) -- lights the story layers too.
	var lamp := OmniLight3D.new()
	lamp.name = "ServiceLamp"
	lamp.position = Vector3(-3.85, 2.25, (BRACKET_A.z + BRACKET_B.z) * 0.5)
	lamp.omni_range = 3.4
	lamp.light_energy = 1.3
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.layers = EXTERIOR
	lamp.light_cull_mask = EXTERIOR | CAMERA_ONLY | DIRECT_ONLY
	add_child(lamp)
	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.12, 0.08, 0.22)
	housing.mesh = hm
	housing.material_override = _mat(Color(0.3, 0.31, 0.33))
	housing.position = Vector3(-4.14, 2.3, lamp.position.z)
	housing.layers = EXTERIOR
	add_child(housing)
	case_normal = _case(BRACKET_A, EXTERIOR)          # normal play: on A, every view
	case_normal.name = "MaintenanceCase"
	_objs["bag_direct"] = _case(BRACKET_A, DIRECT_ONLY)
	_objs["bag_camera"] = _case(BRACKET_B, CAMERA_ONLY)
	# Round 47: the lamp's shadow of the case on the wall below bracket A --
	# the REFERENCE every view agrees on (EXTERIOR: always shown).
	case_shadow = _shadow_decal("CaseShadow", Vector3(-4.066, 0.86, BRACKET_A.z + 0.02), Vector2(0.62, 0.42), 0, EXTERIOR)
	_objs["shadow_cam"] = _shadow_decal("ImpossibleShadow", SHADOW_CENTRE, SHADOW_SIZE, 1, CAMERA_ONLY)
	_objs["eva_worker"] = _worker()
	clear()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


func _layer_all(n: Node3D, layer: int) -> void:
	# Round 46: EXACTLY the given layer (no EXTERIOR bit OR-ed in -- that
	# made story copies visible to every camera).
	for v in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if v is VisualInstance3D:
			(v as VisualInstance3D).layers = layer


## A hull service bracket: wall plate, two shelf arms, a clamp bar, bolts.
## Decor (no collision: never an EVA obstacle, never part of the hull seal).
func _bracket(nm: String, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	root.position = at
	add_child(root)
	var steel := _mat(Color(0.48, 0.5, 0.53))
	var dark := _mat(Color(0.22, 0.23, 0.25))
	var yellow := _mat(Color(0.95, 0.75, 0.12))
	var box := func(size: Vector3, pos: Vector3, m: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = m
		mi.position = pos
		root.add_child(mi)
	box.call(Vector3(0.03, 0.4, 0.56), Vector3(0.015, 0.08, 0), steel)          # wall plate
	for zz in [-0.22, 0.22]:
		box.call(Vector3(0.28, 0.035, 0.04), Vector3(0.155, -0.02, zz), dark)  # shelf arms
		box.call(Vector3(0.03, 0.16, 0.04), Vector3(0.025, -0.1, zz), dark)    # gussets
		box.call(Vector3(0.03, 0.14, 0.035), Vector3(0.28, 0.06, zz), yellow)  # clamp posts
	box.call(Vector3(0.025, 0.03, 0.5), Vector3(0.29, 0.12, 0), yellow)         # clamp bar
	for c in [Vector3(0.035, 0.24, -0.24), Vector3(0.035, 0.24, 0.24), Vector3(0.035, -0.08, -0.24), Vector3(0.035, -0.08, 0.24)]:
		box.call(Vector3(0.015, 0.03, 0.03), c, dark)                           # bolts
	var lb := Label3D.new()
	lb.text = "SVC " + nm.right(1)
	lb.font_size = 22
	lb.pixel_size = 0.0022
	lb.position = Vector3(0.035, 0.24, 0.0)
	lb.rotation_degrees = Vector3(0, 90, 0)
	lb.modulate = Color(0.1, 0.1, 0.1)
	root.add_child(lb)
	_layer_all(root, EXTERIOR)
	return root


## The exterior MAINTENANCE CASE, seated on the shelf of a bracket.
func _case(at: Vector3, layer: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DiscrepancyCase"
	root.position = at + Vector3(0.17, 0.17, 0)
	add_child(root)
	var body := _mat(Color(0.28, 0.33, 0.4))
	var orange := _mat(Color(0.95, 0.45, 0.08))
	var grey := _mat(Color(0.75, 0.76, 0.78))
	var box := func(size: Vector3, pos: Vector3, m: Material) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = m
		mi.position = pos
		root.add_child(mi)
	box.call(Vector3(0.3, 0.3, 0.56), Vector3.ZERO, body)                       # shell
	for zz in [-0.27, 0.27]:
		box.call(Vector3(0.31, 0.31, 0.04), Vector3(0, 0, zz), orange)          # hazard end caps
	for zz in [-0.13, 0.0, 0.13]:
		box.call(Vector3(0.315, 0.025, 0.03), Vector3(0, 0.0, zz), grey)        # ribs
	box.call(Vector3(0.06, 0.04, 0.24), Vector3(0.0, 0.19, 0), grey)            # carry handle
	for zz in [-0.1, 0.1]:
		box.call(Vector3(0.035, 0.04, 0.035), Vector3(0.0, 0.165, zz), grey)    # handle posts
		box.call(Vector3(0.02, 0.06, 0.05), Vector3(0.155, 0.07, zz * 1.7), grey)   # latches
	var lb := Label3D.new()
	lb.text = "MAINT KIT"
	lb.font_size = 26
	lb.pixel_size = 0.0022
	lb.position = Vector3(0.152, -0.06, 0)
	lb.rotation_degrees = Vector3(0, 90, 0)
	lb.modulate = Color(0.95, 0.92, 0.85)
	root.add_child(lb)
	_layer_all(root, layer)
	return root


func _figure(pos: Vector3, layer: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DiscrepancyFigure"
	root.position = pos
	add_child(root)
	var white := _mat(Color(0.85, 0.85, 0.83))
	var parts := [[Vector3(0.42, 0.6, 0.3), Vector3(0, 1.25, 0)], [Vector3(0.16, 0.8, 0.18), Vector3(-0.1, 0.45, 0)], [Vector3(0.16, 0.8, 0.18), Vector3(0.1, 0.45, 0)], [Vector3(0.12, 0.55, 0.14), Vector3(-0.29, 1.2, 0)], [Vector3(0.12, 0.55, 0.14), Vector3(0.29, 1.2, 0)]]
	for p in parts:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		b.mesh = bm
		b.material_override = white
		b.position = p[1]
		root.add_child(b)
	var h := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.17
	hs.height = 0.34
	h.mesh = hs
	h.material_override = white
	h.position = Vector3(0, 1.72, 0)
	root.add_child(h)
	var v := MeshInstance3D.new()
	var vs := SphereMesh.new()
	vs.radius = 0.13
	vs.height = 0.2
	v.mesh = vs
	v.material_override = _mat(Color(0.12, 0.1, 0.06))
	v.position = Vector3(0, 1.72, -0.07)
	root.add_child(v)
	_layer_all(root, layer)
	return root


## A soft lamp shadow projected onto the hull (a Decal: it wraps over the
## plate, ribs and blanket patches like a real shadow, and like any visual
## instance it is culled per camera by its layer). shape 0 = the case (a
## soft rounded box), 1 = a standing person, a little stretched and leaning.
func _shadow_decal(nm: String, centre: Vector3, size: Vector2, shape: int, layer: int) -> Decal:
	var dc := Decal.new()
	dc.name = nm
	# Projection along the decal's -Y: turn it so -Y points into the wall (-X).
	dc.rotation_degrees = Vector3(0, 0, -90)
	dc.position = centre + Vector3(0.12, 0, 0)
	dc.size = Vector3(size.y, 0.36, size.x)          # (height on the wall, depth, width)
	dc.texture_albedo = _shadow_texture(shape)
	dc.modulate = Color(0, 0, 0, 0.5 if shape == 0 else 0.78)
	dc.albedo_mix = 1.0
	dc.upper_fade = 0.0
	dc.lower_fade = 0.0
	dc.layers = layer
	add_child(dc)
	return dc


static func _sd_cap(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa: Vector2 = p - a
	var ba: Vector2 = b - a
	var h: float = clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - r


static func _sd_rbox(p: Vector2, c: Vector2, hs: Vector2, r: float) -> float:
	var d: Vector2 = (p - c).abs() - hs + Vector2(r, r)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - r


## White silhouette with soft alpha edges (u across, v down the wall).
static func _shadow_texture(shape: int) -> ImageTexture:
	var w: int = 96 if shape == 1 else 96
	var h: int = 240 if shape == 1 else 64
	# A Decal maps U along its local X -- here the VERTICAL axis on the wall
	# (local -X... see _shadow_decal) -- so the image is stored transposed:
	# image x = down the wall, image y = across it.
	var img := Image.create(h, w, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2((float(x) + 0.5) / w, (float(y) + 0.5) / h)
			var d: float
			var soft: float
			if shape == 0:
				d = _sd_rbox(p, Vector2(0.5, 0.45), Vector2(0.36, 0.3), 0.12)
				soft = 0.16
			else:
				p.x += (1.0 - p.y) * 0.1                   # a lean, as if from a low lamp
				d = (p - Vector2(0.5, 0.1)).length() - 0.075
				d = minf(d, _sd_cap(p, Vector2(0.5, 0.16), Vector2(0.5, 0.2), 0.035))
				d = minf(d, _sd_rbox(p, Vector2(0.5, 0.36), Vector2(0.13, 0.15), 0.06))
				d = minf(d, _sd_cap(p, Vector2(0.37, 0.24), Vector2(0.3, 0.62), 0.042))   # arms, too long
				d = minf(d, _sd_cap(p, Vector2(0.63, 0.24), Vector2(0.69, 0.6), 0.042))
				d = minf(d, _sd_cap(p, Vector2(0.44, 0.5), Vector2(0.42, 0.98), 0.055))   # legs
				d = minf(d, _sd_cap(p, Vector2(0.56, 0.5), Vector2(0.6, 0.98), 0.055))
				soft = 0.035
			var a: float = 1.0 - smoothstep(-soft * 0.5, soft, d)
			img.set_pixel(y, x, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## The phantom EVA worker: a suited technician (helmet + gold visor, PLSS
## backpack, white suit, gloves, boots) standing in the A1 foot restraints,
## facing the feed box, one arm working a ratchet. DIRECT_ONLY, no
## collision, no shadow, hidden unless the "eva_window" mode is active.
func _worker() -> Node3D:
	var root := Node3D.new()
	root.name = "PhantomEvaWorker"
	add_child(root)
	root.position = WORKER_POS
	var d: Vector3 = WORKER_FACE - WORKER_POS
	root.rotation.y = atan2(-d.x, -d.z)                       # -Z faces the box
	var suit := _mat(Color(0.86, 0.86, 0.83))
	var grey := _mat(Color(0.55, 0.56, 0.58))
	var visor := _mat(Color(0.75, 0.55, 0.18))
	visor.metallic = 0.9
	visor.roughness = 0.15
	# Legs and boots (in the restraints), torso, backpack.
	for zz in [-0.12, 0.12]:
		_wpart(root, _wcap(0.085, 0.82), Vector3(zz, 0.48, 0.02), suit)
		_wpart(root, _wbox(Vector3(0.13, 0.1, 0.27)), Vector3(zz, 0.05, -0.04), grey)
	_wpart(root, _wcap(0.21, 0.72), Vector3(0, 1.22, 0), suit)
	_wpart(root, _wbox(Vector3(0.46, 0.6, 0.24)), Vector3(0, 1.28, 0.27), suit)         # PLSS
	_wpart(root, _wbox(Vector3(0.3, 0.12, 0.06)), Vector3(0, 1.18, -0.2), grey)          # chest control unit
	var helm := SphereMesh.new()
	helm.radius = 0.17
	helm.height = 0.34
	_wpart(root, helm, Vector3(0, 1.73, -0.01), suit)
	var vs := SphereMesh.new()
	vs.radius = 0.135
	vs.height = 0.2
	_wpart(root, vs, Vector3(0, 1.72, -0.08), visor)
	# Left arm on the handrail side (still); right arm working the ratchet.
	_wpart(root, _wcap(0.07, 0.6), Vector3(-0.3, 1.18, -0.12), suit, Vector3(-35, 0, 8))
	_worker_arm = Node3D.new()
	_worker_arm.position = Vector3(0.28, 1.45, -0.02)
	root.add_child(_worker_arm)
	_wpart(_worker_arm, _wcap(0.07, 0.36), Vector3(0, -0.15, -0.06), suit, Vector3(-25, 0, 0))
	_worker_fore = Node3D.new()
	_worker_fore.position = Vector3(0, -0.3, -0.13)
	_worker_arm.add_child(_worker_fore)
	_wpart(_worker_fore, _wcap(0.065, 0.34), Vector3(0, 0, -0.15), suit, Vector3(-90, 0, 0))
	_wpart(_worker_fore, _wbox(Vector3(0.09, 0.1, 0.1)), Vector3(0, 0, -0.33), grey)    # glove + ratchet
	_wpart(_worker_fore, _wbox(Vector3(0.025, 0.025, 0.22)), Vector3(0, 0.02, -0.42), grey)
	_layer_all(root, DIRECT_ONLY)
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.visible = false
	return root


func _wpart(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _wcap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _wbox(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


func _ext03_cam() -> Camera3D:
	var net: Node = get_tree().get_first_node_in_group(&"camera_network") if is_inside_tree() else null
	if net == null or not net.has_method("camera"):
		return null
	return net.camera("EXT-03")


## EXT-03's day-for-night environment (built once): a copy of the world
## environment with exposure / colour graded down to eclipse, highlights
## (hull lamps, the service lamp) kept.
func _night_environment() -> Environment:
	if _night_env != null:
		return _night_env
	var world_env: WorldEnvironment = get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	_night_env = (world_env.environment.duplicate() if world_env != null and world_env.environment != null else Environment.new()) as Environment
	# Tuned against a REAL eclipse rendered on EXT-03 (mean luminance ~42
	# vs ~65 in daylight): darker overall, cooler, less saturated -- the
	# landmarks and the hull lamps stay readable, nothing goes black.
	_night_env.ambient_light_energy = 0.08
	_night_env.adjustment_enabled = true
	_night_env.adjustment_brightness = 0.74
	_night_env.adjustment_contrast = 1.08
	_night_env.adjustment_saturation = 0.5
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0), Color(0.6, 0.63, 0.72), Color(0.97, 0.96, 1.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_night_env.adjustment_color_correction = gt
	return _night_env


## True while EXT-03 is showing the day-for-night picture.
func ext03_night() -> bool:
	var c: Camera3D = _ext03_cam()
	return c != null and _night_env != null and c.environment == _night_env


## Starts a discrepancy. source: "event" (narrative system) or "debug".
func trigger(mode: String, seconds: float = 20.0, source: String = "event") -> bool:
	if not mode in MODES:
		return false
	if source == "debug" and not OS.is_debug_build():
		return false
	if source != "event" and source != "debug":
		return false
	clear()
	active_mode = mode
	_left = seconds
	match mode:
		"camera_figure":
			_objs["figure"].visible = true
		"window_object":
			# The eyes see the case on B; the cameras still see it on A.
			case_normal.visible = true
			_layer_all(case_normal, CAMERA_ONLY)
			_objs["bag_direct"].position = BRACKET_B + Vector3(0.17, 0.17, 0)
			_objs["bag_direct"].visible = true
		"displaced":
			case_normal.visible = false
			_objs["bag_direct"].visible = true
			_objs["bag_camera"].visible = true
		"shadow":
			_objs["shadow_cam"].visible = true
		"daynight":
			var c: Camera3D = _ext03_cam()
			if c == null:
				active_mode = ""
				return false
			_cam_env_saved = c.environment
			c.environment = _night_environment()
		"eva_window":
			_worker_t = 0.0
			_objs["eva_worker"].visible = true
	history.append({"mode": mode, "source": source, "t": Time.get_ticks_msec()})
	return true


func clear() -> void:
	if active_mode == "daynight":
		var c: Camera3D = _ext03_cam()
		if c != null:
			c.environment = _cam_env_saved
		_cam_env_saved = null
	active_mode = ""
	_left = 0.0
	for k in _objs:
		(_objs[k] as Node3D).visible = false
	if case_normal != null:
		case_normal.visible = true                       # back on A, every view
		_layer_all(case_normal, EXTERIOR)
	if _objs.has("bag_direct"):
		_objs["bag_direct"].position = BRACKET_A + Vector3(0.17, 0.17, 0)


func is_active() -> bool:
	return active_mode != ""


func object_position(name: String) -> Vector3:
	return (_objs[name] as Node3D).global_position


func _process(delta: float) -> void:
	if active_mode == "":
		return
	if active_mode == "eva_window" and _worker_arm != null:
		# A ratchet: short, steady strokes with a pause every few -- work,
		# not a wave.
		_worker_t += delta
		var stroke: float = fmod(_worker_t, 3.2)
		var k: float = sin(stroke * TAU * 1.25) if stroke < 2.4 else 0.0
		_worker_fore.rotation.z = deg_to_rad(28.0) * k
		_worker_arm.rotation.x = deg_to_rad(4.0) * k
	_left -= delta
	if _left <= 0.0:
		clear()
