extends SubViewport
## The Control Room workstation's physical screen content -- the same
## "SubViewport as a physical screen's live feed" pattern already
## proven by the laptop (scripts/ui/session_log_screen.gd) and the
## surveillance system (scripts/surveillance/surveillance_camera.gd),
## reused here for a small multi-section computer UI instead of a
## single text editor or a single camera feed.
##
## Navigation is entirely key-driven (workstation_state.gd forwards
## number keys directly to show_section()), deliberately NOT a
## mouse-click-on-3D-screen system: scripts/player/laptop_view.gd's own
## doc comment already identified raycast-to-UV click mapping as "a
## much larger problem" not worth solving for a dedicated-key
## interface, and that reasoning applies equally here. Every section is
## exactly one keypress from Home, so the "reachable within three
## clicks" requirement is satisfied with room to spare.
##
## Surveillance integration: this screen does NOT own any camera
## selection state of its own. It reads the CURRENT feed/camera id from
## the one real SurveillanceConsole instance and calls that same
## node's interact() to cycle cameras -- there is exactly one camera
## selection in the game, owned by SurveillanceConsole, no matter how
## many physical screens display it (Approved Decision A.11: "do not
## duplicate surveillance state or create conflicting camera owners").

const GameSettings = preload("res://scripts/station/game_settings.gd")

enum Section { HOME, OVERVIEW, WORK_ORDERS, DIAGNOSTICS, SURVEILLANCE, SAVE_LOAD, SETTINGS }

const SECTION_NAMES := {
	Section.HOME: "HOME",
	Section.OVERVIEW: "STATION OVERVIEW",
	Section.WORK_ORDERS: "WORK ORDERS",
	Section.DIAGNOSTICS: "DIAGNOSTICS",
	Section.SURVEILLANCE: "SURVEILLANCE",
	Section.SAVE_LOAD: "SAVE / LOAD",
	Section.SETTINGS: "SETTINGS",
}

@export var day_plan_path: NodePath
@export var electrical_panel_path: NodePath
@export var surveillance_console_path: NodePath

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _electrical_panel: Node = get_node_or_null(electrical_panel_path)
@onready var _surveillance_console: Node = get_node_or_null(surveillance_console_path)

@onready var _title_label: Label = $Control/VBox/TitleBar/TitleLabel
@onready var _hint_label: Label = $Control/VBox/HintBar/HintLabel

@onready var _section_roots := {
	Section.HOME: $Control/VBox/Content/Home,
	Section.OVERVIEW: $Control/VBox/Content/Overview,
	Section.WORK_ORDERS: $Control/VBox/Content/WorkOrders,
	Section.DIAGNOSTICS: $Control/VBox/Content/Diagnostics,
	Section.SURVEILLANCE: $Control/VBox/Content/Surveillance,
	Section.SAVE_LOAD: $Control/VBox/Content/SaveLoad,
	Section.SETTINGS: $Control/VBox/Content/Settings,
}

@onready var _overview_status: Label = $Control/VBox/Content/Overview/Status
@onready var _room_info: Label = $Control/VBox/Content/Overview/RoomInfo
@onready var _work_orders_list: Label = $Control/VBox/Content/WorkOrders/List
@onready var _diagnostics_status: Label = $Control/VBox/Content/Diagnostics/Status
@onready var _difficulty_label: Label = $Control/VBox/Content/Settings/DifficultyLabel
@onready var _terminal_lights_row: HBoxContainer = $Control/VBox/Content/Diagnostics/TerminalLights
@onready var _t1_light: ColorRect = $Control/VBox/Content/Diagnostics/TerminalLights/T1/Light
@onready var _t2_light: ColorRect = $Control/VBox/Content/Diagnostics/TerminalLights/T2/Light
@onready var _surveillance_feed: TextureRect = $Control/VBox/Content/Surveillance/Feed
@onready var _surveillance_label: Label = $Control/VBox/Content/Surveillance/CameraLabel

## Room-level topology, derived from and verified against the actual
## MovementNode graph in scenes/main.tscn (not assumed): 8 rooms, 8
## direct edges. Deliberately does NOT include a direct Life Support —
## Engineering edge even though the task brief's prose suggested one --
## the real graph only connects them via Main Junction or via Storage,
## so the room-info text for Life Support says that explicitly instead
## of the map drawing a line that doesn't exist.
const ROOMS := [
	{"id": &"living_quarters", "node": "RoomLivingQuarters", "name": "Living Quarters"},
	{"id": &"control_room", "node": "RoomControlRoom", "name": "Control Room"},
	{"id": &"main_junction", "node": "RoomMainJunction", "name": "Main Junction"},
	{"id": &"communications", "node": "RoomCommunications", "name": "Communications"},
	{"id": &"life_support", "node": "RoomLifeSupport", "name": "Life Support"},
	{"id": &"engineering", "node": "RoomEngineering", "name": "Engineering"},
	{"id": &"storage", "node": "RoomStorage", "name": "Storage"},
	{"id": &"airlock", "node": "RoomAirlock", "name": "Airlock"},
]

