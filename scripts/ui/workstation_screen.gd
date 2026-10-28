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
## Defaults to Control Room (index 1): that's physically where the
## player is standing while reading this screen.
var _selected_room_index: int = 1


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	show_section(Section.HOME)


func show_section(section: Section) -> void:
	_current_section = section
	for key in _section_roots:
		_section_roots[key].visible = (key == section)
	_title_label.text = SECTION_NAMES[section]
	_hint_label.text = "[0] Home     [Esc] Exit" if section != Section.HOME else "[1] Overview  [2] Work Orders  [3] Diagnostics  [4] Surveillance  [5] Save/Load  [6] Settings     [Esc] Exit"
	match section:
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


func current_section() -> Section:
	return _current_section


## Called by workstation_state.gd's key routing (Left/Right arrows),
## only meaningful while the Overview section is showing the map.
func select_next_room() -> void:
	_selected_room_index = (_selected_room_index + 1) % ROOMS.size()
	_refresh_map()


func select_prev_room() -> void:
	_selected_room_index = (_selected_room_index - 1 + ROOMS.size()) % ROOMS.size()
	_refresh_map()


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
			_cycle_difficulty()


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
	if not _day_plan.is_task_done(&"c01"):
		_overview_status.text = "[R] Run Morning Station Inspection"
	else:
		var assignment_line := ""
		if _day_plan.assignment_task_id == &"e06":
			assignment_line = "\nAssignment: E06 Tighten Loose Connection — Engineering."
		_overview_status.text = "Station nominal." + assignment_line
	_refresh_map()


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
				return "%s — Component shelving. Control Wire (16-gauge, %s) available here." % [room_name, _fault_color_name().to_lower()]
			return "%s — Component shelving. Nothing currently needed from here — trace the Engineering circuit (E02) first if a fault is open." % room_name
		&"airlock":
			return "%s — Reached via Engineering's maintenance branch. No equipment." % room_name
	return room_name


func _refresh_work_orders() -> void:
	var repaired: bool = _electrical_panel != null and _electrical_panel.is_repaired()
	var lines: Array[String] = _day_plan.get_work_order_lines(repaired, _fault_color_name())
	if lines.size() > 1 or lines[0] != "No open work orders.":
		lines = lines.duplicate()
		lines.append("")
		lines.append("[R] Verify Repaired System (C05)")
	_work_orders_list.text = "\n".join(lines)


## C05 Verify Repaired System: checks whichever chain is actually open
## right now and reports its real state -- running this before the
## repair is actually done must report the still-broken status, never
## silently pass (MILESTONE1_DESIGN.md Part 4.4/6.10).
func _run_verify() -> bool:
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
func _refresh_settings() -> void:
	_difficulty_label.text = "GAME DIFFICULTY: %s" % repair_difficulty_name().to_upper()


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
