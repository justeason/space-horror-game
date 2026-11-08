extends SceneTree
## Round 37 Priority 1: the pause menu (and main menu / settings) scale
## with the window. Root cause: no stretch mode -- every screen-space
## Control kept its pixel size, so at 1920x1080 / 4K / Retina fullscreen
## the 340 px pause panel and 16 px buttons became tiny. Now the project
## stretches canvas items (1152x648 base, aspect "expand") and an
## "Interface scale" setting multiplies that.
## Verified here: the panel keeps the same fraction of the screen at
## 1152x648, 1920x1080, 2560x1440 and 3840x2160; every button lies inside
## the window; a click at a button's real on-screen position (through the
## final stretch transform) presses THAT button; the UI-scale setting
## changes the factor live.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true


func _init() -> void:
	_check("project stretch mode = canvas_items", ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items")
	_check("project stretch aspect = expand", ProjectSettings.get_setting("display/window/stretch/aspect") == "expand")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	var pm: Node = main.get_node("PauseMenu")
	pm.open()
	for i in 3: await process_frame
	var fractions: Array = []
	for res in [Vector2i(1152, 648), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		get_root().size = res
		for i in 4: await process_frame
		var panel: Control = _panel(pm)
		var r: Rect2 = panel.get_global_rect()
		var screen_r: Rect2 = Rect2(get_root().get_final_transform() * r.position, get_root().get_final_transform().basis_xform(r.size))
		var frac: float = screen_r.size.y / float(res.y)
		fractions.append(frac)
		var inside := true
		for b in _buttons(pm):
			var br: Rect2 = b.get_global_rect()
			var sp: Vector2 = get_root().get_final_transform() * br.get_center()
			inside = inside and sp.x > 0 and sp.y > 0 and sp.x < res.x and sp.y < res.y
		_check("%dx%d: pause panel is %.0f %% of the screen height; all buttons on-screen" % [res.x, res.y, frac * 100.0], inside and frac > 0.2)
		var font_px: float = get_root().get_final_transform().get_scale().y * 16.0
		_check("%dx%d: button text renders at %.0f px (>= 16)" % [res.x, res.y, font_px], font_px >= 15.9)
	_check("the panel keeps the SAME screen fraction at every resolution (%s)" % str(fractions.map(func(f): return snappedf(f, 0.01))), absf(float(fractions.max()) - float(fractions.min())) < 0.02)
	# A click at a button's real window position presses that button.
	get_root().size = Vector2i(1920, 1080)
	for i in 3: await process_frame
	var target: Button = null
	for b in _buttons(pm):
		if b.visible and b.text.to_lower().find("resume") != -1:
			target = b
	if target == null:
		target = _buttons(pm)[0]
	var pressed := [false]
	target.pressed.connect(func(): pressed[0] = true)
	var wp: Vector2 = get_root().get_final_transform() * target.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = wp
	ev.global_position = wp
	ev.pressed = true
	Input.parse_input_event(ev)
	var up: InputEventMouseButton = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	for i in 3: await process_frame
	_check("a click at '%s''s on-screen position (1920x1080) presses it" % target.text, pressed[0])
	# Interface scale setting.
	var f0: float = get_root().content_scale_factor
	GS.set_value("ui_scale", 1.3)
	_check("Interface scale 130 %% -> content scale factor %.2f" % get_root().content_scale_factor, absf(get_root().content_scale_factor - 1.3) < 0.01)
	GS.set_value("ui_scale", 1.0)
	_check("back to 100 %", absf(get_root().content_scale_factor - 1.0) < 0.01 and f0 > 0.0)
	# Settings panel: scrollable, Back always visible.
	var sp = preload("res://scripts/ui/settings_panel.gd").new()
	get_root().add_child(sp)
	await process_frame
	await process_frame
	var back_r: Rect2 = sp.back_button.get_global_rect()
	_check("settings panel: Back button inside the 1152x648 base view (y %.0f)" % back_r.end.y, back_r.end.y <= get_root().get_visible_rect().size.y)
	_check("settings panel has the UI-scale and steady-warning controls", sp.ui_scale_option != null and sp.steady_check != null)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _panel(pm: Node) -> Control:
	for c in pm.find_children("*", "PanelContainer", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return pm.find_children("*", "VBoxContainer", true, false)[0]


func _buttons(pm: Node) -> Array:
	return pm.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree())


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
