extends SubViewport
## The laptop's ENTIRE SESSION LOG interface -- both the read-only
## "just looking at it" display and the actual interactive text editor
## -- rendered as one real texture applied to the laptop's physical
## screen material (scripts/interactables/laptop.gd's
## set_screen_texture()). The same "SubViewport as a physical screen's
## live feed" pattern already used by
## scripts/surveillance/surveillance_camera.gd, extended here from a 3D
## camera feed to an interactive 2D UI tree.
##
## M7.2: this REPLACES the old projected full-screen 2D overlay
## (scripts/ui/session_log.gd, now deleted) entirely -- there is no
## camera-space HUD anymore. The log genuinely only exists as a
## texture on the laptop mesh; turning your head moves it exactly like
## any other physical object, because it IS one.
##
## Input routing (validated empirically before integrating -- see the
## M7.2 investigation notes -- rather than assumed): this SubViewport
## is not inside a SubViewportContainer (it never appears as on-screen
## 2D UI; it is only ever read as a texture), so Godot's automatic
## mouse-forwarding for embedded viewports does not apply. Keyboard
## input instead has to be explicitly forwarded by the caller via
## forward_key(), which calls push_input() on this viewport directly --
## confirmed to correctly route typing, backspace, and caret movement
## to whichever child Control currently has focus within THIS
## viewport, independent of the main scene's own input tree. There is
## deliberately no mouse-click forwarding: see scripts/player/
## sleep_state.gd, which uses dedicated keys (T/Esc/Ctrl+S) for every
## action instead, sidestepping the much larger problem of mapping a
## 3D raycast hit point to this viewport's 2D coordinates.

@onready var _entry_field: TextEdit = $Control/VBox/EntryField
@onready var _hint_label: Label = $Control/VBox/HintLabel
@onready var _edit_hint_label: Label = $Control/VBox/EditHintLabel


@onready var _title: Label = $Control/VBox/TitleLabel
@onready var _subtitle: Label = $Control/VBox/SubtitleLabel
@onready var _status: Label = $Control/VBox/SampleLabel
var _day_plan: Node = null


## Round 44 Priority 14: the laptop screen RENDERS at 2x (960 x 560) while
## its UI keeps the 480 x 280 layout (size_2d_override, stretched): text,
## icons and games are rasterised at twice the pixels. Input arrives in
## RENDER pixels (click_at / hover_at: uv x size) and Godot maps it through
## the stretch, so a visible button answers exactly where it is clicked;
## uv_of() reports layout positions as uv of the layout size.
const RENDER_SCALE := 2


func layout_size() -> Vector2:
	return Vector2(size_2d_override) if size_2d_override != Vector2i.ZERO else Vector2(size)


func _ready() -> void:
	if size_2d_override == Vector2i.ZERO:
		var base: Vector2i = size
		size_2d_override = base
		size_2d_override_stretch = true
		size = base * RENDER_SCALE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_entry_field.editable = false
	_set_hint_for_viewing()
	_build_app_bar()
	_connect_day_plan.call_deferred()


## Round 33: the laptop shows which day it is (and today's shift) from the
## same DayPlan the workstation reads -- found by group, not a NodePath,
## because this screen lives inside the player scene.
func _connect_day_plan() -> void:
	_day_plan = get_tree().get_first_node_in_group(&"day_plan")
	if _day_plan == null:
		return
	_day_plan.day_started.connect(func(_d): refresh_day())
	_day_plan.task_completed.connect(func(_t): refresh_day())
	refresh_day()


# ======================================================================
# Round 34 Priorities 6/13: a real (clickable) laptop desktop. An app bar
# of visible buttons -- Personal Log, Shift Report, Close Laptop; while
# editing: Back, Save. Clicks arrive from the 3D world through click_at()
# (sleep_state.gd raycasts the physical screen). Built so further apps
# (messages, photos, a game) slot into the same bar later.
# ======================================================================
signal app_requested(app: StringName)

var _bar: HBoxContainer
var _report: Label
var _buttons := {}
var _view: StringName = &"home"


