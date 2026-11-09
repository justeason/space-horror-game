extends Node
## Round 38 Priorities 1-2, 5, 19: the station's SURVEILLANCE NETWORK.
## One registry of every camera (the three original interior cameras plus
## new interior and EXTERIOR cameras built here), each with an id, label,
## location, map position and a visible physical housing at a believable
## mount point. Feeds are live SubViewport renders of the real 3D world.
##
## PERFORMANCE: a feed renders only while something shows it -- the
## workstation Cameras page (selected camera), the Control Room console
## (its current camera, while the player is in the Control Room). Every
## other camera holds its last frame (UPDATE_DISABLED).
##
## DISCREPANCY LAYERS (Priority 5): visual layer 19 = CAMERA_ONLY (seen by
## surveillance cameras, never by direct observation: the player's eyes,
## the observation port, mirrors); layer 20 = DIRECT_ONLY (the reverse).
## Nothing uses them in normal play; observation_discrepancy.gd does.

const CAM_SCENE := preload("res://scenes/surveillance/surveillance_camera.tscn")
const CAMERA_ONLY := 1 << 18      # visual layer 19
const DIRECT_ONLY := 1 << 19      # visual layer 20
const EXTERIOR := 1 << 11         # visual layer 12 (sunlit exterior)

## id, label, room (map), node name, [position, look target] or "" for the
## original scene cameras, exterior?, intentional blind spot note.
const CAMERAS := [
	["INT-01", "CONTROL ROOM", &"control_room", "CameraControlRoom", null, false, "under the camera, the console's west side"],
	["INT-02", "CORRIDOR → CONTROL", &"main_junction", "CameraCorridor", null, false, "the Control Room corners beside the doorway"],
	["INT-03", "JUNCTION", &"main_junction", "CameraCorridorEnd", null, false, "the Comms tunnel mouth"],
	["INT-04", "ENGINEERING", &"engineering", "CamEngineering", [Vector3(-2.78, 2.95, 6.72), Vector3(-4.6, 0.9, 3.7)], false, "the breaker-panel alcove right below the camera"],
	["INT-05", "LIFE SUPPORT", &"life_support", "CamLifeSupport", [Vector3(-1.48, 2.95, 11.82), Vector3(-4.1, 0.9, 10.0)], false, "the doorway behind the camera"],
	["INT-06", "STORAGE", &"storage", "CamStorage", [Vector3(-5.55, 2.95, 7.05), Vector3(-7.2, 0.7, 8.9)], false, "the near cabinet face"],
	["INT-07", "AIRLOCK CHAMBER", &"airlock", "CamAirlock", [Vector3(-4.47, 2.42, -0.62), Vector3(-4.95, 0.7, -2.5)], false, "right under the camera, by the inner hatch"],
	["INT-08", "COMMS", &"communications", "CamComms", [Vector3(3.22, 2.95, 8.12), Vector3(1.4, 1.0, 6.3)], false, "the alcove behind the camera"],
	["EXT-01", "HULL OVERVIEW", &"", "CamExtHull", [Vector3(9.0, 10.5, -19.0), Vector3(-3.0, 0.5, -2.5)], true, "the south faces of the modules"],
	["EXT-02", "AIRLOCK HATCH", &"airlock", "CamExtAirlock", [Vector3(-3.45, 3.05, -3.75), Vector3(-4.8, 0.9, -2.75)], true, "directly beneath the camera mount"],
	["EXT-03", "OBSERVATION", &"control_room", "CamExtObservation", [Vector3(-1.62, 3.25, 2.92), Vector3(-3.6, 1.0, 0.2)], true, "the walkway behind the antenna mast"],
	["EXT-04", "ANTENNA A1", &"airlock", "CamExtAntenna", [Vector3(-4.12, 2.55, 2.45), Vector3(-2.85, 0.75, 0.75)], true, "the far side of the feed box"],
	# Round 41: the solar truss / left wing, from the airlock roof.
	["EXT-05", "SOLAR TRUSS", &"airlock", "CamExtSolar", [Vector3(-4.6, 3.75, -3.3), Vector3(-15.0, 1.0, -5.4)], true, "the right wing and the truss's north face"],
]

## Round 39 Priority 6A: a CURATED set of six useful feeds (the rest of the
## table stays documented but is not built -- fewer, better cameras, and
## less rendering): the main corridor, Engineering, Life Support, the
## airlock CHAMBER (inside it, looking at the outer hatch), the hatch from
## outside, and the courtyard also seen through the observation port.
## Round 41: + EXT-01 (the whole vehicle with both solar wings) and
## EXT-05 (the solar truss route). Still only the displayed feed renders.
const CURATED := ["INT-02", "INT-04", "INT-05", "INT-07", "EXT-01", "EXT-02", "EXT-03", "EXT-05"]

var cams: Dictionary = {}        # id -> {vp: SubViewport, label, room, exterior, blind, pos}
var _demand: Dictionary = {}     # requester -> camera id
var _t: float = 0.0


