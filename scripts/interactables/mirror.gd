extends SubViewport
## Round 17 Priority 5: a Living Quarters wash-station mirror's live
## reflection feed -- same "a SubViewport is a real, continuously-
## updating texture any display can show" pattern as
## scripts/surveillance/surveillance_camera.gd (own_world_3d left at
## its default false, so this renders the SAME shared 3D world the main
## scene uses, not an isolated diorama world -- it must see the real
## room and the real player). Unlike a surveillance camera, this one's
## Camera3D has no fixed pose: every frame it is repositioned to the
## true planar-mirror reflection of the player's own camera across this
## mirror's physical plane, so what's shown updates live as the player
## moves and turns, the way a real mirror would.
##
## HONEST LIMITATIONS (Round 19 Priority 1 replaced the whole camera
## model with a genuine off-axis/portal projection -- see
## _update_reflection()'s own doc comment for the full before/after and
## why; the points below describe what's still approximate after that
## fix, not bugs):
## - The TRUE optical mirror-reflection point for a wall-mounted mirror
##   this close to the player (the room is under a metre deep here)
##   lands outside the station's own hull -- there is a solid wall, and
##   then nothing modelled at all, a few centimetres behind the glass.
##   The virtual eye now deliberately sits slightly BEHIND the glass
##   (inside that wall/cabinet volume) rather than true optical depth,
##   because the off-axis frustum math requires looking back THROUGH
##   the glass, not from in front of it -- see
##   _VIRTUAL_EYE_DEPTH_BEHIND_GLASS. This is viable specifically
##   because a solid, single-sided CSGBox3D is backface-culled from the
##   inside (its own surfaces don't occlude a camera sitting inside it),
##   so the wall/cabinet geometry itself does not block the view -- but
##   it also means anything the off-axis frustum frames THAT ISN'T the
##   player's own nearby body or the room's near walls (i.e. open space
##   past where real geometry ends) renders as void/sky-gradient rather
##   than a believable backdrop. In practice the player's own body fills
##   most of the frame at normal mirror-viewing distance, so this is a
##   minor cosmetic gap at the frame's edges, not a broken reflection --
##   documented here rather than silently left for someone else to find.
## - LEFT/RIGHT and UP/DOWN orientation: CONFIRMED CORRECT by render
##   (Round 18), using asymmetric marker cubes specifically because a
##   roughly-symmetric reflected body can hide an orientation bug --
##   see _ready()'s own comment for exactly what was found and fixed.
##   Still correct under the Round 19 off-axis rebuild since the glass
##   material's own uv1_scale correction is orientation-of-camera-
##   independent (re-verified by render this round).
## - It reflects only THIS one flat plane -- no recursive/other-mirror
##   reflections, and no reflection of the mirror's own frame.
## - The reflected body uses this project's existing static-CSG
##   StandingPose (plus the new HeadGroup -- see player_body.gd) with
##   no skeleton: it shows the correct torso/arm/leg silhouette, facing
##   direction, and the SAME look-yaw/pitch follow the world body
##   already has, but it does not independently animate a walk cycle,
##   blink, or track the mirror with its eyes beyond that shared yaw/
##   pitch follow.

@export var player_camera_path: NodePath
@export var mirror_plane_path: NodePath
## The physical glass CSG surface in main.tscn this feed is painted
## onto -- same "a script owns wiring its own feed onto whatever mesh
## it's told about" responsibility wall_watch_window.gd uses, except
## here the mirror script itself does it (there is no separate display
## object; the glass IS the display).
@export var glass_mesh_path: NodePath

@onready var _mirror_camera: Camera3D = $Camera3D

