extends SceneTree
## Round 43 Priorities 2-5: HOLDOUT as a miniature roguelike.
##  - a scrolling world larger than the screen; the camera follows; named
##    landmarks; deterministic map; consistent collision (the survivor and
##    zombies never end up inside a building, car or tree); bullets stop at
##    solid obstacles;
##  - seven enemy kinds with distinct behaviour (swarm packs, runner lunge,
##    spitter keeps distance + telegraphed dodgeable glob, brute knock-back,
##    bloater fuse + burst, armour) and an elite every fifth wave;
##  - five weapons with real trade-offs; unlocks; upgrades incl. magnet and
##    crit that change the simulation; milestones; banners;
##  - persistence of wallet / ranks / weapons / best (never an active run);
##  - game input never moves the technician.
var _ok := true
var main: Node
var h: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	h = main.find_child("LaptopView", true, false)._log_screen.holdout
	_world()
	_enemies()
	_weapons_upgrades()
	_loop_and_save()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _world() -> void:
	h.start_seeded(1)
	var vs: Vector2 = h.view_size()
	_check("world (%s) much larger than the view (%s)" % [h.WORLD.size, vs], h.WORLD.size.x > vs.x * 3.0 and h.WORLD.size.y > vs.y * 3.0)
	_check("landmarks: %s" % str(h.landmark_names()), h.landmark_names().size() >= 6 and "CREW HAB" in h.landmark_names() and "BIODOME" in h.landmark_names())     # Round 45 space retheme
	_check("roads, cars, barricades, fences, trees, streetlights, supply points", h.roads.size() == 4 and h.obstacles.any(func(o): return o["kind"] == "car") and h.obstacles.any(func(o): return o["kind"] == "barricade") and h.obstacles.any(func(o): return o["kind"] == "fence") and h.trees.size() > 10 and h.lights.any(func(l): return l["broken"]) and h.supply_points.size() >= 4)
	var c0: Vector2 = h.cam
	h.held = {KEY_D: true}
	for i in 120:
		h.step(1.0 / 30.0)
	h.held = {}
	_check("the camera follows the survivor (cam %s -> %s)" % [c0, h.cam], h.cam.x > c0.x + 30.0)
	var lm1: Array = h.obstacles.map(func(o): return o["rect"])
	h.build_map()
	_check("deterministic map (same layout every time)", h.obstacles.map(func(o): return o["rect"]) == lm1)
	# Collision: walk into the MOTEL for 3 s -- never inside it.
	var motel: Rect2 = h.landmarks.filter(func(l): return l["name"] == "CREW HAB")[0]["rect"]
	h.player = Vector2(motel.get_center().x, motel.end.y + 20)
	h.held = {KEY_W: true}
	h.zombies = []
	for i in 90:
		h.step(1.0 / 30.0)
	h.held = {}
	_check("walls are solid (survivor stops at the MOTEL, y %.0f >= %.0f)" % [h.player.y, motel.end.y], h.player.y >= motel.end.y + h.PLAYER_R - 0.5)
	_check("survivor always on free ground", h.is_free(h.player, h.PLAYER_R - 0.5))
	# Bullets stop at a building.
	h.player = Vector2(motel.get_center().x, motel.end.y + 30)
	h.bullets = [{"pos": h.player, "vel": Vector2(0, -300), "dmg": 10.0, "life": 2.0, "pierce": 0, "ap": false, "hit": {}}]
	for i in 10:
		h._step_bullets(0.05)
	_check("bullets stop at solid buildings", h.bullets.is_empty())
	# Zombies steer around obstacles and never stand inside one.
	h.player = Vector2(900, 600)
	h.zombies = []
	for i in 30:
		h.spawn_zombie()
	for i in 200:
		h.hp = h.max_hp()
		h._fire_t = 999.0
		h.step(0.05)
	var inside: int = h.zombies.filter(func(z): return not h.is_free(z["pos"], float(h.KINDS[z["kind"]]["r"]) * 0.5)).size()
	_check("no zombie ends up inside an obstacle (%d)" % inside, inside == 0)


