extends Control
## HOLDOUT -- an ORIGINAL top-down survival roguelike on the technician's
## personal laptop (Entertainment). Pure entertainment: its credits,
## weapons and upgrades are its OWN wallet and never touch the station's
## work, stock or finances.
##
## Round 42 built the first arena game. Round 43 Priorities 2-5 make it a
## real miniature roguelike:
##
## WORLD: a SCROLLING town map (WORLD, far larger than the screen) with a
## camera that follows the survivor. Roads with lane markings, parked
## cars, barricades, a fenced park with trees, small buildings, broken
## streetlights and SUPPLY points; named LANDMARKS (MOTEL, PHARMACY, FUEL
## STOP, CHAPEL, BUS DEPOT, DINER, PARK) and a small MINIMAP. Collision is
## cheap circle-vs-rect / circle-vs-circle push-out against static
## obstacles (no physics engine); bullets stop at solid obstacles.
## Zombies steer around buildings via the nearest free corner of whatever
## blocks the straight line.
##
## ENEMIES (each with its own look AND behaviour, unlocked by wave):
##   WALKER  (w1)  slow, average health, basic bite;
##   SWARM   (w2)  tiny, weak, quick, arrives in packs of 5-7;
##   RUNNER  (w3)  fast, fragile, LUNGES when close;
##   SPITTER (w4)  keeps its distance, telegraphs (glow) then lobs a slow,
##                 dodgeable acid glob;
##   BRUTE   (w5)  slow, huge health, heavy hit with knock-back;
##   BLOATER (w6)  swells and bursts after a visible fuse (hurts zombies too);
##   ARMORED (w7)  plated: only RIFLE / ARC hits do full damage;
##   ELITE   (every 5th wave) a gold-ringed boss that drops a scrap cache.
## Every bite has a per-enemy cooldown; spit and blasts are telegraphed --
## no unavoidable damage.
##
## WEAPONS (one equipped, chosen in the ARMORY; all AUTO-AIM / AUTO-FIRE):
##   PISTOL reliable starter;  SMG fast, light, sprays;  SHOTGUN pellets
##   in a cone, short range;  RIFLE slow, heavy, pierces and cracks
##   armour;  ARC COIL an energy bolt that CHAINS between nearby zombies.
##
## UPGRADES (persistent ranks, real effects -- see the stat functions):
##   FIRE RATE, DAMAGE, MULTISHOT, MAX HEALTH, ARMOR, SPEED, REGEN,
##   MAGNET (pickup radius: scrap + medkits must be collected), CRIT.
## CREDITS: kills, cleared waves, milestones (waves 5/10/15/20), scrap.
## LOOP: start -> survive -> clear a wave -> armory (upgrades / weapons)
## -> next wave ... -> die -> summary (wave, kills, score, best) -> restart.
## SAVE: best score, best wave, credits, ranks, unlocked + equipped weapon
## and run count persist; an ACTIVE run deliberately does not (a reload
## returns to the title screen, nothing half-restored).
## INPUT: W A S D / arrows only while the laptop game has keyboard focus --
## the technician never walks around the station while playing.
## Original code and procedural shapes only; no external assets.

signal exited

const WORLD := Rect2(0, 0, 1800, 1200)
const START := Vector2(900, 600)            # the central plaza (always clear)
const HUD_H := 14.0
const PLAYER_R := 5.0
const BASE_SPEED := 62.0
const BASE_HP := 100.0
const BASE_INTERVAL := 0.62                  # pistol (Round 42 API)
const BASE_DAMAGE := 10.0
const RANGE := 140.0
const BULLET_SPEED := 260.0
const CONTACT_CD := 0.8
const MAX_ALIVE := 70
const BASE_MAGNET := 22.0
const ZOOM := 1.6                            # screen px per world px (readable sprites)

const KINDS := {
	"walker": {"hp": 20.0, "speed": 21.0, "dmg": 8.0, "r": 5.0, "credits": 2, "color": Color(0.45, 0.72, 0.35), "wave": 1},
	"swarm": {"hp": 5.0, "speed": 36.0, "dmg": 3.0, "r": 2.6, "credits": 1, "color": Color(0.62, 0.78, 0.5), "wave": 2},
	"runner": {"hp": 11.0, "speed": 41.0, "dmg": 6.0, "r": 4.0, "credits": 3, "color": Color(0.8, 0.82, 0.3), "wave": 3},
	"spitter": {"hp": 16.0, "speed": 19.0, "dmg": 4.0, "r": 5.0, "credits": 5, "color": Color(0.35, 0.75, 0.7), "wave": 4},
	"brute": {"hp": 75.0, "speed": 13.0, "dmg": 18.0, "r": 8.0, "credits": 8, "color": Color(0.55, 0.35, 0.65), "wave": 5},
	"bloater": {"hp": 26.0, "speed": 15.0, "dmg": 0.0, "r": 7.0, "credits": 6, "color": Color(0.75, 0.55, 0.4), "wave": 6},
	"armored": {"hp": 40.0, "speed": 17.0, "dmg": 10.0, "r": 6.0, "credits": 7, "color": Color(0.55, 0.6, 0.65), "wave": 7},
	"elite": {"hp": 380.0, "speed": 15.0, "dmg": 24.0, "r": 11.0, "credits": 30, "color": Color(0.7, 0.3, 0.3), "wave": 5},
}
const SPIT_RANGE := Vector2(85.0, 135.0)
const SPIT_CD := 2.6
const SPIT_WINDUP := 0.55
const SPIT_SPEED := 72.0
const SPIT_DMG := 9.0
const FUSE_S := 0.85
const BLAST_R := 34.0
const BLAST_DMG := 16.0

## id -> stats: interval s, dmg per hit, range px, speed px/s, pellets,
## spread rad (cone / jitter), pierce (extra targets), ap (armour piercing), cost.
const WEAPONS := {
	"pistol": {"name": "PISTOL", "interval": 0.62, "dmg": 10.0, "range": 140.0, "speed": 260.0, "pellets": 1, "spread": 0.0, "pierce": 0, "ap": false, "cost": 0, "color": Color(1.0, 0.92, 0.45)},
	"smg": {"name": "SMG", "interval": 0.17, "dmg": 4.5, "range": 120.0, "speed": 290.0, "pellets": 1, "spread": 0.14, "pierce": 0, "ap": false, "cost": 60, "color": Color(1.0, 0.75, 0.35)},
	"shotgun": {"name": "SHOTGUN", "interval": 0.95, "dmg": 6.0, "range": 85.0, "speed": 240.0, "pellets": 6, "spread": 0.55, "pierce": 0, "ap": false, "cost": 90, "color": Color(1.0, 0.6, 0.3)},
	"rifle": {"name": "RIFLE", "interval": 1.1, "dmg": 34.0, "range": 230.0, "speed": 430.0, "pellets": 1, "spread": 0.0, "pierce": 3, "ap": true, "cost": 140, "color": Color(0.85, 0.95, 1.0)},
	"arc": {"name": "ARC COIL", "interval": 0.8, "dmg": 13.0, "range": 150.0, "speed": 0.0, "pellets": 1, "spread": 0.0, "pierce": 3, "ap": true, "cost": 260, "color": Color(0.55, 0.85, 1.0)},
}
const WEAPON_ORDER := ["pistol", "smg", "shotgun", "rifle", "arc"]
const ARC_JUMP := 62.0

## id -> [label, max rank, [costs per rank], per-rank effect text]
const UPGRADES := {
	"rate": ["FIRE RATE", 5, [10, 20, 35, 55, 80], "-12% time between shots"],
	"damage": ["DAMAGE", 5, [12, 24, 40, 60, 90], "+25% damage"],
	"multishot": ["MULTISHOT", 3, [40, 90, 160], "+1 projectile"],
	"health": ["MAX HEALTH", 4, [15, 30, 50, 80], "+25 max health"],
	"armor": ["ARMOR", 3, [25, 50, 90], "-15% damage taken"],
	"speed": ["SPEED", 3, [15, 35, 60], "+12% move speed"],
	"regen": ["REGEN", 3, [30, 60, 100], "+1 health / s"],
	"magnet": ["MAGNET", 3, [15, 30, 55], "+14 px pickup radius"],
	"crit": ["CRIT", 4, [20, 40, 70, 110], "+8% chance of x2 damage"],
}
const UPGRADE_ORDER := ["rate", "damage", "multishot", "health", "armor", "speed", "regen", "magnet", "crit"]
const MILESTONES := {5: 25, 10: 60, 15: 120, 20: 200}