## Round 20 Priority 1 fix: Round 19 set this to 0.05m -- "just enough
## to define a near plane" -- without accounting for what that does to
## the resulting field of view. Because _asymmetric_frustum_for()'s
## `size` (the frustum's vertical extent, 2*_GLASS_HALF_HEIGHT = 0.42m)
## is CONSTANT regardless of eye depth (proven algebraically: the glass
## corners' projected extent onto the eye's own right/up axes reduces
## to exactly ±half-width/±half-height regardless of eye position), the
## ONLY thing eye depth controls is the frustum's HALF-ANGLE, i.e. how
## wide the effective field of view is: half_angle = atan(half_height /
## depth). At depth=0.05 that is atan(0.21/0.05) ≈ 77°, a ~153° full
## vertical FOV -- genuinely fisheye-level, not a normal lens -- which
## is the actual, confirmed (by render, not just this derivation) cause
## of "stretched, elongated, skewed" reported this round, and WHY it
## reads as worse at oblique angles: wide-angle-lens stretching is
## always most visible for off-centre content and grazing viewing
## angles, exactly the reported symptom. The fix is not a new
## projection technique, only picking a depth whose resulting FOV is
## actually plausible for looking in a mirror: 0.4m gave atan(0.21/0.4)
## ≈ 28° half-angle (~56° full vertical FOV).
##
## Round 21 Priority 2: playtest feedback was that the reflection still
## "feels a bit extended/stretchy," with a suggestion to try REDUCING
## this depth further. The math above shows that is backwards: this is
## exactly the same half_angle = atan(half_height / depth) relationship
## that made depth=0.05 fisheye-stretched in the first place -- a
## SMALLER depth means a WIDER half-angle (more wide-angle-lens
## stretch), not less. A real mirror viewed from a normal standing
## distance reads less like a wide-angle lens and more like a flattering
## portrait-length one (roughly 30-35mm full-frame equivalent), AND
## there is a second, independent reason the same direction helps: the
## virtual eye's total distance to the player's own reflected body is
## (the player's real distance in front of the glass) + depth, so a
## larger depth also pushes the apparent subject distance further away,
## directly reducing the near-field "selfie" perspective stretching a
## close-up subject gets regardless of lens angle. Both effects point
## the same way -- INCREASE depth, not decrease it -- so this was raised
## to 0.8m: atan(0.21/0.8) ≈ 14.7° half-angle (~29° full vertical FOV),
## a noticeably tighter, less stretched, more natural mirror framing,
## confirmed by render (see the Round 21 report) rather than assumed.
## Reducing depth, as first suggested, would have made the reported
## symptom measurably worse, not better -- the fix follows the actual
## math/render evidence instead.
const _MIN_EYE_DEPTH: float = 0.8
## Round 47: with a FIXED 0.8 m depth the floor-length glass (half-height
## 0.95 m) would be framed at a ~50 deg half-angle -- a too-wide, shrunken
## reflection. The depth now follows the glass so the half-angle never
## exceeds MAX_HALF_ANGLE_DEG (same look as the old glass; nearer to a
## true reflection's scale).
const MAX_HALF_ANGLE_DEG: float = 44.0
var _VIRTUAL_EYE_DEPTH_BEHIND_GLASS: float = 0.8
## Half-width/half-height of the physical glass rectangle -- the actual
## portal window the off-axis frustum is built to exactly frame.
##
## Round 24 Priority 3: the glass was enlarged (0.5 x 0.42 -> 0.56 x 0.9,
## extended down toward the basin) so more of the body is visible. These
## are now READ from the glass CSGBox3D's own `size` in _ready() rather
## than hard-coded, so the frustum, the feed texture's aspect ratio and
## the physical glass can never drift apart again. The defaults below
## are only a fallback for a glass node that isn't a CSGBox3D.
var _glass_half_width: float = 0.25
var _glass_half_height: float = 0.21
## Feed texture resolution per metre of glass (the original 0.5 x 0.42
## glass used a 500 x 420 viewport, i.e. 1000 px/m).
## Round 47: the mirror became FLOOR-LENGTH (0.6 x 1.9 m, was 0.56 x 0.9);
## 760 px/m keeps the feed's pixel count close to the old one (456 x 1444).
const _FEED_PIXELS_PER_METRE: float = 760.0
const _FAR_CLIP: float = 30.0

var _player_camera: Camera3D = null
var _mirror_plane: Node3D = null


