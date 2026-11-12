extends Node
## Round 45 Priorities 3-4: STORY-DRIVEN STATION ACCESS (a technician
## clearance, granted automatically -- no badge swiping).
##
##   L0 ORIENTATION  Living Quarters, Control Room, corridor, Junction.
##   L1 MAINTENANCE  Engineering, Life Support, Storage (+ their tunnels and
##                   the airlock TUNNEL as a passage).
##   L2 SPECIALIST   Communications.
##   L3 EVA          suit locker + airlock cycling (exterior service).
##
## TOPOLOGY (inspected): Storage is reached only through Engineering or Life
## Support, the airlock tunnel only through Engineering -- so the physical
## gates are exactly three Junction openings (Engineering tunnel, Life
## Support gap, Comms tunnel); EVA is gated at its machines (locker,
## airlock console), so the tunnel stays walkable as a route. A gate is an
## invisible barrier on its own collision layer (BARRIER_LAYER: the
## technician's body collides with it; station geometry sweeps do not) plus
## a red / green door lamp and a short message on contact.
##
## PROGRESSION comes from real play (DayPlan facts, no parallel missions):
##   L1 after the day-1 check-in (orientation done) -- or any later day;
##   L2 after 3 completed jobs (proficiency) -- or day 4;
##   L3 after 6 completed jobs at L2 -- or day 7.
## The level only ever rises; a developer override (debug builds) is
## transient. DayPlan never schedules work behind a gate (allows_order()),
## so no mandatory job, spare part or tool is out of reach. An old save
## with real progress simply computes its (high) level -- never soft-locked.

const BARRIER_LAYER := 1 << 9
const NAMES := ["ORIENTATION", "MAINTENANCE", "SPECIALIST", "EVA"]
const NAMES_ZH := ["入职", "维护", "专业", "舱外"]


static func _zh() -> bool:
	return String(preload("res://scripts/station/game_settings.gd").get_value("language")).begins_with("zh")
const ROOM_LEVEL := {&"living_quarters": 0, &"control_room": 0, &"engineering": 1, &"life_support": 1, &"storage": 1, &"airlock": 1, &"communications": 2}
## gate id -> [level, centre, size, lamp position (over the opening, Junction
## side), label, lamp yaw (degrees: the sign faces the Junction)]
const GATES := {
	"engineering": [1, Vector3(-1.45, 1.2, 6.06), Vector3(0.08, 2.4, 1.2), Vector3(-1.38, 2.28, 6.06), "ENGINEERING", 90.0],
	"life_support": [1, Vector3(-0.4, 1.2, 7.32), Vector3(1.0, 2.4, 0.08), Vector3(-0.4, 2.28, 7.27), "LIFE SUPPORT", 180.0],
	"communications": [2, Vector3(1.02, 1.2, 4.5), Vector3(0.08, 2.4, 1.2), Vector3(0.98, 2.28, 4.5), "COMMS", -90.0],
}
## Work-order type / workday -> level needed (rooms + parts + tools).
const ORDER_LEVEL := {&"breaker": 1, &"vent": 1, &"seal": 3, &"data": 1, &"thermal": 1, &"power": 1, &"antenna": 3, &"lens": 3,
	&"solar_clean": 3, &"solar_coupler": 3, &"solar_hinge": 3, &"patch_bay": 2, &"emerg_lights": 0, &"junction_panel": 0, &"backup_rx": 2}

var level: int = 0
var dev_override: int = -1          # -1 = none (never saved)
## Round 49: LOWER SERVICE DECK (Deck B) access, a separate ladder of tiers
## on top of L3 -- story-driven first, then training on the deck itself:
##   T1 UTILITIES   Lower Junction, Water Recovery, Thermal Control. Granted
##                  when Chapter One is complete (the window encounter's
##                  chapter card) AND the technician holds L3 -- the opening
##                  of Chapter Two. Never during Chapter One.
##   T2 LOGISTICS   + Workshop, Cargo (2 Deck B jobs closed).
##   T3 SCIENCE     + Laboratory, Hydroponics, Medical (5 Deck B jobs).
##   T4 RECORDS     + Data Archive (8 Deck B jobs, or a Chapter Two record
##                  discrepancy noticed -- the archive becomes relevant).
## Like the level, the tier only rises; the developer override is
## transient (never saved).
var deck_b_level: int = 0
var deck_b_jobs: int = 0
var dev_deck_b: int = -1
const DECK_B_NAMES := ["NONE", "UTILITIES", "LOGISTICS", "SCIENCE", "RECORDS"]
const DeckBTasks = preload("res://scripts/deck_b/deck_b_tasks.gd")
const DeckBLayout = preload("res://scripts/deck_b/deck_b_layout.gd")
var _gates: Dictionary = {}         # id -> {body, lamp_mat, label}
var _msg_cool: float = 0.0
var _dp: Node
signal level_changed(level: int)


