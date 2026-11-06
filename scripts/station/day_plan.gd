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
const PART_NAMES = preload("res://scripts/station/part_names.gd")
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
	if _SERVICE_TASK.has(task_id):
		var w: int = _SERVICE_TASK[task_id]
		_serviced[w] = day_number
		service_history.append({"day": day_number, "workday": w})
		log_event("Serviced: %s" % String(WORKDAY_TITLES.get(w, "equipment")).get_slice(" —", 0))
	task_completed.emit(task_id)


## Slice A's pinned daily assignment -- the one seam a future weighted
## task selector replaces (see the class doc comment). Idempotent.
func assign_daily_task() -> void:
	if assignment_task_id != &"":
		return
	if workday != Workday.NONE:
		# Workday days: the authored workday is the assignment (no E06).
		assignment_changed.emit(&"")
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
			lines.append("  Required part: %s" % PART_NAMES.display(required_component_id, required_part_color_name))
	if workday != Workday.NONE:
		lines.append_array(workday_lines())
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
	if workday == Workday.NONE and not is_task_done(&"c05") and (is_task_done(&"e06") or is_task_done(&"e05")):
		return &"control_room"
	if workday != Workday.NONE and not is_work_order_closed():
		# Round 32: a CLOSED order leaves nothing outstanding (an optional
		# step left unticked must not keep pointing the player back).
		var step: Dictionary = next_workday_step()
		if not step.is_empty():
			return step["room"]
	return &""


## The minimal reset (Approved Decision A.1, Option A): clears every
## field back to its start-of-day value. No calendar, no day counter,
## no simulation-time system -- see MILESTONE1_DESIGN.md Open
## Question 1.
## Round 31 Priority 8: a short daily MAINTENANCE LOG written by the real
## equipment (installs, disposals, restocks, services) and shown in the
## workstation's Work Orders section.
var _day_log: Array[String] = []


func log_event(text: String) -> void:
	_day_log.append(text)


func day_log() -> Array[String]:
	return _day_log.duplicate()


## Supply warnings from the real shelf/reserve counts (no hardcoding).
func supply_warnings() -> Array[String]:
	var out: Array[String] = []
	if not is_inside_tree():
		return out
	for w in blocked_services:
		out.append("BLOCKED: %s — awaiting supplies (next cargo day %d)" % [String(WORKDAY_TITLES.get(w, "service")).get_slice(" —", 0), next_cargo_day])
	if _cargo_port != null and _cargo_port.is_busy():
		out.append("CARGO %s: %s at the airlock port — %s" % [_cargo_port.shipment_id, _cargo_port.status_word(), _cargo_port._manifest_text(" · ")])
	elif _cargo_port != null:
		out.append("CARGO: next shipment day %d" % next_cargo_day)
	var reserve := {}
	for r in get_tree().get_nodes_in_group(&"supply_reserve"):
		for id in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
			reserve[id] = reserve.get(id, 0) + r.reserve_count(id)
	for c in get_tree().get_nodes_in_group(&"storage_cabinet"):
		for t in c.stock_types():
			if c.is_stock_low(t):
				var name: String = PART_NAMES.short(t)
				var res: int = reserve.get(t, 0)
				var fix: String = ("RESTOCK FROM RESERVE (%d)" % res) if res > 0 else "RESERVE EMPTY — AWAIT CARGO"
				out.append("SUPPLY: %s STOCK LOW (%d) — %s" % [name, c.stock_count(t), fix])
	# Round 32 Priority 7: one compact stock line (shelf + reserve, real
	# counts) and one upcoming-maintenance line.
	var stock: Array[String] = []
	for t in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
		var shelf := 0
		for c in get_tree().get_nodes_in_group(&"storage_cabinet"):
			shelf += c.stock_count(t)
		stock.append("%s %d+%d" % [PART_NAMES.short(t), shelf, reserve.get(t, 0)])
	out.append("STOCK (shelf+reserve): " + " · ".join(stock))
	var up: Array[String] = []
	for e in upcoming_services():
		up.append("%s day %d" % [_SERVICE_SHORT.get(e["workday"], "?"), e["day"]])
	if not up.is_empty():
		out.append("UPCOMING: " + " · ".join(up))
	return out


const _SERVICE_SHORT := {Workday.FILTER_SERVICE: "FILTER", Workday.CALIBRATION: "CALIB", Workday.ELECTRICAL_SERVICE: "ELEC", Workday.COOLANT_INSPECTION: "COOLANT"}


