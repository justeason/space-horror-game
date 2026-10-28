extends Control
## Focused multi-stage electrical repair interface -- opened by
## scripts/interactables/electrical_panel.gd (never shown on its own),
## occupying ~94% of the screen per the focused-interaction convention
## (scripts/player/focused_interaction_state.gd). The equipment itself
## is a small isolated 3D scene (scripts/ui/electrical_repair_diorama.gd)
## rendered into a SubViewport and displayed via a SubViewportContainer,
## which automatically forwards mouse input (translated to the
## SubViewport's own local coordinates) to that scene -- the player
## clicks directly on wires/screws/the breaker instead of pressing
## numbered keys. A thin status/legend strip (stage name + a short
## contextual line) sits below the equipment; it is deliberately NOT a
## paragraph -- the diorama's own hover highlight and hint-pulse
## communicate what to do.
##
## This view still owns ONLY display + input routing/orchestration. All
## real state (isolation, which wires are disconnected/reconnected,
## screw progress, repair-stage/E05 completion) lives on the panel
## (scripts/interactables/electrical_panel.gd) -- every diorama click
## is translated into exactly one call to that script's existing
## methods, which already return a {"ok": bool, "message": String, ...}
## result (unchanged from the previous round; only the INPUT/PRESENTATION
## layer changed here, not the procedure's backend logic). The one bit
## of state this view DOES own is `_replace_phase`, a purely local,
## never-persisted "which half of the two-click Replace gesture are we
## on" flag -- see _enter_stage()'s handling of it below for why that is
## always safe to reset on reopen.

const ElectricalPanel = preload("res://scripts/interactables/electrical_panel.gd")

const WIRE_COLOR_ONLY := {
	&"supply": "RED",
	&"return": "BLUE",
	&"service": "YELLOW",
	&"backup": "ORANGE",
	&"ground": "GREEN",
}

@export var focused_state_path: NodePath
@export var sfx_path: NodePath

@onready var _focused_state: Node = get_node(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)

@onready var _title_label: Label = $Panel/VBox/TitleLabel
@onready var _stage_label: Label = $Panel/VBox/StageLabel
@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _diorama_container: SubViewportContainer = $Panel/VBox/DioramaContainer
@onready var _diorama_viewport: SubViewport = $Panel/VBox/DioramaContainer/DioramaViewport
@onready var _diorama: Node3D = $Panel/VBox/DioramaContainer/DioramaViewport/ElectricalRepairDiorama

var _panel: Node = null
var _mode_screws: bool = false
var _screws_removing: bool = true
var _last_stage: StringName = &""
var _replace_phase: StringName = &"damaged" # or &"awaiting_replacement"


func _ready() -> void:
	visible = false
	_diorama.wire_clicked.connect(_on_wire_clicked)
	_diorama.replacement_clicked.connect(_on_replacement_clicked)
	_diorama.breaker_clicked.connect(_on_breaker_clicked)
	_diorama.screw_clicked.connect(_on_screw_clicked)


## Called by electrical_panel.gd's _open_screws(). `removing` selects
## the direction (true while taking the cover off, false while putting
## it back on).
func open_screws(panel: Node, removing: bool) -> void:
	_panel = panel
	_mode_screws = true
	_screws_removing = removing
	if not _focused_state.begin(self):
		return
	visible = true
	_diorama.set_active(true)
	_title_label.text = "ACCESS COVER"
	_set_status("")
	_diorama.sync_full_state(_panel.fault_role(), [], [], false, false, _screw_progress_array(), _panel.screw_turns_needed())
	_refresh()


## Called by electrical_panel.gd's _open_procedure().
func open_procedure(panel: Node) -> void:
	_panel = panel
	_mode_screws = false
	_last_stage = &""
	if not _focused_state.begin(self):
		return
	visible = true
	_diorama.set_active(true)
	_title_label.text = "ELECTRICAL REPAIR — ENGINEERING POWER"
	_set_status("")
	_sync_diorama_full()
	_refresh()


## Duck-typed hook called by focused_interaction_state.gd on ANY exit
## (normal close, Escape, or a forced end()) -- just hides this view
## and drops the panel reference. Never resets the panel's own repair
## state; that is the panel's job and persists across sessions by
## design.
func on_focus_exit() -> void:
	visible = false
	_diorama.set_active(false)
	_panel = null


func cancel_requested() -> void:
	pass # Nothing extra to do -- on_focus_exit() (called right after by
	# focused_interaction_state.gd) already leaves everything exactly
	# where it was; every commit point is the panel's own explicit,
	# isolated call, never implied by merely having this view open.


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _panel == null:
		return
	if not (event is InputEventKey and event.pressed):
		return
	if _mode_screws:
		return
	if _panel.procedure_stage() == &"complete" and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		_close()
		get_viewport().set_input_as_handled()


