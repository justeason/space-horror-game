extends CSGBox3D
## Engineering's one electrical panel, covering E01 Inspect Electrical
## Panel / E02 Trace Electrical Circuit / E05 Replace Damaged Wire for
## Slice B's dependency chain. One prop, one small internal state
## machine -- NOT a generic task engine (GAME_DESIGN.md Section 47) --
## following this project's existing ControlPanel/ToggleSwitch
## precedent of "each physical object owns its own small, specific
## state" (Section 48).
##
## THREE INDEPENDENT STATE AXES:
##   - `_door_open`: purely physical, toggled by clicking the cabinet's
##     own big collider (this script's interact()). Never touches the
##     carried item, the repair stage, or any task flag -- a generic
##     click near the cabinet can only ever open/close it. On HARD
##     difficulty, opening/closing for the first time also requires the
##     small screw-removal/reinstall focused interaction (see
##     `_screws_*` below and `required_screw_count()`).
##   - `_repair_stage`: the outer CLOSED -> INSPECTED -> TRACED ->
##     REPAIRED progression, driven ONLY by terminal_interact() below,
##     called by the small separate `Terminal`/`IntactTerminal` child
##     colliders (scripts/interactables/terminal_connector.gd) -- NOT by
##     this cabinet's own interact(). This is what keeps "a generic
##     click near the panel" from ever touching repair progress: the
##     repair-advancing actions live on a small, separate, physically
##     distinct collider that is only reachable while the door is open.
##   - `_procedure`: the INNER multi-stage repair procedure (isolate ->
##     disconnect -> replace -> reconnect -> restore) that runs once the
##     player reaches TRACED and opens the focused ElectricalRepairView
##     (scripts/ui/electrical_repair_view.gd) from the damaged terminal.
##     `_repair_stage` only advances to REPAIRED (and only then is E05
##     marked done) once `_procedure` reaches COMPLETE -- opening the
##     view, or any partial progress within it, never marks E05 done by
##     itself (this milestone's explicit requirement).
##
## E01/E02 stay a single combined action per terminal click (Approved
## Decision A.7 -- no individually-clickable sub-elements within the
## inspect/trace steps themselves); only E05's install step opens the
## focused multi-stage procedure.
##
## WIRE DISCONNECT/RECONNECT ORDER (this milestone): three wire roles,
## &"supply"/&"return"/&"service", with a FIXED, state-derived required
## disconnect order -- supply first (de-energize the live feed), then
## return, then finally the wire actually being serviced/replaced
## (`_WIRE_ROLES` below) -- a real, if simple, safety-procedure
## justification rather than an arbitrary memorization puzzle. The
## reconnect order is always that sequence reversed. There is currently
## only one fault type in this game (fault_target is always
## &"engineering_power"), so this is deterministic for every attempt
## today; `_WIRE_ROLES`' own ordering is still a function of each wire's
## documented ROLE, not a hardcoded magic sequence with no connection to
## what the wires actually are, so a future second fault type with
## different wire roles would compute a different (still non-arbitrary)
## order without this script's logic changing.
##
## REALISM NOTE: requiring reverse-order reconnection is a deliberate
## gameplay abstraction for THIS fictional station's maintenance
## checklist, not a claim that real electrical work universally works
## this way -- see MILESTONE1_DESIGN.md's record of this round.

enum RepairStage { UNDIAGNOSED, INSPECTED, TRACED, REPAIRED }
enum ProcedureStage { NOT_STARTED, ISOLATE, DISCONNECT, REPLACE, RECONNECT, RESTORE, COMPLETE }

const GameSettings = preload("res://scripts/station/game_settings.gd")

## Round 10 Workstream E: difficulty is no longer this panel's own
## field -- it reads the ONE authoritative global "Game Difficulty"
## (GameSettings.get_difficulty()) like every other difficulty-
## sensitive system, per the player's explicit "difficulty must apply
## across the entire game, rather than belonging to an individual
## electrical repair task."
## EASY: no screws, explicit disconnect+reconnect hints, verbose
## diagnostic. NORMAL: no screws, hints only during disconnect (not
## reconnect -- the player must recall the order), balanced diagnostic.
## HARD: four-screw access cover, no hints at either wire stage, terse
## diagnostic (still solvable from the voltage comparison alone).
##
## MID-REPAIR STABILITY: this repair is a one-time, non-repeatable
## event, so the simplest coherent policy that satisfies "an active
## procedure's requirements stay fixed until completion" is to snapshot
## the global setting ONCE, the first time the player ever opens this
## door, into `_active_difficulty`, and use that snapshot (via
## `_current_difficulty()`) for every difficulty-sensitive check for
## the rest of this repair's lifetime. Before that first open, every
## check reads the live global value, so changing difficulty before
## starting this task takes effect immediately, exactly as it should
## for a task "not yet started".
var _active_difficulty: int = -1


