extends StaticBody3D
## The Control Room's OBSERVATION PORT (west wall). Locked design (see the
## project memory "watch window"): it must read as a real spacecraft port,
## never a monitor -- round, a thick bolted structural rim integrated into
## the wall, glass recessed behind it; no interact(); one fixed viewpoint;
## the set_feed_override() seam kept for future divergence.
##
## Round 38: the glass shows the REAL exterior as DIRECT observation -- a
## portal render from the player's own eye position (off-axis frustum
## through the glass, near plane beyond the wall and hull plating), so it
## has true parallax as you move. It looks into the EVA courtyard at
## antenna mast A1 -- the region exterior cameras EXT-03 / EXT-04 also
## cover. As a DIRECT view it never renders CAMERA_ONLY objects (see
## observation_discrepancy.gd). It renders only while the player is in the
## Control Room.

@export var camera_path: NodePath      # kept: the original fixed feed (fallback / seam)
const RADIUS := 0.34
const GLASS_X := 0.018                 # glass, recessed 5 cm behind the bezel front (local X = into the room; 0 = wall face)
const WALL_DEPTH := 0.46               # wall + hull plating to clip behind the glass
const CAMERA_ONLY := 1 << 18

@onready var screen_mesh: MeshInstance3D = $Screen

var _camera: Node = null
var _feed_override: Texture2D = null
var _vp: SubViewport
var _cam: Camera3D
var _glass: MeshInstance3D
var _glass_mat: ShaderMaterial


func _ready() -> void:
	_camera = get_node_or_null(camera_path)
	var old_back: Node3D = get_node_or_null("Backplate")
	if old_back != null:
		old_back.visible = false
	screen_mesh.visible = false
	_build_port()
	_vp = SubViewport.new()
	_vp.name = "PortalView"
	_vp.size = Vector2i(512, 512)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = _cam.cull_mask & ~CAMERA_ONLY
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(_cam)
	_cam.current = true
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
	# The glass: a quad facing into the room, shown as a circle.
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	var q := QuadMesh.new()
	q.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	_glass.mesh = q
	_glass.rotation_degrees.y = 90.0      # quad +Z -> local +X (into the room)
	_glass.position.x = GLASS_X
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D view : source_color, filter_linear;
uniform float tint = 0.06;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	if (r > 1.0) { discard; }
	vec3 c = texture(view, UV).rgb;
	// a faint glass sheen toward the rim
	c = mix(c, vec3(0.55, 0.65, 0.75), tint * smoothstep(0.55, 1.0, r));
	ALBEDO = c;
}"""
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = sh
	_glass.material_override = _glass_mat
	add_child(_glass)


func set_feed_override(tex: Texture2D) -> void:
	_feed_override = tex
	_update_screen()


func portal_camera() -> Camera3D:
	return _cam


func portal_viewport() -> SubViewport:
	return _vp


func _update_screen() -> void:
	if _glass_mat == null:
		return
	var tex: Texture2D = _feed_override if _feed_override != null else (_vp.get_texture() if _vp != null else null)
	_glass_mat.set_shader_parameter("view", tex)


## Off-axis portal camera from the viewer's eye through the glass.
func _process(_d: float) -> void:
	var eye_cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if eye_cam == null or _cam == null:
		return
	var eye: Vector3 = eye_cam.global_position
	var gx: Transform3D = global_transform
	var c: Vector3 = gx * Vector3(GLASS_X, 0, 0)
	var n: Vector3 = gx.basis.x.normalized()          # into the room
	var up: Vector3 = gx.basis.y.normalized()
	var right: Vector3 = up.cross(n).normalized()     # viewer's right looking out
	var d: float = (eye - c).dot(n)
	var in_room: bool = absf(eye.x) < 1.6 and eye.z > -1.4 and eye.z < 2.4 and d > 0.05
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if (in_room and _feed_override == null) else SubViewport.UPDATE_DISABLED
	if not in_room:
		return
	_cam.global_transform = Transform3D(Basis(right, up, n), eye)
	var near: float = d + WALL_DEPTH
	var k: float = near / d
	var rel: Vector3 = c - eye
	_cam.set_frustum(RADIUS * 2.0 * k, Vector2(rel.dot(right), rel.dot(up)) * k, near, 900.0)
