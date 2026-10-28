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

const CHAMBERS: Array[StringName] = [&"a", &"b", &"c"]
const CHAMBER_LABELS := {&"a": "CHAMBER A", &"b": "CHAMBER B", &"c": "CHAMBER C"}

## The ONE fixed target pressure per chamber, shared across every
## difficulty (see class doc comment for why this stays constant while
## only the coupling matrix/tolerance/duration vary).
const _TARGETS := {&"a": 40.0, &"b": 58.0, &"c": 65.0}
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

## Keyboard fallback per chamber: [decrease, increase].
const _CHAMBER_KEYS := {
	&"a": [KEY_1, KEY_2],
	&"b": [KEY_3, KEY_4],
	&"c": [KEY_5, KEY_6],
}

## Row-normalized (each row sums to EXACTLY 1.0) 3x3 coupling matrices,
## indexed [row][col] = how much chamber `col`'s regulator influences
## chamber `row`'s effective target. The diagonal dominates in every
## difficulty (each chamber still mostly follows its own regulator);
## only the OFF-diagonal strength (how much the other two leak in)
## changes. Row-sum = 1.0 is what guarantees a reachable equilibrium
## exists for any target vector -- see _solve_equilibrium()'s doc
## comment.
const _COUPLING_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: [
		[0.85, 0.10, 0.05],
		[0.08, 0.84, 0.08],
		[0.05, 0.10, 0.85],
	],
	GameSettings.Difficulty.NORMAL: [
		[0.70, 0.20, 0.10],
		[0.15, 0.65, 0.20],
		[0.05, 0.25, 0.70],
	],
	GameSettings.Difficulty.HARD: [
		[0.55, 0.30, 0.15],
		[0.25, 0.50, 0.25],
		[0.15, 0.35, 0.50],
	],
}
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
## FUTURE 4-6 CHAMBER EXPANSION SEAM: _step_springs() and the win-check
## loop already iterate generically over CHAMBERS.size(), so adding
## chambers there needs no changes. The one piece NOT yet N-agnostic is
## _solve_equilibrium()'s hand-expanded 3x3 Cramer's-rule determinant --
## extending CHAMBERS/the coupling matrices/_TARGETS past 3 entries would
## need that solver generalized to NxN (e.g. Gaussian elimination) before
## a verification test like test_sensor_calibration_coupling.gd could
## confirm a 4-6 chamber matrix's equilibrium the same way. Not done this
## round per the brief's own "even if not fully shipped" allowance --
## flagged here precisely so a future round does not have to rediscover
## this seam by trial and error.
## Round 16 Priority 8: fault count now comes from the station's own
## exported active_fault_count() (a work-order-scenario property), not
## from global difficulty -- see sensor_calibration_station.gd's class
## doc comment for the full reasoning. This dict is gone; difficulty
## still independently controls _coupling/_tolerance/_stability_duration
## below, which legitimately ARE difficulty concerns (how forgiving the
## attempt is), unlike fault count (how many problems exist at all).

@onready var _focused_state: Node = get_node(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)

@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _stability_label: Label = $Panel/VBox/StabilityLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _hint_label: Label = $Panel/VBox/HintLabel

@onready var _chamber_rows := {
	&"a": {
		"reading_label": $Panel/VBox/ChamberRow/ChamberA/Inner/ReadingLabel,
		"gauge": $Panel/VBox/ChamberRow/ChamberA/Inner/GaugeStack/Gauge,
		"cylgauge": $Panel/VBox/ChamberRow/ChamberA/Inner/GaugeStack/CylinderGauge,
		"knob": $Panel/VBox/ChamberRow/ChamberA/Inner/Knob,
		"pointer": $Panel/VBox/ChamberRow/ChamberA/Inner/Knob/Pointer,
		"status": $Panel/VBox/ChamberRow/ChamberA/Inner/StatusChip,
	},
	&"b": {
		"reading_label": $Panel/VBox/ChamberRow/ChamberB/Inner/ReadingLabel,
		"gauge": $Panel/VBox/ChamberRow/ChamberB/Inner/GaugeStack/Gauge,
		"cylgauge": $Panel/VBox/ChamberRow/ChamberB/Inner/GaugeStack/CylinderGauge,
		"knob": $Panel/VBox/ChamberRow/ChamberB/Inner/Knob,
		"pointer": $Panel/VBox/ChamberRow/ChamberB/Inner/Knob/Pointer,
		"status": $Panel/VBox/ChamberRow/ChamberB/Inner/StatusChip,
	},
	&"c": {
		"reading_label": $Panel/VBox/ChamberRow/ChamberC/Inner/ReadingLabel,
		"gauge": $Panel/VBox/ChamberRow/ChamberC/Inner/GaugeStack/Gauge,
		"cylgauge": $Panel/VBox/ChamberRow/ChamberC/Inner/GaugeStack/CylinderGauge,
		"knob": $Panel/VBox/ChamberRow/ChamberC/Inner/Knob,
		"pointer": $Panel/VBox/ChamberRow/ChamberC/Inner/Knob/Pointer,
		"status": $Panel/VBox/ChamberRow/ChamberC/Inner/StatusChip,
	},
}
@onready var _damping_knob: Control = $Panel/VBox/SharedControls/DampingKnob
@onready var _damping_pointer: Control = $Panel/VBox/SharedControls/DampingKnob/Pointer

