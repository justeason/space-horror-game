extends Node
## Minimal, explicitly-typed day/task state for Milestone 1's first two
## playable slices (Slice A + Slice B). Deliberately NOT a generic task
## registry -- see GAME_DESIGN.md Section 47 and MILESTONE1_DESIGN.md
## Part 7.1.1. Each locked task gets its own named field; a future
## task-selector (MILESTONE1_DESIGN.md Open Question 6 / the roadmap's
## planned weighted task-selection system) is expected to read/write
## these same fields and grow new ones following the same pattern, not
## replace this with a dictionary-based registry.
##
## A plain scene node (instanced in main.tscn alongside SleepState),
## NOT an autoload/singleton -- Approved Decision A.9.

enum TaskStatus { PENDING, DONE }

# -- Slice A: Control -> Engineering -> Control --
var c01_status: TaskStatus = TaskStatus.PENDING
## Set once C01 completes. Hardcoded/pinned to "e06" for Slice A (see
## MILESTONE1_DESIGN.md Open Question 6: the eventual random task
## selector replaces only this one assignment line, not C01 itself).
var assignment_task_id: StringName = &""
var e06_status: TaskStatus = TaskStatus.PENDING
var c05_status: TaskStatus = TaskStatus.PENDING

# -- Slice B: Control -> Engineering -> Storage -> Engineering -> Control --
var c02_status: TaskStatus = TaskStatus.PENDING
## Set by C02; read by the electrical panel (E01/E02/E05) and S01's
## wire bin. Pinned to "engineering_power" for Slice B.
var fault_target: StringName = &""
var e01_status: TaskStatus = TaskStatus.PENDING
var e02_status: TaskStatus = TaskStatus.PENDING
## Set by E02 once the circuit is traced -- the single source of truth
## S01/E05 check the carried item against. Shown to the player
## directly (Approved Decision A.4's default: component hints visible
## until a difficulty system exists to gate them -- see
## show_component_hint()).
var required_component_id: StringName = &""
var e05_status: TaskStatus = TaskStatus.PENDING

# -- Sensor calibration prototype: L07 Environmental Sensor Calibration
# (Life Support), this milestone's contrasting calibration task. --
var l07_status: TaskStatus = TaskStatus.PENDING

## Round 14 Priority 5 prototype: Coolant Loop Valve Routing (Life
## Support) -- a second free-standing contrasting task, same
## independent-of-the-Slice-A/B-chain status as L07 above. NOTE (Round
## 15 audit): "l08" does not actually match GAME_DESIGN.md Section 29's
## catalog entry for L08 ("Pump Diagnosis") -- this ID was assigned
## before the catalog cross-check Round 15 now requires for new tasks.
## Left as-is rather than renamed, since renaming an existing task ID
## key (not just its label) risks breaking any saved understanding of
## what "l08" means without a corresponding real need this round; see
## MILESTONE1_DESIGN.md's Round 15 entry for the full note. Round 15's
## OWN new task (l02, below) was cross-checked against the catalog
## first specifically to not repeat this.
var l08_status: TaskStatus = TaskStatus.PENDING

## Round 15 Priority 4: L02 Filter Replacement (Life Support) --
## GAME_DESIGN.md Section 29's own catalog entry, matched by ID (not
## just by similar theme): "Isolate airflow -> close valves ->
## depressurize -> remove -> match -> install -> restore valves in
## correct order -> verify." A third free-standing contrasting task,
## same independent-of-the-Slice-A/B-chain status as L07/l08 above.
var l02_status: TaskStatus = TaskStatus.PENDING

## Round 15 Priority 5: E09 Diagnose Intermittent Electrical Fault
## (Engineering) -- GAME_DESIGN.md Section 28's own catalog entry.
## Deliberately NOT built on top of E02 Trace Electrical Circuit:
## E02's existing single-click completion is woven into Slice B's
## tested dependency chain (S01/E05/the workstation diagnostic all key
## off its exact current behavior), and the brief's own "do not
## invalidate completed work or create duplicate task-completion
## events" ruled out changing it. E09 is a genuine, previously-
## unimplemented catalog entry with no dependency chain of its own, so
## building the new probe/test-point mechanic there is both the safer
## AND the more catalog-correct choice. Free-standing, same
## independent-of-the-Slice-A/B-chain status as L07/l08/l02 above.
var e09_status: TaskStatus = TaskStatus.PENDING

## Round 16 Priority 7: M02 Signal Calibration (Communications) --
## GAME_DESIGN.md Section 30's own catalog entry ("Tune signal using a
## physical dial/control and observe the result"), matched by ID. A
## genuinely new maintenance activity in kind: continuous two-
## parameter (frequency + gain) tuning toward a fixed hidden target,
## completed only once signal quality is SUSTAINED above threshold for
## a few continuous seconds -- distinct from every other task here
## (not a discrete sequence, not a single toggle, not alignment/
## insertion, not evidence-based point-and-diagnose). Free-standing,
## same independent-of-the-Slice-A/B-chain status as L07/l08/l02/e09
## above.
var m02_status: TaskStatus = TaskStatus.PENDING

signal assignment_changed(task_id: StringName)
signal task_completed(task_id: StringName)


