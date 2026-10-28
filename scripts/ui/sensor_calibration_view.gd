extends Control
## Focused sensor-calibration interface -- Round 13 Workstream D: L07
## evolved from Round 11's single-chamber coarse/fine/damping tuning
## puzzle into a COUPLED three-chamber pressure-balancing procedure,
## per the player's own request: "When pressure increases in one
## chamber, pressures in connected chambers also change. The player
## must reach the correct range in every chamber while accounting for
## how each adjustment influences the others."
##
## THE SIMULATION: still a damped spring per chamber (Round 11's own
## innovation, kept) -- but each chamber's spring no longer pulls
## toward its OWN setpoint alone. It pulls toward a WEIGHTED BLEND of
## all three setpoints, via a fixed, difficulty-tuned 3x3 coupling
## matrix (`_COUPLING_BY_DIFFICULTY`) whose ROWS SUM TO 1.0 -- that
## normalization is not cosmetic, it is what GUARANTEES a reachable
## equilibrium exists for any target vector (see _solve_equilibrium()'s
## own doc comment: the system M*S=T is then always solvable whenever M
## is invertible, which every authored matrix below is, verified by
## tests/test_sensor_calibration_coupling.gd computing the actual
## solution and confirming it lands in-bounds and in-range for every
## difficulty). Concretely: effective_target[i] = sum_j M[i][j] *
## setpoint[j], then acceleration[i] = RESPONSE_STRENGTH *
## (effective_target[i] - reading[i]) - damping * velocity[i], same
## integration as Round 11. Moving chamber A's regulator therefore
## visibly nudges B and C's OWN readings too, in a real, deterministic,
## learnable way -- not a hidden formula the player has to guess, since
## the direction/magnitude of influence is directly observable by
## adjusting one regulator and watching the other two needles respond.
##
## CONTROLS (per the explicit "do not require manipulating ten
## different knobs" instruction): three chamber regulator knobs (one
## per chamber's own setpoint) plus ONE SHARED damping knob that
## affects all three chambers' convergence uniformly -- four knobs
## total, each with a keyboard fallback. A held Shift key is the
## "shared fine-adjustment mode" (not three separate fine knobs): it
## reduces whichever regulator is currently being adjusted to a slower,
## more precise rate, exactly mirroring Round 11's coarse/fine split
## without tripling the control count.
##
## DIFFICULTY: reads the SAME global GameSettings.get_difficulty()
## every other system uses. EASY uses a weak (near-diagonal) coupling
## matrix, a wide tolerance band and a short stability hold, with an
## explicit "which chambers are linked" hint. NORMAL uses meaningful
## coupling with a moderate band/hold and no direct hint. HARD uses
## strong coupling, a narrow band and a long hold, with no hints at
## all. RESPONSE_STRENGTH (each chamber's fixed physical
## responsiveness) never changes by difficulty -- only the coupling
## matrix, tolerance and stability duration do, consistent with Round
## 11's own "physics stays constant, only acceptance criteria change"
## policy.
##
## FIXED PUZZLE INSTANCE (per the explicit "start with a well-designed
## fixed puzzle instance, do not randomize before this is fun and
## stable"): one authored target vector (`_TARGETS`), shared across all
## three difficulties, with each difficulty's own coupling matrix
## having a verified unique equilibrium landing on that SAME target
## vector within [0,100] -- so the "correct answer" regulator positions
## genuinely differ by difficulty (stronger coupling needs a more
## different-looking regulator layout to reach the same physical
## target pressures), without the puzzle's actual target values moving
## around session to session.
##
## Same focused-mode/"view reads the authoritative object, never
## duplicates its state" conventions as electrical_repair_view.gd --
## the only authoritative state here is DayPlan's l07_status flag
## (reached through sensor_calibration_station.gd's mark_complete()/
## is_complete()). The live simulation (setpoints/readings/velocities/
## damping/stability) is disposable per-attempt session state owned
## entirely by this view -- nothing about an abandoned attempt is worth
## persisting, so every open_station() call starts fresh from the same
## documented starting point (deterministic, not randomized).

const GameSettings = preload("res://scripts/station/game_settings.gd")

@export var focused_state_path: NodePath
@export var sfx_path: NodePath

