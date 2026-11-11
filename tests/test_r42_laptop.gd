extends SceneTree
## Round 42 Priorities 22-27: the personal laptop.
##  - Personal Log no longer cropped: the whole page (menu bar + editor)
##    fits the screen while editing, long paragraphs / unbroken lines /
##    Chinese wrap inside it;
##  - Cargo Drop: a top-out is a real GAME OVER (screen, final + best,
##    RESTART / DESKTOP; no spawning, falling or moving), restart works
##    repeatedly, a game-over board is never saved as an active run;
##  - HOLDOUT (survival game): WASD movement (only through the laptop's own
##    focused input), zombies pursue and bite with a cooldown, the sidearm
##    auto-fires and kills, credits are paid, upgrades really change the
##    simulation and are refused when unaffordable / maxed, enemy variants
##    by wave, pause on focus loss, game over + restart, persistence of
##    the wallet / ranks / best only (never a half-restored run).
var _ok := true
var main: Node
var scr: SubViewport
var hold: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	var lv: Node = main.find_child("LaptopView", true, false)
	scr = lv._log_screen
	hold = scr.holdout
	await _personal_log()
	await _cargo_drop()
	await _holdout()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _personal_log() -> void:
	scr.set_pending_app(&"log")
	scr.set_editing(true)
	scr.open_app(&"log")
	for txt in ["Short entry.", "A long paragraph about the shift, the hum of the vents and the way the corridor camera looks at night when nothing at all is moving in it. " .repeat(4), "x".repeat(400), "第一段。\n今天检查了通信设备，一切正常。\n" + "很长的中文句子没有空格".repeat(20)]:
		scr.show_entry(txt)
		for i in 3: await process_frame
		var vb: Control = scr.get_node("Control/VBox")
		var te: TextEdit = scr.get_node("Control/VBox/EntryField")
		var right: float = te.get_global_rect().end.x
		# Round 44: the screen renders at 2x; widths are in LAYOUT units.
		var lw: float = scr.layout_size().x
		_check("log editor fits the screen (%d chars): editor right edge %.0f <= %d" % [txt.length(), right, lw], vb.size.x <= lw - 20 and right <= lw - 8 and te.wrap_mode != TextEdit.LINE_WRAPPING_NONE)
	var bar: Control = scr.get_node("Control/VBox/AppBar")
	_check("menu bar (with Save / Save & Back / Close) never wider than the screen (%.0f)" % bar.get_combined_minimum_size().x, bar.get_combined_minimum_size().x <= scr.layout_size().x - 24)
	# Round 45: one close action -- CLOSE LAPTOP (notes autosave); no Save / Save & Back.
	_check("CLOSE LAPTOP stays visible while editing (Save / Save & Back retired)", scr._buttons[&"close"].visible and not scr._buttons[&"save"].visible and not scr._buttons[&"back"].visible)
	scr.set_editing(false)


func _cargo_drop() -> void:
	var g: Node = scr._game
	g.restart(99)
	# Fill the bay to the top except a hole that keeps rows from shipping.
	for r in g.ROWS:
		for c in g.COLS:
			g.grid[r][c] = 0 if c != 9 else -1
	g._spawn()
	_check("spawn blocked -> GAME OVER (not a frozen board)", g.game_over and g.over_reason != "")
	_check("game-over screen shown with final + best score", g._over.visible and g._over_text.text.find("Final score") != -1 and g._over_text.text.find("Best") != -1)
	var pos0: Vector2i = g.piece_pos
	g.action("left")
	g.action("drop")
	g._process(5.0)
	_check("during game over, play inputs do nothing", g.piece_pos == pos0 and g.game_over)
	_check("a game-over board is never saved as an active run", g.state_dict().is_empty())
	g.action("restart")
	_check("RESTART: a fresh bay, playing again", not g.game_over and not g._over.visible and g.board_valid() and g.grid.all(func(row): return row.all(func(v): return int(v) == -1)))
	# Lock-out: a load settling above the top.
	g.piece = [Vector2i(0, 0), Vector2i(0, 1)]
	g.piece_pos = Vector2i(0, -1)
	for c in g.COLS:
		g.grid[0][c] = 0 if c != 5 else -1
	g._lock()
	_check("a load locking above the bay is a top-out too", g.game_over)
	for n in 3:
		g.action("restart")
		_check("consecutive session %d starts cleanly" % (n + 1), not g.game_over and g.board_valid())
	var exited := [false]
	g.exited.connect(func(): exited[0] = true)
	g._end_game("TEST")
	(g.buttons["over_exit"] as Button).pressed.emit()
	_check("DESKTOP from the game-over screen returns to the laptop desktop", exited[0])
	g.restart()


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = down
	hold._gui_input(e)


