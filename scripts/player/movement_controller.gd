extends Node3D
## Moves the player between MovementNodes with a smooth physical tween —
## never a teleport. Shows a subtle floor marker toward every movement
## candidate of the node the player currently occupies (see
## MovementNode.get_movement_candidates()), purely as a visual hint;
## they are not click targets.
##
## Movement is triggered by looking toward a destination and left-clicking
## anywhere on screen: see `_try_move_toward_look_direction()`.

const MovementPromptScene := preload("res://scenes/movement_prompt.tscn")

## Speed of travel between nodes, in seconds per meter of distance.
@export var seconds_per_meter: float = 0.9
@export var step_interval: float = 0.38
@export var bob_amplitude: float = 0.035
@export var bob_frequency: float = 9.0

## Height above the floor the movement markers sit at — low and
## floor-mounted so they read as a physical marking, not a floating UI icon.
@export var floor_marker_height: float = 0.03

## How far off-center (in degrees) the player's look direction may be from
## a neighbor's direction and still select it. Neighbors in this corridor
## are ~180 degrees apart, so this threshold both forgives imprecise aim
## and leaves a dead zone (looking roughly sideways) where nothing is
## selected.
@export var move_select_angle_degrees: float = 65.0

## The player has no physical collision shape today — position is tweened
## directly from node to node (see `move_to()`), so nothing here actually
## reads these two values at runtime. They exist so corridor/room authoring
## and navigation validation (see scripts/navigation tests and
## scripts/dev/nav_debug_overlay.gd) have one concrete, shared definition of
## "how much body the player needs clearance for" instead of every piece of
## tooling guessing its own number. Treat a corridor that can't fit a
## capsule of this radius/height as a real authoring bug, not a style
## choice. Changing these does not change movement behavior by itself.
@export var player_clearance_radius: float = 0.3
@export var player_clearance_height: float = 1.0

@export var starting_node: NodePath

@onready var look_pivot: Node3D = $LookPivot
@onready var footsteps: AudioStreamPlayer3D = $Footsteps
@onready var step_timer: Timer = $StepTimer

## Station-wide switch set once, permanently false, by
## scripts/dev/global_free_move.gd at startup now that free movement is
## the station's only active movement system. Defaults true so this
## script is still fully self-sufficient (and the node graph/tween code
## below remains real, runnable, testable logic — see
## test_locked_graph.gd) if global_free_move.gd is ever removed and node
## movement needs to be recovered. When false, clicks are ignored and
## movement prompts stay hidden, but `current_node` and all node-graph
## state are left untouched.
var node_movement_enabled: bool = true

var current_node: Node3D = null
var _is_moving: bool = false
var _bob_time: float = 0.0
var _active_prompts: Array[Node3D] = []
var _active_tween: Tween = null


func _ready() -> void:
	step_timer.wait_time = step_interval
	step_timer.timeout.connect(_on_step_timer_timeout)

	current_node = get_node(starting_node)
	global_position = current_node.global_position
	global_rotation = current_node.global_rotation
	_refresh_prompts.call_deferred()