func _build_app_bar() -> void:
	# Round 38: a lightweight personal computer -- TASKBAR (desktop, save,
	# zoom out, close) + one CONTENT view at a time: the DESKTOP icon grid,
	# or an app (Personal Log, Messages, Schedule, Photos, Files, Shift
	# Report, Cargo Drop). Zooming in (the "editing" state of the bunk) is
	# FOCUSED USE of the whole computer, no longer the log editor only:
	# every app is reachable zoomed or not; the log text is editable only
	# while the Personal Log app is open and the laptop is zoomed.
	var vbox: VBoxContainer = $Control/VBox
	_build_chrome()
	_bar = HBoxContainer.new()
	_bar.name = "AppBar"
	_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(_bar)
	vbox.move_child(_bar, 3)
	_app_title = Label.new()
	_app_title.add_theme_font_size_override("font_size", 13)
	_app_title.add_theme_color_override("font_color", Color(0.75, 0.95, 0.8))
	_app_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Round 42 Priority 23 (Personal Log cropped on the right): ROOT CAUSE --
	# while editing, the menu bar's MINIMUM width (title + Save + Save&Back
	# + Close + the long shift-status clock = 560 px) exceeded the 456 px
	# content width, so the VBox -- and the TextEdit inside it -- grew past
	# the screen's right edge. The title now clips (never forces width) and
	# the clock is compact; _fit_bar() guarantees the fit at runtime.
	_app_title.clip_text = true
	_app_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bar.add_child(_app_title)
	_bar.move_child(_app_title, 0)
	var brand := Label.new()
	_brand = brand
	brand.text = "◆ driftwood"
	brand.add_theme_font_size_override("font_size", 12)
	brand.add_theme_color_override("font_color", Color(0.95, 0.8, 0.55))
	_bar.add_child(brand)
	_bar.move_child(brand, 0)
	# Round 45 Priority 13: in-app navigation (< Desktop, app views) is
	# clearly separate from the ONE physical action, CLOSE LAPTOP (always
	# shown, far right, amber; it saves everything and folds the lid).
	# "back" (zoom out without closing) stays reachable by Esc only.
	for spec in [[&"home", "< Desktop"], [&"note_history", "History"], [&"journal_obs", "Seen"], [&"journal_notes", "Notes"], [&"save", "Save"], [&"back", "< Save & Back"], [&"close", "CLOSE LAPTOP"]]:
		_add_button(_bar, spec[0], spec[1])
	_clock = Label.new()
	_clock.name = "Clock"
	_clock.add_theme_font_size_override("font_size", 11)
	_clock.add_theme_color_override("font_color", Color(0.85, 0.9, 0.88))
	_bar.add_child(_clock)
	# Desktop icon grid.
	_desktop = GridContainer.new()
	_desktop.name = "Desktop"
	_desktop.columns = 4
	_desktop.add_theme_constant_override("h_separation", 6)
	_desktop.add_theme_constant_override("v_separation", 6)
	_desktop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home = HBoxContainer.new()
	_home.name = "Home"
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_theme_constant_override("separation", 8)
	vbox.add_child(_home)
	vbox.move_child(_home, 4)
	_home.add_child(_desktop)
	_desktop.columns = 4
	_desktop.add_theme_constant_override("h_separation", 4)
	_desktop.add_theme_constant_override("v_separation", 4)
	# Round 39: real desktop ICONS (pictogram + label) on the wallpaper.
	for spec in APPS:
		var b := _add_button(_desktop, spec[0], spec[1])
		b.custom_minimum_size = Vector2(76, 60)
		b.icon = _app_icon(spec[0], spec[2])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_color_override("font_color", Color(0.95, 0.96, 0.94))
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		b.add_theme_constant_override("outline_size", 3)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.0)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(3)
		b.add_theme_stylebox_override("normal", sb)
		var sbh: StyleBoxFlat = sb.duplicate()
		sbh.bg_color = Color(1, 1, 1, 0.16)
		sbh.border_color = (spec[2] as Color).lightened(0.2)
		sbh.set_border_width_all(1)
		b.add_theme_stylebox_override("hover", sbh)
		b.add_theme_stylebox_override("pressed", sbh)
	_build_note()
	_report = Label.new()
	_report.name = "ReportView"
	_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.add_theme_font_size_override("font_size", 12)
	_report.add_theme_color_override("font_color", Color(0.75, 0.9, 0.8))
	_report.clip_text = true
	_report.visible = false
	vbox.add_child(_report)
	vbox.move_child(_report, vbox.get_children().find(_entry_field) + 1)
	# Photos viewer.
	_photo_box = VBoxContainer.new()
	_photo_box.name = "PhotoView"
	_photo_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo_box.visible = false
	vbox.add_child(_photo_box)
	vbox.move_child(_photo_box, vbox.get_children().find(_report) + 1)
	var prow := HBoxContainer.new()
	prow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo_box.add_child(prow)
	_add_button(prow, &"photo_prev", "<")
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prow.add_child(_photo)
	_add_button(prow, &"photo_next", ">")
	_photo_caption = Label.new()
	_photo_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_photo_caption.add_theme_font_size_override("font_size", 11)
	_photo_caption.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	_photo_box.add_child(_photo_caption)
	# Files browser.
	_files_box = VBoxContainer.new()
	_files_box.name = "FilesView"
	_files_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files_box.visible = false
	vbox.add_child(_files_box)
	vbox.move_child(_files_box, vbox.get_children().find(_photo_box) + 1)
	# Game.
	_game = preload("res://scripts/ui/cargo_drop_game.gd").new()
	_game.name = "CargoDrop"
	_game.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game.visible = false
	vbox.add_child(_game)
	vbox.move_child(_game, vbox.get_children().find(_files_box) + 1)
	_game.exited.connect(func(): open_app(&"home"))
	_game.score_changed.connect(func(b): game_best = maxi(game_best, b))
	# Round 42: HOLDOUT (survival game), a second Entertainment app.
	holdout = preload("res://scripts/ui/holdout_game.gd").new()
	holdout.name = "Holdout"
	holdout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holdout.visible = false
	vbox.add_child(holdout)
	vbox.move_child(holdout, vbox.get_children().find(_game) + 1)
	holdout.exited.connect(func(): open_app(&"home"))
	# Clicking the visible log text (Personal Log app, zoomed out) zooms in.
	_entry_field.gui_input.connect(_on_entry_input)
	_entry_field.tooltip_text = ""
	vbox.move_child(_bar, 0)     # Round 39: the menu bar is always the top row
	_show_view(&"home")


## Round 44 Priority 2: ONE place per kind of information.
##   TODAY     the day at a glance (status, jobs, cargo, checklist, one
##             reminder) -- replaces Today's Note + Schedule;
##   JOURNAL   the character's automatic journal (+ OBSERVATIONS, + the
##             player's own PRIVATE NOTES = the former Personal Log);
##   MESSAGES  personal correspondence (with replies);
##   FILES     documents, archives -- shift reports now live in
##             Work/Archived Reports (generated from DayPlan's history);
##   PHOTOS, ENTERTAINMENT; SHIFT HANDOVER stays a desktop shortcut.
## Old app ids still open (schedule -> Today, report -> the archive,
## log -> private notes), so nothing saved or scripted breaks.
const APPS := [
	[&"note", "Today", Color(0.98, 0.88, 0.45)],
	[&"handover", "Shift Handover", Color(0.95, 0.55, 0.4)],
	[&"journal", "Journal", Color(0.85, 0.7, 0.35)],
	[&"messages", "Messages", Color(0.35, 0.7, 1.0)],
	[&"photos", "Photos", Color(0.9, 0.5, 0.6)],
	[&"files", "Files", Color(0.75, 0.75, 0.8)],
	[&"game", "Cargo Drop", Color(0.95, 0.6, 0.25)],
	[&"holdout", "Holdout", Color(0.55, 0.85, 0.4)],
]
const DailyNote = preload("res://scripts/ui/daily_note.gd")
const APP_TITLES := {&"journal": "JOURNAL", &"observations": "OBSERVATIONS", &"mail_sent": "SENT LETTERS", &"note": "TODAY", &"note_record": "NOTE ARCHIVE", &"handover": "SHIFT HANDOVER", &"home": "DESKTOP", &"log": "PRIVATE NOTES", &"messages": "MESSAGES", &"schedule": "SCHEDULE", &"photos": "PHOTOS", &"files": "FILES", &"file": "FILES", &"report": "SHIFT REPORT", &"game": "CARGO DROP", &"holdout": "HOLDOUT"}
const Files = preload("res://scripts/ui/laptop_files.gd")
var _app_title: Label
var _brand: Label
var _desktop: GridContainer
var _home: HBoxContainer
var _clock: Label
var _note: Label
var _window: ColorRect
var _wallpaper: TextureRect
var _photo_box: VBoxContainer
var _photo: TextureRect
var _photo_caption: Label
var _files_box: VBoxContainer
var _game: Control
var holdout: Control
var _zoomed: bool = false
var _pending_app: StringName = &""
var photo_index: int = 0
var folder: String = ""            # "" = root
var open_file: String = ""
var game_best: int = 0
var _photo_cache: Dictionary = {}


