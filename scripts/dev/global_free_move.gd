extends Node3D
## Activates free WASD+collision movement for the whole station, once,
## at startup, and keeps it active permanently. Replaces the earlier
## zone-scoped prototype (the now-deleted scripts/dev/free_move_zone.gd),
## which only toggled between node movement and free movement inside two
## hand-authored test boxes — the whole station is free-move territory
## now, so there is nothing left to switch back to, and no AABB
## containment check runs every frame anymore.
##
## The node-based graph/tween system (movement_node.gd, the MovementNodes
## tree, movement_controller.gd) is left fully intact and loadable —
## only its input handling and prompts are turned off once, here — so it
## remains recoverable (flip Player.node_movement_enabled back to true
## and deactivate FreeMoveBody) if free movement is ever reverted.

@export var player_path: NodePath
@export var free_body_path: NodePath

## Set false by scripts/player/sleep_state.gd for the duration of the
## lie-down sequence. Without this, this script's own per-frame mirror
## below would fight the lie-down/get-up tween every physics tick,
## snapping the player back to the (stationary) free body's position
## instead of letting the tween move it.
var mirror_enabled: bool = true

@onready var _player: Node = get_node(player_path)
@onready var _free_body = get_node(free_body_path)


func _ready() -> void:
	_free_body.look_pivot = _player.get_node("LookPivot")
	_free_body.footsteps = _player.get_node("Footsteps")

	_player.force_stop_movement()
	_player.set_node_movement_enabled(false)

	_free_body.sync_to_eye_position(_player.global_position)
	_free_body.set_active(true)

	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if not mirror_enabled:
		return
	# The free body is the single source of truth for position now;
	# mirror it onto the Player each physics tick so the existing
	# LookPivot/Camera3D chain (mouse look, interaction raycasts,
	# everything downstream) keeps working completely unchanged.
	_player.global_position = _free_body.current_eye_position()
