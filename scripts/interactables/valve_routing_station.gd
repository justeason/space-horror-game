extends StaticBody3D
## Life Support's coolant loop valve manifold -- implements L08 Coolant
## Loop Valve Routing. Round 15 Priority 2: now owns the authoritative
## valve state itself (mirrors electrical_panel.gd's own "the physical
## object owns its procedure state; views are presentation-only" split),
## rather than valve_routing_view.gd owning it directly as Round 14 did
## -- needed once a WORLD-visible diorama twin exists (scenes/ui/
## valve_routing_diorama.tscn, shared with the focused view exactly like
## WorldDiorama/electrical_repair_diorama.tscn), so both views can be
## synced from one source instead of drifting.
##
## Round 16 Priority 5: "at least two meaningfully different playable
## configurations... do not make every variation simply a different
## arrangement of identical button clicks." Both configs below reuse
## the SAME 3-valve/pipe geometry (no new wire-count-style expansion --
## see electrical_panel.gd's own Round 16 note on preferring a few
## validated configurations over new geometry per attempt) but give V3
## a genuinely different PHYSICAL MEANING and WIN CONDITION, not just a
## different starting valve state:
##   - STANDARD: V3 is a drain. Win = outlet live, drain sealed. The one
##     decision point is noticing V3 must be CLOSED, not opened.
##   - DUAL_OUTLET: V3 is a second, legitimate outlet (not a drain) --
##     both V2 and V3 must end up open. This alone would just be "open
##     everything," explicitly the anti-pattern the brief warns against,
##     so this config also requires a real SEQUENCE: V2 (the primary
##     outlet) must be opened before V3 (the secondary) while V1 is
##     live, or the manifold reads a pressure-loss warning -- "a
##     pressure-loss problem requiring careful valve sequencing," one of
##     the brief's own suggested variant types. Opening V3 first is
##     harmless and fully recoverable (close it, open V2, reopen V3 in
##     the right order), never a hard failure.

enum ConfigKind { STANDARD, DUAL_OUTLET }

const _CONFIGS: Array[Dictionary] = [
	{"label": "standard_single_outlet", "kind": ConfigKind.STANDARD},
	{"label": "dual_outlet_sequenced", "kind": ConfigKind.DUAL_OUTLET},
]

@export var day_plan_path: NodePath
@export var valve_view_path: NodePath

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _valve_view: Node = get_node_or_null(valve_view_path)
@onready var _world_diorama: Node = get_node_or_null("WorldDiorama")

## Deliberately wrong starting configuration (same "fixed puzzle
## instance, real work required" policy as every other minigame in this
## project): the drain/secondary starts OPEN, the real path starts SHUT.
const _START_OPEN := {1: false, 2: false, 3: true}

var _open := {1: false, 2: false, 3: true}
## Round 16 Priority 5: which valve each OPEN action committed, in
## order -- only meaningful for DUAL_OUTLET's sequencing requirement
## (mirrors electrical_panel.gd's own _disconnected/_recorded_disconnect_order
## pattern). Never reset except by a fresh attempt.
var _open_order: Array = []
var _config_index: int = -1
## True once an out-of-order V3-before-V2 open has happened in the
## current attempt and not yet been corrected -- read by the view to
## show a recoverable pressure-loss warning, consumed once shown.
var _pending_sequence_warning: bool = false
## DUAL_OUTLET only: true iff V3's MOST RECENT transition to open
## happened while V2 was ALREADY open -- the actual completion gate
## (see _is_solved()). Tracked from V3's own opening transition (not
## V2's) specifically so the natural recovery path -- close V3, confirm
## V2 is open, reopen V3 -- always re-establishes this correctly with
## nothing else needing to be re-toggled: V3 is necessarily the LAST
## valve touched in any correctly-sequenced attempt, successful or
## corrected.
var _v3_opened_with_v2_open: bool = false


func _ready() -> void:
	_sync_world_diorama()


func interact() -> void:
	if _valve_view == null:
		return
	_select_config()
	_valve_view.open_station(self)


func get_interact_prompt() -> String:
	if _day_plan.is_task_done(&"l08"):
		return "Click: Check Coolant Valves (Nominal)"
	return "Click: Route Coolant Valves"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"l08")


func is_valve_open(id: int) -> bool:
	return _open.get(id, false)


func open_state() -> Dictionary:
	return _open.duplicate()