var _current_section: Section = Section.HOME
var shell: Control = null   # Round 37: workstation_shell.gd
## Round 28: last workday verify/close result shown under Work Orders.
var _workday_status: String = ""
## Defaults to Control Room (index 1): that's physically where the
## player is standing while reading this screen.
var _selected_room_index: int = 1


## Round 42 Priority 8: the monitor UI is laid out in 640 x 400 units but
## RENDERED at 2x (1280 x 800): text and the camera feed stay sharp on the
## physical screen. Input arriving in render pixels (uv * size) is mapped
## back through the stretch transform by the viewport itself.
const RENDER_SCALE := 2


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	size_2d_override = Vector2i(640, 400)
	size_2d_override_stretch = true
	size = Vector2i(640 * RENDER_SCALE, 400 * RENDER_SCALE)
	if _day_plan.has_signal(&"day_started"):
		_day_plan.day_started.connect(func(_d): show_section(_current_section))
	if _day_plan.has_signal(&"task_completed"):
		_day_plan.task_completed.connect(func(_t): if _current_section == Section.HOME: _refresh_home())
	# Round 33: deferred -- the Home briefing reads the stations' live
	# condition(), and they are not ready yet during this _ready.
	_current_section = Section.HOME
	# Round 37: the visible interface is the three-section, map-first,
	# clickable shell; the old sections stay as the keyboard/text model.
	shell = preload("res://scripts/ui/workstation_shell.gd").new()
	shell.name = "Shell"
	add_child(shell)
	shell.setup(self, _day_plan)
	$Control.visible = false
	show_section.call_deferred(Section.HOME)


## Round 33: the Home screen always says which day it is, and flags a NEW
## SHIFT until the morning check-in (C01) is run.
func _refresh_home() -> void:
	# Round 35: short lines, clear status -- details live in Work Orders.
	var welcome: Label = $Control/VBox/Content/Home/Welcome
	var lines: Array[String] = []
	if _day_plan.has_method("today_title"):
		if _day_plan.is_new_shift():
			lines.append("NEW SHIFT — TODAY IS DAY %d" % _day_plan.day_number)
		else:
			lines.append("TODAY: DAY %d" % _day_plan.day_number)
		lines.append("Scheduled: %s" % _day_plan.today_title())
		for b in briefing_lines():
			lines.append(b)
	else:
		lines.append("WORKSTATION READY")
	welcome.text = "\n".join(lines)


func show_section(section: Section) -> void:
	_current_section = section
	for key in _section_roots:
		_section_roots[key].visible = (key == section)
	_title_label.text = ("DAY %d · %s" % [_day_plan.day_number, SECTION_NAMES[section]]) if "day_number" in _day_plan else SECTION_NAMES[section]
	_hint_label.text = "[0] Home     [Esc] Exit" if section != Section.HOME else "[1] Overview  [2] Work Orders  [3] Diagnostics  [4] Surveillance  [5] Save/Load  [6] Settings     [Esc] Exit"
	match section:
		Section.HOME:
			_refresh_home()
		Section.OVERVIEW:
			_refresh_overview()
		Section.WORK_ORDERS:
			_refresh_work_orders()
		Section.DIAGNOSTICS:
			_refresh_diagnostics()
		Section.SURVEILLANCE:
			_refresh_surveillance()
		Section.SETTINGS:
			_refresh_settings()
		Section.SAVE_LOAD:
			_refresh_save_load()
	# Round 37: old section -> visible shell page (keys 0-6 keep working).
	if shell != null:
		match section:
			Section.SAVE_LOAD, Section.SETTINGS:
				shell.show_page(shell.Page.SYSTEM)
			Section.DIAGNOSTICS:
				shell.ops_panel = "diag"
				shell.show_page(shell.Page.OPS)
			Section.SURVEILLANCE:
				shell.show_page(shell.Page.CAMERAS)
			_:
				shell.ops_panel = ""
				shell.show_page(shell.Page.OPS)


func current_section() -> Section:
	return _current_section


