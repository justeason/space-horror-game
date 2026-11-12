extends Node3D
## Round 48 Priority 5: the Living Quarters WALL CALENDAR follows the
## authoritative game day (DayPlan.day_number), never the computer's date.
##
## Fiction: the rotation's Day 1 is 1 October 2026 (the laptop's personal
## files and the previous technician's archive are dated around it). The
## calendar shows the page of the month the current day falls in; days
## already lived on that page carry a small red slash, TODAY is circled in
## red, future days are blank. Day 32 turns the page to November (and so
## on: real month lengths and weekdays, no Day-31 limit).
##
## Priority 6: a PRESENTATION hook for later horror (set_anomaly()). It only
## changes what is DRAWN -- the authoritative day is never touched -- and
## Phase 1 never calls it (story_events gates it; the F8 panel can preview
## one as a developer-only, uncounted preview).

const START := {"year": 2026, "month": 10, "day": 1}
const MONTHS_EN := ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
const WEEK_EN := ["M", "T", "W", "T", "F", "S", "S"]
const WEEK_ZH := ["一", "二", "三", "四", "五", "六", "日"]
const W := 0.36
const H := 0.50
const CELL := Vector2(0.046, 0.044)
const RED := Color(0.78, 0.1, 0.08)
const INK := Color(0.12, 0.12, 0.13)

var shown_day: int = -1
var page: Dictionary = {}          # {"year", "month"} of the page shown
var anomaly: StringName = &""      # presentation only ("" = trustworthy)
var anomaly_dev: bool = false      # developer preview (never counted)
var _dp: Node
var _cells: Dictionary = {}        # day-of-month -> {"pos": Vector3, "label": Label3D}
var _marks: Node3D
var _grid: Node3D
var _title: Label3D
var _lang: String = ""
var _poll_t: float = 0.0


func _ready() -> void:
	name = "WallCalendar"
	_dp = get_tree().get_first_node_in_group(&"day_plan")
	var paper := _quad(Vector2(W, H), Vector3.ZERO, Color(0.93, 0.92, 0.87), 0.85)
	paper.name = "Paper"
	# The photo strip at the top (a plain teal panel with a hanger hole).
	_quad(Vector2(W, 0.12), Vector3(0, H * 0.5 - 0.06, 0.0008), Color(0.24, 0.38, 0.42), 0.7)
	_quad(Vector2(0.012, 0.012), Vector3(0, H * 0.5 - 0.012, 0.0012), Color(0.15, 0.15, 0.15), 0.9)
	# Binding wire.
	var bind := _quad(Vector2(W * 0.9, 0.006), Vector3(0, H * 0.5 - 0.122, 0.0012), Color(0.55, 0.55, 0.58), 0.4)
	bind.name = "Binding"
	_title = _text("", Vector3(0, H * 0.5 - 0.148, 0.0015), 34, INK)
	_grid = Node3D.new()
	_grid.name = "Grid"
	add_child(_grid)
	_marks = Node3D.new()
	_marks.name = "Marks"
	add_child(_marks)
	refresh(true)


func _process(delta: float) -> void:
	_poll_t += delta
	if _poll_t < 0.5:
		return
	_poll_t = 0.0
	refresh()


func _day() -> int:
	if _dp == null:
		_dp = get_tree().get_first_node_in_group(&"day_plan")
	return int(_dp.day_number) if _dp != null else 1


## Calendar date {"year","month","day","weekday"(0 = Monday)} of game day n.
static func date_of(n: int) -> Dictionary:
	var t0: int = Time.get_unix_time_from_datetime_dict({"year": START.year, "month": START.month, "day": START.day, "hour": 12, "minute": 0, "second": 0})
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(t0 + (maxi(n, 1) - 1) * 86400)
	return {"year": int(d.year), "month": int(d.month), "day": int(d.day), "weekday": (int(d.weekday) + 6) % 7}


static func month_length(year: int, month: int) -> int:
	if month == 2:
		return 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28
	return 30 if month in [4, 6, 9, 11] else 31


## Game day of the 1st of the shown page (may be < 1 for the first page:
## days before the rotation began stay blank, never marked).
func _page_first_day(today: int) -> int:
	return today - int(date_of(today).day) + 1


func _zh() -> bool:
	return TranslationServer.get_locale().begins_with("zh")


## Re-draws when the day (or language) changed, or when forced.
func refresh(force: bool = false) -> void:
	var today: int = _day()
	var lang: String = "zh" if _zh() else "en"
	if not force and today == shown_day and lang == _lang:
		return
	var redraw_grid: bool = force or lang != _lang or page.is_empty()
	shown_day = today
	_lang = lang
	var dt: Dictionary = date_of(today)
	if page.get("year", -1) != dt.year or page.get("month", -1) != dt.month:
		redraw_grid = true
	page = {"year": dt.year, "month": dt.month}
	if redraw_grid:
		_build_grid(dt.year, dt.month)
	_draw_marks(today)


