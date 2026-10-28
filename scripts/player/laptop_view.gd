extends Node
## Owns the laptop's "picked up and in use" presentation: reparenting
## the ONE physical laptop (scripts/interactables/laptop.gd) between
## its resting spot near the bed and the player's lap anchor (see
## scripts/player/player_body.gd's LapAnchor), and the laptop's screen
## content (scripts/ui/session_log_screen.gd -- a SubViewport that IS
## the session log, both viewing and editing; see that script for the
## M7.2 "render the log on the actual laptop screen" redesign).
## Knows nothing about AWAKE/SITTING/EDITING as such -- scripts/player/
## sleep_state.gd owns that state machine and only ever calls
## open()/close()/begin_editing()/end_editing()/save_entry()/
## forward_key_to_screen()/return_to_rest() at the right times, and
## owns the actual key handling and look/movement suppression itself.
##
## The laptop is reparented, never duplicated (M7: "one coherent
## laptop interaction, not two visually unrelated laptop
## representations"): open() moves the SAME node onto the lap anchor;
## close() just folds the lid shut and leaves it there -- the simplest
## reliable option the M7 spec explicitly allows ("leaves it safely
## positioned until the player gets up") -- and return_to_rest() (called
## by sleep_state.gd's get-up handling) puts it back exactly where it
## started, since by then the camera is already mid-transition and a
## snap there is unremarkable.

@export var laptop_path: NodePath
@export var lap_anchor_path: NodePath
@export var log_screen_path: NodePath

## Held pose is expressed relative to the lap anchor itself, which
## already encodes the correct world distance/height for the laptop to
## rest naturally on the lap (see player_body.tscn's LapAnchor) -- so
## these only need to be a small resting offset plus whatever rotation
## makes the screen face back toward the eye.
##
## held_local_rotation_degrees' X component (-20) tilts the WHOLE
## laptop back slightly -- the same thing a real person does, propping
## the back edge of a laptop up a little when it's resting on their
## lap and their eyes are well above it, rather than leaving it
## perfectly flat. Found empirically (see the "next iteration" report):
## with the laptop flat (0 here) no reachable hinge angle on
## laptop.gd's open_angle_degrees aims the screen within 60+ degrees of
## the eye; a modest base tilt plus a wide-ish (but still physically
## normal) hinge angle gets the screen normal within ~24 degrees of
## pointing straight at the eye. Does not affect is_open()/is_editing()
## or the keyboard's own usability -- it is a presentation-only tilt of
## the physical mesh.
@export var pickup_duration: float = 0.4
@export var held_local_position: Vector3 = Vector3.ZERO
@export var held_local_rotation_degrees: Vector3 = Vector3(-20, 0, 0)

@onready var _laptop: Node3D = get_node(laptop_path)
@onready var _lap_anchor: Node3D = get_node(lap_anchor_path)
@onready var _log_screen = get_node(log_screen_path)

var _resting_parent: Node
var _resting_transform: Transform3D
var _is_open := false
var _is_editing := false
var _saved_entry: String = ""
var _move_tween: Tween


func _ready() -> void:
	_resting_parent = _laptop.get_parent()
	_resting_transform = _laptop.transform
	_laptop.set_screen_texture(_log_screen.get_feed_texture())
	_log_screen.show_entry(_saved_entry)


func is_open() -> bool:
	return _is_open


func is_editing() -> bool:
	return _is_editing


## The physical screen mesh's current world position -- used by
## sleep_state.gd to compute the editor zoom target as a fraction of the
## real live distance to the screen, rather than a second hand-placed
## eye position. Meaningful any time the laptop is open; while editing
## begins, the laptop has already finished its pickup tween and is
## sitting still in held_local_position/held_local_rotation_degrees, so
## this is stable for the whole zoom-in tween.
func get_screen_global_position() -> Vector3:
	return _laptop.get_node("HingePivot/LidBack/ScreenGlow").global_position


