extends Node
## Shared "take exclusive control for a maintenance minigame" boundary --
## a small reusable state coordinator, NOT a generic minigame framework.
## Generalizes the exact exclusive-state pattern scripts/station/
## workstation_state.gd and scripts/player/sleep_state.gd already use
## (disable free movement/mirroring/raycast interaction/look input,
## remember what to restore, restore it all on exit) so any future
## maintenance interaction can reuse it instead of re-deriving its own
## copy of the same five lines.
##
## Usage: a physical interactable (e.g. electrical_panel.gd) that wants
## to open a focused UI calls `FocusedInteractionState.begin(view)`,
## where `view` is any node exposing an `on_focus_exit()` method (duck-
## typed, same convention as interact()/get_interact_prompt() elsewhere
## in this project -- optional, called if present so the view can reset
## its own internal sub-state on a forced exit). This script does not
## know anything about what the view displays or does; it only owns the
## player-state boundary and input routing.
##
## Mouse mode is explicitly preserved/restored (not hardcoded back to
## CAPTURED) because a future caller might open a focused view while the
## mouse was already visible for some other reason -- restoring exactly
## what was there before is the only way to never leave the cursor in
## the wrong state.

@export var free_body_path: NodePath
@export var global_free_move_path: NodePath
@export var interaction_controller_path: NodePath
@export var look_controller_path: NodePath

@onready var _free_body: Node = get_node(free_body_path)
@onready var _global_free_move: Node = get_node(global_free_move_path)
@onready var _interaction_controller: Node = get_node(interaction_controller_path)
@onready var _look_controller: Node = get_node(look_controller_path)

var _active_view: Node = null
var _prior_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func is_active() -> bool:
	return _active_view != null


## The view currently holding focus, or null. Lets a caller defensively
## check "is it still me?" before acting (see electrical_panel.gd's own
## defensive checks elsewhere in this project).
func active_view() -> Node:
	return _active_view


## Begins a focused session for `view`. No-op (returns false) if a
## session is already active -- callers should check is_active() first,
## but this is the actual safety net against two interactables somehow
## opening two sessions back-to-back in one frame.
func begin(view: Node) -> bool:
	if _active_view != null:
		return false
	_active_view = view
	_prior_mouse_mode = Input.mouse_mode

	_free_body.set_active(false)
	_global_free_move.mirror_enabled = false
	_interaction_controller.interactions_enabled = false
	_look_controller.escape_enabled = false
	_look_controller.input_enabled = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


## Ends the current session (if any) and restores every piece of state
## begin() touched, in every case -- called whether the view finished
## normally, the player pressed Escape, or something external forced an
## exit (e.g. the active object being removed). Safe to call when
## already inactive (no-op), so callers never need to guard it
## themselves.
func end() -> void:
	if _active_view == null:
		return
	var view := _active_view
	_active_view = null

	_free_body.set_active(true)
	_global_free_move.mirror_enabled = true
	_interaction_controller.interactions_enabled = true
	_look_controller.escape_enabled = true
	_look_controller.input_enabled = true
	Input.mouse_mode = _prior_mouse_mode

	if is_instance_valid(view) and view.has_method("on_focus_exit"):
		view.on_focus_exit()


## Escape is the one key this coordinator itself reserves globally while
## active, mirroring workstation_state.gd/sleep_state.gd's own existing
## Escape convention (dedicated, consistent exit key) rather than
## leaving every view to reimplement its own Escape handling. Runs
## BEFORE the view's own _unhandled_input gets a chance (Godot visits
## more-recently-added siblings first; this node is added after Player
## in main.tscn, same ordering convention workstation_state.gd/
## sleep_state.gd already rely on), and consumes the event so nothing
## else (movement, the view itself) also reacts to the same Escape.
func _unhandled_input(event: InputEvent) -> void:
	if _active_view == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var view := _active_view
		if is_instance_valid(view) and view.has_method("cancel_requested"):
			view.cancel_requested()
		end()
		get_viewport().set_input_as_handled()
