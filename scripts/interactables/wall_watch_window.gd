extends StaticBody3D
## The Control Room's OBSERVATION PORT (west wall). Locked design (see the
## project memory "watch window"): it must read as a real spacecraft port,
## never a monitor -- round, a thick bolted structural rim integrated into
## the wall, glass recessed behind it; no interact(); one fixed viewpoint;
## the set_feed_override() seam kept for future divergence.
##
## Round 47: a REAL TWO-WAY OPENING. Rounds 38-46 drew the exterior on an
## opaque quad from an off-axis portal camera; the wall and the hull plate
## behind it stayed solid, so from the airlock-tunnel port or on EVA the
## Control Room "window" was a dark emissive disc (the player-reported
## solid-colour window). Now a cylinder is cut through the west wall (CSG)
## and the hull plate (exterior_builder), two transparent panes sit in the
## bore (cabin pane here + outer pressure pane on the hull), and a collision pane keeps the
## hull sealed. Inside you see the exterior directly; outside you see the
## lit Control Room. The player's eyes never render CAMERA_ONLY, so the
## direct-view rule is unchanged -- and one SubViewport fewer renders.

@export var camera_path: NodePath      # kept: the original fixed feed (fallback / seam)
const RADIUS := 0.34
const GLASS_X := 0.018                 # glass, recessed 5 cm behind the bezel front (local X = into the room; 0 = wall face)
const WALL_DEPTH := 0.46               # wall + hull plating to clip behind the glass
const CAMERA_ONLY := 1 << 18

@onready var screen_mesh: MeshInstance3D = $Screen

var _camera: Node = null
var _feed_override: Texture2D = null
var _glass: MeshInstance3D            # cabin pane (transparent)
var _override_disc: MeshInstance3D    # only while a feed override is set
var _glass_mat: ShaderMaterial
var bore_cut: CSGCylinder3D


func _ready() -> void:
	_camera = get_node_or_null(camera_path)
	var old_back: Node3D = get_node_or_null("Backplate")
	if old_back != null:
		old_back.visible = false
	screen_mesh.visible = false
	_build_port()
	_cut_bore()
	_update_screen()


func _build_port() -> void:
	var rim_m := StandardMaterial3D.new()
	rim_m.albedo_color = Color(0.36, 0.37, 0.39)
	rim_m.metallic = 0.75
	rim_m.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.17, 0.18)
	dark.metallic = 0.6
	# Outer structural ring (flush with the wall) and inner bezel step.
	# [outer radius, ring width, x (proud of the wall face), material]
	for spec in [[RADIUS + 0.1, 0.06, 0.025, rim_m], [RADIUS + 0.04, 0.07, 0.05, dark], [RADIUS + 0.006, 0.03, GLASS_X + 0.012, dark]]:
		var ring := CSGTorus3D.new()
		ring.inner_radius = spec[0] - spec[1]
		ring.outer_radius = spec[0]
		ring.ring_sides = 8
		ring.sides = 40
		ring.rotation_degrees.z = 90.0
		ring.position.x = spec[2]
		ring.material = spec[3]
		add_child(ring)
	# Bolts around the rim.
	for k in 12:
		var a: float = TAU * k / 12.0
		var bolt := CSGCylinder3D.new()
		bolt.radius = 0.014
		bolt.height = 0.03
		bolt.rotation_degrees.z = 90.0
		bolt.position = Vector3(0.06, cos(a) * (RADIUS + 0.07), sin(a) * (RADIUS + 0.07))
		bolt.material = dark
		add_child(bolt)
	# The panes: real transparent glass (both faces), cabin and outer.
	# Round 47: one cabin pane here; the outer pressure pane is the exterior
	# builder's glass on the hull face. Faint tints only -- four stacked,
	# sun-lit panes (with the tunnel port's) hazed the far view.
	_glass = _pane("Glass", GLASS_X, Color(0.62, 0.72, 0.8, 0.035))
	# Collision: the opening is sealed by the panes (hull leak sweep and
	# player capsule), sized to the whole bore.
	var col: CollisionShape3D = get_node_or_null("Collision")
	if col != null:
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.06, RADIUS * 2.0 + 0.04, RADIUS * 2.0 + 0.04)
		col.shape = bs
		col.position = Vector3(-0.02, 0, 0)
	# The feed-override seam: an opaque disc shown only while a texture is set.
	_override_disc = MeshInstance3D.new()
	_override_disc.name = "OverrideDisc"
	var q := QuadMesh.new()
	q.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	_override_disc.mesh = q
	_override_disc.rotation_degrees.y = 90.0
	_override_disc.position.x = GLASS_X + 0.002
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D view : source_color, filter_linear;
void fragment() {
	if (length(UV - vec2(0.5)) > 0.5) { discard; }
	ALBEDO = texture(view, UV).rgb;
}"""
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = sh
	_override_disc.material_override = _glass_mat
	_override_disc.visible = false
	add_child(_override_disc)


func _pane(nm: String, x: float, tint: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS + 0.004
	cyl.bottom_radius = RADIUS + 0.004
	cyl.height = 0.012
	cyl.radial_segments = 40
	cyl.rings = 1
	mi.mesh = cyl
	mi.rotation_degrees.z = 90.0
	mi.position.x = x
	mi.material_override = preload("res://scripts/exterior/port_glass.gd").material(Color(tint.r, tint.g, tint.b))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1                      # cabin side: lit by the cabin, never by the sun
	add_child(mi)
	return mi


## The real opening through the Control Room west wall (CSG subtraction).
func _cut_bore() -> void:
	var wall: CSGBox3D = get_node_or_null("../../Geometry/ControlRoomWestWall") as CSGBox3D
	if wall == null:
		return
	bore_cut = CSGCylinder3D.new()
	bore_cut.name = "ObservationPortBore"
	bore_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	bore_cut.radius = RADIUS
	bore_cut.height = wall.size.x + 0.1
	bore_cut.sides = 40
	wall.add_child(bore_cut)
	bore_cut.global_transform = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(90.0)), global_position + global_transform.basis.x * (-wall.size.x * 0.5))


## True when the port is a real see-through opening (no portal render).
func is_real_opening() -> bool:
	return bore_cut != null and bore_cut.is_inside_tree() and _override_disc != null and not _override_disc.visible


func set_feed_override(tex: Texture2D) -> void:
	_feed_override = tex
	_update_screen()


func _update_screen() -> void:
	if _glass_mat == null:
		return
	_glass_mat.set_shader_parameter("view", _feed_override)
	_override_disc.visible = _feed_override != null
