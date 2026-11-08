extends Node
## Press-and-hold wristwatch task view. Polls KEY_C every frame (the
## same "poll Input.is_key_pressed() in _process()" convention
## free_move_controller.gd already uses for WASD, not an edge-triggered
## _unhandled_input action) because this needs continuous held/not-held
## state, not a single press event -- holding C raises the display,
## releasing it dismisses it immediately.
##
## C was chosen as genuinely unused: E/F/T/G are all claimed by
## sleep_state.gd (bed/laptop/sleep) and carry_system.gd (drop); 0-6/R/
## Esc are claimed by workstation_state.gd; WASD and the mouse are
## movement/look. See GAME_DESIGN.md's control list -- C does not
## appear anywhere in it.
##
## Reuses interaction_controller.gd's `interactions_enabled` flag (the
## same single signal workstation_state.gd/sleep_state.gd/carry_system.gd
## already drive for their own exclusive states) to decide whether the
## watch is even allowed to raise -- while seated at the workstation,
## sitting/laptop/editing, or sleeping, holding C does nothing at all,
## which is what "do not allow the watch to break... sitting... laptop/
## workstation editing" actually requires in practice: it never
## competes with any of those systems for the same key, and it never
## activates while they own the camera/input.
##
## This is a physical first-person presentation, not a screen-fixed HUD
## box: raising/lowering and the actual on-wrist display are both owned
## by the separate first_person_watch_rig.gd (see its set_raised()/
## set_watch_text()), a camera-child visual-only rig -- NOT a part of
## PlayerBody/StandingPose (see that rig's own class doc comment for
## why this split exists: the previous round's world-body-rotation
## approach was the actual cause of the body disappearing while the
## watch was raised). This script owns only the input polling, the
## exclusive-state gate, and the task-text formatting.
##
## Reads DayPlan directly (get_work_order_lines(), the same shared
## summary workstation_screen.gd's Work Orders section uses) rather
## than formatting its own copy of task state -- single source of
## truth, per this milestone's explicit requirement.

@export var day_plan_path: NodePath
@export var electrical_panel_path: NodePath
@export var interaction_controller_path: NodePath
@export var watch_rig_path: NodePath
@export var raise_duration: float = 0.28
## Round 19 Priority 1/2: the world body, so holding C also plays its
## own distinct "looking at my wrist" pose (see player_body.gd's
## set_watch_raise_pose()) alongside the existing camera-relative
## first-person rig -- addressing the mirror brief's explicit
## requirement that the mirror show a believable world-body inspection
## pose, not just the unchanged standing pose, while C is held.
@export var player_body_path: NodePath
## Round 20 Priority 5: so the glanced watch can tell the player "go get
## the part first" instead of just naming the task's room -- the actual
## gap the work-order-coherence brief named ("clear required part").
@export var carry_system_path: NodePath

@onready var _day_plan: Node = get_node_or_null(day_plan_path)
@onready var _electrical_panel: Node = get_node_or_null(electrical_panel_path)
@onready var _interaction_controller: Node = get_node_or_null(interaction_controller_path)
@onready var _watch_rig: Node = get_node(watch_rig_path)
@onready var _player_body: Node = get_node_or_null(player_body_path)
@onready var _carry_system: Node = get_node_or_null(carry_system_path)


func _process(_delta: float) -> void:
	var held: bool = Input.is_key_pressed(KEY_C)
	var allowed: bool = _interaction_controller == null or _interaction_controller.interactions_enabled
	var should_raise: bool = held and allowed
	var was_raised: bool = _watch_rig.is_raised()

	if should_raise != was_raised:
		_watch_rig.set_raised(should_raise, raise_duration)
		if _player_body != null:
			_player_body.set_watch_raise_pose(should_raise, raise_duration)
		_move_task_message(should_raise)

	if should_raise:
		# Keep it live while held -- e.g. marking a task done elsewhere
		# while the player happens to be holding the watch up should be
		# reflected immediately, not only at the moment it was raised.
		_refresh_text()


## Round 34: the raised watch sits where HUD task messages appear (bottom
## centre) -- while it is up, messages move to the top of the screen.
func _move_task_message(raised: bool) -> void:
	var ml: Control = get_node_or_null("../HUD/TaskMessageLabel") as Control
	if ml == null:
		return
	if raised:
		ml.anchor_top = 0.0; ml.anchor_bottom = 0.0
		ml.offset_top = 58.0; ml.offset_bottom = 90.0
	else:
		ml.anchor_top = 1.0; ml.anchor_bottom = 1.0
		ml.offset_top = -110.0; ml.offset_bottom = -78.0


func is_raised() -> bool:
	return _watch_rig.is_raised()