## Round 18 Priority 3: expanded from 3 to 6 chambers -- the "FUTURE
## 4-6 CHAMBER EXPANSION SEAM" this file's own class doc comment already
## flagged as the one deliberately-deferred piece from Round 14. 6 (not
## the full 8-12 the brief's own targets mention) was chosen because the
## brief's OWN required-calibration-count table tops out at "HARD: 5-6
## chambers requiring calibration" -- a 6-chamber total satisfies every
## row of that table exactly (EASY 1-2 of 6, NORMAL 3-4 of 6, HARD 5-6
## of 6, see _REQUIRED_RANGE_BY_DIFFICULTY) without needing a chamber
## count the table itself never actually requires being fully active.
const CHAMBERS: Array[StringName] = [&"a", &"b", &"c", &"d", &"e", &"f"]
const CHAMBER_LABELS := {
	&"a": "CHAMBER A", &"b": "CHAMBER B", &"c": "CHAMBER C",
	&"d": "CHAMBER D", &"e": "CHAMBER E", &"f": "CHAMBER F",
}

## The ONE fixed target pressure per chamber, shared across every
## difficulty (see class doc comment for why this stays constant while
## only the coupling matrix/tolerance/duration vary).
## A smooth, mostly-monotonic ramp (up then down) across the 6 chambers,
## not an arbitrary zigzag -- target CHOICE matters for a neighbor-
## coupled chain: a target vector with sharp swings between ADJACENT
## chambers forces the equilibrium solver to an overshoot (the coupling
## pulls each chamber toward its neighbors' very different setpoints, so
## reaching a sharp local peak/valley needs an even MORE extreme
## setpoint to compensate) that can land outside the physical [0,100]
## gauge range at HARD's stronger coupling -- confirmed directly: an
## earlier, more jagged target vector solved fine at EASY/NORMAL but
## produced an UNREACHABLE (out-of-range, even negative) HARD solution.
## This vector was verified solvable in-range at every difficulty via
## the actual solver (see tests/test_sensor_calibration_coupling.gd),
## not merely chosen to look smooth. f's target deliberately avoids
## exactly 50.0 (START_VALUE) -- any chamber target equal to the shared
## starting value would start trivially "in range" even while nominally
## active, undermining "real work required" for that one chamber.
const _TARGETS := {&"a": 33.0, &"b": 43.0, &"c": 62.0, &"d": 68.0, &"e": 59.0, &"f": 38.0}
const START_VALUE: float = 50.0 # every chamber's setpoint AND reading start here -- away from every target, real work required
const START_DAMPING: float = 1.4 # deliberately underdamped -- untouched, it will oscillate
const COARSE_RATE: float = 22.0 # units/sec, regulator keys/knob
const FINE_RATE_FACTOR: float = 0.18 # Shift held -- "shared fine mode" multiplies COARSE_RATE down instead of a second knob
const DAMPING_RATE: float = 2.2 # units/sec, Z/X or the Damping knob
const REGULATOR_KNOB_DEGREES_PER_UNIT: float = 2.4
const DAMPING_KNOB_DEGREES_PER_UNIT: float = 16.0
const RESPONSE_STRENGTH: float = 9.0 # fixed spring constant (omega^2) per chamber -- not player-tunable, not difficulty-tunable
const CRITICAL_DAMPING: float = 6.0 # 2*sqrt(RESPONSE_STRENGTH) -- the learnable "sweet spot"
const DAMPING_MIN: float = 0.4
const DAMPING_MAX: float = 7.5
const GAUGE_MIN: float = 0.0
const GAUGE_MAX: float = 100.0
const DIRECTION_DEADBAND: float = 0.01
const MAX_PHYSICS_STEP: float = 0.05 # clamp delta for the spring integration -- numeric stability at low frame rates

## Keyboard fallback per chamber: [decrease, increase]. D/E/F continue
## the SAME number-key-pair convention A/B/C already use (not a scheme
## redesign) -- preserves every existing A/B/C keybinding and test
## unchanged while extending the identical pattern for the 3 new
## chambers.
const _CHAMBER_KEYS := {
	&"a": [KEY_1, KEY_2],
	&"b": [KEY_3, KEY_4],
	&"c": [KEY_5, KEY_6],
	&"d": [KEY_7, KEY_8],
	&"e": [KEY_9, KEY_0],
	&"f": [KEY_MINUS, KEY_EQUAL],
}

