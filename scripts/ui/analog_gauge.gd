extends Control
## A procedurally-drawn analog instrument gauge -- custom _draw(), no
## external assets, reusable wherever this project wants a believable
## spacecraft dial instead of a flat progress-bar-style readout. Built
## for scripts/ui/sensor_calibration_view.gd's L07 task, but kept
## generic (min_value/max_value/target/tolerance are all exported) so
## it is not a single-purpose script.
##
## Draws, back to front: a dark face, tick marks, a colored tolerance
## band, a dim "dial setting" needle (what the player is currently
## commanding), and a brighter "measured reading" needle (the actual,
## lagging sensor value) -- the two needles are the main way the
## player SEES the distinction between "what I'm asking for" and "what
## the sensor is actually reporting" that this milestone's brief asks
## for, without reading two numbers off a label.

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var sweep_start_degrees: float = -130.0
@export var sweep_end_degrees: float = 130.0

@export var target_value: float = 50.0
@export var tolerance: float = 3.0
@export var dial_value: float = 0.0
@export var reading_value: float = 0.0
## 0..1 -- how close the current stability hold is to committing
## success; drives the reading needle's glow.
@export var stability_fraction: float = 0.0
@export var in_tolerance: bool = false

const COLOR_FACE := Color(0.08, 0.09, 0.1, 1)
const COLOR_RIM := Color(0.2, 0.21, 0.23, 1)
const COLOR_TICK := Color(0.45, 0.46, 0.48, 1)
const COLOR_TOLERANCE := Color(0.3, 0.55, 0.35, 0.55)
const COLOR_DIAL_NEEDLE := Color(0.75, 0.6, 0.25, 0.9)
const COLOR_READING_NEEDLE_COLD := Color(0.8, 0.82, 0.85, 1)
const COLOR_READING_NEEDLE_HOT := Color(0.3, 0.95, 0.4, 1)
const COLOR_HUB := Color(0.3, 0.31, 0.33, 1)


func _ready() -> void:
	resized.connect(queue_redraw)


func set_readout(dial: float, reading: float, stability: float, within: bool) -> void:
	dial_value = dial
	reading_value = reading
	stability_fraction = stability
	in_tolerance = within
	queue_redraw()


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - 4.0
	if r <= 4.0:
		return
	var center: Vector2 = size * 0.5

	draw_circle(center, r, COLOR_FACE)
	draw_arc(center, r, 0.0, TAU, 48, COLOR_RIM, 3.0, true)

	# Tolerance band.
	var lo_angle: float = _angle_for(target_value - tolerance)
	var hi_angle: float = _angle_for(target_value + tolerance)
	draw_arc(center, r * 0.86, lo_angle, hi_angle, 24, COLOR_TOLERANCE, r * 0.14, true)

	# Round 10 Workstream F: small on-face labels at the needle tips --
	# the same "name the thing, don't make the player guess from color
	# alone" legend added to cylindrical_gauge.gd, shared font/size so
	# both instruments read consistently despite the different needle
	# layout.
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10
	var target_mid_ang: float = _angle_for(target_value)
	var target_label_pos: Vector2 = center + Vector2(cos(target_mid_ang), sin(target_mid_ang)) * r * 0.98
	draw_string(font, target_label_pos, "TARGET", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TOLERANCE)

	# Tick marks every 10% of the range.
	var steps: int = 10
	for i in (steps + 1):
		var v: float = min_value + (max_value - min_value) * float(i) / float(steps)
		var ang: float = _angle_for(v)
		var p0: Vector2 = center + Vector2(cos(ang), sin(ang)) * r * 0.78
		var p1: Vector2 = center + Vector2(cos(ang), sin(ang)) * r * 0.92
		draw_line(p0, p1, COLOR_TICK, 2.0, true)

	# Dial-setting needle (dim, shorter) -- what the player is commanding.
	var dial_ang: float = _angle_for(dial_value)
	var dial_tip: Vector2 = center + Vector2(cos(dial_ang), sin(dial_ang)) * r * 0.55
	draw_line(center, dial_tip, COLOR_DIAL_NEEDLE, 3.0, true)
	draw_string(font, dial_tip + Vector2(cos(dial_ang), sin(dial_ang)) * 10.0, "SET", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_DIAL_NEEDLE)

	# Reading needle (bright, longer) -- the actual lagging sensor value.
	var reading_ang: float = _angle_for(reading_value)
	var needle_color: Color = COLOR_READING_NEEDLE_HOT if in_tolerance else COLOR_READING_NEEDLE_COLD
	if in_tolerance:
		needle_color = needle_color.lerp(Color(1, 1, 1, 1), 0.25 * stability_fraction)
	var reading_tip: Vector2 = center + Vector2(cos(reading_ang), sin(reading_ang)) * r * 0.82
	draw_line(center, reading_tip, needle_color, 4.0, true)
	draw_string(font, reading_tip + Vector2(cos(reading_ang), sin(reading_ang)) * 10.0, "READING", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, needle_color)

	draw_circle(center, r * 0.06, COLOR_HUB)


func _angle_for(value: float) -> float:
	var t: float = clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)
	return deg_to_rad(lerpf(sweep_start_degrees, sweep_end_degrees, t) - 90.0)
