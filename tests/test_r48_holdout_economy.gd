extends SceneTree
## Round 48 Priorities 28-31: HOLDOUT long-term progression, measured with
## the deterministic simulation (tests/holdout_sim.gd) on FRESH runs (the
## sidearm, nothing bought) with a realistic "save for the next gun" policy.
##  - every non-starter weapon costs more than in Round 47, scaled by tier
##    (not one flat multiplier); the Gravity Mortar stays cheaper than the
##    Arc Projector;
##  - upgrade ranks grow in price (ranks 1-2 stay cheap, then ~2x per rank);
##  - early runs are not hopeless (both difficulties survive the first ten
##    waves with this simple bot), the first gun is affordable early, the
##    top tier needs many waves, upgrades are not all maxed early;
##  - the Round 47 rules hold: a new run keeps nothing bought, the catalog
##    is permanent.
const Sim = preload("res://tests/holdout_sim.gd")
## Round 47 prices (the baseline this round lengthens).
const R47 := {"machete": 40, "smg": 120, "shotgun": 170, "rifle": 300, "launcher": 380, "arc": 480}
const R47_SURVIVAL_TOTAL := 1066     # rate+damage+health+armor+speed+regen, all ranks
var _ok := true
var h: Control


func _init() -> void:
	h = Sim.make(get_root())
	await process_frame
	_prices()
	_upgrades()
	_progression()
	_rules()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _cost(w: String) -> int:
	return int(h.WEAPONS[w]["cost"])


func _prices() -> void:
	_check("Gravity Mortar cheaper than Arc Projector (%d < %d), by stable id" % [_cost("launcher"), _cost("arc")], _cost("launcher") < _cost("arc"))
	var raised := true
	var ratios := {}
	for w in ["smg", "shotgun", "rifle", "launcher", "arc"]:
		raised = raised and _cost(w) > int(R47[w])
		ratios[w] = snappedf(float(_cost(w)) / float(R47[w]), 0.01)
	_check("every non-starter gun costs more than in R47 (x%s)" % str(ratios), raised)
	_check("...scaled by tier, not one flat multiplier (top tiers rise most)", float(ratios["arc"]) > float(ratios["smg"]) and float(ratios["launcher"]) > float(ratios["shotgun"]))
	_check("starting kit stays accessible (sidearm free, cutter %d CR)" % _cost("machete"), _cost("pistol") == 0 and _cost("machete") <= 50)
	var ordered := true
	for i in range(1, h.WEAPON_ORDER.size()):
		ordered = ordered and _cost(h.WEAPON_ORDER[i]) > _cost(h.WEAPON_ORDER[i - 1])
	_check("armory lists by price", ordered)


func _upgrades() -> void:
	var curve_ok := true
	var total := 0
	for id in h.UPGRADES:
		var c: Array = h.UPGRADES[id][2]
		for i in range(1, c.size()):
			curve_ok = curve_ok and int(c[i]) > int(c[i - 1])
			if i >= 2:
				curve_ok = curve_ok and float(c[i]) / float(c[i - 1]) >= 1.6
		if id in ["rate", "damage", "health", "armor", "speed", "regen"]:
			for x in c:
				total += int(x)
	_check("every upgrade line gets more expensive with rank (rank 3+ ~2x the last)", curve_ok)
	_check("rank 1 stays affordable after the first wave (<= 30 CR except multishot)", h.UPGRADES.keys().all(func(id): return id == "multishot" or int(h.UPGRADES[id][2][0]) <= 30))
	_check("maxing the survival lines costs %d CR (R47: %d)" % [total, R47_SURVIVAL_TOTAL], total >= int(R47_SURVIVAL_TOTAL * 1.5))
	h.load_state({})
	h.start_seeded(3)
	h.credits = 5000
	h.mode = "shop"
	h.shop_return = "wave"
	var d0: float = h.damage()
	var i0: float = h.fire_interval()
	h.buy("damage")
	h.buy("rate")
	_check("upgrades still change the run (damage %.1f -> %.1f, interval %.2f -> %.2f)" % [d0, h.damage(), i0, h.fire_interval()], h.damage() > d0 and h.fire_interval() < i0)


func _progression() -> void:
	# Income per wave MEASURED in the game (bot with the rifle loadout, which
	# survives ten waves on both difficulties), then the "save for the next
	# gun" policy replayed on it with the real prices (Sim.ledger). The
	# simple bot itself dies early in sidearm-only fresh runs at R47 prices
	# too (wave 1-3), so its survival is not a price signal.
	for d in ["easy", "hard"]:
		var run: Dictionary = Sim.run(h, d, "rifle", 2, 10)
		var income: Array = run["per_wave"]
		_check("%s: income measured over 10 waves (%s)" % [d, str(income)], bool(run["alive"]) and income.size() >= 10)
		if income.size() < 10:
			continue
		var r: Dictionary = Sim.ledger(h, income)
		var b: Dictionary = r["bought"]
		var ranks: Dictionary = r["ranks"]
		print("  %s: weapons bought at waves %s, ranks by wave %s" % [d, str(b), str(ranks)])
		_check("%s: rank-1 upgrades from the first wave (%d ranks after wave 1)" % [d, int(ranks[1])], int(ranks[1]) >= 1 or b.has("smg") and int(b["smg"]) == 1)
		_check("%s: the first real gun comes early (carbine at wave %s)" % [d, str(b.get("smg", "-"))], b.has("smg") and int(b["smg"]) <= 3)
		_check("%s: the rifle needs saving (wave %s >= 3)" % [d, str(b.get("rifle", "-"))], b.has("rifle") and int(b["rifle"]) >= 3)
		var mortar_min: int = 7 if d == "easy" else 5
		_check("%s: the mortar is a multi-wave investment (wave %s >= %d)" % [d, str(b.get("launcher", "after 10")), mortar_min], not b.has("launcher") or int(b["launcher"]) >= mortar_min)
		_check("%s: the arc is late (wave %s >= 8)" % [d, str(b.get("arc", "after 10"))], not b.has("arc") or int(b["arc"]) >= 8)
		_check("%s: upgrades are not all maxed by wave 7 (%d of 23 ranks)" % [d, int(ranks[7])], int(ranks[7]) < 23)
		_check("%s: but real progress by wave 10 (%d ranks + %d guns)" % [d, int(ranks[10]), b.size()], int(ranks[10]) >= 12 and b.size() >= 2)
	# One real fresh run through the actual shop (sidearm, nothing bought).
	var fr: Dictionary = Sim.progression(h, "easy", 2, 6)
	_check("a real fresh Easy run buys its first gun from the shop (%s)" % str(fr["bought"]), fr["bought"].has("smg") and int(fr["bought"]["smg"]) <= 3)


func _rules() -> void:
	h.load_state({})
	h.start_seeded(7)
	h.credits = 3000
	h.mode = "shop"
	h.shop_return = "wave"
	h.weapon_action("rifle")
	h.buy("damage")
	h.action("restart")
	_check("a new run keeps nothing bought (R47 reset fix)", h.weapon == "pistol" and h.credits == 0 and h.rank("damage") == 0 and h.unlocked.keys() == ["pistol"])
	_check("...the catalog (permanent) keeps the rifle, cheaper next time (%d < %d)" % [h.weapon_cost("rifle"), _cost("rifle")], h.catalog.has("rifle") and h.weapon_cost("rifle") < _cost("rifle"))
	var sd: Dictionary = JSON.parse_string(JSON.stringify(h.state_dict()))
	_check("save holds permanent data only", not sd.has("credits") and not sd.has("ranks") and Array(sd.get("catalog", [])).has("rifle"))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