func _add_button(parent: Node, id: StringName, text: String) -> Button:
	var b := Button.new()
	b.name = "App_%s" % id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func(): _on_app(id))
	parent.add_child(b)
	_buttons[id] = b
	return b


func _on_entry_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _zoomed and _view == &"log":
		_entry_field.accept_event()
		_pending_app = &"log"
		app_requested.emit(&"focus")


## Round 35: the reticle's position as a mouse hover (buttons highlight).
func hover_at(uv: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(uv.x * size.x, uv.y * size.y)
	mv.global_position = mv.position
	push_input(mv)


func _on_app(id: StringName) -> void:
	match id:
		&"home":
			open_app(&"home")
		&"back", &"save", &"close":
			app_requested.emit(id)
		&"note_history":
			_show_view(&"note_record")
		&"journal_obs":
			_show_view(&"observations")
		&"journal_notes":
			_show_view(&"log")
		&"photo_prev":
			photo_index = posmod(photo_index - 1, Files.list("Photos").size())
			_show_view(&"photos")
		&"photo_next":
			photo_index = posmod(photo_index + 1, Files.list("Photos").size())
			_show_view(&"photos")
		_:
			if _zoomed:
				open_app(id)
			else:
				# Zoom in on the chosen app (the whole computer stays usable).
				_pending_app = id
				app_requested.emit(&"focus")


## Opens an app (or the desktop) in place.
func open_app(id: StringName) -> void:
	if id == &"files":
		folder = ""
	if is_entertainment(id) and _day_plan != null and _day_plan.has_method("entertainment_allowed"):
		var ok: Dictionary = _day_plan.entertainment_allowed()
		if not ok["ok"]:
			_show_block(String(ok["reason"]))
			return
	_show_view(id)


## Round 42: the menu bar must never be wider than the screen content
## (that pushed the whole page -- the log editor too -- off the right edge).
func _fit_bar() -> void:
	if _bar == null or _brand == null:
		return
	var avail: float = layout_size().x - 24.0
	_brand.visible = not entertainment_hold
	if _bar.get_combined_minimum_size().x > avail:
		_brand.visible = false


func content_width() -> float:
	return ($Control/VBox as Control).size.x


func _show_view(v: StringName) -> void:
	if v == &"schedule":
		v = &"note"          # Round 44: folded into TODAY
	_view = v
	if v == &"report":
		# Round 44: the shift report lives in Files (archived reports).
		folder = "Work/Archived Reports"
		open_entry({"kind": "txt", "rec": _report_record(-1)})
		return
	if v == &"handover":
		# The desktop shortcut LINKS to the real records in Files: the
		# welcome handover until it is read, then the newest released
		# archive note if unread, else the archive folder.
		folder = Files.HANDOVER_PATH
		var welcome: Dictionary = Files.find(Files.HANDOVER_PATH, Files.HANDOVER_FILE)
		var notes: Array = Files.handover_records(int(_day_plan.day_number) if _day_plan != null else 1)
		if not handover_read.has(0):
			handover_read[0] = true
			open_entry({"kind": "txt", "rec": welcome})
		elif not notes.is_empty() and not handover_read.has(int(notes.back()["handover"])):
			open_entry({"kind": "txt", "rec": notes.back()})
		else:
			_show_view(&"files")
		_refresh_unread()
		return
	var text_view: bool = v in [&"report", &"schedule", &"file", &"note", &"note_record", &"journal", &"observations", &"mail_sent"]
	if _report != null:
		_report.add_theme_font_size_override("font_size", 12)
	_home.visible = v == &"home"
	_window.visible = v != &"home"
	_title.visible = v == &"log"
	$Control/VBox/HSeparator.visible = v == &"log"
	_entry_field.visible = v == &"log"
	_report.visible = text_view
	_photo_box.visible = v == &"photos"
	_files_box.visible = v == &"files"
	_game.visible = v == &"game"
	holdout.visible = v == &"holdout"
	_subtitle.visible = false
	_status.visible = false
	_refresh_note()
	var editing_log: bool = _zoomed and v == &"log"
	_entry_field.editable = editing_log
	if editing_log:
		_entry_field.grab_focus()
		_set_hint_for_editing()
	else:
		_entry_field.release_focus()
		if _zoomed:
			_hint_label.visible = true
			_hint_label.text = "ESC — step back from the laptop"
			_edit_hint_label.visible = false
		else:
			_set_hint_for_viewing()
	_buttons[&"home"].visible = v != &"home"
	_buttons[&"save"].visible = false          # Round 45: notes autosave on close
	_buttons[&"back"].visible = false          # Round 45: Esc zooms out; CLOSE LAPTOP closes
	_buttons[&"close"].visible = true
	_buttons[&"close"].add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	_app_title.text = APP_TITLES.get(v, "")
	_app_title.add_theme_color_override("font_color", Color(0.75, 0.95, 0.8))
	if v != &"home":
		blocked_reason = ""
	_fit_bar()
	if _buttons.has(&"note_history"):
		_buttons[&"note_history"].visible = v == &"note"
	if _buttons.has(&"journal_obs"):
		_buttons[&"journal_obs"].visible = v == &"journal"
		_buttons[&"journal_notes"].visible = v == &"journal"
	if _mail_box != null:
		_mail_box.visible = v == &"messages"
	match v:
		&"note":
			_note_opened()
			_report.text = "\n".join(daily_note_lines())
			_report.add_theme_font_size_override("font_size", 11)
		&"note_record":
			_report.text = "\n".join(DailyNote.record_lines(daily_note(), int(_day_plan.day_number) if _day_plan != null else 1))
			if is_inside_tree():
				get_tree().call_group(&"story_events", &"on_record_checked", "note_archive")
		&"messages":
			for m in messages_today():
				read_messages[String(m["id"])] = true
			_build_mail()
			_refresh_unread()
		&"mail_sent":
			var fm: Node = _family()
			_report.text = "\n".join(fm.sent_lines()) if fm != null else "SENT LETTERS"
			if is_inside_tree():
				get_tree().call_group(&"story_events", &"on_record_viewed", "sent_mail")
		&"journal":
			_refresh_journal()
			if _zoomed:
				_journal_pad().grab_focus()
		&"observations":
			_report.text = "\n".join(observation_lines())
		&"schedule":
			_report.text = "\n".join(schedule_lines())
		&"report":
			if _day_plan != null:
				var lines: Array = []
				if _day_plan.shift_ended and not _day_plan.shift_history.is_empty():
					lines = _day_plan.shift_history[-1]["report"]
				else:
					lines = ["SHIFT IN PROGRESS — %d%% done (report so far):" % int(round(_day_plan.shift_progress() * 100.0))] + Array(_day_plan.shift_report_lines()).slice(1)
				_report.text = "\n".join(lines)
		&"photos":
			var ph: Array = Files.list("Photos")
			var rec: Dictionary = ph[clampi(photo_index, 0, ph.size() - 1)]
			if not _photo_cache.has(rec["photo"]):
				_photo_cache[rec["photo"]] = Files.photo(rec["photo"])
			_photo.texture = _photo_cache[rec["photo"]]
			_photo_caption.text = "%s  ·  %s  (%d/%d)" % [rec["caption"], rec["date"], photo_index + 1, ph.size()]
		&"files":
			_build_file_list()
		&"game":
			if _zoomed:
				_game.grab_focus()
		&"holdout":
			if _zoomed:
				holdout.grab_focus()


func _build_file_list() -> void:
	for c in _files_box.get_children():
		c.queue_free()
	var crumb := Label.new()
	crumb.text = "/home/technician/%s" % folder
	crumb.add_theme_font_size_override("font_size", 11)
	crumb.add_theme_color_override("font_color", Color(0.6, 0.75, 0.7))
	_files_box.add_child(crumb)
	var grid := GridContainer.new()
	grid.columns = 2
	_files_box.add_child(grid)
	var entries: Array = []
	if folder == "":
		for f in Files.folders():
			entries.append({"name": f + "/", "kind": "dir", "target": f})
	else:
		entries.append({"name": "../", "kind": "up"})
		for sf in Files.subfolders(folder):
			entries.append({"name": sf + "/", "kind": "dir", "target": folder + "/" + sf})
		for f in Files.list(folder):
			entries.append({"name": f["name"], "kind": f["type"], "rec": f})
		if folder == Files.HANDOVER_PATH:
			# Round 45: the previous technician's released shift notes.
			for r in Files.handover_records(int(_day_plan.day_number) if _day_plan != null else 1):
				entries.append({"name": r["name"] + ("" if handover_read.has(int(r["handover"])) else "  ●"), "kind": "txt", "rec": r})
		if folder == "Work/Archived Reports" and _day_plan != null:
			# Round 44: this rotation's shift reports (DayPlan's own history).
			for i in _day_plan.shift_history.size():
				var r: Dictionary = _report_record(i)
				entries.append({"name": r["name"], "kind": "txt", "rec": r})
			if not _day_plan.shift_ended:
				var cur: Dictionary = _report_record(-1)
				entries.append({"name": cur["name"], "kind": "txt", "rec": cur})
	for e in entries:
		var b := Button.new()
		b.text = String(e["name"]) + (("   " + String(e["rec"]["date"])) if e.has("rec") and String(e["rec"].get("date", "")) != "" else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(216, 24)
		b.add_theme_font_size_override("font_size", 11)
		# Round 39: a small type icon per entry (folder / text / photo / app).
		var kind: String = String(e["kind"])
		var ic: StringName = &"files" if kind in ["dir", "up"] else ({"img": &"photos", "app": &"game", "msg": &"messages", "log": &"log"}.get(kind, &"report"))
		b.icon = _app_icon(ic, {&"files": Color(0.75, 0.75, 0.8), &"photos": Color(0.9, 0.5, 0.6), &"game": Color(0.95, 0.6, 0.25), &"messages": Color(0.35, 0.7, 1.0), &"log": Color(0.85, 0.7, 0.35)}.get(ic, Color(0.6, 0.85, 0.9)))
		b.add_theme_constant_override("icon_max_width", 18)
		b.pressed.connect(open_entry.bind(e))
		b.name = "Entry_" + String(e["name"]).validate_node_name()
		grid.add_child(b)


## Opens a folder / file from the Files app.
func open_entry(e: Dictionary) -> void:
	match String(e["kind"]):
		"dir":
			folder = e["target"]
			_show_view(&"files")
		"up":
			folder = folder.get_base_dir() if folder.find("/") != -1 else ""
			_show_view(&"files")
		"txt":
			open_file = "%s/%s" % [folder, e["rec"]["name"]]
			_view = &"file"
			_show_view(&"file")
			_report.text = "%s\n\n%s" % [open_file, e["rec"]["text"]]
			if int(e["rec"].get("handover", 0)) > 0:
				handover_read[int(e["rec"]["handover"])] = true
				_refresh_unread()
				_refresh_note()
			# Round 42: a few documents are NARRATIVE discoveries (read on
			# purpose by the technician) -- the story director decides what
			# that means; the laptop never explains it.
			if String(e["rec"].get("story", "")) != "" and is_inside_tree():
				get_tree().call_group(&"story_events", &"on_story_discovery", String(e["rec"]["story"]))
		"img":
			var ph: Array = Files.list("Photos")
			for i in ph.size():
				if ph[i]["name"] == e["rec"]["name"]:
					photo_index = i
			_show_view(&"photos")
		"msg":
			_show_view(&"messages")
		"log":
			_show_view(&"log")
		"app":
			_show_view(StringName(e["rec"].get("app", "game")))


# ======================================================================
# Round 37 Priority 11: personal content. MESSAGES are short, ordinary,
# fictional personal mail that arrives by day (family, a friend, the
# employer's payroll office, a reminder from home) -- no horror hints.
# SCHEDULE is DayPlan's real day (no second calendar). PHOTOS is an
# honest empty album: no imagery is invented or borrowed.
# ======================================================================
const MESSAGES := [
	{"id": "m1", "day": 1, "from": "Mara (sister)", "text": "Made it up there? Mum says to eat something that isn't from a pouch. Call when you get a window."},
	{"id": "m2", "day": 1, "from": "Crew Payroll", "text": "Your rotation allowance has been processed. Statement attached to your account."},
	{"id": "m3", "day": 2, "from": "Dev", "text": "Lost the pub quiz without you. Apparently nobody else knows the capital of Mongolia. Ulaanbaatar, I know NOW."},
	{"id": "m4", "day": 3, "from": "Mara (sister)", "text": "Pip learned to open the treat cupboard. We have moved the treats. Pip is plotting."},
	{"id": "m5", "day": 4, "from": "Dental Clinic", "text": "Reminder: your check-up is rebooked for after your rotation. Reply to change the date."},
	{"id": "m6", "day": 5, "from": "Dev", "text": "Sending the bread recipe you asked for. Step one: be patient. Step two: be more patient."},
	{"id": "m7", "day": 7, "from": "Mum", "text": "The garden is full of tomatoes again. I'll save you some jam. Sleep properly up there."},
	{"id": "m8", "day": 9, "from": "Crew Scheduling", "text": "Your next rest period is confirmed. Thank you for the clean maintenance logs this week."},
]
var read_messages: Dictionary = {}   # id -> true (saved with the laptop)


func messages_today() -> Array:
	var d: int = int(_day_plan.day_number) if _day_plan != null else 1
	return MESSAGES.filter(func(m): return int(m["day"]) <= d)


func unread_count() -> int:
	return messages_today().filter(func(m): return not read_messages.has(String(m["id"]))).size()


func messages_lines() -> Array:
	var out: Array = ["MESSAGES"]
	var ms: Array = messages_today()
	ms.reverse()
	for m in ms:
		out.append("")
		out.append("%s%s · day %d" % ["" if read_messages.has(String(m["id"])) else "NEW  ", m["from"], int(m["day"])])
		out.append(String(m["text"]))
	return out


func schedule_lines() -> Array:
	if _day_plan == null:
		return ["SCHEDULE", "No station link."]
	var dp: Node = _day_plan
	var out: Array = ["SCHEDULE · DAY %d" % dp.day_number]
	out.append("Shift: %s" % ("over — rest" if dp.shift_ended else "%d%% done" % int(round(dp.shift_progress() * 100.0))))
	out.append("Today: %s" % dp.today_title())
	var rows: Array = dp.order_rows().filter(func(r): return not r.get("done", false))
	for r in rows.slice(0, 5):
		out.append("  - %s %s" % [r["tag"], r["action"]])
	if dp.cargo_port() != null and dp.cargo_duty != "open":
		out.append("Next cargo: day %d" % dp.next_cargo_day)
	out.append("")
	out.append("Personal: rest after the shift · reply to Mara · water the basil")
	return out


## Round 45: archive notes read (0 = the welcome handover); saved.
var handover_read: Dictionary = {}


func handover_unread() -> int:
	var n: int = 0 if handover_read.has(0) else 1
	for r in Files.handover_records(int(_day_plan.day_number) if _day_plan != null else 1):
		if not handover_read.has(int(r["handover"])):
			n += 1
	return n


## Today's checklist: has the note released today been read?
func todays_handover_read() -> bool:
	var d: int = int(_day_plan.day_number) if _day_plan != null else 1
	return d > Files.HANDOVER_NOTES.size() or handover_read.has(d)


func _refresh_unread() -> void:
	if _buttons.has(&"handover"):
		var hu: int = handover_unread()
		_buttons[&"handover"].text = "Shift Handover (%d)" % hu if hu > 0 else "Shift Handover"
	if _buttons.has(&"messages"):
		var fm: Node = _family()
		var n: int = unread_count() + (fm.unread_count() if fm != null else 0)
		_buttons[&"messages"].text = "Messages (%d)" % n if n > 0 else "Messages"


func current_view() -> StringName:
	return _view


func button(id: StringName) -> Button:
	return _buttons.get(id, null)


## A click from the 3D world at normalized screen coordinates.
func click_at(uv: Vector2) -> void:
	var pos := Vector2(uv.x * size.x, uv.y * size.y)
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	push_input(mv)
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = pos
		b.global_position = pos
		push_input(b)


## Normalized screen coordinates of a control's centre (tests/tools).
func uv_of(c: Control) -> Vector2:
	var r: Rect2 = c.get_global_rect()
	return r.get_center() / layout_size()


func refresh_day() -> void:
	if _day_plan == null:
		return
	_title.text = "SESSION LOG — DAY %d" % _day_plan.day_number
	if _day_plan.is_new_shift():
		_subtitle.text = "New shift. Report to the Control Room workstation."
	else:
		_subtitle.text = "Shift in progress."
	_status.text = "Today: %s" % _day_plan.today_title()
	_refresh_unread()
	_refresh_note()


func get_feed_texture() -> Texture2D:
	return get_texture()


func show_entry(text: String) -> void:
	_entry_field.text = text


func get_entry_text() -> String:
	return _entry_field.text


## editable=true also grabs keyboard focus (so forward_key() reaches
## it immediately); editable=false releases focus so no stray
## forwarded key can land in it while just viewing.
## Round 38: ZOOMED (focused use of the whole computer) on / off. Zooming
## in opens the requested app (the Personal Log by default, e.g. via T);
## zooming out returns to the desktop.
func set_editing(zoomed: bool) -> void:
	_zoomed = zoomed
	if _bar == null:
		_entry_field.editable = zoomed
		return
	if zoomed:
		# Round 39: zooming in on the laptop itself shows whatever is on the
		# screen (the DESKTOP after opening it); an app clicked while zoomed
		# out, or T (Personal Log), is opened as part of the zoom.
		var app: StringName = _pending_app if _pending_app != &"" else _view
		_pending_app = &""
		_show_view(app)
	else:
		_show_view(&"home")   # "< Save & Back": back to the desktop, zoomed out


## The app to open as part of the next zoom-in (T = Personal Log).
func set_pending_app(id: StringName) -> void:
	_pending_app = id


func is_zoomed() -> bool:
	return _zoomed


## Forwards a real keyboard InputEvent into this viewport so whichever
## Control has focus (the entry field, while editing) receives it as
## if it had been typed directly into this viewport.
func forward_key(event: InputEventKey) -> void:
	push_input(event)


## The editing hint is a SEPARATE label (not a reused/repurposed text
## swap on HintLabel) so it can be styled much more visibly (brighter
## color, larger font) than the dim ordinary-viewing hint -- the dim
## styling was confirmed to read as "no visible indication Esc exits"
## in actual play even though the hint text was technically present.
func _set_hint_for_viewing() -> void:
	_hint_label.visible = true
	_hint_label.text = "T: Edit Entry     F: Close Laptop"
	_edit_hint_label.visible = false


func _set_hint_for_editing() -> void:
	_hint_label.visible = false
	_edit_hint_label.visible = true


# ======================================================================
# Round 39 Priority 1: the laptop reads as a real personal computer -- a
# wallpaper (one of the technician's own photos), a top MENU BAR (brand,
# current app, controls, day/shift clock), desktop ICONS, a sticky TODAY
# note, and apps opening in an opaque WINDOW over the wallpaper.
# ======================================================================
func _build_chrome() -> void:
	var root: Control = $Control
	_wallpaper = TextureRect.new()
	_wallpaper.name = "Wallpaper"
	_wallpaper.texture = Files.wallpaper(960, 560)
	_wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wallpaper.modulate = Color(0.95, 0.95, 0.95)
	_wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_wallpaper)
	root.move_child(_wallpaper, 1)
	var bar_bg := ColorRect.new()
	bar_bg.name = "MenuBarBg"
	bar_bg.color = Color(0.02, 0.03, 0.035, 0.88)
	bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_bg.offset_bottom = 38
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bg)
	root.move_child(bar_bg, 2)
	_window = ColorRect.new()
	_window.name = "Window"
	_window.color = Color(0.05, 0.07, 0.065, 0.97)
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.offset_left = 6
	_window.offset_top = 40
	_window.offset_right = -6
	_window.offset_bottom = -4
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_window)
	root.move_child(_window, 3)