func _ready() -> void:
	add_to_group(&"camera_network")
	var root: Node = get_parent()
	var surv: Node = root.get_node_or_null("Surveillance")
	for c in CAMERAS:
		if not c[0] in CURATED:
			continue
		var vp: SubViewport = null
		if c[4] == null:
			vp = surv.get_node_or_null(c[3]) if surv != null else null
		else:
			vp = CAM_SCENE.instantiate()
			vp.name = c[3]
			vp.camera_id = StringName(c[0])
			if surv != null:
				surv.add_child(vp)
			else:
				add_child(vp)
			var cam: Camera3D = vp.get_node("Camera3D")
			cam.current = true
			cam.fov = 78.0 if c[5] else 72.0
			cam.far = 900.0 if c[5] else 80.0
			cam.look_at_from_position(c[4][0], c[4][1], Vector3.UP)
		if vp == null:
			continue
		vp.size = Vector2i(384, 288)   # Round 38: only displayed feeds render, so afford more detail
		var cam3: Camera3D = vp.get_node("Camera3D")
		cam3.cull_mask = cam3.cull_mask & ~DIRECT_ONLY
		_build_housing(cam3, bool(c[5]))
		cams[c[0]] = {"vp": vp, "label": c[1], "room": c[2], "exterior": c[5], "blind": c[6], "cam": cam3}
	# The player's eyes never see CAMERA_ONLY objects.
	var pc: Camera3D = root.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D")
	if pc != null:
		pc.cull_mask = pc.cull_mask & ~CAMERA_ONLY
	var mir: Node = root.get_node_or_null("Mirrors/LivingQuartersMirror")
	if mir != null:
		for n in mir.find_children("*", "Camera3D", true, false):
			n.cull_mask = n.cull_mask & ~CAMERA_ONLY
	for id in cams:
		(cams[id]["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


## A small physical camera body at the mount (bracket, body, lens ring,
## status LED) -- on a layer the camera itself does not render.
func _build_housing(cam: Camera3D, exterior: bool) -> void:
	var h := Node3D.new()
	h.name = "Housing"
	cam.add_child(h)
	var mat := func(c: Color, m: float) -> StandardMaterial3D:
		var s := StandardMaterial3D.new()
		s.albedo_color = c
		s.metallic = m
		s.roughness = 0.5
		return s
	var body := CSGBox3D.new()
	body.size = Vector3(0.09, 0.08, 0.16) * (1.3 if exterior else 1.0)
	body.position = Vector3(0, 0, 0.1)
	body.material = mat.call(Color(0.82, 0.83, 0.82) if exterior else Color(0.2, 0.21, 0.23), 0.4)
	h.add_child(body)
	var lens := CSGCylinder3D.new()
	lens.radius = 0.03
	lens.height = 0.03
	lens.rotation_degrees.x = 90.0
	lens.position = Vector3(0, 0, 0.012)
	lens.material = mat.call(Color(0.05, 0.05, 0.06), 0.8)
	h.add_child(lens)
	var led := CSGSphere3D.new()
	led.radius = 0.006
	led.position = Vector3(0.03, 0.03, 0.03)
	var lm := StandardMaterial3D.new()
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.15, 0.1) * 1.5
	lm.albedo_color = Color(1.0, 0.2, 0.15)
	led.material = lm
	h.add_child(led)
	var arm := CSGBox3D.new()
	arm.size = Vector3(0.025, 0.12, 0.025)
	arm.position = Vector3(0, 0.08, 0.14)
	arm.material = mat.call(Color(0.3, 0.31, 0.33), 0.6)
	h.add_child(arm)
	for n in h.find_children("*", "GeometryInstance3D", true, false) + [h]:
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = (1 << 15) | (EXTERIOR if exterior else 0)
	cam.cull_mask = cam.cull_mask & ~(1 << 15)


func ids() -> Array:
	var out: Array = []
	for c in CAMERAS:
		if cams.has(c[0]):
			out.append(c[0])
	return out


func feed(id: String) -> Texture2D:
	return (cams[id]["vp"] as SubViewport).get_texture() if cams.has(id) else null


func info(id: String) -> Dictionary:
	return cams.get(id, {})


func camera(id: String) -> Camera3D:
	return cams[id]["cam"] if cams.has(id) else null


## A display asks for a camera (requester = any stable key); "" releases.
func request(requester: String, id: String) -> void:
	if id == "":
		_demand.erase(requester)
	else:
		_demand[requester] = id
	_apply()


func is_rendering(id: String) -> bool:
	return cams.has(id) and (cams[id]["vp"] as SubViewport).render_target_update_mode == SubViewport.UPDATE_ALWAYS


func _apply() -> void:
	var want: Dictionary = {}
	for r in _demand:
		want[_demand[r]] = true
	for id in cams:
		var vp: SubViewport = cams[id]["vp"]
		var mode: int = SubViewport.UPDATE_ALWAYS if want.has(id) else SubViewport.UPDATE_DISABLED
		if vp.render_target_update_mode != mode:
			vp.render_target_update_mode = mode


## Can camera `id` see world point p (in its frustum, nothing solid in
## between, or the first thing hit is within `tolerance` of it -- e.g. the
## surface of a body standing there)? Used to verify coverage / blind spots.
func sees(id: String, p: Vector3, tolerance: float = 0.3) -> bool:
	var cam: Camera3D = camera(id)
	if cam == null or cam.is_position_behind(p):
		return false
	var sp: Vector2 = cam.unproject_position(p)
	var vs: Vector2 = Vector2((cams[id]["vp"] as SubViewport).size)
	if sp.x < 0 or sp.y < 0 or sp.x > vs.x or sp.y > vs.y:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, 1)
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < tolerance


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	# The Control Room console shows its current camera only while the
	# player is in the Control Room.
	var root: Node = get_parent()
	var pc: Node3D = root.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D")
	var console: Node = root.get_node_or_null("Interactables/SurveillanceConsole")
	if pc != null and console != null and console.has_method("get_current_camera_id"):
		var in_ctrl: bool = absf(pc.global_position.x) < 1.6 and pc.global_position.z > -1.4 and pc.global_position.z < 2.4
		var cid: String = String(console.get_current_camera_id())
		var id := ""
		for k in cams:
			if (cams[k]["vp"] as SubViewport).camera_id == StringName(cid) or k == cid:
				id = k
		request("console", id if in_ctrl else "")
