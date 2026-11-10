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
## Round 42: a work order closed (its equipment reports the fault fixed).
signal order_closed(type: StringName)
## Round 33: emitted after the new day's state is set up (sleep -> wake),
## so screens (workstation, laptop) can show which day it is.
signal day_started(day: int)


func _ready() -> void:
	add_to_group(&"day_plan")
	var v: CanvasLayer = preload("res://scripts/ui/fatigue_vignette.gd").new()
	v.name = "FatigueVignette"
	add_child(v)
	# Round 44: the consultable station records + positional station sounds.
	var lg: Node = preload("res://scripts/station/station_log.gd").new()
	lg.name = "StationLog"
	add_child(lg)
	var snd: Node = preload("res://scripts/audio/station_sounds.gd").new()
	snd.name = "StationSounds"
	add_child(snd)
	preload("res://scripts/station/game_settings.gd").apply_one.call_deferred("brightness")


# ======================================================================
# Round 34 Priority 3: the DAILY SHIFT CLOCK. Counts real active gameplay
# (this node's _process: stops while the tree is paused; menus and loading
# are other scenes). Sleeping is only permitted once the shift has ended;
# the player is never moved -- they may keep working (overtime).
# ======================================================================
const GameConfig = preload("res://scripts/station/game_config.gd")
var shift_elapsed_s: float = 0.0
var shift_ended: bool = false
signal shift_ended_signal(day: int)
## Round 34 Priority 4: brief, unobtrusive player notifications.
signal notify(text: String)
@export var message_label_path: NodePath = ^"../Player/HUD/TaskMessageLabel"


# ======================================================================
# Round 43 Priorities 1/7: CLOCK HOLDS. The station clock (shift time,
# post-shift grace, everything derived from it: scheduled emergencies, the
# orbit, tiredness) only runs while the DAY IS ACTIVE and nothing holds it:
#   - day_active: false from the new-day reset (eyes closed) until the
#     technician is up -- out of the lying position. Waking, the wake
#     animation and lying in the bunk never consume work time, so a new
#     day reads exactly 08:00 when the technician sits up.
#   - holds: named reasons (&"entertainment" while a personal laptop GAME
#     is actively played; future reasons may join). Holds never stack time:
#     releasing simply lets the next frame advance by its own delta (no
#     catch-up jump, no duplicate timer).
# EMERGENCY POLICY: games are refused while a real timed emergency is
# active (entertainment_allowed()); if one starts while a game is open the
# game pauses itself and the hold is released at once, so the real
# countdown is never frozen by entertainment (laptop_view / session_log).
# Continuous equipment physics in other nodes keeps running -- but nothing
# SCHEDULED happens while the clock is held (scheduled events are keyed to
# shift_elapsed_s), so a calm station stays calm.
# ======================================================================
var day_active: bool = false
var _holds: Dictionary = {}
signal clock_hold_changed(paused: bool)


func hold_clock(reason: StringName, on: bool) -> void:
	var was: bool = clock_paused()
	if on:
		_holds[reason] = true
	else:
		_holds.erase(reason)
	if was != clock_paused():
		clock_hold_changed.emit(clock_paused())


func is_held(reason: StringName) -> bool:
	return _holds.has(reason)


func clock_paused() -> bool:
	return not day_active or not _holds.is_empty()


func clock_hold_reasons() -> Array:
	var out: Array = _holds.keys()
	if not day_active:
		out.push_front(&"waking")
	return out


## {"ok": bool, "reason": String}: may a personal entertainment app run now?
func entertainment_allowed() -> Dictionary:
	var ss: Node = get_tree().get_first_node_in_group(&"station_status") if is_inside_tree() else null
	if ss != null and ss.has_method("emergency") and not ss.emergency().is_empty():
		return {"ok": false, "reason": "STATION ALERT — %s. Games are locked until it is resolved." % String(ss.emergency().get("title", "EMERGENCY"))}
	if _eva_active():
		return {"ok": false, "reason": "Not while suited up."}
	var env: Node = get_node_or_null(^"../EnvironmentModel")
	if env != null and int(env.get("severity")) > 0:
		return {"ok": false, "reason": "AIR QUALITY ALARM. Deal with it first."}
	return {"ok": true, "reason": ""}


# ======================================================================
# Round 44 Priority 1: TIME DOMAINS (one authority, this node).
#   GAMEPLAY TIME  -- the shift clock and everything keyed to it (orbit,
#                     scheduled emergencies, routines, bedtime grace,
#                     tiredness, ordinary environment drift via
#                     gameplay_delta()). Held by named reasons:
#                     &"waking" (implicit), &"laptop" (focused personal
#                     laptop, ANY app), &"entertainment" (legacy name).
#   UI TIME        -- laptop navigation, app animations, minigames: real
#                     frame delta, never held.
#   CRITICAL TIMERS-- a live emergency's own countdown (equipment
#                     emergency_info) is never held: focused laptop use is
#                     refused during one, and one that starts during laptop
#                     focus ends the focus at once (session_log_screen).
#   STORY PRESENTATION / AUDIO -- run on real time (a story event may play
#                     while the clock is held; audio is never paused).
# ======================================================================
func laptop_focus_allowed() -> Dictionary:
	return entertainment_allowed()


## The delta gameplay systems outside DayPlan should advance by.
func gameplay_delta(delta: float) -> float:
	return 0.0 if clock_paused() else delta


## The day starts once the technician is up (sleep_state reports not
## sleeping / not lying). Polled, so every path (new game, autosave load,
## a mid-day load, tests without a bunk) resolves without bespoke calls.
func _poll_day_active() -> void:
	if day_active:
		return
	var ss: Node = get_node_or_null(^"../SleepState")
	if ss == null or not ss.has_method("is_lying_in_bed") or (not ss.is_lying_in_bed() and not ss.is_sleeping()):
		day_active = true
		clock_hold_changed.emit(clock_paused())


func _process(delta: float) -> void:
	_poll_day_active()
	if clock_paused():
		delta = 0.0
	if not shift_ended:
		shift_elapsed_s += delta
		if shift_elapsed_s >= shift_duration_s():
			_end_shift()
		else:
			_poll_work_complete()
	elif _eva_active():
		# Round 42 Priority 32: never push the technician to bed while they
		# are suited / outside / cycling the airlock -- the post-shift grace
		# period (and tiredness) only runs once they are safely back inside.
		pass
	elif delta > 0.0:
		awake_after_shift_s += delta
		# Gentle reminders once the grace period is over (then every 90 s).
		if awake_after_shift_s >= BED_GRACE_S:
			var n: int = 1 + int((awake_after_shift_s - BED_GRACE_S) / 90.0)
			if n > _bed_reminders:
				_bed_reminders = n
				_ai_event(&"bed_reminder")
	_poll_emergency()
	_poll_cargo_duty()
	_poll_orders()
	_apply_body_state()


