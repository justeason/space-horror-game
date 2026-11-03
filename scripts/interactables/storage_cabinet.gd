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
## Round 24 Priority 1/5: the cabinets are now genuinely recessed into
## the Storage walls (~0.6m deep, see main.tscn's split
## StorageWestWall*/StorageEastWall* pieces), so their contents sit
## well back from the room's own lighting. A small interior lamp
## (optional OmniLight3D) switches on as the door starts to open and
## off once it has fully closed -- same "real fixture, not a UI hint"
## approach as every other light in the station.
@export var interior_light_path: NodePath
@export var interior_light_energy: float = 0.9
## Round 24 Priority 5: a stock placard on the door (optional Label3D)
## showing what this locker holds and how many are still stowed --
## "QTY 0 - RESTOCK" once the part has been taken, so the player can
## read the locker's state without opening it.
@export var stock_label_path: NodePath
@export var stock_item_name: String = ""

## Max distance (m) from an item's recorded resting position for it to
## still count as physically stowed in this cabinet.
const _STOWED_TOLERANCE: float = 0.05

@onready var _door_hinge: Node3D = get_node(door_hinge_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)
@onready var _interior_light: Light3D = get_node_or_null(interior_light_path)
@onready var _stock_label: Label3D = get_node_or_null(stock_label_path)
var _items: Array[Node] = []
## Each item's resting GLOBAL position, recorded once at _ready().
var _rest_positions: Dictionary = {}
## Last-known stowed state per item, so _process() can react the moment
## an item comes BACK to rest (e.g. carry_system.gd's drop() ->
## return_to_rest() while this door is shut).
var _was_stowed: Dictionary = {}
var _open: bool = false
## Whether the door has finished opening. Gating follows this, not
## _open, so stowed items stay hidden for the whole swing.
var _gate_open: bool = false
var _tween: Tween
var _last_stock: int = -1


func _ready() -> void:
	for path in item_paths:
		var item: Node = get_node_or_null(path)
		if item != null:
			_items.append(item)
			if item is Node3D:
				_rest_positions[item] = (item as Node3D).global_position
			_was_stowed[item] = true
	if _interior_light != null:
		_interior_light.light_energy = 0.0
	_apply_item_gating()
	_refresh_stock_label()


func _process(_delta: float) -> void:
	for item in _items:
		var stowed: bool = is_item_stowed(item)
		if stowed and not _was_stowed.get(item, false):
			# Came back to rest (dropped back into storage): re-apply
			# this door's current gating to it.
			_gate_item(item)
		_was_stowed[item] = stowed
	_refresh_stock_label()


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
	if _open and _interior_light != null:
		_interior_light.light_energy = interior_light_energy
	_tween = create_tween()
	_tween.tween_property(_door_hinge, "rotation_degrees:y", target_deg, open_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Items reveal/hide once the door has actually finished swinging,
	# not mid-animation -- they stay physically behind the still-shut
	# (or still-closing) door for the full motion either way.
	_tween.tween_callback(_on_swing_finished)


func get_interact_prompt() -> String:
	return "Click: Close Storage Cabinet" if _open else "Click: Open Storage Cabinet"


func is_open() -> bool:
	return _open


## Number of this cabinet's items still physically on their shelf.
func stock_count() -> int:
	var n: int = 0
	for item in _items:
		if is_item_stowed(item):
			n += 1
	return n


## True only while `item` is still physically at its resting spot in
## this cabinet: not carried, not dropped elsewhere, not installed.
##
## Round 24 Priority 2 ROOT-CAUSE FIX: _apply_item_gating() used to set
## visible/collision on EVERY listed item whenever the door moved,
## wherever that item now was. Opening or closing a cabinet after its
## part had been taken therefore reached out and changed an object that
## was no longer inside it:
## - closing StorageCabinet2 while carrying the new filter hid the
##   cartridge in the player's hand and disabled its collision;
## - opening a cabinet after an install set the installed part (wire or
##   filter, both deliberately hidden by their own mark_installed())
##   VISIBLE again at its install location, i.e. a second, decorative
##   copy of a part that is supposed to be inside a sealed housing.
## Gating now applies only to items that are genuinely still stowed.
func is_item_stowed(item: Node) -> bool:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return false
	if item.has_method("is_installed") and item.is_installed():
		return false
	if not (item is Node3D) or not _rest_positions.has(item):
		return false
	return (item as Node3D).global_position.distance_to(_rest_positions[item]) <= _STOWED_TOLERANCE


func _on_swing_finished() -> void:
	_gate_open = _open
	if not _open and _interior_light != null:
		_interior_light.light_energy = 0.0
	_apply_item_gating()


func _apply_item_gating() -> void:
	for item in _items:
		_gate_item(item)


func _gate_item(item: Node) -> void:
	if not is_item_stowed(item):
		return
	if "visible" in item:
		item.visible = _gate_open
	var collision: Node = item.get_node_or_null("Collision")
	if collision != null and "disabled" in collision:
		collision.disabled = not _gate_open


func _refresh_stock_label() -> void:
	if _stock_label == null:
		return
	var count: int = stock_count()
	if count == _last_stock:
		return
	_last_stock = count
	var line2: String = "QTY %d" % count
	if count == 0:
		line2 = "QTY 0 — RESTOCK"
	_stock_label.text = "%s\n%s" % [stock_item_name, line2]
	_stock_label.modulate = Color(0.92, 0.9, 0.82, 1) if count > 0 else Color(0.95, 0.45, 0.3, 1)
