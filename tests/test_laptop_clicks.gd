extends SceneTree
## Round 34 Priorities 5/6: the bunk laptop is fully usable by CLICKING.
## Sit -> look at the laptop ("Click: Open Laptop") -> click -> it opens ->
## look at the on-screen [Personal Log] button -> click -> editing (cursor
## visible) -> type -> click [Back] (with the cursor) -> click [Shift
## Report] / [Home] -> click [Close Laptop]. F/T remain optional
## shortcuts. Real InputEventMouseButton events through the viewport.
var _ok := true
var main: Node
var ss: Node
var cam: Camera3D
var lp: Node3D
var player: Node3D

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	ss = main.get_node("SleepState")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	cam = lp.get_node("PitchPivot/Camera3D")
	var lv: Node = player.get_node("LaptopView")
	var lap: Node3D = lv._laptop
	var screen: SubViewport = lv._log_screen
	var prompt: Label = player.get_node("HUD/PromptLabel")
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	for i in 5: await physics_frame
	ss.begin_sitting()
	await create_timer(1.6).timeout
	_check("seated on the bunk", ss.is_sitting() and not ss.is_laptop_open())

	# ---- Look at the laptop: hover prompt, click opens it. ----
	await _aim(lap.global_position + Vector3(0, 0.02, 0))
	_check("looking at the laptop shows 'Click: Open Laptop' ('%s')" % prompt.text, ss.laptop_hovered and prompt.text.begins_with("Click: Open Laptop"))
	await _click()
	_check("a click on the laptop opens it (no F needed)", ss.is_laptop_open())
	await create_timer(1.8).timeout
	# ---- Round 39: the click picks the laptop up AND zooms in on its
	# DESKTOP (a proper close-up), not on an app.
	_check("Round 39: the click zooms in on the laptop's desktop (home)", ss.is_editing() and screen.current_view() == &"home" and screen.is_zoomed())
	_check("Round 39: desktop shows icons + today note, no log text", screen._home.visible and not screen._entry_field.visible and screen._note.text.find("DAY") != -1)
	await create_timer(0.6).timeout
	# Round 44: the Personal Log lives in JOURNAL > Notes (private notes).
	await _cursor_click(screen, lap, screen.button(&"journal"))
	await _cursor_click(screen, lap, screen.button(&"journal_notes"))
	_check("clicking Journal > Notes opens the zoomed private-notes editor", ss.is_editing() and screen.current_view() == &"log")
	await create_timer(0.6).timeout
	await _cursor_click(screen, lap, screen.button(&"back"))
	_check("[Save & Back] returns to the desktop", ss.is_laptop_open() and not ss.is_editing())
	await create_timer(0.6).timeout
	# Round 39: clicking the open screen anywhere (not on an icon) zooms in.
	for i in 3:
		await _aim(lap.screen_point(Vector2(0.3, 0.93), cam.global_transform.basis.x))
	await _click()
	_check("Round 39: clicking the open screen (no icon) zooms in on the desktop", ss.is_editing() and screen.current_view() == &"home")
	await create_timer(0.6).timeout
	await _cursor_click(screen, lap, screen.button(&"back"))
	_check("...and [Save & Back] zooms out again", ss.is_laptop_open() and not ss.is_editing())
	await create_timer(0.4).timeout

	# ---- Click the on-screen Personal Log button. ----
	await _aim_at_button(screen, lap, screen.button(&"journal"))
	await _click()
	await create_timer(0.6).timeout
	await _cursor_click(screen, lap, screen.button(&"journal_notes"))
	_check("clicking [Journal] then [Notes] on the screen opens the editor (no T needed)", ss.is_editing() and screen.current_view() == &"log")
	_check("...with a visible cursor for the on-screen buttons", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	for k in [KEY_H, KEY_I]:
		var e := InputEventKey.new()
		e.keycode = k; e.physical_keycode = k; e.unicode = 104 if k == KEY_H else 105; e.pressed = true
		get_root().push_input(e)
		await process_frame
	_check("typing goes into the log", screen.get_entry_text().ends_with("hi"))
	await create_timer(0.6).timeout   # editor zoom settles
	await _cursor_click(screen, lap, screen.button(&"back"))
	_check("clicking [Back] (with the cursor) returns to the laptop desktop", ss.is_laptop_open() and not ss.is_editing())
	_check("...and the entry was kept", lv._saved_entry.ends_with("hi"))
	await create_timer(0.4).timeout

	# ---- TODAY app (Round 44: replaces Schedule / Shift Report on the
	# desktop), Home, Close Laptop. ----
	await _aim_at_button(screen, lap, screen.button(&"note"))
	await _click()
	_check("clicking [Today] zooms in on the live day (status + work %%)", ss.is_editing() and screen.current_view() == &"note" and screen.get_node("Control/VBox/ReportView").text.find("WORK") != -1)
	await create_timer(0.6).timeout
	await _cursor_click(screen, lap, screen.button(&"home"))
	_check("zoomed: clicking [< Desktop] returns to the desktop, still zoomed", screen.current_view() == &"home" and ss.is_editing())
	await _cursor_click(screen, lap, screen.button(&"messages"))
	_check("zoomed: switch app without leaving the laptop (Messages)", screen.current_view() == &"messages" and ss.is_editing())
	await _cursor_click(screen, lap, screen.button(&"close"))
	_check("clicking [Close Laptop] closes it", not ss.is_laptop_open() and ss.is_sitting())

	# ---- F / T stay optional shortcuts. ----
	await _key(KEY_F)
	await create_timer(1.0).timeout
	_check("F still opens the laptop", ss.is_laptop_open())
	await _key(KEY_T)
	_check("T still opens the editor", ss.is_editing())
	await _key(KEY_ESCAPE)
	await _key(KEY_F)
	_check("Esc + F close it again", not ss.is_laptop_open())

	# ---- A click while seated but NOT on the laptop does nothing. ----
	await _aim(cam.global_position + Vector3(0, 1.0, 0))
	await _click()
	_check("a click away from the laptop does not open it", not ss.is_laptop_open())
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _aim(p: Vector3) -> void:
	var d: Vector3 = p - cam.global_position
	var yaw: float = atan2(-d.x, -d.z) - player.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	ss._kill_laptop_aim_tween()
	lp.focus_assist_enabled = false
	lp.rotation.y = yaw
	lp._target_yaw = yaw
	lp.get_node("PitchPivot").rotation.x = pitch
	lp._target_pitch = pitch
	for i in 3: await process_frame
	ss._process(0.0)


func _aim_at_button(screen: SubViewport, lap: Node3D, b: Control) -> void:
	# A couple of iterations: aiming moves the camera slightly (head follow).
	for i in 3:
		await _aim(lap.screen_point(screen.uv_of(b), cam.global_transform.basis.x))


func _cursor_click(screen: SubViewport, lap: Node3D, b: Control) -> void:
	var world: Vector3 = lap.screen_point(screen.uv_of(b), cam.global_transform.basis.x)
	# Round 37: unproject_position() gives VIEWPORT coordinates; a pushed
	# event is in WINDOW coordinates. With canvas_items stretch these differ
	# (headless window 64x64 -> 1152-unit view), so map through the root's
	# final transform, exactly as the OS cursor position relates to the view.
	var px: Vector2 = get_root().get_final_transform() * cam.unproject_position(world)
	var mv := InputEventMouseMotion.new()
	mv.position = px
	mv.global_position = px
	get_root().push_input(mv)
	await process_frame
	await _click(px)


func _click(pos: Vector2 = Vector2.ZERO) -> void:
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
	var e := InputEventKey.new()
	e.keycode = k; e.physical_keycode = k; e.pressed = true
	get_root().push_input(e)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = k; u.physical_keycode = k; u.pressed = false
	get_root().push_input(u)
	await process_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