## Round 32 Priority 7: when each already-serviced system next comes due
## (last service + its interval), soonest first. Systems with an order
## open today are not listed. Derived from the same service log the
## scheduler uses -- not a second schedule.
func upcoming_services() -> Array:
	var out: Array = []
	for w in workday_rotation:
		if _serviced.has(w) and _rearm.has(w):
			out.append({"workday": w, "day": maxi(day_number + 1, int(_serviced[w]) + int(SERVICE_INTERVAL_DAYS.get(w, 0)))})
	out.sort_custom(func(a, b): return a["day"] < b["day"])
	return out


# ======================================================================
# Round 32 Priority 3: cargo resupply schedule.
# ======================================================================
## Shipments arrive at the airlock cargo port every CARGO_INTERVAL_DAYS from
## FIRST_CARGO_DAY. Each manifest is the shortfall between total storage
## capacity (shelf slots + reserve slots) and parts on hand (shelf +
## reserve + still in the port), capped by the port's cargo slots -- a
## finite resupply, never unlimited. A port still busy with the previous
## shipment delays the next one by a day.
const FIRST_CARGO_DAY: int = 3
const CARGO_INTERVAL_DAYS: int = 4
var next_cargo_day: int = FIRST_CARGO_DAY
var cargo_history: Array = []   # [{"day", "id", "manifest"}]
var _cargo_port: Node = null


func register_cargo_port(port: Node) -> void:
	_cargo_port = port


func cargo_port() -> Node:
	return _cargo_port


func cargo_needs() -> Dictionary:
	var out := {}
	if not is_inside_tree():
		return out
	for t in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
		var cap := 0
		var have := 0
		for c in get_tree().get_nodes_in_group(&"storage_cabinet"):
			cap += c.capacity(t)
			have += c.stock_count(t)
		for r in get_tree().get_nodes_in_group(&"supply_reserve"):
			cap += r.capacity(t)
			have += r.reserve_count(t)
		if _cargo_port != null:
			have += _cargo_port.parts_in_port(t)
		out[t] = maxi(cap - have, 0)
	return out


func _run_cargo_schedule() -> void:
	if _cargo_port == null or day_number < next_cargo_day:
		return
	if _cargo_port.is_busy():
		next_cargo_day = day_number + 1
		return
	var needs: Dictionary = cargo_needs()
	var id := "CS-%04d" % (cargo_history.size() + 1)
	if _cargo_port.receive_shipment(id, needs):
		cargo_history.append({"day": day_number, "id": id, "manifest": _cargo_port.manifest.duplicate()})
		log_event("Cargo %s arrived at the airlock port" % id)
	next_cargo_day = day_number + CARGO_INTERVAL_DAYS


func reset_for_new_day() -> void:
	_day_log.clear()
	day_number += 1
	_run_cargo_schedule()
	_start_next_workday()
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


# ======================================================================
# Round 28 Priority 4: authored maintenance workdays
# ======================================================================
## Day 1 is the existing tutorial slices (Slice A/B, unchanged). From day 2
## (after sleeping), each day runs ONE authored workday from
## `workday_rotation`, built entirely from the existing task fields above
## plus a few named physical FACTS reported by the real world objects
## (a part taken from its storage cabinet, the filter housing inspected,
## the used cartridge disposed, ...). No second task registry: a workday is
## only an ordered list of references to those fields/facts.
##
## Each step has a `phase`, so the three outcomes stay separate:
##   "restore" -- the equipment is operational again,
##   "verify"  -- the repair was verified at the Control Room workstation,
##   "cleanup" -- used parts disposed of,
##   "close"   -- the work order closed (needs verify AND cleanup).
## The equipment can therefore be running while the used filter still
## waits for disposal and the order stays open.
##
## Puzzle/fault configurations are NOT regenerated here: the stations keep
## their own fixed authored instances, so reopening a focused screen never
## re-rolls anything.
enum Workday { NONE, ELECTRICAL_SERVICE, FILTER_SERVICE, CALIBRATION, COOLANT_INSPECTION }

@export var workday_rotation: Array[int] = [Workday.FILTER_SERVICE, Workday.CALIBRATION, Workday.ELECTRICAL_SERVICE, Workday.COOLANT_INSPECTION]

const WORKDAY_TITLES := {
	Workday.COOLANT_INSPECTION: "Coolant Routing Inspection — L08",
	Workday.ELECTRICAL_SERVICE: "Electrical Service — Engineering power circuit",
	Workday.FILTER_SERVICE: "Life Support Filter Service — L02",
	Workday.CALIBRATION: "Pressure Sensor Calibration — L07",
}

