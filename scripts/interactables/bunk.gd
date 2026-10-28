extends StaticBody3D
## The bunk's interact() target. Sitting down and getting up are
## deliberately separate actions (see sleep_state.gd): this only ever
## starts the sit-down sequence — re-clicking the bunk while already
## sitting down does nothing (sleep_state.gd no-ops), and getting up is
## a dedicated key press, not a second click here.
##
## interact() (the click path) and the dedicated E-key path (handled by
## sleep_state.gd, driven by is_player_near()) both require the player
## to actually be near the bed first — interaction_controller.gd's
## raycast alone used to let a click from clear across the room start
## the lying-down transition, since its 3m interact_distance was never
## meant to be a proximity gate for every interactable. This checks
## distance against the bed specifically (not a station-wide change)
## so other interactables keep their existing raycast-only behavior.

@export var sleep_state_path: NodePath
@export var player_path: NodePath
## Distance (m) from this node's own origin within which the player
## may interact with the bed. The bed's own collision box is roughly
## 0.9m x 1.7m (see bunk.tscn) centered here, so this comfortably
## covers "standing right next to it" without reaching across the room.
@export var interact_range: float = 1.3

var _sleep_state: Node
var _player: Node3D
var _was_near: bool = false


func _ready() -> void:
	_sleep_state = get_node(sleep_state_path)
	_player = get_node(player_path)


func _process(_delta: float) -> void:
	var near: bool = is_player_near()
	if near != _was_near:
		_was_near = near
		_sleep_state.set_bed_proximity(near)


## Horizontal-only distance: this node's own origin sits at mattress
## height (y=0.4), while the player's eye is always ~1.6m up -- a
## straight 3D distance would bake in that ~1.2m vertical gap and
## starve the actual "standing next to the bed" radius almost
## entirely. Proximity to a piece of furniture is a floor-plan
## question, not a height one.
func is_player_near() -> bool:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	return to_player.length() <= interact_range


## The click/raycast path. No-op from a distance -- see class doc
## comment above.
func interact() -> void:
	if not is_player_near():
		return
	_sleep_state.begin_sitting()