## Persistent (saved).
var best: int = 0
var best_wave: int = 0
var credits: int = 0
var ranks: Dictionary = {}
var runs: int = 0
var unlocked: Dictionary = {"pistol": true}
var weapon: String = "pistol"
## Run state.
var mode: String = "title"        # title | play | shop | paused | over
var player := START
var facing := Vector2.RIGHT
var hp: float = BASE_HP
var wave: int = 1
var wave_t: float = 0.0
var kills: int = 0
var kills_by_kind: Dictionary = {}
var score: int = 0
var run_credits: int = 0
var zombies: Array = []           # {id, pos, hp, max, kind, cd, flash, ...}
var bullets: Array = []           # {pos, vel, dmg, life, pierce, ap, hit}
var spits: Array = []             # {pos, vel, life}
var pickups: Array = []           # {pos, kind: "scrap"|"medkit", value, life}
var corpses: Array = []           # {pos, kind, t, r, col}
var beams: Array = []             # {pts, t}
var fx: Array = []                # {pos, t, col}
var shots_fired: int = 0
var damage_taken: float = 0.0
var hurt_flash: float = 0.0
var held: Dictionary = {}
var shop_return: String = "title"
var message: String = ""
var banner: String = ""
var banner_t: float = 0.0
var _spawn_t: float = 0.0
var _to_spawn: int = 0
var _fire_t: float = 0.0
var _zid: int = 0
var _rng := RandomNumberGenerator.new()
var cam := Vector2.ZERO
## Map (static; deterministic so landmarks are always where you left them).
var obstacles: Array = []         # {rect: Rect2, kind, solid_bullets}
var trees: Array = []             # {pos, r}
var roads: Array = []             # Rect2
var lights: Array = []            # {pos, broken}
var supply_points: Array = []     # Vector2
var landmarks: Array = []         # {name, rect}
var _arena: Control
var _overlay: VBoxContainer
var _ov_title: Label
var _ov_text: Label
var _ov_buttons: HBoxContainer
var _shop_grid: GridContainer
var _weapon_row: HBoxContainer
var buttons: Dictionary = {}


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(440, 190)
	clip_contents = true
	for id in UPGRADES:
		if not ranks.has(id):
			ranks[id] = 0
	build_map()
	_arena = Control.new()
	_arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.draw.connect(_draw_arena)
	add_child(_arena)
	_overlay = VBoxContainer.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_theme_constant_override("separation", 2)
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_overlay)
	_ov_title = _label(_overlay, 16, Color(0.95, 0.75, 0.3))
	_ov_text = _label(_overlay, 10, Color(0.85, 0.9, 0.85))
	_shop_grid = GridContainer.new()
	_shop_grid.columns = 3
	_shop_grid.add_theme_constant_override("h_separation", 3)
	_shop_grid.add_theme_constant_override("v_separation", 2)
	_shop_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay.add_child(_shop_grid)
	for id in UPGRADE_ORDER:
		var b := _button(_shop_grid, "", 8, Vector2(140, 16))
		b.pressed.connect(func(): buy(id))
		buttons["buy_" + id] = b
	_weapon_row = HBoxContainer.new()
	_weapon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_weapon_row.add_theme_constant_override("separation", 3)
	_overlay.add_child(_weapon_row)
	for wid in WEAPON_ORDER:
		var b := _button(_weapon_row, "", 8, Vector2(82, 16))
		b.pressed.connect(func(): weapon_action(wid))
		buttons["weapon_" + wid] = b
	_ov_buttons = HBoxContainer.new()
	_ov_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_ov_buttons.add_theme_constant_override("separation", 6)
	_overlay.add_child(_ov_buttons)
	for spec in [["start", "START"], ["resume", "RESUME"], ["continue", "NEXT WAVE"], ["shop", "ARMORY"], ["restart", "RESTART"], ["back", "BACK"], ["desktop", "DESKTOP"]]:
		var b := _button(_ov_buttons, spec[1], 10, Vector2.ZERO)
		var id: String = spec[0]
		b.pressed.connect(func(): action(id))
		buttons[id] = b
	_refresh_overlay()


