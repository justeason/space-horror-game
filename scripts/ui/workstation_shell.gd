extends Control
## Round 37 Priorities 7-9: the Control Room workstation's VISIBLE interface
## -- three sections instead of seven tabs, map first, mouse-clickable.
##   OPERATIONS (default): the station MAP (the real room topology, read
##     from the existing map layout). Each room shows its HIGHEST real
##     severity from StationStatus (the one shared status model):
##       normal = neutral; routine = orange outline + orange circle badge
##       (gentle pulse); warning = amber fill + diamond badge; emergency =
##       red, pulsing (steady when "steady warning lights" is on), triangle
##       "!" badge. Shape + colour, never colour alone.
##     Selecting a room lists ITS duties, one line each; clicking a duty
##     shows a few detail lines. Day actions (CHECK IN, VERIFY, DIAGNOSTIC,
##     CAMERA) are buttons. A red strip shows a pending emergency.
##   RECORDS: today's log, shift reports, service history.
##   SYSTEM: settings (click a row / < >) and SAVE / LOAD / NEW GAME (the
##     established safe, deferred load path).
## The old seven sections (workstation_screen.gd) stay as the keyboard
## API and the text model the tests read; this shell is what is shown.

const GS = preload("res://scripts/station/game_settings.gd")
enum Page { OPS, CAMERAS, RECORDS, SYSTEM }
const SEV_COLORS := [Color(0.22, 0.24, 0.27), Color(0.95, 0.55, 0.12), Color(1.0, 0.72, 0.12), Color(0.95, 0.15, 0.1)]
const SEV_WORDS := ["NOMINAL", "ROUTINE", "WARNING", "EMERGENCY"]

var screen: Node            # workstation_screen.gd
var dp: Node
var page: int = Page.OPS
var selected_room: StringName = &"control_room"
var selected_duty: int = -1
var ops_panel: String = ""  # "" | "diag"
var room_buttons: Dictionary = {}   # room -> Button
var duty_buttons: Array = []
var tab_buttons: Array = []
var action_buttons: Dictionary = {} # name -> Button
var setting_buttons: Array = []
var _t: float = 0.0
var _title: Label
var _emerg: Label
var _pages: Array = []
var _room_title: Label
var _room_badge: Control
var _duty_box: VBoxContainer
var _detail: Label
var _footer: Label
var _diag: Label
var _records: Label
var _sys_status: Label
var _save_info: Label
var _map: Control


class Badge extends Control:
	var severity: int = 0
	var pulse: float = 1.0
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.45
		match severity:
			1:
				draw_circle(c, r * 0.8, Color(0.95, 0.55, 0.12, pulse))
			2:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Color(1.0, 0.75, 0.15))
			3:
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.85), c + Vector2(-r, r * 0.85)]), Color(1.0, 0.2, 0.12, pulse))
				draw_rect(Rect2(c + Vector2(-r * 0.09, -r * 0.45), Vector2(r * 0.18, r * 0.75)), Color(1, 1, 1))
				draw_rect(Rect2(c + Vector2(-r * 0.09, r * 0.45), Vector2(r * 0.18, r * 0.18)), Color(1, 1, 1))


func setup(p_screen: Node, p_dp: Node) -> void:
	screen = p_screen
	dp = p_dp
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.075)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_top()
	_build_ops()
	_build_cameras()
	_build_records()
	_build_system()
	show_page(Page.OPS)


func _status() -> Node:
	return dp.get_parent().get_node_or_null("StationStatus") if dp != null and dp.get_parent() != null else null