func _build_note() -> void:
	var panel := PanelContainer.new()
	panel.name = "TodayNote"
	panel.custom_minimum_size = Vector2(118, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.9, 0.55, 0.93)
	sb.set_content_margin_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 3
	panel.add_theme_stylebox_override("panel", sb)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", 10)
	_note.add_theme_color_override("font_color", Color(0.2, 0.17, 0.1))
	_note.custom_minimum_size = Vector2(106, 0)
	panel.add_child(_note)
	_home.add_child(panel)


func _refresh_note() -> void:
	if _note == null:
		return
	var lines: Array = []
	if _day_plan != null:
		lines.append("DAY %d" % _day_plan.day_number)
		lines.append(String(_day_plan.today_title()))
		# Round 43: the sticky shows what is still open on today's checklist.
		var open_items: Array = Array(daily_note()["items"]).filter(func(it): return not it["done"])
		for it in open_items.slice(0, 3):
			lines.append("- " + String(it["label"]).to_lower())
		if open_items.is_empty():
			lines.append("- all done. rest.")
	var n: int = unread_count() if _day_plan != null else 0
	if n > 0:
		lines.append("- %d new message%s" % [n, "" if n == 1 else "s"])
	_note.text = "\n".join(lines)
	_refresh_clock()


func _refresh_clock() -> void:
	if _clock == null or _day_plan == null:
		return
	# Round 42: a compact computer clock (day + station time); the long
	# shift status made the menu bar wider than the screen.
	if _day_plan.has_method("clock_text_hhmm"):
		# Round 43: the shift clock visibly PAUSED while a game is played.
		# Round 45: a normal running clock (no PAUSED label) -- the station
		# clock keeps moving; only the shift budget is held.
		_clock.text = "D%d  %s" % [_day_plan.day_number, _day_plan.clock_text_hhmm()]
		_clock.add_theme_color_override("font_color", Color(0.85, 0.9, 0.88))
	elif _day_plan.has_method("shift_status_text"):
		_clock.text = _day_plan.shift_status_text()
	else:
		_clock.text = "DAY %d" % _day_plan.day_number


