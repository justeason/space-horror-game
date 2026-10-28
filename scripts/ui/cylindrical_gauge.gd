extends Control
## A procedurally-drawn CYLINDRICAL drum-style instrument -- the second,
## visually distinct calibration-instrument style requested alongside
## scripts/ui/analog_gauge.gd's circular clock-like dial. Same public
## API shape as analog_gauge.gd (min/max_value, target_value, tolerance,
## dial_value, reading_value, stability_fraction, in_tolerance,
## set_readout()) so either can be dropped into a focused view
## interchangeably, but the VISUAL METAPHOR is completely different: a
## vertical graduated drum that scrolls past a fixed window (the classic
## altimeter/rotating-drum-gauge look), not a needle on a circular face.
##
## Deliberately NOT wired into L07 Environmental Sensor Calibration --
## that task keeps its existing analog_gauge.gd dial and existing
## simulation untouched (per this milestone's explicit constraint: don't
## force two instrument styles into one task, don't invent a new task
## ID just to showcase this). This is a standalone, reusable visual
## component intended for a LATER maintenance/calibration task to adopt
## -- see MILESTONE1_DESIGN.md's Round 9 entry for the documented
## integration path (a plausible candidate: L04 Valve Procedure or a
## future pressure/flow gauge, neither implemented this round).
##
## Drawn, not textured: a housing frame, a vertical scale strip that
## SCROLLS so the current reading always sits at the fixed window
## center (the drum "rotates" by scrolling its printed scale, not by
## literally spinning a 3D mesh -- the same prototype-tier simplification
## analog_gauge.gd's needles already use instead of true 3D), a subtle
## left-right shading gradient across the strip to suggest a curved
## cylindrical surface catching light, a fixed target tick, and a
## bright window indicator for the actual reading.

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var target_value: float = 50.0
@export var tolerance: float = 3.0
@export var dial_value: float = 0.0
@export var reading_value: float = 0.0
@export var stability_fraction: float = 0.0
@export var in_tolerance: bool = false

## How many scale units are visible across the window's height at once
## -- smaller = more "zoomed in" on the drum.
@export var visible_span: float = 24.0

const COLOR_HOUSING := Color(0.15, 0.16, 0.18, 1)
const COLOR_WINDOW_BG := Color(0.07, 0.08, 0.09, 1)
const COLOR_TICK_MAJOR := Color(0.62, 0.64, 0.66, 1)
const COLOR_TICK_MINOR := Color(0.4, 0.42, 0.44, 1)
## Round 10 Workstream F: the target marker used to be nearly the same
## gold tone as the dial-setting marker below (0.75,0.6,0.25 vs.
## 0.7,0.55,0.3) -- the player's actual reported complaint ("doesn't
## clearly understand how to operate/interpret" the drum gauge) traces
## to exactly this: the two most important distinct concepts on the
## instrument were visually almost identical. TARGET is now the same
## green family as the circular gauge's tolerance band/hot-reading
## glow, and the dial tick below keeps gold -- one consistent color
## vocabulary (green = target/success, gold = your commanded setting,
## white->green = actual lagging reading) shared by BOTH gauge styles,
## per the brief's "consistent visual language where helpful".
const COLOR_TARGET := Color(0.35, 0.75, 0.45, 1)
const COLOR_READING_COLD := Color(0.8, 0.84, 0.88, 1)
const COLOR_READING_HOT := Color(0.3, 0.95, 0.4, 1)
const COLOR_DIAL_TICK := Color(0.85, 0.65, 0.25, 1)


func _ready() -> void:
	resized.connect(queue_redraw)


