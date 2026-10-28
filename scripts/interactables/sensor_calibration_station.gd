extends StaticBody3D
## Life Support's environmental sensor calibration unit -- implements
## L07 Environmental Sensor Calibration, the ONE locked task in
## GAME_DESIGN.md's Task Database (Section 29) whose own documented
## description -- "Adjust dial/knob until readings converge" -- already
## matches this milestone's contrasting calibration prototype
## (continuous adjustment + convergence) with no invented task
## identity. No other candidate task in the catalog is described this
## way; L07 was chosen for that reason, not arbitrarily (see
## MILESTONE1_DESIGN.md's record of this round).
##
## One small prop, one duck-typed interact() -- same "each physical
## object owns its own small state" convention as every other
## interactable in this project (GAME_DESIGN.md Section 48). The only
## state this script itself owns is a thin pass-through to DayPlan's
## l07_status; the actual calibration gameplay lives entirely in
## scripts/ui/sensor_calibration_view.gd.

@export var day_plan_path: NodePath
@export var calibration_view_path: NodePath

## Round 16 Priority 8: how many of the three chambers start faulted --
## a property of THIS WORK-ORDER instance/scenario, exported per
## station rather than looked up from global difficulty. Round 15 kept
## this mechanic (fault count scaling with the number of simultaneous
## problems the player must manage) but implemented it by keying
## straight off GameSettings.get_difficulty() (1 fault on EASY, 2 on
## NORMAL, 3 on HARD) -- which conflates two things the brief asks to
## stay separate: global difficulty (how forgiving the tolerance/
## coupling/stability-hold requirement are, still difficulty-keyed
## below in sensor_calibration_view.gd) and task PROGRESSION (how many
## simultaneous problems this particular assignment presents). An EASY-
## difficulty player and a HARD-difficulty player attempting this same
## station now face the identical fault count (this export's value) --
## only how forgiving the attempt is differs by difficulty, exactly as
## the brief's own "allow early assignments to be simple on any global
## difficulty, with advanced assignments becoming more complex through
## progression" describes. This project has no actual day/assignment
## progression system yet (day_plan.gd's own doc comment: "no
## calendar, no day counter" -- and this round explicitly does not add
## one), so for now this is a single exported value on the one L07
## station instance rather than something a real scenario-selector
## picks; the seam is real (a future second station/scenario would
## just export a different value here), even though only one scenario
## exists today.
## Round 18 Priority 3: no longer read by sensor_calibration_view.gd --
## the player's own explicit instruction this round ties the required-
## calibration count to DIFFICULTY (randomized within a per-difficulty
## range each attempt), superseding this export's whole premise. Left
## in place (not deleted) only because it is still a harmless, unused
## @export; a future round could repurpose or remove it.
@export_range(1, 3, 1) var fault_count: int = 2

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _calibration_view: Node = get_node_or_null(calibration_view_path)


func active_fault_count() -> int:
	return clampi(fault_count, 1, 3)


func interact() -> void:
	if _calibration_view == null:
		return
	_calibration_view.open_station(self)


func get_interact_prompt() -> String:
	if _day_plan.is_task_done(&"l07"):
		return "Click: Check Sensor Calibration (Nominal)"
	return "Click: Calibrate Environmental Sensor"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"l07")


## Called by sensor_calibration_view.gd once the reading has stabilized
## inside tolerance for the required duration -- the one and only
## commit point; opening the view, or any amount of unstable adjusting,
## never calls this.
func mark_complete() -> void:
	_day_plan.mark_done(&"l07")