func _ready() -> void:
	add_to_group(&"clearance")
	add_to_group(&"r35_equipment")
	_dp = get_parent()
	_build_gates.call_deferred()
	if _dp != null:
		for sig in [&"day_started", &"task_completed", &"order_closed"]:
			if _dp.has_signal(sig):
				_dp.connect(sig, func(_a): refresh())
		if _dp.has_signal(&"order_closed"):
			_dp.order_closed.connect(_on_order_closed_b)


func effective() -> int:
	return dev_override if dev_override >= 0 else level


func jobs_done() -> int:
	if _dp == null or not "proficiency" in _dp:
		return 0
	var n := 0
	for f in _dp.proficiency:
		n += int(_dp.proficiency[f])
	return n


## What the technician's real progress earns (never lowers the level).
func earned() -> int:
	if _dp == null:
		return 3
	var day: int = int(_dp.day_number)
	var l := 0
	if day >= 2 or _dp.is_task_done(&"c01"):
		l = 1
	if l >= 1 and (jobs_done() >= 3 or day >= 4):
		l = 2
	if l >= 2 and (jobs_done() >= 6 or day >= 7):
		l = 3
	return l


func refresh() -> void:
	var e: int = earned()
	if e > level:
		var old: int = level
		level = e
		for l in range(old + 1, level + 1):
			_announce(l)
		level_changed.emit(level)
	var eb: int = earned_deck_b()
	if eb > deck_b_level:
		var oldb: int = deck_b_level
		deck_b_level = eb
		for t in range(oldb + 1, deck_b_level + 1):
			_announce_deck_b(t)
		level_changed.emit(level)
	_apply()


# ------------------------------------------------------- Round 49: Deck B
func _on_order_closed_b(t: StringName) -> void:
	if DeckBTasks.is_deck_b(t):
		deck_b_jobs += 1
		refresh()


func deck_b_tier() -> int:
	return dev_deck_b if dev_deck_b >= 0 else deck_b_level


func _story() -> Node:
	return get_tree().get_first_node_in_group(&"story_events") if is_inside_tree() else null


func earned_deck_b() -> int:
	if level < 3:
		return 0
	var st: Node = _story()
	if st == null or not st.has_method("chapter_one_complete") or not st.chapter_one_complete():
		return 0
	var t: int = 1
	if deck_b_jobs >= 2:
		t = 2
	if t >= 2 and deck_b_jobs >= 5:
		t = 3
	if t >= 3 and (deck_b_jobs >= 8 or (st.has_method("has_milestone") and st.has_milestone("ch2_records"))):
		t = 4
	return t


func deck_b_room_open(room: StringName) -> bool:
	if not DeckBLayout.ROOMS.has(room):
		return true
	var need: int = int(DeckBLayout.ROOMS[room][2])
	return need > 0 and deck_b_tier() >= need


func _announce_deck_b(t: int) -> void:
	if not is_inside_tree():
		return
	if t == 1:
		# Chapter Two opens: the systems note the day (letters / pacing);
		# the story records the milestone (never a phase change by itself).
		var sysb: Node = get_tree().get_first_node_in_group(&"deck_b_systems")
		if sysb != null and int(sysb.tier1_day) < 0 and _dp != null:
			sysb.tier1_day = int(_dp.day_number)
		var st: Node = _story()
		if st != null and st.has_method("_add_milestone"):
			st._add_milestone("ch2_opened")
	get_tree().call_group(&"station_ai", &"event", StringName("access_deck_b_%d" % t))
	var lg: Node = get_tree().get_first_node_in_group(&"station_log")
	if lg != null:
		lg.record("access", "CLEARANCE LOWER SERVICE DECK · %s granted · TECH-1" % DECK_B_NAMES[t])
	if _dp != null and _dp.has_method("log_event"):
		_dp.log_event("Clearance: Lower Service Deck — %s" % DECK_B_NAMES[t])


func dev_set_deck_b(t: int) -> void:
	if OS.is_debug_build():
		dev_deck_b = clampi(t, -1, 4)
		level_changed.emit(effective())


func _announce(l: int) -> void:
	if not is_inside_tree():
		return
	get_tree().call_group(&"station_ai", &"event", StringName("access_l%d" % l))
	var lg: Node = get_tree().get_first_node_in_group(&"station_log")
	if lg != null:
		lg.record("access", "CLEARANCE %s granted · TECH-1" % NAMES[l])


func room_open(room: StringName) -> bool:
	if DeckBLayout.ROOMS.has(room):
		return deck_b_room_open(room)
	return effective() >= int(ROOM_LEVEL.get(room, 0))


func allows_order(type: StringName) -> bool:
	if DeckBTasks.is_deck_b(type):
		# Every Deck B job (and the design-gap jobs that live on Deck B's
		# systems) needs its tier: nothing is assigned behind the shaft
		# hatch or a lower-deck gate. The EVA-dependent radiator panel path
		# also needs L3 (checked by the job itself).
		return effective() >= 3 and deck_b_tier() >= int(DeckBTasks.entry(type).get("tier", 1))
	return effective() >= int(ORDER_LEVEL.get(type, 0))