# ======================================================================
# Round 39 Priority 7: the shift is measured by WORK, not by a bare clock.
# shift_progress() is the share of today's required work that is done
# (main workday steps, open work orders, cargo duty, check-in and the
# daily MEAL routine). When it reaches 100% a short WRAP-UP period
# starts; then the shift ends and the technician is expected back in
# the bunk (awake_after_shift_s grows; after BED_GRACE_S they slowly
# become tired: slower walking, a dimming vignette, an assistant
# reminder). The old clock remains the hard end of the working day:
# when it runs out, unfinished work carries over as before.
# ======================================================================
const WRAP_UP_S := 45.0
const BED_GRACE_S := 60.0
const TIRED_RAMP_S := 90.0
var work_done_at_s: float = -1.0     # shift_elapsed_s when required work completed
var awake_after_shift_s: float = 0.0
var _bed_reminders: int = 0
signal work_complete(day: int)


func required_work_complete() -> bool:
	if not is_task_done(&"c01"):
		return false
	for r in order_rows():
		if not r.get("done", false):
			return false
	return true


## 0..1: done share of today's required work (partial credit for the
## main workday's steps and the meal routine's two halves).
func shift_progress() -> float:
	if shift_ended:
		return 1.0
	var total: float = 1.0
	var done: float = 1.0 if is_task_done(&"c01") else 0.0
	for r in order_rows():
		total += 1.0
		if r.get("done", false):
			done += 1.0
		else:
			var pr: String = String(r.get("progress", ""))
			if pr.find("/") != -1:
				var a: float = float(pr.get_slice("/", 0))
				var b: float = float(pr.get_slice("/", 1))
				if b > 0.0:
					done += clampf(a / b, 0.0, 0.95)
	return clampf(done / total, 0.0, 1.0)


func is_wrapping_up() -> bool:
	return not shift_ended and work_done_at_s >= 0.0


func wrap_up_remaining_s() -> float:
	return maxf(WRAP_UP_S - (shift_elapsed_s - work_done_at_s), 0.0) if is_wrapping_up() else 0.0


## One compact status for the laptop clock / workstation header.
## Round 42: the clock is STATION TIME; work progress is a separate
## quantity (shown as WORK nn% where it is useful, never as the time).
func shift_status_text() -> String:
	if shift_ended:
		return "DAY %d · %s · REST" % [day_number, clock_text_hhmm()]
	if is_wrapping_up():
		return "DAY %d · %s · WRAP UP" % [day_number, clock_text_hhmm()]
	return "DAY %d · %s · WORK %d%%" % [day_number, clock_text_hhmm(), int(round(shift_progress() * 100.0))]


# ======================================================================
# Round 42 Priority 31: the in-world STATION CLOCK. Four separate
# quantities, never mixed up:
#   A. clock time   -- 08:00 at wake-up, the nominal shift runs to 16:00;
#                      game time advances at shift_duration_s() real
#                      seconds per 8 station hours (configurable, ~10 real
#                      minutes), continuously through overtime;
#   B. shift length -- shift_duration_s() (the hard end of the work period);
#   C. work done    -- shift_progress() (Operations / shift summary only);
#   D. emergencies  -- their own countdown (StationStatus).
# A new day restarts at 08:00 (shift_elapsed_s / awake_after_shift_s reset).
# ======================================================================
const CLOCK_START_MIN := 8 * 60
const CLOCK_SHIFT_MIN := 8 * 60


func clock_minutes() -> int:
	var real_s: float = shift_elapsed_s + (awake_after_shift_s if shift_ended else 0.0)
	var m: float = CLOCK_START_MIN + real_s * CLOCK_SHIFT_MIN / maxf(shift_duration_s(), 1.0)
	return mini(int(m), 23 * 60 + 59)


func clock_text_hhmm() -> String:
	var m: int = clock_minutes()
	return "%02d:%02d" % [m / 60, m % 60]


func shift_end_text() -> String:
	var m: int = CLOCK_START_MIN + CLOCK_SHIFT_MIN
	return "%02d:%02d" % [m / 60, m % 60]


func _poll_work_complete() -> void:
	if required_work_complete():
		if work_done_at_s < 0.0:
			work_done_at_s = shift_elapsed_s
			log_event("Required work complete")
			_notify("Work complete. Wrap up, then rest.")
			work_complete.emit(day_number)
			_ai_event(&"work_complete")
		elif shift_elapsed_s - work_done_at_s >= WRAP_UP_S:
			_end_shift()
	else:
		work_done_at_s = -1.0        # new work appeared (e.g. an emergency)


## 0..1 tiredness from staying up after the shift ended.
func tiredness() -> float:
	if not shift_ended:
		return 0.0
	return clampf((awake_after_shift_s - BED_GRACE_S) / TIRED_RAMP_S, 0.0, 1.0)


func _ai_event(key: StringName) -> void:
	if is_inside_tree():
		get_tree().call_group(&"station_ai", &"event", key)


func bed_required() -> bool:
	return shift_ended


## Movement factor from body state (underfed: 0.85; tired: down to 0.7).
func movement_factor() -> float:
	var f: float = 0.85 if underfed else 1.0
	return f * lerpf(1.0, 0.7, tiredness())


func _apply_body_state() -> void:
	var fb: Node = get_node_or_null(^"../FreeMoveBody")
	if fb != null and "speed_scale" in fb:
		fb.speed_scale = movement_factor()


# ======================================================================
# Round 39 Priority 5: EATING and DRINKING are part of the day. A MEAL
# routine row (Living Quarters) is required work; a day ending without
# both leaves the technician UNDERFED the next day (slower until they
# eat). The quarters galley (quarters_life.gd) owns what was eaten.
# ======================================================================
var meal_required: bool = true
var underfed: bool = false


func _quarters() -> Node:
	return get_tree().get_first_node_in_group(&"quarters_life") if is_inside_tree() else null


func meal_status() -> Dictionary:
	var q: Node = _quarters()
	if q == null:
		return {"ate": true, "drank": true}
	return {"ate": q.ate_today(), "drank": q.drank_today()}


func meal_done() -> bool:
	if not meal_required:
		return true
	var m: Dictionary = meal_status()
	return m["ate"] and m["drank"]


func on_routine_changed() -> void:
	var m: Dictionary = meal_status()
	if m["ate"]:
		underfed = false
	if meal_done():
		log_event("Meal routine done")


func _meal_row() -> Dictionary:
	if not meal_required or _quarters() == null:
		return {}
	var m: Dictionary = meal_status()
	var n: int = int(m["ate"]) + int(m["drank"])
	var action: String = "Breakfast and a drink" if n == 0 else ("Drink" if m["ate"] else "Breakfast")
	return {"id": "MEAL", "tag": "MEAL", "action": action + " at the galley", "short": "BREAKFAST + DRINK" if n == 0 else action.to_upper(), "label": action, "room": &"living_quarters",
		"progress": "%d/2" % n, "done": n == 2, "priority": 1, "carried": false, "severity": 1}


# ======================================================================
# Round 37 Priority 4: EMERGENCIES are uncommon, deterministic events in
# the shift (day seed): from day 5, about one day in four, a Bus A load
# surge at a fixed shift time between 2:00 and 5:00. It acts on the REAL
# power model (power_distribution.surge()): the overload is the
# emergency, its countdown is the real time to the B-03 trip. It opens an
# emergency balancing order (DayPlan stays the one work-order authority);
# never stacked on another open power order's emergency.
# ======================================================================
var emergency_plan: Dictionary = {}   # {day, at_s, kind, seed, fired}