func _button(parent: Node, text: String, fs: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size = min_size
	parent.add_child(b)
	return b


func _label(parent: Node, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	parent.add_child(l)
	return l


## The whole playable world (Round 42 name kept for the API).
func arena_rect() -> Rect2:
	return WORLD


## The visible WORLD rectangle size (screen area / ZOOM).
func view_size() -> Vector2:
	return ((size if size.x > 10.0 else Vector2(440, 190)) - Vector2(0, HUD_H)) / ZOOM


func screen_view_size() -> Vector2:
	return (size if size.x > 10.0 else Vector2(440, 190)) - Vector2(0, HUD_H)


# ================================================================ the map
## Builds the town. Deterministic: the same map every run (players learn it).
func build_map() -> void:
	obstacles = []
	trees = []
	roads = []
	lights = []
	supply_points = []
	landmarks = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4307
	# Roads: two east-west and two north-south avenues around the plaza.
	for y in [300.0, 860.0]:
		roads.append(Rect2(0, y - 22, WORLD.size.x, 44))
	for x in [520.0, 1300.0]:
		roads.append(Rect2(x - 22, 0, 44, WORLD.size.y))
	# Named landmark buildings (solid; bullets stop).
	for spec in [["MOTEL", Rect2(120, 110, 230, 120)], ["PHARMACY", Rect2(640, 110, 150, 110)], ["FUEL STOP", Rect2(1390, 120, 170, 90)],
			["CHAPEL", Rect2(130, 420, 120, 150)], ["BUS DEPOT", Rect2(1420, 950, 260, 130)], ["DINER", Rect2(640, 960, 150, 100)]]:
		_solid(spec[1], "building")
		landmarks.append({"name": spec[0], "rect": spec[1]})
	# Plain buildings fill the blocks (never the plaza around START).
	for r in [Rect2(880, 120, 120, 90), Rect2(1060, 140, 90, 120), Rect2(1640, 360, 120, 140), Rect2(1420, 420, 110, 90),
			Rect2(140, 960, 140, 120), Rect2(330, 1000, 110, 90), Rect2(1640, 620, 110, 150), Rect2(980, 990, 130, 110)]:
		_solid(r, "building")
	# Park (west of the plaza): fence with a gap + trees.
	var park := Rect2(600, 420, 230, 160)
	landmarks.append({"name": "PARK", "rect": park})
	for seg in [Rect2(park.position.x, park.position.y, park.size.x, 3), Rect2(park.position.x, park.end.y - 3, park.size.x * 0.4, 3),
			Rect2(park.end.x - park.size.x * 0.4, park.end.y - 3, park.size.x * 0.4, 3), Rect2(park.position.x, park.position.y, 3, park.size.y)]:
		obstacles.append({"rect": seg, "kind": "fence", "solid_bullets": false})
	for i in 9:
		trees.append({"pos": Vector2(park.position.x + 40 + (i % 3) * 72 + rng.randf_range(-10, 10), park.position.y + 35 + (i / 3) * 45 + rng.randf_range(-8, 8)), "r": rng.randf_range(9, 13)})
	# The plaza's dry fountain (solid; north of the start point).
	trees.append({"pos": START + Vector2(0, -70), "r": 16.0, "fountain": true})
	landmarks.append({"name": "PLAZA", "rect": Rect2(START - Vector2(40, 98), Vector2(80, 14))})
	# Scattered trees on verges.
	for p in [Vector2(80, 700), Vector2(380, 760), Vector2(1120, 420), Vector2(1730, 900), Vector2(1080, 760), Vector2(60, 360), Vector2(1580, 260)]:
		trees.append({"pos": p, "r": rng.randf_range(8, 12)})
	# Parked / abandoned cars along the roads (solid).
	for c in [Vector2(200, 330), Vector2(330, 268), Vector2(760, 272), Vector2(1080, 328), Vector2(1600, 270), Vector2(260, 890), Vector2(1020, 830),
			Vector2(1700, 888), Vector2(548, 160), Vector2(492, 1050), Vector2(1272, 520), Vector2(1328, 1080)]:
		var vertical: bool = absf(c.x - 520.0) < 40.0 or absf(c.x - 1300.0) < 40.0
		_solid(Rect2(c - (Vector2(9, 16) if vertical else Vector2(16, 9)), Vector2(18, 32) if vertical else Vector2(32, 18)), "car")
	# Barricades at the plaza approaches (block movement, not bullets).
	for b in [Rect2(700, 600, 6, 40), Rect2(1094, 640, 6, 40), Rect2(880, 420, 40, 6), Rect2(860, 790, 40, 6)]:
		obstacles.append({"rect": b, "kind": "barricade", "solid_bullets": false})
	# Streetlights (every third one broken / flickering).
	var n := 0
	for rd in roads:
		var horiz: bool = rd.size.x > rd.size.y
		var length: float = rd.size.x if horiz else rd.size.y
		for t in range(90, int(length), 210):
			var p: Vector2 = (Vector2(t, rd.position.y - 6) if horiz else Vector2(rd.position.x - 6, t))
			lights.append({"pos": p, "broken": n % 3 == 1})
			n += 1
	# Supply points (medkits appear at some each wave).
	supply_points = [Vector2(370, 245), Vector2(715, 245), Vector2(1475, 230), Vector2(285, 500), Vector2(1550, 920), Vector2(715, 1080)]


func _solid(r: Rect2, kind: String) -> void:
	obstacles.append({"rect": r, "kind": kind, "solid_bullets": true})


func landmark_names() -> Array:
	return landmarks.map(func(l): return l["name"])


## Is a circle at p (radius r) inside the world and clear of obstacles / trees?
func is_free(p: Vector2, r: float) -> bool:
	if not WORLD.grow(-r).has_point(p):
		return false
	for o in obstacles:
		if _circle_rect(p, r, o["rect"]):
			return false
	for t in trees:
		if p.distance_to(t["pos"]) < r + float(t["r"]):
			return false
	return true


static func _circle_rect(p: Vector2, r: float, rect: Rect2) -> bool:
	var c := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	return p.distance_squared_to(c) < r * r


## Pushes a circle out of obstacles / trees / the world edge (slides along).
func resolve(p: Vector2, r: float) -> Vector2:
	for o in obstacles:
		var rect: Rect2 = o["rect"]
		if p.x < rect.position.x - r or p.x > rect.end.x + r or p.y < rect.position.y - r or p.y > rect.end.y + r:
			continue
		var c := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		var d: Vector2 = p - c
		var l: float = d.length()
		if l < r:
			if l > 0.0001:
				p = c + d / l * r
			else:
				# Centre inside the rect: leave along the shortest axis.
				var dl: float = p.x - rect.position.x
				var dr: float = rect.end.x - p.x
				var dt: float = p.y - rect.position.y
				var db: float = rect.end.y - p.y
				var m: float = minf(minf(dl, dr), minf(dt, db))
				if m == dl: p.x = rect.position.x - r
				elif m == dr: p.x = rect.end.x + r
				elif m == dt: p.y = rect.position.y - r
				else: p.y = rect.end.y + r
	for t in trees:
		var d2: Vector2 = p - (t["pos"] as Vector2)
		var need: float = r + float(t["r"])
		var l2: float = d2.length()
		if l2 < need and l2 > 0.0001:
			p = (t["pos"] as Vector2) + d2 / l2 * need
	p.x = clampf(p.x, WORLD.position.x + r, WORLD.end.x - r)
	p.y = clampf(p.y, WORLD.position.y + r, WORLD.end.y - r)
	return p


## The first obstacle the segment a->b crosses (grown by `grow`), or {}.
func _segment_blocked(a: Vector2, b: Vector2, grow: float, bullets_only: bool = false) -> Dictionary:
	for o in obstacles:
		if bullets_only and not o["solid_bullets"]:
			continue
		var rect: Rect2 = (o["rect"] as Rect2).grow(grow)
		if rect.has_point(a):
			continue
		if _seg_rect(a, b, rect):
			return o
	return {}


static func _seg_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	if maxf(a.x, b.x) < r.position.x or minf(a.x, b.x) > r.end.x or maxf(a.y, b.y) < r.position.y or minf(a.y, b.y) > r.end.y:
		return false
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


# ------------------------------------------------------------ stats
func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func weapon_stats(id: String = "") -> Dictionary:
	return WEAPONS.get(id if id != "" else weapon, WEAPONS["pistol"])


func fire_interval() -> float:
	return float(weapon_stats()["interval"]) * pow(0.88, rank("rate"))


func damage() -> float:
	return float(weapon_stats()["dmg"]) * (1.0 + 0.25 * rank("damage"))


func projectiles() -> int:
	return 1 + rank("multishot")


func weapon_range() -> float:
	return float(weapon_stats()["range"])


func max_hp() -> float:
	return BASE_HP + 25.0 * rank("health")


func armor_factor() -> float:
	return pow(0.85, rank("armor"))


func move_speed() -> float:
	return BASE_SPEED * (1.0 + 0.12 * rank("speed"))


func regen() -> float:
	return 1.0 * rank("regen")


func magnet_radius() -> float:
	return BASE_MAGNET + 14.0 * rank("magnet")


func crit_chance() -> float:
	return 0.08 * rank("crit")


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


## Armory weapon button: unlock (pay once) or equip an unlocked weapon.
func weapon_action(id: String) -> bool:
	if not WEAPONS.has(id):
		return false
	if unlocked.get(id, false):
		weapon = id
		message = "%s equipped." % WEAPONS[id]["name"]
		_refresh_overlay()
		return true
	var cost: int = int(WEAPONS[id]["cost"])
	if credits < cost:
		message = "Need %d CR to unlock the %s (have %d)." % [cost, WEAPONS[id]["name"], credits]
		_refresh_overlay()
		return false
	credits -= cost
	unlocked[id] = true
	weapon = id
	message = "NEW WEAPON: %s — equipped." % WEAPONS[id]["name"]
	_announce("NEW WEAPON  ·  %s" % WEAPONS[id]["name"])
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
	player = START
	facing = Vector2.RIGHT
	hp = max_hp()
	kills = 0
	kills_by_kind = {}
	score = 0
	run_credits = 0
	shots_fired = 0
	damage_taken = 0.0
	zombies = []
	bullets = []
	spits = []
	pickups = []
	corpses = []
	beams = []
	fx = []
	held = {}
	message = ""
	_begin_wave(1)
	mode = "play"
	_update_camera()
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
	# Fresh medkits at a few supply points.
	pickups = pickups.filter(func(p): return p["kind"] != "medkit")
	for i in mini(2 + n / 3, supply_points.size()):
		pickups.append({"pos": supply_points[(n * 2 + i) % supply_points.size()], "kind": "medkit", "value": 25, "life": 9999.0})
	var newkind: String = ""
	for k in KINDS:
		if int(KINDS[k]["wave"]) == n and k != "elite":
			newkind = k
	if n % 5 == 0:
		_announce("WAVE %d  ·  ELITE INCOMING" % n)
	elif newkind != "":
		_announce("WAVE %d  ·  %sS SIGHTED" % [n, newkind.to_upper()])
	else:
		_announce("WAVE %d" % n)


func _announce(text: String) -> void:
	banner = text
	banner_t = 2.4


func spawn_interval() -> float:
	return maxf(0.35, 2.0 - 0.15 * wave)


## The kinds this wave may send, with weights.
func kind_table() -> Array:
	var t: Array = [["walker", 5.0]]
	if wave >= 2: t.append(["swarm", 1.6])
	if wave >= 3: t.append(["runner", 2.4])
	if wave >= 4: t.append(["spitter", 1.0])
	if wave >= 5: t.append(["brute", minf(0.6 + 0.1 * (wave - 5), 1.5)])
	if wave >= 6: t.append(["bloater", 0.8])
	if wave >= 7: t.append(["armored", 0.9])
	return t


## The next enemy type for this wave (unlocked kinds, weighted).
func _pick_kind() -> String:
	var t: Array = kind_table()
	var total: float = 0.0
	for e in t:
		total += float(e[1])
	var roll: float = _rng.randf() * total
	for e in t:
		roll -= float(e[1])
		if roll <= 0.0:
			return e[0]
	return "walker"


## A zombie just off-screen around the survivor, on free ground, never
## within 60 px of them.
func spawn_zombie(kind: String = "") -> Dictionary:
	var k: String = kind if kind != "" else _pick_kind()
	var r: float = float(KINDS[k]["r"])
	var ring: float = view_size().length() * 0.5 + 16.0
	var p: Vector2 = Vector2.INF
	for attempt in 32:
		var cand: Vector2 = player + Vector2.from_angle(_rng.randf() * TAU) * (ring + _rng.randf() * 90.0)
		if cand.distance_to(player) >= 60.0 and is_free(cand, r + 1.0):
			p = cand
			break
	if p == Vector2.INF:
		p = resolve(player + Vector2.from_angle(_rng.randf() * TAU) * ring, r)
	var hpz: float = float(KINDS[k]["hp"]) * (1.0 + 0.08 * (wave - 1))
	var z := {"pos": p, "hp": hpz, "max": hpz, "kind": k}
	_norm(z)
	zombies.append(z)
	return z


func _spawn_group() -> void:
	if zombies.size() >= MAX_ALIVE:
		_to_spawn += 1          # postponed, not lost
		return
	var k: String = _pick_kind()
	if k == "swarm":
		var lead: Dictionary = spawn_zombie("swarm")
		for i in _rng.randi_range(4, 6):
			var z: Dictionary = spawn_zombie("swarm")
			var p: Vector2 = (lead["pos"] as Vector2) + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-14, 14))
			if is_free(p, 3.0):
				z["pos"] = p
	else:
		spawn_zombie(k)


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
	else:
		_age_fx(minf(delta, 0.05))
	if is_visible_in_tree():
		_arena.queue_redraw()


