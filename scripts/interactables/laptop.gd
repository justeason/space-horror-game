extends Node3D
## Reusable rugged maintenance-tech laptop prop. Closed by default;
## set_open() smoothly animates the lid about its hinge and wakes/
## sleeps the screen. Has no interact() -- this prop is never clicked
## directly; it is picked up and opened by scripts/player/laptop_view.gd
## via a dedicated key while lying down (see scripts/player/
## sleep_state.gd), since aiming a raycast at a laptop resting near
## your own face while lying down is awkward.
##
## There is exactly ONE laptop instance in the game (the one resting on
## the bed) -- laptop_view.gd reparents this same node between the
## world (resting) and the player's lap anchor (in use) rather than
## creating a second copy, per M7's "one coherent laptop" requirement.
##
## The screen shows whatever texture set_screen_texture() was given
## (typically scripts/ui/session_log_screen.gd's live SubViewport feed,
## wired once by laptop_view.gd) -- the same "SubViewport as a physical
## screen's texture" pattern already used by
## scripts/surveillance/surveillance_camera.gd, reused here for a UI
## tree instead of a 3D camera. With no texture set, the screen is just
## a plain dark/lit panel (so this prop still works standalone, e.g. in
## an editor preview, without requiring a texture).

## -130 (rather than a more typical real-laptop ~100-110) is tuned
## together with laptop_view.gd's held_local_rotation_degrees base tilt
## so the screen actually faces the seated player's eye -- see that
## script's comment for the empirical search that produced both
## numbers together.
@export var open_angle_degrees: float = -130.0
@export var hinge_animation_duration: float = 0.3
@export var is_open: bool = false

@onready var _hinge: Node3D = $HingePivot
@onready var _screen: CSGBox3D = $HingePivot/LidBack/ScreenGlow

var _screen_material: StandardMaterial3D
var _screen_texture: Texture2D = null
var _hinge_tween: Tween


func _ready() -> void:
	_screen_material = StandardMaterial3D.new()
	# UNSHADED, not lit + emissive: with normal per-pixel shading, the
	# screen's own full-strength emission (meant to make it read as a
	# glowing, self-lit display regardless of room darkness) STACKED
	# ADDITIVELY on top of ordinary scene lighting (ambient + the nearby
	# bedside lamp, Light_LivingBed) -- confirmed by feeding the screen
	# a flat mid-gray test texture and finding it rendered as solid
	# clipped white (255,255,255) regardless of the texture's actual
	# content, even for a value as low as 0.5. This silently made BOTH
	# the ordinary laptop screen (title/sample text) and the EDITING
	# screen (the ESC hint, the entry field, typed text) completely
	# unreadable -- the root cause behind "no visible Esc hint" and
	# "typing appears to have no effect": the content was always being
	# rendered correctly (see the SubViewport texture itself, which is
	# fine), it just never survived being displayed on the 3D screen
	# mesh. Unshaded makes albedo_texture the literal, final on-screen
	# color -- no scene lighting applied, no risk of any channel ever
	# exceeding 1.0 since the UI's own authored colors are already in
	# 0..1 range -- which is also the physically sensible behavior for
	# an actual LCD (its displayed color isn't supposed to be tinted or
	# brightened by a nearby lamp).
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# CSGBox3D's auto-generated UV for this face does not run
	# U-horizontal/V-vertical the way a naive "box size (0.24 wide,
	# 0.14 tall)" would suggest -- confirmed by rendering the live feed
	# and finding the SESSION LOG text rotated 90 degrees and mirrored.
	# scenes/interactables/laptop.tscn's ScreenGlow is now authored
	# rotated -90 degrees about its own normal (with size.x/size.z
	# swapped to keep the same on-screen rectangle) to fix the rotation;
	# this uv1_scale/offset flip corrects the remaining vertical mirror
	# that rotation alone left behind (title ended up at the bottom).
	# Found empirically (there is no documented CSGBox3D UV convention
	# to derive this from) by rendering actual screenshots of each
	# candidate and comparing -- see the M9 investigation notes.
	_screen_material.uv1_scale = Vector3(1, -1, 1)
	_screen_material.uv1_offset = Vector3(0, 1, 0)
	_screen.material = _screen_material
	_hinge.rotation.x = deg_to_rad(open_angle_degrees) if is_open else 0.0
	_apply_screen_state()


## Wires a live texture (e.g. scripts/ui/session_log_screen.gd's
## SubViewport feed) onto the screen. Safe to call once at startup and
## never again -- the texture itself stays live on its own.
func set_screen_texture(tex: Texture2D) -> void:
	_screen_texture = tex
	_apply_screen_state()


func set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	if _hinge_tween != null and _hinge_tween.is_valid():
		_hinge_tween.kill()
	_hinge_tween = create_tween()
	var target_angle: float = deg_to_rad(open_angle_degrees) if value else 0.0
	_hinge_tween.tween_property(_hinge, "rotation:x", target_angle, hinge_animation_duration)
	_apply_screen_state()


## Unshaded (see _ready()): albedo_texture/albedo_color ARE the final
## on-screen color directly, with no scene lighting involved -- emission
## is deliberately left disabled/untouched here, not just zeroed, so
## there is only ONE code path controlling the screen's brightness.
func _apply_screen_state() -> void:
	if is_open and _screen_texture != null:
		_screen_material.albedo_texture = _screen_texture
		_screen_material.albedo_color = Color(1, 1, 1, 1)
	else:
		_screen_material.albedo_texture = null
		_screen_material.albedo_color = Color(0.15, 0.55, 0.5) if is_open else Color(0.03, 0.03, 0.04)
