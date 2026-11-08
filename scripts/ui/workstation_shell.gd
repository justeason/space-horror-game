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
var ops_panel: String = ""  # "" | "diag" | "camera"
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
var _cam: TextureRect
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
	_cam = TextureRect.new()
	_cam.position = Vector2(8, 4)
	_cam.size = Vector2(380, 250)
	_cam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cam.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cam.visible = false
	_cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_cam)
	# Day actions.
	action_buttons["checkin"] = _btn("CHECK IN", Vector2(8, 262), Vector2(120, 30), p, func(): screen._run_c01(); refresh(), 13)
	action_buttons["verify"] = _btn("VERIFY REPAIR", Vector2(134, 262), Vector2(128, 30), p, func(): screen._run_verify(); refresh(), 12)
	action_buttons["diag"] = _btn("DIAGNOSTIC", Vector2(268, 262), Vector2(118, 30), p, toggle_diag, 12)
	action_buttons["camera"] = _btn("CAMERAS", Vector2(392, 262), Vector2(100, 30), p, func(): show_page(Page.CAMERAS), 12)
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
## Round 38: the dedicated surveillance tab. Click a camera (interior /
## exterior), see its LIVE feed (rendered only while shown), its id,
## location, blind spot, and where it sits on a small station plan.
var cam_buttons: Dictionary = {}
var selected_cam: String = "INT-02"
var _feed: TextureRect
var _cam_info: Label
var _plan: Control


func _net() -> Node:
	return dp.get_parent().get_node_or_null("CameraNetwork") if dp != null and dp.get_parent() != null else null


func _build_cameras() -> void:
	var p: Control = _pages[Page.CAMERAS]
	var net: Node = _net()
	_lbl("INTERIOR", Vector2(10, 2), Vector2(90, 16), p, 10, Color(0.85, 0.75, 0.45))
	_cam_page = p
	_build_cam_buttons()
	_feed = TextureRect.new()
	_feed.position = Vector2(212, 4)
	_feed.size = Vector2(420, 262)
	_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_feed)
	_cam_info = _lbl("", Vector2(214, 266), Vector2(302, 44), p, 10, Color(0.8, 0.92, 0.88))
	_plan = Control.new()
	_plan.position = Vector2(520, 270)
	_plan.size = Vector2(112, 64)
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.draw.connect(_draw_plan)
	p.add_child(_plan)
	action_buttons["back_to_map"] = _btn("< MAP", Vector2(212, 312), Vector2(70, 22), p, func(): show_page(Page.OPS), 11)


var _cam_page: Control