func _age_fx(dt: float) -> void:
	for f in fx:
		f["t"] = float(f["t"]) - dt
	fx = fx.filter(func(f): return float(f["t"]) > 0.0)
	for c in corpses:
		c["t"] = float(c["t"]) - dt
	corpses = corpses.filter(func(c): return float(c["t"]) > 0.0)
	for b in beams:
		b["t"] = float(b["t"]) - dt
	beams = beams.filter(func(b): return float(b["t"]) > 0.0)
	banner_t = maxf(banner_t - dt, 0.0)
	hurt_flash = maxf(hurt_flash - dt, 0.0)


func _hurt(amount: float) -> void:
	var d: float = amount * armor_factor()
	hp -= d
	damage_taken += d
	hurt_flash = 0.3
	fx.append({"pos": player, "t": 0.25, "col": Color(1, 0.2, 0.15)})


## Fills in per-zombie state (tests may hand in minimal dictionaries).
func _norm(z: Dictionary) -> void:
	if not z.has("id"):
		_zid += 1
		z["id"] = _zid
	for k in [["cd", 0.0], ["flash", 0.0], ["steer", Vector2.INF], ["steer_t", 0.0], ["spit_cd", SPIT_CD * 0.6], ["windup", -1.0], ["fuse", -1.0], ["lunge", 0.0]]:
		if not z.has(k[0]):
			z[k[0]] = k[1]


## One simulation tick (also driven directly by tests).
func step(dt: float) -> void:
	if mode != "play":
		return
	# Survivor.
	var md: Vector2 = move_dir()
	if md != Vector2.ZERO:
		facing = md
	player = resolve(player + md * move_speed() * dt, PLAYER_R)
	hp = minf(hp + regen() * dt, max_hp())
	# Spawning.
	wave_t += dt
	_spawn_t -= dt
	if _to_spawn > 0 and _spawn_t <= 0.0:
		_spawn_t = spawn_interval()
		_to_spawn -= 1
		if wave % 5 == 0 and _to_spawn == 0:
			spawn_zombie("elite")
		else:
			_spawn_group()
	_step_zombies(dt)
	_separate()
	# Auto-attack the nearest zombie in the weapon's range.
	_fire_t -= dt
	if _fire_t <= 0.0:
		var target: Dictionary = nearest_zombie()
		if not target.is_empty():
			_fire_t = fire_interval()
			_fire_at(target)
	_step_bullets(dt)
	_step_spits(dt)
	_step_pickups(dt)
	_collect_dead()
	_age_fx(dt)
	_update_camera()
	if hp <= 0.0:
		_game_over()
		return
	# Wave cleared: everything spawned and dead.
	if _to_spawn == 0 and zombies.is_empty():
		var bonus: int = 5 + 2 * wave
		credits += bonus
		run_credits += bonus
		score += 50 * wave
		message = "WAVE %d CLEARED  +%d CR" % [wave, bonus]
		if MILESTONES.has(wave):
			var mb: int = int(MILESTONES[wave])
			credits += mb
			run_credits += mb
			message += "  ·  MILESTONE +%d CR" % mb
		best_wave = maxi(best_wave, wave)
		shop_return = "wave"
		mode = "shop"
		_refresh_overlay()


func _step_zombies(dt: float) -> void:
	for z in zombies:
		_norm(z)
		var kind: String = z["kind"]
		var kd: Dictionary = KINDS[kind]
		var zr: float = float(kd["r"])
		var zp: Vector2 = z["pos"]
		var to: Vector2 = player - zp
		var dist: float = to.length()
		var reach: float = PLAYER_R + zr
		z["cd"] = maxf(float(z["cd"]) - dt, 0.0)
		z["flash"] = maxf(float(z["flash"]) - dt, 0.0)
		# Bloater fuse: swells visibly, then bursts.
		if float(z["fuse"]) >= 0.0:
			z["fuse"] = float(z["fuse"]) + dt
			if float(z["fuse"]) >= FUSE_S:
				_burst(z)
			continue
		if kind == "bloater" and dist < reach + 14.0:
			z["fuse"] = 0.0
			continue
		var speed: float = float(kd["speed"])
		var goal: Vector2 = player
		if kind == "spitter":
			# Keep a firing distance; telegraph, then lob a slow glob.
			if dist < SPIT_RANGE.x:
				goal = zp - to
			elif dist <= SPIT_RANGE.y:
				goal = zp
			z["spit_cd"] = float(z["spit_cd"]) - dt
			if float(z["windup"]) >= 0.0:
				z["windup"] = float(z["windup"]) + dt
				goal = zp
				if float(z["windup"]) >= SPIT_WINDUP:
					z["windup"] = -1.0
					z["spit_cd"] = SPIT_CD
					spits.append({"pos": zp, "vel": to.normalized() * SPIT_SPEED, "life": 3.0})
			elif float(z["spit_cd"]) <= 0.0 and dist <= SPIT_RANGE.y + 10.0 and _segment_blocked(zp, player, 0.0, true).is_empty():
				z["windup"] = 0.0
		if kind == "runner":
			# A short lunge when close.
			z["lunge"] = maxf(float(z["lunge"]) - dt, 0.0)
			if dist < 55.0 and float(z["lunge"]) <= 0.0 and float(z["cd"]) <= 0.0:
				z["lunge"] = 1.6
			if float(z["lunge"]) > 1.2:
				speed *= 2.2
		# Steering: aim at a free corner when the straight line is blocked
		# (re-planned a few times a second).
		z["steer_t"] = float(z["steer_t"]) - dt
		if float(z["steer_t"]) <= 0.0:
			z["steer_t"] = 0.35
			z["steer"] = _plan_corner(zp, goal, zr)
		if z["steer"] != Vector2.INF and zp.distance_to(z["steer"]) < 4.0:
			z["steer"] = Vector2.INF
		var aim: Vector2 = goal if z["steer"] == Vector2.INF else z["steer"]
		var dir: Vector2 = aim - zp
		if (dist > reach - 0.5 or kind == "spitter") and dir.length() > 0.5:
			z["pos"] = resolve(zp + dir.normalized() * speed * dt, zr)
		if dist <= reach + 0.5 and float(z["cd"]) <= 0.0 and float(kd["dmg"]) > 0.0:
			z["cd"] = CONTACT_CD
			_hurt(float(kd["dmg"]))
			if kind in ["brute", "elite"]:
				player = resolve(player + to.normalized() * 14.0, PLAYER_R)


