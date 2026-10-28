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
## HONEST LIMITATIONS (see the Round 18 final report -- Round 17's
## "left-right not verified"/"does not zoom" notes here were resolved
## or found to be mistaken this round; see below and the _ready() UV
## comments):
## - The TRUE optical mirror-reflection point for a wall-mounted mirror
##   this close to the player (the room is under a metre deep here)
##   lands outside the station's own hull -- there is a solid wall, and
##   then nothing modelled at all, a few centimetres behind the glass.
##   Worse, the glass pane and its cabinet housing (main.tscn) are both
##   SOLID CSG boxes with no hollow cavity at all, so there is no depth
##   behind the glass a camera could occupy without sitting inside solid
##   geometry. _update_reflection() keeps the true reflection's LEFT/
##   RIGHT and UP/DOWN placement (so the view correctly tracks the
##   player moving side to side or up and down), but instead of pushing
##   the camera behind the glass, it holds it a small fixed distance IN
##   FRONT of the glass (_CAMERA_OFFSET_FROM_GLASS, toward the room, on
##   the player's own side) -- a standard practical approximation for a
##   tight-interior wall mirror. CONFIRMED BY RENDER (Round 18): this
##   still produces a real, physically-sensible zoom -- the camera-to-
##   subject distance is (player's real distance to the glass) minus
##   this fixed offset, so the reflection genuinely grows as the player
##   approaches and shrinks as they back away; Round 17's claim that it
##   "does not noticeably zoom" was never actually render-verified and
##   turned out to be wrong.
## - LEFT/RIGHT and UP/DOWN orientation: CONFIRMED CORRECT by render
##   (Round 18), using asymmetric marker cubes specifically because a
##   roughly-symmetric reflected body can hide an orientation bug --
##   see _ready()'s own comment for exactly what was found and fixed.
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

## How far IN FRONT of the glass (toward the room, the player's own
## side) the mirror camera actually sits, regardless of the player's
## true distance -- see the class doc comment's honest limitation.
## Positive = toward the room. Comfortably clears both the glass pane
## and its cabinet housing (main.tscn), which are solid right up
## against each other with no hollow gap a camera could otherwise sit
## in.
const _CAMERA_OFFSET_FROM_GLASS: float = 0.25

var _player_camera: Camera3D = null
var _mirror_plane: Node3D = null


func _ready() -> void:
	# Same reasoning as SurveillanceCamera: not in a SubViewportContainer,
	# so nothing else would mark this viewport "visible" each frame.
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_player_camera = get_node_or_null(player_camera_path)
	_mirror_plane = get_node_or_null(mirror_plane_path)

	var glass: GeometryInstance3D = get_node_or_null(glass_mesh_path)
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


## Reflects the real camera's eye position across the mirror's own
## plane (local -Z = the glass's outward-facing/reflective side,
## matching how WashMirrorGlass is oriented in main.tscn -- it faces
## south/-z into the room) for the LEFT/RIGHT and UP/DOWN placement
## only, holds a fixed offset in front of the glass for depth (see the
## class doc comment's honest limitation on why), then aims the mirror
## camera back at the player's eye. An ordinary look-at rotation --
## never an improper/reflected basis -- so there is no front-face
## winding-order concern to work around; the resulting capture's own
## left/right is corrected afterward as a 2D texture flip instead (see
## _ready()'s own comment on the glass material).
func _update_reflection() -> void:
	var plane_xform: Transform3D = _mirror_plane.global_transform
	var plane_point: Vector3 = plane_xform.origin
	var plane_normal: Vector3 = -plane_xform.basis.z.normalized()

	var eye: Vector3 = _player_camera.global_transform.origin
	var to_eye: Vector3 = eye - plane_point
	var distance_in_front: float = to_eye.dot(plane_normal)
	# In-plane (left/right, up/down) component only -- this is the part
	# of the true reflection that stays geometrically meaningful at
	# this room's scale; see the class doc comment for why the DEPTH
	# component is clamped instead of used as-is.
	var in_plane: Vector3 = to_eye - distance_in_front * plane_normal
	var camera_pos: Vector3 = plane_point + in_plane + _CAMERA_OFFSET_FROM_GLASS * plane_normal

	if distance_in_front < 0.001:
		return
	_mirror_camera.global_transform = Transform3D(Basis(), camera_pos)
	_mirror_camera.look_at(eye, Vector3.UP)