func plan_emergency() -> void:
	emergency_plan = {}
	if day_number < 5:
		return
	var h: int = absi(hash([day_number, "emergency"]))
	if h % 4 != 0:
		return
	if proficiency_level("electrical") < 1:
		return   # Round 38: never before the technician has done electrical work
	emergency_plan = {"day": day_number, "at_s": 120.0 + float(h % 181), "kind": "overload", "seed": h, "fired": false}


func _poll_emergency() -> void:
	if emergency_plan.is_empty() or bool(emergency_plan.get("fired", false)) or int(emergency_plan.get("day", -1)) != day_number:
		return
	if shift_elapsed_s < float(emergency_plan["at_s"]):
		return
	fire_emergency()


## Fires the planned (or a test-requested) emergency now.
func fire_emergency(kind: String = "overload", seed: int = -1) -> void:
	if not emergency_plan.is_empty():
		emergency_plan["fired"] = true
		kind = String(emergency_plan.get("kind", kind))
		if seed < 0:
			seed = int(emergency_plan.get("seed", 0))
	var pw: Node = order_equipment(&"power")
	if kind != "overload" or pw == null:
		return
	var c: int = pw.surge(seed if seed >= 0 else day_number)
	log_event("EMERGENCY: Bus A overload (%s)" % pw.CHANNELS[c], &"emergency")
	if is_inside_tree():
		get_tree().call_group(&"journal", &"on_emergency", day_number)
	var existing: Array = orders.filter(func(o): return o["status"] == "open" and String(o["type"]) == "power")
	if existing.is_empty():
		_order_seq += 1
		orders.append({"id": "WO-%04d" % _order_seq, "type": "power", "category": "B", "priority": 3, "day": day_number,
			"seed": seed, "status": "open", "carried_from": -1, "emergency": true})
	else:
		existing[0]["emergency"] = true


# ======================================================================
# Round 35 Priorities 4/11/12: CONCURRENT WORK ORDERS. The day's main
# maintenance workday stays as it was; the new equipment tasks are extra
# ORDERS held here (DayPlan stays the one work-order authority). Each order
# is a small record; the EQUIPMENT it targets is authoritative for its
# state and completion (register_order_equipment()), so there is no second
# task registry and no fake simulation:
#   order: {id, type, category, priority, day, seed, status, carried_from}
#   equipment API: order_rearm(seed), order_done(), order_next() ->
#     {short, action, room}, order_progress() -> "2/4", order_detail() ->
#     Array[String], order_feasible() -> bool
# Categories: A quick routine (5-20 s), B interactive (20-90 s), C full
# job (2-5 min), D multi-room chain (2-6 min). Category = time/complexity,
# NOT difficulty (difficulty only changes assistance/tolerances).
# ======================================================================
const ORDER_TYPES := {
	&"breaker": {"tag": "BREAKER", "category": "A", "weight": 1, "priority": 3, "title": "Reset tripped breaker", "intro_day": 2},
	&"vent": {"tag": "VENT", "category": "B", "weight": 2, "priority": 2, "title": "Clean ventilation grille", "intro_day": 3},
	&"power": {"tag": "LOADS", "category": "B", "weight": 2, "priority": 2, "title": "Balance power distribution", "intro_day": 4},
	&"seal": {"tag": "SEAL", "category": "B", "weight": 2, "priority": 1, "title": "Inspect hatch seal", "intro_day": 5},
	&"data": {"tag": "DATA", "category": "D", "weight": 3, "priority": 1, "title": "Transfer diagnostic data", "intro_day": 6},
	# Round 36: portable thermal probe survey (Control -> Engineering -> Control).
	&"thermal": {"tag": "THERMAL", "category": "D", "weight": 3, "priority": 1, "title": "Thermal survey: power terminals", "intro_day": 7},
	# Round 38: comms link degraded -> EVA repair of antenna A1 (chain).
	&"antenna": {"tag": "ANTENNA", "category": "D", "weight": 3, "priority": 2, "title": "Restore comms link (EVA)", "intro_day": 8},
	# Round 39: grimed exterior camera lens -> EVA wipe (chain).
	&"lens": {"tag": "EXT CAM", "category": "D", "weight": 2, "priority": 1, "title": "Clean exterior camera lens (EVA)", "intro_day": 9},
	# Round 41: solar array EVA work, introduced one at a time (a routine
	# outer-panel inspection first, then the electrical and structural jobs).
	&"solar_clean": {"tag": "SOLAR PNL", "category": "D", "weight": 3, "priority": 1, "title": "Solar outer panel inspection (EVA)", "intro_day": 10},
	&"solar_coupler": {"tag": "SOLAR CPL", "category": "D", "weight": 3, "priority": 2, "title": "Service solar power coupler (EVA)", "intro_day": 11},
	&"solar_hinge": {"tag": "SOLAR HNG", "category": "D", "weight": 3, "priority": 2, "title": "Solar hinge latch inspection (EVA)", "intro_day": 13},
	# Round 42: Junction and Communications daily maintenance (physical,
	# short-to-moderate, a different fault each time).
	&"patch_bay": {"tag": "PATCH", "category": "B", "weight": 2, "priority": 2, "title": "Service signal patch bay (Comms)", "intro_day": 12},
	&"emerg_lights": {"tag": "EM LIGHT", "category": "B", "weight": 2, "priority": 1, "title": "Emergency lighting test (Junction)", "intro_day": 14},
	&"junction_panel": {"tag": "J-PANEL", "category": "B", "weight": 2, "priority": 1, "title": "Inspect Junction distribution panel", "intro_day": 15},
	&"backup_rx": {"tag": "RX TEST", "category": "B", "weight": 2, "priority": 1, "title": "Backup receiver test (Comms)", "intro_day": 16},
}
## Round 41: LONG exterior jobs -- never more than one open at a time
## (no day with several long EVA chains).
const LONG_EVA := [&"antenna", &"solar_clean", &"solar_coupler", &"solar_hinge"]

# ======================================================================
# Round 38 Priority 14: TECHNICIAN PROFICIENCY -- counts of REAL completed
# work per family (each closed order / workday credited exactly once).
# It changes guidance detail (the assistant skips routine narration for a
# practised family) and which fault combinations may appear (seal double
# faults, filter mechanical variants, Bus A emergencies). No points, no
# repair-speed bonuses: the work stays physical.
# ======================================================================
const FAMILIES := ["electrical", "life_support", "mechanical", "communications", "eva"]
const ORDER_FAMILY := {&"breaker": ["electrical"], &"power": ["electrical"], &"thermal": ["electrical"], &"vent": ["life_support"], &"seal": ["mechanical"], &"data": ["communications"], &"antenna": ["communications", "eva"], &"lens": ["eva"], &"solar_clean": ["eva"], &"solar_coupler": ["electrical", "eva"], &"solar_hinge": ["mechanical", "eva"], &"patch_bay": ["communications"], &"emerg_lights": ["electrical"], &"junction_panel": ["electrical"], &"backup_rx": ["communications"]}
const WORKDAY_FAMILY := {Workday.FILTER_SERVICE: ["life_support"], Workday.CALIBRATION: ["life_support"], Workday.ELECTRICAL_SERVICE: ["electrical"], Workday.COOLANT_INSPECTION: ["mechanical"], Workday.INSPECTION_ROUND: ["mechanical"], Workday.COMMS_CHECK: ["communications"]}
var proficiency: Dictionary = {"electrical": 0, "life_support": 0, "mechanical": 0, "communications": 0, "eva": 0}
var _credited: Dictionary = {}


