extends SceneTree
## Round 47 Priority 31: the Messages scrollbar behaves like a normal
## control. REAL mouse events (Input.parse_input_event at window
## coordinates) go through the game's actual input path: the main window ->
## the seated technician (sleep_state) -> the 3D laptop screen mapping ->
## the laptop's SubViewport. Checked: press on the thumb + drag moves the
## content proportionally, release stops it at once (no continued
## scrolling), wheel scrolls, the thumb reflects the position, a drag that
## leaves the screen is still released, no reply is sent while dragging,
## nothing scrolls once Messages is closed.
## Runs WINDOWED: GUI mouse delivery does not exist in headless mode.
var _ok := true
var main: Node
var dp: Node
var se: Node
var ss: Node
var scr: Node
var fb: Node
var cam: Camera3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	DisplayServer.window_set_size(Vector2i(1280, 720))
	dp = main.get_node("DayPlan")
	se = main.get_node("StoryEvents")
	ss = main.get_node("SleepState")
	fb = main.get_node("FreeMoveBody")
	scr = main.get_node("Player/LaptopView")._log_screen
	main.get_node("StationAI").set_enabled(false)
	await _open_laptop()
	await _scroll()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _open_laptop() -> void:
	fb.sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	for i in 5: await physics_frame
	ss.begin_sitting()
	await _wait(1.8)
	ss.open_laptop(true)
	await _wait(2.6)
	if ss.has_method("begin_editing") and not ss.is_laptop_open():
		ss.begin_editing()
	cam = main.get_viewport().get_camera_3d()
	_check("seated with the laptop open in focused use", ss._state == ss.State.EDITING)


## Window coordinates of a point given in the laptop SubViewport's pixels.
func _win(p: Vector2) -> Vector2:
	var lap: Node = ss._laptop_node()
	# Control rects are in the screen's LAYOUT space (see uv_of()).
	var uv: Vector2 = p / scr.layout_size()
	var wp: Vector3 = lap.screen_point(uv, cam.global_transform.basis.x)
	# Viewport coordinates -> WINDOW coordinates (what a real mouse event
	# carries; the window may be larger than the base viewport).
	return get_root().get_final_transform() * cam.unproject_position(wp)


func _mouse_button(p: Vector2, pressed: bool, idx: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if (pressed and idx == MOUSE_BUTTON_LEFT) else 0
	e.factor = 1.0
	Input.parse_input_event(e)
	await process_frame
	await process_frame


func _mouse_move(p: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(e)
	await process_frame
	await process_frame


func _scroll() -> void:
	var fm: Node = se.family
	dp.day_number = 4
	scr.open_app(&"messages")
	var contacts: Array = fm.contacts_available()
	_check("a conversation is available (%s)" % str(contacts), not contacts.is_empty())
	scr.open_contact(contacts[0])
	# A long history (many exchanged lines) in the conversation view.
	var lines: Array = []
	for i in 60:
		lines.append("Day %d — a long letter line number %d, keeping the thread long enough to scroll." % [1 + i / 6, i])
	scr._mail_text.text = scr._mail_text.text + "\n" + "\n".join(lines)
	await process_frame
	await process_frame
	var sc: ScrollContainer = scr._mail_scroll
	sc.scroll_vertical = 0
	await process_frame
	var bar: VScrollBar = sc.get_v_scroll_bar()
	var maxv: float = bar.max_value - bar.page
	_check("long history: the bar can scroll (range %.0f px)" % maxv, bar.visible and maxv > 100.0)
	var replies0: int = fm.state_dict().hash()
	var r: Rect2 = bar.get_global_rect()
	var thumb_h: float = maxf(r.size.y * bar.page / bar.max_value, 12.0)
	var grab := Vector2(r.get_center().x, r.position.y + thumb_h * 0.5)
	# Wheel first.
	var p0: Vector2 = _win(sc.get_global_rect().get_center())
	await _mouse_move(p0, false)
	await _mouse_button(p0, true, MOUSE_BUTTON_WHEEL_DOWN)
	await _mouse_button(p0, false, MOUSE_BUTTON_WHEEL_DOWN)
	var after_wheel: int = sc.scroll_vertical
	_check("mouse wheel scrolls (%d px)" % after_wheel, after_wheel > 0)
	sc.scroll_vertical = 0
	await process_frame
	# Drag the thumb to the middle.
	await _mouse_move(_win(grab), false)
	await _mouse_button(_win(grab), true)
	var target_y: float = r.position.y + (r.size.y - thumb_h) * 0.5 + thumb_h * 0.5
	for k in range(1, 11):
		await _mouse_move(_win(Vector2(grab.x, lerpf(grab.y, target_y, k / 10.0))), true)
	var mid: int = sc.scroll_vertical
	_check("dragging the thumb moves the content (%d px of %.0f)" % [mid, maxv], mid > maxv * 0.3 and mid < maxv * 0.7)
	_check("the thumb tracks the position (value %.0f)" % bar.value, absf(bar.value - float(mid)) < 1.0)
	await _mouse_button(_win(Vector2(grab.x, target_y)), false)
	var at_release: int = sc.scroll_vertical
	for k in 6:
		await _mouse_move(_win(Vector2(grab.x, target_y + 20.0 + k * 15.0)), false)
	await _wait(0.4)
	_check("released: it stops at once, no continued scrolling (%d -> %d)" % [at_release, sc.scroll_vertical], sc.scroll_vertical == at_release and not scr.pointer_held())
	# Drag to the bottom, leaving the screen, release off-screen.
	var mid_thumb_y: float = r.position.y + (r.size.y - thumb_h) * (float(sc.scroll_vertical) / maxv) + thumb_h * 0.5
	await _mouse_move(_win(Vector2(grab.x, mid_thumb_y)), false)
	await _mouse_button(_win(Vector2(grab.x, mid_thumb_y)), true)
	for k in range(1, 9):
		await _mouse_move(_win(Vector2(grab.x, mid_thumb_y + k * 60.0)), true)
	_check("dragged to the bottom (%d of %.0f)" % [sc.scroll_vertical, maxv], float(sc.scroll_vertical) >= maxv - 2.0)
	await _mouse_button(_win(Vector2(grab.x, scr.layout_size().y + 80.0)), false)
	_check("a release off the screen still ends the drag", not scr.pointer_held())
	_check("no reply was sent while scrolling", fm.state_dict().hash() == replies0)
	# Closed app: the wheel does nothing to it.
	var v0: int = sc.scroll_vertical
	scr.open_app(&"home")
	await process_frame
	await _mouse_button(p0, true, MOUSE_BUTTON_WHEEL_UP)
	await _mouse_button(p0, false, MOUSE_BUTTON_WHEEL_UP)
	_check("Messages closed: no scrolling", sc.scroll_vertical == v0)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