## The screen mesh's actual front-facing normal, read from its LIVE
## global transform (not a hand-guessed constant) -- the screen is a
## thin CSGBox3D, so its flat axis (local Y) is the normal; reference_point
## (always the viewer's eye, before any zoom) picks which of the two
## opposite directions along that axis is "outward" (toward the viewer)
## rather than assuming a fixed authoring convention. Used by
## sleep_state.gd's editor zoom to align the camera's viewing direction
## exactly opposite this normal -- "looking squarely at the screen" --
## instead of merely aiming at its center point, which still left the
## screen looking like a keystoned trapezoid whenever the laptop's own
## tilt (held_local_rotation_degrees, open_angle_degrees) put the screen
## plane at an angle to the straight line from the eye to its center.
func get_screen_outward_normal(reference_point: Vector3) -> Vector3:
	var screen: Node3D = _laptop.get_node("HingePivot/LidBack/ScreenGlow")
	var normal: Vector3 = screen.global_transform.basis.y.normalized()
	var to_reference: Vector3 = (reference_point - screen.global_position).normalized()
	if normal.dot(to_reference) < 0.0:
		normal = -normal
	return normal


## The lid's own front edge (opposite the hinge) -- where a hand would
## actually grip to open it -- used by sleep_state.gd to aim the
## open-laptop hand gesture (player_body.gd's animate_hand_open_laptop())
## at a point on the physical object instead of an arbitrary offset.
func get_lid_grip_global_position() -> Vector3:
	return _laptop.get_node("HingePivot/LidBack").global_position


## How long the lid's own hinge animation takes -- used by
## sleep_state.gd to time the open-laptop hand gesture against the
## actual lid-opening motion, once the laptop has finished settling
## into the held pose (see open_laptop()'s deferred call: the grip
## position is only meaningful AFTER the pickup tween completes).
func get_hinge_duration() -> float:
	return _laptop.hinge_animation_duration


## Reparents the laptop onto the lap anchor (keep_global_transform
## means it stays exactly where it visually is at that instant, so it
## never jumps), then eases it into the held pose and opens the lid.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_laptop.reparent(_lap_anchor, true)
	_kill_move_tween()
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.tween_property(_laptop, "position", held_local_position, pickup_duration)
	_move_tween.tween_property(_laptop, "rotation_degrees", held_local_rotation_degrees, pickup_duration)
	_move_tween.chain().tween_callback(func(): _laptop.set_open(true))


## Folds the lid shut. The laptop stays on the lap anchor, closed,
## until return_to_rest() is called (see get-up handling) -- this is
## deliberate, not a bug: see the class doc comment above.
func close() -> void:
	if not _is_open:
		return
	if _is_editing:
		end_editing()
	_is_open = false
	_laptop.set_open(false)


func begin_editing() -> void:
	if not _is_open or _is_editing:
		return
	_is_editing = true
	_log_screen.set_editing(true)


## Saves the entry WITHOUT exiting editing (M7.2 Priority 3: Ctrl+S).
func save_entry() -> void:
	if not _is_editing:
		return
	_saved_entry = _log_screen.get_entry_text()


func end_editing() -> void:
	if not _is_editing:
		return
	_saved_entry = _log_screen.get_entry_text()
	_log_screen.set_editing(false)
	_is_editing = false


## Forwards a real keyboard event into the laptop screen's SubViewport
## so its focused TextEdit receives it as ordinary typing. Only
## meaningful while editing; sleep_state.gd only calls this then.
func forward_key_to_screen(event: InputEventKey) -> void:
	_log_screen.forward_key(event)


## Called by sleep_state.gd once the player is actually getting up, so
## the laptop is guaranteed to be back at its original resting spot by
## the time the player is standing again, regardless of whether it was
## ever picked up this cycle. Idempotent.
func return_to_rest() -> void:
	if _laptop.get_parent() == _resting_parent:
		return
	_kill_move_tween()
	_laptop.reparent(_resting_parent, false)
	_laptop.transform = _resting_transform


func _kill_move_tween() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