func credit(key: String, families: Array) -> void:
	if _credited.has(key):
		return
	_credited[key] = true
	for f in families:
		proficiency[f] = int(proficiency.get(f, 0)) + 1


func proficiency_level(family: String) -> int:
	return int(proficiency.get(family, 0))


static func rank_name(n: int) -> String:
	return "Trainee" if n == 0 else ("Technician" if n <= 2 else ("Qualified" if n <= 5 else "Senior"))
## Time-weighted budget per day type (A=1, B=2, C/D=3; the main workday
## counts 3, the cargo duty 2). Targets: quiet 3-4, normal 4-6, busy 5-7.
const DAY_BUDGET := {"quiet": 7, "normal": 9, "busy": 11}
var orders: Array = []
var day_type: String = ""
var _order_seq: int = 0
var _order_equipment: Dictionary = {}


func register_order_equipment(type: StringName, node: Node) -> void:
	_order_equipment[type] = node


func order_equipment(type: StringName) -> Node:
	return _order_equipment.get(type, null)


func open_orders() -> Array:
	return orders.filter(func(o): return o["status"] == "open")


func has_open_order(type: StringName) -> bool:
	return orders.any(func(o): return o["status"] == "open" and StringName(o["type"]) == type)


## Deterministic schedule for the new day (after the main workday is
## chosen). Unfinished orders stay (carried over); new types are introduced
## one per day from day 2; the remaining budget is filled from unlocked
## types in a day-seeded order, never duplicating an open type and never
## creating an impossible combination.
func _schedule_orders() -> void:
	for o in orders:
		if o["status"] == "open" and int(o["day"]) < day_number and int(o.get("carried_from", -1)) == -1:
			o["carried_from"] = int(o["day"])
	orders = orders.filter(func(o): return o["status"] == "open" or int(o["day"]) >= day_number - 3)
	if day_number < 2:
		day_type = ""
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day_number, "orders"])
	var kinds := ["quiet", "normal", "busy"]
	day_type = "quiet" if workday in ROUTINE_WORKDAYS else kinds[1 + rng.randi() % 2]
	if day_number <= 3:
		day_type = "quiet"   # early days stay gentle
	var used: int = (3 if workday != Workday.NONE else 0) + (2 if cargo_duty == "open" else 0)
	for o in open_orders():
		used += int(ORDER_TYPES[StringName(o["type"])]["weight"])
	var budget: int = DAY_BUDGET[day_type]
	var candidates: Array = []
	for t in ORDER_TYPES:
		if int(ORDER_TYPES[t]["intro_day"]) <= day_number:
			candidates.append(t)
	# The newest type first (progressive introduction), then seeded order.
	candidates.sort_custom(func(a, b): return int(ORDER_TYPES[a]["intro_day"]) > int(ORDER_TYPES[b]["intro_day"]))
	var newest: Variant = candidates[0] if not candidates.is_empty() and int(ORDER_TYPES[candidates[0]]["intro_day"]) == day_number else null
	var rest: Array = candidates.filter(func(t): return t != newest)
	for i in range(rest.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = rest[i]; rest[i] = rest[j]; rest[j] = tmp
	var ordered: Array = ([newest] if newest != null else []) + rest
	for t in ordered:
		var w: int = int(ORDER_TYPES[t]["weight"])
		# The task being introduced today may exceed the budget slightly, so
		# progressive introduction never stalls behind carried-over work.
		var allowance: int = 2 if t == newest else 0
		if used + w > budget + allowance or has_open_order(t):
			continue
		if not _order_compatible(t):
			continue
		var eq: Node = order_equipment(t)
		if eq == null or (eq.has_method("order_feasible") and not eq.order_feasible()):
			continue
		_order_seq += 1
		var o := {"id": "WO-%04d" % _order_seq, "type": String(t), "category": ORDER_TYPES[t]["category"],
			"priority": int(ORDER_TYPES[t]["priority"]), "day": day_number,
			"seed": hash([day_number, String(t)]), "status": "open", "carried_from": -1}
		orders.append(o)
		eq.order_rearm(int(o["seed"]))
		used += w
		log_event("New order %s: %s" % [o["id"], ORDER_TYPES[t]["title"]])


## Never schedule mutually exclusive work: no hatch-seal inspection while a
## cargo transfer uses the airlock.
func _order_compatible(t: StringName) -> bool:
	if t == &"seal" and cargo_duty == "open":
		return false
	if t in LONG_EVA and LONG_EVA.any(func(x): return has_open_order(x)):
		return false
	return true


func _poll_orders() -> void:
	for o in orders:
		if o["status"] != "open":
			continue
		var eq: Node = order_equipment(StringName(o["type"]))
		if eq != null and eq.order_done():
			o["status"] = "done"
			o["done_day"] = day_number
			credit(String(o["id"]), ORDER_FAMILY.get(StringName(o["type"]), []))
			var title: String = ORDER_TYPES[StringName(o["type"])]["title"]
			log_event("Closed work order %s: %s" % [o["id"], title], &"order_closed")
			_notify("%s — complete." % title)
			order_closed.emit(StringName(o["type"]))


## ONE short line per assignment for the workstation (Round 35 Priority 3):
## [{id, tag, action, room, progress, done}] -- the main workday first,
## then open orders by priority, then the cargo duty. The action is the
## NEXT physical step and advances by itself.
func order_rows() -> Array:
	var rows: Array = []
	if workday != Workday.NONE:
		var g: Dictionary = {}
		if not is_work_order_closed():
			for step in WORKDAY_STEPS[workday]:
				var done: bool = is_task_done(step[3]) if step[2] == "task" else has_fact(step[3])
				if not done:
					g = {"action": STEP_ACTION.get(step[3], String(step[0])), "short": STEP_SHORT.get(step[3], ""), "label": step[0], "room": step[1]}
					break
		var steps: Array = workday_steps()
		var n_done: int = steps.filter(func(s): return s["done"]).size()
		rows.append({"id": "MAIN", "tag": WORKDAY_TAG.get(workday, "TASK"), "action": g.get("action", "Done"), "short": g.get("short", ""), "label": g.get("label", ""), "room": g.get("room", &""),
			"progress": "%d/%d" % [n_done, steps.size()], "done": is_work_order_closed(), "priority": 2, "carried": carried_over_from > 0,
			# Round 37: an unrepaired Engineering power fault is a WARNING.
			"severity": 2 if (workday == Workday.ELECTRICAL_SERVICE and not is_equipment_restored()) else 1})
	var open_sorted: Array = open_orders()
	open_sorted.sort_custom(func(a, b): return int(a["priority"]) > int(b["priority"]) or (int(a["priority"]) == int(b["priority"]) and String(a["id"]) < String(b["id"])))
	for o in open_sorted:
		var eq: Node = order_equipment(StringName(o["type"]))
		var nx: Dictionary = eq.order_next() if eq != null else {}
		var sev: int = maxi(int(eq.order_severity()) if eq != null and eq.has_method("order_severity") else 1, 1)
		rows.append({"id": o["id"], "tag": ORDER_TYPES[StringName(o["type"])]["tag"], "action": nx.get("action", "Check equipment"), "short": nx.get("short", ""), "room": nx.get("room", &""),
			"progress": eq.order_progress() if eq != null else "", "done": false, "priority": int(o["priority"]) + (3 if sev >= 3 else 0), "carried": int(o.get("carried_from", -1)) > 0, "type": o["type"], "severity": sev, "emergency": bool(o.get("emergency", false))})
	if cargo_duty == "open":
		var c: Dictionary = cargo_step()
		rows.append({"id": "CARGO", "tag": "CARGO", "action": c.get("action", "Receive shipment"), "short": c.get("short", "CARGO"), "room": c.get("room", &"airlock"), "progress": "", "done": false, "priority": 1, "carried": false, "severity": 1})
	var meal: Dictionary = _meal_row()
	if not meal.is_empty():
		rows.append(meal)
	for o in orders:
		if o["status"] == "done" and int(o.get("done_day", -1)) == day_number:
			rows.append({"id": o["id"], "tag": ORDER_TYPES[StringName(o["type"])]["tag"], "action": "Complete", "room": &"", "progress": "", "done": true, "priority": 0, "carried": false})
	return rows


const ROOM_SHORT := {&"control_room": "Control", &"life_support": "Life Support", &"engineering": "Engineering", &"storage": "Storage", &"airlock": "Airlock", &"communications": "Comms", &"living_quarters": "Quarters"}
const WORKDAY_TAG := {Workday.FILTER_SERVICE: "FILTER", Workday.CALIBRATION: "SENSORS", Workday.ELECTRICAL_SERVICE: "WIRING", Workday.COOLANT_INSPECTION: "COOLANT", Workday.INSPECTION_ROUND: "ROUNDS", Workday.COMMS_CHECK: "COMMS"}
## Short verb phrases for every workday step (one-line rows).
const STEP_ACTION := {
	&"c01": "Check in at workstation", &"c02": "Run diagnostics", &"e02": "Trace the fault", &"retrieved:wire": "Get spare wire",
	&"e05": "Replace wire, restore power", &"c05": "Self-test", &"inspected:filter": "Inspect housing",
	&"retrieved:filter": "Get cartridge", &"l02": "Replace cartridge", &"verified": "Self-test",
	&"disposed:used_filter": "Dispose old cartridge", &"closed": "Closing", &"l08": "Route coolant",
	&"reviewed:sensor_warning": "Review warning", &"l07": "Calibrate chambers", &"reading:filter": "Log filter status",
	&"reading:coolant": "Log coolant status", &"reading:power": "Log power status", &"reading:storage_audit": "Count spares",
	&"reading:sensors": "Log sensor status", &"m02": "Signal check",
}


## One formatted row: "VENT — Clean blocked section · Life Support  2/4"
static func format_row(r: Dictionary, width: int = 56) -> String:
	var room: String = ROOM_SHORT.get(StringName(r.get("room", &"")), "")
	var core: String = "%s — %s" % [r["tag"], r["action"]]
	if room != "":
		core += " · " + room
	var tail: String = ""
	if r.get("done", false):
		tail = "done"
	elif String(r.get("progress", "")) != "":
		tail = r["progress"]
	if r.get("carried", false) and not r.get("done", false):
		tail = ("c/o " + tail).strip_edges()
	var room_part: String = core
	if room_part.length() + tail.length() + 2 > width:
		room_part = room_part.substr(0, maxi(width - tail.length() - 3, 8)) + ".."
	return room_part + ("  " + tail if tail != "" else "")


func shift_duration_s() -> float:
	return GameConfig.shift_duration_s()


func shift_remaining_s() -> float:
	return maxf(shift_duration_s() - shift_elapsed_s, 0.0)


static func clock_text(seconds: float) -> String:
	var s: int = int(ceil(seconds))
	return "%02d:%02d" % [s / 60, s % 60]


func can_sleep() -> bool:
	return shift_ended


func sleep_refusal() -> String:
	return "Shift in progress — %d%% done." % int(round(shift_progress() * 100.0))


## Ends the shift NOW (the clock reached the duration; tests/tools may also
## call it). The day's report is generated automatically from real work.
func end_shift_now() -> void:
	if not shift_ended:
		shift_elapsed_s = maxf(shift_elapsed_s, shift_duration_s())
		_end_shift()


func _end_shift() -> void:
	shift_ended = true
	if not shift_reported:
		shift_reported = true
		shift_history.append({"day": day_number, "report": shift_report_lines()})
		log_event("Daily shift ended")
	if _eva_active():
		_notify("Shift over. Finish safely and come back in through the airlock.")
	else:
		_notify("Shift over. Return to your bunk and rest.")
	if day_number == 1:
		_ai_event(&"save_hint")
	shift_ended_signal.emit(day_number)


func _eva_active() -> bool:
	var e: Node = get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null
	return e != null and e.has_method("is_eva_active") and (e.is_eva_active() or bool(e.get("suited")))


func _notify(text: String) -> void:
	notify.emit(text)
	var ml: Label = get_node_or_null(message_label_path) as Label
	if ml != null:
		preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), text, 3.5)