var _clock_tick: float = 0.0


func _process(delta: float) -> void:
	_clock_tick += delta
	if _clock_tick >= 1.0:
		_clock_tick = 0.0
		_refresh_clock()
	_update_entertainment_hold()
	# Round 44 Priority 20: a closed laptop does not render its screen.
	var lv: Node = get_parent()
	var lid_open: bool = lv == null or not lv.has_method("is_open") or lv.is_open() or _zoomed
	var want_mode: int = SubViewport.UPDATE_ALWAYS if lid_open else SubViewport.UPDATE_DISABLED
	if render_target_update_mode != want_mode:
		render_target_update_mode = want_mode


# ======================================================================
# Round 44 Priority 1: the WHOLE focused (zoomed-in) laptop holds gameplay
# time under the &"laptop" reason -- desktop, Today, messages, journal,
# files, photos and games alike. If a genuine emergency starts while
# focused, the focus ends (the technician is handed back the station) and
# the hold is released; zooming in during one is refused (sleep_state.gd).
# The Round 43 notes below describe the earlier games-only policy.
# Round 43 Priority 1: PERSONAL GAMES PAUSE THE SHIFT CLOCK. The laptop
# distinguishes PRODUCTIVITY apps (log, notes, messages, files, report --
# the clock runs) from ENTERTAINMENT apps (Cargo Drop, Holdout, any future
# game listed in ENTERTAINMENT_APPS). While a game is actively in use
# (its window open on the zoomed-in laptop) DayPlan's clock is held under
# the &"entertainment" reason; it resumes the moment the game is left
# (desktop, zoom out, laptop closed). Emergency policy (the safer one):
# games refuse to open during an active station emergency, and an
# emergency that starts mid-game pauses the game and releases the hold
# immediately, with an unmistakable alert in the game window.
# ======================================================================
const ENTERTAINMENT_APPS := [&"game", &"holdout"]
var entertainment_hold: bool = false
var blocked_reason: String = ""