## Row-normalized (each row sums to EXACTLY 1.0) 3x3 coupling matrices,
## indexed [row][col] = how much chamber `col`'s regulator influences
## chamber `row`'s effective target. The diagonal dominates in every
## difficulty (each chamber still mostly follows its own regulator);
## only the OFF-diagonal strength (how much the other two leak in)
## changes. Row-sum = 1.0 is what guarantees a reachable equilibrium
## exists for any target vector -- see _solve_equilibrium()'s doc
## comment.
## Round 18 Priority 3: replaces 3 hand-authored 3x3 matrices with a
## GENERATED NEIGHBOR-ONLY coupling structure (per the brief's own
## "consider modest interactions between NEIGHBORING chambers" --
## chamber i's regulator now only leaks into i-1/i+1, physically
## plausible for pipes/chambers in a row, not an arbitrary dense NxN
## matrix that would need N^2 hand-tuned values per difficulty). Each
## row still sums to EXACTLY 1.0 (same reachable-equilibrium guarantee
## _solve_equilibrium()'s own doc comment explains -- row-normalization
## generalizes to any N, verified for N=6 by
## tests/test_sensor_calibration_coupling.gd the same way it was for
## N=3), built by _build_neighbor_coupling() below instead of hand-
## listed, so the three difficulties can't accidentally drift out of
## that invariant.
const _NEIGHBOR_WEIGHT_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: 0.055,
	GameSettings.Difficulty.NORMAL: 0.13,
	GameSettings.Difficulty.HARD: 0.21,
}


## Builds an NxN row-normalized "tridiagonal" coupling matrix: row i's
## weight toward each existing neighbor (i-1, i+1) is `neighbor_weight`;
## the remainder (1.0 minus however many real neighbors this row has,
## times neighbor_weight) is the diagonal -- endpoint chambers (only one
## real neighbor) end up with a slightly stronger diagonal than middle
## chambers (two neighbors), which is physically sensible (an end
## chamber is less exposed) and never needs special-casing beyond
## "a neighbor only exists if the index is in range".
static func _build_neighbor_coupling(n: int, neighbor_weight: float) -> Array:
	var matrix: Array = []
	for i in n:
		var row: Array = []
		for j in n:
			row.append(0.0)
		var neighbor_count: int = 0
		if i > 0:
			row[i - 1] = neighbor_weight
			neighbor_count += 1
		if i < n - 1:
			row[i + 1] = neighbor_weight
			neighbor_count += 1
		row[i] = 1.0 - neighbor_weight * neighbor_count
		matrix.append(row)
	return matrix


static func _coupling_for_difficulty(difficulty: int) -> Array:
	var weight: float = _NEIGHBOR_WEIGHT_BY_DIFFICULTY.get(difficulty, _NEIGHBOR_WEIGHT_BY_DIFFICULTY[GameSettings.Difficulty.NORMAL])
	return _build_neighbor_coupling(CHAMBERS.size(), weight)


## Round 18 Priority 3's own explicit per-difficulty target table:
## EASY 1-2, NORMAL 3-4, HARD 5-6 of this station's 6 total chambers.
const _REQUIRED_RANGE_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: [1, 2],
	GameSettings.Difficulty.NORMAL: [3, 4],
	GameSettings.Difficulty.HARD: [5, 6],
}


func _random_required_count(difficulty: int) -> int:
	var range_pair: Array = _REQUIRED_RANGE_BY_DIFFICULTY.get(difficulty, [3, 4])
	return randi_range(range_pair[0], range_pair[1])


## Test-only: forces the required-calibration count instead of a random
## pick within the difficulty's range, for deterministic regression
## coverage. Must be called before open_station() (which reads this
## once and does not re-check it mid-attempt), same "test-only forced
## value, read once" contract as every other debug_force_*() hook in
## this project (e.g. electrical_panel.gd's debug_force_fault_role()).
func debug_force_active_count(count: int) -> void:
	_debug_forced_count = count
const _TOLERANCE_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: 6.0,
	GameSettings.Difficulty.NORMAL: 4.0,
	GameSettings.Difficulty.HARD: 2.5,
}
const _STABILITY_DURATION_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: 1.0,
	GameSettings.Difficulty.NORMAL: 1.8,
	GameSettings.Difficulty.HARD: 2.5,
}