## Called by workstation_state.gd's key routing (Left/Right arrows),
## only meaningful while the Overview section is showing the map.
func select_next_room() -> void:
	_selected_room_index = (_selected_room_index + 1) % ROOMS.size()
	_refresh_map()
	if shell != null:
		shell.select_room(ROOMS[_selected_room_index]["id"])


## Round 37: [7] Records.
func show_records() -> void:
	if shell != null:
		shell.show_page(shell.Page.RECORDS)


func select_prev_room() -> void:
	_selected_room_index = (_selected_room_index - 1 + ROOMS.size()) % ROOMS.size()
	_refresh_map()
	if shell != null:
		shell.select_room(ROOMS[_selected_room_index]["id"])


## "[R] Run" action, context-sensitive per section -- Overview runs
## C01, Diagnostics runs C02, Surveillance cycles the camera, Settings
## cycles the electrical-repair difficulty.
func run_action() -> void:
	match _current_section:
		Section.OVERVIEW:
			_run_c01()
		Section.WORK_ORDERS:
			_run_verify()
		Section.DIAGNOSTICS:
			_run_c02()
		Section.SURVEILLANCE:
			_cycle_camera()
		Section.SETTINGS:
			adjust_setting(1)
		Section.SAVE_LOAD:
			_do_save()


func _run_c01() -> void:
	if not _day_plan.is_task_done(&"c01"):
		_day_plan.mark_done(&"c01")
		_day_plan.assign_daily_task()
	_refresh_overview()


## This milestone's Phase C: the eight subsystem readings used to be a
## four-line paragraph of "X: nominal" repeated eight times. They are
## now the StatusLights row authored directly in workstation_screen.tscn
## (eight small colored indicators + three-letter labels) -- nothing
## here currently varies any of them (no subsystem besides Engineering
## power has simulated fault state yet), so there is deliberately no
## per-frame light-color logic to write: inventing one would mean
## inventing fake sensor data this milestone's brief explicitly forbids.
## When a second subsystem gains real fault state, give its light a
## small setter here the same way _refresh_map() already drives the
## station diagram from real DayPlan/panel state -- not a redesign of
## this section.
func _refresh_overview() -> void:
	# Round 33: kept short so the station map stays fully visible; the full
	# morning briefing is on the Home screen.
	var priority: String = ""
	for l in briefing_lines():
		if l.begins_with("Priority:"):
			priority = "\n" + l
	if not _day_plan.is_task_done(&"c01"):
		_overview_status.text = "[R] Run Morning Station Inspection" + priority
	else:
		var assignment_line := ""
		if _day_plan.assignment_task_id == &"e06":
			assignment_line = "\nAssignment: E06 Tighten Loose Connection — Engineering."
		_overview_status.text = "Morning inspection complete." + assignment_line + priority
	_refresh_map()


## Round 33 Priority 3: the MORNING BRIEFING -- concise, from real state:
## the day, each maintained system's live condition, today's order and its
## next step, maintenance coming due, cargo, and supply shortages.
func briefing_lines() -> Array[String]:
	var out: Array[String] = []
	var attention: Array[String] = []
	for e in [["FilterHousingStation", "FILTER"], ["EngineeringCabinet1", "WIRING"], ["SensorCalibrationStation", "SENSORS"], ["ValveRoutingStation", "COOLANT"]]:
		var n: Node = _station(e[0])
		if n != null and n.is_node_ready() and n.has_method("condition"):
			var c: String = String(n.condition())
			if c != "nominal" and c != "restored":
				attention.append("%s %s" % [e[1], c.replace("_", " ")])
	var root: Node = _day_plan.get_parent()
	var br: Node = root.find_child("BreakerPanel", true, false) if root != null else null
	if br != null and not br.tripped_ids().is_empty():
		attention.append("BREAKER %s" % ", ".join(br.tripped_ids()))
	out.append("Systems: %s" % ("all nominal" if attention.is_empty() else " · ".join(attention)))
	var rows: Array = _day_plan.order_rows() if _day_plan.has_method("order_rows") else []
	var open_n: int = rows.filter(func(r): return not r.get("done", false)).size()
	out.append("Duties: %d open · Shift %s" % [open_n, "ended" if _day_plan.shift_ended else "%d%%" % int(round(_day_plan.shift_progress() * 100.0))])
	var g: Dictionary = _day_plan.guidance() if _day_plan.has_method("guidance") else {}
	if not g.is_empty():
		out.append("Priority: %s (%s)" % [g["label"], _day_plan.ROOM_SHORT.get(StringName(g["room"]), String(g["room"]).capitalize())])
	if _day_plan.cargo_duty == "open" and _day_plan.cargo_port() != null:
		out.append("Cargo: %s at the airlock" % _day_plan.cargo_port().shipment_id)
	elif _day_plan.cargo_port() != null:
		out.append("Cargo: next shipment day %d" % _day_plan.next_cargo_day)
	if _day_plan.get("carried_over_from") != null and _day_plan.carried_over_from > 0:
		out.append("Carried over from day %d" % _day_plan.carried_over_from)
	return out