## Round 21 Priority 1: ROOT CAUSE of "the reflected raised hand/arm
## still looks like a bunch of cylinders," confirmed directly by render
## comparison, NOT the world body's own geometry quality at all (that
## was already substantially improved -- see player_body.gd's own
## Round 21 doc comment on the new lofted-tube limb mesh). This
## camera's `cull_mask` was never set, so it kept Camera3D's own
## default (every layer, including layer 2 -- the layer
## first_person_watch_rig.tscn's ArmGroup/WatchAssembly live on, see
## that scene's own `layers = 2`). That rig is a plain CHILD OF THE
## PLAYER'S OWN CAMERA3D, positioned right at the player's eye point,
## deliberately meant to be seen ONLY by the player's own first-person
## view when the watch is raised (see that script's own class doc
## comment) -- but with no cull_mask override here, this camera (and
## every other non-player camera in the game) renders it too. Standing
## close to the mirror with the watch raised, that rig's own geometry
## (a SEPARATE, never-upgraded-this-round, literally SKIN-COLORED
## cylinder-and-sphere forearm+hand, confirmed by reading
## first_person_watch_rig.tscn's Mat_skin resource) sits almost exactly
## where the reflection's head/chest is -- which is what was actually
## being seen and reported as "still cylinders," not the dark-gloved
## world-body arm this round's work went into. The fix mirrors
## player.tscn's OWN camera, which already excludes the symmetric case
## (HeadGroup's layer, value 4, excluded from the PLAYER's own camera
## so it never sees its own head) -- here the first-person rig's layer
## (value 2) is excluded from every OTHER camera instead, so only the
## player's own first-person view ever shows that rig, and every other
## viewpoint (this mirror, any future third-person/multiplayer camera)
## shows only the real world-body arm.
const _EXCLUDE_FIRST_PERSON_RIG_LAYER: int = 2


func _ready() -> void:
	# Same reasoning as SurveillanceCamera: not in a SubViewportContainer,
	# so nothing else would mark this viewport "visible" each frame.
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_player_camera = get_node_or_null(player_camera_path)
	_mirror_plane = get_node_or_null(mirror_plane_path)
	_mirror_camera.cull_mask = _mirror_camera.cull_mask & ~_EXCLUDE_FIRST_PERSON_RIG_LAYER

	var glass: GeometryInstance3D = get_node_or_null(glass_mesh_path)
	if glass is CSGBox3D:
		var glass_size: Vector3 = (glass as CSGBox3D).size
		_glass_half_width = glass_size.x * 0.5
		_glass_half_height = glass_size.y * 0.5
		size = Vector2i(roundi(glass_size.x * _FEED_PIXELS_PER_METRE), roundi(glass_size.y * _FEED_PIXELS_PER_METRE))
		_VIRTUAL_EYE_DEPTH_BEHIND_GLASS = maxf(_MIN_EYE_DEPTH, _glass_half_height / tan(deg_to_rad(MAX_HALF_ANGLE_DEG)))
	if glass != null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = get_feed_texture()
		# Round 18 Priority 1 fix: two INDEPENDENT, confirmed-separately
		# orientation bugs, found with asymmetric marker cubes (never
		# assumed/guessed -- see tests/test_mirror_reflection.gd and the
		# Round 18 report for the actual before/after renders):
		#
		# 1. LEFT/RIGHT: the mirror camera in _update_reflection() is an
		#    ORDINARY (proper, non-reflected) camera placed in front of the
		#    glass and aimed back at the player -- correct for ITS OWN
		#    purpose (a marker toward world -X lands on the camera's own
		#    left, exactly as plain 3D geometry predicts for a camera
		#    looking back the opposite way), but that is NOT what a true
		#    mirror shows: reflecting across this glass's Z-normal plane
		#    leaves left/right as the PLAYER would see it UNCHANGED from
		#    their own direct view, which a raw, un-corrected camera capture
		#    gets backwards. uv1_scale.x=-1 corrects this -- cheaply, as a
		#    2D texture operation -- without reflecting the 3D camera's own
		#    basis (which would also flip triangle winding and break
		#    backface culling for everything seen through the mirror).
		# 2. UP/DOWN: independent of the above, this specific CSGBox3D
		#    face's OWN default UV mapping (main.tscn's WashMirrorGlass)
		#    turned out to already invert V -- confirmed by comparing the
		#    raw SubViewport capture (asymmetric marker correctly top-left)
		#    against the same texture painted on the glass with only the
		#    U-flip applied (the SAME marker rendered bottom-right, i.e.
		#    vertically flipped too, which nothing in this script's own
		#    logic causes) -- this is what the player experienced as "the
		#    reflection is upside down." uv1_scale.y=-1 corrects it.
		mat.uv1_scale = Vector3(-1.0, -1.0, 1.0)
		mat.uv1_offset = Vector3(1.0, 1.0, 0.0)
		glass.material_override = mat