func _current_difficulty() -> int:
	if _active_difficulty == -1:
		return GameSettings.get_difficulty()
	return _active_difficulty


func _lock_active_difficulty() -> void:
	if _active_difficulty == -1:
		_active_difficulty = GameSettings.get_difficulty()

## Canonical role order -- see class doc comment for the safety-
## procedure rationale (supply/live-feed first). This is the FIXED
## TOTAL set of wires/terminals this one physical panel always has
## (Round 17 Priority 1: "the total wire system should stay fixed and
## believable" -- the ship itself never changes). It is NOT itself the
## required disconnect order -- see _disconnect_order() below, which
## restricts this canonical order down to THIS attempt's own relevant
## subset (_relevant_roles) and reshuffles around whichever role is at
## fault.
const WIRE_ROLES: Array[StringName] = [&"supply", &"return", &"service", &"backup", &"ground"]
const WIRE_COLOR_NAMES := {
	&"supply": "Red",
	&"return": "Blue",
	&"service": "Yellow",
	&"backup": "Orange",
	&"ground": "Green",
}
## Matches electrical_repair_diorama.gd's own _HEALTHY_WIRE_COLOR --
## used only to recolor the ONE carried spare-wire prop (wire_component.gd)
## to whichever role this attempt's config puts at fault; the diorama
## itself derives its own wire colors independently.
const WIRE_COLORS := {
	&"supply": Color(0.62, 0.12, 0.1, 1),
	&"return": Color(0.14, 0.26, 0.6, 1),
	&"service": Color(0.68, 0.56, 0.08, 1),
	&"backup": Color(0.75, 0.4, 0.08, 1),
	&"ground": Color(0.15, 0.55, 0.22, 1),
}
const SCREW_COUNT: int = 4
const SCREW_TURNS_TO_REMOVE: int = 3

## Round 17 Priority 1 rework (building on Round 16 Priority 3): "the
## randomization should be logically grounded in the same physical
## panel, not look like the ship itself changed arbitrarily." The panel
## now always shows all 5 WIRE_ROLES, physically present every attempt
## -- what varies between configs is WHICH 3-wire SUBSET (`relevant`)
## is actually involved in a given repair, plus which member of that
## subset is at fault (`fault`, disconnected last/replaced/reconnected
## first). Wires outside `relevant` are never touched: clicking one
## during DISCONNECT is accepted by the raycast (so the player can
## genuinely inspect/try any of the 5, not have 2 silently inert
## colliders) but rejected by disconnect_wire() with an explicit
## "not part of the flagged circuit" message, distinct from a plain
## wrong-order rejection -- see that function's own comment. Every
## field besides `relevant`/`fault` is still derived (never hand-
## authored per config), so no inconsistent/impossible configuration
## can be authored: _disconnect_order() restricts WIRE_ROLES' own
## canonical order down to `relevant`, fault appended last. `label` is
## purely for the final report/debugging, never shown to the player.
const _REPAIR_CONFIGS: Array[Dictionary] = [
	{"label": "standard_service_fault", "relevant": [&"supply", &"return", &"service"], "fault": &"service"},
	{"label": "alternate_return_fault", "relevant": [&"supply", &"return", &"service"], "fault": &"return"},
	{"label": "backup_circuit_fault", "relevant": [&"return", &"backup", &"ground"], "fault": &"backup"},
]

@export var day_plan_path: NodePath
@export var carry_system_path: NodePath
@export var message_label_path: NodePath
@export var repair_view_path: NodePath
## Round 16 Priority 3: the one carryable spare wire in Storage --
## recolored (and its own pickup message's color name updated) to match
## WHICHEVER role this attempt's config says is at fault, so the carried
## part is never a color that contradicts the diagnostic/visual.
@export var wire_component_path: NodePath
@export var required_component_id: StringName = &"wire_control_16ga"
@export var message_duration: float = 3.0

