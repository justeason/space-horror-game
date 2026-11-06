extends StaticBody3D
## Life Support's filter housing -- implements L02 Filter Replacement
## (GAME_DESIGN.md Section 29: "Isolate airflow -> close valves ->
## depressurize -> remove -> match -> install -> restore valves in
## correct order -> verify"). Round 15 Priority 4: a maintenance
## procedure built on ALIGNMENT AND INSERTION rather than wire-sequence
## memory (electrical repair) or discrete valve-open/closed routing
## (coolant loop) -- the new cartridge must be rotated to match the
## housing's keyway before it will seat, not merely clicked in the
## right order.
##
## Same "physical object owns its procedure state; views are
## presentation-only" split as electrical_panel.gd/valve_routing_station.gd.

enum Stage { ISOLATE, OPEN_LATCHES, REMOVE_OLD, ALIGN_INSERT, CLOSE_LATCHES, RESTORE, COMPLETE }

const GameSettings = preload("res://scripts/station/game_settings.gd")

## Fixed puzzle instance (same policy as every other minigame in this
## project): one authored target keyway angle, not randomized.
const _TARGET_ANGLE_DEG: float = 135.0
const _START_ANGLE_DEG: float = 0.0
const _ROTATE_STEP_DEG: float = 45.0

const _TOLERANCE_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: 40.0,
	GameSettings.Difficulty.NORMAL: 20.0,
	GameSettings.Difficulty.HARD: 8.0,
}
## Whether the correct target angle is highlighted for the player, per
## difficulty -- EASY shows it outright, NORMAL/HARD require reading the
## housing's own physical keyway marker instead of a UI hint.
const _SHOW_GUIDE_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: true,
	GameSettings.Difficulty.NORMAL: false,
	GameSettings.Difficulty.HARD: false,
}

@export var day_plan_path: NodePath
@export var filter_view_path: NodePath
## Round 20 Priority 4: the replacement cartridge must now be physically
## retrieved from Storage (StorageCabinet2/FilterCartridge) and carried
## here before the swap can proceed -- same "gate the existing
## procedure on carry_system state, don't duplicate its logic" pattern
## electrical_panel.gd already uses for the electrical spare wire.
@export var carry_system_path: NodePath
const _REQUIRED_ITEM_ID: StringName = &"filter_cartridge"

## Round 21 Priority 4: the physical old/dirty cartridge this station
## ejects once remove_old_cartridge() actually succeeds -- see
## used_filter_cartridge.gd's own class doc comment for the full
## "not just magically deleted" rationale. Optional (get_node_or_null):
## a harmless no-op if left unwired, same defensive convention as
## carry_system_path above.
@export var used_cartridge_path: NodePath
## World-space offset (in THIS station's own local space, so it stays
## correct regardless of room orientation) where the ejected cartridge
## lands -- a nearby floor spot in front of the housing, not inside its
## own collision. Local -Z is this station's own "front" (see
## get_interact_prompt()'s camera-facing convention elsewhere in this
## project); -1.55 in Y reaches down to the Life Support floor from the
## station's own eye-height anchor.
@export var eject_local_offset: Vector3 = Vector3(0.0, -1.55, 0.4)

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _filter_view: Node = get_node_or_null(filter_view_path)
@onready var _world_diorama: Node = get_node_or_null("WorldDiorama")
@onready var _carry_system: Node = get_node_or_null(carry_system_path)
@onready var _used_cartridge: Node = get_node_or_null(used_cartridge_path)

var _stage: Stage = Stage.ISOLATE
var _latch_open := {1: false, 2: false}
var _cartridge_angle_deg: float = _START_ANGLE_DEG
var _active_difficulty: int = -1
var _failed_insert_flash: bool = false
var _missing_part_flash: bool = false


## Round 31 Priority 3: recurring filter service. The cartridge actually
## installed is tracked; when its service interval comes round, DayPlan
## re-arms this housing (back to ISOLATE with that cartridge still seated)
## and the procedure runs again: the cartridge that comes OUT becomes a
## real used cartridge item (a fresh used_filter_cartridge instance once
## the previous one has been disposed of), a clean one from Storage goes in.
const _USED_SCENE := preload("res://scenes/interactables/used_filter_cartridge.tscn")
var _installed_cartridge: Node3D = null
var _used_parent: Node = null
var _used_carry_path: NodePath
var _used_msg_path: NodePath
var _service_count: int = 0


func _ready() -> void:
	if _used_cartridge != null:
		_used_parent = _used_cartridge.get_parent()
		var cs: Node = _used_cartridge.get_node_or_null(_used_cartridge.carry_system_path)
		var ml: Node = _used_cartridge.get_node_or_null(_used_cartridge.message_label_path)
		_used_carry_path = cs.get_path() if cs != null else NodePath()
		_used_msg_path = ml.get_path() if ml != null else NodePath()
	var dp: Node = get_node_or_null(day_plan_path)
	if dp != null and dp.has_method("register_service_rearm"):
		dp.register_service_rearm(dp.Workday.FILTER_SERVICE, _rearm_for_service, _clean_cartridge_available)
	_sync_world_diorama()