## Machine-level gates: "eva" (locker, airlock cycle), "comms".
func allows(kind: String) -> bool:
	match kind:
		"eva": return effective() >= 3
		"comms": return effective() >= 2
	return true


func refusal(kind: String) -> String:
	if _zh():
		return "需要舱外培训" if kind == "eva" else "访问受限"
	return "TRAINING REQUIRED — EVA" if kind == "eva" else "ACCESS RESTRICTED"


func dev_set(l: int) -> void:
	if OS.is_debug_build():
		dev_override = clampi(l, -1, 3)
		_apply()
		level_changed.emit(effective())


# ------------------------------------------------------------- gates
func _build_gates() -> void:
	var root: Node = _dp.get_parent() if _dp != null else null
	if root == null:
		return
	var holder := Node3D.new()
	holder.name = "AccessGates"
	root.add_child(holder)
	for id in GATES:
		var g: Array = GATES[id]
		var body := StaticBody3D.new()
		body.name = "Gate_" + id
		body.collision_layer = BARRIER_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = g[2]
		cs.shape = bs
		body.add_child(cs)
		body.position = g[1]
		holder.add_child(body)
		var sign := Node3D.new()
		sign.position = g[3]
		sign.rotation_degrees.y = float(g[5])
		holder.add_child(sign)
		var plate := CSGBox3D.new()
		plate.size = Vector3(0.5, 0.16, 0.02)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.08, 0.09, 0.1)
		plate.material = pm
		sign.add_child(plate)
		var lamp := CSGBox3D.new()
		lamp.size = Vector3(0.06, 0.06, 0.03)
		lamp.position = Vector3(-0.19, 0.0, 0.015)
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		lamp.material = m
		sign.add_child(lamp)
		var lbl := Label3D.new()
		lbl.font_size = 22
		lbl.pixel_size = 0.0011
		lbl.outline_size = 4
		lbl.position = Vector3(0.04, 0.0, 0.025)
		sign.add_child(lbl)
		_gates[id] = {"body": body, "mat": m, "label": lbl}
	var fb: CollisionObject3D = root.get_node_or_null("FreeMoveBody") as CollisionObject3D
	if fb != null:
		fb.collision_mask |= BARRIER_LAYER
	refresh()


func gate_open(id: String) -> bool:
	return effective() >= int(GATES[id][0])


func _apply() -> void:
	for id in _gates:
		var open: bool = gate_open(id)
		var g: Dictionary = _gates[id]
		(g["body"] as StaticBody3D).collision_layer = 0 if open else BARRIER_LAYER
		var c: Color = Color(0.2, 0.9, 0.35) if open else Color(0.95, 0.2, 0.15)
		(g["mat"] as StandardMaterial3D).albedo_color = c
		(g["mat"] as StandardMaterial3D).emission = c
		(g["label"] as Label3D).text = ("%s · OPEN" if open else "%s · RESTRICTED") % GATES[id][4]
		(g["label"] as Label3D).modulate = c.lightened(0.3)


## Contact with a closed gate: a short message (rate-limited).
func _process(delta: float) -> void:
	_msg_cool = maxf(_msg_cool - delta, 0.0)
	if _msg_cool > 0.0 or _gates.is_empty():
		return
	var root: Node = _dp.get_parent() if _dp != null else null
	var fb: Node3D = root.get_node_or_null("FreeMoveBody") as Node3D if root != null else null
	if fb == null:
		return
	for id in _gates:
		if gate_open(id):
			continue
		var g: Array = GATES[id]
		var c: Vector3 = g[1]
		var h: Vector3 = (g[2] as Vector3) * 0.5 + Vector3(0.45, 0, 0.45)
		var p: Vector3 = fb.global_position
		if absf(p.x - c.x) <= h.x and absf(p.z - c.z) <= h.z:
			_msg_cool = 4.0
			var hud: Label = root.get_node_or_null("Player/HUD/TaskMessageLabel") as Label
			if hud != null:
				var msg: String = ("访问受限 · 需要%s权限" % NAMES_ZH[int(g[0])]) if _zh() else ("ACCESS RESTRICTED · %s clearance" % NAMES[int(g[0])])
				preload("res://scripts/ui/hud_message.gd").show(hud, get_instance_id(), msg, 2.5)
			return


func state_dict() -> Dictionary:
	return {"level": level, "deck_b_level": deck_b_level, "deck_b_jobs": deck_b_jobs}


func load_dict(d: Dictionary) -> void:
	level = clampi(int(d.get("level", 0)), 0, 3)
	deck_b_level = clampi(int(d.get("deck_b_level", 0)), 0, 4)
	deck_b_jobs = maxi(int(d.get("deck_b_jobs", 0)), 0)
	dev_override = -1
	dev_deck_b = -1
	refresh()
