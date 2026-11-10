extends Control
## Round 42 Priorities 24-27: HOLDOUT -- an ORIGINAL compact top-down
## survival game on the technician's personal laptop (Entertainment). Pure
## entertainment: its credits and upgrades are its OWN wallet and never
## touch the station's work, stock or finances.
##
## PLAY: W A S D move (only while the laptop game has keyboard focus -- the
## keys arrive through the laptop screen's own viewport, so the technician
## never walks around the station while playing). The survivor's sidearm
## fires AUTOMATICALLY at the nearest zombie in range (no aiming). Zombies
## shamble in from the arena edges in WAVES; contact hurts (per-zombie
## cooldown). Kills and cleared waves pay CREDITS.
## ENEMIES: WALKER (slow, average), RUNNER (fast, fragile, from wave 3),
## BRUTE (slow, very tough, hits hard, from wave 5); more of everything
## each wave.
## UPGRADES (persistent ranks bought in the SHOP -- from the title screen,
## between waves, after a run): FIRE RATE, DAMAGE, MULTISHOT, MAX HEALTH,
## ARMOR, SPEED, REGEN. Each rank really changes the simulation (see
## fire_interval(), damage(), ...). Costs are shown; an unaffordable or
## maxed upgrade is refused with a reason.
## SAVE: best score, credits, upgrade ranks and run count persist (the
## laptop save). An ACTIVE run is deliberately NOT persisted: a reload
## returns to the title screen (nothing half-restored).
## Original code and procedural shapes only; no external assets or music.

signal exited

const ARENA_TOP := 16.0
const PLAYER_R := 5.0
const BASE_SPEED := 62.0
const BASE_HP := 100.0
const BASE_INTERVAL := 0.62
const BASE_DAMAGE := 10.0
const RANGE := 130.0
const BULLET_SPEED := 230.0
const CONTACT_CD := 0.8
const WAVE_S := 28.0
const KINDS := {
	"walker": {"hp": 20.0, "speed": 21.0, "dmg": 8.0, "r": 5.0, "credits": 2, "color": Color(0.45, 0.72, 0.35)},
	"runner": {"hp": 11.0, "speed": 41.0, "dmg": 6.0, "r": 4.0, "credits": 3, "color": Color(0.8, 0.82, 0.3)},
	"brute": {"hp": 75.0, "speed": 13.0, "dmg": 18.0, "r": 8.0, "credits": 8, "color": Color(0.55, 0.35, 0.65)},
}
## id -> [label, max rank, [costs per rank], per-rank effect text]
const UPGRADES := {
	"rate": ["FIRE RATE", 5, [10, 20, 35, 55, 80], "-12% time between shots"],
	"damage": ["DAMAGE", 5, [12, 24, 40, 60, 90], "+25% damage"],
	"multishot": ["MULTISHOT", 3, [40, 90, 160], "+1 projectile"],
	"health": ["MAX HEALTH", 4, [15, 30, 50, 80], "+25 max health"],
	"armor": ["ARMOR", 3, [25, 50, 90], "-15% damage taken"],
	"speed": ["SPEED", 3, [15, 35, 60], "+12% move speed"],
	"regen": ["REGEN", 3, [30, 60, 100], "+1 health / s"],
}
const UPGRADE_ORDER := ["rate", "damage", "multishot", "health", "armor", "speed", "regen"]