func _screw_progress_array() -> Array:
	var arr: Array = []
	for i in 4:
		arr.append(_panel.screw_progress(i))
	return arr


func _sync_diorama_full() -> void:
	var stage: StringName = _panel.procedure_stage()
	_diorama.sync_full_state(
		_panel.fault_role(), _panel.disconnected_roles(), _panel.reconnected_roles(),
		stage == &"reconnect" or stage == &"restore" or stage == &"complete",
		_panel.is_isolated(), _screw_progress_array(), _panel.screw_turns_needed()
	)


# ============================================================
# Diorama signal handlers -- each is a thin call-through to the
# panel's existing methods, exactly mirroring the previous round's
# keyboard dispatch (_handle_procedure_input/_handle_screws_input) but
# keyed by the action the player actually clicked instead of a keycode.
# ============================================================

func _on_wire_clicked(role: StringName) -> void:
	var stage: StringName = _panel.procedure_stage()
	if stage == &"disconnect":
		var result: Dictionary = _panel.disconnect_wire(role)
		if result.get("ok", false):
			_diorama.animate_wire_disconnect(role)
		_apply_result(result)
	elif stage == &"replace" and role == _panel.fault_role() and _replace_phase == &"damaged":
		_diorama.begin_replace_sequence()
		_replace_phase = &"awaiting_replacement"
		if _sfx != null:
			_sfx.play_kind(&"click")
		_refresh()
	elif stage == &"reconnect":
		var result2: Dictionary = _panel.reconnect_wire(role)
		if result2.get("ok", false):
			_diorama.animate_wire_reconnect(role)
		_apply_result(result2)


## Round 11 B1 fix: the replacement wire's collider is the one and
## only visible click target for the fault role for the rest of the
## procedure once installed (the original wire node is hidden) -- so
## during RECONNECT, a click here must be treated exactly like
## _on_wire_clicked(_panel.fault_role()) would be for any other role,
## not silently ignored. See _update_allowed()'s matching fix above.
func _on_replacement_clicked() -> void:
	var stage: StringName = _panel.procedure_stage()
	if stage == &"replace" and _replace_phase == &"awaiting_replacement":
		var result: Dictionary = _panel.install_replacement_wire()
		if result.get("ok", false):
			_diorama.animate_install_replacement()
		_apply_result(result)
	elif stage == &"reconnect":
		var result2: Dictionary = _panel.reconnect_wire(_panel.fault_role())
		if result2.get("ok", false):
			_diorama.animate_wire_reconnect(_panel.fault_role())
		_apply_result(result2)


func _on_breaker_clicked() -> void:
	var stage: StringName = _panel.procedure_stage()
	if stage == &"isolate" or stage == &"disconnect":
		_panel.toggle_isolation()
		_diorama.animate_breaker(_panel.is_isolated())
		if _sfx != null:
			_sfx.play_kind(&"clunk")
		_refresh()
	elif stage == &"restore":
		var result: Dictionary = _panel.restore_power()
		if result.get("ok", false):
			_diorama.animate_breaker(false)
		_apply_result(result)


func _on_screw_clicked(index: int) -> void:
	var finished: bool = _panel.turn_screw(index, _screws_removing)
	_diorama.animate_screw(index, _panel.screw_progress(index), _panel.screw_turns_needed())
	if _sfx != null:
		_sfx.play_kind(&"ratchet")
	if finished:
		if _screws_removing:
			_panel.on_screws_removed()
		else:
			_panel.on_screws_reinstalled()
		if _sfx != null:
			_sfx.play_kind(&"success")
		_close()
	else:
		_refresh()


func _apply_result(result: Dictionary) -> void:
	_play_feedback(result)
	_set_status(String(result.get("message", "")))
	_refresh()


func _play_feedback(result: Dictionary) -> void:
	if _sfx == null:
		return
	if result.get("ok", false):
		_sfx.play_kind(&"success" if result.get("complete", false) else &"click")
	else:
		_sfx.play_kind(&"fail")


func _close() -> void:
	_focused_state.end()


func _set_status(text: String) -> void:
	_status_label.text = text


