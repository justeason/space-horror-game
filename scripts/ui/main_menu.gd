extends Control
## Round 34 Priority 8: the game's MAIN MENU (separate from the in-world
## Control Room workstation). Continue / New Game / Load Game / Settings /
## Credits / Quit. Loading reuses SaveGame's validated, deferred path:
## a save is read + validated HERE, then queued for the station scene,
## which restores it before the player gets control.

const SaveGameScript = preload("res://scripts/station/save_game.gd")
const GameFlow = preload("res://scripts/station/game_flow.gd")
const GS = preload("res://scripts/station/game_settings.gd")
const L10N = preload("res://scripts/ui/localization.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

var sg: Node
var _center: CenterContainer
var _page: Control
var buttons := {}
var status_label: Label
var _changing := false


func _ready() -> void:
	L10N.setup()
	GS.apply_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(0.85, 0.55, 0.1, 0.8)
	stripe.position = Vector2(0, 0)
	stripe.size = Vector2(6, 4000)
	add_child(stripe)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	sg = SaveGameScript.new()
	sg.name = "MenuSaveSlots"
	add_child(sg)
	show_main()
	# Round 45: exported-build smoke test (only with SMH_SMOKE_TEST=1).
	var Smoke = load("res://scripts/station/smoke_test.gd")
	if Smoke.wanted() and get_tree().root.get_node_or_null("SmokeTest") == null:
		var st: Node = Smoke.new()
		st.name = "SmokeTest"
		get_tree().root.add_child.call_deferred(st)
		st.run.call_deferred(self)


func _clear() -> void:
	if _page != null:
		_page.queue_free()
	buttons.clear()


func _vbox() -> VBoxContainer:
	_clear()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(380, 0)
	_center.add_child(v)
	_page = v
	return v


func show_main() -> void:
	var v := _vbox()
	var title := Label.new()
	title.text = "SATELLITE MAINTENANCE"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Station technician · deep orbit"
	sub.add_theme_color_override("font_color", Color(0.5, 0.58, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var latest: Dictionary = sg.latest_slot()
	_button(v, "continue", tr("MENU_CONTINUE") + ("  —  " + tr("SLOT_DAY") % latest["day"] if not latest.is_empty() else ""), _on_continue, latest.is_empty())
	_button(v, "new", tr("MENU_NEW_GAME"), _on_new_game)
	_button(v, "load", tr("MENU_LOAD"), show_load)
	_button(v, "settings", tr("MENU_SETTINGS"), show_settings)
	_button(v, "credits", tr("MENU_CREDITS"), show_credits)
	_button(v, "quit", tr("MENU_QUIT"), func(): get_tree().quit())
	status_label = Label.new()
	status_label.text = tr("MENU_NO_SAVE") if latest.is_empty() else ""
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(status_label)


func _button(parent: Node, id: String, text: String, cb: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	parent.add_child(b)
	buttons[id] = b
	return b


func _on_continue() -> void:
	var latest: Dictionary = sg.latest_slot()
	if not latest.is_empty():
		start_load(latest["path"])


func _on_new_game() -> void:
	var any_save := false
	for e in sg.list_slots():
		any_save = any_save or e["ok"]
	if not any_save:
		start_new_game()
		return
	var v := _vbox()
	var l := Label.new()
	l.text = tr("MENU_NEW_CONFIRM")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	_button(v, "confirm_new", tr("MENU_START"), start_new_game)
	_button(v, "cancel", tr("MENU_CANCEL"), show_main)


func show_load() -> void:
	var v := _vbox()
	var t := Label.new()
	t.text = tr("MENU_LOAD")
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)
	for e in sg.list_slots():
		var label: String = tr("SLOT_MANUAL") if e["slot"] == "manual" else tr("SLOT_AUTOSAVE")
		if e["ok"]:
			label += "  —  " + tr("SLOT_DAY") % e["day"] + "  ·  " + Time.get_datetime_string_from_unix_time(int(e["saved_at"]), true)
		else:
			label += "  —  " + (tr("SLOT_EMPTY") if e["message"] == "No saved game found." else e["message"])
		var path: String = e["path"]
		_button(v, "slot_" + String(e["slot"]), label, func(): start_load(path), not e["ok"])
	_button(v, "back", tr("MENU_BACK"), show_main)


func show_settings() -> void:
	_clear()
	var p := SettingsPanel.new()
	p.closed.connect(show_main)
	_center.add_child(p)
	_page = p


func show_credits() -> void:
	var v := _vbox()
	var t := Label.new()
	t.text = tr("CREDITS_TITLE")
	t.add_theme_font_size_override("font_size", 24)
	v.add_child(t)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	body.text = credits_text()
	v.add_child(body)
	_button(v, "back", tr("MENU_BACK"), show_main)


## Only verifiable facts about this project's contents.
static func credits_text() -> String:
	return "\n".join([
		"Satellite Maintenance Horror — a project by its author (repository owner).",
		"Development assistance: Claude (Anthropic).",
		"",
		"Built with the Godot Engine — MIT License. © 2014-present Godot Engine contributors; © 2007-2014 Juan Linietsky, Ariel Manzur.",
		"Interface text uses Godot's built-in default font; Chinese text uses your system's fonts.",
		"",
		"All 3D geometry is constructed in-engine; all sound effects and ambience are synthesized at runtime. No third-party art, audio or font files are included.",
	])


func start_new_game() -> void:
	if _changing:
		return
	_changing = true
	GameFlow.start_mode = "new_game"
	GameFlow.from_main_menu = true
	_go.call_deferred()


func start_load(path: String) -> void:
	if _changing:
		return
	var r: Dictionary = sg.read_save(path)
	if not r["ok"]:
		if status_label != null and is_instance_valid(status_label):
			status_label.text = "Load failed: " + r["message"]
		return
	_changing = true
	var data: Dictionary = r["data"]
	data["_save_path"] = sg.save_path
	data["_autosave_path"] = sg.autosave_path
	SaveGameScript.queue_load(data)
	GameFlow.start_mode = ""
	GameFlow.from_main_menu = true
	_go.call_deferred()


func _go() -> void:
	get_tree().change_scene_to_file(GameFlow.STATION)
