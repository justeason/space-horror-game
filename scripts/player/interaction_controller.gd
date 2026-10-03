extends Camera3D
## Detects what the player is looking at and lets them click it.
##
## Camera3D sits deeper in the scene tree than Player
## (Player/LookPivot/PitchPivot/Camera3D), so Godot delivers
## `_unhandled_input` here BEFORE Player's movement_controller.gd sees it.
## When there is a valid hover target, we call `interact()` on it and
## consume the event via `set_input_as_handled()`, which stops it from
## ever reaching the movement controller. When there is no hover target,
## we leave the event alone, so movement_controller.gd's own
## `_unhandled_input` still receives the click and handles movement
## exactly as it did before this script existed.
##
## Anything the player can click just needs an `interact()` method —
## there's no shared base class. This is the same duck-typed contract
## the old movement-prompt system used.

@export var interact_distance: float = 3.0

## Path to the HUD reticle this controller subtly changes on hover.
@export var reticle_path: NodePath

@export var reticle_default_size: float = 3.0
@export var reticle_default_alpha: float = 0.45
@export var reticle_hover_size: float = 5.0
@export var reticle_hover_alpha: float = 0.8

var _reticle: ColorRect
var _hovered: Object = null


func _ready() -> void:
	if reticle_path != NodePath():
		_reticle = get_node(reticle_path) as ColorRect
	_set_reticle_state(false)


func _process(_delta: float) -> void:
	var hovered := _raycast_hovered()
	if hovered != _hovered:
		_hovered = hovered
		_set_reticle_state(_hovered != null)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hovered != null:
			_hovered.interact()
			get_viewport().set_input_as_handled()
		# No hover target: event is left unhandled on purpose, so
		# movement_controller.gd still receives it.


func _raycast_hovered() -> Object:
	var space_state := get_world_3d().direct_space_state
	var origin := global_position
	var target := origin - global_transform.basis.z * interact_distance

	var query := PhysicsRayQueryParameters3D.create(origin, target)
	var result := space_state.intersect_ray(query)

	if result and result.has("collider"):
		var collider = result["collider"]
		if collider.has_method("interact"):
			return collider
	return null


func _set_reticle_state(is_hovering: bool) -> void:
	if _reticle == null:
		return
	var size: float = reticle_hover_size if is_hovering else reticle_default_size
	var alpha: float = reticle_hover_alpha if is_hovering else reticle_default_alpha
	var half := size * 0.5
	_reticle.offset_left = -half
	_reticle.offset_top = -half
	_reticle.offset_right = half
	_reticle.offset_bottom = half
	var c := _reticle.color
	_reticle.color = Color(c.r, c.g, c.b, alpha)