## Round 14 Priority 3: scalable difficulty framework -- progression by
## HOW MANY chambers start genuinely faulty (off their target, needing
## deliberate correction) rather than by changing the simulation,
## coupling math, or win condition at all. EASY = 1 active fault,
## NORMAL = 2, HARD = 3 (identical to every prior round's behavior, so
## the best-tested path is unchanged). A chamber NOT in this set simply
## starts already AT its own target (see open_station()) -- still fully
## alive in the simulation (coupling can still nudge it off-range if the
## player over-corrects an active chamber, and the win condition still
## requires EVERY chamber in CHAMBERS to be in-band, unchanged), so nothing
## about _step_springs()/_solve_equilibrium()/the win check needed to
## change. The existing per-chamber status chip ("LOW"/"HIGH"/"IN RANGE",
## driven purely by each chamber's own current reading vs. target)
## therefore ALREADY shows which chambers need attention for free, with
## no extra UI state to introduce.
##
## Round 18 Priority 3 (supersedes both paragraphs above): the "FUTURE
## 4-6 CHAMBER EXPANSION SEAM" is now built -- _solve_equilibrium() is a
## general NxN Gaussian-elimination solver, CHAMBERS has 6 entries, and
## the coupling matrix is GENERATED per difficulty (_build_neighbor_coupling())
## instead of hand-authored. The brief's OWN explicit instruction this
## round ("make difficulty depend on the existing global EASY/NORMAL/
## HARD setting... EASY 1-2, NORMAL 3-4, HARD 5-6 chambers requiring
## calibration") supersedes Round 16 Priority 8's choice to make fault
## count a station/work-order property independent of difficulty --
## required count is now RANDOMIZED within the difficulty's own range
## each time the station opens (see open_station()), not a fixed
## station export; sensor_calibration_station.gd's active_fault_count()
## is no longer read here (kept on that script, now unused by this view,
## rather than deleted -- see that script's own updated comment).

@onready var _focused_state: Node = get_node(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)

@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _stability_label: Label = $Panel/VBox/StabilityLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _hint_label: Label = $Panel/VBox/HintLabel

## Round 18 Priority 3: A/B/C still resolve from scene-authored nodes;
## D/E/F don't exist in the .tscn (hand-writing 3 more ~6-node chamber
## panels in a text scene file is impractical to do reliably) -- see
## _build_chamber_d_to_f(), called from _ready(), which builds them
## procedurally with the EXACT same node shape as A/B/C so every other
## function here (which already indexes this dict generically by role)
## treats all 6 chambers identically.
var _chamber_rows := {}
@onready var _damping_knob: Control = $Panel/VBox/SharedControls/DampingKnob
@onready var _damping_pointer: Control = $Panel/VBox/SharedControls/DampingKnob/Pointer

var _station: Node = null
var _setpoint := {}
var _reading := {}
var _velocity := {}
var _prev_gap := {}
var _damping: float = START_DAMPING
var _stability_timer: float = 0.0
var _done: bool = false
var _tolerance: float = 4.0
var _stability_duration: float = 1.8
var _coupling: Array = []
var _active_fault_count: int = 3
## Round 18 Priority 3: debug/test-only override for the randomized
## required-calibration count -- see open_station()'s own comment.
var _debug_forced_count: int = -1

var _dragging_control: StringName = &""
var _drag_prev_angle: float = 0.0
var _use_cylinder_display: bool = false

static var _ever_opened: bool = false
var _showing_first_use_hint: bool = false
var _hint_timer: float = 0.0
const _FIRST_USE_HINT_DURATION: float = 9.0


func _ready() -> void:
	visible = false
	for ch in [&"a", &"b", &"c"]:
		_chamber_rows[ch] = {
			"reading_label": get_node("Panel/VBox/ChamberRow/Chamber%s/Inner/ReadingLabel" % ch.to_upper()),
			"gauge": get_node("Panel/VBox/ChamberRow/Chamber%s/Inner/GaugeStack/Gauge" % ch.to_upper()),
			"cylgauge": get_node("Panel/VBox/ChamberRow/Chamber%s/Inner/GaugeStack/CylinderGauge" % ch.to_upper()),
			"knob": get_node("Panel/VBox/ChamberRow/Chamber%s/Inner/Knob" % ch.to_upper()),
			"pointer": get_node("Panel/VBox/ChamberRow/Chamber%s/Inner/Knob/Pointer" % ch.to_upper()),
			"status": get_node("Panel/VBox/ChamberRow/Chamber%s/Inner/StatusChip" % ch.to_upper()),
		}
	_build_chamber_d_to_f()
	for ch in CHAMBERS:
		_setpoint[ch] = START_VALUE
		_reading[ch] = START_VALUE
		_velocity[ch] = 0.0
		_prev_gap[ch] = -1.0
	for ch in CHAMBERS:
		var knob: Control = _chamber_rows[ch]["knob"]
		knob.gui_input.connect(_on_knob_gui_input.bind(ch, knob))
	_damping_knob.gui_input.connect(_on_knob_gui_input.bind(&"damping", _damping_knob))


