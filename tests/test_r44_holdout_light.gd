extends SceneTree
## Round 44 Priorities 11-13 / 15-16 / 20: Holdout modes + buildings, and
## the lighting calibration.
##  - EASY keeps the Round 43 balance; HARD: more zombies, faster pacing,
##    earlier variety, tougher growth, a higher (still bounded) alive cap;
##    best scores kept per difficulty; difficulty saved;
##  - buildings: real walls + door gaps, roof hidden only while inside,
##    interior collision, zombies come in through the doors, lurkers wait
##    inside, spewer acid forces repositioning; machete + launcher;
##  - a full HARD wave at the alive cap simulates well inside a frame;
##  - lighting: ambient slightly darker, ceiling strips brighter, Storage
##    floor strips dimmer than ceiling accents, breaker darkness kept,
##    interior lights no longer reach the exterior hull layer.
var _ok := true
var main: Node
var h: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	h = main.find_child("LaptopView", true, false)._log_screen.holdout
	_modes()
	_buildings()
	_combat()
	_perf()
	await _lighting()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _modes() -> void:
	h.load_state({})
	_check("default difficulty EASY", h.difficulty == "easy")
	var easy_n: int = h.wave_size(3)
	var easy_iv: float = 0.0
	h.wave = 3
	easy_iv = h.spawn_interval()
	var easy_kinds: int = h.kind_table().size()
	h.action("diff_hard")
	_check("title HARD button selects HARD", h.difficulty == "hard")
	h.wave = 3
	_check("HARD: more zombies per wave (%d vs %d)" % [h.wave_size(3), easy_n], h.wave_size(3) >= easy_n + 6)
	_check("HARD: faster spawning (%.2f vs %.2f s)" % [h.spawn_interval(), easy_iv], h.spawn_interval() < easy_iv * 0.8)
	_check("HARD: more variety earlier (wave 3: %d vs %d kinds)" % [h.kind_table().size(), easy_kinds], h.kind_table().size() > easy_kinds)
	# Round 46: the new HARD cap is 120 (step cost measured in test_r46_holdout_balance).
	_check("HARD: bounded alive cap (%d)" % h.max_alive(), h.max_alive() > 95 and h.max_alive() <= 120)
	h.start_seeded(2)
	h.score = 500
	h.hp = 0.0
	h.zombies = [{"pos": h.player, "hp": 999.0, "max": 999.0, "kind": "brute"}]
	h.step(0.05)
	_check("game over labelled HARD with the HARD best", h.mode == "over" and h._ov_title.text.find("HARD") != -1 and int(h.best_by["hard"]) >= 500)
	h.action("diff_easy")
	_check("EASY best kept separately", int(h.best_by["easy"]) < 500 and h.best == int(h.best_by["easy"]))
	h.action("diff_hard")
	var sd: Dictionary = JSON.parse_string(JSON.stringify(h.state_dict()))
	h.load_state({})
	h.load_state(sd)
	_check("difficulty + per-mode bests saved", h.difficulty == "hard" and int(h.best_by["hard"]) >= 500)
	var legacy := {"best": 321, "credits": 5}
	h.load_state(legacy)
	# Round 46: a Round 43 record was set in the old EASY balance, which no
	# longer exists -- kept (not lost) as the Classic Easy record.
	_check("a Round 43 save keeps its best (as the Classic Easy record)", h.difficulty == "easy" and int(h.legacy_best.get("classic_easy", {}).get("score", 0)) == 321)