func _plan_corner(from: Vector2, to: Vector2, r: float) -> Vector2:
	var o: Dictionary = _segment_blocked(from, to, r + 1.0)
	if o.is_empty():
		return Vector2.INF
	var rect: Rect2 = (o["rect"] as Rect2).grow(r + 5.0)
	var best_c := Vector2.INF
	var best_cost: float = INF
	for c in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		if not WORLD.has_point(c):
			continue
		var cost: float = from.distance_to(c) + c.distance_to(to)
		if cost < best_cost:
			best_cost = cost
			best_c = c
	return best_c


func _burst(z: Dictionary) -> void:
	z["hp"] = 0.0
	z["fuse"] = -1.0
	z["burst"] = true
	var zp: Vector2 = z["pos"]
	fx.append({"pos": zp, "t": 0.5, "col": Color(0.95, 0.75, 0.35), "big": BLAST_R})
	if player.distance_to(zp) <= BLAST_R + PLAYER_R:
		_hurt(BLAST_DMG)
	for o in zombies:
		if o != z and float(o["hp"]) > 0.0 and (o["pos"] as Vector2).distance_to(zp) <= BLAST_R:
			o["hp"] = float(o["hp"]) - BLAST_DMG * 2.0
			o["flash"] = 0.12


func _step_bullets(dt: float) -> void:
	for b in bullets:
		var prev: Vector2 = b["pos"]
		b["pos"] = prev + (b["vel"] as Vector2) * dt
		b["life"] = float(b["life"]) - dt
		if not _segment_blocked(prev, b["pos"], 0.0, true).is_empty():
			b["life"] = 0.0
			fx.append({"pos": prev, "t": 0.1, "col": Color(0.8, 0.8, 0.7)})
			continue
		for z in zombies:
			_norm(z)
			if float(z["hp"]) > 0.0 and not (b["hit"] as Dictionary).has(z["id"]) and (b["pos"] as Vector2).distance_to(z["pos"]) <= float(KINDS[z["kind"]]["r"]) + 1.5:
				_damage_zombie(z, float(b["dmg"]), bool(b["ap"]))
				(b["hit"] as Dictionary)[z["id"]] = true
				fx.append({"pos": b["pos"], "t": 0.15, "col": Color(1, 0.9, 0.5)})
				if int(b["pierce"]) > 0:
					b["pierce"] = int(b["pierce"]) - 1
				else:
					b["life"] = 0.0
					break
	bullets = bullets.filter(func(b): return float(b["life"]) > 0.0 and WORLD.grow(10).has_point(b["pos"]))


func _damage_zombie(z: Dictionary, amount: float, ap: bool) -> void:
	var dmg: float = amount
	if crit_chance() > 0.0 and _rng.randf() < crit_chance():
		dmg *= 2.0
		fx.append({"pos": (z["pos"] as Vector2) + Vector2(0, -8), "t": 0.4, "col": Color(1.0, 0.95, 0.3), "text": "CRIT"})
	if z["kind"] == "armored" and not ap:
		dmg *= 0.35
		fx.append({"pos": z["pos"], "t": 0.12, "col": Color(0.8, 0.85, 0.9)})
	z["hp"] = float(z["hp"]) - dmg
	z["flash"] = 0.12


func _step_spits(dt: float) -> void:
	for s in spits:
		s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * dt
		s["life"] = float(s["life"]) - dt
		if (s["pos"] as Vector2).distance_to(player) <= PLAYER_R + 3.0:
			_hurt(SPIT_DMG)
			s["life"] = 0.0
			fx.append({"pos": s["pos"], "t": 0.3, "col": Color(0.5, 0.95, 0.4)})
		elif not _segment_blocked(s["pos"], s["pos"], 0.0, true).is_empty():
			s["life"] = 0.0
	spits = spits.filter(func(s): return float(s["life"]) > 0.0)


func _step_pickups(dt: float) -> void:
	var mag: float = magnet_radius()
	for p in pickups:
		p["life"] = float(p["life"]) - dt
		var d: float = (p["pos"] as Vector2).distance_to(player)
		if d <= mag:
			# Drawn in by the magnet, collected on contact.
			p["pos"] = (p["pos"] as Vector2).move_toward(player, 140.0 * dt)
			d = (p["pos"] as Vector2).distance_to(player)
		if d <= PLAYER_R + 3.0:
			p["life"] = 0.0
			if p["kind"] == "scrap":
				credits += int(p["value"])
				run_credits += int(p["value"])
				fx.append({"pos": player, "t": 0.3, "col": Color(1.0, 0.85, 0.3)})
			else:
				hp = minf(hp + float(p["value"]), max_hp())
				fx.append({"pos": player, "t": 0.35, "col": Color(0.4, 1.0, 0.5)})
	pickups = pickups.filter(func(p): return float(p["life"]) > 0.0)


func _collect_dead() -> void:
	for z in zombies:
		if float(z["hp"]) <= 0.0:
			var kind: String = z["kind"]
			if kind == "bloater" and not z.get("burst", false):
				_burst(z)
			kills += 1
			kills_by_kind[kind] = int(kills_by_kind.get(kind, 0)) + 1
			var c: int = int(KINDS[kind]["credits"])
			run_credits += c
			credits += c
			score += 10 * c
			corpses.append({"pos": z["pos"], "kind": kind, "t": 0.7, "r": float(KINDS[kind]["r"]), "col": KINDS[kind]["color"]})
			if kind == "elite":
				for i in 5:
					pickups.append({"pos": (z["pos"] as Vector2) + Vector2.from_angle(i * 1.25) * 10.0, "kind": "scrap", "value": 3, "life": 20.0})
			elif _rng.randf() < 0.22:
				pickups.append({"pos": z["pos"], "kind": "scrap", "value": 2, "life": 12.0})
	zombies = zombies.filter(func(z): return float(z["hp"]) > 0.0)


func nearest_zombie() -> Dictionary:
	var best_d: float = weapon_range()
	var out: Dictionary = {}
	for z in zombies:
		var d: float = player.distance_to(z["pos"])
		if d <= best_d:
			best_d = d
			out = z
	return out


func _fire_at(target: Dictionary) -> void:
	_norm(target)
	var w: Dictionary = weapon_stats()
	var tpos: Vector2 = target["pos"]
	var base: float = (tpos - player).angle()
	shots_fired += 1
	fx.append({"pos": player + Vector2.from_angle(base) * 7.0, "t": 0.06, "col": w["color"]})
	if weapon == "arc":
		# Instant bolt chaining to nearby zombies (MULTISHOT adds chain links).
		var pts: Array = [player]
		var hit: Array = []
		var cur: Dictionary = target
		for j in int(w["pierce"]) + projectiles():
			if cur.is_empty():
				break
			_damage_zombie(cur, damage(), true)
			hit.append(cur["id"])
			pts.append(cur["pos"])
			var nxt: Dictionary = {}
			var bd: float = ARC_JUMP
			for z in zombies:
				_norm(z)
				if not z["id"] in hit and float(z["hp"]) > 0.0 and (z["pos"] as Vector2).distance_to(cur["pos"]) <= bd:
					bd = (z["pos"] as Vector2).distance_to(cur["pos"])
					nxt = z
			cur = nxt
		beams.append({"pts": pts, "t": 0.16})
		return
	var pellets: int = int(w["pellets"])
	var n: int = projectiles() * pellets
	var spread: float = float(w["spread"])
	var life: float = float(w["range"]) / float(w["speed"]) * 1.15
	for i in n:
		var a: float
		if pellets > 1:
			a = base + (float(i) / maxf(n - 1, 1) - 0.5) * spread
		else:
			a = base + (float(i) - float(n - 1) * 0.5) * 0.18 + (_rng.randf_range(-spread, spread) if spread > 0.0 else 0.0)
		bullets.append({"pos": player, "vel": Vector2.from_angle(a) * float(w["speed"]), "dmg": damage(), "life": life, "pierce": int(w["pierce"]), "ap": bool(w["ap"]), "hit": {}, "col": w["color"]})