## Builds chambers D/E/F with the exact same Panel/Inner/ReadingLabel/
## StatusChip/GaugeStack(Gauge+CylinderGauge)/Knob(Pointer) node shape
## A/B/C already have in the .tscn (see that scene's own ChamberA block)
## so sync/_refresh()/hover code never needs a "which chambers are
## procedural" branch.
func _build_chamber_d_to_f() -> void:
	var row: HBoxContainer = get_node("Panel/VBox/ChamberRow")
	var template_reading: Label = get_node("Panel/VBox/ChamberRow/ChamberA/Inner/ReadingLabel")
	var template_status: Label = get_node("Panel/VBox/ChamberRow/ChamberA/Inner/StatusChip")
	var template_pointer: ColorRect = get_node("Panel/VBox/ChamberRow/ChamberA/Inner/Knob/Pointer")

	for ch in [&"d", &"e", &"f"]:
		var panel := Panel.new()
		panel.name = "Chamber%s" % ch.to_upper()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(panel)

		var inner := VBoxContainer.new()
		inner.name = "Inner"
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 10.0
		inner.offset_top = 10.0
		inner.offset_right = -10.0
		inner.offset_bottom = -10.0
		inner.add_theme_constant_override("separation", 6)
		panel.add_child(inner)

		var reading_label := Label.new()
		reading_label.name = "ReadingLabel"
		reading_label.add_theme_color_override("font_color", template_reading.get_theme_color("font_color"))
		reading_label.add_theme_font_size_override("font_size", template_reading.get_theme_font_size("font_size"))
		reading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(reading_label)

		var status := Label.new()
		status.name = "StatusChip"
		status.add_theme_font_size_override("font_size", template_status.get_theme_font_size("font_size"))
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(status)

		var gauge_stack := Control.new()
		gauge_stack.name = "GaugeStack"
		gauge_stack.custom_minimum_size = Vector2(0, 130)
		gauge_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gauge_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(gauge_stack)

		var gauge: Control = Control.new()
		gauge.name = "Gauge"
		gauge.set_script(preload("res://scripts/ui/analog_gauge.gd"))
		gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
		gauge_stack.add_child(gauge)

		var cylgauge: Control = Control.new()
		cylgauge.name = "CylinderGauge"
		cylgauge.visible = false
		cylgauge.set_script(preload("res://scripts/ui/cylindrical_gauge.gd"))
		cylgauge.set_anchors_preset(Control.PRESET_FULL_RECT)
		gauge_stack.add_child(cylgauge)

		var knob := Panel.new()
		knob.name = "Knob"
		knob.custom_minimum_size = Vector2(64, 64)
		knob.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		knob.mouse_filter = Control.MOUSE_FILTER_STOP
		inner.add_child(knob)

		var pointer := ColorRect.new()
		pointer.name = "Pointer"
		pointer.offset_left = 29.0
		pointer.offset_top = 6.0
		pointer.offset_right = 35.0
		pointer.offset_bottom = 32.0
		pointer.pivot_offset = Vector2(3, 26)
		pointer.color = template_pointer.color
		pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		knob.add_child(pointer)

		_chamber_rows[ch] = {
			"reading_label": reading_label, "gauge": gauge, "cylgauge": cylgauge,
			"knob": knob, "pointer": pointer, "status": status,
		}


## Called by sensor_calibration_station.gd's interact().
func open_station(station: Node) -> void:
	_station = station
	if not _focused_state.begin(self):
		return
	visible = true
	_done = station.is_complete()
	var difficulty: int = GameSettings.get_difficulty()
	# Round 18 Priority 3: required-calibration count is now RANDOMIZED
	# within the current difficulty's own range (_REQUIRED_RANGE_BY_DIFFICULTY)
	# every time the station opens, not read from the station's own
	# active_fault_count() export (Round 16 Priority 8's choice,
	# superseded this round per the brief's own explicit instruction --
	# see this file's class doc comment). _debug_forced_count overrides
	# this for deterministic tests, same "test-only forced value" contract
	# every other randomized system in this project already uses.
	var fault_count: int = _debug_forced_count if _debug_forced_count != -1 else _random_required_count(difficulty)
	var active: Array = CHAMBERS.slice(0, fault_count)
	for ch in CHAMBERS:
		# Only this attempt's active (faulty) chambers start away from
		# their target; the rest start already solved. Difficulty still
		# independently scales _coupling/_tolerance/_stability_duration
		# below (how forgiving the attempt is), never how many chambers
		# are broken.
		_setpoint[ch] = START_VALUE if ch in active else _TARGETS[ch]
		_reading[ch] = START_VALUE if ch in active else _TARGETS[ch]
		_velocity[ch] = 0.0
		_prev_gap[ch] = -1.0
	_damping = START_DAMPING
	_stability_timer = 0.0
	_dragging_control = &""
	_use_cylinder_display = false # circular dial is the default/primary style
	_coupling = _coupling_for_difficulty(difficulty)
	_tolerance = _TOLERANCE_BY_DIFFICULTY.get(difficulty, 4.0)
	_stability_duration = _STABILITY_DURATION_BY_DIFFICULTY.get(difficulty, 1.8)
	_active_fault_count = fault_count
	_showing_first_use_hint = not _ever_opened and not _done
	_hint_timer = _FIRST_USE_HINT_DURATION
	_ever_opened = true
	for ch in CHAMBERS:
		_chamber_rows[ch]["gauge"].visible = true
		_chamber_rows[ch]["cylgauge"].visible = false
	_refresh()