func interact() -> void:
	if _filter_view == null:
		return
	if _day_plan.has_method("record_fact"):
		_day_plan.record_fact(&"inspected:filter")
	if _active_difficulty == -1:
		_active_difficulty = GameSettings.get_difficulty()
	_filter_view.open_station(self)


func get_interact_prompt() -> String:
	if is_complete():
		return "Click: Check Filter Housing (Nominal)"
	return "Click: Service Filter Housing"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"l02")


func stage() -> Stage:
	return _stage


## True from the moment airflow is isolated (STAGE 1 complete) until
## it's explicitly restored (STAGE 6) -- drives the valve handle's
## open/closed visual independent of the exact stage enum value.
func is_isolated() -> bool:
	return _stage != Stage.ISOLATE and _stage != Stage.COMPLETE


func tolerance_deg() -> float:
	return _TOLERANCE_BY_DIFFICULTY.get(_current_difficulty(), 20.0)


func guide_shown() -> bool:
	return _SHOW_GUIDE_BY_DIFFICULTY.get(_current_difficulty(), false)


func target_angle_deg() -> float:
	return _TARGET_ANGLE_DEG


func cartridge_angle_deg() -> float:
	return _cartridge_angle_deg


func latch_open(index: int) -> bool:
	return _latch_open.get(index, false)


func _current_difficulty() -> int:
	return _active_difficulty if _active_difficulty != -1 else GameSettings.get_difficulty()


## STAGE 1: isolate airflow (the valve lever click) -- must happen
## before the latches can be touched, matching the documented
## "isolate airflow -> close valves" ordering.
func toggle_isolate() -> Dictionary:
	if _stage == Stage.ISOLATE:
		_stage = Stage.OPEN_LATCHES
		_sync_world_diorama()
		return {"ok": true, "stage": _stage}
	if _stage == Stage.RESTORE:
		_stage = Stage.COMPLETE
		mark_complete()
		_sync_world_diorama()
		return {"ok": true, "stage": _stage, "complete": true}
	return {"ok": false}


## STAGES 2/5: the two latches, reused for both opening (before
## removal) and closing (after the new cartridge seats) -- "restore
## valves in correct order" is satisfied by the fixed stage gating
## itself (latches only do something during OPEN_LATCHES/CLOSE_LATCHES).
func toggle_latch(index: int) -> Dictionary:
	if _stage != Stage.OPEN_LATCHES and _stage != Stage.CLOSE_LATCHES:
		return {"ok": false}
	_latch_open[index] = not _latch_open[index]
	var both_open: bool = _latch_open[1] and _latch_open[2]
	var both_closed: bool = not _latch_open[1] and not _latch_open[2]
	if _stage == Stage.OPEN_LATCHES and both_open:
		_stage = Stage.REMOVE_OLD
	elif _stage == Stage.CLOSE_LATCHES and both_closed:
		_stage = Stage.RESTORE
	_sync_world_diorama()
	return {"ok": true, "stage": _stage, "latch_open": _latch_open.duplicate()}


## STAGE 3: pull the old (contaminated) cartridge -- gated on actually
## carrying the real replacement part retrieved from Storage (Round 20
## Priority 4), the same "no part, no progress, but harmless/
## recoverable" contract electrical_panel.gd's own _attempt_install()
## already uses. A missing-part attempt is explicitly flagged (rather
## than silently returning {"ok": false} like an out-of-stage call) so
## the view can surface a clear, distinct message instead of the
## generic "nothing happened" a player would otherwise see.
func remove_old_cartridge() -> Dictionary:
	if _stage != Stage.REMOVE_OLD:
		return {"ok": false}
	if not _has_required_part():
		_missing_part_flash = true
		return {"ok": true, "removed": false}
	_stage = Stage.ALIGN_INSERT
	_cartridge_angle_deg = _START_ANGLE_DEG
	_sync_world_diorama()
	if (not is_instance_valid(_used_cartridge) or _used_cartridge.is_queued_for_deletion()) and _used_parent != null:
		# The previous used cartridge was disposed of: the cartridge coming
		# out now is a new physical used item. (Round 32: a cartridge
		# disposed earlier in the SAME frame is still "valid" until the
		# deferred free runs -- it must not be re-ejected and then vanish.)
		_used_cartridge = _USED_SCENE.instantiate()
		_used_cartridge.name = "UsedFilterCartridge%d" % (_service_count + 1)
		_used_cartridge.carry_system_path = _used_carry_path
		_used_cartridge.message_label_path = _used_msg_path
		_used_parent.add_child(_used_cartridge)
	if is_instance_valid(_installed_cartridge):
		# The (hidden, seated) cartridge that came out IS the used one now --
		# exactly one physical representation at a time.
		_installed_cartridge.queue_free()
		_installed_cartridge = null
	if is_instance_valid(_used_cartridge) and _used_cartridge.has_method("eject_at"):
		_used_cartridge.eject_at(global_transform * Transform3D(Basis(), eject_local_offset))
	return {"ok": true, "removed": true, "stage": _stage}


