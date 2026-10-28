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

## Path to the shared bottom-center HUD prompt label (also used by
## scripts/player/sleep_state.gd for its own exclusive states --
## SITTING/LAPTOP/EDITING/SLEEPING). This controller owns the label
## only while `interactions_enabled` is true, i.e. only during ordinary
## free-roam: the moment another system takes exclusive control it sets
## `interactions_enabled = false` (already an established convention --
## see sleep_state.gd's begin_sitting() and workstation_state.gd's
## begin_use()), which immediately clears this controller's own prompt
## text via the setter below so the two owners never fight over the
## same label.
@export var prompt_label_path: NodePath

## Optional: lets the free-roam prompt fall back to the bed's own
## proximity-driven "E: Sit Down" prompt when nothing is being hovered.
## The bed is a proximity interaction, not a raycast one (see
## scripts/interactables/bunk.gd's class doc comment), so it can't be
## answered by get_interact_prompt() on a hovered object the way every
## other interactable in this system is.
@export var sleep_state_path: NodePath

## Optional: appends a "Space: Drop <item>" hint whenever the player is
## carrying something, alongside (not instead of) whatever else the
## prompt is already showing -- matches the multi-action convention
## scripts/player/sleep_state.gd already uses for its own prompts (e.g.
## "E: Get Up    F: Laptop    G: Sleep"). Space is also the pickup key
## (see carry_system.gd's _unhandled_input()) when nothing is carried;
## this hint only ever shows the drop half since it's only appended
## while something IS carried.
@export var carry_system_path: NodePath

@export var reticle_default_size: float = 3.0
@export var reticle_default_alpha: float = 0.45
@export var reticle_hover_size: float = 5.0
@export var reticle_hover_alpha: float = 0.8

var _reticle: ColorRect
var _prompt_label: Label
var _sleep_state: Node
var _carry_system: Node
var _hovered: Object = null


## Public read of whatever is currently hovered (or null) -- lets
## scripts/player/carry_system.gd's Space pickup reuse the SAME
## targeted-by-the-player object this controller's own click/prompt
## system already resolves every frame, instead of re-deriving its own
## separate raycast. Defined up here, next to the var it reads, rather
## than at the bottom with the other public methods, so the
## relationship is obvious at a glance.
func get_hovered() -> Object:
	return _hovered

## Set false while an exclusive first-person sequence owns the camera
## (see scripts/player/sleep_state.gd) so hovering/clicking other
## objects is suppressed — e.g. you shouldn't be able to interact with
## anything else while lying down. Hover detection itself is skipped
## too, so the reticle doesn't highlight as if something were usable.
## A custom setter so the moment any system takes exclusive control,
## this controller's own contextual prompt text is cleared immediately
## (not just on the next _process, which would otherwise leave a stale
## "Click: ..." line showing underneath e.g. the seated workstation).
var interactions_enabled: bool = true:
	set(value):
		interactions_enabled = value
		if not value:
			_hovered = null
			_set_reticle_state(false)
			_set_prompt_text("")


func _ready() -> void:
	# Round 15: must win "which Camera3D is active for the main window"
	# explicitly, not by relying on Godot's fragile auto-promotion
	# ("first/only camera becomes current") order -- confirmed directly
	# that adding the valve routing station's own world-embedded
	# diorama camera (a plain Node3D sibling in the main 3D world, same
	# pattern electrical_repair_diorama.gd's WorldDiorama already used
	# without incident) could silently steal the active camera and
	# point the whole game at a tiny wall-mounted prop instead of the
	# player. This one explicit claim makes the player's own camera
	# robust against ANY current/future world-embedded diorama camera,
	# regardless of scene-tree ordering.
	current = true
	if reticle_path != NodePath():
		_reticle = get_node(reticle_path) as ColorRect
	if prompt_label_path != NodePath():
		_prompt_label = get_node(prompt_label_path) as Label
	if sleep_state_path != NodePath():
		_sleep_state = get_node(sleep_state_path)
	if carry_system_path != NodePath():
		_carry_system = get_node(carry_system_path)
	_set_reticle_state(false)


func _process(_delta: float) -> void:
	if not interactions_enabled:
		if _hovered != null:
			_hovered = null
			_set_reticle_state(false)
		return
	var hovered := _raycast_hovered()
	if hovered != _hovered:
		_hovered = hovered
		_set_reticle_state(_hovered != null)
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not interactions_enabled:
		return
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


## Recomputed from scratch every frame (not edge-triggered) so it is
## always correct regardless of which source changed: what's hovered,
## carried-item state, task state, or bed proximity. Priority: whatever
## is actually being looked at wins over ambient bed proximity.
func _update_prompt() -> void:
	if _prompt_label == null:
		return
	var text := ""
	if _hovered != null and _hovered.has_method("get_interact_prompt"):
		text = _hovered.get_interact_prompt()
	if text == "" and _sleep_state != null and _sleep_state.is_near_bed():
		text = "E: Sit Down"
	if _carry_system != null and _carry_system.is_carrying():
		var drop_hint := "Space: Drop %s" % _carry_system.carried_item_display_name()
		text = "%s    %s" % [text, drop_hint] if text != "" else drop_hint
	_set_prompt_text(text)


func _set_prompt_text(text: String) -> void:
	if _prompt_label == null:
		return
	_prompt_label.text = text
	_prompt_label.visible = text != ""


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