## Duck-typed hook called by focused_interaction_state.gd on any exit.
func on_focus_exit() -> void:
	visible = false
	_station = null
	_dragging_control = &""


func cancel_requested() -> void:
	pass # Nothing to roll back -- l07 only ever commits via
	# _commit_success() below on a real simultaneous-stability success;
	# abandoning an in-progress attempt loses no task progress, and the
	# next attempt starts clean from START_VALUE/START_DAMPING.


func _process(delta: float) -> void:
	if not visible or _station == null or _done:
		return

	var fine: bool = Input.is_key_pressed(KEY_SHIFT)
	var rate: float = COARSE_RATE * (FINE_RATE_FACTOR if fine else 1.0)
	for ch in CHAMBERS:
		var keys: Array = _CHAMBER_KEYS[ch]
		if Input.is_key_pressed(keys[0]):
			_setpoint[ch] = clampf(_setpoint[ch] - rate * delta, GAUGE_MIN, GAUGE_MAX)
			_dismiss_first_use_hint()
		if Input.is_key_pressed(keys[1]):
			_setpoint[ch] = clampf(_setpoint[ch] + rate * delta, GAUGE_MIN, GAUGE_MAX)
			_dismiss_first_use_hint()
	if Input.is_key_pressed(KEY_Z):
		_damping = clampf(_damping - DAMPING_RATE * delta, DAMPING_MIN, DAMPING_MAX)
		_dismiss_first_use_hint()
	if Input.is_key_pressed(KEY_X):
		_damping = clampf(_damping + DAMPING_RATE * delta, DAMPING_MIN, DAMPING_MAX)
		_dismiss_first_use_hint()

	if _showing_first_use_hint:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_showing_first_use_hint = false

	_step_springs(minf(delta, MAX_PHYSICS_STEP))

	var all_in_band: bool = true
	for ch in CHAMBERS:
		if absf(_reading[ch] - _TARGETS[ch]) > _tolerance:
			all_in_band = false
	if all_in_band:
		_stability_timer += delta
		if _stability_timer >= _stability_duration:
			_commit_success()
	else:
		_stability_timer = 0.0

	_refresh()


## The coupled tuning puzzle: each chamber is a damped spring, but its
## own pull target is a WEIGHTED BLEND of all three setpoints (the
## coupling matrix row for that chamber), not just its own setpoint --
## see class doc comment for the full reasoning. Deliberately NOT
## clamped to GAUGE_MIN/MAX -- an underdamped overshoot past either end
## is a genuine, visible consequence of poor tuning, not a bug to hide.
func _step_springs(delta: float) -> void:
	var effective_target := {}
	for i in CHAMBERS.size():
		var row: Array = _coupling[i]
		var sum: float = 0.0
		for j in CHAMBERS.size():
			sum += row[j] * _setpoint[CHAMBERS[j]]
		effective_target[CHAMBERS[i]] = sum
	for ch in CHAMBERS:
		var accel: float = RESPONSE_STRENGTH * (effective_target[ch] - _reading[ch]) - _damping * _velocity[ch]
		_velocity[ch] += accel * delta
		_reading[ch] += _velocity[ch] * delta