## Local transform the installed wire is given once reparented under
## the correct Terminal node (see _attempt_install()) -- a plausible
## "plugged in, flush against the terminal" pose, not realistic cable
## physics.
@export var installed_wire_local_transform: Transform3D = Transform3D(Basis(), Vector3(0.0, 0.0, 0.05))

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _carry_system: Node = get_node(carry_system_path)
@onready var _message_label: Label = get_node_or_null(message_label_path)
@onready var _repair_view: Node = get_node_or_null(repair_view_path)
@onready var _wire_component: Node = get_node_or_null(wire_component_path)
@onready var _hatch_cover: Node3D = get_node("AccessHatchCover")
@onready var _terminal: Node3D = get_node("Terminal")
@onready var _intact_terminal: Node3D = get_node("IntactTerminal")
## Round 13 Workstream B: the SAME electrical_repair_diorama.tscn used
## by the focused close-up view (scripts/ui/electrical_repair_view.gd),
## instantiated a second time as a plain, non-interactive child of this
## cabinet (world_display_mode = true -- see that script's own class
## doc comment) sitting inside the middle compartment's real opening.
## This replaces the single flat "DamagedWireVisual" placeholder cylinder
## that previously was the ENTIRE in-world wire representation -- the
## player's own reported "the focused minigame doesn't match what I see
## in the cabinet" complaint. Kept the same wire routes/colors/terminal
## layout/breaker/damage-and-replacement appearance as the focused view
## by construction (literally the same scene), not a second hand-
## authored geometry that could drift out of sync -- see
## _sync_world_diorama() below for how its visual STATE (not its
## geometry) stays synchronized with every procedure action.
@onready var _world_diorama: Node3D = get_node_or_null("WorldDiorama")

var _repair_stage: RepairStage = RepairStage.UNDIAGNOSED
var _door_open: bool = false
var _message_timer: float = 0.0

# -- Screw-cover sub-state (HARD only; harmless/unused otherwise) --
var _screw_progress: Array = [0, 0, 0, 0] # 0..SCREW_TURNS_TO_REMOVE per screw
var _screws_done_for_open: bool = false
var _screws_reinstalled: bool = false

# -- Inner repair-procedure sub-state (only meaningful once TRACED) --
var _procedure: ProcedureStage = ProcedureStage.NOT_STARTED
var _isolated: bool = false
var _disconnected: Array = [] # Array[StringName], actual order so far
var _reconnected: Array = [] # Array[StringName], actual order so far
var _recorded_disconnect_order: Array = [] # frozen once DISCONNECT completes
## Set true the moment install_replacement_wire() actually commits --
## distinct from _repair_stage reaching REPAIRED (which only happens
## later, once restore_power() succeeds). Drives whether the damaged-
## wire stub visual shows, independent of how many times the door gets
## toggled in between.
var _wire_replaced: bool = false

## Round 16 Priority 3: which of _REPAIR_CONFIGS this attempt uses --
## -1 means "not yet chosen." Locked exactly once, the first time
## _trace() runs (the earliest point any player-visible text commits to
## a specific fault/color), and never regenerated afterward (Escape/
## reentry, wrong clicks, difficulty changes -- none of them touch it,
## same "preserve the chosen configuration for the whole attempt"
## contract _active_difficulty already uses).
var _config_index: int = -1
var _fault_role: StringName = &"service"
## Round 17 Priority 1: the 3-wire subset THIS attempt actually
## involves -- defaults to the original fixed set so a fresh instance
## that never receives an explicit config selection behaves exactly as
## every pre-Round-17 test already assumes.
var _relevant_roles: Array = [&"supply", &"return", &"service"]


func _ready() -> void:
	_refresh_interior_visuals()


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			_message_label.visible = false


## The cabinet's own big collider. Deliberately does ONLY one thing:
## toggle the door (subject to the HARD-only screw gate below). See the
## class doc comment above for why this is kept entirely separate from
## terminal_interact().
func interact() -> void:
	_lock_active_difficulty()
	if not _door_open:
		if _current_difficulty() == GameSettings.Difficulty.HARD and not _screws_done_for_open:
			_open_screws(true)
			return
		_door_open = true
		_refresh_interior_visuals()
		_show_message("Panel open.")
		return

	if _current_difficulty() == GameSettings.Difficulty.HARD and _repair_stage == RepairStage.REPAIRED and not _screws_reinstalled:
		_open_screws(false)
		return
	_door_open = false
	_refresh_interior_visuals()
	_show_message("Panel closed.")


func get_interact_prompt() -> String:
	if not _door_open:
		if _current_difficulty() == GameSettings.Difficulty.HARD and not _screws_done_for_open:
			return "Click: Remove Access Screws"
		return "Click: Open Panel"
	if _current_difficulty() == GameSettings.Difficulty.HARD and _repair_stage == RepairStage.REPAIRED and not _screws_reinstalled:
		return "Click: Reinstall Access Screws"
	return "Click: Close Panel"


