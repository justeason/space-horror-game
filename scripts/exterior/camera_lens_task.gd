extends "res://scripts/station/equipment_base.gd"
## Round 39 Priority 6G: a second, fully playable EVA task -- the EXT-02
## AIRLOCK HATCH camera's lens gets a grime film (outgassing residue /
## thruster soot). It is REAL: a translucent film disc sits just inside
## the camera's near plane, so the feed on the workstation genuinely looks
## smeared, and the camera housing shows the film from outside.
## Chain (work order "lens", from day 9):
##   CHECK FEED (Cameras tab, select EXT-02) -> SUIT UP -> AIRLOCK OUT ->
##   WIPE LENS (float up to the camera mount: two wipes) -> AIRLOCK IN
##   -> VERIFY FEED (view EXT-02 again: clean).

const CAM_ID := "EXT-02"
var dirt: float = 0.0             # 0 clean .. 1 opaque
var request_day: int = -1
var checked: bool = false
var verified_day: int = -1
var _film: MeshInstance3D
var _film_mat: StandardMaterial3D
var _built: bool = false


func _ready() -> void:
	_base_ready(&"lens")
	add_to_group(&"lens_task")
	_build.call_deferred()


func _net() -> Node:
	return get_tree().get_first_node_in_group(&"camera_network") if is_inside_tree() else null


func _build() -> void:
	var net: Node = _net()
	var cam: Camera3D = net.camera(CAM_ID) if net != null else null
	if cam == null:
		return
	_film = MeshInstance3D.new()
	_film.name = "LensFilm"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.085
	cyl.bottom_radius = 0.085
	cyl.height = 0.002
	cyl.radial_segments = 24
	_film.mesh = cyl
	_film.rotation_degrees.x = 90.0
	_film.position = Vector3(0, 0, -0.056)
	_film_mat = StandardMaterial3D.new()
	_film_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_film_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_film_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_film_mat.albedo_texture = _grime_texture()
	_film.material_override = _film_mat
	_film.layers = 1 | (1 << 11)
	_film.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(_film)
	# Wipe point: the camera body (reach it floating).
	ClickPart.make(self, &"lens", Vector3(0.24, 0.22, 0.3), cam, Vector3(0, 0, 0.05))
	_built = true
	_refresh()


static func _grime_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in n:
		for x in n:
			var v: float = 0.55 + 0.45 * sin(x * 0.31 + sin(y * 0.17) * 2.0) * cos(y * 0.23 + x * 0.05) + rng.randf_range(-0.2, 0.2)
			img.set_pixel(x, y, Color(0.42, 0.36, 0.28, clampf(v, 0.15, 1.0)))
	return ImageTexture.create_from_image(img)


func _refresh() -> void:
	if _film_mat != null:
		_film_mat.albedo_color = Color(1, 1, 1, clampf(dirt * 0.85, 0.0, 0.9))
		_film.visible = dirt > 0.02


func _today() -> int:
	return _dp.day_number if _dp != null else 1


func _eva() -> Node:
	return get_tree().get_first_node_in_group(&"eva_system")


func on_part(id: StringName) -> void:
	if id != &"lens":
		return
	var eva: Node = _eva()
	if eva == null or not eva.outside:
		say("The camera is outside the hull.")
		return
	if dirt <= 0.02:
		say("Lens is clean.")
		return
	dirt = maxf(dirt - 0.5, 0.0)
	sfx(&"click")
	say("Lens wiped." if dirt <= 0.02 else "Film partly off — wipe again.")
	_refresh()


func part_prompt(id: StringName) -> String:
	var eva: Node = _eva()
	if id == &"lens" and eva != null and eva.outside and dirt > 0.02:
		return "Click: wipe the %s lens" % CAM_ID
	return ""


## The workstation Cameras tab shows a feed (workstation_shell.gd).
func on_feed_viewed(id: String) -> void:
	if id != CAM_ID or request_day == -1:
		return
	if dirt > 0.02:
		if not checked:
			checked = true
			say("%s feed smeared — the lens needs cleaning (EVA)." % CAM_ID)
			ai_event(&"lens_intro")
	else:
		var eva: Node = _eva()
		if (eva == null or not eva.outside) and verified_day < request_day:
			verified_day = _today()
			sfx(&"success")
			say("%s feed clear." % CAM_ID)


# ------------------------------------------------------------ work order
func order_rearm(seed: int) -> void:
	request_day = _today()
	dirt = 0.7 + float(absi(seed) % 3) * 0.1
	checked = false
	verified_day = -1
	_refresh()


func order_done() -> bool:
	return request_day != -1 and verified_day >= request_day and dirt <= 0.02


func order_feasible() -> bool:
	return _net() != null and _net().camera(CAM_ID) != null


func order_severity() -> int:
	return 1


func order_next() -> Dictionary:
	var eva: Node = _eva()
	var outside: bool = eva != null and eva.outside
	var suited: bool = eva != null and eva.suited
	if dirt > 0.02:
		if not checked:
			return {"action": "View the %s feed (Cameras tab)" % CAM_ID, "short": "CHECK FEED", "room": &"control_room"}
		if outside:
			return {"action": "Float up to the hatch camera, wipe the lens", "short": "WIPE LENS", "room": &"airlock"}
		if not suited:
			return {"action": "Put on the EVA suit (airlock)", "short": "SUIT UP", "room": &"airlock"}
		return {"action": "Airlock chamber: press OUT", "short": "AIRLOCK OUT", "room": &"airlock"}
	if outside:
		return {"action": "Float back into the chamber, press IN", "short": "AIRLOCK IN", "room": &"airlock"}
	return {"action": "View the %s feed again" % CAM_ID, "short": "VERIFY FEED", "room": &"control_room"}


func order_progress() -> String:
	return "%d%%" % roundi((1.0 - dirt) * 100.0)


func order_detail() -> Array:
	return ["Exterior camera %s (above the airlock hatch): lens film %d %%." % [CAM_ID, roundi(dirt * 100.0)], "EVA: tether ring A1 is right below it — rise with Space."]


func state_dict() -> Dictionary:
	return {"dirt": dirt, "request_day": request_day, "checked": checked, "verified_day": verified_day}


func load_dict(d: Dictionary) -> void:
	dirt = float(d.get("dirt", 0.0))
	request_day = int(d.get("request_day", -1))
	checked = bool(d.get("checked", false))
	verified_day = int(d.get("verified_day", -1))
	_refresh()