# ======================================================================
# Round 34 Priority 4: EVENT-DRIVEN work-order completion. Every recorded
# fact / completed task re-evaluates the open order: once the equipment is
# restored the system self-test VERIFIES it automatically; once verified
# AND cleanup is done the order CLOSES automatically. Cleanup and physical
# steps stay mandatory -- only redundant confirmation clicks are gone.
# ======================================================================
var _auto_guard: bool = false


func _auto_advance() -> void:
	if _auto_guard or workday == Workday.NONE or is_work_order_closed():
		return
	_auto_guard = true
	if is_equipment_restored() and not is_maintenance_verified():
		if workday in ROUTINE_WORKDAYS:
			var mm: Array[String] = reading_mismatches()
			if mm.is_empty():
				_facts[&"verified"] = true
				_notify("Readings cross-checked against the station record.")
			else:
				for id in readings.keys():
					if mm.any(func(m): return m.begins_with(String(id) + " ")):
						readings.erase(id)
						_facts.erase(StringName("reading:%s" % id))
				_notify("Cross-check failed — re-read: %s." % "; ".join(mm))
		else:
			match workday:
				Workday.ELECTRICAL_SERVICE:
					c05_status = TaskStatus.DONE
				_:
					_facts[&"verified"] = true
			_notify("%s verified." % _short_title())
	if is_maintenance_verified() and is_cleanup_complete() and not is_work_order_closed():
		_facts[&"closed"] = true
		credit("MAIN-d%d-w%d" % [day_number, workday], WORKDAY_FAMILY.get(workday, []))
		log_event("Closed work order: %s" % _short_title(), &"order_closed")
		_notify("%s complete." % _short_title())
	_auto_guard = false