func is_task_done(task_id: StringName) -> bool:
	match task_id:
		&"c01": return c01_status == TaskStatus.DONE
		&"e06": return e06_status == TaskStatus.DONE
		&"c05": return c05_status == TaskStatus.DONE
		&"c02": return c02_status == TaskStatus.DONE
		&"e01": return e01_status == TaskStatus.DONE
		&"e02": return e02_status == TaskStatus.DONE
		&"e05": return e05_status == TaskStatus.DONE
		&"l07": return l07_status == TaskStatus.DONE
		&"l08": return l08_status == TaskStatus.DONE
		&"l02": return l02_status == TaskStatus.DONE
		&"e09": return e09_status == TaskStatus.DONE
		&"m02": return m02_status == TaskStatus.DONE
	return false


func mark_done(task_id: StringName) -> void:
	match task_id:
		&"c01": c01_status = TaskStatus.DONE
		&"e06": e06_status = TaskStatus.DONE
		&"c05": c05_status = TaskStatus.DONE
		&"c02": c02_status = TaskStatus.DONE
		&"e01": e01_status = TaskStatus.DONE
		&"e02": e02_status = TaskStatus.DONE
		&"e05": e05_status = TaskStatus.DONE
		&"l07": l07_status = TaskStatus.DONE
		&"l08": l08_status = TaskStatus.DONE
		&"l02": l02_status = TaskStatus.DONE
		&"e09": e09_status = TaskStatus.DONE
		&"m02": m02_status = TaskStatus.DONE
	task_completed.emit(task_id)


## Slice A's pinned daily assignment -- the one seam a future weighted
## task selector replaces (see the class doc comment). Idempotent.
func assign_daily_task() -> void:
	if assignment_task_id != &"":
		return
	assignment_task_id = &"e06"
	assignment_changed.emit(assignment_task_id)


## Slice B's pinned fault -- same seam, a different chain. Idempotent.
func trigger_fault() -> void:
	if fault_target != &"":
		return
	fault_target = &"engineering_power"


func set_required_component(component_id: StringName) -> void:
	required_component_id = component_id


## Whether the component spec should currently be shown to the player.
## Always true until a real Easy/Hard difficulty system exists --
## Approved Decision A.4 asks only that this be its own decision point
## (so a future difficulty setting can gate it) without requiring any
## task logic to be rewritten once that system exists.
func show_component_hint() -> bool:
	return true


## Single source of truth for "what are the open work orders right
## now," in plain text lines -- shared by workstation_screen.gd's Work
## Orders section and the wristwatch view (scripts/player/wristwatch_view.gd)
## so both read the exact same authoritative summary instead of each
## formatting their own copy. `electrical_panel_repaired` is passed in
## rather than read directly here because DayPlan has no reference to
## the physical panel prop (Approved Decision A.9: DayPlan is plain task
## state, not a scene-graph hub). `required_part_color_name` is passed
## in the same way (Round 16 Priority 3: which wire is at fault, and
## therefore which color the required spare actually is, now varies per
## repair-instance config instead of always being "yellow" -- the
## caller already holds the panel reference this needs).
func get_work_order_lines(electrical_panel_repaired: bool, required_part_color_name: String = "yellow") -> Array[String]:
	var lines: Array[String] = []
	if assignment_task_id == &"e06":
		var status := "DONE" if is_task_done(&"e06") else "PENDING"
		lines.append("E06 Tighten Loose Connection — Engineering [%s]" % status)
	if fault_target == &"engineering_power":
		lines.append("Electrical Fault — Engineering [%s]" % ("REPAIRED" if electrical_panel_repaired else "OPEN"))
		if required_component_id != &"" and show_component_hint():
			lines.append("  Required part: Control Wire (16-gauge, %s)" % required_part_color_name.to_lower())
	if lines.is_empty():
		lines.append("No open work orders.")
	return lines


## Which room the player should head to next, derived purely from
## existing task fields (no new state) -- used by the Control Room
## station map to highlight "the room associated with the current
## outstanding task." A simple fixed priority order over the two
## existing slices; returns &"" once nothing is outstanding.
func get_outstanding_task_room() -> StringName:
	if not is_task_done(&"c01"):
		return &"control_room"
	if assignment_task_id == &"e06" and not is_task_done(&"e06"):
		return &"engineering"
	if fault_target == &"engineering_power" and not is_task_done(&"e05"):
		return &"engineering"
	if not is_task_done(&"c05") and (is_task_done(&"e06") or is_task_done(&"e05")):
		return &"control_room"
	return &""


## The minimal reset (Approved Decision A.1, Option A): clears every
## field back to its start-of-day value. No calendar, no day counter,
## no simulation-time system -- see MILESTONE1_DESIGN.md Open
## Question 1.
func reset_for_new_day() -> void:
	c01_status = TaskStatus.PENDING
	assignment_task_id = &""
	e06_status = TaskStatus.PENDING
	c05_status = TaskStatus.PENDING
	c02_status = TaskStatus.PENDING
	fault_target = &""
	e01_status = TaskStatus.PENDING
	e02_status = TaskStatus.PENDING
	required_component_id = &""
	e05_status = TaskStatus.PENDING
	l07_status = TaskStatus.PENDING
	l08_status = TaskStatus.PENDING
	l02_status = TaskStatus.PENDING
	e09_status = TaskStatus.PENDING
	m02_status = TaskStatus.PENDING
