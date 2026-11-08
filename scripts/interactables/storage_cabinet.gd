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
## Round 28: optional DayPlan + the fact recorded the first time the part
## leaves this cabinet (e.g. &"retrieved:filter").
@export var day_plan_path: NodePath
@export var retrieval_fact: StringName = &""

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
var _last_fact_stock: int = 0
## Round 31: engineered slots (global rest transforms), one per authored part.
var _slots: Array = []
## Round 32: the part TYPE each slot was authored for (several compatible
## types can share a cabinet, e.g. power harnesses on the shelf and
## shielded signal cables in the lower tray).
var _slot_types: Array = []
## Where this cabinet's stock lives in the tree (captured at load).
var _home_parent: Node = null
## The part type this cabinet stocks (from its authored parts).
@export var stock_item_id: StringName = &""
## At or below this many parts the placard and workstation warn.
const LOW_STOCK: int = 1
const PART_NAMES = preload("res://scripts/station/part_names.gd")


func _ready() -> void:
	add_to_group(&"storage_cabinet")
	for path in item_paths:
		var item: Node = get_node_or_null(path)
		if item != null:
			_items.append(item)
			if item is Node3D:
				_rest_positions[item] = (item as Node3D).global_position
				# Round 31: every authored part defines one engineered SLOT;
				# capacity is exactly the number of real slots.
				_slots.append((item as Node3D).global_transform)
				_slot_types.append(item.item_id if "item_id" in item else &"")
			_was_stowed[item] = true
			if _home_parent == null:
				_home_parent = item.get_parent()
			if stock_item_id == &"" and "item_id" in item:
				stock_item_id = item.item_id
	_build_slot_holders()
	if _interior_light != null:
		_interior_light.light_energy = 0.0
	_apply_item_gating()
	_last_fact_stock = stock_count()
	_refresh_stock_label()


func _process(_delta: float) -> void:
	# Parts consumed for good (freed) leave the stock list for good.
	_items = _items.filter(func(it): return is_instance_valid(it))
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
	if not _open:
		# Round 31: a door that starts closing cancels any reach into it --
		# the hand never grabs a part through a shutting door.
		for item in _items:
			var cs: Variant = item.get("_carry_system") if is_instance_valid(item) else null
			if cs != null and cs.has_method("is_reserved") and cs.is_reserved(item):
				cs.cancel_reach()
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


## Round 30: true when `item` is one of THIS cabinet's parts and the door
## is fully open -- carry_system.gd then stows it back on its shelf slot.
## Round 31: any compatible, unused part (same item_id -- one of this
## cabinet's own, or one carried over from the reserve crate) is accepted
## while the door is fully open and a slot is free.
func accepts_item(item: Node) -> bool:
	if not (_open and _gate_open) or item == null or not ("item_id" in item):
		return false
	if item.has_method("is_carrier"):
		return item.can_unload_into(self)
	if not _slot_types.has(item.item_id):
		return false
	if item.has_method("is_installed") and item.is_installed():
		return false
	return free_slot_index(item) != -1


## Puts `item` in a slot (its own if free, else the first free one) and
## takes ownership of it: it becomes this cabinet's stock. Returns false
## (touching nothing) if no slot is free.
func stow(item: Node3D) -> bool:
	var idx: int = free_slot_index(item)
	if idx == -1:
		return false
	var slot: Transform3D = _slots[idx]
	if item.has_method("set_rest_global"):
		# Adopted parts (e.g. from the reserve crate) move home: same parent
		# as this cabinet's own stock.
		item.set_rest_global(slot, _home_parent)
	_rest_positions[item] = slot.origin
	if not _items.has(item):
		_items.append(item)
		_was_stowed[item] = false
		var dpl: Node = get_node_or_null(day_plan_path)
		if dpl != null and dpl.has_method("log_event"):
			dpl.log_event("Restocked: %s" % stock_item_name, &"restocked")
	item.return_to_rest()
	_gate_item(item)
	return true


## Round 33: called by the carry system at the grasp of one of this
## cabinet's stowed parts -- the retrieval step, recorded deterministically.
func on_item_taken(_item: Node) -> void:
	if retrieval_fact == &"":
		return
	var dp: Node = get_node_or_null(day_plan_path)
	if dp != null and dp.has_method("record_fact") and not dp.has_fact(retrieval_fact):
		dp.record_fact(retrieval_fact)


## Round 33 save/load: index of the slot `item` currently occupies, or -1.
func slot_index_of(item: Node) -> int:
	if not is_item_stowed(item):
		return -1
	for i in _slots.size():
		if _slots[i].origin.distance_to(_rest_positions[item]) < _STOWED_TOLERANCE:
			return i
	return -1