func _btn(text: String, pos: Vector2, sz: Vector2, parent: Control, cb: Callable, font: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _lbl(text: String, pos: Vector2, sz: Vector2, parent: Control, font: int = 12, col: Color = Color(0.85, 0.9, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_top() -> void:
	_title = _lbl("", Vector2(12, 8), Vector2(200, 22), self, 14, Color(0.75, 0.92, 1.0))
	var names := ["OPERATIONS", "CAMERAS", "RECORDS", "SYSTEM"]
	for i in 4:
		var b := _btn(names[i], Vector2(206 + 98 * i, 6), Vector2(94, 26), self, show_page.bind(i), 11)
		b.toggle_mode = true
		tab_buttons.append(b)
	action_buttons["exit"] = _btn("X", Vector2(602, 6), Vector2(30, 26), self, _exit, 13)
	_emerg = _lbl("", Vector2(8, 36), Vector2(624, 20), self, 13, Color(1, 0.95, 0.9))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.04, 0.03)
	_emerg.add_theme_stylebox_override("normal", sb)
	_emerg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in 4:
		var p := Control.new()
		p.position = Vector2(0, 60)
		p.size = Vector2(640, 340)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(p)
		_pages.append(p)


func _exit() -> void:
	var ws: Node = dp.get_parent().get_node_or_null("WorkstationState") if dp != null else null
	if ws != null and ws.has_method("end_use"):
		ws.end_use()


# ------------------------------------------------------------ OPERATIONS
func _build_ops() -> void:
	var p: Control = _pages[Page.OPS]
	_map = Control.new()
	_map.position = Vector2(8, 4)
	_map.size = Vector2(380, 250)
	p.add_child(_map)
	var mbg := ColorRect.new()
	mbg.color = Color(0.06, 0.085, 0.1)
	mbg.size = _map.size
	mbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(mbg)
	# The REAL topology: copy the existing map layout (rooms + corridors)
	# and scale it into this larger area.
	var old: Control = screen.get_node("Control/VBox/Content/Overview/Map")
	var sx: float = 380.0 / 400.0
	var sy: float = 250.0 / 185.0
	for c in old.get_children():
		if c is ColorRect and String(c.name).begins_with("Edge"):
			var e := ColorRect.new()
			e.color = Color(0.32, 0.36, 0.38)
			e.position = Vector2(c.offset_left * sx, c.offset_top * sy)
			e.size = Vector2(maxf((c.offset_right - c.offset_left) * sx, 3.0), maxf((c.offset_bottom - c.offset_top) * sy, 3.0))
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_map.add_child(e)
	for r in screen.ROOMS:
		var c: ColorRect = old.get_node(r["node"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(c.offset_left * sx, c.offset_top * sy)
		b.size = Vector2((c.offset_right - c.offset_left) * sx, (c.offset_bottom - c.offset_top) * sy)
		b.text = preload("res://scripts/station/station_status.gd").ROOM_NAMES.get(r["id"], r["name"])
		b.add_theme_font_size_override("font_size", 10)
		b.clip_text = true
		b.pressed.connect(select_room.bind(r["id"]))
		_map.add_child(b)
		var badge := Badge.new()
		badge.size = Vector2(16, 16)
		badge.position = Vector2(b.size.x - 15, -7)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
		room_buttons[r["id"]] = b
	# Selected room panel.
	_room_badge = Badge.new()
	_room_badge.position = Vector2(396, 6)
	_room_badge.size = Vector2(20, 20)
	p.add_child(_room_badge)
	_room_title = _lbl("", Vector2(420, 4), Vector2(214, 22), p, 15, Color(0.95, 0.95, 0.9))
	_duty_box = VBoxContainer.new()
	_duty_box.position = Vector2(396, 30)
	_duty_box.size = Vector2(238, 120)
	_duty_box.add_theme_constant_override("separation", 3)
	p.add_child(_duty_box)
	_detail = _lbl("", Vector2(398, 156), Vector2(236, 100), p, 11, Color(0.72, 0.8, 0.78))
	# Panels over the map area (diagnostic / camera).
	_diag = _lbl("", Vector2(12, 8), Vector2(372, 242), p, 11, Color(0.8, 0.95, 0.85))
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.03, 0.05, 0.06, 0.97)
	dsb.set_content_margin_all(6)
	_diag.add_theme_stylebox_override("normal", dsb)
	_diag.visible = false
	# Round 41: the Operations page no longer carries a camera feed or a
	# CAMERAS button (both duplicated the dedicated Cameras tab).
	# Day actions.
	action_buttons["checkin"] = _btn("CHECK IN", Vector2(8, 262), Vector2(120, 30), p, func(): screen._run_c01(); refresh(), 13)
	action_buttons["verify"] = _btn("VERIFY REPAIR", Vector2(134, 262), Vector2(128, 30), p, func(): screen._run_verify(); refresh(), 12)
	action_buttons["diag"] = _btn("DIAGNOSTIC", Vector2(268, 262), Vector2(118, 30), p, toggle_diag, 12)
	_footer = _lbl("", Vector2(10, 298), Vector2(620, 36), p, 11, Color(0.6, 0.68, 0.68))


func select_room(room: StringName) -> void:
	selected_room = room
	selected_duty = -1
	ops_panel = ""
	for i in screen.ROOMS.size():
		if screen.ROOMS[i]["id"] == room:
			screen._selected_room_index = i
	if page != Page.OPS:
		show_page(Page.OPS)
	refresh()


func select_duty(i: int) -> void:
	selected_duty = -1 if selected_duty == i else i
	refresh()


func toggle_diag() -> void:
	ops_panel = "" if ops_panel == "diag" else "diag"
	if ops_panel == "diag":
		screen._run_c02()
	refresh()


func toggle_camera() -> void:
	show_page(Page.CAMERAS)


# ---------------------------------------------------------------- CAMERAS
## Round 38 dedicated surveillance tab; Round 41 LAYOUT (playtest: text
## overlapped, spacing uneven, feed details crowded):
##   LEFT  (x 8-186)   camera list in two separated groups, INTERIOR and
##                     EXTERIOR; each row = compact ID + short location,
##                     font fitted to the row with real font metrics;
##                     the active camera is highlighted;
##   RIGHT (x 194-632) a LARGE live feed (kept 4:3), with only a small
##                     REC/ID tag and the clock drawn ON the feed corners;
##   BOTTOM (under the feed) ONE line: location; ONE line: blind spot --
##                     each fitted to its width (never wrapping into the
##                     next control), plus a tiny plan of the camera.
var cam_buttons: Dictionary = {}
var selected_cam: String = "INT-02"
var _feed: TextureRect
var _feed_frame: Panel
var _feed_tag: Label
var _feed_clock: Label
var _cam_info: Label            # line 1: id · location
var _cam_blind: Label           # line 2: blind spot
var _plan: Control
var _cam_page: Control
const CAM_LIST_W := 178.0
## Round 42 Priority 8: the feed is 16:9 (matches the 1280x720 / 640x360
## camera renders) and as wide as the page allows beside the list; an
## INSPECT mode gives the feed the whole monitor (and the seated view
## leans in -- workstation_state.set_inspect_zoom()).
const FEED_RECT := Rect2(192, 2, 442, 249)
const INSPECT_RECT := Rect2(4, 2, 632, 312)
var cam_inspect: bool = false


func _net() -> Node:
	return dp.get_parent().get_node_or_null("CameraNetwork") if dp != null and dp.get_parent() != null else null


## Largest font size <= max_size at which `text` fits `width` (real metrics).
static func fit_font_size(text: String, width: float, max_size: int, min_size: int = 8) -> int:
	var f: Font = ThemeDB.fallback_font
	for sz in range(max_size, min_size - 1, -1):
		if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= width:
			return sz
	return min_size


static func text_width(text: String, size: int) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _build_cameras() -> void:
	var p: Control = _pages[Page.CAMERAS]
	_cam_page = p
	_feed_frame = Panel.new()
	_feed_frame.position = FEED_RECT.position
	_feed_frame.size = FEED_RECT.size
	_feed_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.0, 0.0, 0.0)
	fsb.border_color = Color(0.25, 0.32, 0.34)
	fsb.set_border_width_all(1)
	_feed_frame.add_theme_stylebox_override("panel", fsb)
	p.add_child(_feed_frame)
	_feed = TextureRect.new()
	_feed.position = FEED_RECT.position + Vector2(1, 1)
	_feed.size = FEED_RECT.size - Vector2(2, 2)
	_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_feed)
	# Corner tags on the feed (small, outlined, never over the list).
	_feed_tag = _feed_corner_label(p, Vector2(FEED_RECT.position.x + 52, FEED_RECT.position.y + 6), HORIZONTAL_ALIGNMENT_LEFT)
	_feed_clock = _feed_corner_label(p, Vector2(FEED_RECT.end.x - 52 - 110, FEED_RECT.position.y + 6), HORIZONTAL_ALIGNMENT_RIGHT)
	_cam_info = _lbl("", Vector2(196, 256), Vector2(344, 18), p, 12, Color(0.88, 0.95, 0.92))
	_cam_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_cam_blind = _lbl("", Vector2(196, 278), Vector2(344, 18), p, 10, Color(0.62, 0.72, 0.7))
	_cam_blind.autowrap_mode = TextServer.AUTOWRAP_OFF
	_plan = Control.new()
	_plan.position = Vector2(548, 256)
	_plan.size = Vector2(84, 46)
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.draw.connect(_draw_plan)
	p.add_child(_plan)
	action_buttons["back_to_map"] = _btn("< MAP", Vector2(8, 306), Vector2(CAM_LIST_W, 26), p, func(): show_page(Page.OPS), 11)
	action_buttons["inspect"] = _btn("⤢ INSPECT", Vector2(192, 306), Vector2(110, 26), p, toggle_inspect, 11)
	action_buttons["cam_prev"] = _btn("◀", Vector2(4, 316), Vector2(40, 22), p, func(): step_camera(-1), 11)
	action_buttons["cam_next"] = _btn("▶", Vector2(48, 316), Vector2(40, 22), p, func(): step_camera(1), 11)
	action_buttons["inspect_back"] = _btn("✕ BACK", Vector2(560, 316), Vector2(76, 22), p, toggle_inspect, 11)
	_inspect_line = _lbl("", Vector2(96, 318), Vector2(456, 18), p, 11, Color(0.88, 0.95, 0.92))
	_inspect_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	_build_cam_buttons()
	_layout_cameras()


var _inspect_line: Label


func toggle_inspect() -> void:
	cam_inspect = not cam_inspect
	_layout_cameras()
	var ws: Node = dp.get_parent().get_node_or_null("WorkstationState") if dp != null and dp.get_parent() != null else null
	if ws != null and ws.has_method("set_inspect_zoom"):
		ws.set_inspect_zoom(cam_inspect and page == Page.CAMERAS)
	refresh()


func step_camera(d: int) -> void:
	var net: Node = _net()
	if net == null:
		return
	var ids: Array = net.ids()
	if ids.is_empty():
		return
	var i: int = maxi(ids.find(selected_cam), 0)
	select_camera(ids[posmod(i + d, ids.size())])


## Normal: list | feed | info lines. Inspect: the feed fills the monitor,
## one compact line + prev / next / back underneath.
func _layout_cameras() -> void:
	if _feed == null:
		return
	var r: Rect2 = INSPECT_RECT if cam_inspect else FEED_RECT
	_feed_frame.position = r.position
	_feed_frame.size = r.size
	_feed.position = r.position + Vector2(1, 1)
	_feed.size = r.size - Vector2(2, 2)
	_feed_tag.position = Vector2(r.position.x + 8, r.position.y + 6)
	_feed_clock.position = Vector2(r.end.x - 8 - 110, r.position.y + 6)
	for id in cam_buttons:
		(cam_buttons[id] as Button).visible = not cam_inspect
	for n in _cam_page.get_children():
		if String(n.name).begins_with("Group") or n is ColorRect:
			(n as CanvasItem).visible = not cam_inspect
	_cam_info.visible = not cam_inspect
	_cam_blind.visible = not cam_inspect
	_plan.visible = not cam_inspect
	action_buttons["back_to_map"].visible = not cam_inspect
	action_buttons["inspect"].visible = not cam_inspect
	for k in ["cam_prev", "cam_next", "inspect_back"]:
		action_buttons[k].visible = cam_inspect
	_inspect_line.visible = cam_inspect


func _feed_corner_label(p: Control, pos: Vector2, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(110, 16)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.95, 0.97, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return l


## Built when the network exists (it is created after the workstation).
func _build_cam_buttons() -> void:
	var net: Node = _net()
	if net == null or not cam_buttons.is_empty() or _cam_page == null:
		return
	var p: Control = _cam_page
	var ids: Array = net.ids()
	if ids.is_empty():
		return                      # the network has not built its cameras yet
	var y: float = 2.0
	for group in [["INTERIOR", false], ["EXTERIOR", true]]:
		var head := _lbl(group[0], Vector2(10, y), Vector2(CAM_LIST_W - 4, 15), p, 10, Color(0.85, 0.75, 0.45))
		head.name = "Group" + group[0]
		head.autowrap_mode = TextServer.AUTOWRAP_OFF
		var hh: float = maxf(head.get_combined_minimum_size().y, 15.0)
		head.size = Vector2(CAM_LIST_W - 4, hh)
		var rule := ColorRect.new()
		rule.color = Color(0.85, 0.75, 0.45, 0.35)
		rule.position = Vector2(10, y + hh)
		rule.size = Vector2(CAM_LIST_W - 4, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(rule)
		y += hh + 3.0
		for id in ids:
			if String(id).begins_with("EXT") != group[1]:
				continue
			var text: String = "%s  %s" % [id, net.info(id)["label"]]
			var fs: int = fit_font_size(text, CAM_LIST_W - 16.0, 11, 8)
			var b := _btn(text, Vector2(8, y), Vector2(CAM_LIST_W, 24), p, select_camera.bind(id), fs)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.clip_text = true
			b.size = Vector2(CAM_LIST_W, 24)     # re-apply after clipping (no text-driven growth)
			b.set_meta("font_px", fs)
			var sel := StyleBoxFlat.new()
			sel.bg_color = Color(0.16, 0.42, 0.48)
			sel.border_color = Color(0.6, 0.95, 1.0)
			sel.set_border_width_all(1)
			sel.border_width_left = 4
			sel.set_content_margin_all(4)
			b.add_theme_stylebox_override("pressed", sel)
			b.add_theme_stylebox_override("hover_pressed", sel)
			b.size = Vector2(CAM_LIST_W, 24)
			cam_buttons[id] = b
			y += 26.0
		y += 8.0


func select_camera(id: String) -> void:
	selected_cam = id
	refresh()


func _refresh_cameras() -> void:
	var net: Node = _net()
	if net == null:
		return
	_build_cam_buttons()
	for id in cam_buttons:
		(cam_buttons[id] as Button).button_pressed = id == selected_cam
	# Round 39: a shown feed counts as LOOKING at it (lens-grime check).
	if page == Page.CAMERAS and is_inside_tree():
		get_tree().call_group(&"lens_task", &"on_feed_viewed", selected_cam)
		get_tree().call_group(&"story_events", &"on_feed_viewed", selected_cam)
	var inf: Dictionary = net.info(selected_cam)
	_feed.texture = net.feed(selected_cam) if monitor_on() else null
	_feed_tag.text = ("MONITOR OFF  ·  console switch") if not monitor_on() else (("● REC  %s" % selected_cam) if _feed.texture != null else ("NO SIGNAL  %s" % selected_cam))
	_feed_clock.text = "D%02d  %s" % [dp.day_number, dp.clock_text_hhmm()]
	var line1: String = "%s · %s" % [selected_cam, String(inf.get("label", ""))]
	var line2: String = ("Blind spot: %s" % String(inf.get("blind", "-"))) if detail_mode() else ""
	_cam_info.text = line1
	_cam_info.add_theme_font_size_override("font_size", fit_font_size(line1, _cam_info.size.x, 12, 9))
	_cam_blind.text = line2
	_cam_blind.add_theme_font_size_override("font_size", fit_font_size(line2, _cam_blind.size.x, 10, 8))
	if _inspect_line != null:
		var l3: String = "%s · %s · %s" % [selected_cam, String(inf.get("label", "")), "LIVE %dx%d" % [net.feed_size(selected_cam).x, net.feed_size(selected_cam).y] if net.is_rendering(selected_cam) else "NO SIGNAL"]
		_inspect_line.text = l3
		_inspect_line.add_theme_font_size_override("font_size", fit_font_size(l3, _inspect_line.size.x, 11, 8))
	_plan.queue_redraw()


## Small station plan from the real floor footprints + the camera's
## position and view direction.
func _draw_plan() -> void:
	var net: Node = _net()
	var geo: Node = dp.get_parent().get_node_or_null("Geometry") if dp != null else null
	if net == null or geo == null:
		return
	var w2p := func(v: Vector3) -> Vector2:
		return Vector2((v.x + 8.5) / 18.0 * _plan.size.x, (v.z + 10.0) / 23.0 * _plan.size.y)
	_plan.draw_rect(Rect2(Vector2.ZERO, _plan.size), Color(0.03, 0.05, 0.06, 0.9))
	for n in geo.get_children():
		if n is CSGBox3D and String(n.name).ends_with("Floor") and (n as CSGBox3D).size.x > 0.6:
			var b: CSGBox3D = n
			var a: Vector2 = w2p.call(b.global_position - Vector3(b.size.x, 0, b.size.z) * 0.5)
			var e: Vector2 = w2p.call(b.global_position + Vector3(b.size.x, 0, b.size.z) * 0.5)
			_plan.draw_rect(Rect2(a, e - a), Color(0.25, 0.3, 0.32))
	var cam: Camera3D = net.camera(selected_cam)
	if cam != null:
		var cp: Vector2 = w2p.call(cam.global_position)
		cp = cp.clamp(Vector2(3, 3), _plan.size - Vector2(3, 3))
		var fwd: Vector3 = -cam.global_transform.basis.z
		var tip: Vector2 = cp + Vector2(fwd.x, fwd.z).normalized() * 10.0
		_plan.draw_line(cp, tip, Color(1.0, 0.8, 0.3), 2.0)
		_plan.draw_circle(cp, 3.0, Color(1.0, 0.35, 0.25))


## Room duties for the map (day 1's orientation tasks included).
func room_duties(room: StringName) -> Array:
	var st: Node = _status()
	var out: Array = []
	if st != null:
		var rs: Dictionary = st.rooms()
		out = Array(rs.get(room, {"duties": []})["duties"])
	return out


## Round 45: the physical console toggles (console_toggles.gd).
func _toggles() -> Node:
	return get_tree().get_first_node_in_group(&"console_toggles") if is_inside_tree() else null


func monitor_on() -> bool:
	var tg: Node = _toggles()
	return tg == null or bool(tg.monitor_on)


## DETAIL mode (the DIAG toggle): technical lines; off = short visual default.
func detail_mode() -> bool:
	var tg: Node = _toggles()
	return tg != null and bool(tg.diag)


func _clearance() -> Node:
	return get_tree().get_first_node_in_group(&"clearance") if is_inside_tree() else null


func _refresh_ops() -> void:
	var st: Node = _status()
	var rs: Dictionary = st.rooms() if st != null else {}
	var steady: bool = bool(GS.get_value("steady_warnings"))
	var pulse: float = 1.0 if steady else 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * PI))
	var gentle: float = 1.0 if steady else 0.75 + 0.25 * (0.5 + 0.5 * sin(_t * 1.6))
	for room in room_buttons:
		var b: Button = room_buttons[room]
		var sev: int = int(rs.get(room, {"severity": 0})["severity"])
		var fill: Color = Color(0.2, 0.22, 0.25)
		var border: Color = Color(0.4, 0.44, 0.46)
		var bw := 1
		match sev:
			1:
				border = SEV_COLORS[1] * gentle
				bw = 2
			2:
				fill = Color(0.42, 0.3, 0.06)
				border = SEV_COLORS[2]
				bw = 3
			3:
				fill = Color(0.55, 0.06, 0.04).lerp(Color(0.85, 0.1, 0.06), 1.0 - pulse)
				border = Color(1.0, 0.3, 0.2)
				bw = 3
		if room == selected_room:
			border = Color(0.95, 0.97, 1.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(bw)
		for st_name in ["normal", "hover", "pressed"]:
			var s2: StyleBoxFlat = sb.duplicate()
			if st_name == "hover":
				s2.bg_color = fill.lightened(0.12)
			b.add_theme_stylebox_override(st_name, s2)
		# Round 45: rooms beyond the technician's clearance are dimmed.
		var clr: Node = _clearance()
		var locked: bool = clr != null and not clr.room_open(room)
		b.modulate = Color(0.45, 0.45, 0.5) if locked else Color(1, 1, 1)
		var badge: Badge = b.get_child(0)
		badge.severity = sev
		badge.pulse = pulse if sev == 3 else gentle
		badge.queue_redraw()
	var sel: Dictionary = rs.get(selected_room, {"severity": 0, "duties": []})
	var sev_sel: int = int(sel["severity"])
	_room_badge.severity = sev_sel
	_room_badge.pulse = pulse
	_room_badge.queue_redraw()
	var clr2: Node = _clearance()
	var sel_locked: bool = clr2 != null and not clr2.room_open(selected_room)
	_room_title.text = "%s · %s" % [preload("res://scripts/station/station_status.gd").ROOM_NAMES.get(selected_room, "ROOM"), "RESTRICTED" if sel_locked else SEV_WORDS[sev_sel]]
	_room_title.add_theme_color_override("font_color", SEV_COLORS[sev_sel] if sev_sel > 0 else Color(0.8, 0.85, 0.85))
	var duties: Array = sel["duties"]
	if duty_buttons.size() != duties.size():
		for b in duty_buttons:
			b.queue_free()
		duty_buttons.clear()
		for i in duties.size():
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.custom_minimum_size = Vector2(238, 24)
			b.add_theme_font_size_override("font_size", 12)
			b.pressed.connect(select_duty.bind(i))
			_duty_box.add_child(b)
			duty_buttons.append(b)
	for i in duties.size():
		var d: Dictionary = duties[i]
		# Round 45: one short required action per line ("CLEAN VENT");
		# the full sentence only in DETAIL (Diag) mode.
		var label: String = String(d["action"]) if detail_mode() else String(d.get("short", d["action"])).to_upper()
		duty_buttons[i].text = "%s %s" % [["", "o", "<>", "!"][int(d["severity"])], label]
		duty_buttons[i].add_theme_color_override("font_color", SEV_COLORS[int(d["severity"])] if int(d["severity"]) > 0 else Color(0.9, 0.9, 0.9))
	selected_duty = clampi(selected_duty, -1, duties.size() - 1)
	if sel_locked:
		_detail.text = "Needs %s clearance." % clr2.NAMES[int(clr2.ROOM_LEVEL.get(selected_room, 0))]
	elif duties.is_empty():
		_detail.text = "" if sev_sel == 0 else ""
	elif selected_duty >= 0:
		_detail.text = "\n".join(_duty_details(duties[selected_duty]).slice(0, 6 if detail_mode() else 2))
	else:
		_detail.text = ""
	# Day actions: only those that apply now.
	action_buttons["checkin"].visible = not dp.is_task_done(&"c01")
	action_buttons["verify"].visible = int(dp.workday) == 0 and not dp.is_task_done(&"c05") and (dp.is_task_done(&"e06") or (screen._electrical_panel != null and screen._electrical_panel.is_repaired()))
	_diag.visible = ops_panel == "diag"
	if _diag.visible:
		_diag.text = screen._diagnostics_status.text
	_map.visible = true
	# Footer: the single most urgent duty on the station (same model).
	var all_d: Array = st.duties() if st != null else []
	var top: Dictionary = {}
	for d in all_d:
		if top.is_empty() or int(d["severity"]) > int(top["severity"]):
			top = d
	var top_label: String = (String(top["action"]) if detail_mode() else String(top.get("short", top["action"])).to_upper()) if not top.is_empty() else ""
	_footer.text = ("NEXT: %s · %s" % [top_label, preload("res://scripts/station/station_status.gd").ROOM_NAMES.get(StringName(top["room"]), "")]) if not top.is_empty() else "ALL DONE"
	# Round 42: the station's TRUE cabin environment (EnvironmentModel),
	# always on the Operations page -- the reference a technician compares
	# the physical wall readouts against.
	var env: Node = dp.get_parent().get_node_or_null("EnvironmentModel")
	if env != null:
		_footer.text += ("\nCABIN %.1f kPa · O2 %.1f kPa (live sensors)" % [env.pressure_kpa, env.o2_kpa]) if detail_mode() else ("\nCABIN %.0f kPa · O2 %.1f" % [env.pressure_kpa, env.o2_kpa])


func _duty_details(d: Dictionary) -> Array:
	var id: String = String(d.get("id", ""))
	if d.has("details"):
		return Array(d["details"])
	if id.begins_with("COND") or id == "DAY1":
		return [String(d["action"])]
	for r in screen.work_order_rows():
		if String(r["id"]) == id:
			return screen.work_order_detail_lines(r)
	return []


# --------------------------------------------------------------- RECORDS
## Round 44 Priority 9: RECORDS tabs -- the daily summary plus the four
## consultable station logs (station_log.gd). Opening a log tab tells the
## story director a record was consulted (investigations).
const RECORD_TABS := [["summary", "SUMMARY"], ["airlock", "AIRLOCK"], ["camera", "CAMERAS"], ["environment", "ENVIRONMENT"], ["access", "ACCESS"]]
var record_tab: String = "summary"
var record_buttons: Dictionary = {}


func select_record_tab(id: String) -> void:
	record_tab = id
	for k in record_buttons:
		(record_buttons[k] as Button).modulate = Color(1, 0.85, 0.45) if k == id else Color(1, 1, 1)
	if id != "summary" and is_inside_tree():
		get_tree().call_group(&"story_events", &"on_record_viewed", id + "_log")
	_refresh_records()


func _build_records() -> void:
	var p: Control = _pages[Page.RECORDS]
	for i in RECORD_TABS.size():
		var t: Array = RECORD_TABS[i]
		record_buttons[t[0]] = _btn(t[1], Vector2(10 + i * 124, 2), Vector2(120, 22), p, select_record_tab.bind(t[0]), 11)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 28)
	sc.size = Vector2(620, 306)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	_records = Label.new()
	_records.custom_minimum_size = Vector2(600, 0)
	_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records.add_theme_font_size_override("font_size", 12)
	_records.add_theme_color_override("font_color", Color(0.82, 0.88, 0.86))
	sc.add_child(_records)


func _refresh_records() -> void:
	if record_tab != "summary":
		var lg: Node = get_tree().get_first_node_in_group(&"station_log") if is_inside_tree() else null
		_records.text = "\n".join(lg.lines(record_tab, 18)) if lg != null else "(no station log)"
		return
	var lines: Array[String] = ["TODAY · DAY %d" % dp.day_number]
	var log: Array = Array(dp.day_log())
	if log.is_empty():
		lines.append("  (nothing logged yet)")
	for l in log.slice(maxi(log.size() - 14, 0)):
		lines.append("  " + String(l))
	lines.append("")
	lines.append("SHIFT REPORTS")
	if dp.shift_history.is_empty():
		lines.append("  (none yet)")
	for h in dp.shift_history.slice(maxi(dp.shift_history.size() - 3, 0)):
		lines.append("  Day %d: %s" % [int(h["day"]), " · ".join(Array(h["report"]).slice(0, 3))])
	lines.append("")
	lines.append("TECHNICIAN PROFICIENCY")
	for f in dp.FAMILIES:
		var n: int = dp.proficiency_level(f)
		lines.append("  %-15s %-11s (%d jobs)" % [String(f).replace("_", " ").to_upper(), dp.rank_name(n), n])
	lines.append("")
	lines.append("SERVICE HISTORY")
	for s in dp.service_history.slice(maxi(dp.service_history.size() - 6, 0)):
		lines.append("  Day %d: %s" % [int(s["day"]), String(dp.WORKDAY_TITLES.get(int(s["workday"]), "service")).get_slice(" —", 0)])
	_records.text = "\n".join(lines)


# ---------------------------------------------------------------- SYSTEM
func _build_system() -> void:
	var p: Control = _pages[Page.SYSTEM]
	_lbl("SETTINGS", Vector2(12, 2), Vector2(200, 18), p, 12, Color(0.85, 0.75, 0.45))
	var rows: Array = screen.settings_rows()
	for i in rows.size():
		var y: float = 22 + i * 20
		var b := _btn("", Vector2(10, y), Vector2(300, 19), p, _setting_click.bind(i, 1), 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var lb := _btn("<", Vector2(314, y), Vector2(26, 19), p, _setting_click.bind(i, -1), 11)
		setting_buttons.append([b, lb])
	_lbl("GAME", Vector2(370, 2), Vector2(200, 18), p, 12, Color(0.85, 0.75, 0.45))
	action_buttons["save"] = _btn("SAVE GAME", Vector2(368, 24), Vector2(262, 34), p, func(): screen._do_save(); _slots_dirty = true; refresh(), 14)
	action_buttons["load"] = _btn("LOAD GAME", Vector2(368, 64), Vector2(262, 34), p, func(): screen.save_load_key(KEY_L); _slots_dirty = true; refresh(), 14)
	action_buttons["new"] = _btn("NEW GAME", Vector2(368, 104), Vector2(262, 28), p, func(): screen.save_load_key(KEY_N); refresh(), 12)
	_save_info = _lbl("", Vector2(370, 138), Vector2(262, 70), p, 11, Color(0.7, 0.8, 0.78))
	_sys_status = _lbl("", Vector2(370, 210), Vector2(262, 110), p, 11, Color(0.95, 0.85, 0.6))


var _slots_dirty: bool = true
var _summary: String = ""
var _auto: String = "none"


func _setting_click(i: int, dir: int) -> void:
	screen.settings_sel = i
	screen.adjust_setting(dir)
	refresh()


func _refresh_system() -> void:
	var rows: Array = screen.settings_rows()
	for i in mini(rows.size(), setting_buttons.size()):
		setting_buttons[i][0].text = "%s   %s" % [rows[i][1], rows[i][2]]
	var sg: Node = screen._save_game_node()
	if sg == null:
		_save_info.text = "Save system unavailable."
		return
	if _slots_dirty:
		# Disk reads only when the page opens or after a save/load action.
		_slots_dirty = false
		_summary = sg.save_summary()
		_auto = "none"
		for slot in sg.list_slots():
			if String(slot.get("slot", "")) == "autosave" and slot.get("ok", false):
				_auto = "Day %d" % int(slot.get("day", 0))
	var summary: String = _summary
	_save_info.text = "Saved game: %s\nAutosave (start of day): %s\nCurrent: Day %d" % [summary if summary != "" else "none", _auto, dp.day_number]
	var why: String = sg.save_blocker()
	action_buttons["save"].disabled = why != ""
	action_buttons["save"].tooltip_text = why
	action_buttons["load"].disabled = summary == ""
	_sys_status.text = screen._save_status if screen._save_status != "" else (("Cannot save now: " + why) if why != "" else "")


# ------------------------------------------------------------- common
func show_page(p: int) -> void:
	if p != Page.CAMERAS and cam_inspect:
		cam_inspect = false
		_layout_cameras()
		var ws: Node = dp.get_parent().get_node_or_null("WorkstationState") if dp != null and dp.get_parent() != null else null
		if ws != null and ws.has_method("set_inspect_zoom"):
			ws.set_inspect_zoom(false)
	page = p
	_slots_dirty = true
	for i in _pages.size():
		_pages[i].visible = i == p
		tab_buttons[i].button_pressed = i == p
	refresh()


func refresh() -> void:
	if dp == null:
		return
	var st: Node = _status()
	var e: Dictionary = st.emergency() if st != null else {}
	_emerg.visible = not e.is_empty()
	if _emerg.visible:
		_emerg.text = "! %s   %s" % [st.emergency_line(), String(e.get("action", ""))]
	# Round 42: station TIME in the header; work progress stays a separate
	# quantity (WORK nn%).
	# Round 46: + the REAL shift time left (mm:ss of the 600 s budget).
	_title.text = "DAY %d · %s · %s" % [dp.day_number, dp.clock_text_hhmm(), "REST" if dp.shift_ended else ("WORK DONE · %s LEFT" % dp.clock_text(dp.shift_remaining_s()) if dp.is_wrapping_up() else "WORK %d%% · %s LEFT" % [int(round(dp.shift_progress() * 100.0)), dp.clock_text(dp.shift_remaining_s())])]
	_title.add_theme_font_size_override("font_size", fit_font_size(_title.text, 192.0, 14, 9))
	match page:
		Page.OPS: _refresh_ops()
		Page.CAMERAS: _refresh_cameras()
		Page.RECORDS: _refresh_records()
		Page.SYSTEM: _refresh_system()
	# Only the camera actually on screen renders -- Round 42 Priority 7
	# (stale-feed bug): the monitor's Cameras page is VISIBLE to anyone in
	# the Control Room / corridor / Junction A, seated or not, so it keeps
	# its feed live whenever the player could see the monitor (it used to
	# stop rendering the moment the technician stood up, freezing the last
	# frame -- the technician still seated -- on the monitor). Seated: HI
	# resolution (close inspection); standing: LO.
	var net: Node = _net()
	if net != null:
		var ws: Node = dp.get_parent().get_node_or_null("WorkstationState")
		var seated: bool = ws != null and ws.is_in_use()
		var shown: bool = page == Page.CAMERAS and (seated or monitor_visible_to_player()) and monitor_on()
		net.request("workstation", selected_cam if shown else "", shown and seated)


var _rt: float = 0.0


## The player's eye is somewhere the monitor can be seen from (the Control
## Room, the corridor or Junction A, looking back through the doorway).
func monitor_visible_to_player() -> bool:
	var pc: Node3D = dp.get_parent().get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") if dp != null and dp.get_parent() != null else null
	if pc == null:
		return false
	var p: Vector3 = pc.global_position
	return absf(p.x) < 1.6 and p.z > -1.4 and p.z < 5.6 and p.y < 3.0


func _process(delta: float) -> void:
	_t += delta
	_rt += delta
	if _rt >= 0.1 and is_visible_in_tree():
		_rt = 0.0
		refresh()
