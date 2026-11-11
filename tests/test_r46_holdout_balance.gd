extends SceneTree
## Round 46 Priorities 3-4: HOLDOUT difficulty + weapon economy, measured
## with the deterministic simulation in tests/holdout_sim.gd.
##  - the old (Round 44/45) HARD balance is the new EASY, exactly;
##  - the new HARD is substantially harder (bigger / faster waves, earlier
##    variety, elites more often with a bigger escort, more ranged pressure,
##    fewer medkits) -- measured pressure, and still survivable;
##  - weapons: tiered prices; ARC PROJECTOR and GRAVITY MORTAR have
##    different strengths (mortar: dense packs; arc: fast scattered packs,
##    stuns); rifle = single target; top tier needs several waves of income;
##  - fixes: swept bullet hits (fast rounds no longer skip small creatures),
##    hidden lurkers come out when they are all that is left;
##  - save migration: old Hard records -> Easy, old Easy kept as a legacy
##    record, unlocked weapons kept;
##  - performance at the active-enemy cap.
const Sim = preload("res://tests/holdout_sim.gd")
var _ok := true
var h: Control


func _init() -> void:
	await process_frame
	h = Sim.make(get_root())
	await process_frame
	_difficulty_values()
	_weapons()
	_economy()
	_pressure()
	_fixes()
	_migration()
	_performance()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _difficulty_values() -> void:
	var old_hard := {"count": 1.75, "interval": 0.7, "unlock_shift": 2, "hp_growth": 0.12, "speed": 1.08, "max_alive": 95, "credits": 1.3, "elite_every": 4}
	var e: Dictionary = h.DIFFICULTY["easy"]
	var same := true
	for k in old_hard:
		same = same and is_equal_approx(float(e[k]), float(old_hard[k]))
	_check("new EASY = the old HARD balance (all values)", same)
	var hd: Dictionary = h.DIFFICULTY["hard"]
	h.difficulty = "easy"
	var ez5: int = h.wave_size(5)
	h.difficulty = "hard"
	var hz5: int = h.wave_size(5)
	_check("HARD: wave 5 sends %d vs %d (>= 1.35x)" % [hz5, ez5], hz5 >= int(ez5 * 1.35))
	_check("HARD: faster spawns, earlier variety, elites every %d waves with +%d escort" % [hd["elite_every"], hd["escort_extra"]], float(hd["interval"]) < float(e["interval"]) and int(hd["unlock_shift"]) > int(e["unlock_shift"]) and int(hd["elite_every"]) < int(e["elite_every"]) and int(hd["escort_extra"]) > 0)
	_check("HARD: more ranged pressure, fewer medkits, faster creatures (not just health)", float(hd["ranged"]) > 1.2 and float(hd["medkits"]) < 1.0 and float(hd["speed"]) > float(e["speed"]))
	h.difficulty = "easy"


func _weapons() -> void:
	var r := {}
	for w in ["rifle", "arc", "launcher"]:
		r[w] = {"dense": Sim.clear_time(h, w, "armored", 20, 90.0, 8.0), "elite": Sim.clear_time(h, w, "elite", 1, 90.0),
			"scatter": Sim.charge_test(h, w, "runner", 9, 170.0, 40.0)}
	print("  weapons: ", r)
	_check("GRAVITY MORTAR is the dense-pack weapon (%.1f s vs arc %.1f s)" % [r["launcher"]["dense"], r["arc"]["dense"]], r["launcher"]["dense"] < r["arc"]["dense"] * 0.7 and r["launcher"]["dense"] < r["rifle"]["dense"])
	_check("ARC PROJECTOR controls fast scattered packs (damage taken %.0f vs mortar %.0f)" % [r["arc"]["scatter"][1], r["launcher"]["scatter"][1]], float(r["arc"]["scatter"][1]) < float(r["launcher"]["scatter"][1]) * 0.5)
	_check("...the mortar is weak against a lone elite (%.1f s vs rifle %.1f s)" % [r["launcher"]["elite"], r["rifle"]["elite"]], r["launcher"]["elite"] > r["rifle"]["elite"] * 1.5)
	_check("PULSE RIFLE is the single-target weapon (elite %.1f s)" % r["rifle"]["elite"], r["rifle"]["elite"] < r["arc"]["elite"] and r["rifle"]["elite"] < r["launcher"]["elite"])
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/holdout_game.gd")
	_check("mortar arming distance + gravity well; arc stun + chain falloff", src.find("MORTAR_MIN") != -1 and src.find("wells.append") != -1 and src.find("ARC_STUN") != -1 and src.find("ARC_FALLOFF") != -1)