func _process(_delta: float) -> void:
	if _player_camera == null or _mirror_plane == null:
		return
	_update_reflection()


func get_feed_texture() -> Texture2D:
	return get_texture()


## Round 19 Priority 1 fix (SECOND, final pass): ROOT CAUSE of "behaves
## like a fixed camera displaying a scene, not a genuine planar
## reflection" turned out to be TWO separate things, found in sequence:
##
## 1. (First pass, superseded) `look_at(eye, UP)` every frame always
##    re-aimed the camera to frame the player dead-centre regardless of
##    where they stood -- a tracking-shot, not a mirror. Replacing that
##    with a reflected-gaze orientation (player's forward/up reflected
##    across the plane) DID make the rendered content change with
##    player position, confirmed by render, but a render-verified
##    3-position sweep (see tests/ and the scratchpad parallax sweep)
##    showed the reflected character's own screen position/scale barely
##    moved between positions -- not the dramatic parallax a real
##    mirror shows.
## 2. The actual deeper cause: painting one SubViewport texture onto the
##    glass with a plain (symmetric-frustum) camera means the texture's
##    content depends only on where the virtual camera is pointed, not
##    on the REAL viewer's angle to the fixed glass rectangle. A true
##    mirror is a WINDOW into reflected space: the portion of that
##    space visible through a fixed window pane depends on the eye's
##    position relative to the window's fixed edges (stand far to one
##    side and you see less of what's near the opposite edge, more of
##    what's near your own side -- off-axis framing, not just "camera
##    looks a different way").
##
## THE FIX: a genuine off-axis ("asymmetric frustum" / portal-style)
## projection. The virtual eye E is the true in-plane (left/right,
## up/down) reflection of the player's own eye -- unchanged tracking
## math from Round 18 -- but is now placed slightly BEHIND the glass
## (toward the wall, _VIRTUAL_EYE_DEPTH_BEHIND_GLASS) rather than in
## front of it. This sounds like it reintroduces the "camera stuck
## inside solid CSG geometry" problem Round 18 deliberately avoided,
## but it does not: Godot's default backface culling makes a solid,
## single-sided CSGBox3D's surfaces INVISIBLE to a camera inside it (all
## its faces point away from an interior viewpoint), so the wall/cabinet
## box does not actually occlude anything from E's point of view -- see
## the class doc comment's honest limitation about what IS visible past
## that (nothing modelled, a void) instead.
##
## With E behind the glass looking back through it at the room, the
## camera's ORIENTATION is fixed to the GLASS's own plane basis (its
## local right/up, and the plane normal as forward) -- NOT the player's
## gaze at all. This is the key conceptual shift from pass 1: a portal's
## viewing axis is fixed to the portal itself; only the FRUSTUM's
## asymmetry (via frustum_offset) captures where the real viewer is
## standing relative to the window. The frustum is built to exactly
## frame the glass rectangle's four corners as seen from E -- see
## _asymmetric_frustum_for() -- which is what produces real,
## position-dependent, oblique-angle-correct parallax: moving E
## sideways changes WHICH part of the room is visible through the fixed
## window, exactly like a real window or mirror.
##
## HANDEDNESS/WINDING: because orientation is fixed to the glass's own
## (right, up, -normal) basis rather than built from reflected vectors,
## there is no improper-basis risk here at all -- this basis is always
## proper by construction. The existing uv1_scale.x=-1 glass-material
## correction (Round 18, verified with asymmetric marker cubes) is
## UNCHANGED and still needed: it corrects the left/right sense of the
## rendered texture itself, independent of how the source camera inside
## that texture is aimed.
func _update_reflection() -> void:
	var plane_xform: Transform3D = _mirror_plane.global_transform
	var plane_point: Vector3 = plane_xform.origin
	var plane_normal: Vector3 = -plane_xform.basis.z.normalized()
	var plane_right: Vector3 = plane_xform.basis.x.normalized()
	var plane_up: Vector3 = plane_xform.basis.y.normalized()

	var player_xform: Transform3D = _player_camera.global_transform
	var eye: Vector3 = player_xform.origin
	var to_eye: Vector3 = eye - plane_point
	var distance_in_front: float = to_eye.dot(plane_normal)
	if distance_in_front < 0.001:
		return

	# True in-plane (left/right, up/down) reflection of the player's eye
	# offset from the mirror's centre -- unchanged tracking math from
	# Round 18 -- but the virtual eye now sits slightly BEHIND the glass
	# (toward the wall) instead of in front of it, so it can look back
	# THROUGH the glass at the room, which off-axis framing requires.
	var in_plane: Vector3 = to_eye - distance_in_front * plane_normal
	var virtual_eye: Vector3 = plane_point + in_plane - _VIRTUAL_EYE_DEPTH_BEHIND_GLASS * plane_normal

	_mirror_camera.global_transform = Transform3D(Basis(plane_right, plane_up, -plane_normal), virtual_eye)
	_mirror_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_mirror_camera.far = _FAR_CLIP
	var frustum: Dictionary = _asymmetric_frustum_for(virtual_eye, plane_point, plane_right, plane_up, plane_normal)
	_mirror_camera.near = frustum.near
	_mirror_camera.size = frustum.size
	_mirror_camera.frustum_offset = frustum.offset