var _station: Node = null
var _setpoint := {&"a": START_VALUE, &"b": START_VALUE, &"c": START_VALUE}
var _reading := {&"a": START_VALUE, &"b": START_VALUE, &"c": START_VALUE}
var _velocity := {&"a": 0.0, &"b": 0.0, &"c": 0.0}
var _prev_gap := {&"a": -1.0, &"b": -1.0, &"c": -1.0}
var _damping: float = START_DAMPING
var _stability_timer: float = 0.0
var _done: bool = false
var _tolerance: float = 4.0
var _stability_duration: float = 1.8
var _coupling: Array = []
var _active_fault_count: int = 3

var _dragging_control: StringName = &""
var _drag_prev_angle: float = 0.0
var _use_cylinder_display: bool = false

static var _ever_opened: bool = false
var _showing_first_use_hint: bool = false
var _hint_timer: float = 0.0
const _FIRST_USE_HINT_DURATION: float = 9.0


func _ready() -> void:
	visible = false
	for ch in CHAMBERS:
		var knob: Control = _chamber_rows[ch]["knob"]
		knob.gui_input.connect(_on_knob_gui_input.bind(ch, knob))
	_damping_knob.gui_input.connect(_on_knob_gui_input.bind(&"damping", _damping_knob))


## Called by sensor_calibration_station.gd's interact().
func open_station(station: Node) -> void:
	_station = station
	if not _focused_state.begin(self):
		return
	visible = true
	_done = station.is_complete()
	var difficulty: int = GameSettings.get_difficulty()
	var fault_count: int = station.active_fault_count()
	var active: Array = CHAMBERS.slice(0, fault_count)
	for ch in CHAMBERS:
		# Round 16 Priority 8: only this WORK ORDER's active (faulty)
		# chambers (station.active_fault_count(), independent of global
		# difficulty -- see sensor_calibration_station.gd's class doc
		# comment) start away from their target; the rest start already
		# solved. Difficulty still independently scales _coupling/
		# _tolerance/_stability_duration below (how forgiving the
		# attempt is), never how many chambers are broken.
		_setpoint[ch] = START_VALUE if ch in active else _TARGETS[ch]
		_reading[ch] = START_VALUE if ch in active else _TARGETS[ch]
		_velocity[ch] = 0.0
		_prev_gap[ch] = -1.0
	_damping = START_DAMPING
	_stability_timer = 0.0
	_dragging_control = &""
	_use_cylinder_display = false # circular dial is the default/primary style
	_coupling = _COUPLING_BY_DIFFICULTY.get(difficulty, _COUPLING_BY_DIFFICULTY[GameSettings.Difficulty.NORMAL])
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
## effective_target[i] == reading[i] == T[i] for all i) -- Cramer's
## rule on the fixed 3x3 system. Row-normalized M (every row sums to
## 1.0, true of every authored matrix above) guarantees this is always
## solvable whenever M is invertible: if M were the identity-like
## "uncoupled" case, S=T trivially; row-normalization generalizes that
## guarantee to any mix of coupling strengths, since M always maps the
## all-ones vector to itself, keeping the system well-posed. Used by
## tests/test_sensor_calibration_coupling.gd to verify, for every
## difficulty's matrix, that a real solution exists AND lands within
## the actual reachable regulator range [0,100] -- not merely that the
## math is solvable in the abstract.
static func _solve_equilibrium(matrix: Array, targets: Dictionary) -> Dictionary:
	var m: Array = matrix
	var t: Array = [targets[&"a"], targets[&"b"], targets[&"c"]]
	var det: float = (
		m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
		- m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
		+ m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
	)
	if is_zero_approx(det):
		return {}
	var result: Array = [0.0, 0.0, 0.0]
	for col in 3:
		var mc: Array = [m[0].duplicate(), m[1].duplicate(), m[2].duplicate()]
		for row in 3:
			mc[row][col] = t[row]
		var det_c: float = (
			mc[0][0] * (mc[1][1] * mc[2][2] - mc[1][2] * mc[2][1])
			- mc[0][1] * (mc[1][0] * mc[2][2] - mc[1][2] * mc[2][0])
			+ mc[0][2] * (mc[1][0] * mc[2][1] - mc[1][1] * mc[2][0])
		)
		result[col] = det_c / det
	return {&"a": result[0], &"b": result[1], &"c": result[2]}


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
		_status_label.text = "CALIBRATED — all three chambers stable."
		_controls_label.text = "[Esc] Close"
		_stability_label.text = ""
		_hint_label.text = ""
		return

	_status_label.text = (
		"Bring all three chambers into range and hold them there simultaneously."
		if _active_fault_count >= CHAMBERS.size()
		else "%d of %d chambers are out of range — bring every chamber into range and hold them there simultaneously." % [_active_fault_count, CHAMBERS.size()]
	)
	_controls_label.text = "A [1/2]  B [3/4]  C [5/6] (hold Shift to fine-tune)   Damping [Z/X]   [Tab] Gauge Style   [Esc] Exit (no progress lost)"
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