func is_door_open() -> bool:
	return _door_open


func is_repaired() -> bool:
	return _repair_stage == RepairStage.REPAIRED


## Returns &"easy"/&"normal"/&"hard" rather than the Difficulty enum
## value -- same cross-script-safety reasoning as procedure_stage()
## above: callers (workstation_screen.gd, electrical_repair_view.gd)
## hold this panel only as a loosely-typed Node reference. Reflects
## THIS repair's current effective difficulty -- the live global
## setting before the door has ever been opened, the locked snapshot
## afterward (see _current_difficulty()).
func repair_difficulty() -> StringName:
	match _current_difficulty():
		GameSettings.Difficulty.EASY: return &"easy"
		GameSettings.Difficulty.HARD: return &"hard"
	return &"normal"


## Called by terminal_connector.gd (the small separate collider), not by
## this cabinet's own interact(). `terminal_id` distinguishes the one
## correct (damaged) connection point from the other, intentionally
## non-functional one -- see "wrong terminal preserves the wire" below.
func terminal_interact(terminal_id: StringName) -> void:
	if not _door_open:
		# The terminal's own collider is disabled while closed (see
		# _refresh_interior_visuals()), so this should be unreachable in
		# practice; kept as a defensive no-op rather than assuming the
		# collision gate alone is sufficient.
		return
	if terminal_id != &"damaged":
		_show_message("Terminal %s: connection nominal. The fault is elsewhere on this panel." % terminal_display_id(terminal_id))
		return
	match _repair_stage:
		RepairStage.UNDIAGNOSED:
			_inspect()
		RepairStage.INSPECTED:
			_trace()
		RepairStage.TRACED:
			_open_procedure()
		RepairStage.REPAIRED:
			_show_message("Panel nominal.")


func get_terminal_prompt(terminal_id: StringName) -> String:
	if not _door_open:
		return ""
	var display_id := terminal_display_id(terminal_id)
	if terminal_id != &"damaged":
		return "Click: Inspect Connection (Terminal %s)" % display_id
	match _repair_stage:
		RepairStage.UNDIAGNOSED:
			return "Click: Inspect Electrical Panel (Terminal %s)" % display_id
		RepairStage.INSPECTED:
			return "Click: Trace Circuit (Terminal %s)" % display_id
		RepairStage.TRACED:
			if _procedure > ProcedureStage.REPLACE or _wire_replaced:
				return "Click: Resume Repair Procedure (Terminal %s)" % display_id
			if _carry_system.is_carrying() and _carry_system.carried_item_id() == required_component_id:
				if _procedure != ProcedureStage.NOT_STARTED:
					return "Click: Resume Repair Procedure (Terminal %s)" % display_id
				return "Click: Begin Repair Procedure (Terminal %s)" % display_id
			return "Click: Attempt Repair (requires Control Wire)"
		RepairStage.REPAIRED:
			return "Click: Check Panel (Nominal)"
	return ""


## Physical terminal ID used by both the panel's own prompts/messages
## and the Control Room diagnostic (workstation_screen.gd) so the
## player can match a diagnostic reading to the physical connector it
## describes -- see this file's class doc comment and GAME_DESIGN.md
## Phase 4's "at least two relevant clues" requirement.
func terminal_display_id(terminal_id: StringName) -> String:
	return "T-2" if terminal_id == &"damaged" else "T-1"


func _inspect() -> void:
	_repair_stage = RepairStage.INSPECTED
	_day_plan.mark_done(&"e01")
	_show_message("Inspection: Terminal T-2 shows a damaged wire on the flagged circuit.")


func _trace() -> void:
	_repair_stage = RepairStage.TRACED
	_day_plan.mark_done(&"e02")
	_day_plan.set_required_component(required_component_id)
	_select_repair_config()
	_show_message("Circuit traced to Terminal T-2. Required part: Control Wire (16-gauge, %s)." % fault_color_name().to_lower())


## Round 16 Priority 3: picks (once, idempotently) which _REPAIR_CONFIGS
## entry this attempt uses, and propagates the choice to everything that
## needs to agree with it before the player can see any of it -- the
## carried spare's own color/message (recolored here, the moment the
## fault becomes known, regardless of whether it has been picked up
## yet) and `_fault_role` (read by fault_role()/fault_color_name()/
## _disconnect_order(), and pushed into the diorama via
## electrical_repair_view.gd's/_sync_world_diorama()'s own
## sync_full_state() calls -- never read directly by this panel's own
## wire-order logic, which only ever needs _disconnect_order()).
func _select_repair_config() -> void:
	if _config_index != -1:
		return
	_apply_config(randi() % _REPAIR_CONFIGS.size())