## Round 12 Workstream A5: the watch face is a small physical display,
## not a second work-orders screen -- the full multi-line summary this
## used to show ("No assignment yet — check in at the Control Room
## workstation.") was the actual, measurable cause of oversized/
## wrapping text on the tiny recessed face. This now shows ONE concise
## glanceable status (room name + a short action word), derived from
## the SAME authoritative DayPlan.get_outstanding_task_room() the
## station map already uses for "which room to head to next" --no
## second copy of that priority logic, and no invented in-game clock
## (this project has no time/calendar system at all -- see
## day_plan.gd's reset_for_new_day() class doc comment -- so a glanced
## "time" would be fabricated, not real game state). Full work-order
## detail remains exactly where it was: the Control Room workstation.
func _refresh_text() -> void:
	if _day_plan == null:
		_watch_rig.set_watch_text("NO SIGNAL")
		return
	# Round 37: a pending timed EMERGENCY takes the watch face (the same
	# status model as the top-screen banner and the workstation map).
	var stn: Node = _day_plan.get_parent().get_node_or_null("StationStatus") if _day_plan.get_parent() != null else null
	if stn != null:
		var e: Dictionary = stn.emergency()
		if not e.is_empty():
			_watch_rig.set_watch_text("! %s
%s %s" % [String(e["title"]).replace("POWER ", "PWR "), String(stn.ROOM_NAMES.get(StringName(e["room"]), "")).left(8), stn.clock(float(e["seconds"]))])
			return
	# Round 34 Priority 11: on workdays (and while a cargo duty is open) the
	# watch shows the ONE next action, where, and the shift clock -- all
	# event-driven from DayPlan.guidance(); it advances by itself.
	# Round 39 Priority 7: after the shift, the watch points to the bunk.
	if "shift_ended" in _day_plan and _day_plan.shift_ended:
		_watch_rig.set_watch_text("SHIFT OVER\nBUNK · REST")
		return
	if _day_plan.has_method("guidance") and (_day_plan.workday != 0 or _day_plan.cargo_duty == "open"):
		var g: Dictionary = _day_plan.guidance()
		var clock: String = "REST" if _day_plan.shift_ended else ("WRAP UP" if _day_plan.is_wrapping_up() else "%d%%" % int(round(_day_plan.shift_progress() * 100.0)))
		if g.is_empty():
			_watch_rig.set_watch_text("ALL CLEAR\n%s" % clock)
		else:
			_watch_rig.set_watch_text("%s\n%s · %s" % [g["short"], String(g["room"]).replace("_", " ").to_upper().replace("CONTROL ROOM", "CTRL RM").replace("LIFE SUPPORT", "LIFE SUP"), clock])
		return
	var room: StringName = _day_plan.get_outstanding_task_room()
	if room == &"":
		# Round 32 Priority 7: a shipment waiting at the airlock is the one
		# glanceable thing worth showing when no order is open.
		var port: Node = _day_plan.cargo_port() if _day_plan.has_method("cargo_port") else null
		if port != null and port.is_busy() and port.state != port.PortState.RECEIVED:
			_watch_rig.set_watch_text("CARGO %s\nAIRLOCK" % ("READY" if port.state == port.PortState.ARRIVED else "OPEN"))
			return
		_watch_rig.set_watch_text("ALL CLEAR")
		return
	# Round 20 Priority 5: if a part is already known to be required
	# (diagnosed, but not yet in hand) for the STILL-OPEN electrical
	# fault, send the player to Storage FIRST rather than naming the
	# work-site room they can't actually finish the job in yet -- the
	# glanceable equivalent of get_work_order_lines()'s own "Required
	# part:" line. Gated on e05 (the repair task itself) being
	# outstanding, not just on required_component_id being non-empty --
	# that field is never reset mid-day (see reset_for_new_day()), so
	# without this gate the hint would wrongly keep showing "GET PART"
	# after the repair is already done and the real next step is to
	# head back and verify it at the Control Room.
	if _day_plan.required_component_id != &"" and not _day_plan.is_task_done(&"e05") and not _has_required_part():
		var pn: String = preload("res://scripts/station/part_names.gd").short(_day_plan.required_component_id)
		_watch_rig.set_watch_text("GET PART\nSTORAGE" if pn == "16GA" else "GET PART %s\nSTORAGE" % pn)
		return
	var action: String
	if room == &"control_room":
		action = "CHECK IN" if not _day_plan.is_task_done(&"c01") else "VERIFY REPAIR"
	else:
		action = "TASK: %s" % String(_day_plan.assignment_task_id).to_upper() if _day_plan.assignment_task_id != &"" else "IN PROGRESS"
	_watch_rig.set_watch_text("%s\n%s" % [action, String(room).replace("_", " ").to_upper()])


func _has_required_part() -> bool:
	if _carry_system == null:
		return true # unknown -- don't block the normal message if unwired
	return _carry_system.is_carrying() and _carry_system.carried_item_id() == _day_plan.required_component_id