## Repaints the legend/allowed-set from the panel's current
## authoritative state -- called after every input, so this view never
## accumulates its own stale copy of anything. A stage CHANGE (not just
## a refresh within the same stage) also resets `_replace_phase` and
## updates the diorama's hint pulse.
func _refresh() -> void:
	if _mode_screws:
		_refresh_screws()
		return
	var stage: StringName = _panel.procedure_stage()
	if stage != _last_stage:
		_enter_stage(stage)
		_last_stage = stage

	if stage == &"isolate":
		_stage_label.text = "STAGE 1 / 5 — ISOLATE SUPPLY"
		_controls_label.text = "Click the breaker to isolate the circuit."
	elif stage == &"disconnect":
		_stage_label.text = "STAGE 2 / 5 — DISCONNECT WIRES"
		_controls_label.text = _hint_controls_text(_panel.current_hint_sequence(), "Click the correct wire to disconnect it.")
	elif stage == &"replace":
		_stage_label.text = "STAGE 3 / 5 — REPLACE DAMAGED SEGMENT"
		_controls_label.text = "Click the damaged wire to remove it." if _replace_phase == &"damaged" else "Click the replacement wire to install it."
	elif stage == &"reconnect":
		_stage_label.text = "STAGE 4 / 5 — RECONNECT WIRES (reverse order)"
		_controls_label.text = _hint_controls_text(_panel.current_hint_sequence(), "Recall the reverse order and reconnect each wire.")
	elif stage == &"restore":
		_stage_label.text = "STAGE 5 / 5 — RESTORE POWER"
		_controls_label.text = "Click the breaker to restore power."
	elif stage == &"complete":
		_stage_label.text = "REPAIR COMPLETE"
		_controls_label.text = "[Enter] Close"

	_update_allowed(stage)


func _enter_stage(stage: StringName) -> void:
	if stage == &"replace":
		_replace_phase = &"damaged"


func _update_allowed(stage: StringName) -> void:
	var allowed: Array = []
	var pulse: StringName = &""
	if stage == &"isolate":
		allowed = [&"breaker"]
	elif stage == &"disconnect":
		# Round 17 Priority 1: every one of the panel's 5 fixed wires is
		# clickable during DISCONNECT, not just this attempt's relevant
		# 3 -- a click on an irrelevant wire is accepted by the raycast
		# and rejected by disconnect_wire() with an explicit "not part
		# of the flagged circuit" message (see that function's own
		# comment), which reads as genuine inspection of a real system
		# rather than two colliders that silently do nothing.
		allowed = [&"breaker"]
		for role in ElectricalPanel.WIRE_ROLES:
			allowed.append(StringName("wire:%s" % role))
		var hint: Array = _panel.current_hint_sequence()
		if not hint.is_empty():
			pulse = StringName("wire:%s" % hint[0])
	elif stage == &"replace":
		allowed = [StringName("wire:%s" % _panel.fault_role())] if _replace_phase == &"damaged" else [&"replacement"]
	elif stage == &"reconnect":
		# Round 11 B1 fix: the fault role's real, VISIBLE collider is
		# the replacement wire (action &"replacement") once installed,
		# not the original (now-hidden) "wire:<fault>" collider -- this
		# stage is only ever reached after installation, so the fault
		# role here always means the replacement. See
		# _on_replacement_clicked() for the matching dispatch fix.
		# Round 16 Priority 3: which OTHER two roles stay on their own
		# original "wire:X" collider is now a function of this attempt's
		# fault role, not always "supply, return" -- see
		# ElectricalPanel.WIRE_ROLES/_panel.fault_role().
		allowed = []
		for role in ElectricalPanel.WIRE_ROLES:
			if role != _panel.fault_role():
				allowed.append(StringName("wire:%s" % role))
		allowed.append(&"replacement")
		var hint2: Array = _panel.current_hint_sequence()
		if not hint2.is_empty():
			pulse = &"replacement" if hint2[0] == _panel.fault_role() else StringName("wire:%s" % hint2[0])
	elif stage == &"restore":
		allowed = [&"breaker"]
	_diorama.set_allowed(allowed)
	_diorama.set_pulsing_hint(pulse)


func _hint_controls_text(hint: Array, fallback: String) -> String:
	if hint.is_empty():
		return fallback
	var names: Array = []
	for role in hint:
		names.append(WIRE_COLOR_ONLY.get(role, String(role)))
	return "Glowing wire shows the next step (%s)." % ", ".join(names)


func _refresh_screws() -> void:
	_stage_label.text = "REMOVING ACCESS SCREWS" if _screws_removing else "REINSTALLING ACCESS SCREWS"
	_controls_label.text = "Click each screw to turn it."
	_diorama.set_active(true)
	_diorama.set_allowed([&"screw:0", &"screw:1", &"screw:2", &"screw:3"])