## [label, room, kind ("task"/"fact"), key, phase]
const WORKDAY_STEPS := {
	Workday.ELECTRICAL_SERVICE: [
		["Receive work order", &"control_room", "task", &"c01", ""],
		["Review diagnostics", &"control_room", "task", &"c02", ""],
		["Identify the faulty circuit", &"engineering", "task", &"e02", ""],
		["Retrieve replacement wire from Storage", &"storage", "fact", &"retrieved:wire", ""],
		["Repair the panel and restore power", &"engineering", "task", &"e05", "restore"],
		["Verify at the Control Room workstation", &"control_room", "task", &"c05", "verify"],
		["Close the work order", &"control_room", "fact", &"closed", "close"],
	],
	Workday.FILTER_SERVICE: [
		["Receive maintenance assignment", &"control_room", "task", &"c01", ""],
		["Inspect the filter housing", &"life_support", "fact", &"inspected:filter", ""],
		["Retrieve replacement cartridge from Storage", &"storage", "fact", &"retrieved:filter", ""],
		["Replace the cartridge and restore airflow", &"life_support", "task", &"l02", "restore"],
		["Verify operation at the workstation", &"control_room", "fact", &"verified", "verify"],
		["Dispose of the used cartridge", &"storage", "fact", &"disposed:used_filter", "cleanup"],
		["Close the work order", &"control_room", "fact", &"closed", "close"],
	],
	Workday.COOLANT_INSPECTION: [
		["Receive inspection order", &"control_room", "task", &"c01", ""],
		["Re-route coolant at the valve manifold", &"life_support", "task", &"l08", "restore"],
		["Verify flow at the workstation", &"control_room", "fact", &"verified", "verify"],
		["Close the work order", &"control_room", "fact", &"closed", "close"],
	],
	Workday.CALIBRATION: [
		["Receive sensor warning", &"control_room", "task", &"c01", ""],
		["Review the pressure warning in Diagnostics", &"control_room", "fact", &"reviewed:sensor_warning", ""],
		["Calibrate the coupled chambers", &"life_support", "task", &"l07", "restore"],
		["Verify stability at the workstation", &"control_room", "fact", &"verified", "verify"],
		["Close the work order", &"control_room", "fact", &"closed", "close"],
	],
}

var day_number: int = 1
var workday: int = Workday.NONE
var _facts: Dictionary = {}
## Equipment service log (persists across days): workday -> the day its
## equipment was last serviced. Round 29 Priority 8 foundation: replaces
## the Round 28 boolean set. The stations keep their repaired state, so a
## serviced system is only scheduled AGAIN once it is due (see
## SERVICE_INTERVAL_DAYS) AND its equipment has registered a re-arm handler
## (register_service_rearm()) that can put it back into a real, physical
## fault -- no station registers one yet, so the Round 28 behaviour ("every
## system serviced -> no broken work orders") is unchanged.
var _serviced: Dictionary = {}
## Every completed service, in order: {"day": int, "workday": int}.
var service_history: Array = []
## Days after a service before that equipment is due again.
const SERVICE_INTERVAL_DAYS := {Workday.FILTER_SERVICE: 4, Workday.CALIBRATION: 3, Workday.ELECTRICAL_SERVICE: 5, Workday.COOLANT_INSPECTION: 6}
var _rearm: Dictionary = {}
## Round 32: due services that could not be scheduled for lack of parts.
var blocked_services: Array = []
var _feasible: Dictionary = {}
const _SERVICE_TASK := {&"e05": Workday.ELECTRICAL_SERVICE, &"l02": Workday.FILTER_SERVICE, &"l07": Workday.CALIBRATION, &"l08": Workday.COOLANT_INSPECTION}

signal workday_step_completed(label: String)


func record_fact(fact: StringName) -> void:
	if _facts.has(fact):
		return
	_facts[fact] = true
	if workday != Workday.NONE:
		for step in WORKDAY_STEPS[workday]:
			if step[2] == "fact" and step[3] == fact:
				workday_step_completed.emit(step[0])


func has_fact(fact: StringName) -> bool:
	return _facts.has(fact)


func is_workday_active() -> bool:
	return workday != Workday.NONE


func workday_steps() -> Array:
	if workday == Workday.NONE:
		return []
	var out: Array = []
	for step in WORKDAY_STEPS[workday]:
		var done: bool = is_task_done(step[3]) if step[2] == "task" else has_fact(step[3])
		out.append({"label": step[0], "room": step[1], "done": done, "phase": step[4]})
	return out


func _phase_done(phase: String) -> bool:
	var any := false
	for s in workday_steps():
		if s["phase"] == phase:
			any = true
			if not s["done"]:
				return false
	return any


