extends RefCounted
## Round 46: deterministic HOLDOUT balance simulation (shared by the
## balance test and by developer tuning runs). Pure step() driving -- no
## rendering, fixed seeds, fixed dt -- so results are reproducible.
##
## Bot: kites away from nearby creatures (weighted by proximity), drifts
## back toward the start when nothing is close, and is fully automatic
## like the player's weapon. It is a CONSISTENT baseline, not a good
## player: absolute waves matter less than comparisons (Easy vs Hard,
## weapon vs weapon).

const DT := 1.0 / 30.0


static func make(root: Node) -> Control:
	var h: Control = load("res://scripts/ui/holdout_game.gd").new()
	h.size = Vector2(800, 450)
	root.add_child(h)
	return h


static func _kite(h: Control) -> void:
	# Threat field: repulsion from close creatures + an ORBIT component
	# (circle the pack instead of backing into walls).
	var away := Vector2.ZERO
	var centroid := Vector2.ZERO
	var nclose := 0
	for z in h.zombies:
		if bool(z.get("dormant", false)):
			continue
		var d: Vector2 = h.player - (z["pos"] as Vector2)
		var l: float = d.length()
		if l < 120.0 and l > 0.01:
			away += d / l * (120.0 - l)
			centroid += z["pos"]
			nclose += 1
	var want := Vector2.ZERO
	if nclose > 0:
		centroid /= nclose
		var tang: Vector2 = (h.player - centroid).orthogonal().normalized()
		want = away.normalized() + tang * 0.8
	else:
		var nz: Dictionary = {}
		var nd: float = INF
		for z in h.zombies:
			# (dormant lurkers too: a wave ends only when they are found)
			if h.player.distance_to(z["pos"]) < nd:
				nd = h.player.distance_to(z["pos"])
				nz = z
		if not nz.is_empty() and (nd > h.weapon_range() * 0.8 or h.building_at(nz["pos"]) != h.player_building()):
			want = (_route(h, nz["pos"]) - h.player).normalized()
		elif h.player.distance_to(h.START) > 60.0:
			want = (h.START - h.player).normalized() * 0.5
	h.held = {}
	if want.length() < 0.05:
		return
	# Pick the best FREE heading among 8 (the input is 8-way).
	var best := Vector2.ZERO
	var best_s: float = -INF
	var stepl: float = h.move_speed() * 0.25
	for k in 8:
		var dir: Vector2 = Vector2.from_angle(k * TAU / 8.0)
		var to: Vector2 = h.resolve(h.player + dir * stepl, h.PLAYER_R)
		var free: float = (to - h.player).length() / stepl
		var sc: float = dir.dot(want.normalized()) + free * 1.2
		for z in h.zombies:
			var dd: float = to.distance_to(z["pos"])
			if dd < 40.0:
				sc -= (40.0 - dd) / 40.0 * 1.5
		if sc > best_s:
			best_s = sc
			best = dir
	if best.x > 0.38: h.held[KEY_D] = true
	if best.x < -0.38: h.held[KEY_A] = true
	if best.y > 0.38: h.held[KEY_S] = true
	if best.y < -0.38: h.held[KEY_W] = true


## Next waypoint toward `goal` through building doors (mirrors nav_goal()).
static func _route(h: Control, goal: Vector2) -> Vector2:
	var gb: int = h.building_at(goal)
	var pb: int = h.player_building()
	if gb == pb:
		return goal
	if pb != -1:
		var d: Dictionary = h._nearest_door(pb, h.player)
		return d["out"] if h.player.distance_to(d["in"]) < 8.0 or h.player.distance_to(d["at"]) < 10.0 else d["in"]
	var d2: Dictionary = h._nearest_door(gb, h.player)
	return d2["in"] if h.player.distance_to(d2["out"]) < 8.0 or h.player.distance_to(d2["at"]) < 10.0 else d2["out"]


## One run: returns {wave, kills, time, credits, per_wave_credits: Array}.
static func run(h: Control, difficulty: String, weapon: String, seed: int, max_wave: int = 14, ranks: Dictionary = {}, kite: bool = true, buy: bool = true) -> Dictionary:
	h.load_state({"difficulty": difficulty})
	h.difficulty = difficulty
	# Round 47: a run starts with the sidearm and nothing bought; the
	# balance tools hand the run its loadout explicitly.
	h.start_seeded(seed, {"unlocked": h.WEAPONS.keys(), "weapon": weapon, "ranks": ranks, "credits": 0})
	var t: float = 0.0
	var per_wave: Array = []
	var c0: int = h.credits
	while t < 60.0 * 25.0:
		if h.mode == "shop":
			per_wave.append(h.credits - c0)
			if buy:
				# A steady upgrade policy (cheapest useful rank first).
				var bought := true
				while bought:
					bought = false
					var best_id: String = ""
					var best_c: int = 1 << 30
					for id in ["damage", "rate", "health", "armor", "regen", "speed"]:
						var cst: int = h.upgrade_cost(id)
						if cst > 0 and cst < best_c:
							best_c = cst
							best_id = id
					if best_id != "" and h.credits >= best_c:
						bought = h.buy(best_id)
			c0 = h.credits
			if h.wave >= max_wave:
				break
			h.action("continue")
			continue
		if h.mode != "play":
			break
		if kite:
			_kite(h)
		h.step(DT)
		t += DT
	var cleared: int = h.wave - (0 if h.mode == "shop" else 1)
	return {"wave": cleared, "kills": h.kills, "time": t, "credits": h.run_credits, "per_wave": per_wave, "alive": h.mode == "shop"}


## Time (s) for a stationary survivor to kill a pack: `n` of `kind`
## clustered `dist` px away (creatures held in place: pure weapon output).
static func clear_time(h: Control, weapon: String, kind: String, n: int, dist: float, spacing: float = 9.0, ranks: Dictionary = {}, pinned: bool = true) -> float:
	h.load_state({"difficulty": "easy"})
	h.start_seeded(7, {"unlocked": h.WEAPONS.keys(), "weapon": weapon, "ranks": ranks})
	h._to_spawn = 0
	h.zombies = []
	var centre: Vector2 = h.player + Vector2(dist, 0)
	var cols: int = int(ceil(sqrt(float(n))))
	for i in n:
		var z: Dictionary = {"pos": centre + Vector2((i % cols) - cols * 0.5, (i / cols) - cols * 0.5) * spacing, "hp": float(h.KINDS[kind]["hp"]), "max": float(h.KINDS[kind]["hp"]), "kind": kind}
		h._norm(z)
		h.zombies.append(z)
	var orig: Dictionary = {}
	for z in h.zombies:
		orig[z["id"]] = z["pos"]
	var t: float = 0.0
	h.hp = 1e9
	while t < 120.0:
		if h.zombies.filter(func(z): return float(z["hp"]) > 0.0).is_empty():
			return t
		h._to_spawn = 0
		h.step(DT)
		h.hp = 1e9
		if pinned:
			for z in h.zombies:
				if orig.has(z["id"]):
					z["pos"] = orig[z["id"]]      # pinned: pure weapon output
		t += DT
		if h.mode != "play":
			return t
	return t


## A charging pack against a stationary (invulnerable) survivor: returns
## [seconds to clear, damage the survivor took] -- crowd CONTROL, not just
## kill speed (stuns / slows keep creatures off the survivor).
static func charge_test(h: Control, weapon: String, kind: String, n: int, dist: float, spacing: float) -> Array:
	h.damage_taken = 0.0
	var t: float = clear_time(h, weapon, kind, n, dist, spacing, {}, false)
	return [t, h.damage_taken]