func _station(n: String) -> Node:
	var root: Node = _day_plan.get_parent()
	return root.find_child(n, true, false) if root != null else null


## Station topology map (augments Overview, per this milestone's Phase
## 4): recolors each room box by (is the outstanding task there, is it
## currently selected) and refreshes the selected room's info text.
## Round 16 Priority 3: which color the currently-required spare wire
## actually is, read from the panel if one is wired up and has already
## chosen a config (fault_color_name() defaults to "Yellow" otherwise,
## matching every prior round's only possible color) -- "yellow" is the
## safe fallback for any screen/test wired up without a panel reference.
func _fault_color_name() -> String:
	if _electrical_panel != null and _electrical_panel.has_method("fault_color_name"):
		return _electrical_panel.fault_color_name()
	return "yellow"


## Reads DayPlan.get_outstanding_task_room()/get_work_order_lines()
## directly -- no separate map-only task state.
func _refresh_map() -> void:
	var outstanding_room: StringName = _day_plan.get_outstanding_task_room()
	var map := $Control/VBox/Content/Overview/Map
	for i in ROOMS.size():
		var room: Dictionary = ROOMS[i]
		var box: ColorRect = map.get_node(room["node"])
		box.color = _room_color(room["id"] == outstanding_room, i == _selected_room_index)
	var selected: Dictionary = ROOMS[_selected_room_index]
	_room_info.text = _room_info_text(selected["id"], selected["name"])


func _room_color(is_task_room: bool, is_selected: bool) -> Color:
	if is_task_room and is_selected:
		return Color(0.75, 0.58, 0.15)
	if is_task_room:
		return Color(0.5, 0.38, 0.12)
	if is_selected:
		return Color(0.45, 0.48, 0.52)
	return Color(0.22, 0.24, 0.27)


## Concise per-room info, including explaining unmet dependencies
## rather than leaving a room looking inert for no stated reason
## (Phase 4's explicit requirement).
func _room_info_text(room_id: StringName, room_name: String) -> String:
	match room_id:
		&"living_quarters":
			return "%s — Bunk, personal laptop. No outstanding tasks here." % room_name
		&"control_room":
			var line := "%s — Workstation (this terminal)." % room_name
			if not _day_plan.is_task_done(&"c01"):
				line += " [R] Run Morning Station Inspection is pending (see Overview)."
			elif not _day_plan.is_task_done(&"c05") and (_day_plan.is_task_done(&"e06") or _day_plan.is_task_done(&"e05")):
				line += " A completed repair is awaiting verification (see Work Orders)."
			return line
		&"main_junction":
			return "%s — Central hub connecting Communications, Life Support, and Engineering. No equipment." % room_name
		&"communications":
			# Round 16 Priority 8: this used to always say "not used by
			# any currently active task," stale the moment the Signal
			# Calibration console (M02) was added to this room -- same
			# "appropriate room equipment" discoverability gap this
			# priority asks to review. Free-standing tasks (M02, and
			# life_support's own L07/L08/L02 below) are deliberately
			# NOT injected into the Work Orders panel/Slice B chain --
			# this is flavor/discoverability text only, reading
			# DayPlan's existing done-flags, never duplicating or
			# mutating task state.
			return ("%s — Signal calibration console, routine maintenance (serviced)." % room_name) if _day_plan.is_task_done(&"m02") \
				else ("%s — Signal calibration console available for routine maintenance." % room_name)
		&"life_support":
			var serviced: Array[String] = []
			var pending: Array[String] = []
			for entry in [["l07", "sensor calibration"], ["l08", "coolant valve routing"], ["l02", "filter housing service"]]:
				if _day_plan.is_task_done(entry[0]):
					serviced.append(entry[1])
				else:
					pending.append(entry[1])
			var summary := ", ".join(pending) if not pending.is_empty() else ", ".join(serviced)
			var suffix := " Available: %s." % summary if not pending.is_empty() else " All routine maintenance here is serviced."
			return "%s — Environmental/coolant/filter equipment.%s Reaches Engineering via Storage or Main Junction, not directly." % [room_name, suffix]
		&"engineering":
			var repaired: bool = _electrical_panel != null and _electrical_panel.is_repaired()
			var lines: Array[String] = _day_plan.get_work_order_lines(repaired, _fault_color_name())
			if lines.size() > 0 and lines[0] != "No open work orders.":
				# Phase D fix: this used to always say "electrical panel"
				# even when the actual outstanding work was E06 (a small,
				# separate loose-connection fitting, not the panel at
				# all) -- player feedback traced to exactly this
				# mismatch. Name whichever equipment the real outstanding
				# work order actually points at.
				var equipment := "Electrical panel"
				if _day_plan.assignment_task_id == &"e06" and not _day_plan.is_task_done(&"e06"):
					equipment = "Loose connection fitting (small bracket, separate from the electrical panel)"
				return "%s — %s.\n%s" % [room_name, equipment, "\n".join(lines)]
			# Round 16 Priority 8: this fallback line never mentioned the
			# diagnostic bench (E09, added Round 15) -- same stale-
			# discoverability gap as the communications/life_support
			# fixes above. Flavor/discoverability text only, same
			# "never injected into Work Orders" policy as every other
			# free-standing task.
			var e09_note := " No outstanding Slice B work here." if _day_plan.is_task_done(&"e09") else " Diagnostic bench available (E09)."
			return "%s — Electrical panel, maintenance connection.%s" % [room_name, e09_note]
		&"storage":
			if _day_plan.required_component_id != &"" and not _day_plan.is_task_done(&"e05"):
				return "%s — Component shelving. %s available here." % [room_name, preload("res://scripts/station/part_names.gd").display(_day_plan.required_component_id, _fault_color_name())]
			return "%s — Component shelving. Nothing currently needed from here — trace the Engineering circuit (E02) first if a fault is open." % room_name
		&"airlock":
			return "%s — Reached via Engineering's maintenance branch. No equipment." % room_name
	return room_name


