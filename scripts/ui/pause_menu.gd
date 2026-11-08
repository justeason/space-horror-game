extends CanvasLayer
## Round 34 Priority 8: the in-game PAUSE MENU (Esc). Pauses the tree --
## which also pauses the shift clock (DayPlan._process). Esc priority: an
## active modal (seated workstation, laptop / log editor, a focused
## equipment panel, sleeping) keeps Esc for itself; only free play opens
## this menu. Esc while open goes back / resumes.

const GameFlow = preload("res://scripts/station/game_flow.gd")
const GS = preload("res://scripts/station/game_settings.gd")
const L10N = preload("res://scripts/ui/localization.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

var _root: Control
var _center: CenterContainer
var _page: Control
var buttons := {}
var status_label: Label
var is_open := false


func _ready() -> void:
	add_to_group(&"pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	L10N.setup()
	GS.apply_all()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_center)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if is_open:
		if _page is PanelContainer:   # settings sub-page -> back
			show_main()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if modal_active():
		return   # the modal's own Esc handler closes it
	open()
	get_viewport().set_input_as_handled()


func modal_active() -> bool:
	var main: Node = get_parent()
	var ws: Node = main.get_node_or_null("WorkstationState")
	if ws != null and (ws.is_in_use() or ws.get("_transitioning") == true):
		return true   # also mid sit-down / stand-up: never freeze a transition
	var ss: Node = main.get_node_or_null("SleepState")
	if ss != null and (ss.is_laptop_open() or ss.is_editing() or ss.is_sleeping()):
		return true
	var fi: Node = main.get_node_or_null("FocusedInteractionState")
	if fi != null and fi.is_active():
		return true
	return false


func open() -> void:
	is_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	show_main()


func close() -> void:
	is_open = false
	_root.visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _vbox() -> VBoxContainer:
	if _page != null:
		_page.queue_free()
	buttons.clear()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(340, 0)
	_center.add_child(v)
	_page = v
	return v


func show_main() -> void:
	var v := _vbox()
	var t := Label.new()
	t.text = tr("PAUSE_TITLE")
	t.add_theme_font_size_override("font_size", 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_button(v, "resume", tr("PAUSE_RESUME"), close)
	var sg: Node = _save_game()
	var why: String = sg.save_blocker() if sg != null else "no save system"
	_button(v, "save", tr("PAUSE_SAVE") + ("" if why == "" else "  (%s)" % why), _on_save, why != "")
	_button(v, "load", tr("MENU_LOAD"), show_load)
	_button(v, "settings", tr("MENU_SETTINGS"), show_settings)
	_button(v, "main_menu", tr("PAUSE_MAIN_MENU"), _on_main_menu)
	_button(v, "quit", tr("MENU_QUIT"), func(): get_tree().quit())
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(340, 0)
	status_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
	v.add_child(status_label)


func _button(parent: Node, id: String, text: String, cb: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	parent.add_child(b)
	buttons[id] = b
	return b


func _save_game() -> Node:
	return get_parent().get_node_or_null("SaveGame")


func _on_save() -> void:
	var r: Dictionary = _save_game().save_game()
	status_label.text = r["message"]


func show_load() -> void:
	var v := _vbox()
	var t := Label.new()
	t.text = tr("MENU_LOAD")
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	for e in _save_game().list_slots():
		var label: String = tr("SLOT_MANUAL") if e["slot"] == "manual" else tr("SLOT_AUTOSAVE")
		label += "  —  " + (tr("SLOT_DAY") % e["day"] if e["ok"] else tr("SLOT_EMPTY"))
		var path: String = e["path"]
		_button(v, "slot_" + String(e["slot"]), label, func(): _on_load(path), not e["ok"])
	_button(v, "back", tr("MENU_BACK"), show_main)
	status_label = Label.new()
	v.add_child(status_label)


func _on_load(path: String) -> void:
	var sg: Node = _save_game()
	var r: Dictionary = sg.read_save(path)
	if not r["ok"]:
		status_label.text = "Load failed: " + r["message"]
		return
	# Unpause first; the scene change itself is deferred by SaveGame.
	is_open = false
	get_tree().paused = false
	sg.load_game(path)


func show_settings() -> void:
	if _page != null:
		_page.queue_free()
	var p := SettingsPanel.new()
	p.closed.connect(show_main)
	_center.add_child(p)
	_page = p


func _on_main_menu() -> void:
	is_open = false
	get_tree().paused = false
	_to_menu.call_deferred()


func _to_menu() -> void:
	get_tree().change_scene_to_file(GameFlow.MAIN_MENU)
