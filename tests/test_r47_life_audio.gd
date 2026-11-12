extends SceneTree
## Round 47 Priorities 20-31: physical sound, the inner voice, the Living
## Quarters layout and Holdout.
##   ACOUSTIC PATH   positional sounds attenuate with distance and with every
##                   wall between ear and source: the airlock knock is
##                   distant + muffled from the Control Room / Junction /
##                   Engineering, close + clear inside the airlock / at the
##                   hatch; the window knock comes from the port itself;
##   LIFE SOUNDS     drinking, tea, eating, brushing, watering each play
##                   their OWN sound from where they happen -- and nothing
##                   plays for an action that did not happen;
##   THOUGHTS        meals / tea / water react as rotating inner thoughts
##                   (no HUD remark, no assistant), both languages;
##   VOICE           spoken thoughts only with a natural local voice,
##                   otherwise captions -- reported honestly;
##   QUARTERS        the sink in front of the mirror is gone, the hygiene
##                   niche (toothbrush + water saver) works, the mirror is
##                   floor-length and nothing stands in front of it;
##   HOLDOUT         Mortar cheaper than Arc (stable ids), every new run
##                   starts fresh, the catalog persists, old saves migrate
##                   visibly, purchases only inside a run, per-run economy.
const Sim = preload("res://tests/holdout_sim.gd")
var _ok := true
var main: Node
var dp: Node
var se: Node
var q: Node
var fb: Node
var lp: Node3D
var player: Node3D
var cam: Camera3D
var snd: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	dp = main.get_node("DayPlan")
	se = main.get_node("StoryEvents")
	q = main.get_node("Equipment/QuartersLife")
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	cam = lp.get_node("PitchPivot/Camera3D")
	snd = main.get_tree().get_first_node_in_group(&"station_sounds")
	main.get_node("DayPlan/Clearance").dev_set(3)
	main.get_node("StationAI").set_enabled(false)
	await _acoustics()
	await _life_sounds_and_thoughts()
	_voice()
	await _quarters()
	await _holdout()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _at(eye: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for i in 4: await physics_frame
	await process_frame


func _last(kind: String) -> Dictionary:
	for i in range(snd.heard.size() - 1, -1, -1):
		if String(snd.heard[i]["kind"]) == kind:
			return snd.heard[i]
	return {}


# ------------------------------------------------------------- acoustics
func _acoustics() -> void:
	var spots := {"Control Room": Vector3(0.0, 1.6, 0.2), "Main Junction": Vector3(-0.2, 1.6, 5.4), "Engineering": Vector3(-4.2, 1.6, 5.0), "inside the Airlock": Vector3(-4.8, 1.6, -1.4), "at the outer hatch": Vector3(-4.8, 1.6, -2.15)}
	var res := {}
	for k in spots:
		await _at(spots[k])
		snd.play_at(&"hatch_knock", se.HATCH_KNOCK_POS, false)
		res[k] = _last("hatch_knock")
		print("  knock heard in %s: %.1f m, %d walls, %.1f dB, low-pass %.0f Hz" % [k, float(res[k]["dist"]), int(res[k]["walls"]), float(res[k]["db"]), float(res[k]["cutoff"])])
	_check("from the Control Room the airlock knock is distant and muffled (%.1f dB, %d walls)" % [float(res["Control Room"]["db"]), int(res["Control Room"]["walls"])], float(res["Control Room"]["db"]) <= -18.0 and int(res["Control Room"]["walls"]) >= 2 and float(res["Control Room"]["cutoff"]) < 1500.0)
	_check("...from the Junction and Engineering too (%.1f / %.1f dB)" % [float(res["Main Junction"]["db"]), float(res["Engineering"]["db"])], float(res["Main Junction"]["db"]) <= -14.0 and float(res["Engineering"]["db"]) <= -10.0)
	_check("inside the airlock it is clearer (%.1f dB)" % float(res["inside the Airlock"]["db"]), float(res["inside the Airlock"]["db"]) > float(res["Control Room"]["db"]) + 10.0)
	_check("at the hatch it is close and sharp (%.1f dB, no wall)" % float(res["at the outer hatch"]["db"]), float(res["at the outer hatch"]["db"]) >= -6.0 and int(res["at the outer hatch"]["walls"]) == 0)
	_check("it comes from the hatch, never from the Control Room window", (res["Control Room"]["pos"] as Vector3).distance_to(Vector3(-1.2, 1.5, 1.4)) > 3.0)
	# The hatch-handle event now uses this path (no private full-volume player).
	var src: String = FileAccess.get_file_as_string("res://scripts/story/story_events.gd")
	_check("the hatch-handle event's knock goes through the acoustic path", src.find("play_at(&\"hatch_knock\"") != -1 and src.find("_hatch_sound.unit_size") == -1)
	await _at(Vector3(0.3, 1.6, 0.4))
	snd.play_at(&"glass_knock", Vector3(-1.47, 1.4, 1.5), false)
	var gk: Dictionary = _last("glass_knock")
	_check("window taps come from the port itself, through its glass (%d wall, %.1f dB)" % [int(gk["walls"]), float(gk["db"])], int(gk["walls"]) <= 1 and float(gk["db"]) > -16.0 and float(gk["db"]) < -4.0)


# --------------------------------------------- life sounds + inner thoughts
func _life_sounds_and_thoughts() -> void:
	var iv: Node = se.inner
	var ml: Label = q.get_node_or_null(q.message_label_path) as Label
	await _at(Vector3(3.1, 1.6, -0.3))
	dp.day_number = 3
	q.load_dict({})
	iv.queue = []
	iv.current = {}
	snd.heard = []
	# Water: dispenser, then a sip at the mouth.
	q.on_part(&"water")
	var disp: Dictionary = _last("dispense")
	_check("water: the dispenser sound comes from the dispenser", not disp.is_empty() and (disp["pos"] as Vector3).distance_to(q.GALLEY + Vector3(-0.26, 1.0, 0.02)) < 0.05)
	q._on_consumed("water")
	var sip: Dictionary = _last("sip")
	_check("...and a sip at the technician's own mouth", not sip.is_empty() and (sip["pos"] as Vector3).distance_to(cam.global_position) < 0.3)
	_check("water's reaction is an inner thought, not a HUD remark", iv.queue.any(func(x): return String(x["id"]).begins_with("routine:water")) and (ml == null or ml.text.find("Water. Better") == -1))
	# Tea: the hot-water unit heats, clicks off; the mug is a sip.
	snd.heard = []
	q.on_part(&"tea")
	_check("tea: the hot-water unit heats (from the unit)", not _last("kettle").is_empty() and (_last("kettle")["pos"] as Vector3).distance_to(q.GALLEY + Vector3(0.2, 1.08, -0.02)) < 0.05)
	q._process(3.2)
	_check("...and its thermostat clicks off when ready (not an interface chime)", not _last("kettle_done").is_empty() and _last("success").is_empty())
	q.on_part(&"mug")
	q._on_consumed("tea")
	_check("tea: a sip + an inner thought ('Still warm.' family)", not _last("sip").is_empty() and iv.queue.any(func(x): return String(x["id"]).begins_with("routine:tea")))
	snd.heard = []
	q.on_part(&"tea")
	_check("no sound for an action that did not happen (tea already had)", _last("kettle").is_empty())
	# Meals: wrapper / tray + chewing; rotating thoughts.
	snd.heard = []
	iv.queue = []
	q.on_part(&"meal")
	q._on_consumed("meal")
	_check("breakfast: a foil pouch + chewing at the mouth", not _last("wrapper").is_empty() and not _last("chew").is_empty())
	var first: String = String(iv.queue.filter(func(x): return String(x["id"]).begins_with("routine:meal"))[0]["text"]) if iv.queue.any(func(x): return String(x["id"]).begins_with("routine:meal")) else ""
	dp.day_number = 4
	iv.queue = []
	q.on_part(&"meal")
	q._on_consumed("meal")
	var second: String = String(iv.queue.filter(func(x): return String(x["id"]).begins_with("routine:meal"))[0]["text"]) if iv.queue.any(func(x): return String(x["id"]).begins_with("routine:meal")) else ""
	_check("meal thoughts rotate ('%s' -> '%s')" % [first, second], first != "" and second != "" and first != second)
	_check("no second, generic everyday thought on top of the meal thought", not iv.queue.any(func(x): return String(x["id"]).begins_with("everyday:breakfast")))
	var zh_ok := true
	for k in q.ROUTINE_THOUGHTS:
		for line in q.ROUTINE_THOUGHTS[k]:
			zh_ok = zh_ok and String(line[1]) != "" and String(line[1]) != String(line[0])
	_check("every routine thought has Simplified Chinese", zh_ok)
	# Brushing at the hygiene niche.
	snd.heard = []
	q.on_part(&"brush")
	q._on_consumed("brush")
	_check("brushing: the brush sound at the mouth, and it counts", not _last("brush").is_empty() and q.brushed_today())
	var sd: Dictionary = JSON.parse_string(JSON.stringify(q.state_dict()))
	_check("thought rotation survives save/load", sd.has("routine_uses") and int(sd["routine_uses"].get("meal", 0)) >= 2)
	iv.queue = []
	dp.day_number = 1


func _voice() -> void:
	var IV: Script = load("res://scripts/story/inner_voice.gd")
	var nat_en: String = IV.natural_voice("en")
	_check("natural-voice policy: only Enhanced/Premium voices qualify ('%s')" % nat_en, nat_en == "" or nat_en.contains("(Premium)") or nat_en.contains("(Enhanced)"))
	_check("the robotic Eloquence voice (Flo) is no longer used", not String(IV.VOICE["en"][0]).begins_with("Flo"))
	_check("captions-only fallback reported honestly here (%s)" % se.inner.backend(), se.inner.backend().begins_with("captions"))
	_check("a conversational pace (%d wpm), still under the assistant (168)" % int(IV.VOICE["en"][1]), int(IV.VOICE["en"][1]) >= 150 and int(IV.VOICE["en"][1]) < 168)
	_check("the evaluation sample tool exists (five delivery types)", FileAccess.file_exists("res://tools/voice_samples.sh") and FileAccess.get_file_as_string("res://tools/voice_samples.sh").count("|") >= 5)


# ------------------------------------------------------------- quarters
func _quarters() -> void:
	for n in ["WashCabinet", "WashCounterTop", "WashBasinFloor", "WashFaucetBase", "WashFaucetSpout", "WashUnderStoragePanel"]:
		if main.get_node_or_null("Geometry/" + n) != null:
			_check("redundant sink removed: %s still present" % n, false)
	_check("the redundant sink in front of the mirror is removed", main.get_node_or_null("Geometry/WashCounterTop") == null)
	var niche: Node = q.get_node_or_null("HygieneNiche")
	_check("the ONE hygiene station is kept (toothbrush part + water-saver tap)", niche != null and niche.find_children("*", "", true, false).any(func(n): return String(n.name).to_lower().contains("brush")))
	var g: CSGBox3D = main.get_node("Geometry/WashMirrorGlass")
	var bottom: float = g.global_position.y - g.size.y * 0.5
	_check("floor-length mirror: bottom %.2f m above the deck, %.2f m tall" % [bottom, g.size.y], bottom <= 0.06 and g.size.y >= 1.8 and g.size.x >= 0.55)
	var frame: CSGBox3D = main.get_node("Geometry/WashMirrorCabinet")
	_check("slim frame behind the glass, down to the deck", frame.size.x - g.size.x <= 0.1 and frame.global_position.y - frame.size.y * 0.5 <= 0.03 and frame.global_position.z > g.global_position.z)
	var mir: Node = main.get_node("Mirrors/LivingQuartersMirror")
	var mcam: Camera3D = mir.find_children("*", "Camera3D", true, false)[0]
	_check("the reflection frames the full glass (feed %s, aspect %.2f vs glass %.2f)" % [str(mir.size), float(mir.size.x) / float(mir.size.y), g.size.x / g.size.y], absf(float(mir.size.x) / float(mir.size.y) - g.size.x / g.size.y) < 0.01 and mir.size.x * mir.size.y <= 700000)
	# Nothing solid stands in front of the mirror any more.
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.6, 0.7)
	var pq := PhysicsShapeQueryParameters3D.new()
	pq.shape = box
	pq.collision_mask = 1
	pq.transform = Transform3D(Basis(), Vector3(2.15, 0.95, 1.85))
	pq.exclude = [(fb as CollisionObject3D).get_rid()]
	var hits: Array = (main as Node3D).get_world_3d().direct_space_state.intersect_shape(pq, 8)
	_check("clear floor in front of the mirror (%d obstacles)" % hits.size(), hits.is_empty())
	_check("the mirror still syncs with the real rig (first-person rig layer excluded, body layer kept)", mcam.cull_mask & 2 == 0 and mcam.cull_mask & 1 != 0)