func is_equipment_restored() -> bool:
	return _phase_done("restore")


func is_maintenance_verified() -> bool:
	return _phase_done("verify")


## True when nothing needs cleaning up (or the cleanup is done).
func is_cleanup_complete() -> bool:
	for s in workday_steps():
		if s["phase"] == "cleanup" and not s["done"]:
			return false
	return true


func is_work_order_closed() -> bool:
	return has_fact(&"closed")


## The first not-done step (the one the player should do next), or {}.
func next_workday_step() -> Dictionary:
	for s in workday_steps():
		if not s["done"]:
			return s
	return {}


## Workstation [R] in Work Orders: verifies the repaired equipment, and on
## a later press closes the order once cleanup is done. Returns a short
## status line for the screen.
func workday_verify_or_close() -> String:
	if workday == Workday.NONE:
		return ""
	if not is_equipment_restored():
		return "Verification failed: equipment not yet restored."
	if not is_maintenance_verified():
		match workday:
			Workday.ELECTRICAL_SERVICE:
				mark_done(&"c05")
			_:
				record_fact(&"verified")
		return "Verified: equipment operating normally."
	if not is_cleanup_complete():
		return "Order stays open: used parts still awaiting disposal."
	if not is_work_order_closed():
		record_fact(&"closed")
		return "Work order closed."
	return "Work order already closed."


func workday_lines() -> Array[String]:
	var lines: Array[String] = []
	if workday == Workday.NONE:
		return lines
	lines.append("DAY %d — %s" % [day_number, WORKDAY_TITLES[workday]])
	for s in workday_steps():
		lines.append("  [%s] %s" % ["x" if s["done"] else " ", s["label"]])
	var status: String = "OPEN"
	if is_work_order_closed():
		status = "CLOSED"
	elif is_maintenance_verified() and not is_cleanup_complete():
		status = "VERIFIED — cleanup pending"
	elif is_equipment_restored():
		status = "RESTORED — verification pending"
	lines.append("  Status: " + status)
	return lines


func _start_next_workday() -> void:
	_facts.clear()
	workday = Workday.NONE
	if day_number < 2 or workday_rotation.is_empty():
		return
	var n: int = workday_rotation.size()
	for i in n:
		var w: int = workday_rotation[(day_number - 2 + i) % n]
		if not _serviced.has(w):
			workday = w
			return
	# Everything has been serviced at least once: schedule the first DUE
	# system whose equipment can genuinely re-fault.
	blocked_services.clear()
	for i in n:
		var w: int = workday_rotation[(day_number - 2 + i) % n]
		if is_service_due(w) and _rearm.has(w) and not is_service_feasible(w):
			# Round 32: a due service with no usable part is NOT erased -- it
			# is BLOCKED, awaiting supplies (cargo / restock), and shown.
			blocked_services.append(w)
	for i in n:
		var w: int = workday_rotation[(day_number - 2 + i) % n]
		if is_service_due(w) and _rearm.has(w) and is_service_feasible(w):
			(_rearm[w] as Callable).call(daily_variant_seed(w))
			_serviced.erase(w)
			workday = w
			return


func is_equipment_serviced(w: int) -> bool:
	return _serviced.has(w)


## Round 29 Priority 8 foundation API.
func last_serviced_day(w: int) -> int:
	return _serviced.get(w, -1)


func days_since_service(w: int) -> int:
	return day_number - _serviced[w] if _serviced.has(w) else -1


func is_service_due(w: int) -> bool:
	return _serviced.has(w) and days_since_service(w) >= SERVICE_INTERVAL_DAYS.get(w, 999999)


## A station opts in to recurring work by registering a handler that puts
## its equipment back into a real fault for a new work order; the handler
## receives daily_variant_seed() so e.g. calibration targets can vary per
## day without re-rolling within a day.
func register_service_rearm(w: int, handler: Callable, feasible: Callable = Callable()) -> void:
	_rearm[w] = handler
	if feasible.is_valid():
		_feasible[w] = feasible


## Round 31: never schedule an impossible work order -- e.g. a filter
## service with no clean cartridge on the shelf or in the reserve.
func is_service_feasible(w: int) -> bool:
	return not _feasible.has(w) or bool((_feasible[w] as Callable).call())


func has_service_rearm(w: int) -> bool:
	return _rearm.has(w)


## Deterministic per (day, workday): the same day always yields the same
## variant (no re-rolling on reopen), a different day a different one.
func daily_variant_seed(w: int = -1) -> int:
	return hash([day_number, w if w >= 0 else workday])