func _enemies() -> void:
	h.start_seeded(3)
	_check("nine enemy kinds + elite with different stats (R44: + lurker, spewer)", h.KINDS.size() == 10 and h.KINDS["runner"]["speed"] > h.KINDS["walker"]["speed"] and h.KINDS["brute"]["hp"] > 3.0 * h.KINDS["walker"]["hp"] and h.KINDS["swarm"]["r"] < h.KINDS["walker"]["r"])
	h.wave = 1
	# Round 46: the old Hard balance is the new Easy (variety unlocks 2 waves
	# earlier) -- wave 1 is still a small, mostly-walker table.
	_check("wave 1 table: walkers + at most two early kinds (R46 Easy)", h.kind_table().size() <= 3 and h.kind_table()[0][0] == "walker")
	h.wave = 7
	var seen: Dictionary = {}
	for i in 400:
		seen[h._pick_kind()] = true
	_check("wave 7 draws every kind (%s)" % str(seen.keys()), seen.size() == 9)
	# Swarm arrives as a pack.
	h.zombies = []
	h._rng.seed = 1
	var guard := 0
	while not h.zombies.any(func(z): return z["kind"] == "swarm") and guard < 200:
		h.zombies = []
		h._spawn_group()
		guard += 1
	_check("swarm spawns as a pack (%d)" % h.zombies.size(), h.zombies.size() >= 5)
	# Spitter keeps its distance and telegraphs a dodgeable glob.
	h.zombies = []
	h.spits = []
	h.player = Vector2(900, 600)
	var sp: Dictionary = h.spawn_zombie("spitter")
	sp["pos"] = h.player + Vector2(60, 0)
	for i in 20:
		h._fire_t = 999.0
		h.hp = h.max_hp()
		h.step(0.05)
	_check("spitter backs off to firing range (%.0f px)" % (sp["pos"] as Vector2).distance_to(h.player), (sp["pos"] as Vector2).distance_to(h.player) > 70.0)
	var wound := false
	for i in 80:
		h._fire_t = 999.0
		h.step(0.05)
		if float(sp.get("windup", -1.0)) >= 0.0:
			wound = true
		if not h.spits.is_empty():
			break
	_check("spitter telegraphs (wind-up) before a glob is fired", wound and not h.spits.is_empty())
	var g: Dictionary = h.spits[0]
	_check("the glob is slow enough to dodge (%.0f px/s vs survivor %.0f)" % [(g["vel"] as Vector2).length(), h.move_speed()], (g["vel"] as Vector2).length() < h.move_speed() * 1.3)
	var hp0: float = h.hp
	var side: Vector2 = (g["vel"] as Vector2).orthogonal().normalized()
	h.zombies = []
	h.held = {}
	for i in 60:
		h.player = h.resolve(h.player + side * h.move_speed() * 0.05, h.PLAYER_R)
		h._step_spits(0.05)
	_check("sidestepping dodges it (no damage)", h.hp == hp0)
	# Runner lunges.
	h.zombies = []
	var rn: Dictionary = h.spawn_zombie("runner")
	rn["pos"] = h.player + Vector2(50, 0)
	h._fire_t = 999.0
	h.step(0.05)
	_check("runner lunges when close", float(rn["lunge"]) > 1.2)
	# Brute knock-back.
	h.zombies = []
	h.player = Vector2(900, 600)
	var br: Dictionary = h.spawn_zombie("brute")
	br["pos"] = h.player + Vector2(10, 0)
	var p0: Vector2 = h.player
	h._fire_t = 999.0
	h.step(0.02)
	_check("brute hits hard and knocks back (%.0f px)" % p0.distance_to(h.player), h.player.distance_to(p0) > 8.0)
	# Bloater: visible fuse, then a burst that also hurts zombies.
	h.zombies = []
	h.hp = h.max_hp()
	var bl: Dictionary = h.spawn_zombie("bloater")
	bl["pos"] = h.player + Vector2(16, 0)
	var wk: Dictionary = h.spawn_zombie("walker")
	wk["pos"] = h.player + Vector2(30, 10)
	wk["hp"] = 20.0
	h._fire_t = 999.0
	h.step(0.05)
	_check("bloater starts a visible fuse instead of biting", float(bl["fuse"]) >= 0.0)
	var hpb: float = h.hp
	for i in 20:
		h._fire_t = 999.0
		h.step(0.05)
	_check("...then bursts: survivor and nearby zombie hurt", h.hp < hpb and not h.zombies.has(bl) and float(wk["hp"]) < 20.0)
	# Armour: only armour-piercing weapons do full damage.
	var ar := {"pos": Vector2.ZERO, "hp": 100.0, "max": 100.0, "kind": "armored"}
	h._damage_zombie(ar, 10.0, false)
	var plain: float = 100.0 - float(ar["hp"])
	ar["hp"] = 100.0
	h._damage_zombie(ar, 10.0, true)
	_check("armored: %.1f from normal rounds vs %.1f from AP" % [plain, 100.0 - float(ar["hp"])], plain < 5.0 and 100.0 - float(ar["hp"]) >= 9.9)
	# Elite on every fifth wave.
	h.start_seeded(4)
	h._begin_wave(int(h.diff()["elite_every"]))      # Round 46: Easy elites every 4th wave
	h._to_spawn = 1
	h._spawn_t = 0.0
	h._fire_t = 999.0
	h.step(0.05)
	_check("an elite wave ends with an ELITE + banner", h.zombies.any(func(z): return z["kind"] == "elite") and h.banner.find("ELITE") != -1)