# --------------------------------------------------------------- holdout
func _holdout() -> void:
	var h: Control = Sim.make(get_root())
	await process_frame
	_check("Gravity Mortar costs LESS than the Arc Projector (%d < %d), by stable id" % [int(h.WEAPONS["launcher"]["cost"]), int(h.WEAPONS["arc"]["cost"])], int(h.WEAPONS["launcher"]["cost"]) < int(h.WEAPONS["arc"]["cost"]))
	_check("...and the other prices are unchanged", int(h.WEAPONS["pistol"]["cost"]) == 0 and int(h.WEAPONS["machete"]["cost"]) == 40 and int(h.WEAPONS["smg"]["cost"]) == 120 and int(h.WEAPONS["shotgun"]["cost"]) == 170 and int(h.WEAPONS["rifle"]["cost"]) == 300 and int(h.WEAPONS["arc"]["cost"]) == 480)
	_check("distinct roles kept (arc = chain damage, mortar = area control)", String(h.WEAPON_ROLE["arc"]).length() > 0 and String(h.WEAPON_ROLE["launcher"]).length() > 0 and h.WEAPON_ROLE["arc"] != h.WEAPON_ROLE["launcher"])
	h.load_state({})
	h.start_seeded(11)
	h.credits = 900
	h.mode = "shop"
	h.shop_return = "wave"
	_check("inside a run: buy the mortar + an upgrade", h.weapon_action("launcher") and h.buy("damage") and h.weapon == "launcher")
	_check("...the purchase enters the permanent catalog", h.catalog.has("launcher"))
	for case in ["same-day restart", "next-day restart", "after game over", "abandoned run"]:
		match case:
			"next-day restart":
				dp.day_number += 1
			"after game over":
				h.mode = "play"
				h.hp = 1.0
				h.zombies = [{"pos": h.player, "hp": 999.0, "max": 999.0, "kind": "brute", "cd": 0.0, "flash": 0.0}]
				h.step(0.05)
			"abandoned run":
				h.mode = "paused"
		h.action("restart" if case != "same-day restart" else "start")
		_check("%s: wave 1, sidearm, 0 credits, no upgrades, nothing bought" % case, h.wave == 1 and h.weapon == "pistol" and h.credits == 0 and h.rank("damage") == 0 and h.unlocked.keys() == ["pistol"])
		h.credits = 900
		h.mode = "shop"
		h.shop_return = "wave"
		h.weapon_action("launcher")
		h.buy("damage")
	h.mode = "play"
	h.hp = 1.0
	h.zombies = [{"pos": h.player, "hp": 999.0, "max": 999.0, "kind": "brute", "cd": 0.0, "flash": 0.0}]
	h.step(0.05)
	_check("...on the game-over screen", h.mode == "over" and h._ov_text.text.find("KEPT") != -1 and h._ov_text.text.find("RESET") != -1)
	_check("outside a run nothing can be bought (it would vanish)", not h.weapon_action("arc") and not h.buy("rate") and h.message.find("run") != -1)
	_check("catalog weapons are cheaper in later runs (%d < %d)" % [h.weapon_cost("launcher"), int(h.WEAPONS["launcher"]["cost"])], h.weapon_cost("launcher") < int(h.WEAPONS["launcher"]["cost"]) and h.weapon_cost("arc") == int(h.WEAPONS["arc"]["cost"]))
	var best0: int = h.best
	var sd: Dictionary = JSON.parse_string(JSON.stringify(h.state_dict()))
	h.load_state({})
	h.load_state(sd)
	_check("save/load: records + catalog kept; run state never saved", h.best == best0 and h.catalog.has("launcher") and not sd.has("credits") and not sd.has("ranks") and h.weapon == "pistol")
	# Old mixed-model save.
	h.load_state({"best": 400, "best_wave": 6, "credits": 260, "ranks": {"damage": 3, "rate": 2}, "unlocked": ["pistol", "smg", "rifle"], "weapon": "rifle", "difficulty": "easy", "balance": 2})
	_check("old save: bought weapons -> catalog, NOT equipped or owned this run", h.catalog.has("smg") and h.catalog.has("rifle") and h.weapon == "pistol" and h.unlocked.keys() == ["pistol"])
	_check("old save: wallet + ranks kept on record, and the title says so", int(h.legacy_progress.get("wallet", 0)) == 260 and int(h.legacy_progress["ranks"].get("damage", 0)) == 3 and h.migration_note != "" and h.best == 400)
	h.mode = "title"
	h._refresh_overlay()
	_check("...the title shows the change once (records kept)", h._ov_text.text.find("Runs now start fresh") != -1)
	var sd2: Dictionary = JSON.parse_string(JSON.stringify(h.state_dict()))
	h.load_state(sd2)
	_check("no double migration", h.migration_note == "" and int(h.legacy_progress.get("wallet", 0)) == 260)
	# Per-run economy: a fresh sidearm run (the bot buys upgrades as it
	# goes) earns enough in one run for a first real weapon.
	for d in ["easy", "hard"]:
		var tot := 0
		var waves: Array = []
		for sd_i in [21, 22, 23]:
			var r: Dictionary = Sim.run(h, d, "pistol", sd_i, 8, {}, true, true)
			tot += int(r["credits"])
			waves.append(int(r["wave"]))
		print("  %s: fresh sidearm runs cleared waves %s, earned %d CR on average" % [d, str(waves), tot / 3])
		_check("%s: a fresh run earns enough for a first weapon (avg %d CR >= 120)" % [d, tot / 3], tot / 3 >= 120)
	h.queue_free()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