func _apply_config(index: int) -> void:
	_config_index = index
	var config: Dictionary = _REPAIR_CONFIGS[index]
	_relevant_roles = config.get("relevant", [&"supply", &"return", &"service"]).duplicate()
	_fault_role = config.get("fault", &"service")
	if _wire_component != null and _wire_component.has_method("set_fault_color"):
		_wire_component.set_fault_color(fault_color_name(), WIRE_COLORS.get(_fault_role, WIRE_COLORS[&"service"]))


## Test-only: forces a specific fault role instead of a random pick, for
## deterministic/seeded regression coverage (Priority 3's own explicit
## "use deterministic seeds for testing" requirement). Must be called
## BEFORE _trace() (i.e. before the first terminal_interact() past
## INSPECTED) -- _select_repair_config() is a no-op once a config is
## already locked, same as every other test-only override in this
## project (e.g. GameSettings.cycle_difficulty() in ordinary tests).
## Matches by fault role (each configured fault is currently unique
## across _REPAIR_CONFIGS, so this remains unambiguous).
func debug_force_fault_role(role: StringName) -> void:
	if _config_index != -1:
		return
	for i in _REPAIR_CONFIGS.size():
		if _REPAIR_CONFIGS[i].get("fault", &"") == role:
			_apply_config(i)
			return


## Test-only: forces a specific config by its "label" field, for the
## (now possible, Round 17) case where two configs could share a fault
## role in the future, or a test simply wants to name the exact
## scenario it means rather than reverse-engineer it from a fault role.
func debug_force_config_label(label: String) -> void:
	if _config_index != -1:
		return
	for i in _REPAIR_CONFIGS.size():
		if _REPAIR_CONFIGS[i].get("label", "") == label:
			_apply_config(i)
			return


func relevant_roles() -> Array:
	return _relevant_roles.duplicate()


func is_relevant(role: StringName) -> bool:
	return role in _relevant_roles


## Which role THIS attempt's locked configuration says is at fault --
## the one wire that gets disconnected last, replaced, and reconnected
## first. Defaults to &"service" (this panel's only fault role before
## this round) if read before a config has ever been selected.
func fault_role() -> StringName:
	return _fault_role


func fault_color_name() -> String:
	return WIRE_COLOR_NAMES.get(_fault_role, "Yellow")


## The required disconnect order for THIS attempt: the canonical
## WIRE_ROLES order restricted to THIS attempt's relevant subset
## (Round 17 Priority 1), minus the fault role, with the fault role
## appended last -- "live feed first [if relevant this attempt], the
## wire actually being serviced last," generalized from a fixed
## hardcoded sequence to a rule that produces a correct, non-arbitrary
## order for WHICHEVER subset/fault this attempt's config specifies
## (see the class doc comment's WIRE DISCONNECT/RECONNECT ORDER
## section). Reconnect order is always this reversed, same as before.
func _disconnect_order() -> Array:
	var order: Array = []
	for role in WIRE_ROLES:
		if role in _relevant_roles and role != _fault_role:
			order.append(role)
	order.append(_fault_role)
	return order


## Opens the focused multi-stage repair procedure (scripts/ui/
## electrical_repair_view.gd) instead of installing directly -- the
## actual fix for "E05 completes the moment the puzzle is opened": this
## only ever hands control to the view; the view calls back through
## is_isolated()/disconnect_wire()/install_replacement_wire()/
## reconnect_wire()/restore_power() below, and only restore_power()
## succeeding sets _repair_stage = REPAIRED.
func _open_procedure() -> void:
	# The carried-wire check only matters before REPLACE actually
	# commits (which consumes it) -- resuming a procedure already past
	# that point (RECONNECT/RESTORE) must never re-demand the now-
	# installed wire still be in the player's hands.
	if _procedure <= ProcedureStage.REPLACE and _wire_replaced == false:
		if not _carry_system.is_carrying() or _carry_system.carried_item_id() != required_component_id:
			if _carry_system.is_carrying():
				_show_message("That isn't the right part for this repair. (Needs: Control Wire, 16-gauge, %s.)" % fault_color_name().to_lower())
			else:
				_show_message("Nothing to install. You need the Control Wire (16-gauge, %s) from Storage." % fault_color_name().to_lower())
			return
	if _repair_view == null:
		return
	if _procedure == ProcedureStage.NOT_STARTED:
		_procedure = ProcedureStage.ISOLATE
	_repair_view.open_procedure(self)