func is_entertainment(id: StringName) -> bool:
	return id in ENTERTAINMENT_APPS


func _update_entertainment_hold() -> void:
	var want: bool = _zoomed
	if want and _day_plan != null and _day_plan.has_method("entertainment_allowed"):
		var ok: Dictionary = _day_plan.entertainment_allowed()
		if not ok["ok"]:
			want = false
			_pause_games()
			_show_block(String(ok["reason"]))
			# Hand control back: end the focused session.
			app_requested.emit(&"back")
	if want != entertainment_hold:
		entertainment_hold = want
		_refresh_clock()
		_fit_bar()
		if _day_plan != null and _day_plan.has_method("hold_clock"):
			_day_plan.hold_clock(&"laptop", want)


func is_visible_game() -> bool:
	return (_view == &"game" and _game != null and _game.visible) or (_view == &"holdout" and holdout != null and holdout.visible)


func _pause_games() -> void:
	if _game != null and not _game.game_over:
		_game.paused = true
	if holdout != null and holdout.mode == "play":
		holdout.action("pause")


## Shown in place of a refused / interrupted game: back on the desktop with
## a clear alert in the menu bar title.
func _show_block(reason: String) -> void:
	blocked_reason = reason
	_show_view(&"home")
	_app_title.text = reason
	_app_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))


