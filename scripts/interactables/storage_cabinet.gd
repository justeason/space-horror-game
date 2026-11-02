extends Node3D
## Round 19 Priority 3: a small physical parts locker in the Storage
## room. Player feedback was that replacement parts "feel like they
## appear magically on countertops" -- investigation found the parts
## were ALREADY physically located in the Storage room (e.g.
## WireComponent already sits on Geometry/StorageRack1Shelf), but
## nothing actually enclosed them: the "shelf" was open air next to a
## solid decorative rack, directly clickable with no door, drawer, or
## any opening ritual at all. This script adds that missing layer: a
## real hinged door (see door_hinge_path) that must be opened with E
## before any item inside becomes visible or clickable, and closed
## again the same way.
##
## This deliberately does NOT touch carry/pickup logic at all -- the
## contained item's own interact()/pick_up() path (e.g.
## wire_component.gd) is completely unchanged. This script only decides
## whether that item's own collision shape can be hit by a raycast in
## the first place (disabled while the door is shut), the same
## "gate the existing object, don't duplicate its logic" pattern this
## project already uses for e.g. HeadGroup's render-layer gating.
##
## Round 21 Priority 3, TWO further fixes, both confirmed by reading
## this file and main.tscn (not assumed from the player's own guess at
## the cause):
## 1. The door was never actually openable: this script's interact()
##    lives on this ROOT node, but every collidable surface is a
##    separate child CSGBox3D (Back/Top/Bottom/SideNear/SideFar/
##    DoorPanel) -- a raycast hit on any of them returned THAT CHILD as
##    the collider, which has no interact() of its own, so
##    interaction_controller.gd's strict "the hit collider itself must
##    have interact()" check always failed silently. Fixed centrally in
##    interaction_controller.gd (an additive ancestor-walk fallback),
##    not here -- this script's own node structure is unchanged.
## 2. The cabinet used to be a small box bolted onto the SIDE of the
##    big decorative StorageRack, sticking out past it into the room.
##    Both cabinets were rebuilt to share their rack's own footprint
##    (same width/depth) as a true middle section of one continuous
##    built-in unit (the rack is now split into Upper/Lower pieces
##    flanking the cabinet door vertically), so the interactive storage
##    now reads as part of the larger closet-like furniture instead of
##    a separate appendage -- see main.tscn's own StorageCabinet1/2 and
##    StorageRack1Upper/Lower/2Upper/Lower node groups.

@export var door_hinge_path: NodePath
## Items physically inside this cabinet (NodePaths relative to this
## node) -- hidden and non-collidable while the door is shut, shown and
## collidable once it is open. Each item is expected to own a
## "Collision" child (CollisionShape3D) or be a CollisionObject3D
## itself, matching every other interactable prop in this project.
@export var item_paths: Array[NodePath] = []
@export var open_duration: float = 0.5
@export var door_open_degrees: float = -100.0
## Round 20 Priority 8: the same shared procedural sound bank every
## other mechanical interactable in this project already uses (see
## carry_system.gd's own sfx_path doc comment) -- a hinged door opening/
## closing is the same kind of small mechanical feedback those already
## play. Optional (get_node_or_null): harmless no-op if left unwired.
@export var sfx_path: NodePath

@onready var _door_hinge: Node3D = get_node(door_hinge_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)
var _items: Array[Node] = []
var _open: bool = false
var _tween: Tween


func _ready() -> void:
	for path in item_paths:
		var item: Node = get_node_or_null(path)
		if item != null:
			_items.append(item)
	_apply_item_gating()


## Idempotent toggle, same "repeated clicks just flip state cleanly"
## contract as every other door/hatch interactable in this project
## (e.g. electrical_panel.gd's own door interact()).
func interact() -> void:
	_open = not _open
	if _sfx != null:
		_sfx.play_kind(&"clunk")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var target_deg: float = door_open_degrees if _open else 0.0
	_tween = create_tween()
	_tween.tween_property(_door_hinge, "rotation_degrees:y", target_deg, open_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Items reveal/hide once the door has actually finished swinging,
	# not mid-animation -- they stay physically behind the still-shut
	# (or still-closing) door for the full motion either way.
	_tween.tween_callback(_apply_item_gating)


func get_interact_prompt() -> String:
	return "Click: Close Storage Cabinet" if _open else "Click: Open Storage Cabinet"


func is_open() -> bool:
	return _open


func _apply_item_gating() -> void:
	for item in _items:
		if "visible" in item:
			item.visible = _open
		var collision: Node = item.get_node_or_null("Collision")
		if collision != null and "disabled" in collision:
			collision.disabled = not _open