func _weapons_upgrades() -> void:
	h.start_seeded(5)
	h.credits = 0
	_check("seven weapons (R44: + machete, launcher), pistol owned", h.WEAPONS.size() == 7 and h.unlocked.has("pistol") and h.weapon == "pistol")
	_check("locked weapon refused without credits", not h.weapon_action("rifle") and h.message.find("Need") != -1 and h.weapon == "pistol")
	h.credits = 1000
	_check("unlock = notification + equipped", h.weapon_action("smg") and h.weapon == "smg" and h.banner.find("NEW WEAPON") != -1)
	var rates := {}
	for w in h.WEAPON_ORDER:
		h.unlocked[w] = true
		h.weapon_action(w)
		rates[w] = [h.fire_interval(), h.damage(), h.weapon_range()]
	_check("SMG fires fastest, RIFLE hits hardest and reaches furthest, SHOTGUN shortest", rates["smg"][0] < rates["pistol"][0] and rates["rifle"][1] > rates["pistol"][1] * 2.0 and rates["rifle"][2] > rates["pistol"][2] and rates["shotgun"][2] < rates["pistol"][2])
	h.player = Vector2(900, 600)
	h.zombies = []
	var z: Dictionary = h.spawn_zombie("walker")
	z["pos"] = h.player + Vector2(40, 0)
	h.weapon_action("shotgun")
	h.bullets = []
	h._fire_at(z)
	_check("SHOTGUN: a cone of %d pellets" % h.bullets.size(), h.bullets.size() == 6)
	h.weapon_action("rifle")
	h.bullets = []
	h._fire_at(z)
	_check("RIFLE: a piercing, armour-piercing round", h.bullets.size() == 1 and int(h.bullets[0]["pierce"]) >= 3 and bool(h.bullets[0]["ap"]))
	h.weapon_action("arc")
	h.zombies = []
	for k in 4:
		var zz: Dictionary = h.spawn_zombie("walker")
		zz["pos"] = h.player + Vector2(40 + k * 30, 0)
		zz["hp"] = 100.0
	h._fire_at(h.nearest_zombie())
	_check("ARC: an instant bolt chaining through %d zombies" % h.zombies.filter(func(q): return float(q["hp"]) < 100.0).size(), h.zombies.filter(func(q): return float(q["hp"]) < 100.0).size() >= 3 and not h.beams.is_empty())
	# Magnet + crit really change the run.
	var m0: float = h.magnet_radius()
	h.buy("magnet")
	h.pickups = [{"pos": h.player + Vector2(m0 + 8.0, 0), "kind": "scrap", "value": 5, "life": 10.0}]
	var c0: int = h.credits
	for i in 20:
		h._step_pickups(0.05)
	_check("MAGNET: scrap just outside the old radius is now collected (+%d)" % (h.credits - c0), h.credits == c0 + 5)
	_check("CRIT: rank gives a real chance", h.crit_chance() == 0.0 and h.buy("crit") and h.crit_chance() > 0.0)
	var hp_full: float = h.max_hp()
	h.buy("health")
	_check("MAX HEALTH raises the cap", h.max_hp() > hp_full)
	h.pickups = [{"pos": h.player, "kind": "medkit", "value": 25, "life": 10.0}]
	h.hp = 10.0
	h._step_pickups(0.05)
	_check("medkits heal", h.hp > 30.0)


func _loop_and_save() -> void:
	h.start_seeded(6)
	h._begin_wave(5)
	h._to_spawn = 0
	h.zombies = []
	var c0: int = h.credits
	h.step(0.05)
	_check("wave 5 cleared: milestone bonus + armory", h.mode == "shop" and h.message.find("MILESTONE") != -1 and h.credits > c0 + 25)
	h.action("continue")
	h.hp = 1.0
	h.zombies = [{"pos": h.player, "hp": 999.0, "max": 999.0, "kind": "brute"}]
	h.step(0.05)
	_check("death -> summary with wave / kills / best", h.mode == "over" and h._ov_text.text.find("Wave 6") != -1 and h.best_wave >= 6)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(h.state_dict()))
	h.load_state({})
	_check("blank load resets to pistol", h.weapon == "pistol" and h.unlocked.size() == 1)
	h.load_state(sd)
	_check("save/load: weapons, equipped, ranks, best wave persist; never a live run", h.unlocked.has("arc") and h.weapon == "arc" and h.rank("magnet") == 1 and h.best_wave >= 6 and h.mode == "title" and h.zombies.is_empty())
	var fb: Node3D = main.get_node("FreeMoveBody")
	var p: Vector3 = fb.global_position
	h.start_seeded(7)
	var e := InputEventKey.new()
	e.keycode = KEY_A
	e.pressed = true
	h._gui_input(e)
	for i in 10:
		h.step(0.05)
	e.pressed = false
	h._gui_input(e)
	_check("game keys never move the technician", fb.global_position.distance_to(p) < 0.01)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