## A small pictogram per app (procedural; no external assets).
static func _app_icon(id: StringName, c: Color) -> ImageTexture:
	var w := 30
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(1, 1, w - 2, h - 2), c.darkened(0.35))
	img.fill_rect(Rect2i(2, 2, w - 4, h - 4), c)
	var ink := Color(0.08, 0.09, 0.1)
	var paper := Color(0.96, 0.95, 0.9)
	match id:
		&"log", &"journal":
			img.fill_rect(Rect2i(8, 4, 14, 18), paper)
			for k in 4:
				img.fill_rect(Rect2i(10, 7 + k * 3, 10, 1), ink)
		&"messages":
			img.fill_rect(Rect2i(5, 5, 20, 12), paper)
			img.fill_rect(Rect2i(8, 17, 4, 4), paper)
			img.fill_rect(Rect2i(9, 9, 12, 1), ink)
			img.fill_rect(Rect2i(9, 12, 8, 1), ink)
		&"schedule":
			img.fill_rect(Rect2i(6, 5, 18, 16), paper)
			img.fill_rect(Rect2i(6, 5, 18, 4), c.darkened(0.5))
			for k in 3:
				for j in 4:
					img.fill_rect(Rect2i(8 + j * 4, 11 + k * 3, 2, 2), ink)
		&"photos":
			img.fill_rect(Rect2i(5, 5, 20, 16), Color(0.55, 0.75, 0.95))
			for x in 20:
				var hh: int = 6 - absi(x - 9) / 2
				if hh > 0:
					img.fill_rect(Rect2i(5 + x, 21 - hh, 1, hh), Color(0.25, 0.45, 0.3))
			img.fill_rect(Rect2i(19, 7, 3, 3), Color(1.0, 0.9, 0.4))
		&"files":
			img.fill_rect(Rect2i(5, 7, 8, 3), Color(0.98, 0.85, 0.45))
			img.fill_rect(Rect2i(5, 9, 20, 12), Color(0.98, 0.8, 0.35))
		&"report":
			img.fill_rect(Rect2i(8, 4, 14, 18), paper)
			img.fill_rect(Rect2i(11, 3, 8, 3), ink)
			for k in 3:
				img.fill_rect(Rect2i(10, 16 - k * 3, 3 + k * 3, 2), Color(0.2, 0.5, 0.45))
		&"game":
			for p in [[7, 13], [13, 13], [13, 7], [19, 13]]:
				img.fill_rect(Rect2i(p[0], p[1], 5, 5), Color(0.9, 0.55, 0.2))
				img.fill_rect(Rect2i(p[0], p[1], 5, 1), Color(1.0, 0.8, 0.5))
		&"note":
			img.fill_rect(Rect2i(7, 3, 16, 20), paper)
			img.fill_rect(Rect2i(7, 3, 16, 3), Color(0.9, 0.4, 0.3))
			for k in 4:
				img.fill_rect(Rect2i(9, 9 + k * 3, 2, 2), ink)
				img.fill_rect(Rect2i(12, 9 + k * 3, 9, 1), ink)
		&"handover":
			img.fill_rect(Rect2i(5, 7, 8, 3), Color(0.98, 0.85, 0.45))
			img.fill_rect(Rect2i(5, 9, 20, 12), Color(0.98, 0.8, 0.35))
			img.fill_rect(Rect2i(10, 4, 12, 13), paper)
			img.fill_rect(Rect2i(12, 7, 8, 1), ink)
			img.fill_rect(Rect2i(12, 10, 6, 1), ink)
		&"holdout":
			# Round 45: a spaceman (white, gold visor) among three creatures.
			img.fill_rect(Rect2i(4, 4, 22, 18), Color(0.1, 0.09, 0.14))
			for zp in [[7, 7], [20, 8], [9, 17]]:
				img.fill_rect(Rect2i(zp[0], zp[1], 4, 4), Color(0.78, 0.4, 0.85))
			img.fill_rect(Rect2i(14, 12, 4, 4), Color(0.93, 0.94, 0.96))
			img.fill_rect(Rect2i(16, 12, 2, 2), Color(0.95, 0.75, 0.3))
			img.fill_rect(Rect2i(18, 13, 3, 1), Color(1.0, 0.92, 0.45))
	return ImageTexture.create_from_image(img)



# ======================================================================
# Round 43 Priorities 9-11 / 22: TODAY'S NOTE (daily shift note) and the
# SHIFT HANDOVER shortcut on the desktop. The note's content is derived
# (scripts/ui/daily_note.gd); story PRESENTATION overlays are layered on at
# display time only (story_events.gd laptop_overlays()) -- authentic
# player data (the Personal Log) and the save are never altered.
# ======================================================================
func _quarters_node() -> Node:
	return get_tree().get_first_node_in_group(&"quarters_life") if is_inside_tree() else null


func _story() -> Node:
	return get_tree().get_first_node_in_group(&"story_events") if is_inside_tree() else null


func daily_note() -> Dictionary:
	var note: Dictionary = DailyNote.build(_day_plan, _quarters_node(), todays_handover_read())
	# Round 45: an ordinary station duty from the story (the observation
	# port check, after the window cue was ignored twice).
	var we: Node = get_tree().get_first_node_in_group(&"window_encounter") if is_inside_tree() else null
	if we != null:
		note["items"] = Array(note["items"]) + we.today_items()
	return note


func daily_note_lines() -> Array:
	var st: Node = _story()
	var ov: Array = st.laptop_overlays("daily_note") if st != null and st.has_method("laptop_overlays") else []
	return DailyNote.lines(daily_note(), ov)


func _note_opened() -> void:
	var st: Node = _story()
	if st != null and st.has_method("on_document_opened"):
		st.on_document_opened("daily_note")



# ======================================================================
# Round 44: archived shift reports, journal observations, family mail.
# ======================================================================
func _family() -> Node:
	return get_tree().get_first_node_in_group(&"family_mail") if is_inside_tree() else null


## A shift report as a file record (i = index in shift_history; -1 = the
## current shift: in progress, or the latest finished one).
func _report_record(i: int) -> Dictionary:
	if _day_plan == null:
		return {"name": "shift_report.txt", "date": "", "type": "txt", "text": "No station link."}
	if i >= 0 and i < _day_plan.shift_history.size():
		var h: Dictionary = _day_plan.shift_history[i]
		return {"name": "shift_report_day_%02d.txt" % int(h["day"]), "date": "day %d" % int(h["day"]), "type": "txt", "text": "\n".join(Array(h["report"]))}
	if _day_plan.shift_ended and not _day_plan.shift_history.is_empty():
		return _report_record(_day_plan.shift_history.size() - 1)
	var lines: Array = ["SHIFT IN PROGRESS — %d%% done (report so far):" % int(round(_day_plan.shift_progress() * 100.0))] + Array(_day_plan.shift_report_lines()).slice(1)
	return {"name": "shift_report_day_%02d_in_progress.txt" % int(_day_plan.day_number), "date": "today", "type": "txt", "text": "\n".join(lines)}