var _wo_sel: int = 0
var _wo_details: bool = false


## Round 35 Priority 3: ONE SHORT LINE PER ASSIGNMENT. Each row shows what
## needs attention, the NEXT physical action, where, and a small status;
## ↑/↓ select, Enter toggles an optional detail panel for the selected
## row. Rows advance by themselves as the equipment changes.
func work_order_rows() -> Array:
	var rows: Array = []
	if _day_plan.workday == 0 and (_day_plan.assignment_task_id != &"" or _day_plan.fault_target != &""):
		# Day-1 orientation chain (Slice A/B) -- one row.
		var repaired: bool = _electrical_panel != null and _electrical_panel.is_repaired()
		var tag := "WIRING" if _day_plan.fault_target != &"" else "FITTING"
		var act := "Verify at workstation [R]"
		var room := &"control_room"
		if _day_plan.assignment_task_id == &"e06" and not _day_plan.is_task_done(&"e06"):
			act = "Tighten loose connection"
			room = &"engineering"
		elif _day_plan.fault_target != &"" and not repaired:
			act = "Repair the power fault"
			room = &"engineering"
		var done: bool = _day_plan.is_task_done(&"c05")
		rows.append({"id": "SLICE", "tag": tag, "action": "Complete" if done else act, "room": &"" if done else room, "progress": "", "done": done, "priority": 2})
	if _day_plan.has_method("order_rows"):
		rows.append_array(_day_plan.order_rows())
	if _day_plan.shift_ended and not _day_plan.shift_history.is_empty() and int(_day_plan.shift_history[-1]["day"]) == _day_plan.day_number:
		rows.append({"id": "REPORT", "tag": "REPORT", "action": "Day %d shift report" % _day_plan.day_number, "room": &"", "progress": "", "done": true, "priority": 0})
	return rows


func select_work_order(delta: int) -> void:
	var n: int = work_order_rows().size()
	if n > 0:
		_wo_sel = (_wo_sel + delta + n) % n
	_refresh_work_orders()


func toggle_work_order_details() -> void:
	_wo_details = not _wo_details
	_refresh_work_orders()


func work_order_detail_lines(row: Dictionary) -> Array:
	match String(row["id"]):
		"MAIN":
			return Array(_day_plan.workday_lines())
		"REPORT":
			return Array(_day_plan.shift_history[-1]["report"])
		"CARGO":
			var c: Dictionary = _day_plan.cargo_step()
			return ["Cargo %s — %s" % [_day_plan.cargo_port().shipment_id, _day_plan.cargo_port()._manifest_text(" · ")], "Next: %s" % c.get("label", "")]
		"SLICE":
			var repaired: bool = _electrical_panel != null and _electrical_panel.is_repaired()
			return Array(_day_plan.get_work_order_lines(repaired, _fault_color_name()))
	var eq: Node = _day_plan.order_equipment(StringName(row.get("type", ""))) if row.has("type") else null
	return eq.order_detail() if eq != null else []


