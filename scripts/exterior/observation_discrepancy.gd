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
## Control: trigger(mode, seconds, source) / clear(). `source` must be
## "event" (the future narrative/event system) or "debug" (tests/tools in a
## debug build). Never random, never on early routine days, never saved
## (a load starts clean), no explanation, no identity.

const CAMERA_ONLY := 1 << 18
const DIRECT_ONLY := 1 << 19
const MODES := ["camera_figure", "window_object", "displaced"]
const EXTERIOR := 1 << 11
## Service brackets on the airlock tunnel's east wall (face x = -4.2,
## facing the Control Room port): shelf height 1.15 m.
const WALL_X := -4.2
const BRACKET_A := Vector3(-4.2, 1.15, 0.9)
const BRACKET_B := Vector3(-4.2, 1.15, -1.15)
var case_normal: Node3D

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
	history.append({"mode": mode, "source": source, "t": Time.get_ticks_msec()})
	return true


func clear() -> void:
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
	_left -= delta
	if _left <= 0.0:
		clear()