func set_readout(dial: float, reading: float, stability: float, within: bool) -> void:
	dial_value = dial
	reading_value = reading
	stability_fraction = stability
	in_tolerance = within
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 4.0 or h <= 4.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), COLOR_HOUSING, true)
	var window_margin: Vector2 = Vector2(w * 0.12, h * 0.06)
	var window_rect := Rect2(window_margin, size - window_margin * 2.0)
	draw_rect(window_rect, COLOR_WINDOW_BG, true)

	# Cylindrical shading: a soft brighten-then-darken sweep across the
	# window's width, like light curving over a rounded drum surface.
	var shade_steps := 10
	for i in shade_steps:
		var t: float = float(i) / float(shade_steps - 1)
		var curve: float = 1.0 - abs(t - 0.5) * 2.0 # 0 at edges, 1 at center
		var a: float = 0.05 + 0.05 * curve
		var seg_w: float = window_rect.size.x / float(shade_steps)
		var seg_rect := Rect2(window_rect.position + Vector2(seg_w * i, 0), Vector2(seg_w, window_rect.size.y))
		draw_rect(seg_rect, Color(1, 1, 1, a), true)

	# Scrolling vertical scale: reading_value always sits at the
	# window's vertical center; everything else scrolls past it.
	var px_per_unit: float = window_rect.size.y / visible_span
	var center_y: float = window_rect.position.y + window_rect.size.y * 0.5

	var first_tick: float = floor((reading_value - visible_span * 0.5) / 2.0) * 2.0
	var v: float = first_tick
	while v <= reading_value + visible_span * 0.5:
		var y: float = center_y - (v - reading_value) * px_per_unit
		if y >= window_rect.position.y and y <= window_rect.position.y + window_rect.size.y:
			var is_major: bool = int(round(v)) % 10 == 0
			var tick_w: float = window_rect.size.x * (0.4 if is_major else 0.22)
			var cx: float = window_rect.position.x + window_rect.size.x * 0.5
			draw_line(Vector2(cx - tick_w * 0.5, y), Vector2(cx + tick_w * 0.5, y), COLOR_TICK_MAJOR if is_major else COLOR_TICK_MINOR, 1.5 if is_major else 1.0, true)
		v += 2.0

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10

	# Target tick -- fixed scale position, scrolls like everything else.
	var target_y: float = center_y - (target_value - reading_value) * px_per_unit
	if target_y >= window_rect.position.y - 4.0 and target_y <= window_rect.position.y + window_rect.size.y + 4.0:
		draw_line(Vector2(window_rect.position.x, target_y), Vector2(window_rect.position.x + window_rect.size.x, target_y), COLOR_TARGET, 2.0, true)
		# Tolerance band as two faint bracket lines above/below target.
		var tol_px: float = tolerance * px_per_unit
		draw_line(Vector2(window_rect.position.x, target_y - tol_px), Vector2(window_rect.position.x + window_rect.size.x * 0.25, target_y - tol_px), COLOR_TARGET, 1.0, true)
		draw_line(Vector2(window_rect.position.x, target_y + tol_px), Vector2(window_rect.position.x + window_rect.size.x * 0.25, target_y + tol_px), COLOR_TARGET, 1.0, true)
		draw_string(font, Vector2(window_rect.position.x + window_rect.size.x * 0.3, target_y - 3.0), "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_TARGET)

	# Fixed window indicator -- the actual reading, always centered.
	var reading_color: Color = COLOR_READING_HOT if in_tolerance else COLOR_READING_COLD
	if in_tolerance:
		reading_color = reading_color.lerp(Color(1, 1, 1, 1), 0.2 * stability_fraction)
	draw_rect(Rect2(window_rect.position.x - 6, center_y - 1.5, window_rect.size.x + 12, 3), reading_color, true)
	draw_line(Vector2(window_rect.position.x - 6, center_y - 7), Vector2(window_rect.position.x - 6, center_y + 7), reading_color, 2.0, true)
	draw_line(Vector2(window_rect.position.x + window_rect.size.x + 6, center_y - 7), Vector2(window_rect.position.x + window_rect.size.x + 6, center_y + 7), reading_color, 2.0, true)
	draw_string(font, Vector2(window_rect.position.x + window_rect.size.x + 10, center_y + 3.0), "READING", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, reading_color)

	# Dial-setting indicator (gold, a solid wedge pointing INTO the
	# window) on the opposite side from the reading markers -- the
	# commanded value, distinct from the actual (lagging) reading shown
	# in the window. Made deliberately bold/arrow-shaped rather than a
	# thin line, since a thin same-toned tick was the actual player-
	# reported "can't tell what I'm adjusting" problem on this gauge.
	var dial_y: float = center_y - (dial_value - reading_value) * px_per_unit
	if dial_y >= 0.0 and dial_y <= h:
		var tip_x: float = window_rect.position.x - 1.0
		var points := PackedVector2Array([
			Vector2(2.0, dial_y - 5.0),
			Vector2(2.0, dial_y + 5.0),
			Vector2(tip_x, dial_y),
		])
		draw_colored_polygon(points, COLOR_DIAL_TICK)
		draw_string(font, Vector2(2.0, dial_y - 8.0), "SET", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_DIAL_TICK)