func _refresh_work_orders() -> void:
	var rows: Array = work_order_rows()
	_wo_sel = clampi(_wo_sel, 0, maxi(rows.size() - 1, 0))
	var lines: Array[String] = []
	if rows.is_empty():
		lines.append("No open work orders.")
	for i in rows.size():
		lines.append(("> " if i == _wo_sel else "  ") + _day_plan.format_row(rows[i]))
	lines.append("")
	if _day_plan.has_method("shift_report_lines"):
		lines.append("SHIFT ENDED — rest in your bunk" if _day_plan.shift_ended else ("SHIFT WORK DONE — wrap up" if _day_plan.is_wrapping_up() else "SHIFT %d%% done" % int(round(_day_plan.shift_progress() * 100.0))))
	if _workday_status != "":
		lines.append(_workday_status)
	if _wo_details and not rows.is_empty():
		lines.append("— %s —" % rows[_wo_sel]["tag"])
		for d in work_order_detail_lines(rows[_wo_sel]).slice(0, 9):
			lines.append(String(d))
	else:
		var stock := ""
		for w in _day_plan.supply_warnings():
			if w.begins_with("STOCK") or w.begins_with("BLOCKED") or w.begins_with("SUPPLY"):
				stock = w if stock == "" else stock
		if stock != "":
			lines.append(stock.replace("STOCK (shelf+reserve): ", "STOCK "))
	lines.append("[Up/Dn] select   [Enter] details   [R] check")
	_work_orders_list.text = "\n".join(lines)


## C05 Verify Repaired System: checks whichever chain is actually open
## right now and reports its real state -- running this before the
## repair is actually done must report the still-broken status, never
## silently pass (MILESTONE1_DESIGN.md Part 4.4/6.10).
func _run_verify() -> bool:
	# Round 28 workdays: verify the restored equipment, then (after any
	# cleanup) close the order -- two separate presses, two separate states.
	if _day_plan.has_method("is_workday_active") and _day_plan.is_workday_active():
		_workday_status = _day_plan.workday_verify_or_close()
		_refresh_work_orders()
		return _day_plan.is_maintenance_verified()
	var verified_anything := false
	if _day_plan.assignment_task_id == &"e06" and _day_plan.is_task_done(&"e06"):
		_day_plan.mark_done(&"c05")
		verified_anything = true
	if _day_plan.fault_target == &"engineering_power" and _electrical_panel != null and _electrical_panel.is_repaired():
		_day_plan.mark_done(&"c05")
		verified_anything = true
	_refresh_work_orders()
	return verified_anything


## Phase 4's "meaningful evidence rather than always spelling out the
## exact answer": the two terminal IDs here (T-1/T-2) are the SAME ones
## electrical_panel.gd's get_terminal_prompt()/terminal_display_id()
## show at the physical panel, so a player who reads this screen and
## later inspects the panel can match the diagnostic reading to the
## connector it describes -- two independent clues (a voltage
## comparison AND a continuity result) that both point at the same
## terminal, not an unrelated random answer. Verbosity is gated by the
## one global Game Difficulty setting (Round 10 Workstream E) -- read
## directly here rather than through electrical_panel.gd's own
## repair-specific snapshot, since this is a passive readout, not a
## committed repair action whose requirements must stay fixed mid-task.
func _refresh_diagnostics() -> void:
	if _day_plan.fault_target == &"":
		_diagnostics_status.text = "[R] Run Subsystem Diagnostic (Power)"
		_terminal_lights_row.visible = false
		return
	# A compact visual pairing for the text evidence below -- two status
	# lights the player can glance at before reading the numbers, not a
	# replacement for reasoning about them (Phase C's explicit "do not
	# turn the diagnostic into an automatic answer reveal").
	_terminal_lights_row.visible = true
	_t1_light.color = Color(0.2, 0.85, 0.3, 1)
	_t2_light.color = Color(0.85, 0.2, 0.15, 1)
	var difficulty: StringName = GameSettings.difficulty_name()
	var lines: Array[String] = [
		"SUBSYSTEM DIAGNOSTIC — ENGINEERING POWER",
		"",
		"Circuit path: Main Bus -> Breaker B2 -> Terminal T-1 / T-2 (Control Wire run)",
		"",
		"Terminal T-1: 24.1V DC",
		"Terminal T-2: 11.4V DC",
	]
	if difficulty != &"hard":
		lines.append("")
		lines.append("Continuity — T-1: OK      T-2: FAIL (open circuit)")
	lines.append("")
	lines.append("Subsystem message: ENG-PWR-02 fault latched")
	if difficulty == &"easy":
		lines.append("")
		lines.append("Likely fault: Terminal T-2 (low voltage, continuity failure).")
	lines.append("")
	lines.append("See Work Orders for the repair chain.")
	_diagnostics_status.text = "\n".join(lines)


