extends CanvasLayer
## Round 42 Priorities 2-4: the DEVELOPER-ONLY testing interface.
##
## ACCESS: built ONLY in debug / development builds -- story_events.gd
## creates it when OS.is_debug_build() is true; an exported RELEASE build
## never instantiates it, registers no input for it and the StoryEvents
## dev_* API refuses there too (the build configuration is the real
## restriction). F8 opens it (F3 diagnostics untouched). The first opening
## of a session asks for the unlock code ("justeason" -- a convenience
## against accidental opening, NOT security); after that the panel stays
## unlocked for the session.
##
## Tabs:
##   STORY   -- narrative phase, milestones, seen / pending events, a
##              transient phase OVERRIDE (never saved);
##   EVENTS  -- every REGISTERED event (unavailable placeholders are shown
##              as unavailable, never as functional): id, name, phase,
##              eligibility, state, cooldown; TRIGGER (preview, uncounted),
##              TRIGGER+COUNT, ARM (when available), CANCEL, RESET, SEEN
##              toggle, ENABLE toggle, normal / abnormal variant;
##   STATION -- controlled faults through each equipment's OWN fault API
##              (order_rearm / trip / surge ...); every touched device's
##              state is snapshotted first and RESTORE puts it back;
##   PLAYER  -- room, position, EVA zone, selected / rendering cameras, story
##              flags, last log / assistant lines; safe teleports (inside
##              the pressurised station only, never while suited);
##   SESSION -- restore everything (story snapshot, overrides, equipment).
## Nothing here writes a save; developer previews never count as plays.

const UNLOCK_CODE := "justeason"
static var unlocked: bool = false

const TELEPORTS := [
	["Control Room", Vector3(0.0, 1.6, 0.8)],
	["Junction", Vector3(0.0, 1.6, 4.5)],
	["Communications", Vector3(2.0, 1.6, 7.1)],
	["Engineering", Vector3(-4.2, 1.6, 5.0)],
	["Life Support", Vector3(-2.9, 1.6, 10.8)],
	["Storage", Vector3(-6.5, 1.6, 8.0)],
	["Quarters", Vector3(3.7, 1.6, 0.5)],
	["Airlock tunnel", Vector3(-4.8, 1.6, 0.9)],
]

var main: Node
var se: Node
var is_open: bool = false
var _root: PanelContainer
var _lock_box: VBoxContainer
var _code: LineEdit
var _lock_msg: Label
var _tabs: TabContainer
var _story_lbl: Label
var _events_box: VBoxContainer
var _player_lbl: Label
var _station_lbl: Label
var _session_lbl: Label
var _deck_b_lbl: Label
var _task_pick: OptionButton
var _variant: String = "normal"
var _eq_snapshots: Dictionary = {}     # node path -> state_dict
var _t: float = 0.0
var _mouse_before: int = Input.MOUSE_MODE_CAPTURED
## Round 46: input ownership. While open the panel OWNS the mouse: a
## full-screen, invisible blocker under it swallows clicks so nothing
## behind (seated workstation, laptop, world interactions) reacts, and the
## workstation's own mouse projection steps aside (owns_mouse()). On close
## the previous look / mouse state is restored exactly -- seated stays
## seated, a focused laptop stays focused, walking gets mouse-look back.
var _look_before: bool = true
var _blocker: Control
var last_action: String = ""


func setup(p_main: Node, p_se: Node) -> void:
	main = p_main
	se = p_se


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"mouse_overlay")
	_blocker = Control.new()
	_blocker.name = "DevPanelBlocker"
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	add_child(_blocker)
	_build()
	_root.visible = false


## Round 46: true while the panel owns mouse input (see _blocker).
func owns_mouse() -> bool:
	return is_open


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# Esc closes the panel only -- it must not also stand the technician
		# up from the workstation or step back from the laptop.
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if not OS.is_debug_build():
		return
	is_open = true
	_root.visible = true
	_blocker.visible = true
	_lock_box.visible = not unlocked
	_tabs.visible = unlocked
	_mouse_before = Input.mouse_mode
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_player_input(false)
	if not unlocked and is_inside_tree():
		_code.grab_focus()
	refresh()


func close() -> void:
	is_open = false
	_root.visible = false
	_blocker.visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_before
	_set_player_input(true)


func _set_player_input(on: bool) -> void:
	var lc: Node = main.get_node_or_null("Player/LookPivot") if main != null else null
	if lc != null and "input_enabled" in lc:
		if not on:
			_look_before = bool(lc.input_enabled)
			lc.input_enabled = false
			return
		var ws: Node = main.get_node_or_null("WorkstationState")
		# Only hand looking back if nothing else (the seated workstation) owns it.
		if ws != null and ws.is_in_use():
			return
		lc.input_enabled = _look_before


func try_unlock(code: String) -> bool:
	if not OS.is_debug_build():
		return false
	if code.strip_edges() == UNLOCK_CODE:
		unlocked = true
		_lock_box.visible = false
		_tabs.visible = is_open
		refresh()
		return true
	_lock_msg.text = "Wrong code."
	return false


