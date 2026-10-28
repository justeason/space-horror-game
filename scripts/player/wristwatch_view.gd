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

@onready var _day_plan: Node = get_node_or_null(day_plan_path)
@onready var _electrical_panel: Node = get_node_or_null(electrical_panel_path)
@onready var _interaction_controller: Node = get_node_or_null(interaction_controller_path)
@onready var _watch_rig: Node = get_node(watch_rig_path)


func _process(_delta: float) -> void:
	var held: bool = Input.is_key_pressed(KEY_C)
	var allowed: bool = _interaction_controller == null or _interaction_controller.interactions_enabled
	var should_raise: bool = held and allowed
	var was_raised: bool = _watch_rig.is_raised()

	if should_raise != was_raised:
		_watch_rig.set_raised(should_raise, raise_duration)

	if should_raise:
		# Keep it live while held -- e.g. marking a task done elsewhere
		# while the player happens to be holding the watch up should be
		# reflected immediately, not only at the moment it was raised.
		_refresh_text()


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
	var room: StringName = _day_plan.get_outstanding_task_room()
	if room == &"":
		_watch_rig.set_watch_text("ALL CLEAR")
		return
	var action: String
	if room == &"control_room":
		action = "CHECK IN" if not _day_plan.is_task_done(&"c01") else "VERIFY REPAIR"
	else:
		action = "TASK: %s" % String(_day_plan.assignment_task_id).to_upper() if _day_plan.assignment_task_id != &"" else "IN PROGRESS"
	_watch_rig.set_watch_text("%s\n%s" % [action, String(room).replace("_", " ").to_upper()])
