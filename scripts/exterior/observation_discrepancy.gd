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
##   "window_object"  a tethered tool bag drifting by the mast: window only;
##   "displaced"      the same tool bag: near the mast for the eyes/port,
##                    near the hatch on camera.
## Control: trigger(mode, seconds, source) / clear(). `source` must be
## "event" (the future narrative/event system) or "debug" (tests/tools in a
## debug build). Never random, never on early routine days, never saved
## (a load starts clean), no explanation, no identity.

const CAMERA_ONLY := 1 << 18
const DIRECT_ONLY := 1 << 19
const MODES := ["camera_figure", "window_object", "displaced"]

var active_mode: String = ""
var _left: float = 0.0
var _objs: Dictionary = {}       # name -> Node3D
var history: Array = []          # [{mode, source, t}]


func _ready() -> void:
	add_to_group(&"observation_discrepancy")
	_objs["figure"] = _figure(Vector3(-4.35, 0.0, -3.75), CAMERA_ONLY)
	_objs["bag_direct"] = _bag(Vector3(-2.6, 1.7, 1.55), DIRECT_ONLY)
	_objs["bag_camera"] = _bag(Vector3(-4.6, 1.5, -3.95), CAMERA_ONLY)
	clear()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


func _layer_all(n: Node3D, layer: int) -> void:
	for v in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if v is VisualInstance3D:
			(v as VisualInstance3D).layers = layer | (1 << 11)


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


func _bag(pos: Vector3, layer: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DiscrepancyBag"
	root.position = pos
	add_child(root)
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.22, 0.2)
	b.mesh = bm
	b.material_override = _mat(Color(0.75, 0.45, 0.1))
	root.add_child(b)
	var strap := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.02, 0.5, 0.02)
	strap.mesh = sm
	strap.material_override = _mat(Color(0.9, 0.85, 0.2))
	strap.position = Vector3(0.1, 0.35, 0)
	root.add_child(strap)
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
			_objs["bag_direct"].visible = true
		"displaced":
			_objs["bag_direct"].visible = true
			_objs["bag_camera"].visible = true
	history.append({"mode": mode, "source": source, "t": Time.get_ticks_msec()})
	return true


func clear() -> void:
	active_mode = ""
	_left = 0.0
	for k in _objs:
		(_objs[k] as Node3D).visible = false


func is_active() -> bool:
	return active_mode != ""


func object_position(name: String) -> Vector3:
	return (_objs[name] as Node3D).global_position


func _process(delta: float) -> void:
	if active_mode == "":
		return
	_left -= delta
	var bag: Node3D = _objs["bag_direct"]
	bag.position.y = 1.7 + sin(Time.get_ticks_msec() / 900.0) * 0.08
	bag.rotation.y += delta * 0.3
	if _left <= 0.0:
		clear()