func _short_title() -> String:
	return String(WORKDAY_TITLES.get(workday, "Work order")).get_slice(" —", 0)


# ======================================================================
# Round 34 Priorities 4/11/14: the CARGO LOGISTICS DUTY -- a second, short
# assignment on delivery days. It completes itself once the shipment is
# received, every part has been put away (none left in the carrier) and
# the port is secured again. Unfinished, it simply stays open next day.
# ======================================================================
var cargo_duty: String = ""        # "" | "open" | "done"
var cargo_duty_id: String = ""


func _poll_cargo_duty() -> void:
	if cargo_duty != "open" or _cargo_port == null:
		return
	var port: Node = _cargo_port
	if port.state == port.PortState.SECURED and port.received_shipments.has(cargo_duty_id) and parts_in_transit() == 0 and _carrier_empty():
		cargo_duty = "done"
		log_event("Cargo duty complete: %s stored" % cargo_duty_id, &"cargo_duty")
		_notify("Cargo delivery %s received and stored." % cargo_duty_id)


func _carrier_empty() -> bool:
	for c in get_tree().get_nodes_in_group(&"supply_carrier"):
		if c.part_count() > 0:
			return false
	return true


## Next physical step of the open cargo duty, or {} -- event-driven from
## the port/carrier state (no acknowledgement clicks).
func cargo_step() -> Dictionary:
	if cargo_duty != "open" or _cargo_port == null:
		return {}
	var port: Node = _cargo_port
	var car: Node = port.get("carrier")
	var S = port.PortState
	match port.state:
		S.ARRIVED: return {"label": "Cargo arrived: check the shipment ID at the airlock transfer port", "action": "Check shipment ID", "short": "CARGO ID", "room": &"airlock"}
		S.ID_CHECKED: return {"label": "Unlock and open the cargo hatch", "action": "Open cargo hatch", "short": "OPEN HATCH", "room": &"airlock"}
		S.OPEN: return {"label": "Release the cargo restraint", "action": "Release restraint", "short": "RELEASE", "room": &"airlock"}
	if car != null and car.part_count() > 0:
		if car.is_docked():
			return {"label": "Carry the parts carrier to Storage (or take parts one by one)", "action": "Carry tray to Storage", "short": "CARRY TRAY", "room": &"storage"}
		return {"label": "Unload the carrier into the reserve crate (Space)", "action": "Unload tray into crate", "short": "UNLOAD TRAY", "room": &"storage"}
	if parts_in_transit() > 0:
		return {"label": "Put the carried part away in Storage", "action": "Stow the part", "short": "STOW PART", "room": &"storage"}
	match port.state:
		S.UNLOADING, S.EMPTY: return {"label": "Confirm receipt at the port panel", "action": "Confirm receipt", "short": "CONFIRM", "room": &"airlock"}
	if car != null and not car.is_docked():
		return {"label": "Return the empty carrier to the cargo port", "action": "Return empty tray", "short": "RETURN TRAY", "room": &"airlock"}
	if port.state == S.RECEIVED:
		return {"label": "Close and secure the cargo hatch", "action": "Secure cargo hatch", "short": "SECURE HATCH", "room": &"airlock"}
	return {}


## Short watch labels for every workday step key.
const STEP_SHORT := {
	&"c01": "CHECK IN", &"c02": "RUN DIAG", &"e02": "TRACE FAULT", &"retrieved:wire": "GET SPARE",
	&"e05": "REPAIR PANEL", &"c05": "SELF-TEST", &"inspected:filter": "INSPECT FILTER",
	&"retrieved:filter": "GET FILTER", &"l02": "REPLACE FILTER", &"verified": "SELF-TEST",
	&"disposed:used_filter": "DISPOSE OLD", &"closed": "CLOSE", &"l08": "ROUTE COOLANT",
	&"reviewed:sensor_warning": "REVIEW DIAG", &"l07": "CALIBRATE", &"reading:filter": "LOG FILTER",
	&"reading:coolant": "LOG COOLANT", &"reading:power": "LOG POWER", &"reading:storage_audit": "AUDIT SPARES",
	&"reading:sensors": "LOG SENSORS", &"m02": "SIGNAL CHECK",
}


## Round 34 Priority 11: the ONE next thing to do (work order first, then
## the cargo duty), for the wristwatch and the workstation.
func guidance() -> Dictionary:
	# Round 35: the single highest-priority ACTIONABLE row (ties keep the
	# row order: main workday, then orders, then the cargo duty).
	var best: Dictionary = {}
	for r in order_rows():
		if r.get("done", false):
			continue
		if best.is_empty() or int(r["priority"]) > int(best["priority"]):
			best = r
	if best.is_empty():
		return {}
	var short: String = String(best.get("short", ""))
	if short == "":
		short = String(best["action"]).to_upper()
	return {"label": String(best.get("label", "")) if String(best.get("label", "")) != "" else String(best["action"]), "short": short, "room": best.get("room", &""), "tag": best["tag"], "id": best["id"]}


## Round 33: "which day is it, and what is today about" -- one line, shared
## by the workstation Home screen and the laptop so they never disagree.
func today_title() -> String:
	if workday != Workday.NONE:
		return String(WORKDAY_TITLES[workday])
	if day_number == 1:
		return "Orientation shift (station check-in)"
	return "No scheduled maintenance"


## True from the start of a day until the player checks in at the
## Control Room (C01) -- the "new shift" hint.
func is_new_shift() -> bool:
	return not is_task_done(&"c01")


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
	# Round 43: after the first day's check-in, one brief pointer to the
	# previous technician's handover (desktop shortcut).
	if task_id == &"c01" and day_number == 1 and not is_task_done(&"c01"):
		_ai_event.call_deferred(&"handover_day1")
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
	_auto_advance()


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


func log_event(text: String, kind: StringName = &"", amount: int = 1) -> void:
	_day_log.append(text)
	if kind != &"":
		shift_stats[String(kind)] = int(shift_stats.get(String(kind), 0)) + amount


# ======================================================================
# Round 33 Priority 3: end-of-shift report, derived ONLY from what actually
# happened today (structured counters written by the real equipment through
# log_event(), the service log, the work-order state). Submitting it is the
# shift-completion action; unfinished work is listed and carried over.
# ======================================================================
var shift_stats: Dictionary = {}      # kind -> count, today only
var shift_reported: bool = false
var shift_history: Array = []         # [{"day", "report": [lines]}]
var carried_over_from: int = -1       # day the current order was carried from
var inspections_done: Array = []      # Round 33 inspection facts recorded today


func serviced_today() -> Array:
	var out: Array = []
	for e in service_history:
		if int(e["day"]) == day_number:
			out.append(String(WORKDAY_TITLES.get(int(e["workday"]), "equipment")).get_slice(" —", 0))
	return out