func _build_grid(year: int, month: int) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()
	_title.text = ("%d年%d月" % [year, month]) if _lang == "zh" else ("%s %d" % [MONTHS_EN[month - 1], year])
	var x0: float = -CELL.x * 3.0
	var y0: float = H * 0.5 - 0.178
	var names: Array = WEEK_ZH if _lang == "zh" else WEEK_EN
	for c in 7:
		var l := _text(names[c], Vector3(x0 + c * CELL.x, y0, 0.0015), 19, RED if c == 6 else Color(0.35, 0.35, 0.38), _grid)
		l.name = "Weekday%d" % c
	# weekday of the 1st of this month
	var t: int = Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 1, "hour": 12, "minute": 0, "second": 0})
	var wd: int = (int(Time.get_datetime_dict_from_unix_time(t).weekday) + 6) % 7
	var n: int = month_length(year, month)
	for d in range(1, n + 1):
		var slot: int = wd + d - 1
		var row: int = slot / 7
		var col: int = slot % 7
		if row > 5:
			row = 5
		var p := Vector3(x0 + col * CELL.x, y0 - 0.034 - row * CELL.y, 0.0015)
		var l := _text(str(d), p, 30, RED if col == 6 else INK, _grid)
		l.name = "Day%02d" % d
		_cells[d] = {"pos": p, "label": l}
	# a faint ruled grid behind the numbers
	var rows: int = int(ceil(float(wd + n) / 7.0))
	for r in rows + 1:
		_quad(Vector2(CELL.x * 7.0, 0.0012), Vector3(0, y0 - 0.012 - r * CELL.y, 0.0011), Color(0.75, 0.74, 0.7), 0.9, _grid)


func _draw_marks(today: int) -> void:
	for c in _marks.get_children():
		c.queue_free()
	var first_day: int = _page_first_day(today)
	for d in _cells:
		var game_day: int = first_day + int(d) - 1
		var state: StringName = &""
		if game_day >= 1 and game_day < today:
			state = &"past"
		elif game_day == today:
			state = &"today"
		# Presentation-only anomalies (never Phase 1; see set_anomaly()).
		if anomaly == &"tomorrow_marked" and game_day == today + 1:
			state = &"foreign"
		elif anomaly == &"mark_missing" and game_day == today - 1 and state == &"past":
			state = &""
		if state == &"past":
			_slash(_cells[d]["pos"], d)
		elif state == &"today":
			_ring(_cells[d]["pos"], 0.0185, 0.0028, RED)
		elif state == &"foreign":
			# a ring drawn by someone else: darker, thinner, not quite closed
			_ring(_cells[d]["pos"], 0.02, 0.0014, Color(0.3, 0.04, 0.04), 300.0)


## Public state for tests / dev panel: {"day", "page", "past": [...], "today": n, "anomaly"}.
func marks() -> Dictionary:
	var out := {"day": shown_day, "page": page.duplicate(), "past": [], "today": -1, "foreign": [], "anomaly": String(anomaly)}
	for m in _marks.get_children():
		if m.is_queued_for_deletion():
			continue
		var d: int = int(m.get_meta("dom", 0))
		match String(m.get_meta("kind", "")):
			"past": out["past"].append(d)
			"today": out["today"] = d
			"foreign": out["foreign"].append(d)
	out["past"].sort()
	return out


## Priority 6 hook. kind: &"tomorrow_marked" | &"mark_missing" | &"" (clear).
## Presentation only; DayPlan.day_number is never read-modified here.
func set_anomaly(kind: StringName, dev: bool = false) -> void:
	anomaly = kind
	anomaly_dev = dev and kind != &""
	refresh(true)


func _slash(p: Vector3, dom: int) -> void:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.036, 0.003)
	m.mesh = q
	m.material_override = _mat(RED, 0.8)
	m.position = p + Vector3(0, 0.002, 0.0006)
	m.rotation.z = deg_to_rad(38.0 + float(hash([dom, "slash"]) % 9) - 4.0)
	m.set_meta("kind", "past")
	m.set_meta("dom", dom)
	_marks.add_child(m)


func _ring(p: Vector3, r: float, w: float, col: Color, arc_deg: float = 360.0) -> void:
	var holder := Node3D.new()
	holder.position = p + Vector3(0, 0.003, 0.0008)
	var dom: int = -1
	for d in _cells:
		if (_cells[d]["pos"] as Vector3).is_equal_approx(p):
			dom = int(d)
	holder.set_meta("dom", dom)
	holder.set_meta("kind", "today" if col == RED else "foreign")
	_marks.add_child(holder)
	# A hand-drawn ring: short quad segments, slightly elliptical.
	var segs: int = 22
	var steps: int = int(round(segs * arc_deg / 360.0))
	for i in steps:
		var a0: float = TAU * float(i) / segs + 0.3
		var a1: float = TAU * float(i + 1) / segs + 0.3
		var p0 := Vector2(cos(a0) * r * 1.12, sin(a0) * r)
		var p1 := Vector2(cos(a1) * r * 1.12, sin(a1) * r)
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(p0.distance_to(p1) + w * 0.6, w)
		m.mesh = q
		m.material_override = _mat(col, 0.8)
		var mid: Vector2 = (p0 + p1) * 0.5
		m.position = Vector3(mid.x, mid.y, 0)
		m.rotation.z = (p1 - p0).angle()
		holder.add_child(m)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _quad(size: Vector2, pos: Vector3, c: Color, rough: float, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	m.mesh = q
	m.material_override = _mat(c, rough)
	m.position = pos
	(parent if parent != null else self).add_child(m)
	return m


func _text(t: String, pos: Vector3, size: int, c: Color, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.00042
	l.modulate = c
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	(parent if parent != null else self).add_child(l)
	return l