# --------------------------------------------------------------- build
func _build() -> void:
	_root = PanelContainer.new()
	_root.name = "DevPanel"
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -560
	_root.offset_right = -8
	_root.offset_top = 8
	_root.offset_bottom = -8
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.05, 0.94)
	sb.border_color = Color(0.95, 0.6, 0.15)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	_root.add_theme_stylebox_override("panel", sb)
	add_child(_root)
	var v := VBoxContainer.new()
	_root.add_child(v)
	var title := Label.new()
	title.text = "DEVELOPER — STORY / EVENT TEST PANEL  (debug build · F8)"
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	title.add_theme_font_size_override("font_size", 14)
	v.add_child(title)
	# Unlock prompt.
	_lock_box = VBoxContainer.new()
	v.add_child(_lock_box)
	var l := Label.new()
	l.text = "Developer code:"
	_lock_box.add_child(l)
	_code = LineEdit.new()
	_code.secret = true
	_code.placeholder_text = "code"
	_code.text_submitted.connect(func(t): try_unlock(t))
	_lock_box.add_child(_code)
	var ub := Button.new()
	ub.text = "Unlock"
	ub.pressed.connect(func(): try_unlock(_code.text))
	_lock_box.add_child(ub)
	_lock_msg = Label.new()
	_lock_box.add_child(_lock_msg)
	# Tabs.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_story_lbl = _tab_label("STORY", _build_story_controls)
	var ev_scroll := ScrollContainer.new()
	ev_scroll.name = "EVENTS"
	ev_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(ev_scroll)
	_events_box = VBoxContainer.new()
	_events_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ev_scroll.add_child(_events_box)
	_station_lbl = _tab_label("STATION", _build_station_controls)
	_player_lbl = _tab_label("PLAYER", _build_player_controls)
	_session_lbl = _tab_label("SESSION", _build_session_controls)
	_deck_b_lbl = _tab_label("DECK B", _build_deck_b_controls)


