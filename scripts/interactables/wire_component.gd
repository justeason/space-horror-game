extends StaticBody3D
## The one retrievable component for Slice B's S01 -> E05 chain: a
## labeled replacement wire normally resting in its Storage bin.
##
## Duck-typed contracts satisfied: `interact()` (interaction_controller.gd),
## `item_id` + `return_to_rest()` (scripts/player/carry_system.gd).

@export var carry_system_path: NodePath
@export var item_id: StringName = &"wire_control_16ga"
@export var message_label_path: NodePath
@export var message_duration: float = 1.5

@onready var _carry_system: Node = get_node(carry_system_path)
@onready var _message_label: Label = get_node_or_null(message_label_path)

var _resting_parent: Node
var _resting_transform: Transform3D
var _message_timer: float = 0.0
## Set once by mark_installed() below. A permanently-installed wire is
## no longer a loose pickup: interact()/get_interact_prompt() both
## become inert so it can never be picked back up "as if it were still
## loose" (Phase 2.C's explicit requirement), while remaining a normal,
## visible world object otherwise.
var _installed: bool = false
## Round 16 Priority 3: which color this attempt's electrical_panel.gd
## config says the required wire is -- defaults to "Yellow" (this
## prop's only color before this round), set via set_fault_color()
## the moment a config is chosen (electrical_panel.gd's _trace()),
## independent of whether this prop has been picked up yet.
var _color_name: String = "Yellow"


func _ready() -> void:
	_resting_parent = get_parent()
	_resting_transform = transform


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			_message_label.visible = false


func interact() -> void:
	if _installed:
		return
	if _carry_system.is_carrying():
		return
	if _carry_system.pick_up(self):
		_show_message("Picked up: Control Wire (16-gauge, %s)." % _color_name.to_lower())


## Called once by electrical_panel.gd's _select_repair_config() the
## moment this attempt's fault role is chosen -- recolors this prop's
## own insulation material (CoilLoopA/B/CableEndA/B all already share
## ONE resource by original design, so this one assignment recolors the
## whole spare consistently) to match, so the carried part's color is
## never a stale "always yellow" mismatch against whichever wire this
## attempt's diagnostic/diorama actually says is faulted.
func set_fault_color(color_name: String, color: Color) -> void:
	_color_name = color_name
	var mat: StandardMaterial3D = get_node("CoilLoopA").material
	mat.albedo_color = color


func get_interact_prompt() -> String:
	if _installed:
		return ""
	if _carry_system.is_carrying():
		return ""
	return "Click: Pick Up Wire Component"


func is_installed() -> bool:
	return _installed


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true
	_message_timer = message_duration


## Called by carry_system.gd's drop() -- puts this wire back exactly
## where it started, parented back under its original Storage rack.
func return_to_rest() -> void:
	reparent(_resting_parent, false)
	transform = _resting_transform


## Called by carry_system.gd's Space drop action: places this wire at an
## arbitrary world position/orientation found by that script's own
## floor/clearance checks (e.g. on the floor near the player), rather
## than snapping back to its original Storage resting spot. Reparents to
## the same parent return_to_rest() uses so it stays a normal, clickable
## world object afterward -- not a special "dropped" state.
func place_in_world(world_transform: Transform3D) -> void:
	reparent(_resting_parent, false)
	global_transform = world_transform


func get_display_name() -> String:
	return "Wire Component"


## Called once by electrical_panel.gd's _attempt_install(), after
## carry_system.gd's take_carried_item_if_matches() has already removed
## this node from the carry system (so this never runs while still
## "carried" from that system's point of view). Reparents under the
## correct Terminal node at a fixed local pose and disables this body's
## own collision so it no longer competes for raycasts aimed at the
## terminal/cabinet behind it. Idempotent: electrical_panel.gd's own
## repair-stage gating already ensures this is only ever called once
## per wire, but a stray second call is still a safe no-op rather than
## re-parenting/duplicating anything.
##
## ROUND 16 FIX (Priority 2, "the replacement wire still looks like an
## extra object sitting next to the three main wires"): this used to
## also leave the wire VISIBLE here, which reparents this node's own
## COILED-SPARE geometry (CoilLoopA/B etc. -- a visually distinct shape
## from the diorama's own smooth curved cable wires, authored for a
## carryable pickup prop, not for matching the repair diorama's own
## service-wire mesh) directly into the cabinet's recessed service bay,
## right alongside electrical_repair_diorama.gd's own `_replacement_wire`
## node -- which is the ACTUAL, authoritative "installed replacement
## wire" visual, shown identically in both the focused close-up view
## and the world-embedded diorama twin (Round 13's "one shared diorama,
## not two independently hand-authored geometries" architecture). Round
## 15 only recolored this node (blue -> yellow) to match that same
## diorama wire, which fixed the color mismatch but left the actual
## DUPLICATE OBJECT in place -- still reading as an unrelated fourth
## wire/coil sitting in the compartment, just now a yellow one instead
## of a blue one. This node is still reparented under Terminal (kept
## addressable at a real location for is_installed()/get_parent()
## checks already relied on elsewhere) but now goes invisible the
## moment it installs: the diorama's own `_replacement_wire` is the one
## and only visible "installed wire" from this point on, exactly as it
## already was for the other two (never-replaced) wires.
func mark_installed(parent_node: Node, local_transform: Transform3D) -> void:
	if _installed:
		return
	_installed = true
	reparent(parent_node, false)
	transform = local_transform
	visible = false
	var collision := get_node_or_null("Collision")
	if collision != null:
		collision.disabled = true
	if _message_label != null:
		_message_timer = 0.0
		_message_label.visible = false