## Compact investigation summary: what was noticed / checked / contradicted.
func observation_lines() -> Array:
	var st: Node = _story()
	var out: Array = ["OBSERVATIONS"]
	if st == null or not "evidence" in st or st.evidence.is_empty():
		out.append("  Nothing out of the ordinary. Good.")
		return out
	var by: Dictionary = {}
	for e in st.evidence:
		by[String(e["event"])] = true
	for ev in by:
		var mark: String = {"observed": "?", "checked": "?·", "contradicted": "!"}.get(st.investigation_state(ev), "")
		var jn: Node = get_tree().get_first_node_in_group(&"journal")
		var txt: String = String(jn.OBSERVED.get(ev, ev)) if jn != null else ev
		out.append("  [%s] %s" % [mark, txt.left(78)])
	out.append("")
	out.append("  ? noticed   ?· checked in person   ! records disagree")
	return out


var _mail_box: HBoxContainer
var _mail_list: VBoxContainer
var _mail_text: Label
var _mail_opts: VBoxContainer
var mail_open: String = ""


func _ensure_mail_ui() -> void:
	if _mail_box != null:
		return
	var vbox: VBoxContainer = $Control/VBox
	_mail_box = HBoxContainer.new()
	_mail_box.name = "MailView"
	_mail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mail_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_mail_box)
	vbox.move_child(_mail_box, vbox.get_children().find(_report) + 1)
	_mail_list = VBoxContainer.new()
	_mail_list.custom_minimum_size = Vector2(140, 0)
	_mail_list.add_theme_constant_override("separation", 2)
	_mail_box.add_child(_mail_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mail_box.add_child(right)
	_mail_text = Label.new()
	_mail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mail_text.add_theme_font_size_override("font_size", 11)
	_mail_text.add_theme_color_override("font_color", Color(0.82, 0.9, 0.86))
	_mail_text.clip_text = true
	right.add_child(_mail_text)
	_mail_opts = VBoxContainer.new()
	_mail_opts.add_theme_constant_override("separation", 2)
	right.add_child(_mail_opts)


func _mail_button(parent: Node, text: String, cb: Callable, name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.name = name.validate_node_name()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_mail() -> void:
	_ensure_mail_ui()
	for c in _mail_list.get_children() + _mail_opts.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var fm: Node = _family()
	if fm != null:
		var convs: Array = fm.available()
		convs.reverse()
		for conv in convs:
			var unread: bool = fm.state(conv) == "unread" or (fm.answer_delivered(conv) and not bool(fm.threads.get(conv, {}).get("answer_read", false)))
			_mail_button(_mail_list, "%s%s · %s" % ["● " if unread else "", fm.CONVERSATIONS[conv]["short"], fm.CONVERSATIONS[conv]["subject"]], open_thread.bind(conv), "Thread_" + conv)
	_mail_button(_mail_list, "Older mail", open_thread.bind("_older"), "Thread_older")
	_mail_button(_mail_list, "Sent letters ›", func(): _show_view(&"mail_sent"), "Thread_sent")
	if mail_open == "" and fm != null and not fm.available().is_empty():
		mail_open = fm.available().back()
	_fill_thread()


func open_thread(conv: String) -> void:
	mail_open = conv
	_build_mail()


func _fill_thread() -> void:
	var fm: Node = _family()
	for c in _mail_opts.get_children():
		_mail_opts.remove_child(c)
		c.queue_free()
	if mail_open == "_older" or mail_open == "" or fm == null or not fm.CONVERSATIONS.has(mail_open):
		_mail_text.text = "\n".join(messages_lines())
		return
	fm.mark_read(mail_open)
	if is_inside_tree():
		get_tree().call_group(&"story_events", &"on_letter_opened", mail_open)
	_mail_text.text = "\n".join(fm.thread_lines(mail_open))
	if fm.state(mail_open) != "replied":
		for o in fm.options(mail_open):
			_mail_button(_mail_opts, "Reply: %s" % o["text"], send_reply.bind(mail_open, String(o["id"])), "Reply_" + String(o["id"]))
	_refresh_unread()


func send_reply(conv: String, choice: String) -> bool:
	var fm: Node = _family()
	var ok: bool = fm != null and fm.reply(conv, choice)
	_build_mail()
	return ok



# ======================================================================
# Round 45 Priority 14: AUTO-WRITING. In JOURNAL, any ordinary key press
# (forwarded into this viewport while the laptop is focused) writes the
# next few characters of today's pre-composed entry. Backspace, Esc and
# shortcut chords never touch the text; held keys type at a throttled
# pace; the technician never moves (focused laptop).
# ======================================================================
var _pad: Control
var _type_t: int = 0


func _journal() -> Node:
	return get_tree().get_first_node_in_group(&"journal") if is_inside_tree() else null


func _journal_pad() -> Control:
	if _pad == null:
		_pad = Control.new()
		_pad.name = "JournalPad"
		_pad.focus_mode = Control.FOCUS_ALL
		_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pad.gui_input.connect(_on_pad_input)
		$Control.add_child(_pad)
	return _pad


func _today_n() -> int:
	return int(_day_plan.day_number) if _day_plan != null else 1


func _refresh_journal() -> void:
	var jn: Node = _journal()
	_report.text = "\n".join(jn.page_lines(_today_n())) if jn != null else "JOURNAL"


func journal_key(event: InputEventKey) -> bool:
	if not event.pressed or event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return false
	if event.keycode in [KEY_BACKSPACE, KEY_ESCAPE, KEY_TAB, KEY_DELETE] or (event.unicode < 32 and event.keycode != KEY_ENTER):
		return false
	var now: int = Time.get_ticks_msec()
	if event.echo and now - _type_t < 45:
		return true          # held key: throttled
	_type_t = now
	var jn: Node = _journal()
	if jn == null:
		return false
	jn.type_keys(_today_n(), 1)
	_refresh_journal()
	return true


func _on_pad_input(e: InputEvent) -> void:
	if _view == &"journal" and e is InputEventKey and journal_key(e):
		_pad.accept_event()