func _open_screws(removing: bool) -> void:
	if _repair_view == null:
		# No view wired up (e.g. a bare test scene) -- fail safe to the
		# plain toggle rather than getting the cabinet stuck unopenable.
		if removing:
			_door_open = true
			_screws_done_for_open = true
		else:
			_door_open = false
			_screws_reinstalled = true
		_refresh_interior_visuals()
		return
	_repair_view.open_screws(self, removing)


# ============================================================
# Screw-cover sub-procedure (HARD only). `_screw_progress[i]` runs
# 0 (fully seated) .. SCREW_TURNS_TO_REMOVE (fully out) while removing,
# and the same range in reverse while reinstalling. Progress persists
# across a cancel/reopen of the focused view (Phase 6's "reopening
# preserves committed state" extended to this sub-procedure too) --
# nothing here resets it except actually finishing the direction in
# progress.
# ============================================================

func required_screw_count() -> int:
	return SCREW_COUNT if _current_difficulty() == GameSettings.Difficulty.HARD else 0


func screw_turns_needed() -> int:
	return SCREW_TURNS_TO_REMOVE


func screw_progress(index: int) -> int:
	if index < 0 or index >= _screw_progress.size():
		return 0
	return _screw_progress[index]


## `removing`: true while taking screws out (progress counts UP to
## SCREW_TURNS_TO_REMOVE), false while reinstalling (progress counts
## DOWN to 0 -- each call here still only ever moves one direction's
## worth per invocation, matching one authored "turn").  Returns true
## once the direction in progress fully completes this call.
func turn_screw(index: int, removing: bool) -> bool:
	if index < 0 or index >= _screw_progress.size():
		return false
	if removing:
		_screw_progress[index] = mini(_screw_progress[index] + 1, SCREW_TURNS_TO_REMOVE)
	else:
		_screw_progress[index] = maxi(_screw_progress[index] - 1, 0)
	_sync_world_diorama()
	return screws_fully_removed() if removing else screws_fully_reinstalled()


func screws_fully_removed() -> bool:
	for p in _screw_progress:
		if p < SCREW_TURNS_TO_REMOVE:
			return false
	return true


func screws_fully_reinstalled() -> bool:
	for p in _screw_progress:
		if p > 0:
			return false
	return true


## Called by electrical_repair_view.gd once all four screws are out.
func on_screws_removed() -> void:
	_screws_done_for_open = true
	_door_open = true
	_refresh_interior_visuals()
	_show_message("Access screws removed. Panel open.")


## Called by electrical_repair_view.gd once all four screws are back in.
func on_screws_reinstalled() -> void:
	_screws_reinstalled = true
	_door_open = false
	_refresh_interior_visuals()
	_show_message("Access screws reinstalled. Panel closed.")


# ============================================================
# Inner repair procedure: isolate -> disconnect -> replace ->
# reconnect -> restore. Every method here validates its own
# prerequisite and returns a small result Dictionary
# ({"ok": bool, "message": String}) the view renders directly --
# this script never touches UI nodes, same separation of concerns as
# every other object/view pair in this project (workstation_screen.gd
# reads day_plan.gd the same way).
# ============================================================

## Returns a plain StringName (&"not_started"/&"isolate"/&"disconnect"/
## &"replace"/&"reconnect"/&"restore"/&"complete") rather than the
## ProcedureStage enum value itself -- scripts/ui/electrical_repair_view.gd
## holds this panel only as a loosely-typed Node reference (duck-typed,
## same convention as every other object/view pair in this project), and
## a nested enum TYPE (as opposed to a plain method call or constant) is
## not reliably reachable through an untyped reference. A StringName
## sidesteps the question entirely and is just as unambiguous.
func procedure_stage() -> StringName:
	match _procedure:
		ProcedureStage.NOT_STARTED: return &"not_started"
		ProcedureStage.ISOLATE: return &"isolate"
		ProcedureStage.DISCONNECT: return &"disconnect"
		ProcedureStage.REPLACE: return &"replace"
		ProcedureStage.RECONNECT: return &"reconnect"
		ProcedureStage.RESTORE: return &"restore"
		ProcedureStage.COMPLETE: return &"complete"
	return &"not_started"


