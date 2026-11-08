extends StaticBody3D
## The Control Room's physical workstation monitor. Unlike the laptop,
## this console never moves between a resting pose and a held pose --
## it's a fixed piece of furniture -- so there is no "view mover"
## script analogous to laptop_view.gd. This one small interactable,
## plus workstation_state.gd (the camera zoom/lock + key-routing
## coordinator, mirroring sleep_state.gd's role for the bed/laptop)
## and workstation_screen.gd (the UI content), are the whole system.

@export var workstation_state_path: NodePath
@export var player_path: NodePath
## Distance (m) from this node's own origin within which the player may
## begin using the workstation. Same horizontal-only-distance convention
## as scripts/interactables/bunk.gd's interact_range -- the raycast's
## own interact_distance (3m) was never meant to be a proximity gate by
## itself (see bunk.gd's class doc comment), so this checks distance
## against the console specifically.
##
## Grounded in the actual desk geometry, not picked arbitrarily: the
## desk surface (ConsoleDesk, scenes/main.tscn) has its near edge at
## z=-0.6, and this console sits at z=-0.92, so a player standing right
## at the desk's own edge is already ~0.35m away; the default spawn
## point used station-wide (ControlRoomRearLeft) sits 0.82m away. 1.0m
## comfortably covers "standing at the desk" through "just walked up to
## it" while excluding triggering from clear across the room (player
## feedback: wanted this tighter than the previous 2.0m).
@export var interact_range: float = 1.0

@onready var _workstation_state: Node = get_node(workstation_state_path)
@onready var _player: Node3D = get_node(player_path)
@onready var _screen: MeshInstance3D = $Screen
@onready var _screen_viewport: SubViewport = $WorkstationScreen

var _screen_material: StandardMaterial3D


func _ready() -> void:
	# Unshaded, driven only by albedo -- the laptop's screen material
	# was found to render as solid overexposed white when it was BOTH
	# normally lit AND adding full-strength emission on top of that
	# (confirmed by feeding it a flat gray test texture and getting pure
	# white back); built unshaded from the start here to avoid
	# reintroducing that bug in a second screen.
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_material.albedo_texture = _screen_viewport.get_texture()
	# BoxMesh's auto-generated UV for this face does NOT span the full
	# 0..1 range across the face the way a naive "box size" assumption
	# would suggest -- confirmed empirically with a calibration texture
	# (vertical color gradient + decile tick marks) rendered onto the
	# live mesh and measured pixel-by-pixel: with no correction, only
	# about the left 33% of the texture was ever visible, silently
	# cropping everything past that point (this was the Control Room
	# Workstation Revamp's "text too large / clipped" bug -- the UI
	# layout itself was always correct; the physical screen mesh was
	# only ever displaying a third of it). This rescales the mesh's
	# native UV back out to the full 0..1 range. There is no documented
	# formula for this -- it was measured, not derived, the same way
	# the laptop screen's own UV rotation was found last round.
	_screen_material.uv1_scale = Vector3(3.03, 2.04, 1.0)
	_screen.material_override = _screen_material


func interact() -> void:
	if not is_player_near():
		return
	_workstation_state.begin_use()


## Horizontal-only distance -- see interact_range's doc comment.
func is_player_near() -> bool:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	return to_player.length() <= interact_range


func get_interact_prompt() -> String:
	if _workstation_state.is_in_use():
		return ""
	if not is_player_near():
		return ""
	return "Click: Use Workstation"


func get_screen_global_position() -> Vector3:
	return _screen.global_position


## Outward normal read from the screen mesh's LIVE transform (its thin
## axis is local Z -- this screen is authored as an ordinary wall-facing
## "picture frame" quad, width=X/height=Y/depth=Z, unlike the laptop's
## lid-hinge-authored screen, which is why that one used its local Y
## instead), not guessed -- same general technique proven last round
## for the laptop screen (scripts/player/laptop_view.gd's
## get_screen_outward_normal()).
func get_screen_outward_normal(reference_point: Vector3) -> Vector3:
	var normal: Vector3 = _screen.global_transform.basis.z.normalized()
	var to_reference: Vector3 = (reference_point - _screen.global_position).normalized()
	if normal.dot(to_reference) < 0.0:
		normal = -normal
	return normal


## Round 37: normalized screen coordinates (0,0 top-left .. 1,1) where a
## ray meets the monitor's front face, or (-1,-1). Derived from geometry:
## the Screen mesh is a 0.576 x 0.36 box facing local +Z.
func screen_uv_on_ray(from: Vector3, dir: Vector3) -> Vector2:
	var inv: Transform3D = _screen.global_transform.affine_inverse()
	var lf: Vector3 = inv * from
	var ld: Vector3 = inv.basis * dir
	var size: Vector3 = (_screen.mesh as BoxMesh).size
	var face_z: float = size.z * 0.5
	if absf(ld.z) < 1e-6:
		return Vector2(-1, -1)
	var t: float = (face_z - lf.z) / ld.z
	if t <= 0.0:
		return Vector2(-1, -1)
	var p: Vector3 = lf + ld * t
	var u: float = p.x / size.x + 0.5
	var v: float = 0.5 - p.y / size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2(-1, -1)
	return Vector2(u, v)


## Inverse (tests / tools): screen uv -> world point on the face.
func screen_point(uv: Vector2) -> Vector3:
	var size: Vector3 = (_screen.mesh as BoxMesh).size
	return _screen.global_transform * Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, size.z * 0.5)