func unfinished_work() -> Array[String]:
	var out: Array[String] = []
	if workday != Workday.NONE and not is_work_order_closed():
		var state := "not started"
		if is_maintenance_verified():
			state = "verified, cleanup pending"
		elif is_equipment_restored():
			state = "restored, verification pending"
		elif not next_workday_step().is_empty():
			state = "next: " + String(next_workday_step()["label"])
		out.append("%s — %s%s" % [String(WORKDAY_TITLES[workday]).get_slice(" —", 0), state, " (carries over)" if not is_equipment_restored() else ""])
	for w in blocked_services:
		out.append("%s — blocked, awaiting supplies" % String(WORKDAY_TITLES.get(w, "service")).get_slice(" —", 0))
	if _cargo_port != null and _cargo_port.is_busy() and _cargo_port.state != _cargo_port.PortState.RECEIVED:
		out.append("Cargo %s — %s at the airlock" % [_cargo_port.shipment_id, _cargo_port.status_word()])
	return out


func shift_report_lines() -> Array[String]:
	var s := shift_stats
	var lines: Array[String] = ["SHIFT REPORT — DAY %d" % day_number]
	var serviced: Array = serviced_today()
	lines.append("Equipment serviced: %s" % (", ".join(serviced) if not serviced.is_empty() else "none"))
	lines.append("Work orders closed: %d" % int(s.get("order_closed", 0)))
	lines.append("Inspections completed: %s" % (", ".join(inspections_done) if not inspections_done.is_empty() else "none"))
	lines.append("Parts consumed: %d   discarded: %d   restocked: %d" % [int(s.get("consumed", 0)), int(s.get("discarded", 0)), int(s.get("restocked", 0))])
	lines.append("Cargo received: %s" % (("%d part(s)" % int(s.get("cargo_parts", 0))) if int(s.get("cargo_parts", 0)) > 0 else "none"))
	var unf: Array[String] = unfinished_work()
	lines.append("Unfinished: %s" % ("none" if unf.is_empty() else "; ".join(unf)))
	var concerns: Array[String] = []
	for w in supply_warnings():
		if w.begins_with("SUPPLY") or w.begins_with("BLOCKED"):
			concerns.append(w)
	lines.append("Supply concerns: %s" % ("none" if concerns.is_empty() else "; ".join(concerns)))
	if meal_required and _quarters() != null:
		var m: Dictionary = meal_status()
		lines.append("Meals: %s" % ("eaten and drunk" if m["ate"] and m["drank"] else ("SKIPPED — " + ", ".join(([] if m["ate"] else ["no food"]) + ([] if m["drank"] else ["no drink"])))))
	return lines


## Round 34: there is no manual "submit report" action any more -- the
## report is generated automatically when the shift clock ends
## (_end_shift()). A live preview is always available.


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
		have += parts_in_transit(t)
		out[t] = maxi(cap - have, 0)
	return out


## Round 33: parts in a parts carrier that is NOT docked in the port (being
## carried / set down on the way to Storage). Docked-carrier parts are
## already counted by the port.
func parts_in_transit(t: StringName = &"") -> int:
	var n := 0
	if not is_inside_tree():
		return 0
	for c in get_tree().get_nodes_in_group(&"supply_carrier"):
		if not c.is_docked():
			n += c.part_count(t)
	return n


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
		cargo_duty = "open"
		cargo_duty_id = id
	next_cargo_day = day_number + CARGO_INTERVAL_DAYS


func reset_for_new_day() -> void:
	# Round 33: essential unfinished work (equipment NOT restored) carries
	# into the next day with its progress, instead of being erased.
	var carry := {}
	if workday != Workday.NONE and not (workday in ROUTINE_WORKDAYS) and not is_equipment_restored():
		carry = {"workday": workday, "facts": _facts.duplicate(), "from": day_number, "tasks": {},
			"fault_target": fault_target, "required": required_component_id}
		for step in WORKDAY_STEPS[workday]:
			if step[2] == "task" and step[3] != &"c01" and is_task_done(step[3]):
				carry["tasks"][step[3]] = true
	if meal_required and _quarters() != null:
		underfed = not meal_status()["ate"]
	var prev_day: int = day_number
	work_done_at_s = -1.0
	awake_after_shift_s = 0.0
	_bed_reminders = 0
	_day_log.clear()
	shift_stats = {}
	shift_reported = false
	inspections_done = []
	readings = {}
	shift_elapsed_s = 0.0
	shift_ended = false
	# Round 43: the new day's clock waits at 08:00 until the technician is up.
	day_active = false
	if cargo_duty == "done":
		cargo_duty = ""
	day_number += 1
	_run_cargo_schedule()
	if carry.is_empty():
		carried_over_from = -1
		_start_next_workday()
		_schedule_orders()
	else:
		workday = carry["workday"]
		_facts = carry["facts"]
		_facts.erase(&"closed")
		carried_over_from = carry["from"]
		_schedule_orders()
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
	if not carry.is_empty():
		for t in carry["tasks"]:
			mark_done_silent(t)
		fault_target = carry["fault_target"]
		required_component_id = carry["required"]
		log_event("Carried over from day %d: %s" % [carry["from"], String(WORKDAY_TITLES[workday]).get_slice(" —", 0)])
	plan_emergency()
	if _quarters() != null and _quarters().has_method("on_new_day"):
		_quarters().on_new_day(prev_day)
	day_started.emit(day_number)
	if underfed:
		_ai_event.call_deferred(&"underfed")


## Restores a task's DONE flag without the side effects of mark_done()
## (no service log entry, no signal) -- used for carried-over progress.
func mark_done_silent(task_id: StringName) -> void:
	match task_id:
		&"c02": c02_status = TaskStatus.DONE
		&"e01": e01_status = TaskStatus.DONE
		&"e02": e02_status = TaskStatus.DONE
		&"e05": e05_status = TaskStatus.DONE
		&"l07": l07_status = TaskStatus.DONE
		&"l08": l08_status = TaskStatus.DONE
		&"l02": l02_status = TaskStatus.DONE


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
enum Workday { NONE, ELECTRICAL_SERVICE, FILTER_SERVICE, CALIBRATION, COOLANT_INSPECTION, INSPECTION_ROUND, COMMS_CHECK }
## Round 33 Priority 4: ROUTINE work for days with no service due -- an
## inspection round (physical status readings + a Storage supply audit) or
## a communications check (routine signal check + cross-check readings).
## Not part of the first-time rotation and never carried over.
const ROUTINE_WORKDAYS := [Workday.INSPECTION_ROUND, Workday.COMMS_CHECK]

@export var workday_rotation: Array[int] = [Workday.FILTER_SERVICE, Workday.CALIBRATION, Workday.ELECTRICAL_SERVICE, Workday.COOLANT_INSPECTION]

const WORKDAY_TITLES := {
	Workday.COOLANT_INSPECTION: "Coolant Routing Inspection — L08",
	Workday.ELECTRICAL_SERVICE: "Electrical Service — Engineering power circuit",
	Workday.FILTER_SERVICE: "Life Support Filter Service — L02",
	Workday.CALIBRATION: "Pressure Sensor Calibration — L07",
	Workday.INSPECTION_ROUND: "Routine Inspection Round — station systems",
	Workday.COMMS_CHECK: "Routine Communications Check — M02",
}