func _run_c02() -> void:
	# Round 28: on Filter/Calibration workdays Diagnostics reviews THAT
	# day's warning; only the electrical workday (and day 1) raises the
	# Engineering power fault.
	if _day_plan.has_method("is_workday_active") and _day_plan.is_workday_active() and _day_plan.workday != _day_plan.Workday.ELECTRICAL_SERVICE:
		if _day_plan.workday == _day_plan.Workday.CALIBRATION:
			_day_plan.record_fact(&"reviewed:sensor_warning")
		_refresh_diagnostics()
		_refresh_work_orders()
		return
	if not _day_plan.is_task_done(&"c02"):
		_day_plan.mark_done(&"c02")
		_day_plan.trigger_fault()
	_refresh_diagnostics()


func _refresh_surveillance() -> void:
	if _surveillance_console == null:
		_surveillance_label.text = "No surveillance console linked."
		return
	_surveillance_feed.texture = _surveillance_console.get_current_feed_texture()
	_surveillance_label.text = "Camera: %s     [R] Next Camera" % _surveillance_console.get_current_camera_id()


func _cycle_camera() -> void:
	if _surveillance_console == null:
		return
	_surveillance_console.interact()
	_refresh_surveillance()


## Round 10 Workstream E: this is now the ONE place the player sets
## difficulty for the entire game, not just Engineering -- displayed as
## "Game Difficulty" per the player's explicit "this must be labeled
## clearly as applying to the entire game, not simply to Engineering."
## Reads/writes the shared GameSettings singleton directly, so there is
## exactly one authoritative difficulty value; every task (currently
## E05's hints/screws and C02's diagnostic verbosity) reads the same
## place, never a second copy here.
## Round 35 Priority 1: the SAME player settings as the main/pause menus
## (GameSettings -> user://game_settings.cfg), plus the gameplay difficulty.
## ↑/↓ select a row, ←/→ (or [R]) change it; applied immediately.
const _GSX = preload("res://scripts/station/game_settings.gd")
var settings_sel: int = 0


func settings_rows() -> Array:
	var rows: Array = [["difficulty", "Game difficulty", repair_difficulty_name().to_upper()]]
	for b in _GSX.AUDIO_BUSES:
		rows.append(["vol_%s" % b, tr("SET_VOL_%s" % b), "%d %%" % roundi(float(_GSX.get_value("vol_%s" % b)) * 100.0)])
	rows.append(["fullscreen", tr("SET_FULLSCREEN"), "ON" if bool(_GSX.get_value("fullscreen")) else "OFF"])
	var sz: Vector2i = _GSX.WINDOW_SIZES[clampi(int(_GSX.get_value("window_size")), 0, _GSX.WINDOW_SIZES.size() - 1)]
	rows.append(["window_size", tr("SET_WINDOW_SIZE"), "%d × %d" % [sz.x, sz.y]])
	rows.append(["mouse_sensitivity", tr("SET_SENS"), "%.1f×" % float(_GSX.get_value("mouse_sensitivity"))])
	rows.append(["invert_y", tr("SET_INVERT"), "ON" if bool(_GSX.get_value("invert_y")) else "OFF"])
	rows.append(["reduce_effects", tr("SET_REDUCE_FX"), "ON" if bool(_GSX.get_value("reduce_effects")) else "OFF"])
	for k in ["ai_guidance", "ai_voice", "ai_captions"]:
		rows.append([k, tr("SET_" + k.to_upper()), "ON" if bool(_GSX.get_value(k)) else "OFF"])
	rows.append(["language", tr("SET_LANGUAGE"), preload("res://scripts/ui/localization.gd").LANGUAGE_NAMES.get(String(_GSX.get_value("language")), "English")])
	return rows


func select_setting(delta: int) -> void:
	var n: int = settings_rows().size()
	settings_sel = (settings_sel + delta + n) % n
	_refresh_settings()


