extends Node3D
## Moves the player between MovementNodes with a smooth physical tween —
## never a teleport. Shows a subtle floor marker toward every reachable
## neighbor of the node the player currently occupies, purely as a visual
## hint; they are not click targets.
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

@export var starting_node: NodePath

@onready var look_pivot: Node3D = $LookPivot
@onready var footsteps: AudioStreamPlayer3D = $Footsteps
@onready var step_timer: Timer = $StepTimer

var current_node: Node3D = null
var _is_moving: bool = false
var _bob_time: float = 0.0
var _active_prompts: Array[Node3D] = []


func _ready() -> void:
	step_timer.wait_time = step_interval
	step_timer.timeout.connect(_on_step_timer_timeout)

	current_node = get_node(starting_node)
	global_position = current_node.global_position
	global_rotation = current_node.global_rotation
	_refresh_prompts.call_deferred()


func _process(delta: float) -> void:
	if _is_moving:
		_bob_time += delta * bob_frequency
		look_pivot.position.y = sin(_bob_time) * bob_amplitude
	elif look_pivot.position.y != 0.0:
		look_pivot.position.y = lerpf(look_pivot.position.y, 0.0, delta * 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_move_toward_look_direction()


## Picks whichever neighbor of `current_node` is most closely aligned
## (horizontally) with where the camera is currently looking, and moves
## there if it's within `move_select_angle_degrees`. Pitch (looking up/down)
## is ignored entirely — only the look yaw matters.
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

	for neighbor in current_node.get_neighbor_nodes():
		var to_neighbor: Vector3 = neighbor.global_position - current_node.global_position
		to_neighbor.y = 0.0
		if to_neighbor.length_squared() < 0.0001:
			continue
		var angle := look_dir.angle_to(to_neighbor.normalized())
		if angle < best_angle:
			best_angle = angle
			best_neighbor = neighbor

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
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target_node.global_position, duration)
	tween.tween_property(self, "global_rotation:y", target_node.global_rotation.y, duration)
	tween.chain().tween_callback(_on_arrived.bind(target_node))


func _on_arrived(target_node: Node3D) -> void:
	_is_moving = false
	step_timer.stop()
	current_node = target_node
	_refresh_prompts()


func _on_step_timer_timeout() -> void:
	footsteps.play_step()


func _refresh_prompts() -> void:
	_clear_prompts()
	for neighbor in current_node.get_neighbor_nodes():
		var prompt := MovementPromptScene.instantiate()
		get_tree().current_scene.add_child(prompt)
		var midpoint := current_node.global_position.lerp(neighbor.global_position, 0.6)
		midpoint.y = floor_marker_height
		prompt.global_position = midpoint
		_active_prompts.append(prompt)


func _clear_prompts() -> void:
	for prompt in _active_prompts:
		if is_instance_valid(prompt):
			prompt.queue_free()
	_active_prompts.clear()