## Cheap pairwise push so zombies never stack into one blob.
func _separate() -> void:
	var n: int = zombies.size()
	for i in n:
		for j in range(i + 1, n):
			var a: Dictionary = zombies[i]
			var b: Dictionary = zombies[j]
			var d: Vector2 = b["pos"] - a["pos"]
			var min_d: float = float(KINDS[a["kind"]]["r"]) + float(KINDS[b["kind"]]["r"])
			if absf(d.x) > min_d or absf(d.y) > min_d:
				continue
			var l: float = d.length()
			if l < min_d and l > 0.001:
				var push: Vector2 = d / l * (min_d - l) * 0.5
				a["pos"] -= push
				b["pos"] += push


func _update_camera() -> void:
	var vs: Vector2 = view_size()
	cam = player - vs * 0.5
	cam.x = clampf(cam.x, WORLD.position.x, WORLD.end.x - vs.x)
	cam.y = clampf(cam.y, WORLD.position.y, WORLD.end.y - vs.y)


func _game_over() -> void:
	hp = 0.0
	mode = "over"
	best = maxi(best, score)
	best_wave = maxi(best_wave, wave)
	held = {}
	message = ""
	_refresh_overlay()


# --------------------------------------------------------------- views
func _refresh_overlay() -> void:
	if _overlay == null:
		return
	var show: Dictionary = {}
	_shop_grid.visible = mode == "shop"
	_weapon_row.visible = mode == "shop"
	_overlay.visible = mode != "play"
	match mode:
		"title":
			_ov_title.text = "HOLDOUT"
			_ov_text.text = "Survive the town. WASD moves — your %s fires by itself.\nBest %d (wave %d) · Wallet %d CR" % [WEAPONS[weapon]["name"], best, best_wave, credits]
			show = {"start": true, "shop": true, "desktop": true}
		"paused":
			_ov_title.text = "PAUSED"
			_ov_text.text = "Wave %d · Score %d · HP %d · %s" % [wave, score, int(hp), WEAPONS[weapon]["name"]]
			show = {"resume": true, "restart": true, "desktop": true}
		"shop":
			_ov_title.text = "ARMORY · %d CR" % credits
			_ov_text.text = message if message != "" else ("Spend credits before wave %d." % (wave + 1) if shop_return == "wave" else "Upgrades and weapons carry over to every run.")
			show = {"continue": shop_return == "wave", "back": shop_return == "title", "desktop": true}
			for id in UPGRADE_ORDER:
				var b: Button = buttons["buy_" + id]
				var cost: int = upgrade_cost(id)
				b.text = "%s %d/%d · %s" % [UPGRADES[id][0], rank(id), UPGRADES[id][1], ("MAX" if cost < 0 else "%d CR" % cost)]
				b.disabled = cost < 0 or credits < cost
				b.tooltip_text = UPGRADES[id][3]
			for wid in WEAPON_ORDER:
				var wb: Button = buttons["weapon_" + wid]
				if wid == weapon:
					wb.text = "■ " + String(WEAPONS[wid]["name"])
				elif unlocked.get(wid, false):
					wb.text = String(WEAPONS[wid]["name"])
				else:
					wb.text = "%s %dCR" % [WEAPONS[wid]["name"], int(WEAPONS[wid]["cost"])]
				wb.disabled = not unlocked.get(wid, false) and credits < int(WEAPONS[wid]["cost"])
		"over":
			_ov_title.text = "GAME OVER"
			_ov_text.text = "Wave %d · %d kills · Score %d · Best %d (wave %d)\n+%d CR this run (wallet %d CR)" % [wave, kills, score, best, best_wave, run_credits, credits]
			show = {"restart": true, "shop": true, "desktop": true}
	for k in ["start", "resume", "continue", "shop", "restart", "back", "desktop"]:
		(buttons[k] as Button).visible = show.get(k, false)


## World -> arena drawing space (the world pass draws under a ZOOM transform).
func _w2s(p: Vector2) -> Vector2:
	return p - cam