func _holdout() -> void:
	_check("Holdout is a desktop app", scr.APPS.any(func(a): return a[0] == &"holdout"))
	scr.open_app(&"holdout")
	await process_frame
	_check("title screen first (START / UPGRADES / DESKTOP)", hold.mode == "title" and hold.buttons["start"].visible)
	hold.start_seeded(7)
	var p0: Vector2 = hold.player
	_key(KEY_D, true)
	for i in 30:
		hold.step(1.0 / 30.0)
	_key(KEY_D, false)
	var p1: Vector2 = hold.player
	for i in 10:
		hold.step(1.0 / 30.0)
	_check("D moves right (%.0f px), releasing stops" % (p1.x - p0.x), p1.x - p0.x > 40.0 and hold.player.distance_to(p1) < 0.5)
	var fb: Node3D = main.get_node("FreeMoveBody")
	var fbp: Vector3 = fb.global_position
	_key(KEY_W, true)
	for i in 10:
		hold.step(0.05)
	_key(KEY_W, false)
	await physics_frame
	_check("game WASD never moves the technician", fb.global_position.distance_to(fbp) < 0.01 and hold.player.y < p1.y)
	# Pursuit + contact damage with cooldown.
	hold.zombies = []
	var z: Dictionary = hold.spawn_zombie("walker")
	_check("zombies spawn away from the survivor (%.0f px)" % (z["pos"] as Vector2).distance_to(hold.player), (z["pos"] as Vector2).distance_to(hold.player) >= 60.0)
	var d0: float = (z["pos"] as Vector2).distance_to(hold.player)
	hold._fire_t = 999.0
	for i in 20:
		hold._fire_t = 999.0
		hold.step(0.05)
	_check("zombies pursue", hold.zombies.is_empty() or (hold.zombies[0]["pos"] as Vector2).distance_to(hold.player) < d0)
	hold.zombies = [{"pos": hold.player + Vector2(5, 0), "hp": 999.0, "max": 999.0, "kind": "walker", "cd": 0.0, "flash": 0.0}]
	var hp0: float = hold.hp
	for i in 10:
		hold._fire_t = 999.0
		hold.step(0.05)
	var bitten: float = hp0 - hold.hp
	_check("contact damage with a cooldown (%.0f HP in 0.5 s = one bite)" % bitten, bitten > 5.0 and bitten < 9.0)
	# Auto-attack kills, pays credits.
	hold.zombies = []
	hold.hp = hold.max_hp()
	hold._fire_t = 0.0
	hold.player = hold.arena_rect().get_center()
	var c0: int = hold.credits
	var zz: Dictionary = hold.spawn_zombie("walker")
	zz["pos"] = hold.player + Vector2(60, 0)
	var shots0: int = hold.shots_fired
	for i in 60:
		hold.step(0.05)
		if hold.zombies.is_empty():
			break
	_check("auto-attack fires at the nearest zombie (%d shots) and kills it" % (hold.shots_fired - shots0), hold.shots_fired > shots0 and hold.kills >= 1)
	_check("credits paid (+%d)" % (hold.credits - c0), hold.credits > c0)
	# Upgrades change the simulation; refusals.
	hold.credits = 5
	_check("unaffordable upgrade refused with a reason", not hold.buy("rate") and hold.message.find("Need") != -1)
	hold.credits = 1000
	var iv: float = hold.fire_interval()
	var dmg: float = hold.damage()
	var sp: float = hold.move_speed()
	hold.buy("rate")
	hold.buy("damage")
	hold.buy("speed")
	hold.buy("multishot")
	_check("FIRE RATE / DAMAGE / SPEED / MULTISHOT really change the run", hold.fire_interval() < iv and hold.damage() > dmg and hold.move_speed() > sp and hold.projectiles() == 2)
	for i in 6:
		hold.buy("armor")
	_check("max rank refused (%s)" % hold.message, hold.rank("armor") == 3 and hold.message.find("max") != -1)
	_check("credits spent are the GAME's own wallet (station untouched)", not main.get_node("DayPlan").has_method("holdout") and hold.credits < 1000)
	# Enemy variants by wave.
	hold.wave = 6
	var kinds: Dictionary = {}
	for i in 200:
		kinds[hold._pick_kind()] = true
	_check("later waves bring runners and brutes (%s)" % str(kinds.keys()), kinds.has("runner") and kinds.has("brute") and kinds.has("walker"))
	hold.wave = 1
	var early: Dictionary = {}
	for i in 200:
		early[hold._pick_kind()] = true
	_check("wave 1 is walkers only", early.keys() == ["walker"])
	# Wave clear -> shop -> next wave.
	hold.start_seeded(3)
	hold._to_spawn = 0
	hold.zombies = []
	hold.step(0.05)
	_check("wave cleared: bonus credits + the upgrade shop", hold.mode == "shop" and hold.message.find("CLEARED") != -1)
	hold.action("continue")
	_check("next wave starts", hold.mode == "play" and hold.wave == 2)
	# Pause on focus loss; game over; restart.
	hold._notification(Control.NOTIFICATION_FOCUS_EXIT)
	_check("losing the laptop focus pauses the run and drops held keys", hold.mode == "paused" and hold.held.is_empty())
	hold.action("resume")
	hold.hp = 1.0
	hold.zombies = [{"pos": hold.player, "hp": 999.0, "max": 999.0, "kind": "brute", "cd": 0.0, "flash": 0.0}]
	hold.step(0.05)
	_check("death -> GAME OVER screen with score / best", hold.mode == "over" and hold.best >= hold.score and hold.buttons["restart"].visible)
	hold.action("restart")
	_check("restart: a new run at full health", hold.mode == "play" and hold.hp == hold.max_hp() and hold.wave == 1)
	# Persistence: wallet / ranks / best only.
	var sd: Dictionary = hold.state_dict()
	hold.load_state({})
	hold.load_state(JSON.parse_string(JSON.stringify(sd)))
	_check("save/load keeps credits %d, ranks, best %d; never an active run" % [hold.credits, hold.best], hold.credits == int(sd["credits"]) and hold.rank("rate") == 1 and hold.best == int(sd["best"]) and hold.mode == "title")
	var sg: Node = main.get_node("SaveGame")
	var data: Dictionary = sg.collect_state()
	_check("the laptop save carries Holdout's wallet / ranks / best", data.has("laptop") and data["laptop"].has("holdout") and int(data["laptop"]["holdout"]["credits"]) == hold.credits)
	scr.open_app(&"home")


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