func _economy() -> void:
	var c: Dictionary = {}
	for w in h.WEAPONS:
		c[w] = int(h.WEAPONS[w]["cost"])
	_check("tiers: starter < intermediate < advanced < top (%s)" % str(c), c["pistol"] == 0 and c["machete"] <= 50 and c["smg"] > c["machete"] and c["shotgun"] > c["smg"] and c["rifle"] > c["shotgun"] and c["arc"] > c["rifle"] and c["launcher"] > c["arc"])
	var run: Dictionary = Sim.run(h, "easy", "arc", 1, 6)
	var pw: Array = run["per_wave"]
	var cum: Array = []
	var acc := 0
	for x in pw:
		acc += int(x)
		cum.append(acc)
	print("  easy income per wave: ", pw, " cumulative: ", cum)
	_check("income measured over several waves (%d)" % pw.size(), pw.size() >= 4)
	if pw.size() >= 4:
		_check("top tier is a real investment: > 3 waves of early income (wave-1 income %d)" % int(pw[0]), c["arc"] > int(pw[0]) * 3 and c["launcher"] > cum[1])
		_check("...but reachable by deliberate saving (%d CR after %d waves >= %d)" % [cum[cum.size() - 1], cum.size(), c["launcher"]], cum[cum.size() - 1] >= c["launcher"])
		_check("intermediate weapons need meaningful savings (> wave-1 income)", c["smg"] > int(pw[0]) and c["shotgun"] > int(pw[0]))


func _pressure() -> void:
	# Same wave, same seeds, same weapon: what the first 30 s of WAVE 4 throw
	# at the survivor (waves are gated on clearing, so a whole-run count
	# would mostly measure the bot's kill speed).
	var spawned := {}
	var peak := {}
	var ranged := {}
	for d in ["easy", "hard"]:
		spawned[d] = 0
		peak[d] = 0
		ranged[d] = 0
		for seed in [11, 12, 13]:
			h.load_state({"unlocked": h.WEAPONS.keys(), "weapon": "rifle", "difficulty": d})
			h.difficulty = d
			h.start_seeded(seed)
			h._begin_wave(4)
			var seen := {}
			var t := 0.0
			while t < 30.0 and h.mode == "play":
				Sim._kite(h)
				h.hp = 1e9
				h.step(Sim.DT)
				peak[d] = maxi(int(peak[d]), h.zombies.size())
				for z in h.zombies:
					if not seen.has(z["id"]):
						seen[z["id"]] = true
						if z["kind"] in ["spitter", "spewer"]:
							ranged[d] = int(ranged[d]) + 1
				t += Sim.DT
			spawned[d] = int(spawned[d]) + seen.size()
	_check("HARD wave 4: %d creatures in 30 s vs %d (>= 1.3x)" % [spawned["hard"], spawned["easy"]], int(spawned["hard"]) >= int(spawned["easy"]) * 1.3)
	_check("HARD wave 4: peak %d at once vs %d (>= 1.3x)" % [peak["hard"], peak["easy"]], int(peak["hard"]) >= int(peak["easy"]) * 1.3)
	_check("HARD wave 4: more ranged creatures (%d vs %d)" % [ranged["hard"], ranged["easy"]], int(ranged["hard"]) > int(ranged["easy"]))
	var best_hard := 0
	for seed in [1, 2]:
		best_hard = maxi(best_hard, int(Sim.run(h, "hard", "arc", seed, 4)["wave"]))
	_check("HARD is not impossible: the simple bot still clears %d waves" % best_hard, best_hard >= 2)


func _fixes() -> void:
	var t: float = Sim.clear_time(h, "rifle", "runner", 6, 60.0, 18.0)
	_check("swept hits: the fast rifle round no longer skips small creatures (6 runners in %.1f s)" % t, t < 15.0)
	h.load_state({"unlocked": ["pistol"], "weapon": "pistol", "difficulty": "easy"})
	h.start_seeded(5)
	h._to_spawn = 0
	h.zombies = []
	var lz: Dictionary = h.spawn_zombie("lurker")
	lz["dormant"] = true
	lz["pos"] = h._lurk_spot()
	h.step(Sim.DT)
	_check("only hidden lurkers left -> they stir and come out", not h.zombies.is_empty() and not bool(h.zombies[0].get("dormant", false)))


func _migration() -> void:
	h.load_state({"best": 900, "best_wave": 9, "credits": 75, "unlocked": ["pistol", "arc"], "weapon": "arc", "difficulty": "hard",
		"best_by": {"easy": 1500, "hard": 900}, "best_wave_by": {"easy": 14, "hard": 9}})
	_check("old save: Hard record -> Easy (same balance)", int(h.best_by["easy"]) == 900 and int(h.best_wave_by["easy"]) == 9 and int(h.best_by["hard"]) == 0)
	_check("old save: Easy record kept as a legacy record (never deleted)", int(h.legacy_best.get("classic_easy", {}).get("score", 0)) == 1500)
	_check("old save: unlocked weapons + credits kept", h.unlocked.has("arc") and h.weapon == "arc" and h.credits == 75)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(h.state_dict()))
	h.load_state(sd)
	_check("new save round-trip: no double migration", int(h.best_by["easy"]) == 900 and int(h.legacy_best["classic_easy"]["score"]) == 1500)


func _performance() -> void:
	h.load_state({"unlocked": ["launcher"], "weapon": "launcher", "difficulty": "hard"})
	h.difficulty = "hard"
	h.start_seeded(9)
	h._to_spawn = 0
	h.zombies = []
	for i in h.max_alive():
		h.spawn_zombie(["walker", "runner", "spitter", "swarm", "armored"][i % 5])
	var t0: int = Time.get_ticks_usec()
	for i in 120:
		h.hp = 1e9
		h._to_spawn = 0
		h.step(Sim.DT)
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / 120.0
	_check("performance: %d creatures at the cap, %.2f ms per simulation step (< 4.5 ms)" % [h.max_alive(), ms], ms < 4.5)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