func adjust_setting(dir: int) -> void:
	var key: String = settings_rows()[settings_sel][0]
	match key:
		"difficulty":
			_cycle_difficulty()
			return
		"fullscreen", "invert_y", "reduce_effects", "ai_guidance", "ai_voice", "ai_captions":
			_GSX.set_value(key, not bool(_GSX.get_value(key)))
		"window_size":
			_GSX.set_value(key, (int(_GSX.get_value(key)) + dir + _GSX.WINDOW_SIZES.size()) % _GSX.WINDOW_SIZES.size())
		"mouse_sensitivity":
			_GSX.set_value(key, clampf(snappedf(float(_GSX.get_value(key)) + 0.1 * dir, 0.1), 0.2, 3.0))
		"language":
			var i: int = _GSX.LANGUAGES.find(String(_GSX.get_value(key)))
			_GSX.set_value(key, _GSX.LANGUAGES[(i + dir + _GSX.LANGUAGES.size()) % _GSX.LANGUAGES.size()])
		_:
			_GSX.set_value(key, clampf(snappedf(float(_GSX.get_value(key)) + 0.1 * dir, 0.05), 0.0, 1.0))
	_refresh_settings()


func _refresh_settings() -> void:
	var lines: Array[String] = []
	var rows: Array = settings_rows()
	settings_sel = clampi(settings_sel, 0, rows.size() - 1)
	_difficulty_label.add_theme_font_size_override("font_size", 11)
	for i in rows.size():
		lines.append("%s%-22s %s" % ["> " if i == settings_sel else "  ", rows[i][1], rows[i][2]])
	lines.append("")
	lines.append("[Up/Dn] select   [Left/Right] change   (same as main menu)")
	_difficulty_label.text = "\n".join(lines)


func repair_difficulty_name() -> String:
	return String(GameSettings.difficulty_name())


## Cycles EASY -> NORMAL -> HARD -> EASY and persists immediately
## (GameSettings.cycle_difficulty()). Safe to call at any time,
## including while a repair is in progress elsewhere -- see
## electrical_panel.gd's `_active_difficulty` snapshot for why an
## already-started repair's screw/hint requirements never change
## mid-task even though this setting just did.
func _cycle_difficulty() -> void:
	GameSettings.cycle_difficulty()
	_refresh_settings()


# ======================================================================
# Round 33 Priority 1: SAVE / LOAD (one slot). [R] save, [L] load, [N] new
# game (press twice to confirm). Starting a new game never deletes the save.
# ======================================================================
var _save_status: String = ""
var _new_game_armed_ms: int = -1


func _save_game_node() -> Node:
	return get_tree().get_first_node_in_group(&"save_game") if is_inside_tree() else null


func _refresh_save_load() -> void:
	var notice: Label = $Control/VBox/Content/SaveLoad/Notice
	var sg: Node = _save_game_node()
	if sg == null:
		notice.text = "Save / Load unavailable (no save system in this scene)."
		return
	var lines: Array[String] = []
	lines.append("CURRENT SHIFT: DAY %d" % _day_plan.day_number)
	var summary: String = sg.save_summary()
	lines.append("SAVED GAME: %s" % (summary if summary != "" else "none"))
	var why: String = sg.save_blocker()
	lines.append("")
	lines.append("[R] Save progress" + ("   (unavailable: %s)" % why if why != "" else ""))
	lines.append("[L] Load saved game" + ("" if summary != "" else "   (no save)"))
	lines.append("[N] New game (press twice) — keeps the save until you save again")
	if _save_status != "":
		lines.append("")
		lines.append(_save_status)
	if sg.last_message != "" and _save_status == "":
		lines.append("")
		lines.append(sg.last_message)
	notice.text = "\n".join(lines)


func _do_save() -> void:
	var sg: Node = _save_game_node()
	if sg == null:
		return
	_save_status = sg.save_game()["message"]
	_refresh_save_load()


func save_load_key(keycode: int) -> void:
	var sg: Node = _save_game_node()
	if sg == null:
		return
	match keycode:
		KEY_L:
			_save_status = sg.load_game()["message"]
		KEY_N:
			if _new_game_armed_ms >= 0 and Time.get_ticks_msec() - _new_game_armed_ms < 4000:
				_new_game_armed_ms = -1
				sg.new_game()
				return
			_new_game_armed_ms = Time.get_ticks_msec()
			_save_status = "Press [N] again to start a NEW game (your save is not deleted)."
	_refresh_save_load()


## Round 34: the shift clock on Work Orders / Home ticks while visible.
var _tick: float = 0.0


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	if _current_section == Section.WORK_ORDERS:
		_refresh_work_orders()
	elif _current_section == Section.HOME:
		_refresh_home()