## Idempotent, locked for the whole attempt once chosen -- same
## "generate/choose once, never regenerate on reentry or wrong actions"
## contract electrical_panel.gd's own _select_repair_config() uses.
func _select_config() -> void:
	if _config_index != -1:
		return
	_config_index = randi() % _CONFIGS.size()


## Test-only deterministic override (Priority 5's own "use deterministic
## seeds for testing" requirement, same pattern as
## electrical_panel.gd's debug_force_fault_role()). Must be called
## before interact() ever opens the station for the first time.
func debug_force_config(kind: int) -> void:
	if _config_index != -1:
		return
	for i in _CONFIGS.size():
		if _CONFIGS[i].get("kind", -1) == kind:
			_config_index = i
			return


func config_kind() -> int:
	if _config_index == -1:
		return ConfigKind.STANDARD
	return _CONFIGS[_config_index].get("kind", ConfigKind.STANDARD)


func is_dual_outlet() -> bool:
	return config_kind() == ConfigKind.DUAL_OUTLET


## Short, physical label for V3's terminal -- read by the view to keep
## its own status/schematic text and the diorama's 3D label agreed with
## whichever config is active.
func drain_label_text() -> String:
	return "OUTLET B" if is_dual_outlet() else "DRAIN"


## Flow reaches a valve/segment only if every valve upstream of it (per
## the fixed topology: INLET->V1->JUNCTION, JUNCTION->V2->OUTLET,
## JUNCTION->V3->DRAIN/OUTLET B) is open -- a tiny, fully fixed 3-node
## graph by design, not a generic solver (see valve_routing_view.gd's
## own class doc comment for why a fixed single puzzle instance was
## chosen).
func flow_state() -> Dictionary:
	var v1_live: bool = _open[1]
	return {
		"v1_live": v1_live,
		"outlet_live": v1_live and _open[2],
		"drain_live": v1_live and _open[3],
	}


## Whether branch 3 should currently render/read as a LEAK (STANDARD
## config) or a legitimate second outlet (DUAL_OUTLET) -- the one thing
## the view/diorama need from the config besides the label text.
func branch3_is_leak() -> bool:
	return not is_dual_outlet()


## Toggles valve `id` and resolves the new flow state. Always succeeds
## (there is no "wrong click" to reject here -- every valve is always
## reachable and reversible, per the brief's own "incorrect adjustments
## should be reversible" requirement); returns the new flow/complete
## state so the view can react without re-deriving it.
func toggle_valve(id: int) -> Dictionary:
	if is_complete():
		return {"ok": false}
	var opening: bool = not _open[id]
	_open[id] = opening
	if opening:
		_open_order.append(id)
		if is_dual_outlet() and id == 3:
			_v3_opened_with_v2_open = _open[2]
			# The out-of-order case -- opening V3 while V1 is live but V2
			# is NOT yet open -- is harmless and fully recoverable (not
			# rejected, not reset), but flagged so the view can show the
			# pressure-loss warning this config's whole point is to teach.
			if _open[1] and not _open[2]:
				_pending_sequence_warning = true
	_sync_world_diorama()
	var flow: Dictionary = flow_state()
	var completed: bool = _is_solved(flow)
	if completed:
		mark_complete()
	return {"ok": true, "open": _open[id], "flow": flow, "complete": completed}


func _is_solved(flow: Dictionary) -> bool:
	if is_dual_outlet():
		# Both branches live is NECESSARY but not sufficient -- V3 must
		# have been the one most recently opened, and only after V2 was
		# already open (the real sequencing requirement, not just a
		# final-state check that "open everything" would trivially
		# satisfy).
		return flow["outlet_live"] and flow["drain_live"] and _v3_opened_with_v2_open
	return flow["outlet_live"] and not flow["drain_live"]


## Consumed (not polled) by the view, same "read once and clear"
## contract filter_housing_station.gd's own consume_failed_insert_flash()
## uses, so a single out-of-order action surfaces exactly one warning.
func consume_sequence_warning() -> bool:
	var v: bool = _pending_sequence_warning
	_pending_sequence_warning = false
	return v


func mark_complete() -> void:
	_day_plan.mark_done(&"l08")


func reset_attempt() -> void:
	_open = _START_OPEN.duplicate()
	_open_order.clear()
	_pending_sequence_warning = false
	_v3_opened_with_v2_open = false
	_sync_world_diorama()


func _sync_world_diorama() -> void:
	if _world_diorama == null:
		return
	_world_diorama.sync_full_state(_open, branch3_is_leak())
	if _world_diorama.has_method("set_drain_label_text"):
		_world_diorama.set_drain_label_text(drain_label_text())