## Round 33 save/load: put `item` into exactly slot `idx` (no logging, no
## retrieval facts) while restoring a saved game.
func persist_place(item: Node3D, idx: int) -> bool:
	if idx < 0 or idx >= _slots.size():
		return false
	if item.has_method("set_rest_global"):
		item.set_rest_global(_slots[idx], _home_parent)
	_rest_positions[item] = _slots[idx].origin
	if not _items.has(item):
		_items.append(item)
	item.return_to_rest()
	_was_stowed[item] = true
	_gate_item(item)
	_last_fact_stock = stock_count()
	return true


## Round 33 save/load: re-baseline after a restore so the restored stock is
## not mistaken for a retrieval.
func persist_refresh() -> void:
	_items = _items.filter(func(it): return is_instance_valid(it))
	_apply_item_gating()
	_last_fact_stock = stock_count()
	_refresh_stock_label()


func capacity(id: StringName = &"") -> int:
	if id == &"":
		return _slots.size()
	return _slot_types.count(id)


func is_stock_low(id: StringName = &"") -> bool:
	return stock_count(id if id != &"" else stock_item_id) <= LOW_STOCK


## Part types this cabinet stocks, in slot order.
func stock_types() -> Array:
	var out: Array = []
	for t in _slot_types:
		if not out.has(t):
			out.append(t)
	return out


## Slot `item` should go to: its own slot when that is free, otherwise the
## first slot no stowed part occupies. -1 when the cabinet is full.
func free_slot_index(item: Node = null) -> int:
	var taken: Array = []
	for other in _items:
		if other != item and is_item_stowed(other):
			taken.append(_rest_positions[other])
	if item != null and _rest_positions.has(item):
		var own: Vector3 = _rest_positions[item]
		var own_free := true
		for t in taken:
			if (t as Vector3).distance_to(own) < _STOWED_TOLERANCE:
				own_free = false
		for i in _slots.size():
			if _slots[i].origin.distance_to(own) < _STOWED_TOLERANCE and own_free:
				return i
	for i in _slots.size():
		if item != null and "item_id" in item and _slot_types[i] != item.item_id:
			continue
		var used := false
		for t in taken:
			if (t as Vector3).distance_to(_slots[i].origin) < _STOWED_TOLERANCE:
				used = true
		if not used:
			return i
	return -1


## The authored cabinet has one retaining holder (filter clamp ring/arm/
## strap, wire retaining strap) at its first slot; every further slot gets
## an identical holder, so each stocked part is visibly secured.
func _build_slot_holders() -> void:
	if _slots.size() < 2:
		return
	var holders: Array = []
	for n in ["ClampRing", "ClampArm", "ClampStrap", "RetainingStrap"]:
		var h: Node = get_node_or_null(n)
		if h is Node3D:
			holders.append(h)
	var base: Vector3 = _slots[0].origin
	for i in range(1, _slots.size()):
		var off: Vector3 = _slots[i].origin - base
		for h in holders:
			var d: Node3D = (h as Node3D).duplicate()
			d.name = "%s_Slot%d" % [h.name, i + 1]
			add_child(d)
			d.global_position = (h as Node3D).global_position + off





func is_open() -> bool:
	return _open


## Number of this cabinet's items still physically on their shelf.
func stock_count(id: StringName = &"") -> int:
	var n: int = 0
	for item in _items:
		if is_item_stowed(item) and (id == &"" or ("item_id" in item and item.item_id == id)):
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
func is_item_stowed(item) -> bool:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return false
	if item.has_method("is_installed") and item.is_installed():
		return false
	# Round 30: a part already taken is in the HAND even while it still
	# sits at its shelf spot waiting for the reach to grasp it -- closing
	# the door then must not hide or disable it.
	var cs: Variant = item.get("_carry_system")
	if cs != null and cs.has_method("is_holding") and cs.is_holding(item):
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
	var count: int = stock_count()
	# Round 31: with several parts per cabinet, TAKING one (stock drops)
	# is the retrieval step; DayPlan's record_fact() is idempotent and
	# facts reset each day.
	if count < _last_fact_stock and retrieval_fact != &"":
		var dp: Node = get_node_or_null(day_plan_path)
		if dp != null and dp.has_method("record_fact") and not dp.has_fact(retrieval_fact):
			dp.record_fact(retrieval_fact)
	_last_fact_stock = count
	if _stock_label == null:
		_last_stock = count
		return
	if count == _last_stock:
		return
	_last_stock = count
	var lines: Array = [stock_item_name]
	var any_low := false
	for t in stock_types():
		var n: int = stock_count(t)
		var tag: String = ("%s  " % PART_NAMES.short(t)) if stock_types().size() > 1 else ""
		var l: String = "%s%d AVAILABLE" % [tag, n]
		if n == 0:
			l = "%s0 AVAILABLE — RESTOCK" % tag
		elif n <= LOW_STOCK:
			l = "%s%d AVAILABLE — LOW" % [tag, n]
		any_low = any_low or n <= LOW_STOCK
		lines.append(l)
	_stock_label.text = "\n".join(lines)
	_stock_label.modulate = Color(0.95, 0.45, 0.3, 1) if any_low else Color(0.92, 0.9, 0.82, 1)