func is_isolated() -> bool:
	return _isolated


## The breaker/isolation control. Always safe to toggle -- there is no
## danger/fail state here on purpose (this milestone's explicit "do not
## introduce arbitrary danger or a punitive fail state"); it simply
## must be ON (isolated) before disconnect_wire() will accept anything.
func toggle_isolation() -> Dictionary:
	_isolated = not _isolated
	if _isolated and _procedure == ProcedureStage.ISOLATE:
		_procedure = ProcedureStage.DISCONNECT
	_sync_world_diorama()
	return {"ok": true, "isolated": _isolated}


func disconnected_roles() -> Array:
	return _disconnected.duplicate()


func reconnected_roles() -> Array:
	return _reconnected.duplicate()


## The hint sequence to display right now, or an empty array if hints
## should be hidden -- the one place difficulty/stage decide hint
## visibility, so the view never has to re-derive this policy itself.
func current_hint_sequence() -> Array:
	match _procedure:
		ProcedureStage.DISCONNECT:
			if _current_difficulty() == GameSettings.Difficulty.HARD:
				return []
			return _disconnect_order()
		ProcedureStage.RECONNECT:
			if _current_difficulty() == GameSettings.Difficulty.EASY:
				var reversed: Array = _recorded_disconnect_order.duplicate()
				reversed.reverse()
				return reversed
			return []
	return []


## Disconnects `role` if it is next in the required order AND the
## circuit is isolated. A wrong role (out of order) or an un-isolated
## attempt is rejected with a clear message and NO state change --
## already-disconnected wires stay disconnected (recoverable, not
## punitive), matching this milestone's explicit "preserves recoverable
## state" requirement.
func disconnect_wire(role: StringName) -> Dictionary:
	if _procedure != ProcedureStage.DISCONNECT:
		return {"ok": false, "message": "Not ready to disconnect wires yet."}
	if not _isolated:
		return {"ok": false, "message": "Isolate the circuit first (toggle the breaker)."}
	if role in _disconnected:
		return {"ok": false, "message": "%s wire already disconnected." % WIRE_COLOR_NAMES.get(role, role)}
	# Round 17 Priority 1: a wire outside this attempt's relevant subset
	# is a genuinely different rejection reason than "relevant, but
	# wrong order" -- the physical panel always shows all 5 wires, but
	# only _relevant_roles are actually part of THIS flagged circuit.
	# Distinguishing the message (rather than reusing the generic
	# "wrong order" text) keeps the panel readable as a real, inspectable
	# system: clicking an untouched wire tells you it checks out, not
	# that you clicked the right wire at the wrong time.
	if not (role in _relevant_roles):
		return {"ok": false, "message": "%s wire checks out fine -- not part of the flagged circuit this time." % WIRE_COLOR_NAMES.get(role, role)}
	var next_required: StringName = _next_required(_disconnect_order(), _disconnected)
	if role != next_required:
		return {"ok": false, "message": "Wrong order. Disconnect the %s wire next." % WIRE_COLOR_NAMES.get(next_required, next_required)}
	_disconnected.append(role)
	if _disconnected.size() == _disconnect_order().size():
		_recorded_disconnect_order = _disconnected.duplicate()
		_procedure = ProcedureStage.REPLACE
	_sync_world_diorama()
	return {"ok": true, "message": "%s wire disconnected." % WIRE_COLOR_NAMES.get(role, role), "complete": _procedure == ProcedureStage.REPLACE}


## The REPLACE commit point. Only consumes the carried wire -- and only
## now, not when the procedure view was merely opened -- once every
## prerequisite holds: all three wires disconnected, and the correct
## part still actually carried (re-checked here, not just assumed from
## _open_procedure()'s own earlier check, in case the player dropped it
## in between). Reversible/cancelable up to exactly this call: the view
## only calls this when the player explicitly confirms, never
## automatically on entering the REPLACE stage.
func install_replacement_wire() -> Dictionary:
	if _procedure != ProcedureStage.REPLACE:
		return {"ok": false, "message": "Disconnect all three wires first."}
	var item: Node3D = _carry_system.take_carried_item_if_matches(required_component_id)
	if item == null:
		if _carry_system.is_carrying():
			return {"ok": false, "message": "That isn't the right part for this repair. (Needs: Control Wire, 16-gauge, %s.)" % fault_color_name().to_lower()}
		return {"ok": false, "message": "You no longer have the Control Wire. Fetch another from Storage."}
	item.mark_installed(_terminal, installed_wire_local_transform)
	_wire_replaced = true
	_procedure = ProcedureStage.RECONNECT
	_sync_world_diorama()
	return {"ok": true, "message": "Damaged segment replaced. Reconnect the wires in reverse order."}