func _draw_arena() -> void:
	var a: Control = _arena
	var vs: Vector2 = view_size()
	var view := Rect2(cam, vs).grow(16)
	var font: Font = ThemeDB.fallback_font
	var tnow: float = Time.get_ticks_msec() / 1000.0
	a.draw_rect(Rect2(Vector2.ZERO, a.size), Color(0.04, 0.05, 0.05))
	a.draw_set_transform(Vector2(0, HUD_H), 0.0, Vector2(ZOOM, ZOOM))
	# Ground: dusk grass with a faint lot grid (shows the map scrolling).
	a.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.11, 0.14, 0.09))
	# The central PLAZA: paving around a dry fountain.
	var pz := Rect2(START - Vector2(150, 110), Vector2(300, 220))
	if view.intersects(pz):
		a.draw_rect(Rect2(_w2s(pz.position), pz.size), Color(0.2, 0.2, 0.19))
		for k in range(1, 15):
			a.draw_line(_w2s(pz.position + Vector2(k * 20, 0)), _w2s(pz.position + Vector2(k * 20, pz.size.y)), Color(0.17, 0.17, 0.16), 1.0)
		for k in range(1, 11):
			a.draw_line(_w2s(pz.position + Vector2(0, k * 20)), _w2s(pz.position + Vector2(pz.size.x, k * 20)), Color(0.17, 0.17, 0.16), 1.0)
	var g0 := Vector2(floor(cam.x / 60.0) * 60.0, floor(cam.y / 60.0) * 60.0)
	for gx in range(int(g0.x), int(cam.x + vs.x) + 60, 60):
		a.draw_line(_w2s(Vector2(gx, cam.y)), _w2s(Vector2(gx, cam.y + vs.y)), Color(0.13, 0.16, 0.1), 1.0)
	for gy in range(int(g0.y), int(cam.y + vs.y) + 60, 60):
		a.draw_line(_w2s(Vector2(cam.x, gy)), _w2s(Vector2(cam.x + vs.x, gy)), Color(0.13, 0.16, 0.1), 1.0)
	# Park lawn.
	for lm in landmarks:
		if lm["name"] == "PARK" and view.intersects(lm["rect"]):
			a.draw_rect(Rect2(_w2s((lm["rect"] as Rect2).position), (lm["rect"] as Rect2).size), Color(0.13, 0.22, 0.1))
	# Roads: kerb, asphalt, lane dashes.
	for rd in roads:
		if not view.intersects(rd):
			continue
		a.draw_rect(Rect2(_w2s(rd.position - Vector2(4, 4)), rd.size + Vector2(8, 8)), Color(0.3, 0.3, 0.28))
		a.draw_rect(Rect2(_w2s(rd.position), rd.size), Color(0.17, 0.17, 0.18))
		var horiz: bool = rd.size.x > rd.size.y
		var mid: float = rd.get_center().y if horiz else rd.get_center().x
		var c0: float = cam.x if horiz else cam.y
		var from: int = int(c0 - fmod(c0, 40.0))
		for t in range(from, from + int(vs.x if horiz else vs.y) + 40, 40):
			var p: Vector2 = Vector2(t, mid - 1) if horiz else Vector2(mid - 1, t)
			a.draw_rect(Rect2(_w2s(p), Vector2(18, 2) if horiz else Vector2(2, 18)), Color(0.75, 0.65, 0.25, 0.8))
	# Streetlights: pools of light (broken ones flicker).
	for l in lights:
		var lp: Vector2 = l["pos"]
		if not view.has_point(lp):
			continue
		var on: bool = not l["broken"] or fmod(tnow * 7.3 + lp.x, 3.0) > 2.2
		if on:
			a.draw_circle(_w2s(lp), 26.0, Color(1.0, 0.9, 0.6, 0.07))
		a.draw_circle(_w2s(lp), 2.0, Color(0.85, 0.8, 0.6) if on else Color(0.35, 0.35, 0.35))
	# Supply crates and pickups.
	for sp in supply_points:
		if view.has_point(sp):
			a.draw_rect(Rect2(_w2s(sp) + Vector2(6, -5), Vector2(9, 9)), Color(0.45, 0.32, 0.18))
			a.draw_line(_w2s(sp) + Vector2(6, -5), _w2s(sp) + Vector2(15, 4), Color(0.3, 0.2, 0.1), 1.0)
	for p in pickups:
		var pp: Vector2 = p["pos"]
		if not view.has_point(pp):
			continue
		if p["kind"] == "medkit":
			a.draw_rect(Rect2(_w2s(pp) - Vector2(4, 4), Vector2(8, 8)), Color(0.9, 0.9, 0.88))
			a.draw_rect(Rect2(_w2s(pp) - Vector2(1, 3), Vector2(2, 6)), Color(0.85, 0.15, 0.15))
			a.draw_rect(Rect2(_w2s(pp) - Vector2(3, 1), Vector2(6, 2)), Color(0.85, 0.15, 0.15))
		else:
			a.draw_circle(_w2s(pp), 2.5, Color(1.0, 0.82, 0.3))
	# Corpses (death animation: a flattened, fading body + stain).
	for c in corpses:
		var k: float = float(c["t"]) / 0.7
		var cr: float = float(c["r"])
		a.draw_circle(_w2s(c["pos"]), cr * (1.0 + (1.0 - k) * 0.6), Color(0.3, 0.08, 0.06, 0.5 * k))
		a.draw_circle(_w2s(c["pos"]), cr * k, Color((c["col"] as Color).darkened(0.4), k))
	# Obstacles.
	for o in obstacles:
		var r: Rect2 = o["rect"]
		if not view.intersects(r):
			continue
		var sr := Rect2(_w2s(r.position), r.size)
		match String(o["kind"]):
			"building":
				a.draw_rect(Rect2(sr.position + Vector2(3, 3), sr.size), Color(0, 0, 0, 0.35))
				a.draw_rect(sr, Color(0.27, 0.25, 0.24))
				a.draw_rect(sr.grow(-4), Color(0.33, 0.31, 0.29))
				a.draw_rect(sr, Color(0.12, 0.11, 0.1), false, 1.0)
				for wx in range(int(sr.position.x) + 10, int(sr.end.x) - 8, 22):
					a.draw_rect(Rect2(wx, sr.position.y + 6, 8, 4), Color(0.12, 0.13, 0.15))
			"car":
				var col: Color = [Color(0.55, 0.15, 0.12), Color(0.2, 0.3, 0.5), Color(0.6, 0.6, 0.58), Color(0.25, 0.4, 0.3)][int(r.position.x + r.position.y) % 4]
				a.draw_rect(sr, col.darkened(0.3))
				a.draw_rect(sr.grow(-2), col)
				var wind: Rect2 = Rect2(sr.position + Vector2(3, sr.size.y * 0.25), Vector2(sr.size.x - 6, sr.size.y * 0.2)) if sr.size.y > sr.size.x else Rect2(sr.position + Vector2(sr.size.x * 0.6, 3), Vector2(sr.size.x * 0.18, sr.size.y - 6))
				a.draw_rect(wind, Color(0.55, 0.7, 0.8, 0.8))
			"barricade":
				a.draw_rect(sr, Color(0.9, 0.5, 0.15))
				var vert: bool = sr.size.y > sr.size.x
				for s in range(0, int(maxf(sr.size.x, sr.size.y)), 8):
					var stripe: Rect2 = Rect2(sr.position + Vector2(0, s), Vector2(sr.size.x, 4)) if vert else Rect2(sr.position + Vector2(s, 0), Vector2(4, sr.size.y))
					a.draw_rect(stripe.intersection(sr), Color(0.95, 0.95, 0.9))
			"fence":
				a.draw_rect(sr, Color(0.45, 0.33, 0.2))
				var vert2: bool = sr.size.y > sr.size.x
				for s in range(0, int(maxf(sr.size.x, sr.size.y)), 14):
					a.draw_rect(Rect2(sr.position + (Vector2(-1, s) if vert2 else Vector2(s, -1)), Vector2(5, 5)), Color(0.35, 0.25, 0.15))
	# Landmark names on their roofs.
	for lm in landmarks:
		var lr: Rect2 = lm["rect"]
		if view.intersects(lr):
			var tp: Vector2 = _w2s(lr.get_center()) + Vector2(-float(String(lm["name"]).length()) * 3.0, 3)
			a.draw_string(font, tp, lm["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.88, 0.6))
	# Spit globs.
	for s in spits:
		a.draw_circle(_w2s(s["pos"]), 3.0, Color(0.45, 0.95, 0.35))
		a.draw_circle(_w2s(s["pos"]), 1.5, Color(0.85, 1.0, 0.6))
	# Zombies (each kind its own silhouette).
	for z in zombies:
		_draw_zombie(z, view)
	# Bullets + arc bolts.
	for b in bullets:
		var bp: Vector2 = _w2s(b["pos"])
		var bc: Color = b.get("col", Color(1.0, 0.92, 0.45))
		a.draw_line(bp - (b["vel"] as Vector2).normalized() * 6.0, bp, Color(bc, 0.7), 1.5)
		a.draw_circle(bp, 2.0 if weapon != "rifle" else 1.5, bc)
	for bm in beams:
		var pts: Array = bm["pts"]
		for i in pts.size() - 1:
			var p0: Vector2 = _w2s(pts[i])
			var p1: Vector2 = _w2s(pts[i + 1])
			var mid2: Vector2 = (p0 + p1) * 0.5 + (p1 - p0).orthogonal().normalized() * sin(tnow * 60.0 + i) * 5.0
			a.draw_polyline(PackedVector2Array([p0, mid2, p1]), Color(0.6, 0.9, 1.0, clampf(float(bm["t"]) * 7.0, 0, 1)), 2.0)
	# Survivor (with the magnet ring and the weapon's muzzle colour).
	if mode != "title":
		var sp2: Vector2 = _w2s(player)
		a.draw_arc(sp2, magnet_radius(), 0, TAU, 24, Color(1.0, 0.85, 0.3, 0.12), 1.0)
		a.draw_circle(sp2, PLAYER_R + 1.5, Color(0.1, 0.25, 0.4))
		a.draw_circle(sp2, PLAYER_R, Color(0.55, 0.8, 1.0))
		a.draw_line(sp2, sp2 + facing * (PLAYER_R + 4.0), WEAPONS[weapon]["color"], 2.0)
	# Tree crowns above everything walking.
	for t in trees:
		var tp2: Vector2 = t["pos"]
		if t.get("fountain", false) and view.has_point(tp2):
			a.draw_circle(_w2s(tp2), float(t["r"]), Color(0.45, 0.45, 0.43))
			a.draw_circle(_w2s(tp2), float(t["r"]) - 3.0, Color(0.16, 0.2, 0.22))
			a.draw_circle(_w2s(tp2), 3.0, Color(0.5, 0.5, 0.48))
			continue
		if view.has_point(tp2):
			a.draw_circle(_w2s(tp2) + Vector2(2, 2), float(t["r"]), Color(0, 0, 0, 0.3))
			a.draw_circle(_w2s(tp2), float(t["r"]), Color(0.12, 0.3, 0.13))
			a.draw_circle(_w2s(tp2) - Vector2(2, 2), float(t["r"]) * 0.6, Color(0.18, 0.4, 0.17))
	for f in fx:
		var t: float = float(f["t"])
		if f.has("text"):
			a.draw_string(font, _w2s(f["pos"]) + Vector2(-8, -(0.4 - t) * 20.0), f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, f["col"])
		elif f.has("big"):
			a.draw_circle(_w2s(f["pos"]), float(f["big"]) * (1.0 - t), Color(f["col"], clampf(t * 1.6, 0.0, 0.6)))
		else:
			a.draw_circle(_w2s(f["pos"]), 2.0 + (0.4 - t) * 10.0, Color(f["col"], clampf(t * 3.0, 0.0, 0.8)))
	a.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	vs = screen_view_size()
	# Hurt vignette (attack feedback).
	if hurt_flash > 0.0:
		var hc := Color(0.9, 0.1, 0.05, hurt_flash * 1.2)
		a.draw_rect(Rect2(0, HUD_H, a.size.x, 4), hc)
		a.draw_rect(Rect2(0, a.size.y - 4, a.size.x, 4), hc)
		a.draw_rect(Rect2(0, HUD_H, 4, vs.y), hc)
		a.draw_rect(Rect2(a.size.x - 4, HUD_H, 4, vs.y), hc)
	# Menus / pause / game over sit on a dimmed map (readable text).
	if mode != "play":
		a.draw_rect(Rect2(Vector2(0, HUD_H), vs), Color(0.0, 0.0, 0.0, 0.66))
	_draw_minimap(a)
	# Wave / weapon banner.
	if banner_t > 0.0 and mode == "play":
		var alpha: float = clampf(banner_t, 0.0, 1.0)
		var bw: float = float(banner.length()) * 6.4 + 20.0
		a.draw_rect(Rect2(Vector2((a.size.x - bw) * 0.5, HUD_H + 10), Vector2(bw, 17)), Color(0, 0, 0, 0.6 * alpha))
		a.draw_string(font, Vector2((a.size.x - bw) * 0.5 + 10, HUD_H + 23), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.98, 0.78, 0.32, alpha))
	# HUD strip: health bar, wave, score, kills, credits, weapon.
	a.draw_rect(Rect2(0, 0, a.size.x, HUD_H), Color(0.02, 0.03, 0.03))
	a.draw_rect(Rect2(2, 3, 80, 8), Color(0.2, 0.05, 0.05))
	a.draw_rect(Rect2(2, 3, 80.0 * clampf(hp / max_hp(), 0.0, 1.0), 8), Color(0.85, 0.2, 0.15))
	a.draw_string(font, Vector2(86, 11), "HP %d  W%d  SCORE %d  KILLS %d  %d CR  %s" % [int(maxf(hp, 0.0)), wave, score, kills, credits, WEAPONS[weapon]["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.95, 0.9))


func _draw_zombie(z: Dictionary, view: Rect2) -> void:
	var a: Control = _arena
	var zp: Vector2 = z["pos"]
	if not view.has_point(zp):
		return
	var kind: String = z["kind"]
	var kd: Dictionary = KINDS[kind]
	var c: Color = (kd["color"] as Color).lerp(Color.WHITE, 0.6 if float(z.get("flash", 0.0)) > 0.0 else 0.0)
	var zr: float = float(kd["r"])
	var sp: Vector2 = _w2s(zp)
	var to: Vector2 = (player - zp).normalized()
	match kind:
		"brute", "elite":
			if kind == "elite":
				a.draw_arc(sp, zr + 3.0, 0, TAU, 20, Color(1.0, 0.8, 0.25, 0.85), 2.0)
			a.draw_rect(Rect2(sp - Vector2(zr, zr * 0.8), Vector2(zr * 2, zr * 1.6)), c.darkened(0.5))
			a.draw_rect(Rect2(sp - Vector2(zr - 1.5, zr * 0.8 - 1.5), Vector2(zr * 2 - 3, zr * 1.6 - 3)), c)
			a.draw_line(sp, sp + to.rotated(0.7) * (zr + 5.0), c.darkened(0.3), 3.0)
			a.draw_line(sp, sp + to.rotated(-0.7) * (zr + 5.0), c.darkened(0.3), 3.0)
		"swarm":
			a.draw_circle(sp, zr, c)
			a.draw_circle(sp + to * 1.5, 1.0, Color(0.9, 0.2, 0.15))
		"runner":
			var tip: Vector2 = sp + to * (zr + 3.0)
			a.draw_colored_polygon(PackedVector2Array([tip, sp + to.rotated(2.4) * zr, sp + to.rotated(-2.4) * zr]), c)
			if float(z.get("lunge", 0.0)) > 1.2:
				a.draw_line(sp - to * 8.0, sp - to * 2.0, Color(c, 0.5), 2.0)
		"spitter":
			a.draw_circle(sp, zr, c.darkened(0.2))
			var winding: bool = float(z.get("windup", -1.0)) >= 0.0
			a.draw_circle(sp + to * 2.0, zr * 0.55, Color(0.6, 1.0, 0.45) if winding else c.lightened(0.2))
			if winding:
				a.draw_arc(sp, zr + 3.0, 0, TAU, 14, Color(0.6, 1.0, 0.45, 0.8), 1.5)
		"bloater":
			var fuse: float = float(z.get("fuse", -1.0))
			var swell: float = 1.0 + (maxf(fuse, 0.0) / FUSE_S) * 0.5
			a.draw_circle(sp, zr * swell, c.darkened(0.3))
			a.draw_circle(sp, zr * swell - 1.5, c if fuse < 0.0 or fmod(fuse * 10.0, 1.0) > 0.5 else Color(1.0, 0.9, 0.5))
			for i in 3:
				a.draw_circle(sp + Vector2.from_angle(i * 2.1) * zr * 0.5, 1.5, Color(0.5, 0.65, 0.3))
		"armored":
			a.draw_circle(sp, zr + 1.0, Color(0.2, 0.22, 0.25))
			a.draw_circle(sp, zr, c)
			a.draw_arc(sp, zr - 1.0, to.angle() - 1.2, to.angle() + 1.2, 8, Color(0.85, 0.88, 0.92), 2.0)
		_:
			a.draw_circle(sp, zr + 1.0, c.darkened(0.6))
			a.draw_circle(sp, zr, c)
			a.draw_line(sp, sp + to.rotated(0.5) * (zr + 3.0), c.darkened(0.3), 1.5)
			a.draw_line(sp, sp + to.rotated(-0.5) * (zr + 3.0), c.darkened(0.3), 1.5)
	if float(z["hp"]) < float(z["max"]):
		a.draw_rect(Rect2(sp + Vector2(-zr, -zr - 4.0), Vector2(2.0 * zr * clampf(float(z["hp"]) / float(z["max"]), 0, 1), 1.5)), Color(0.9, 0.3, 0.2))


func _draw_minimap(a: Control) -> void:
	var mw := 66.0
	var mh: float = mw * WORLD.size.y / WORLD.size.x
	var o := Vector2(a.size.x - mw - 3, HUD_H + 3)
	var k: float = mw / WORLD.size.x
	a.draw_rect(Rect2(o, Vector2(mw, mh)), Color(0, 0, 0, 0.55))
	for rd in roads:
		a.draw_rect(Rect2(o + rd.position * k, rd.size * k), Color(0.4, 0.4, 0.4, 0.6))
	for lm in landmarks:
		a.draw_rect(Rect2(o + (lm["rect"] as Rect2).position * k, (lm["rect"] as Rect2).size * k), Color(0.8, 0.7, 0.4, 0.7))
	for z in zombies:
		a.draw_rect(Rect2(o + (z["pos"] as Vector2) * k, Vector2(1, 1)), Color(0.9, 0.3, 0.25))
	a.draw_rect(Rect2(o + cam * k, view_size() * k), Color(1, 1, 1, 0.5), false, 1.0)
	a.draw_circle(o + player * k, 1.6, Color(0.6, 0.85, 1.0))


# ------------------------------------------------------------ save / load
func state_dict() -> Dictionary:
	return {"best": best, "best_wave": best_wave, "credits": credits, "ranks": ranks.duplicate(), "runs": runs, "unlocked": unlocked.keys(), "weapon": weapon}


func load_state(d: Dictionary) -> void:
	best = maxi(int(d.get("best", 0)), 0)
	best_wave = maxi(int(d.get("best_wave", 0)), 0)
	credits = maxi(int(d.get("credits", 0)), 0)
	runs = maxi(int(d.get("runs", 0)), 0)
	var rk: Dictionary = d.get("ranks", {})
	for id in UPGRADES:
		ranks[id] = clampi(int(rk.get(id, 0)), 0, int(UPGRADES[id][1]))
	unlocked = {"pistol": true}
	for w in Array(d.get("unlocked", [])):
		if WEAPONS.has(String(w)):
			unlocked[String(w)] = true
	weapon = String(d.get("weapon", "pistol"))
	if not unlocked.has(weapon):
		weapon = "pistol"
	# A saved game never resumes mid-run.
	mode = "title"
	zombies = []
	bullets = []
	spits = []
	pickups = []
	held = {}
	_refresh_overlay()