## Solves M*S=T for the setpoint vector S that puts every chamber's
## READING exactly at its own target AT EQUILIBRIUM (velocity=0, so
## effective_target[i] == reading[i] == T[i] for all i) -- Gaussian
## elimination with partial pivoting on the general NxN system (Round 18
## Priority 3: generalized from Round 14's fixed 3x3 Cramer's-rule
## version per that round's own documented "FUTURE 4-6 CHAMBER EXPANSION
## SEAM" -- Cramer's rule's determinant expansion does not scale past a
## handful of rows; Gaussian elimination does). Row-normalized M (every
## row sums to 1.0, guaranteed by _build_neighbor_coupling()) guarantees
## this is always solvable whenever M is invertible: if M were the
## identity-like "uncoupled" case, S=T trivially; row-normalization
## generalizes that guarantee to any mix of coupling strengths, since M
## always maps the all-ones vector to itself, keeping the system well-
## posed. Used by tests/test_sensor_calibration_coupling.gd to verify,
## for every difficulty's matrix, that a real solution exists AND lands
## within the actual reachable regulator range [0,100] -- not merely
## that the math is solvable in the abstract.
static func _solve_equilibrium(matrix: Array, targets: Dictionary) -> Dictionary:
	var n: int = matrix.size()
	# Augmented matrix [M | T], rows duplicated so the input is untouched.
	var aug: Array = []
	for i in n:
		var row: Array = matrix[i].duplicate()
		row.append(targets[CHAMBERS[i]])
		aug.append(row)

	for col in n:
		# Partial pivoting: swap in the largest-magnitude remaining entry
		# in this column so a near-zero diagonal doesn't blow up the
		# division below -- not merely a theoretical concern once the
		# matrix stops being hand-picked for a clean 3x3 determinant.
		var pivot_row: int = col
		var pivot_val: float = absf(aug[col][col])
		for r in range(col + 1, n):
			if absf(aug[r][col]) > pivot_val:
				pivot_row = r
				pivot_val = absf(aug[r][col])
		if is_zero_approx(pivot_val):
			return {}
		if pivot_row != col:
			var tmp: Array = aug[col]
			aug[col] = aug[pivot_row]
			aug[pivot_row] = tmp
		var pivot: float = aug[col][col]
		for r in n:
			if r == col:
				continue
			var factor: float = aug[r][col] / pivot
			if is_zero_approx(factor):
				continue
			for c in range(col, n + 1):
				aug[r][c] -= factor * aug[col][c]

	var result: Dictionary = {}
	for i in n:
		result[CHAMBERS[i]] = aug[i][n] / aug[i][i]
	return result


func _commit_success() -> void:
	_done = true
	_station.mark_complete()
	if _sfx != null:
		_sfx.play_kind(&"success")


func _dismiss_first_use_hint() -> void:
	_showing_first_use_hint = false


## Only consumed to stop the adjustment/movement keys leaking to
## free_move_controller.gd while this view is open -- the actual
## adjustment is polled continuously in _process() above (matching
## free_move_controller.gd's own WASD-polling convention), not event-
## driven, so there is nothing else to act on here. Tab is the one
## edge-triggered action: toggles ALL THREE chamber gauges together
## between the circular and cylindrical styles -- one consistent
## design, never a mixed mode -- purely cosmetic, drives the exact same
## simulation/state either way.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_Z, KEY_X, KEY_SHIFT] or event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]):
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_use_cylinder_display = not _use_cylinder_display
		for ch in CHAMBERS:
			_chamber_rows[ch]["gauge"].visible = not _use_cylinder_display
			_chamber_rows[ch]["cylgauge"].visible = _use_cylinder_display
		_refresh()
		get_viewport().set_input_as_handled()


## Rotary-knob drag, shared by all four controls (three chamber
## regulators + damping, bound to this handler with their own name/node
## via Callable.bind in _ready()): click anywhere on a knob, then
## moving the mouse around its center turns it like a real dial -- the
## ANGULAR delta since the last frame (not the absolute angle) drives
## the corresponding value, so a knob can be spun past a full turn in
## either direction without snapping. Only one knob can be "grabbed" at
## a time (_dragging_control), so overlapping drag gestures across
## controls can't fight each other. Holding Shift while dragging a
## chamber knob applies the SAME shared fine-mode rate reduction as the
## keyboard path.
func _on_knob_gui_input(event: InputEvent, control_name: StringName, knob: Control) -> void:
	if _station == null or _done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging_control = control_name
			_drag_prev_angle = _angle_to_knob_center(knob, event.position)
		elif _dragging_control == control_name:
			_dragging_control = &""
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_control == control_name:
		var ang: float = _angle_to_knob_center(knob, event.position)
		var delta_ang: float = wrapf(ang - _drag_prev_angle, -PI, PI)
		_drag_prev_angle = ang
		var delta_deg: float = rad_to_deg(delta_ang)
		if control_name == &"damping":
			_damping = clampf(_damping + delta_deg / DAMPING_KNOB_DEGREES_PER_UNIT, DAMPING_MIN, DAMPING_MAX)
		elif control_name in CHAMBERS:
			var fine_factor: float = FINE_RATE_FACTOR if Input.is_key_pressed(KEY_SHIFT) else 1.0
			_setpoint[control_name] = clampf(_setpoint[control_name] + (delta_deg / REGULATOR_KNOB_DEGREES_PER_UNIT) * fine_factor, GAUGE_MIN, GAUGE_MAX)
		_dismiss_first_use_hint()
		get_viewport().set_input_as_handled()