func _buildings() -> void:
	h.start_seeded(3)
	_check("three enterable buildings (house, store, diner)", h.buildings.size() == 3 and h.buildings.map(func(b): return b["kind"]) == ["house", "store", "diner"])
	var house: Dictionary = h.buildings[0]
	var door: Dictionary = house["doors"][0]
	_check("doors are real gaps (outside and inside points free)", h.is_free(door["out"], h.PLAYER_R) and h.is_free(door["in"], h.PLAYER_R))
	h.zombies = []
	h.player = door["out"]
	var into: Vector2 = ((door["in"] as Vector2) - (door["out"] as Vector2)).normalized()
	_check("outside: the roof is on (not inside)", h.player_building() == -1)
	for i in 40:
		h.player = h.resolve(h.player + into * h.move_speed() * 0.05, h.PLAYER_R)
	_check("walking through the door: inside the HOUSE (roof hidden)", h.player_building() == 0)
	var r: Rect2 = house["rect"]
	h.player = Vector2(r.position.x + 30, r.position.y + 30)
	for i in 80:
		h.player = h.resolve(h.player + Vector2(-1, 0) * h.move_speed() * 0.05, h.PLAYER_R)
	_check("interior walls are solid (x %.0f >= %.0f)" % [h.player.x, r.position.x + h.WALL], h.player.x >= r.position.x + h.WALL + h.PLAYER_R - 0.5)
	var shots_blocked: bool = not h._segment_blocked(Vector2(r.position.x - 30, r.position.y + 30), Vector2(r.position.x + 30, r.position.y + 30), 0.0, true).is_empty()
	_check("walls stop bullets", shots_blocked)
	# A zombie outside finds its way in through a door.
	h.player = r.get_center() + Vector2(-50, 10)
	h.player = h.resolve(h.player, h.PLAYER_R)
	h.hp = 1e9
	var z: Dictionary = h.spawn_zombie("walker")
	z["pos"] = (door["out"] as Vector2) + Vector2(0, -40)
	var got_in := false
	for i in 600:
		h._fire_t = 999.0
		h.hp = 1e9
		h.step(0.05)
		if h.building_at(z["pos"]) == 0:
			got_in = true
			break
	_check("a walker outside comes in through the door", got_in)
	# Lurker waits inside a building the survivor is not in.
	h.player = Vector2(900, 600)
	h.zombies = []
	var lk: Dictionary = h.spawn_zombie("lurker")
	_check("lurker spawns dormant inside a building", lk.get("dormant", false) and h.building_at(lk["pos"]) != -1)
	var p0: Vector2 = lk["pos"]
	for i in 20:
		h._fire_t = 999.0
		h.step(0.05)
	_check("...and stays put while the survivor is far", (lk["pos"] as Vector2) == p0)
	h.player = h.resolve((lk["pos"] as Vector2) + Vector2(40, 0), h.PLAYER_R)
	h._fire_t = 999.0
	h.step(0.05)
	_check("...wakes when the survivor comes close", not lk.get("dormant", true))


func _combat() -> void:
	h.start_seeded(4)
	h.zombies = []
	h.player = Vector2(900, 650)
	var sp: Dictionary = h.spawn_zombie("spewer")
	sp["pos"] = h.player + Vector2(120, 0)
	for i in 60:
		h._fire_t = 999.0
		h.hp = h.max_hp()
		h.step(0.05)
	_check("spewer leaves acid puddles (%d)" % h.acid.size(), h.acid.size() >= 1)
	h.zombies = []
	h.acid = [{"pos": h.player, "life": 5.0}]
	var hp0: float = h.hp
	for i in 10:
		h.step(0.05)
	_check("standing in acid hurts (forces repositioning)", h.hp < hp0)
	h.acid = []
	h.credits = 5000             # Round 48 prices: enough for the cutter + the mortar
	h.weapon_action("machete")
	for k in 3:
		var z: Dictionary = h.spawn_zombie("walker")
		z["pos"] = h.player + Vector2(15, -8 + k * 8)
		z["hp"] = 100.0
	h._fire_at(h.nearest_zombie())
	_check("MACHETE: one swing hits every zombie in reach", h.zombies.filter(func(z): return float(z["hp"]) < 100.0).size() == 3)
	_check("MACHETE only reaches close zombies (range %.0f)" % h.weapon_range(), h.weapon_range() < 40.0)
	h.zombies = []
	h.weapon_action("launcher")
	for k in 4:
		var z2: Dictionary = h.spawn_zombie("walker")
		z2["pos"] = h.player + Vector2(100 + (k % 2) * 10, (k / 2) * 10)
		z2["hp"] = 100.0
	h._fire_at(h.nearest_zombie())
	for i in 30:
		h._step_grenades(0.05)
	_check("LAUNCHER: a lobbed grenade blasts a group (area damage)", h.zombies.filter(func(z): return float(z["hp"]) < 100.0).size() >= 3 and h.grenades.is_empty())


