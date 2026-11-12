extends PanelContainer
## Round 34 Priority 9: the shared SETTINGS screen (main menu and pause
## menu). Every control writes GameSettings, which persists to
## user://game_settings.cfg (independent of game saves) and applies the
## value immediately: real audio-bus volumes, window mode/size, mouse
## sensitivity/inversion, and the language (localized labels refresh live).
## Gameplay difficulty stays where it was (the Control Room workstation).

signal closed

const GS = preload("res://scripts/station/game_settings.gd")
const L10N = preload("res://scripts/ui/localization.gd")

var _box: VBoxContainer
var _outer: VBoxContainer
var sliders := {}        # bus -> HSlider (tests)
var fullscreen_check: CheckBox
var size_option: OptionButton
var sens_slider: HSlider
var invert_check: CheckBox
var reduce_check: CheckBox
var brightness_slider: HSlider
var thought_volume_slider: HSlider
var thought_source_label: Label
var language_option: OptionButton
var back_button: Button
var ai_checks := {}
var ui_scale_option: OptionButton   # Round 37
var steady_check: CheckBox      # Round 36: assistant settings (tests)


func _ready() -> void:
	L10N.setup()
	custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.09, 0.96)
	sb.border_color = Color(0.3, 0.38, 0.42)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	# Round 37: the list scrolls inside a fixed-height area (it no longer
	# fits the 648-pixel base height); Back stays visible below it.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 470)
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	_outer = outer
	_title("MENU_SETTINGS", 22)
	_title("SET_AUDIO", 15)
	for b in GS.AUDIO_BUSES:
		var row := _row("SET_VOL_%s" % b)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(220, 0)
		s.value = float(GS.get_value("vol_%s" % b))
		var key: String = "vol_%s" % b
		s.value_changed.connect(func(v): GS.set_value(key, v))
		row.add_child(s)
		sliders[b] = s
	_title("SET_DISPLAY", 15)
	var r1 := _row("SET_FULLSCREEN")
	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "On"
	fullscreen_check.button_pressed = bool(GS.get_value("fullscreen"))
	fullscreen_check.toggled.connect(func(on): GS.set_value("fullscreen", on))
	r1.add_child(fullscreen_check)
	var r2 := _row("SET_WINDOW_SIZE")
	size_option = OptionButton.new()
	for sz in GS.WINDOW_SIZES:
		size_option.add_item("%d × %d" % [sz.x, sz.y])
	size_option.selected = int(GS.get_value("window_size"))
	size_option.item_selected.connect(func(i): GS.set_value("window_size", i))
	r2.add_child(size_option)
	var r7 := _row("SET_UI_SCALE")
	ui_scale_option = OptionButton.new()
	for f in GS.UI_SCALES:
		ui_scale_option.add_item("%d %%" % roundi(f * 100.0))
	ui_scale_option.selected = maxi(GS.UI_SCALES.find(float(GS.get_value("ui_scale"))), 2)
	ui_scale_option.item_selected.connect(func(i): GS.set_value("ui_scale", GS.UI_SCALES[i]))
	r7.add_child(ui_scale_option)
	var r8 := _row("SET_STEADY_WARN")
	steady_check = CheckBox.new()
	steady_check.text = "On"
	steady_check.button_pressed = bool(GS.get_value("steady_warnings"))
	steady_check.toggled.connect(func(on): GS.set_value("steady_warnings", on))
	r8.add_child(steady_check)
	_title("SET_INPUT", 15)
	var r3 := _row("SET_SENS")
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.2
	sens_slider.max_value = 3.0
	sens_slider.step = 0.1
	sens_slider.custom_minimum_size = Vector2(220, 0)
	sens_slider.value = float(GS.get_value("mouse_sensitivity"))
	sens_slider.value_changed.connect(func(v): GS.set_value("mouse_sensitivity", v))
	r3.add_child(sens_slider)
	var r4 := _row("SET_INVERT")
	invert_check = CheckBox.new()
	invert_check.text = "On"
	invert_check.button_pressed = bool(GS.get_value("invert_y"))
	invert_check.toggled.connect(func(on): GS.set_value("invert_y", on))
	r4.add_child(invert_check)
	var rb := _row("SET_BRIGHTNESS")
	var bs := HSlider.new()
	bs.min_value = 0.7
	bs.max_value = 1.4
	bs.step = 0.05
	bs.custom_minimum_size = Vector2(220, 0)
	bs.value = float(GS.get_value("brightness"))
	bs.value_changed.connect(func(v): GS.set_value("brightness", v))
	rb.add_child(bs)
	brightness_slider = bs
	var r6 := _row("SET_REDUCE_FX")
	reduce_check = CheckBox.new()
	reduce_check.text = "On"
	reduce_check.button_pressed = bool(GS.get_value("reduce_effects"))
	reduce_check.toggled.connect(func(on): GS.set_value("reduce_effects", on))
	r6.add_child(reduce_check)
	_title("SET_AI", 15)
	for key in ["ai_guidance", "ai_voice", "ai_captions"]:
		var ar := _row("SET_" + key.to_upper())
		var cb := CheckBox.new()
		cb.text = "On"
		cb.button_pressed = bool(GS.get_value(key))
		var k: String = key
		cb.toggled.connect(func(on): GS.set_value(k, on))
		ar.add_child(cb)
		ai_checks[key] = cb
	for key in ["thought_voice", "thought_captions"]:
		var tr_row := _row("SET_" + key.to_upper())
		var tcb := CheckBox.new()
		tcb.text = "On"
		tcb.button_pressed = bool(GS.get_value(key))
		var tk: String = key
		tcb.toggled.connect(func(on): GS.set_value(tk, on))
		tr_row.add_child(tcb)
		ai_checks[key] = tcb
	# Round 48: the inner voice's own volume, and WHAT will be heard.
	var tv_row := _row("SET_THOUGHT_VOLUME")
	thought_volume_slider = HSlider.new()
	thought_volume_slider.min_value = 0.0
	thought_volume_slider.max_value = 1.0
	thought_volume_slider.step = 0.05
	thought_volume_slider.custom_minimum_size = Vector2(220, 0)
	thought_volume_slider.value = float(GS.get_value("thought_volume"))
	thought_volume_slider.value_changed.connect(func(v): GS.set_value("thought_volume", v))
	tv_row.add_child(thought_volume_slider)
	var src_row := _row("SET_THOUGHT_SOURCE")
	thought_source_label = Label.new()
	thought_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thought_source_label.custom_minimum_size = Vector2(300, 0)
	thought_source_label.add_theme_font_size_override("font_size", 12)
	var iv: Node = get_tree().get_first_node_in_group(&"inner_voice") if is_inside_tree() else null
	if iv == null:
		iv = load("res://scripts/story/inner_voice.gd").new()
		thought_source_label.text = iv.backend_summary()
		iv.free()
	else:
		thought_source_label.text = iv.backend_summary()
	src_row.add_child(thought_source_label)
	var controls := Label.new()
	controls.text = tr("SET_CONTROLS") + ": " + tr("CONTROLS_TEXT")
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size = Vector2(520, 0)
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color(0.65, 0.72, 0.7))
	_box.add_child(controls)
	_title("SET_LANGUAGE", 15)
	var r5 := _row("SET_LANGUAGE")
	language_option = OptionButton.new()
	for loc in GS.LANGUAGES:
		language_option.add_item(L10N.LANGUAGE_NAMES[loc])
	language_option.selected = maxi(GS.LANGUAGES.find(String(GS.get_value("language"))), 0)
	language_option.item_selected.connect(_on_language)
	r5.add_child(language_option)
	back_button = Button.new()
	back_button.text = tr("MENU_BACK")
	back_button.custom_minimum_size = Vector2(0, 36)
	back_button.pressed.connect(func(): closed.emit())
	_outer.add_child(back_button)


func _on_language(i: int) -> void:
	GS.set_value("language", GS.LANGUAGES[i])
	_build.call_deferred()   # labels re-translate


func _title(key: String, size: int) -> void:
	var l := Label.new()
	l.text = tr(key)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0) if size > 18 else Color(0.85, 0.75, 0.45))
	_box.add_child(l)


func _row(key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = tr(key)
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	_box.add_child(h)
	return h
