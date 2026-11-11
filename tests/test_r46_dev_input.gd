extends SceneTree
## Round 46 Priority 10/30: the F8 developer panel OWNS the mouse while open
## -- in every context, without pausing.
##  - seated at the workstation (the reported bug: the workstation's _input
##    swallowed every mouse event before the GUI saw it): hover + click on a
##    panel button work, the workstation behind does not react;
##  - Esc closes only the panel (still seated);
##  - closing restores the previous control state exactly: seated stays
##    seated (no mouse-look), walking gets mouse-look back, a focused laptop
##    stays focused (no mouse-look);
##  - release builds never open it (debug-build guard).
var _ok := true
var main: Node
var panel: CanvasLayer
var lc: Node
var ws: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame
	panel = main.get_node_or_null("DevPanel")
	lc = main.get_node("Player/LookPivot")
	ws = main.get_node("WorkstationState")
	_check("developer panel exists in this debug build", panel != null)
	if panel == null:
		_finish()
		return
	panel.try_unlock(panel.UNLOCK_CODE)
	await _seated()
	await _walking()
	await _laptop()
	var src: String = FileAccess.get_file_as_string("res://scripts/dev/dev_panel.gd")
	_check("release builds never open it (debug-build guard in open())", src.find("func open() -> void:\n\tif not OS.is_debug_build():\n\t\treturn") != -1)
	_finish()


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # windowed test: hand the cursor back
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _find_button(text: String) -> Button:
	for b in panel.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree():
			return b
	return null


func _move(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	get_root().push_input(mv)
	await process_frame
	await process_frame


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		get_root().push_input(e)
		await process_frame
	await process_frame


func _key(k: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		get_root().push_input(e)
		await process_frame


## Opens the Story tab so the harmless "Variant" buttons are visible.
func _story_tab() -> void:
	var tabs: TabContainer = panel._tabs
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i).to_lower().find("story") != -1:
			tabs.current_tab = i
	await create_timer(0.3).timeout      # let the new tab lay out


func _seated() -> void:
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(0.6, 1.6, -0.4))
	await create_timer(0.2).timeout
	ws.begin_use()
	await create_timer(2.5).timeout
	_check("seated at the workstation (precondition)", ws.is_in_use() and not lc.input_enabled)
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var page0: int = int(screen.shell.page)
	await _key(KEY_F8)
	_check("F8 opens the panel while seated (no pause)", panel.is_open and not paused)
	await _story_tab()
	var b: Button = _find_button("Variant: abnormal")
	_check("a panel button is on screen", b != null)
	if b == null:
		return
	var c: Vector2 = b.get_global_rect().get_center()
	await _move(c)
	_check("hover works while seated (button under the cursor is hovered)", b.is_hovered())
	panel._variant = "normal"
	await _click(c)
	_check("click works while seated (variant -> abnormal)", panel._variant == "abnormal")
	# A click over the monitor (the middle of the screen, outside the panel)
	# must not reach the workstation behind.
	var vp_size: Vector2 = get_root().get_visible_rect().size
	await _click(Vector2(vp_size.x * 0.3, vp_size.y * 0.5))
	_check("the workstation behind does not take clicks while the panel is open", int(screen.shell.page) == page0 and ws.is_in_use())
	await _key(KEY_ESCAPE)
	_check("Esc closes only the panel (still seated)", not panel.is_open and ws.is_in_use())
	_check("...seated control restored (mouse-look stays off at the desk)", not lc.input_enabled)
	await _move(Vector2(vp_size.x * 0.3, vp_size.y * 0.5))
	_check("...and the workstation owns the mouse again", not ws._overlay_owns_mouse())
	ws.end_use()
	await create_timer(2.5).timeout


func _walking() -> void:
	_check("walking (precondition: mouse-look on)", lc.input_enabled and not ws.is_in_use())
	await _key(KEY_F8)
	_check("walking: panel open, mouse-look suspended", panel.is_open and not lc.input_enabled)
	var b: Button = _find_button("Variant: normal")
	panel._variant = "abnormal"
	if b != null:
		await _move(b.get_global_rect().get_center())
		await _click(b.get_global_rect().get_center())
	_check("walking: hover + click work", b != null and panel._variant == "normal")
	await _key(KEY_F8)
	_check("walking: closing gives mouse-look back", not panel.is_open and lc.input_enabled)


func _laptop() -> void:
	var ss: Node = main.get_node("SleepState")
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	await create_timer(0.2).timeout
	ss.begin_sitting()
	await create_timer(2.0).timeout
	ss.open_laptop(false)
	await create_timer(2.5).timeout
	ss.begin_editing()
	await create_timer(1.5).timeout
	var look0: bool = lc.input_enabled
	_check("laptop focused (precondition)", ss.is_editing())
	panel.open()
	await create_timer(0.3).timeout
	panel._variant = "normal"
	var b: Button = _find_button("Variant: abnormal")
	if b != null:
		await _move(b.get_global_rect().get_center())
		await _click(b.get_global_rect().get_center())
	_check("laptop: hover + click work", b != null and panel._variant == "abnormal" and b.is_hovered())
	panel.close()
	await process_frame
	_check("laptop: closing keeps the laptop focused, look state unchanged", ss.is_editing() and lc.input_enabled == look0)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