## Reconnects `role` if it is next in the reverse-of-disconnect order.
## Same "reject, don't reset" recovery contract as disconnect_wire().
func reconnect_wire(role: StringName) -> Dictionary:
	if _procedure != ProcedureStage.RECONNECT:
		return {"ok": false, "message": "Not ready to reconnect wires yet."}
	if role in _reconnected:
		return {"ok": false, "message": "%s wire already reconnected." % WIRE_COLOR_NAMES.get(role, role)}
	if not (role in _relevant_roles):
		return {"ok": false, "message": "%s wire was never part of the flagged circuit -- nothing to reconnect there." % WIRE_COLOR_NAMES.get(role, role)}
	var required_order: Array = _recorded_disconnect_order.duplicate()
	required_order.reverse()
	var next_required: StringName = _next_required(required_order, _reconnected)
	if role != next_required:
		return {"ok": false, "message": "Wrong order. Reconnect the %s wire next." % WIRE_COLOR_NAMES.get(next_required, next_required)}
	_reconnected.append(role)
	if _reconnected.size() == _disconnect_order().size():
		_procedure = ProcedureStage.RESTORE
	_sync_world_diorama()
	return {"ok": true, "message": "%s wire reconnected." % WIRE_COLOR_NAMES.get(role, role), "complete": _procedure == ProcedureStage.RESTORE}


## Final restore+verify. Requires isolation to be switched back off
## (power restored) AND all three connections actually back in place --
## real continuity/terminal-assignment validation against this script's
## own state, not a rubber stamp. Only this call marks E05 done, which
## is also the only moment _repair_stage becomes REPAIRED (so
## is_repaired()/the watch/map/workstation, which all already read that
## one flag, update automatically -- no separate "procedure done" flag
## to keep in sync).
func restore_power() -> Dictionary:
	if _procedure != ProcedureStage.RESTORE:
		return {"ok": false, "message": "Finish reconnecting the wires first."}
	if _reconnected.size() != _relevant_roles.size():
		return {"ok": false, "message": "Not all connections are restored -- continuity check failed."}
	if _isolated:
		_isolated = false
	_procedure = ProcedureStage.COMPLETE
	_repair_stage = RepairStage.REPAIRED
	_day_plan.mark_done(&"e05")
	_refresh_interior_visuals()
	_show_message("Power restored. Return to the Control Room workstation to verify the repair.")
	return {"ok": true, "message": "Power restored. Repair complete."}


func _next_required(order: Array, done: Array) -> StringName:
	for role in order:
		if not (role in done):
			return role
	return &""


## Single source of truth for what the interior (hatch cover vs.
## terminals/damaged-wire stub) should look like right now, called both
## on door toggle and after any repair-stage transition. The terminal
## colliders are only reachable (use_collision) while the door is open,
## which is the actual mechanism that stops a generic cabinet click from
## ever reaching the install action (see the class doc comment).
func _refresh_interior_visuals() -> void:
	_hatch_cover.visible = not _door_open
	# Round 14 Priority 1 fix: the wire/terminal assembly inside the
	# recessed service bay (ServiceBayCavity in main.tscn) must only be
	# visible once the cover is actually off -- previously it was never
	# hidden at all, so it rendered identically whether the door was
	# open or closed (confirmed via rendered screenshot), defeating the
	# whole "closed cover hides internals" read.
	if _world_diorama != null:
		_world_diorama.visible = _door_open
	_terminal.set_reachable(_door_open)
	_intact_terminal.set_reachable(_door_open)
	_sync_world_diorama()


## Round 13 Workstream B4: pushes this panel's full authoritative wire/
## breaker/screw state into the in-world diorama twin, using the EXACT
## same 7-argument shape electrical_repair_view.gd's own
## _sync_diorama_full() computes for the focused close-up instance --
## both views are driven from the one authoritative source
## (this script), never from each other, so they cannot drift apart.
## Safe to call at any time, including with no world diorama present
## (get_node_or_null already handles that at @onready time).
func _sync_world_diorama() -> void:
	if _world_diorama == null:
		return
	_world_diorama.sync_full_state(
		_fault_role, _disconnected, _reconnected, _wire_replaced,
		_isolated, _screw_progress.duplicate(), SCREW_TURNS_TO_REMOVE
	)


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true
	_message_timer = message_duration