func _angle_to_knob_center(knob: Control, local_pos: Vector2) -> float:
	var center: Vector2 = knob.size * 0.5
	var v: Vector2 = local_pos - center
	return atan2(v.y, v.x)


func _refresh() -> void:
	var all_in_band: bool = true
	for ch in CHAMBERS:
		var in_band: bool = absf(_reading[ch] - _TARGETS[ch]) <= _tolerance
		if not in_band:
			all_in_band = false
		var stability_fraction: float = clampf(_stability_timer / _stability_duration, 0.0, 1.0) if all_in_band else 0.0
		var active_gauge: Control = _chamber_rows[ch]["cylgauge"] if _use_cylinder_display else _chamber_rows[ch]["gauge"]
		active_gauge.target_value = _TARGETS[ch]
		active_gauge.tolerance = _tolerance
		active_gauge.set_readout(_setpoint[ch], _reading[ch], stability_fraction, in_band and not _done)
		_chamber_rows[ch]["pointer"].rotation = deg_to_rad((_setpoint[ch] / GAUGE_MAX) * 280.0 - 140.0)
		var status: Label = _chamber_rows[ch]["status"]
		var reading_label: Label = _chamber_rows[ch]["reading_label"]
		reading_label.text = "%s\nTarget %.0f ± %.0f   Now %.1f %s" % [CHAMBER_LABELS[ch], _TARGETS[ch], _tolerance, _reading[ch], _direction_arrow(ch)]
		if in_band:
			status.text = "IN RANGE"
			status.modulate = Color(0.4, 0.95, 0.5, 1)
		elif _reading[ch] < _TARGETS[ch] - _tolerance:
			status.text = "LOW"
			status.modulate = Color(0.95, 0.75, 0.3, 1)
		else:
			status.text = "HIGH"
			status.modulate = Color(0.95, 0.55, 0.3, 1)

	_damping_pointer.rotation = deg_to_rad(((_damping - DAMPING_MIN) / (DAMPING_MAX - DAMPING_MIN)) * 280.0 - 140.0)

	if _done:
		_status_label.text = "CALIBRATED — all chambers stable."
		_controls_label.text = "[Esc] Close"
		_stability_label.text = ""
		_hint_label.text = ""
		return

	_status_label.text = (
		"Bring every chamber into range, then hold steady."
		if _active_fault_count >= CHAMBERS.size()
		else "%d of %d chambers out of range — bring them in range and hold." % [_active_fault_count, CHAMBERS.size()]
	)
	_controls_label.text = "A[1/2] B[3/4] C[5/6] D[7/8] E[9/0] F[-/=]  ·  Shift = fine-tune  ·  Damping[Z/X]  ·  [Tab] Style  ·  [Esc] Exit"
	_stability_label.text = ("Stable: %.1fs / %.1fs" % [_stability_timer, _stability_duration]) if all_in_band else "Not yet stable — every chamber must be in range at once."
	if _showing_first_use_hint:
		var coupling_note: String = ""
		if GameSettings.get_difficulty() == GameSettings.Difficulty.EASY:
			coupling_note = " Each chamber's regulator mainly affects itself, but also nudges the other two a little — watch how their readings shift when you adjust one."
		_hint_label.text = "Each chamber has its own regulator and target range. Adjusting one chamber's regulator also shifts the others.%s" % coupling_note
	else:
		_hint_label.text = ""


## Per-chamber "is the gap to THIS chamber's own target actually
## closing" indicator -- compares this frame's distance-to-target
## against last frame's, not the raw sign of the setpoint (which only
## shows which way the player is CURRENTLY turning that regulator, not
## whether that is actually helping once coupling/lag/oscillation from
## the OTHER two chambers is in play).
func _direction_arrow(ch: StringName) -> String:
	var gap: float = absf(_reading[ch] - _TARGETS[ch])
	var arrow: String
	if _prev_gap[ch] < 0.0:
		arrow = ""
	elif gap < _prev_gap[ch] - DIRECTION_DEADBAND:
		arrow = "▲"
	elif gap > _prev_gap[ch] + DIRECTION_DEADBAND:
		arrow = "▼"
	else:
		arrow = "●"
	_prev_gap[ch] = gap
	return arrow