## Computes the asymmetric (off-axis) frustum that exactly frames the
## physical glass rectangle (centre `glass_center`, half-extents
## _glass_half_width/_glass_half_height along `glass_right`/`glass_up`)
## as seen from virtual eye `eye`, looking along `forward_axis` (the
## direction from the eye through the glass into the room). Standard
## portal/off-axis-projection derivation: project each of the glass
## rectangle's 4 corners (relative to the eye) onto the eye's own
## right/up/forward axes; all 4 share the same forward-axis distance
## (the rectangle is planar and perpendicular to forward_axis), which
## becomes the near-plane distance; the corners' right/up extents give
## the frustum's left/right/top/bottom bounds directly. Returns a
## Dictionary with near (float), size (float, vertical extent at the
## near plane -- matches Camera3D.size's own meaning), and offset
## (Vector2, matches Camera3D.frustum_offset's own meaning: how far the
## frustum's centre is shifted from the view axis, in the same
## near-plane-distance units as size).
func _asymmetric_frustum_for(eye: Vector3, glass_center: Vector3, glass_right: Vector3, glass_up: Vector3, forward_axis: Vector3) -> Dictionary:
	var xs: Array[float] = []
	var ys: Array[float] = []
	var near_dist: float = 0.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector3 = glass_center + sx * _glass_half_width * glass_right + sy * _glass_half_height * glass_up
			var rel: Vector3 = corner - eye
			xs.append(rel.dot(glass_right))
			ys.append(rel.dot(glass_up))
			near_dist = rel.dot(forward_axis)
	var left: float = xs.min()
	var right_bound: float = xs.max()
	var bottom: float = ys.min()
	var top: float = ys.max()
	near_dist = maxf(near_dist, 0.01)
	return {
		"near": near_dist,
		"size": top - bottom,
		"offset": Vector2((left + right_bound) * 0.5, (bottom + top) * 0.5),
	}