func _tab_label(name: String, controls: Callable) -> Label:
	var sc := ScrollContainer.new()
	sc.name = name
	_tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(520, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	box.add_child(lbl)
	controls.call(box)
	return lbl


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(func():
		cb.call()
		refresh.call_deferred())
	parent.add_child(b)
	return b


func _calendar_anomaly(kind: StringName) -> void:
	var cal: Node = get_tree().current_scene.find_child("WallCalendar", true, false) if get_tree().current_scene != null else null
	if cal != null:
		cal.set_anomaly(kind, true)
		last_action = "calendar preview: %s" % (String(kind) if kind != &"" else "cleared")


func _row(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	return h


func _build_story_controls(box: VBoxContainer) -> void:
	var h := _row(box)
	var l := Label.new()
	l.text = "Phase override:"
	h.add_child(l)
	for p in [0, 1, 2, 3]:
		_button(h, "none" if p == 0 else "P%d" % p, func(): se.dev_set_phase_override(p); last_action = "phase override %d" % p)
	var h2 := _row(box)
	_button(h2, "Variant: normal", func(): _variant = "normal")
	_button(h2, "Variant: abnormal", func(): _variant = "abnormal")
	# Round 45: WINDOW ENCOUNTER test controls (transient; dev_reset restores).
	var h3 := _row(box)
	var wl := Label.new()
	wl.text = "Window:"
	h3.add_child(wl)
	for spec in [["Prepare", "dev_prepare"], ["Cue", "dev_cue"], ["Go to spot", "dev_goto"], ["Idle pose", "dev_spawn"], ["Gaze react", "dev_react"], ["Replay", "dev_replay"], ["Slow replay", "dev_replay_slow"], ["Guide", "dev_guide"], ["Reset", "dev_reset"]]:
		var m: String = spec[1]
		_button(h3, spec[0], func(): se._dev_touch(); se.window.call(m); last_action = "window " + m)
	var h4 := _row(box)
	# Round 48: compare the window-figure animation variants from the real
	# spot (developer only; "B" ships). Replays at normal speed.
	var vl := Label.new()
	vl.text = "Figure variant:"
	h4.add_child(vl)
	for v in ["A", "B", "C"]:
		var vv: String = v
		_button(h4, vv + (" (ship)" if vv == "B" else ""), func(): se._dev_touch(); se.window.figure.variant = vv; se.window.dev_replay(); last_action = "window figure variant " + vv)
	# Round 48: the wall calendar's future-anomaly hook (presentation only;
	# never in Phase 1 play; the real day is untouched).
	var hcal := _row(box)
	_button(hcal, "Calendar: tomorrow marked", func(): _calendar_anomaly(&"tomorrow_marked"))
	_button(hcal, "mark missing", func(): _calendar_anomaly(&"mark_missing"))
	_button(hcal, "Clear", func(): _calendar_anomaly(&""))
	# Round 47: the window / camera contradiction variants (previews).
	var hm := _row(box)
	for mv in [["Mismatch: shadow", &"mismatch_shadow"], ["day/night", &"mismatch_daynight"], ["EVA worker", &"mismatch_eva"]]:
		var mid: StringName = mv[1]
		_button(hm, mv[0], func(): se.dev_trigger(mid); last_action = "preview " + String(mid))
	_button(hm, "Clear", func(): se.dev_cancel(); last_action = "mismatch cleared")
	# Round 47: the hand at the observation port (separate event).
	var hh := _row(box)
	_button(hh, "Hand: prepare", func(): se.dev_prepare_hand(); last_action = "hand armed (stand in the Control Room, face away)")
	_button(hh, "Trigger", func(): se.dev_trigger(&"window_hand"); last_action = "hand: knock")
	_button(hh, "Replay", func(): se.dev_cancel(); se.dev_trigger(&"window_hand"); last_action = "hand: replay")
	_button(hh, "Cancel", func(): se.dev_cancel(); last_action = "hand cancelled")
	_button(hh, "Reset", func(): se.dev_reset(&"window_hand"); se._pending_investigation.erase("window_hand"); last_action = "hand reset")
	_button(hh, "Test investigation", func(): se._dev_touch(); se._investigated("window_hand"); last_action = "hand: glass checked")
	# Round 46: the task-linked wrong reading (prepare a REAL setup, then
	# trigger; status shows true vs displayed).
	var hc := _row(box)
	_button(hc, "Cal: prepare done", func(): se.dev_prepare_cal("normal"); last_action = "calibration done (real)")
	_button(hc, "Cal: prepare pending", func(): se.dev_prepare_cal("abnormal"); last_action = "calibration pending (real)")
	_button(hc, "Trigger denial", func(): se.dev_trigger(&"wrong_reading", "normal"); last_action = "workstation denies calibration")
	_button(hc, "Trigger false AI", func(): se.dev_trigger(&"wrong_reading", "abnormal"); last_action = "assistant false announcement")
	_button(hc, "Reset", func(): se.dev_cancel(); last_action = "wrong reading reset")
	# Round 46: the peripheral figure.
	var hpf := _row(box)
	_button(hpf, "Peripheral: next fast turn", func(): se._dev_touch(); se.peripheral.force_next = true; last_action = "peripheral armed (turn fast)")
	_button(hpf, "Show left", func(): se._dev_touch(); se.peripheral.dev_preview = true; se.peripheral.try_show(-1.0); last_action = "peripheral left")
	_button(hpf, "Show right", func(): se._dev_touch(); se.peripheral.dev_preview = true; se.peripheral.try_show(1.0); last_action = "peripheral right")
	_button(hpf, "Reset", func(): se.peripheral.dev_reset(); last_action = "peripheral reset")
	# Round 46: basil care states + the Phase 3 return (preview / reset).
	var hb := HBoxContainer.new()
	box.add_child(hb)
	for bs in [["Basil healthy", 0], ["dry", 1], ["wilting", 2], ["dead", 3]]:
		var bc: int = bs[1]
		_button(hb, bs[0], func(): main.get_node("Equipment/QuartersLife").dev_basil_state(bc); last_action = "basil state %d" % bc)
	_button(hb, "Return preview", func(): se.dev_trigger(&"basil_return"); last_action = "basil return preview")
	_button(hb, "Reset return", func(): main.get_node("Equipment/QuartersLife").basil_return_reset(); last_action = "basil return reset")
	_button(h4, "Test investigation (tunnel check)", func(): se._dev_touch(); se._investigated("window_figure"); last_action = "window check")
	_button(h4, "Handover: release all", func(): main.get_node("DayPlan").day_number = maxi(main.get_node("DayPlan").day_number, 10); last_action = "day >= 10 (all notes)")
	for cl in [0, 1, 2, 3, -1]:
		_button(h4, "Clr %s" % ("auto" if cl < 0 else str(cl)), func(): main.get_node("DayPlan/Clearance").dev_set(cl); last_action = "clearance %d" % cl)


func _build_station_controls(box: VBoxContainer) -> void:
	var specs := [
		["Trip breaker B-01", func(): _eq("Equipment/BreakerPanel", func(n): n.trip(0, "DEV TEST"))],
		["Trip breaker B-04 (comms)", func(): _eq("Equipment/BreakerPanel", func(n): n.trip(3, "DEV TEST"))],
		["Power overload (surge)", func(): _eq("Equipment/PowerDistribution", func(n): n.order_rearm(4242))],
		["Airflow: dirty vent", func(): _eq("Equipment/VentGrille", func(n): n.order_rearm(77))],
		["Oxygen warning (O2 19.4 kPa)", func(): _eq("EnvironmentModel", func(n): n.o2_kpa = 19.4)],
		["Airlock seal fault", func(): _eq("Equipment/HatchSeal", func(n): n.order_rearm(31))],
		["Solar: hinge restricts a wing", func(): _eq("Equipment/SolarHinge", func(n): n.order_rearm(5))],
		["Comms: antenna feed loose", func(): _eq("Equipment/AntennaMast", func(n): n.order_rearm(11))],
		["Surveillance: INT-02 offline", func(): _net_offline("INT-02", true)],
		["Surveillance: all online", func(): _net_offline("", false)],
	]
	for s in specs:
		_button(box, s[0], s[1])
	_button(box, "RESTORE all station changes", restore_station)


func _build_player_controls(box: VBoxContainer) -> void:
	var l := Label.new()
	l.text = "Safe teleport (inside the pressurised station only):"
	box.add_child(l)
	var h: HBoxContainer = null
	for i in TELEPORTS.size():
		if i % 4 == 0:
			h = _row(box)
		var t: Array = TELEPORTS[i]
		_button(h, t[0], func(): teleport(i))


func _build_session_controls(box: VBoxContainer) -> void:
	_button(box, "Cancel active event", func(): se.dev_cancel(); last_action = "cancel")
	_button(box, "Return to normal simulation (restore story + station)", restore_all)


# ------------------------------------------------------------- actions
func _node(path: String) -> Node:
	if main == null:
		return null
	var n: Node = main.get_node_or_null(path)
	if n == null and path.begins_with("Exterior/"):
		n = main.find_child(path.get_slice("/", 1), true, false)
	return n


## Applies a change through the equipment's own API, snapshotting the
## device the first time so RESTORE can put it back.
func _eq(path: String, change: Callable) -> bool:
	var n: Node = _node(path)
	if n == null:
		last_action = "missing %s" % path
		return false
	if not _eq_snapshots.has(path):
		if n.has_method("state_dict"):
			_eq_snapshots[path] = n.state_dict()
		elif "o2_kpa" in n:
			_eq_snapshots[path] = {"_o2": n.o2_kpa, "_p": n.pressure_kpa}
	change.call(n)
	last_action = "station: %s" % path
	return true


func _net_offline(id: String, off: bool) -> void:
	var net: Node = _node("CameraNetwork")
	if net != null and net.has_method("dev_set_offline"):
		net.dev_set_offline(id, off)
		last_action = "surveillance %s %s" % [id if id != "" else "all", "offline" if off else "online"]


func restore_station() -> void:
	for path in _eq_snapshots:
		var n: Node = _node(path)
		var snap: Dictionary = _eq_snapshots[path]
		if n == null:
			continue
		if snap.has("_o2"):
			n.o2_kpa = snap["_o2"]
			n.pressure_kpa = snap["_p"]
		elif n.has_method("load_dict"):
			n.load_dict(snap)
	_eq_snapshots = {}
	_net_offline("", false)
	last_action = "station restored"


func restore_all() -> void:
	se.dev_restore()
	restore_station()
	last_action = "normal simulation restored"


func event_action(id: StringName, what: String) -> bool:
	var ok := true
	match what:
		"trigger": ok = se.dev_trigger(id, _variant, false)
		"count": ok = se.dev_trigger(id, _variant, true)
		"arm": ok = se.debug_arm(id)
		"cancel": se.dev_cancel()
		"reset": se.dev_reset(id)
		"seen": se.dev_set_seen(id, not bool(se.state[id]["seen"]))
		"enable": se.dev_set_enabled(id, not se.is_enabled(id))
	last_action = "%s %s -> %s" % [what, id, "ok" if ok else "refused"]
	return ok


## Debug only, inside the station, never while suited / in the airlock
## cycle / outside: EVA safety is not bypassable from here.
func teleport(i: int) -> bool:
	var eva: Node = main.get_tree().get_first_node_in_group(&"eva_system")
	if eva != null and (eva.suited or eva.is_eva_active()):
		last_action = "teleport refused: EVA / suit in use"
		return false
	var ws: Node = main.get_node_or_null("WorkstationState")
	if ws != null and ws.is_in_use():
		last_action = "teleport refused: seated"
		return false
	var fb: Node = main.get_node_or_null("FreeMoveBody")
	if fb == null or not fb.has_method("sync_to_eye_position"):
		return false
	fb.sync_to_eye_position(TELEPORTS[i][1])
	if "velocity" in fb:
		fb.velocity = Vector3.ZERO
	last_action = "teleport %s" % TELEPORTS[i][0]
	return true


# --------------------------------------------------------------- views
func _process(delta: float) -> void:
	if not is_open or not unlocked:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh(false)


func refresh(rebuild_events: bool = true) -> void:
	if se == null or not unlocked:
		return
	_story_lbl.text = story_text()
	_player_lbl.text = player_text()
	_station_lbl.text = "Last action: %s\nChanged devices (restorable): %s" % [last_action, ", ".join(_eq_snapshots.keys()) if not _eq_snapshots.is_empty() else "none"]
	if _deck_b_lbl != null:
		_deck_b_lbl.text = deck_b_text()
	_session_lbl.text = "Active event: %s %s\nStory snapshot held: %s\nPhase override: %s\nLast action: %s\nPreviews never count as plays; overrides are never saved." % [String(se.active) if se.active != &"" else "none", se.active_variant, "yes" if se.dev_has_snapshot() else "no", str(se.dev_phase_override) if se.dev_phase_override > 0 else "none", last_action]
	if rebuild_events:
		_rebuild_events()
	else:
		for c in _events_box.get_children():
			if c.has_meta("event_id"):
				(c.get_child(0) as Label).text = event_line(StringName(c.get_meta("event_id")))


func story_text() -> String:
	var fp: Dictionary = se.familiar_progress()
	var lines: Array = [
		"Narrative phase: %d%s   (story %d)" % [se.phase(), "  [OVERRIDE]" if se.dev_phase_override > 0 else "", se.story_phase],
		"Current milestone: %s" % se.current_milestone(),
		"Completed: %s" % (", ".join(se.milestones) if not se.milestones.is_empty() else "none"),
		"Familiarity: %d duty kinds (need %d), feeds used on %d days (need 2)" % [fp["duties"], se.FAMILIAR_DUTIES, fp["feed_days"]],
		"Investigations: %s" % ", ".join(se.investigations),
		"Seen events: %s" % ", ".join(se.state.keys().filter(func(k): return bool(se.state[k]["seen"])).map(func(k): return String(k))),
		"Armed today (day %d): %s" % [se.day(), String(se.armed_id()) if se.armed_id() != &"" else "nothing"],
		"Variant for triggers: %s" % _variant,
	]
	# Round 43: the INVESTIGATION state per event + gathered evidence.
	if se.has_method("investigation_state"):
		var inv: Array = []
		for id in se.EVENTS:
			var st: String = se.investigation_state(String(id))
			if st != "none":
				inv.append("%s=%s" % [id, st])
		lines.append("Investigation state: %s" % (", ".join(inv) if not inv.is_empty() else "nothing observed yet"))
		if se.get("window") != null:
			lines.append("Window encounter: stage %s · witnessed day %d · guide days %s · ready %s · observable %s" % [se.window.stage, se.window.witnessed_day, str(se.window.guide_days), se.window.is_ready_now(), se.window.observable()])
			lines.append("Window figure: " + se.window.dev_status())
			var odn: Node = main.get_tree().get_first_node_in_group(&"observation_discrepancy")
			lines.append("Window/camera contradiction: mode '%s' · EXT-03 night %s · shadow %s · eva %s" % [odn.active_mode if odn != null else "?", odn.ext03_night() if odn != null else false, se.eligibility(&"mismatch_shadow"), se.eligibility(&"mismatch_eva")])
			var hn: Node3D = se.hand_node()
			lines.append("Window hand: %s · seen %s · knocks %d · armed %s · eligibility '%s' · investigation %s" % [hn.state if hn != null else "-", hn.seen if hn != null else false, hn.knocks_played if hn != null else 0, se.is_armed(&"window_hand"), se.eligibility(&"window_hand"), se.investigation_state("window_hand")])
		var dpc: Node = main.get_node_or_null("DayPlan")
		if dpc != null and "cal_task" in se:
			lines.append("Calibration: L07 TRUE %s · M02 TRUE %s · workstation shows %s" % ["done" if dpc.is_task_done(&"l07") else "pending", "done" if dpc.is_task_done(&"m02") else "pending", ("%s NOT CALIBRATED (story)" % se.cal_task_shown) if se.cal_task_shown != "" else "the truth"])
		var qd: Node = main.get_node_or_null("Equipment/QuartersLife")
		if qd != null and qd.has_method("basil_state_name"):
			lines.append("Basil: %s%s · died day %d · seen dead %s · return day %d" % [qd.basil_state_name(), " (TRUE: dead)" if qd.basil_dead and qd.basil_return_day >= 0 else "", qd.basil_dead_day, qd.basil_seen_dead, qd.basil_return_day])
		var clr: Node = main.get_node_or_null("DayPlan/Clearance")
		if clr != null:
			lines.append("Clearance: %s (earned %d%s)" % [clr.NAMES[clr.effective()], clr.earned(), " · DEV OVERRIDE" if clr.dev_override >= 0 else ""])
		for e in se.evidence.slice(maxi(se.evidence.size() - 4, 0)):
			lines.append("  · d%d %s [%s] %s" % [int(e["day"]), e["event"], e["kind"], String(e["text"]).left(70)])
	return "\n".join(lines)


func event_line(id: StringName) -> String:
	var e: Dictionary = se.EVENTS[id]
	var st: Dictionary = se.state[id]
	if not bool(e["implemented"]):
		return "%s — %s\n  UNAVAILABLE (not implemented)" % [id, e["name"]]
	var why: String = se.eligibility(id)
	return "%s — %s  [phase %d%s]\n  %s · plays %d/%d · seen %s · last day %s · cooldown %d d%s\n  needs: %s" % [
		id, e["name"], int(e["phase"]), " late" if bool(e["late"]) else "",
		"ELIGIBLE" if why == "" else "not eligible: " + why,
		int(st["plays"]), int(e["max_plays"]), "yes" if bool(st["seen"]) else "no",
		str(st["last_day"]) if int(st["last_day"]) > 0 else "-", int(e["cooldown_days"]),
		"  · ACTIVE" if se.active == id else ("  · ARMED" if se.is_armed(id) else ""), e["needs"]]


func _rebuild_events() -> void:
	for c in _events_box.get_children():
		_events_box.remove_child(c)
		c.queue_free()
	for id in se.EVENTS:
		var box := VBoxContainer.new()
		box.set_meta("event_id", String(id))
		_events_box.add_child(box)
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(520, 0)
		l.add_theme_font_size_override("font_size", 11)
		l.text = event_line(id)
		box.add_child(l)
		if bool(se.EVENTS[id]["implemented"]):
			var h := _row(box)
			for a in [["Trigger", "trigger"], ["Trigger+count", "count"], ["Arm", "arm"], ["Cancel", "cancel"], ["Reset", "reset"], ["Seen ±", "seen"], ["Enable ±", "enable"]]:
				var what: String = a[1]
				_button(h, a[0], func(): event_action(id, what))
		box.add_child(HSeparator.new())


func player_text() -> String:
	var lines: Array = []
	# Round 46: every time domain side by side (shift budget vs station clock).
	var dpt: Node = main.get_node_or_null("DayPlan")
	if dpt != null and dpt.has_method("time_diagnostics"):
		var td: Dictionary = dpt.time_diagnostics()
		lines.append("Time: clock %s · shift %.1f s elapsed / %.1f s left · x%.0f clock rate" % [td["clock"], td["elapsed_s"], td["remaining_s"], td["multiplier"]])
		lines.append("Time domain: %s · pause: %s · laptop clock +%.0f s · after shift %.0f s" % [td["domain"], td["pause"] if String(td["pause"]) != "" else "none", td["laptop_clock_s"], td["after_shift_s"]])
	var pc: Node3D = main.get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") as Node3D
	var br: Node = main.get_node_or_null("Equipment/BreakerPanel")
	if pc != null:
		var p: Vector3 = pc.global_position
		lines.append("Eye position: (%.2f, %.2f, %.2f)" % [p.x, p.y, p.z])
		if br != null and br.has_method("zone_at"):
			lines.append("Room / power zone: %s" % String(br.zone_at(p)))
	var eva: Node = main.get_tree().get_first_node_in_group(&"eva_system")
	if eva != null:
		lines.append("EVA zone: %s · suited %s · floating %s" % [eva.zone, eva.suited, eva.get("float_mode")])
	var net: Node = main.get_node_or_null("CameraNetwork")
	var sh: Node = main.get_node_or_null("Interactables/WorkstationConsole/WorkstationScreen/Shell")
	if net != null:
		var rendering: Array = net.ids().filter(func(i): return net.is_rendering(i))
		lines.append("Selected camera: %s · rendering: %s · demand: %s" % [sh.selected_cam if sh != null else "-", ", ".join(rendering), str(net.demanded())])
	lines.append("Presence visible (camera-only): %s · hatch clones: %d" % [se.presence_visible(), se.hatch_clone_count()])
	var dp: Node = main.get_node_or_null("DayPlan")
	if dp != null:
		var log: Array = dp._day_log
		lines.append("Last equipment log: %s" % (log.back() if not log.is_empty() else "-"))
		lines.append("Day %d · %s" % [dp.day_number, dp.clock_text_hhmm() if dp.has_method("clock_text_hhmm") else ""])
	var ai: Node = main.get_tree().get_first_node_in_group(&"station_ai")
	if ai != null and not ai.history.is_empty():
		lines.append("Last assistant line: %s" % String(ai.history.back().get("text", "")))
	lines.append("Story history (last 4): %s" % str(se.history.slice(maxi(se.history.size() - 4, 0))))
	return "\n".join(lines)


# ===================================================================
# Round 49: DECK B (Lower Service Deck) developer tools. Every override is
# transient (never saved): access tier, faults are real model faults the
# technician then repairs normally; previews never count as plays.
# ===================================================================
const DeckBLayout = preload("res://scripts/deck_b/deck_b_layout.gd")
const DeckBTasks = preload("res://scripts/deck_b/deck_b_tasks.gd")
const DECK_B_TELEPORTS := [["B-01 Junction", "BJunctionC"], ["B-02 Water", "BWaterA"], ["B-03 Thermal", "BThermalA"], ["B-04 Workshop", "BWorkshopA"],
	["B-05 Lab", "BLabA"], ["B-06 Botany", "BBotanyA"], ["B-07 Medical", "BMedA"], ["B-08 Cargo", "BCargoA"], ["B-09 Archive", "BArchiveA"],
	["Shaft (Deck A)", "ShaftTop"], ["Shaft (Deck B)", "BShaftBottom"]]


func _deck_b() -> Node:
	return main.get_node_or_null("DeckB") if main != null else null


func _sys_b() -> Node:
	return main.get_node_or_null("DeckB/DeckBSystems") if main != null else null


func _build_deck_b_controls(box: VBoxContainer) -> void:
	var l := Label.new()
	l.text = "Access (developer override, not saved):"
	box.add_child(l)
	var h := _row(box)
	for t in [-1, 0, 1, 2, 3, 4]:
		var tt: int = t
		_button(h, "auto" if t < 0 else "T%d" % t, func(): main.get_node("DayPlan/Clearance").dev_set_deck_b(tt); last_action = "Deck B tier %s" % ("auto" if tt < 0 else str(tt)))
	_button(h, "Unlock all (L3 + T4)", func(): main.get_node("DayPlan/Clearance").dev_set(3); main.get_node("DayPlan/Clearance").dev_set_deck_b(4); last_action = "Deck B fully unlocked (dev)")
	var l2 := Label.new()
	l2.text = "Teleport (Deck B rooms / shaft landings):"
	box.add_child(l2)
	var ht: HBoxContainer = null
	for i in DECK_B_TELEPORTS.size():
		if i % 4 == 0:
			ht = _row(box)
		var ti: int = i
		_button(ht, DECK_B_TELEPORTS[i][0], func(): teleport_node(DECK_B_TELEPORTS[ti][1]))
	var hl := _row(box)
	_button(hl, "Ladder: climb down", func(): ladder_test(true))
	_button(hl, "Ladder: climb up", func(): ladder_test(false))
	_button(hl, "Abort to landing", func(): shaft_abort())
	_button(hl, "Hoist: send", func(): hoist_send_dev())
	var l3 := Label.new()
	l3.text = "Inject a REAL model fault (repair it normally):"
	box.add_child(l3)
	var hf := _row(box)
	_button(hf, "Water pump air lock", func(): _sys_b().water["pump_fault"] = "air_lock"; _sys_b().water["processing"] = true; last_action = "fault: P-201 air lock")
	_button(hf, "Filter bed spent", func(): _sys_b().water["filter_life"] = 0.25; last_action = "fault: MF-2 spent")
	_button(hf, "Coolant speed drop", func(): _sys_b().thermal["fault"] = "speed_drop"; last_action = "fault: P-301 speed")
	var hf2 := _row(box)
	_button(hf2, "FEED-1 chatter", func(): _sys_b().power["feed1_fault"] = "chatter"; last_action = "fault: FEED-1 intermittent")
	_button(hf2, "Battery hot (V1 shut)", func(): _sys_b().thermal["v1"] = 0.0; last_action = "fault: V1 closed")
	_button(hf2, "Trip B3 breaker", func(): _sys_b().power["on"][2] = false; last_action = "fault: B3 tripped")
	_button(hf2, "Clear all faults", func(): clear_deck_b_faults())
	var l4 := Label.new()
	l4.text = "Work orders (Deck B registry):"
	box.add_child(l4)
	var hk := _row(box)
	_task_pick = OptionButton.new()
	_task_pick.focus_mode = Control.FOCUS_NONE
	for t in DeckBTasks.TYPES:
		_task_pick.add_item(String(t))
	hk.add_child(_task_pick)
	_button(hk, "Raise", func(): raise_selected_task())
	_button(hk, "Cancel open", func(): cancel_selected_task())
	var hs := _row(box)
	_button(hs, "Restock lower-deck parts", func(): restock_deck_b())
	_button(hs, "Berth cargo vehicle now", func(): berth_cargo())
	_button(hs, "Interior always visible", func(): toggle_interior())
	var l5 := Label.new()
	l5.text = "Chapter Two / Phase Three events (preview never counts):"
	box.add_child(l5)
	var he: HBoxContainer = null
	var ids: Array = []
	for id in se.EVENTS:
		if bool(se.EVENTS[id].get("deck_b", false)):
			ids.append(id)
	for i in ids.size():
		if i % 3 == 0:
			he = _row(box)
		var eid: StringName = ids[i]
		_button(he, String(eid), func(): se.dev_trigger(eid, _variant); last_action = "preview " + String(eid))
	var hr := _row(box)
	_button(hr, "Cancel event", func(): se.dev_cancel(); last_action = "cancel")
	_button(hr, "Reset Deck B events", func():
		for id2 in ids:
			se.dev_reset(id2)
		last_action = "Deck B events reset")


func deck_b_text() -> String:
	var clr: Node = main.get_node_or_null("DayPlan/Clearance")
	var s: Node = _sys_b()
	var lines: Array = []
	if clr != null:
		lines.append("Deck B tier: %d %s (earned %d · Deck B jobs %d)%s" % [clr.deck_b_tier(), clr.DECK_B_NAMES[clr.deck_b_tier()], clr.earned_deck_b(), clr.deck_b_jobs, " · DEV OVERRIDE" if clr.dev_deck_b >= 0 else ""])
	var pc: Node3D = main.get_node_or_null("Player") as Node3D
	if pc != null:
		lines.append("Player: %s · room %s" % ["DECK B" if DeckBLayout.is_lower(pc.global_position) else "DECK A", String(DeckBLayout.room_at(pc.global_position))])
	var sh: Node = _deck_b().get_node_or_null("VerticalShaft") if _deck_b() != null else null
	if sh != null:
		lines.append("Shaft: climbing %s grip %d dir %d lid %s · hoist at %s (%s)" % [sh.climbing, sh.grip, sh.dir, "open" if sh.lid_open else "shut", sh.hoist_at, sh.hoist_item.name if sh.hoist_item != null else "empty"])
	if s != null:
		lines.append("Water: %s raw %.1f L potable %.1f L cond %.0f bed %d %% pump %s %s" % [s.water_status(), float(s.water["raw_l"]), float(s.water["potable_l"]), float(s.water["pot_cond"]), int(float(s.water["filter_life"]) * 100.0), "RUN" if s.water["processing"] else "IDLE", s.water["pump_fault"]])
		lines.append("Coolant: %s supply %.1f ENG %.1f BATT %.1f LAB %.1f fault '%s' standby %s" % [s.thermal_status(), float(s.thermal["supply"]), float(s.thermal["eng_T"]), float(s.thermal["batt_T"]), float(s.thermal["lab_T"]), s.thermal["fault"], s.thermal["standby"]])
		lines.append("Bus B: B1 %s B2 %s B3 %s B4 %s · feed1 '%s' · B2 on %s · FEED-2 %.2f kW" % ["ON" if s.powered(0) else "off", "ON" if s.powered(1) else "off", "ON" if s.powered(2) else "off", "ON" if s.powered(3) else "off", s.power["feed1_fault"], s.power["b2_source"], s.feed2_load()])
		lines.append("Visited lower rooms: %s · Deck B days %d · services logged %d" % [", ".join(s.rooms_visited_total()), s.deck_b_days(), s.service_log.size()])
	var dp: Node = main.get_node_or_null("DayPlan")
	if dp != null:
		var ob: Array = dp.open_orders().filter(func(o): return DeckBTasks.is_deck_b(StringName(o["type"])))
		lines.append("Open Deck B orders: %s" % ", ".join(ob.map(func(o): return "%s %s" % [o["id"], o["type"]])))
	lines.append("Chapter: one complete %s · milestones %s" % [se.chapter_one_complete(), ", ".join(se.milestones)])
	lines.append("Last action: %s" % last_action)
	return "\n".join(lines)


func shaft_abort() -> void:
	_deck_b().get_node("VerticalShaft").abort_to_landing()
	last_action = "shaft: abort to landing"


func hoist_send_dev() -> void:
	var sh: Node = _deck_b().get_node("VerticalShaft")
	sh.hoist_send(sh.hoist_at if sh.hoist_at in ["A", "B"] else "A")
	last_action = "hoist sent"


func berth_cargo() -> void:
	var cb: Node = _deck_b().room_node(&"b08")
	if cb != null:
		cb.arrive(randi())
		last_action = "cargo vehicle berthed"


func toggle_interior() -> void:
	_deck_b().interior_forced = not _deck_b().interior_forced
	last_action = "interior forced %s" % _deck_b().interior_forced


func teleport_node(node_name: String) -> bool:
	var sh: Node = _deck_b().get_node_or_null("VerticalShaft") if _deck_b() != null else null
	if sh != null and sh.is_climbing():
		last_action = "teleport refused: climbing"
		return false
	var n: Node3D = main.get_node_or_null("MovementNodes/" + node_name) as Node3D
	var fb: Node = main.get_node_or_null("FreeMoveBody")
	if n == null or fb == null:
		return false
	fb.sync_to_eye_position(n.global_position)
	fb.velocity = Vector3.ZERO
	last_action = "teleport %s" % node_name
	return true


func ladder_test(down: bool) -> void:
	teleport_node("ShaftTop" if down else "BShaftBottom")
	var sh: Node = _deck_b().get_node("VerticalShaft")
	main.get_tree().create_timer(0.3).timeout.connect(func(): sh.begin(down))
	last_action = "ladder test %s (W / click to continue)" % ("down" if down else "up")


func clear_deck_b_faults() -> void:
	var s: Node = _sys_b()
	if s == null:
		return
	s.water["pump_fault"] = ""
	s.thermal["fault"] = ""
	s.thermal["rad_fault"] = ""
	s.thermal["rad"] = [1.0, 1.0]
	s.power["feed1_fault"] = ""
	s.power["on"] = [true, true, true, true]
	last_action = "Deck B faults cleared"


func raise_selected_task() -> void:
	if _task_pick == null or _task_pick.selected < 0:
		return
	var t := StringName(_task_pick.get_item_text(_task_pick.selected))
	var dp: Node = main.get_node("DayPlan")
	var o: Dictionary = dp.raise_order(t, "developer")
	last_action = ("raised %s %s" % [o.get("id", ""), t]) if not o.is_empty() else "not raised (open already / gated: unlock Deck B)"


func cancel_selected_task() -> void:
	if _task_pick == null or _task_pick.selected < 0:
		return
	var t: String = _task_pick.get_item_text(_task_pick.selected)
	var dp: Node = main.get_node("DayPlan")
	for o in dp.orders:
		if o["status"] == "open" and String(o["type"]) == t:
			o["status"] = "cancelled"
	last_action = "cancelled open %s" % t


func restock_deck_b() -> void:
	var db: Node = _deck_b()
	var plan := [[&"b02", "WaterSpareBeds", &"mf_bed"], [&"b02", "PumpSealKits", &"pump_seal_kit"], [&"b03", "ThermalSpares", &"valve_actuator"], [&"b04", "WorkshopStock", &"relay_module"],
		[&"b06", "BotanyCabinet", &"grow_light_module"], [&"b09", "ArchiveBlanks", &"data_cartridge"], [&"b01", "EmSpareClip", &"lamp_module"]]
	var n := 0
	for p in plan:
		var room: Node = db.room_node(p[0])
		if room == null:
			continue
		var r: Node = room.find_child(p[1], true, false)
		if r != null and r.free_slot() != -1:
			room.spawn_part(p[2], r)
			n += 1
	last_action = "restocked %d lower-deck parts" % n