## Built when the network exists (it is created after the workstation).
func _build_cam_buttons() -> void:
	var net: Node = _net()
	if net == null or not cam_buttons.is_empty() or _cam_page == null:
		return
	var p: Control = _cam_page
	var ids: Array = net.ids()
	var ni := 0
	var ne := 0
	# Round 39: curated set -- the EXTERIOR group follows the interior list.
	var n_int: int = ids.filter(func(i): return not String(i).begins_with("EXT")).size()
	var ext_y: float = 20.0 + n_int * 26.0 + 14.0
	_lbl("EXTERIOR", Vector2(10, ext_y - 18.0), Vector2(90, 16), p, 10, Color(0.85, 0.75, 0.45))
	for id in ids:
		var ext: bool = String(id).begins_with("EXT")
		var y: float = (ext_y + ne * 30) if ext else (20 + ni * 26)
		var b := _btn("%s %s" % [id, net.info(id)["label"]], Vector2(8, y), Vector2(196, 24 if not ext else 26), p, select_camera.bind(id), 10)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		cam_buttons[id] = b
		if ext:
			ne += 1
		else:
			ni += 1


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
	var inf: Dictionary = net.info(selected_cam)
	_feed.texture = net.feed(selected_cam)
	var tsec: int = int(dp.shift_elapsed_s)
	_cam_info.text = "%s · %s   LIVE %02d:%02d\nBlind spot: %s" % [selected_cam, inf.get("label", ""), tsec / 60, tsec % 60, inf.get("blind", "-")]
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
		var badge: Badge = b.get_child(0)
		badge.severity = sev
		badge.pulse = pulse if sev == 3 else gentle
		badge.queue_redraw()
	var sel: Dictionary = rs.get(selected_room, {"severity": 0, "duties": []})
	var sev_sel: int = int(sel["severity"])
	_room_badge.severity = sev_sel
	_room_badge.pulse = pulse
	_room_badge.queue_redraw()
	_room_title.text = "%s · %s" % [preload("res://scripts/station/station_status.gd").ROOM_NAMES.get(selected_room, "ROOM"), SEV_WORDS[sev_sel]]
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
		duty_buttons[i].text = "%s %s" % [["", "o", "<>", "!"][int(d["severity"])], d["action"]]
		duty_buttons[i].add_theme_color_override("font_color", SEV_COLORS[int(d["severity"])] if int(d["severity"]) > 0 else Color(0.9, 0.9, 0.9))
	selected_duty = clampi(selected_duty, -1, duties.size() - 1)
	if duties.is_empty():
		_detail.text = "No work here." if sev_sel == 0 else ""
	elif selected_duty >= 0:
		_detail.text = "\n".join(_duty_details(duties[selected_duty]).slice(0, 6))
	else:
		_detail.text = ""
	# Day actions: only those that apply now.
	action_buttons["checkin"].visible = not dp.is_task_done(&"c01")
	action_buttons["verify"].visible = int(dp.workday) == 0 and not dp.is_task_done(&"c05") and (dp.is_task_done(&"e06") or (screen._electrical_panel != null and screen._electrical_panel.is_repaired()))
	_diag.visible = ops_panel == "diag"
	if _diag.visible:
		_diag.text = screen._diagnostics_status.text
	_cam.visible = false
	_map.visible = true
	# Footer: the single most urgent duty on the station (same model).
	var all_d: Array = st.duties() if st != null else []
	var top: Dictionary = {}
	for d in all_d:
		if top.is_empty() or int(d["severity"]) > int(top["severity"]):
			top = d
	_footer.text = ("NEXT: %s · %s" % [top["action"], preload("res://scripts/station/station_status.gd").ROOM_NAMES.get(StringName(top["room"]), "")]) if not top.is_empty() else "All assignments complete."


func _duty_details(d: Dictionary) -> Array:
	var id: String = String(d.get("id", ""))
	if id.begins_with("COND") or id == "DAY1":
		return [String(d["action"])]
	for r in screen.work_order_rows():
		if String(r["id"]) == id:
			return screen.work_order_detail_lines(r)
	return []


# --------------------------------------------------------------- RECORDS
func _build_records() -> void:
	var p: Control = _pages[Page.RECORDS]
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 4)
	sc.size = Vector2(620, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	_records = Label.new()
	_records.custom_minimum_size = Vector2(600, 0)
	_records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records.add_theme_font_size_override("font_size", 12)
	_records.add_theme_color_override("font_color", Color(0.82, 0.88, 0.86))
	sc.add_child(_records)


func _refresh_records() -> void:
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
	_title.text = "DAY %d · %s" % [dp.day_number, "SHIFT ENDED · REST" if dp.shift_ended else ("WORK DONE · WRAP UP" if dp.is_wrapping_up() else "SHIFT %d%%" % int(round(dp.shift_progress() * 100.0)))]
	match page:
		Page.OPS: _refresh_ops()
		Page.CAMERAS: _refresh_cameras()
		Page.RECORDS: _refresh_records()
		Page.SYSTEM: _refresh_system()
	# Only the camera actually on screen renders.
	var net: Node = _net()
	if net != null:
		var ws: Node = dp.get_parent().get_node_or_null("WorkstationState")
		var shown: bool = page == Page.CAMERAS and ws != null and ws.is_in_use()
		net.request("workstation", selected_cam if shown else "")


var _rt: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	_rt += delta
	if _rt >= 0.1 and is_visible_in_tree():
		_rt = 0.0
		refresh()