func _perf() -> void:
	h.load_state({})
	h.action("diff_hard")
	h.start_seeded(9)
	h.wave = 12
	h.zombies = []
	for i in h.max_alive():
		h.spawn_zombie()
	var t0: int = Time.get_ticks_usec()
	for i in 60:
		h.hp = 1e9
		h.step(1.0 / 60.0)
	var per: float = float(Time.get_ticks_usec() - t0) / 60.0 / 1000.0
	print("MEASURED: Holdout HARD step with %d zombies: %.2f ms" % [h.zombies.size(), per])
	_check("a full HARD wave at the alive cap simulates in < 8 ms per step (%.2f ms)" % per, per < 8.0)
	h.load_state({})


func _lighting() -> void:
	await process_frame
	var env: Environment = (main.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment
	_check("ambient slightly darker (%.2f, was 0.20)" % env.ambient_light_energy, env.ambient_light_energy < 0.2 and env.ambient_light_energy >= 0.15)
	var decor: Node = main.get_tree().get_first_node_in_group(&"station_decor")
	_check("ceiling accent strips brighter (glow %.2f, was 0.55)" % decor.STRIP_GLOW, decor.STRIP_GLOW > 0.55 and decor.STRIP_GLOW <= 0.9)
	var floor_glows: Array = decor.strips.filter(func(s): return float(s.get("glow", 0.0)) == decor.FLOOR_GLOW)
	_check("Storage floor strips dimmer than the ceiling accents (%d at %.2f)" % [floor_glows.size(), decor.FLOOR_GLOW], floor_glows.size() >= 2 and decor.FLOOR_GLOW < decor.STRIP_GLOW * 0.6)
	_check("Storage floor fill lights dimmer (%.2f, was 0.45)" % decor.storage_lights[0].light_energy, decor.storage_lights.all(func(l): return l.light_energy < 0.4))
	var ext: Node = main.get_tree().get_first_node_in_group(&"exterior")
	await process_frame
	_check("exterior meshes moved to the exterior layer only (%d)" % ext.exterior_meshes_moved, ext.exterior_meshes_moved > 100)
	var room: Light3D = main.get_node("Lights/Light_ControlRoom")
	_check("interior lights no longer light the exterior layer (%d masked)" % ext.interior_lights_masked, (room.light_cull_mask & ext.EXTERIOR) == 0 and ext.interior_lights_masked >= 15)
	var hull_mesh: GeometryInstance3D = ext.get_node("Hull").get_child(0)
	_check("a hull plate is outside every interior light's reach (layers %d)" % hull_mesh.layers, (hull_mesh.layers & room.light_cull_mask) == 0)
	var cam: Camera3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_check("...but every view still renders the exterior layer", (cam.cull_mask & ext.EXTERIOR) != 0)
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var snap: Dictionary = br.state_dict()
	br.trip(0, "TEST")
	await create_timer(0.7).timeout
	var dark: Array = decor.strips.filter(func(s): return s["zone"] == br.BREAKERS[0]["zone"] and (s["mat"] as StandardMaterial3D).emission.get_luminance() == 0.0)
	_check("breaker darkness kept: a tripped zone's strips go dark (%d)" % dark.size(), dark.size() > 0)
	br.load_dict(snap)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