## Gated on node_movement_enabled (see that export's own doc comment:
## GlobalFreeMove permanently disables node-based movement station-wide
## at startup) -- this head-bob is part of the node-walk feature and
## was previously running UNCONDITIONALLY even with node movement
## disabled, since _is_moving can never become true that way. Its
## "settle back to 0" branch then ran forever, every frame, for the
## entire game, fighting ANY other system that legitimately writes to
## look_pivot.position -- confirmed to be the actual cause of a
## reported "editor zoom camera drifts back out" bug: sleep_state.gd's
## _start_editor_zoom() tweens look_pivot.position to a nonzero offset,
## and this unrelated, permanently-dead bob-reset logic silently eroded
## just its Y component back toward 0 every subsequent frame once the
## tween finished. Gating the whole method on node_movement_enabled
## (matching every other node-movement entry point in this script)
## leaves look_pivot.position fully available to other systems when
## node movement is disabled, and preserves the original bob/settle
## behavior intact for the (currently unused, but still real/testable)
## case where it is re-enabled.
func _process(delta: float) -> void:
	if not node_movement_enabled:
		return
	if _is_moving:
		_bob_time += delta * bob_frequency
		look_pivot.position.y = sin(_bob_time) * bob_amplitude
	elif look_pivot.position.y != 0.0:
		look_pivot.position.y = lerpf(look_pivot.position.y, 0.0, delta * 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if not node_movement_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_move_toward_look_direction()


## Picks whichever movement candidate of `current_node` is most closely
## aligned (horizontally) with where the camera is currently looking, and
## moves there if it's within `move_select_angle_degrees`. Pitch (looking
## up/down) is ignored entirely — only the look yaw matters.
func _try_move_toward_look_direction() -> void:
	if _is_moving:
		return

	var look_dir: Vector3 = -look_pivot.global_transform.basis.z
	look_dir.y = 0.0
	if look_dir.length_squared() < 0.0001:
		return
	look_dir = look_dir.normalized()

	var best_neighbor: Node3D = null
	var best_angle := INF

	for candidate in current_node.get_movement_candidates():
		var to_candidate: Vector3 = candidate.global_position - current_node.global_position
		to_candidate.y = 0.0
		if to_candidate.length_squared() < 0.0001:
			continue
		var angle := look_dir.angle_to(to_candidate.normalized())
		if angle < best_angle:
			best_angle = angle
			best_neighbor = candidate

	if best_neighbor != null and best_angle <= deg_to_rad(move_select_angle_degrees):
		move_to(best_neighbor)


## Ignored if already mid-transition.
func move_to(target_node: Node3D) -> void:
	if _is_moving or target_node == null or target_node == current_node:
		return

	_is_moving = true
	_clear_prompts()

	var distance := global_position.distance_to(target_node.global_position)
	var duration: float = max(distance * seconds_per_meter, 0.25)

	step_timer.start()
	_on_step_timer_timeout() # immediate step on departure

	var tween := create_tween()
	_active_tween = tween
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target_node.global_position, duration)
	tween.tween_property(self, "global_rotation:y", target_node.global_rotation.y, duration)
	tween.chain().tween_callback(_on_arrived.bind(target_node))


## Prototype hook for the free-movement experiment: immediately halts any
## in-flight node-to-node tween (killing it leaves global_position
## exactly where it already was — it does not snap back or jump forward)
## so free movement can take over from that exact spot without the tween
## continuing to fight it for control of the player's position.
func force_stop_movement() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	_is_moving = false
	step_timer.stop()
	_clear_prompts()


## Prototype hook for the free-movement experiment: enables/disables the
## click-to-move system without touching `current_node` or any graph
## state, so disabling and re-enabling is always safe to call.
func set_node_movement_enabled(value: bool) -> void:
	node_movement_enabled = value
	if value:
		_refresh_prompts()
	else:
		_clear_prompts()


func _on_arrived(target_node: Node3D) -> void:
	_is_moving = false
	step_timer.stop()
	current_node = target_node
	_refresh_prompts()


func _on_step_timer_timeout() -> void:
	footsteps.play_step()


func _refresh_prompts() -> void:
	if not node_movement_enabled:
		return
	_clear_prompts()
	for candidate in current_node.get_movement_candidates():
		var prompt := MovementPromptScene.instantiate()
		get_tree().current_scene.add_child(prompt)
		var midpoint := current_node.global_position.lerp(candidate.global_position, 0.6)
		midpoint.y = floor_marker_height
		prompt.global_position = midpoint
		_active_prompts.append(prompt)


func _clear_prompts() -> void:
	for prompt in _active_prompts:
		if is_instance_valid(prompt):
			prompt.queue_free()
	_active_prompts.clear()