## Persistent (saved).
var best: int = 0
var credits: int = 0
var ranks: Dictionary = {}
var runs: int = 0
## Run state.
var mode: String = "title"        # title | play | shop | paused | over
var player := Vector2.ZERO
var hp: float = BASE_HP
var wave: int = 1
var wave_t: float = 0.0
var kills: int = 0
var score: int = 0
var run_credits: int = 0
var zombies: Array = []           # {pos, hp, max, kind, cd, flash}
var bullets: Array = []           # {pos, vel, dmg, life}
var fx: Array = []                # {pos, t, col}
var shots_fired: int = 0
var damage_taken: float = 0.0
var held: Dictionary = {}
var shop_return: String = "title"
var message: String = ""
var _spawn_t: float = 0.0
var _to_spawn: int = 0
var _fire_t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _arena: Control
var _overlay: VBoxContainer
var _ov_title: Label
var _ov_text: Label
var _ov_buttons: HBoxContainer
var _shop_grid: GridContainer
var buttons: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(440, 190)
	clip_contents = true
	for id in UPGRADES:
		if not ranks.has(id):
			ranks[id] = 0
	_arena = Control.new()
	_arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.draw.connect(_draw_arena)
	add_child(_arena)
	_overlay = VBoxContainer.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_overlay)
	_ov_title = _label(_overlay, 18, Color(0.95, 0.75, 0.3))
	_ov_text = _label(_overlay, 11, Color(0.85, 0.9, 0.85))
	_shop_grid = GridContainer.new()
	_shop_grid.columns = 2
	_shop_grid.add_theme_constant_override("h_separation", 4)
	_shop_grid.add_theme_constant_override("v_separation", 2)
	_shop_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay.add_child(_shop_grid)
	for id in UPGRADE_ORDER:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 9)
		b.custom_minimum_size = Vector2(200, 18)
		b.pressed.connect(func(): buy(id))
		_shop_grid.add_child(b)
		buttons["buy_" + id] = b
	_ov_buttons = HBoxContainer.new()
	_ov_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_ov_buttons.add_theme_constant_override("separation", 6)
	_overlay.add_child(_ov_buttons)
	for spec in [["start", "START"], ["resume", "RESUME"], ["continue", "NEXT WAVE"], ["shop", "UPGRADES"], ["restart", "RESTART"], ["back", "BACK"], ["desktop", "DESKTOP"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var id: String = spec[0]
		b.pressed.connect(func(): action(id))
		_ov_buttons.add_child(b)
		buttons[id] = b
	_refresh_overlay()


func _label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	parent.add_child(l)
	return l


func arena_rect() -> Rect2:
	var s: Vector2 = size if size.x > 10.0 else Vector2(440, 190)
	return Rect2(Vector2(2, ARENA_TOP), s - Vector2(4, ARENA_TOP + 2))


# ------------------------------------------------------------ upgrades
func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func fire_interval() -> float:
	return BASE_INTERVAL * pow(0.88, rank("rate"))


func damage() -> float:
	return BASE_DAMAGE * (1.0 + 0.25 * rank("damage"))


func projectiles() -> int:
	return 1 + rank("multishot")


func max_hp() -> float:
	return BASE_HP + 25.0 * rank("health")


func armor_factor() -> float:
	return pow(0.85, rank("armor"))


func move_speed() -> float:
	return BASE_SPEED * (1.0 + 0.12 * rank("speed"))


func regen() -> float:
	return 1.0 * rank("regen")


func upgrade_cost(id: String) -> int:
	var r: int = rank(id)
	var costs: Array = UPGRADES[id][2]
	return int(costs[r]) if r < costs.size() else -1


## Buy one rank; refuses (with a reason in `message`) when maxed / poor.
func buy(id: String) -> bool:
	if not UPGRADES.has(id):
		return false
	var cost: int = upgrade_cost(id)
	if cost < 0:
		message = "%s is at max rank." % UPGRADES[id][0]
		_refresh_overlay()
		return false
	if credits < cost:
		message = "Need %d CR for %s (have %d)." % [cost, UPGRADES[id][0], credits]
		_refresh_overlay()
		return false
	credits -= cost
	ranks[id] = rank(id) + 1
	message = "%s rank %d." % [UPGRADES[id][0], rank(id)]
	_refresh_overlay()
	return true


# ---------------------------------------------------------------- flow
func action(id: String) -> void:
	match id:
		"start", "restart":
			start_run()
		"resume":
			if mode == "paused":
				mode = "play"
		"pause":
			if mode == "play":
				mode = "paused"
			elif mode == "paused":
				mode = "play"
		"continue":
			if mode == "shop" and shop_return == "wave":
				_begin_wave(wave + 1)
				mode = "play"
		"shop":
			shop_return = "wave" if (mode == "shop" and shop_return == "wave") else ("title" if mode in ["title", "over"] else shop_return)
			if mode in ["title", "over"]:
				shop_return = "title"
			mode = "shop"
			message = ""
		"back":
			if mode == "shop":
				mode = "title" if shop_return == "title" else "shop"
		"desktop":
			if mode == "play":
				mode = "paused"
			exited.emit()
	_refresh_overlay()


func start_run() -> void:
	_rng.seed = hash([Time.get_ticks_usec(), runs])
	runs += 1
	var r: Rect2 = arena_rect()
	player = r.get_center()
	hp = max_hp()
	kills = 0
	score = 0
	run_credits = 0
	shots_fired = 0
	damage_taken = 0.0
	zombies = []
	bullets = []
	fx = []
	held = {}
	message = ""
	_begin_wave(1)
	mode = "play"
	_refresh_overlay()


## Tests: a reproducible run.
func start_seeded(s: int) -> void:
	start_run()
	_rng.seed = s


func _begin_wave(n: int) -> void:
	wave = n
	wave_t = 0.0
	_to_spawn = 6 + 4 * n
	_spawn_t = 0.0


func spawn_interval() -> float:
	return maxf(0.35, 2.0 - 0.15 * wave)


func _pick_kind() -> String:
	var roll: float = _rng.randf()
	if wave >= 5 and roll < minf(0.08 + 0.02 * (wave - 5), 0.25):
		return "brute"
	if wave >= 3 and roll < 0.35:
		return "runner"
	return "walker"


## A zombie on a random arena edge, never within 60 px of the survivor.
func spawn_zombie(kind: String = "") -> Dictionary:
	var r: Rect2 = arena_rect()
	var k: String = kind if kind != "" else _pick_kind()
	var p := Vector2.ZERO
	for attempt in 12:
		var side: int = _rng.randi() % 4
		match side:
			0: p = Vector2(_rng.randf_range(r.position.x, r.end.x), r.position.y + 2)
			1: p = Vector2(_rng.randf_range(r.position.x, r.end.x), r.end.y - 2)
			2: p = Vector2(r.position.x + 2, _rng.randf_range(r.position.y, r.end.y))
			_: p = Vector2(r.end.x - 2, _rng.randf_range(r.position.y, r.end.y))
		if p.distance_to(player) >= 60.0:
			break
	var hpz: float = float(KINDS[k]["hp"]) * (1.0 + 0.08 * (wave - 1))
	var z := {"pos": p, "hp": hpz, "max": hpz, "kind": k, "cd": 0.0, "flash": 0.0}
	zombies.append(z)
	return z


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: int = event.keycode
		if k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			held[k] = event.pressed
			accept_event()
		elif event.pressed and k == KEY_P:
			action("pause")
			accept_event()
		elif event.pressed and (k == KEY_ENTER or k == KEY_SPACE):
			if mode in ["title", "over"]:
				action("start")
			elif mode == "paused":
				action("resume")
			accept_event()


func _notification(what: int) -> void:
	# Losing the laptop's focus (zoomed out, app closed) pauses the run and
	# drops every held key -- nothing keeps moving behind the technician's back.
	if what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_VISIBILITY_CHANGED:
		held = {}
		if mode == "play" and (what == NOTIFICATION_FOCUS_EXIT or not is_visible_in_tree()):
			mode = "paused"
			_refresh_overlay()


func move_dir() -> Vector2:
	var d := Vector2.ZERO
	if held.get(KEY_W, false) or held.get(KEY_UP, false): d.y -= 1.0
	if held.get(KEY_S, false) or held.get(KEY_DOWN, false): d.y += 1.0
	if held.get(KEY_A, false) or held.get(KEY_LEFT, false): d.x -= 1.0
	if held.get(KEY_D, false) or held.get(KEY_RIGHT, false): d.x += 1.0
	return d.normalized()


func _process(delta: float) -> void:
	if mode == "play" and is_visible_in_tree():
		step(minf(delta, 0.05))
	elif not fx.is_empty():
		fx = fx.filter(func(f): return float(f["t"]) > 0.0)
	_arena.queue_redraw()


## One simulation tick (also driven directly by tests).
func step(dt: float) -> void:
	if mode != "play":
		return
	var r: Rect2 = arena_rect()
	# Survivor.
	player += move_dir() * move_speed() * dt
	player.x = clampf(player.x, r.position.x + PLAYER_R, r.end.x - PLAYER_R)
	player.y = clampf(player.y, r.position.y + PLAYER_R, r.end.y - PLAYER_R)
	hp = minf(hp + regen() * dt, max_hp())
	# Spawning.
	wave_t += dt
	_spawn_t -= dt
	if _to_spawn > 0 and _spawn_t <= 0.0:
		_spawn_t = spawn_interval()
		_to_spawn -= 1
		spawn_zombie()
	# Zombies: approach, keep apart, bite on contact (with a cooldown).
	for z in zombies:
		var kd: Dictionary = KINDS[z["kind"]]
		var to: Vector2 = player - z["pos"]
		var dist: float = to.length()
		var reach: float = PLAYER_R + float(kd["r"])
		if dist > reach - 0.5:
			z["pos"] += to / maxf(dist, 0.001) * float(kd["speed"]) * dt
		z["cd"] = maxf(float(z["cd"]) - dt, 0.0)
		z["flash"] = maxf(float(z["flash"]) - dt, 0.0)
		if dist <= reach + 0.5 and float(z["cd"]) <= 0.0:
			z["cd"] = CONTACT_CD
			var d: float = float(kd["dmg"]) * armor_factor()
			hp -= d
			damage_taken += d
			fx.append({"pos": player, "t": 0.25, "col": Color(1, 0.2, 0.15)})
	_separate()
	# Auto-attack: nearest zombie in range.
	_fire_t -= dt
	if _fire_t <= 0.0:
		var target: Dictionary = nearest_zombie()
		if not target.is_empty():
			_fire_t = fire_interval()
			_fire_at(target["pos"])
	# Bullets.
	for b in bullets:
		b["pos"] += b["vel"] * dt
		b["life"] = float(b["life"]) - dt
		for z in zombies:
			if float(z["hp"]) > 0.0 and (b["pos"] as Vector2).distance_to(z["pos"]) <= float(KINDS[z["kind"]]["r"]) + 1.5:
				z["hp"] = float(z["hp"]) - float(b["dmg"])
				z["flash"] = 0.12
				b["life"] = 0.0
				fx.append({"pos": b["pos"], "t": 0.15, "col": Color(1, 0.9, 0.5)})
				break
	bullets = bullets.filter(func(b): return float(b["life"]) > 0.0 and r.grow(10).has_point(b["pos"]))
	# Deaths -> credits.
	for z in zombies:
		if float(z["hp"]) <= 0.0:
			kills += 1
			var c: int = int(KINDS[z["kind"]]["credits"])
			run_credits += c
			credits += c
			score += 10 * c
			fx.append({"pos": z["pos"], "t": 0.4, "col": KINDS[z["kind"]]["color"]})
	zombies = zombies.filter(func(z): return float(z["hp"]) > 0.0)
	for f in fx:
		f["t"] = float(f["t"]) - dt
	fx = fx.filter(func(f): return float(f["t"]) > 0.0)
	if hp <= 0.0:
		_game_over()
		return
	# Wave cleared: everything spawned and dead (or survived the timer).
	if _to_spawn == 0 and zombies.is_empty():
		var bonus: int = 5 + 2 * wave
		credits += bonus
		run_credits += bonus
		score += 50 * wave
		message = "WAVE %d CLEARED  +%d CR" % [wave, bonus]
		shop_return = "wave"
		mode = "shop"
		_refresh_overlay()


func nearest_zombie() -> Dictionary:
	var best_d: float = RANGE
	var out: Dictionary = {}
	for z in zombies:
		var d: float = player.distance_to(z["pos"])
		if d <= best_d:
			best_d = d
			out = z
	return out


func _fire_at(target: Vector2) -> void:
	var n: int = projectiles()
	var base: float = (target - player).angle()
	for i in n:
		var a: float = base + (float(i) - float(n - 1) * 0.5) * 0.18
		bullets.append({"pos": player, "vel": Vector2.from_angle(a) * BULLET_SPEED, "dmg": damage(), "life": 0.9})
	shots_fired += 1
	fx.append({"pos": player + Vector2.from_angle(base) * 7.0, "t": 0.06, "col": Color(1, 0.95, 0.6)})


## Cheap pairwise push so zombies never stack into one blob.
func _separate() -> void:
	var n: int = zombies.size()
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = zombies[i]
			var b: Dictionary = zombies[j]
			var d: Vector2 = b["pos"] - a["pos"]
			var min_d: float = float(KINDS[a["kind"]]["r"]) + float(KINDS[b["kind"]]["r"])
			var l: float = d.length()
			if l < min_d and l > 0.001:
				var push: Vector2 = d / l * (min_d - l) * 0.5
				a["pos"] -= push
				b["pos"] += push


func _game_over() -> void:
	hp = 0.0
	mode = "over"
	best = maxi(best, score)
	held = {}
	message = ""
	_refresh_overlay()


# --------------------------------------------------------------- views
func _refresh_overlay() -> void:
	if _overlay == null:
		return
	var show: Dictionary = {}
	_shop_grid.visible = mode == "shop"
	_overlay.visible = mode != "play"
	match mode:
		"title":
			_ov_title.text = "HOLDOUT"
			_ov_text.text = "Survive the waves. WASD to move — the sidearm fires by itself.\nBest %d · Credits %d CR" % [best, credits]
			show = {"start": true, "shop": true, "desktop": true}
		"paused":
			_ov_title.text = "PAUSED"
			_ov_text.text = "Wave %d · Score %d · HP %d" % [wave, score, int(hp)]
			show = {"resume": true, "restart": true, "desktop": true}
		"shop":
			_ov_title.text = "UPGRADES · %d CR" % credits
			_ov_text.text = message if message != "" else ("Spend credits before wave %d." % (wave + 1) if shop_return == "wave" else "Ranks carry over to every run.")
			show = {"continue": shop_return == "wave", "back": shop_return == "title", "desktop": true}
			for id in UPGRADE_ORDER:
				var b: Button = buttons["buy_" + id]
				var cost: int = upgrade_cost(id)
				b.text = "%s %d/%d · %s" % [UPGRADES[id][0], rank(id), UPGRADES[id][1], ("MAX" if cost < 0 else "%d CR" % cost)]
				b.disabled = cost < 0 or credits < cost
				b.tooltip_text = UPGRADES[id][3]
		"over":
			_ov_title.text = "GAME OVER"
			_ov_text.text = "Wave %d · %d kills · Score %d · Best %d\n+%d CR this run (wallet %d CR)" % [wave, kills, score, best, run_credits, credits]
			show = {"restart": true, "shop": true, "desktop": true}
	for k in ["start", "resume", "continue", "shop", "restart", "back", "desktop"]:
		(buttons[k] as Button).visible = show.get(k, false)


func _draw_arena() -> void:
	var r: Rect2 = arena_rect()
	_arena.draw_rect(Rect2(Vector2.ZERO, _arena.size), Color(0.04, 0.05, 0.05))
	_arena.draw_rect(r, Color(0.09, 0.1, 0.08))
	# A few fixed crates / debris for a sense of place (no collision).
	for i in 7:
		var p := Vector2(r.position.x + fmod(37.0 * i * i + 23.0, r.size.x - 20.0) + 10.0, r.position.y + fmod(53.0 * i + 17.0, r.size.y - 20.0) + 10.0)
		_arena.draw_rect(Rect2(p, Vector2(6, 5)), Color(0.16, 0.15, 0.12))
	_arena.draw_rect(r, Color(0.35, 0.4, 0.38), false, 1.0)
	for z in zombies:
		var kd: Dictionary = KINDS[z["kind"]]
		var c: Color = (kd["color"] as Color).lerp(Color.WHITE, 0.6 if float(z["flash"]) > 0.0 else 0.0)
		var zr: float = float(kd["r"])
		_arena.draw_circle(z["pos"], zr + 1.0, c.darkened(0.6))
		_arena.draw_circle(z["pos"], zr, c)
		var to: Vector2 = (player - (z["pos"] as Vector2)).normalized()
		_arena.draw_line(z["pos"], (z["pos"] as Vector2) + to.rotated(0.5) * (zr + 3.0), c.darkened(0.3), 1.5)
		_arena.draw_line(z["pos"], (z["pos"] as Vector2) + to.rotated(-0.5) * (zr + 3.0), c.darkened(0.3), 1.5)
		if float(z["hp"]) < float(z["max"]):
			_arena.draw_rect(Rect2((z["pos"] as Vector2) + Vector2(-zr, -zr - 4.0), Vector2(2.0 * zr * float(z["hp"]) / float(z["max"]), 1.5)), Color(0.9, 0.3, 0.2))
	for b in bullets:
		var bp: Vector2 = b["pos"]
		_arena.draw_line(bp - (b["vel"] as Vector2).normalized() * 6.0, bp, Color(1.0, 0.85, 0.35, 0.7), 1.5)
		_arena.draw_circle(bp, 2.2, Color(1.0, 0.92, 0.45))
	if mode != "title":
		_arena.draw_circle(player, PLAYER_R + 1.5, Color(0.1, 0.25, 0.4))
		_arena.draw_circle(player, PLAYER_R, Color(0.55, 0.8, 1.0))
		_arena.draw_circle(player, 2.0, Color(0.95, 0.97, 1.0))
	for f in fx:
		var t: float = float(f["t"])
		_arena.draw_circle(f["pos"], 2.0 + (0.4 - t) * 10.0, Color(f["col"], clampf(t * 3.0, 0.0, 0.8)))
	# Menus / pause / game over sit on a dimmed arena (readable text).
	if mode != "play":
		_arena.draw_rect(r, Color(0.0, 0.0, 0.0, 0.62))
	# HUD strip.
	var font: Font = ThemeDB.fallback_font
	_arena.draw_rect(Rect2(2, 2, 90, 9), Color(0.2, 0.05, 0.05))
	_arena.draw_rect(Rect2(2, 2, 90.0 * clampf(hp / max_hp(), 0.0, 1.0), 9), Color(0.85, 0.2, 0.15))
	_arena.draw_string(font, Vector2(98, 11), "HP %d   WAVE %d   SCORE %d   KILLS %d   %d CR" % [int(maxf(hp, 0.0)), wave, score, kills, credits], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.95, 0.9))


# ------------------------------------------------------------ save / load
func state_dict() -> Dictionary:
	return {"best": best, "credits": credits, "ranks": ranks.duplicate(), "runs": runs}


func load_state(d: Dictionary) -> void:
	best = maxi(int(d.get("best", 0)), 0)
	credits = maxi(int(d.get("credits", 0)), 0)
	runs = maxi(int(d.get("runs", 0)), 0)
	var rk: Dictionary = d.get("ranks", {})
	for id in UPGRADES:
		ranks[id] = clampi(int(rk.get(id, 0)), 0, int(UPGRADES[id][1]))
	# A saved game never resumes mid-run.
	mode = "title"
	zombies = []
	bullets = []
	held = {}
	_refresh_overlay()
