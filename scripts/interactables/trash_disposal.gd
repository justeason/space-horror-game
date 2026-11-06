extends StaticBody3D
## Round 21 Priority 4/8: the Storage disposal container for used/dirty
## parts -- the back half of the filter loop's "not just magically
## deleted" requirement (see used_filter_cartridge.gd's own class doc
## comment for the front half: a real, physical, carryable used part).
## Duck-typed interact(): if the player is carrying an item this bin
## accepts, throwing it away consumes it via carry_system.gd's
## take_carried_item_if_matches() and calls the item's own dispose() --
## the same "gate a procedure on carry state, consume on success"
## pattern electrical_panel.gd/filter_housing_station.gd already use
## for INSTALLING a part, just inverted for discarding one.

@export var carry_system_path: NodePath
@export var sfx_path: NodePath
@export var message_label_path: NodePath
@export var message_duration: float = 2.0
## Round 28: optional DayPlan, told when the used filter is disposed.
@export var day_plan_path: NodePath

## Which item_ids this bin accepts -- kept narrow (not "anything
## currently carried") so it reads as a specific parts-disposal point
## next to the filter supply, not a catch-all trash can for every
## carryable in the game.
const _ACCEPTED_ITEM_IDS: Array[StringName] = [&"used_filter_cartridge"]

@onready var _carry_system: Node = get_node_or_null(carry_system_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)
@onready var _message_label: Label = get_node_or_null(message_label_path)
@onready var _day_plan: Node = get_node_or_null(day_plan_path)
## Round 22 Priority 2/6: a brief hinged-flap open/close on a successful
## disposal -- the "small but clear physical interaction feel" Priority
## 6 asked for, reusing the exact same hinge-rotation-tween pattern
## storage_cabinet.gd's own door already uses, so throwing something
## away reads as a real physical act (the flap actually opens to
## receive it) rather than the item just vanishing the instant you
## click.
@onready var _flap_hinge: Node3D = get_node_or_null("FlapHinge")
@onready var _indicator: CSGBox3D = get_node_or_null("Indicator")
const _FLAP_OPEN_DEGREES: float = -75.0

var _message_timer: float = 0.0
var _disposed_count: int = 0
var _flap_tween: Tween


func _ready() -> void:
	add_to_group(&"no_place")   # Round 32: not a place-gesture surface


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			if _message_label.get_meta(&"msg_owner", 0) == get_instance_id():   # shared HUD label: hide only our own message
				_message_label.visible = false


func interact() -> void:
	if _carry_system == null or not _carry_system.is_carrying():
		_show_message("Nothing to dispose of.")
		return
	var carried_id: StringName = _carry_system.carried_item_id()
	if not _ACCEPTED_ITEM_IDS.has(carried_id):
		_show_message("That doesn't belong in this disposal unit.")
		return
	var item: Node3D = _carry_system.take_carried_item_if_matches(carried_id)
	var dpl: Node = get_node_or_null(day_plan_path)
	if item != null and dpl != null and dpl.has_method("log_event"):
		dpl.log_event("Disposed: %s" % (item.get_display_name() if item.has_method("get_display_name") else "part"))
	if item == null:
		return
	if item.has_method("dispose"):
		item.dispose()
	_disposed_count += 1
	if _day_plan != null and carried_id == &"used_filter_cartridge":
		_day_plan.record_fact(&"disposed:used_filter")
	if _sfx != null:
		_sfx.play_kind(&"success")
	_show_message("Disposed of used filter cartridge.")
	_play_flap_cycle()


## Opens the flap, holds briefly, closes it again -- a one-shot visual
## confirmation that something was actually received, not a looping
## idle animation. Safe to call back-to-back (kills any in-flight
## tween first, same "never let two tweens fight over the same node"
## convention as every other hinge animation in this project).
func _play_flap_cycle() -> void:
	if _flap_hinge == null:
		return
	if _flap_tween != null and _flap_tween.is_valid():
		_flap_tween.kill()
	_flap_tween = create_tween()
	_flap_tween.tween_property(_flap_hinge, "rotation_degrees:x", _FLAP_OPEN_DEGREES, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flap_tween.tween_interval(0.35)
	_flap_tween.tween_property(_flap_hinge, "rotation_degrees:x", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _indicator != null and _indicator.material != null:
		var mat: StandardMaterial3D = _indicator.material
		var indicator_tween: Tween = create_tween()
		indicator_tween.tween_property(mat, "emission_energy_multiplier", 3.0, 0.1)
		indicator_tween.tween_property(mat, "emission_energy_multiplier", 1.2, 0.4)


func get_interact_prompt() -> String:
	if _carry_system == null or not _carry_system.is_carrying():
		return "Space Trash Disposal"
	var carried_id: StringName = _carry_system.carried_item_id()
	if _ACCEPTED_ITEM_IDS.has(carried_id):
		return "Click: Throw Away %s" % _carry_system.carried_item_display_name()
	return "Space Trash Disposal (not for this item)"


## For tests/wristwatch hinting: how many items have actually been
## disposed of this session -- not persisted (matches this project's
## existing "no save/load system" scope, same as e.g.
## sensor_calibration_view.gd's own session-only completion counter).
func disposed_count() -> int:
	return _disposed_count


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.set_meta(&"msg_owner", get_instance_id())
	_message_label.visible = true
	_message_timer = message_duration