func _has_required_part() -> bool:
	return _carry_system != null and _carry_system.is_carrying() and _carry_system.carried_item_id() == _REQUIRED_ITEM_ID


func consume_missing_part_flash() -> bool:
	var v: bool = _missing_part_flash
	_missing_part_flash = false
	return v


## STAGE 4a: rotates the new cartridge by one fixed step -- the actual
## "alignment" half of the mechanic.
func rotate_cartridge(direction: int) -> Dictionary:
	if _stage != Stage.ALIGN_INSERT:
		return {"ok": false}
	_cartridge_angle_deg = fmod(_cartridge_angle_deg + direction * _ROTATE_STEP_DEG + 360.0, 360.0)
	_sync_world_diorama()
	return {"ok": true, "angle": _cartridge_angle_deg}


## STAGE 4b: attempts to seat the cartridge at its CURRENT rotation.
## Succeeds only within this difficulty's tolerance of the fixed target
## angle -- an incorrect attempt is harmless and recoverable (per the
## brief's own "incorrect orientation should physically fail to seat,
## with recoverable feedback... do not silently accept"), not a
## progress-losing failure.
func attempt_insert() -> Dictionary:
	if _stage != Stage.ALIGN_INSERT:
		return {"ok": false}
	var diff: float = abs(wrapf(_cartridge_angle_deg - _TARGET_ANGLE_DEG, -180.0, 180.0))
	if diff <= tolerance_deg():
		if _carry_system != null:
			var item: Node3D = _carry_system.take_carried_item_if_matches(_REQUIRED_ITEM_ID)
			if item != null and item.has_method("mark_installed"):
				item.mark_installed(self, installed_cartridge_local_transform())
				_installed_cartridge = item
				_service_count += 1
				if _day_plan != null and _day_plan.has_method("log_event"):
					_day_plan.log_event("Installed clean filter cartridge")
		_stage = Stage.CLOSE_LATCHES
		_sync_world_diorama()
		return {"ok": true, "seated": true, "stage": _stage}
	_failed_insert_flash = true
	return {"ok": true, "seated": false, "angle_off_deg": diff}


## Round 24 Priority 2: where a seated cartridge physically lives, in
## THIS station's own local space -- the centre of the world twin's own
## housing tube (WorldDiorama/Housing), with the cartridge's own long
## (Y) axis turned to lie along that tube's axis. Replaces the old
## hard-coded Vector3(0, -0.6, 0), which put the "installed" cartridge
## in open air 0.6m below the station. Scale is stripped so the part
## keeps its real size (the twin itself is a scaled model).
func installed_cartridge_local_transform() -> Transform3D:
	var housing: Node3D = _world_diorama.get_node_or_null("Housing") if _world_diorama != null else null
	if housing == null:
		return Transform3D()
	var local: Transform3D = global_transform.affine_inverse() * housing.global_transform
	var axis_basis := Basis(Vector3(0, 0, 1), PI / 2.0)
	return Transform3D(local.basis.orthonormalized() * axis_basis, local.origin)


func consume_failed_insert_flash() -> bool:
	var v: bool = _failed_insert_flash
	_failed_insert_flash = false
	return v


func mark_complete() -> void:
	_day_plan.mark_done(&"l02")


func _sync_world_diorama() -> void:
	if _world_diorama == null:
		return
	_world_diorama.sync_full_state(_stage, _latch_open, _cartridge_angle_deg)


func _rearm_for_service(_seed: int) -> void:
	_stage = Stage.ISOLATE
	_latch_open = {1: false, 2: false}
	_cartridge_angle_deg = _START_ANGLE_DEG
	_failed_insert_flash = false
	_missing_part_flash = false
	_sync_world_diorama()


## Feasibility for DayPlan: a clean cartridge on a shelf or in the reserve.
func _clean_cartridge_available() -> bool:
	for c in get_tree().get_nodes_in_group(&"storage_cabinet"):
		if c.stock_count(_REQUIRED_ITEM_ID) > 0:
			return true
	for r in get_tree().get_nodes_in_group(&"supply_reserve"):
		if r.reserve_count(_REQUIRED_ITEM_ID) > 0:
			return true
	return false


func service_count() -> int:
	return _service_count


## Equipment condition (Round 31 Priority 8), from real state only:
## in_progress mid-procedure, service_due when today's work order needs
## it, restored once serviced today, nominal otherwise.
func condition() -> StringName:
	var dp: Node = get_node_or_null(day_plan_path)
	if _stage != Stage.ISOLATE and _stage != Stage.COMPLETE:
		return &"in_progress"
	if dp != null and dp.workday == dp.Workday.FILTER_SERVICE and not dp.is_task_done(&"l02"):
		return &"service_due"
	if dp != null and dp.is_task_done(&"l02"):
		return &"restored"
	return &"nominal"
