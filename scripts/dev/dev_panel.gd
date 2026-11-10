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
var _variant: String = "normal"
var _eq_snapshots: Dictionary = {}     # node path -> state_dict
var _t: float = 0.0
var _mouse_before: int = Input.MOUSE_MODE_CAPTURED
var last_action: String = ""


func setup(p_main: Node, p_se: Node) -> void:
	main = p_main
	se = p_se


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		toggle()
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
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_before
	_set_player_input(true)


func _set_player_input(on: bool) -> void:
	var lc: Node = main.get_node_or_null("Player/LookPivot") if main != null else null
	if lc != null and "input_enabled" in lc:
		var ws: Node = main.get_node_or_null("WorkstationState")
		# Only hand looking back if nothing else (the seated workstation) owns it.
		if on and ws != null and ws.is_in_use():
			return
		lc.input_enabled = on


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