## [label, room, kind ("task"/"fact"), key, phase]
const WORKDAY_STEPS := {
	Workday.ELECTRICAL_SERVICE: [
		["Receive work order", &"control_room", "task", &"c01", ""],
		["Review diagnostics", &"control_room", "task", &"c02", ""],
		["Identify the faulty circuit", &"engineering", "task", &"e02", ""],
		["Retrieve replacement wire from Storage", &"storage", "fact", &"retrieved:wire", ""],
		["Repair the panel and restore power", &"engineering", "task", &"e05", "restore"],
		["Power self-test (automatic)", &"control_room", "task", &"c05", "verify"],
		["Order closes automatically", &"control_room", "fact", &"closed", "close"],
	],
	Workday.FILTER_SERVICE: [
		["Receive maintenance assignment", &"control_room", "task", &"c01", ""],
		["Inspect the filter housing", &"life_support", "fact", &"inspected:filter", ""],
		["Retrieve replacement cartridge from Storage", &"storage", "fact", &"retrieved:filter", ""],
		["Replace the cartridge and restore airflow", &"life_support", "task", &"l02", "restore"],
		["Airflow self-test (automatic)", &"control_room", "fact", &"verified", "verify"],
		["Dispose of the used cartridge", &"storage", "fact", &"disposed:used_filter", "cleanup"],
		["Order closes automatically", &"control_room", "fact", &"closed", "close"],
	],
	Workday.COOLANT_INSPECTION: [
		["Receive inspection order", &"control_room", "task", &"c01", ""],
		["Re-route coolant at the valve manifold", &"life_support", "task", &"l08", "restore"],
		["Flow self-test (automatic)", &"control_room", "fact", &"verified", "verify"],
		["Order closes automatically", &"control_room", "fact", &"closed", "close"],
	],
	Workday.INSPECTION_ROUND: [
		["Receive the inspection round", &"control_room", "task", &"c01", ""],
		["Log the filter housing status", &"life_support", "fact", &"reading:filter", "inspect"],
		["Log the coolant manifold status", &"life_support", "fact", &"reading:coolant", "inspect"],
		["Log the power panel status", &"engineering", "fact", &"reading:power", "inspect"],
		["Audit the electrical spares (count the shelf)", &"storage", "fact", &"reading:storage_audit", "inspect"],
		["Readings cross-checked (automatic)", &"control_room", "fact", &"verified", "verify"],
		["Order closes automatically", &"control_room", "fact", &"closed", "close"],
	],
	Workday.COMMS_CHECK: [
		["Receive the communications check", &"control_room", "task", &"c01", ""],
		["Run the routine signal check", &"communications", "task", &"m02", "inspect"],
		["Log the sensor array status", &"life_support", "fact", &"reading:sensors", "inspect"],
		["Cross-check the power panel status", &"engineering", "fact", &"reading:power", "inspect"],
		["Readings cross-checked (automatic)", &"control_room", "fact", &"verified", "verify"],
		["Order closes automatically", &"control_room", "fact", &"closed", "close"],
	],
	Workday.CALIBRATION: [
		["Receive sensor warning", &"control_room", "task", &"c01", ""],
		["Review the pressure warning in Diagnostics", &"control_room", "fact", &"reviewed:sensor_warning", ""],
		["Calibrate the coupled chambers", &"life_support", "task", &"l07", "restore"],
		["Stability self-test (automatic)", &"control_room", "fact", &"verified", "verify"],
		["Order closes automatically", &"control_room", "fact", &"closed", "close"],
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
	_auto_advance()


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
	# Round 33: an inspection has nothing to restore -- its readings play
	# that role.
	if workday in ROUTINE_WORKDAYS:
		return _phase_done("inspect")
	return _phase_done("restore")


# ======================================================================
# Round 33 Priority 4: physical READINGS (inspection tags, supply audit).
# ======================================================================
var readings: Dictionary = {}          # id -> reading text logged today
var _reading_sources: Dictionary = {}  # id -> Callable returning the LIVE reading


func register_reading_source(id: StringName, source: Callable) -> void:
	_reading_sources[id] = source


func has_reading(id: StringName) -> bool:
	return readings.has(String(id))


func reading_of(id: StringName) -> String:
	return String(readings.get(String(id), ""))


## Called by a physical inspection point. Returns the player message.
func log_reading(id: StringName, title: String, reading: String) -> String:
	var first: bool = not readings.has(String(id))
	readings[String(id)] = reading
	record_fact(StringName("reading:%s" % id))
	if first:
		inspections_done.append("%s %s" % [title.get_slice(" ", 0), reading])
		log_event("Logged %s: %s" % [title, reading], &"inspection")
	return "Logged %s: %s" % [title, reading]


## The workstation cross-check: every logged reading must still match the
## equipment's live state; a stale/mismatched one has to be re-read.
func reading_mismatches() -> Array[String]:
	var out: Array[String] = []
	for id in readings:
		var src: Variant = _reading_sources.get(StringName(id), null)
		if src is Callable and (src as Callable).is_valid():
			var live: String = (src as Callable).call()
			if live != readings[id]:
				out.append("%s logged %s, now %s" % [id, readings[id], live])
	return out


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
		if workday in ROUTINE_WORKDAYS:
			return "Cannot file yet: %s." % String(next_workday_step().get("label", "readings missing")).to_lower()
		return "Verification failed: equipment not yet restored."
	if workday in ROUTINE_WORKDAYS and not is_maintenance_verified():
		var mm: Array[String] = reading_mismatches()
		if not mm.is_empty():
			for id in readings.keys():
				if mm.any(func(m): return m.begins_with(String(id) + " ")):
					readings.erase(id)
					_facts.erase(StringName("reading:%s" % id))
			return "Cross-check failed — re-read: %s." % "; ".join(mm)
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
		log_event("Closed work order: %s" % String(WORKDAY_TITLES[workday]).get_slice(" —", 0), &"order_closed")
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
		status = "READINGS COMPLETE — file at the workstation" if workday in ROUTINE_WORKDAYS else "RESTORED — verification pending"
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
			_pick_service_variant(w)
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
			_pick_service_variant(w)
			return
	# Round 33: nothing due -> a routine inspection day (alternating).
	workday = ROUTINE_WORKDAYS[day_number % ROUTINE_WORKDAYS.size()]


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
## Round 36: equipment that has several legitimate starting conditions for
## a service (e.g. the filter housing) registers a picker; it is called ONCE
## when a NEW service event for `w` is generated (first-time or due), with
## the deterministic day seed -- never on carry-over, reload or reopening.
var _variant_pickers: Dictionary = {}


func register_service_variant(w: int, picker: Callable) -> void:
	_variant_pickers[w] = picker


func _pick_service_variant(w: int) -> void:
	if _variant_pickers.has(w):
		(_variant_pickers[w] as Callable).call(daily_variant_seed(w))


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
