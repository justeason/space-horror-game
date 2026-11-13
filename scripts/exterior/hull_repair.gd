extends "res://scripts/deck_b/deck_b_room.gd"
## Round 50 -- A06 HULL DAMAGE: assessment, stabilisation and exterior
## repair on three predefined, serviceable hull sites (all within tether
## reach of an existing ring; none on moving machinery or the solar wings):
##   lower    B-04 Workshop south wall, the LOWER service module (ring D1,
##            reached from A3 below the antenna pad) -- a SMALL PUNCTURE:
##            the SAME physical defect as the network leak "hull_b04"
##            (deck_b_systems.gd), never a second copy
##   seam     airlock tunnel east wall beside the walkway (ring A2) -- a
##            DAMAGED PANEL SEAM: a slow leak into Deck A the make-up gas
##            hides from the pressure gauges, but not from its flow meter
##   impact   Engineering's south wall (ring A3) -- EXTERIOR IMPACT damage
##            to an MMOD cover panel: no breach at severity 1 (inspect and
##            record), a cracked panel to replace at 2-3
## Inside: the HULL MONITOR at the airlock (impact sensor zones, leak
## linkage, LOCATE / VERIFY / DEFER). Outside (existing EVA, tethers and
## worksites): inspect with the probe -> prepare the surface -> fit the
## patch / sealant / replacement panel from the SUIT CADDY (a real item,
## consumed) -> torque the fasteners in a CROSS pattern -> seal probe.
## Verification is from INSIDE (the network: hold test / make-up flow).
## Outcomes: inspected_no_breach, stabilized (a temporary inside patch,
## defect remains), repaired, deferred_part, deferred_eva, verified_normal.

const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
const EXT := 1 << 11
const CROSS := [0, 2, 1, 3]          # diagonal torque order (any start)
## site -> [type, centre on the hull, outward normal, stance (eye), ring, leak id]
## (centres sit ON the outer hull plating -- measured: 0.11-0.12 m
## outboard of the pressure wall faces.)
const SITES := {
	"lower": ["puncture", Vector3(-4.75, -2.18, 2.775), Vector3(0, 0, -1), Vector3(-4.6, -2.05, 2.25), "D1", "hull_b04"],
	"seam": ["seam", Vector3(-4.075, 1.45, -1.25), Vector3(1, 0, 0), Vector3(-3.62, 1.5, -1.25), "A2", "hull_seam"],
	"impact": ["impact", Vector3(-3.3, 1.55, 2.875), Vector3(0, 0, -1), Vector3(-3.3, 1.6, 2.38), "A3", ""],
}
const SITE_NAME := {"lower": "lower module B-04/S", "seam": "airlock seam AL-E3", "impact": "Engineering MMOD panel EN-S2"}

## Authoritative damage per site (saved): state none | damaged | repaired;
## sev 1..3; found (located on the monitor); work: the exterior steps.
var dmg := {}
var anomaly_log: Array = []
var active_site: String = ""         # the A06 order's site
var _vis := {}                        # site -> {damaged, patch, repaired, bolts[], marks}
var _mon: Label3D
var _built_ext: bool = false


func _ready() -> void:
	room_id = &"airlock"
	add_to_group(&"hull_repair")
	_room_ready([&"a06_hull"])
	for s in SITES:
		dmg[s] = _fresh(s)
	_build_monitor()
	_build_exterior.call_deferred()


func _fresh(s: String) -> Dictionary:
	return {"state": "none", "sev": 1, "found": false, "inspected": false, "prep": false, "fitted": false, "align": 0, "seated": false,
		"bolts": [], "removed": false, "sealed": false, "probed": false, "day": -1}


func _eva() -> Node:
	return get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null


func _suit() -> Node:
	return get_tree().get_first_node_in_group(&"suit_service") if is_inside_tree() else null


func _ext_layers(n: Node) -> void:
	for v in n.find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).layers = 1 | EXT
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 | EXT


func _layer_a(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).layers = 1
		_layer_a(c)


# ------------------------------------------------------------ monitor
func _build_monitor() -> void:
	var p := Node3D.new()
	p.name = "HullMonitor"
	p.position = Vector3(-5.198, 1.35, 2.42)
	p.rotation_degrees.y = 90.0
	add_child(p)
	dbox(Vector3(0.36, 0.36, 0.04), Vector3(0, 0, 0.02), Color(0.18, 0.2, 0.23), p)
	dbox(Vector3(0.38, 0.03, 0.05), Vector3(0, 0.185, 0.02), Color(0.3, 0.6, 0.9), p)
	text("HULL MONITOR · IMPACT / LEAK", Vector3(0, 0.155, 0.042), 7, Color(0.95, 0.95, 0.9), p)
	_mon = readout(Vector3(0, 0.04, 0.042), Vector2(0.32, 0.18), p, 7)
	part(&"mon_read", Vector3(0.32, 0.18, 0.05), Vector3(0, 0.04, 0.05), p)
	var b: Array = [["locate", "LOCATE", Color(0.3, 0.6, 0.9)], ["verify", "VERIFY", Color(0.25, 0.9, 0.4)], ["defer", "DEFER", Color(0.9, 0.7, 0.2)]]
	for i in b.size():
		var x: float = -0.11 + i * 0.11
		button(b[i][0], Vector3(x, -0.11, 0.045), b[i][2], p, Vector3(0.07, 0.035, 0.02))
		text(b[i][1], Vector3(x, -0.145, 0.042), 5, Color(0.9, 0.9, 0.9), p)
	_layer_a(p)
	flush_clicks(p, 0.045)                      # out of the tunnel's walking band


# ----------------------------------------------------------- exterior
func _build_exterior() -> void:
	if _built_ext:
		return
	_built_ext = true
	var e: Node = _eva()
	for s in SITES:
		var d: Array = SITES[s]
		var root := Node3D.new()
		root.name = "HullSite_" + s
		add_child(root)
		root.position = d[1]
		var nrm: Vector3 = d[2]
		root.look_at_from_position(d[1], d[1] - nrm, Vector3.UP)   # local +z = outward
		var v := {"damaged": Node3D.new(), "patch": Node3D.new(), "repaired": Node3D.new(), "bolts": [], "old_panel": Node3D.new()}
		for k in ["damaged", "patch", "repaired", "old_panel"]:
			(v[k] as Node3D).name = k.capitalize()
			root.add_child(v[k])
		_site_geometry(s, root, v)
		_ext_layers(root)
		_vis[s] = v
		# Worksite: a handhold on the structure + the work parts.
		var hold_pos: Vector3 = d[1] + nrm * 0.08 + Vector3(0, 0.32, 0)
		var bar := dbox(Vector3(0.34, 0.035, 0.035), hold_pos, Color(0.95, 0.75, 0.15), self)
		bar.name = "Handhold_" + s
		_ext_layers(bar)
		if e != null and e.has_method("register_worksite"):
			e.register_worksite("hull_" + s, d[3], d[1], [d[4]], self, hold_pos, "HULL SITE " + s.to_upper())
	# A small floodlight at the lower site (it is in the deck's shadow).
	var sl := SpotLight3D.new()
	sl.name = "LowerSiteLamp"
	sl.light_color = Color(0.95, 0.97, 1.0)
	sl.light_energy = 1.6
	sl.spot_range = 3.5
	sl.spot_angle = 40.0
	sl.light_cull_mask = EXT
	add_child(sl)
	sl.look_at_from_position(Vector3(-4.15, -1.25, 2.6), SITES["lower"][1], Vector3.UP)
	var lamp := dbox(Vector3(0.08, 0.06, 0.08), Vector3(-4.15, -1.25, 2.72), Color(0.9, 0.9, 0.85), self)
	glow(lamp, Color(1.0, 0.95, 0.85), 1.2)
	_ext_layers(lamp)
	_refresh()


func _site_geometry(s: String, root: Node3D, v: Dictionary) -> void:
	var dmg_n: Node3D = v["damaged"]
	var patch: Node3D = v["patch"]
	var rep: Node3D = v["repaired"]
	match SITES[s][0]:
		"puncture":
			# Scorched MLI around a small hole; curled blanket edges.
			dcyl(0.09, 0.006, Vector3(0, 0, 0.004), Color(0.25, 0.22, 0.2), dmg_n, Vector3(90, 0, 0), 0.1)
			dcyl(0.012, 0.01, Vector3(0, 0, 0.009), Color(0.01, 0.01, 0.01), dmg_n, Vector3(90, 0, 0), 0.0)
			for k in 5:
				var a: float = TAU * k / 5.0 + 0.4
				var f := dbox(Vector3(0.05, 0.012, 0.004), Vector3(cos(a) * 0.06, sin(a) * 0.06, 0.012), Color(0.85, 0.75, 0.45), dmg_n, 0.6)
				f.rotation = Vector3(0.5, 0, a)
			var frost := dcyl(0.03, 0.004, Vector3(0, 0, 0.014), Color(0.9, 0.95, 1.0), dmg_n, Vector3(90, 0, 0), 0.0)
			frost.name = "Frost"
			glow(frost, Color(0.8, 0.9, 1.0), 0.6)
			# Patch plate (positioned, then aligned) + four fasteners.
			dbox(Vector3(0.2, 0.2, 0.012), Vector3.ZERO, Color(0.8, 0.8, 0.78), patch, 0.6)
			dbox(Vector3(0.006, 0.05, 0.002), Vector3(0, 0.07, 0.007), Color(0.1, 0.1, 0.1), patch)     # scribe mark
			_bolts(patch, v, 0.08)
			for e2 in [[Vector3(0.23, 0.012, 0.01), Vector3(0, 0.11, 0.02)], [Vector3(0.23, 0.012, 0.01), Vector3(0, -0.11, 0.02)], [Vector3(0.012, 0.23, 0.01), Vector3(0.11, 0, 0.02)], [Vector3(0.012, 0.23, 0.01), Vector3(-0.11, 0, 0.02)]]:
				dbox(e2[0], e2[1], Color(0.95, 0.95, 0.92), rep, 0.1)   # cured sealant bead round the patch
			# Alignment crosshair painted on the hull (always there).
			dbox(Vector3(0.004, 0.24, 0.002), Vector3(0, 0, 0.001), Color(0.95, 0.4, 0.1), root)
			dbox(Vector3(0.24, 0.004, 0.002), Vector3(0, 0, 0.001), Color(0.95, 0.4, 0.1), root)
		"seam":
			# A lifted panel edge with a discoloured seal strip.
			var lift := dbox(Vector3(0.5, 0.32, 0.01), Vector3(0, 0, 0.012), Color(0.82, 0.82, 0.8), dmg_n, 0.4)
			lift.rotation_degrees.x = 4.0
			dbox(Vector3(0.5, 0.018, 0.006), Vector3(0, -0.16, 0.01), Color(0.45, 0.32, 0.2), dmg_n, 0.1)
			dbox(Vector3(0.5, 0.32, 0.01), Vector3(0, 0, 0.006), Color(0.85, 0.85, 0.83), rep, 0.4)
			dbox(Vector3(0.5, 0.02, 0.008), Vector3(0, -0.16, 0.01), Color(0.95, 0.95, 0.95), rep, 0.1)  # fresh bead
			dbox(Vector3(0.5, 0.02, 0.008), Vector3(0, -0.16, 0.01), Color(0.92, 0.92, 0.95), patch, 0.1) # wet sealant
			_bolts(patch, v, 0.22, 0.12)
		"impact":
			# An MMOD cover panel: crater + crack (damaged), a clean panel.
			dbox(Vector3(0.4, 0.3, 0.012), Vector3(0, 0, 0.006), Color(0.6, 0.58, 0.55), dmg_n, 0.3)
			dcyl(0.05, 0.008, Vector3(0.04, 0.02, 0.013), Color(0.2, 0.18, 0.16), dmg_n, Vector3(90, 0, 0))
			var crack := dbox(Vector3(0.18, 0.006, 0.004), Vector3(0.1, -0.03, 0.014), Color(0.1, 0.1, 0.1), dmg_n)
			crack.rotation_degrees.z = -25.0
			dbox(Vector3(0.4, 0.3, 0.012), Vector3(0, 0, 0.006), Color(0.88, 0.88, 0.86), rep, 0.3)
			dbox(Vector3(0.4, 0.3, 0.012), Vector3(0, 0, 0.006), Color(0.88, 0.88, 0.86), patch, 0.3)
			_bolts(patch, v, 0.17, 0.12)
			# The empty mounting frame (seen once the old panel is off).
			for sx in [-0.2, 0.2]:
				dbox(Vector3(0.012, 0.3, 0.02), Vector3(sx, 0, 0.004), Color(0.4, 0.42, 0.45), v["old_panel"])
	for k in 4:
		part(StringName("x_%s_bolt%d" % [s, k]), Vector3(0.06, 0.06, 0.08), (v["bolts"][k] as Node3D).position, root)
	part(StringName("x_%s_work" % s), Vector3(0.3, 0.26, 0.1), Vector3(0, 0, 0.04), root)


func _bolts(parent: Node3D, v: Dictionary, hx: float, hy: float = -1.0) -> void:
	if hy < 0.0:
		hy = hx
	for p in [Vector2(-hx, hy), Vector2(hx, hy), Vector2(hx, -hy), Vector2(-hx, -hy)]:
		var b := Node3D.new()
		b.position = Vector3(p.x, p.y, 0.012)
		parent.add_child(b)
		dcyl(0.012, 0.016, Vector3.ZERO, Color(0.55, 0.55, 0.58), b, Vector3(90, 0, 0), 0.8)
		v["bolts"].append(b)


# --------------------------------------------------------- interaction
func on_part(id: StringName) -> void:
	var sid := String(id)
	match sid:
		"mon_read": _mon_read()
		"locate": _locate()
		"verify": _verify()
		"defer": _defer()
		_:
			if sid.begins_with("x_"):
				var site: String = sid.get_slice("_", 1)
				var what: String = sid.get_slice("_", 2)
				_exterior(site, what)
	_refresh()


func part_prompt(id: StringName) -> String:
	var sid := String(id)
	match sid:
		"mon_read": return "Click: Read the hull monitor"
		"locate": return "Click: LOCATE — triangulate the impact / leak zone"
		"verify": return "Click: VERIFY the hull from inside"
		"defer": return "Click: DEFER the exterior repair (logged)"
	if sid.begins_with("x_"):
		var site: String = sid.get_slice("_", 1)
		var e: Node = _eva()
		if e == null or not e.outside or not e.at_worksite("hull_" + site):
			return "Grab the handhold at this site first" if e != null and e.outside else ""
		return "Click: " + _next_word(site)
	return ""


func _caddy_item(kinds: Array) -> Node3D:
	var ss: Node = _suit()
	if ss == null or ss.caddy == null:
		return null
	for sl in ss.caddy.slots:
		for c in sl.get_children():
			if c.get("item_id") in kinds:
				return c
	return null


func _caddy_free() -> bool:
	var ss: Node = _suit()
	return ss != null and ss.caddy != null and ss.caddy.free_slot() != -1


func _exterior(site: String, what: String) -> void:
	var e: Node = _eva()
	if e == null or not e.outside or not e.at_worksite("hull_" + site):
		say("Get to the %s worksite and grab its handhold first." % SITE_NAME[site])
		return
	var d: Dictionary = dmg[site]
	var typ: String = SITES[site][0]
	if d["state"] == "none":
		d["inspected"] = true
		say("Probe sweep of %s: plate sound, no scoring, no flow." % SITE_NAME[site])
		sfx(&"click")
		return
	if d["state"] == "repaired":
		say("%s: repaired — fasteners torqued, seal intact." % SITE_NAME[site])
		return
	if not bool(d["inspected"]):
		_probe(site)
		return
	if what.begins_with("bolt"):
		_bolt(site, int(what.right(1)))
		return
	match typ:
		"puncture":
			if not bool(d["prep"]):
				d["prep"] = true
				sfx(&"scrub")
				say("MLI cut back and the plate abraded clean around the hole (a patch only bonds to bare metal).")
			elif not bool(d["fitted"]):
				var kit: Node3D = _caddy_item([&"hull_patch_kit"])
				if kit == null:
					sfx(&"fail")
					say("No hull patch kit in the suit caddy — it is back in the airlock (EVA REPAIR STOCK).")
					return
				consume_part(kit)
				d["fitted"] = true
				d["align"] = 2 if (absi(hash([site, d["day"]])) % 2) == 0 else -2
				sfx(&"insert")
				say("Patch plate offered up — it sits %s of the crosshair. Slide it into line before seating." % ("left" if int(d["align"]) < 0 else "right"))
			elif int(d["align"]) != 0:
				d["align"] = int(d["align"]) - signi(int(d["align"]))
				sfx(&"scrub")
				say("Patch nudged %s." % ("into line with the crosshair — scribe marks match" if int(d["align"]) == 0 else "— nearly there"))
			elif not bool(d["seated"]):
				d["seated"] = true
				sfx(&"clunk")
				say("Patch pressed home over the hole. Torque the four fasteners in a CROSS pattern.")
			else:
				_seal_probe(site)
		"seam":
			if not bool(d["prep"]):
				d["prep"] = true
				sfx(&"scrub")
				say("Old seal strip scraped out of the seam, edges wiped.")
			elif not bool(d["fitted"]):
				var kit2: Node3D = _caddy_item([&"seam_seal_kit"])
				if kit2 == null:
					sfx(&"fail")
					say("No seam sealant kit in the suit caddy.")
					return
				consume_part(kit2)
				d["fitted"] = true
				d["seated"] = true
				sfx(&"hiss")
				say("Sealant bead laid along the seam. Re-torque the panel edge fasteners (cross pattern).")
			else:
				_seal_probe(site)
		"impact":
			if int(d["sev"]) <= 1:
				_seal_probe(site)
				return
			if not bool(d["removed"]):
				if (d["bolts"] as Array).size() < 4:
					say("Back the four fasteners out first (any order).")
					return
				if not _caddy_free():
					sfx(&"fail")
					say("No free slot in the suit caddy for the damaged panel — it must come back in, not drift away.")
					return
				var ss: Node = _suit()
				var old: Node3D = spawn_part(&"hull_panel_damaged", ss.caddy, {"condition": 0.2, "state": "failed", "history": [{"day": day(), "text": "removed from %s (impact)" % SITE_NAME[site]}]})
				old.visible = false
				d["removed"] = true
				d["bolts"] = []
				sfx(&"clunk")
				say("Damaged panel off and clipped into the caddy. Fit the replacement.")
			elif not bool(d["fitted"]):
				var pn: Node3D = _caddy_item([&"hull_panel"])
				if pn == null:
					sfx(&"fail")
					say("No replacement MMOD panel in the suit caddy.")
					return
				consume_part(pn)
				d["fitted"] = true
				d["seated"] = true
				sfx(&"insert")
				say("Replacement panel on its studs. Torque the fasteners in a CROSS pattern.")
			else:
				_seal_probe(site)


func _probe(site: String) -> void:
	var d: Dictionary = dmg[site]
	d["inspected"] = true
	sfx(&"relay")
	match SITES[site][0]:
		"puncture":
			var net: Node = sys()
			var p04: float = net.pressure("B04") if net != null else 0.0
			say("Probe: a %d mm puncture through the plate, edges petalled outward; %s." % [2 + int(d["sev"]) * 2, "gas jetting (B-04 at %.0f kPa)" % p04 if p04 > 20.0 and _leak_live() else "no flow (B-04 isolated / patched inside)"], 5.0)
		"seam":
			say("Probe: panel edge lifted ~2 mm, the seal strip cracked and brown; a faint flow along 30 cm of seam.", 4.5)
		"impact":
			say("Probe: impact crater %d mm on the MMOD cover; %s." % [4 + int(d["sev"]) * 5, "the pressure wall behind it is untouched — no breach" if int(d["sev"]) <= 1 else "the cover panel is CRACKED (pressure wall intact) — replace the panel"], 5.0)


func _bolt(site: String, k: int) -> void:
	var d: Dictionary = dmg[site]
	var typ: String = SITES[site][0]
	var removing: bool = typ == "impact" and not bool(d["removed"])
	if not removing and not bool(d["seated"]):
		say("Nothing to fasten yet.")
		return
	var b: Array = d["bolts"]
	if b.has(k):
		say("Fastener %d already %s." % [k + 1, "out" if removing else "torqued"])
		return
	if not removing:
		# Cross pattern: the 2nd fastener is opposite the 1st, the 4th
		# opposite the 3rd -- otherwise the plate seats unevenly.
		var ok := true
		if b.size() == 1 or b.size() == 3:
			ok = k == (int(b[b.size() - 1]) + 2) % 4
		if not ok:
			d["bolts"] = []
			sfx(&"fail")
			say("Uneven seating — the plate rocked. Back all fasteners off and torque them in a CROSS pattern (opposite corners).", 4.5)
			return
	b.append(k)
	d["bolts"] = b
	sfx(&"ratchet")
	if b.size() == 4:
		say("All four fasteners %s." % ("out" if removing else "torqued to 5 N·m — now check the seal with the probe"))


func _seal_probe(site: String) -> void:
	var d: Dictionary = dmg[site]
	var typ: String = SITES[site][0]
	if typ == "impact" and int(d["sev"]) <= 1:
		d["probed"] = true
		say("Seal probe: pressure wall intact, no flow. Record it from inside (VERIFY).")
		return
	if (d["bolts"] as Array).size() < 4:
		say("Torque all four fasteners first.")
		return
	d["probed"] = true
	d["state"] = "repaired"
	var net: Node = sys()
	var lid: String = SITES[site][5]
	if net != null and lid != "" and not net.leak(lid).is_empty():
		net.set_leak_state(lid, "repaired")
	sfx(&"success")
	var p_in: float = net.pressure("B04") if net != null and site == "lower" else 101.3
	if p_in < 90.0:
		say("Seal probe: NO DIFFERENTIAL behind the patch (B-04 at %.0f kPa) — verify from inside after repressurising." % p_in, 5.0)
	else:
		say("Seal probe: no flow across the %s. Exterior work complete — verify from inside." % ("patch" if typ == "puncture" else ("seam" if typ == "seam" else "panel")), 4.5)


func _leak_live() -> bool:
	var net: Node = sys()
	var lk: Dictionary = net.leak("hull_b04") if net != null else {}
	return not lk.is_empty() and String(lk["state"]) == "active"


func _mon_read() -> void:
	sfx(&"click")
	var rows: Array = []
	for s in SITES:
		var d: Dictionary = dmg[s]
		if d["state"] != "none":
			rows.append("%s: %s%s" % [SITE_NAME[s], d["state"].to_upper(), "" if d["found"] else " (zone only)"])
	var net: Node = sys()
	say("Hull monitor: %s · make-up %.2f kPa·m³/s" % [", ".join(rows) if not rows.is_empty() else "no impact events", float(net.press["makeup_flow"]) if net != null else 0.0], 5.0)


func _locate() -> void:
	var any := false
	for s in SITES:
		var d: Dictionary = dmg[s]
		if d["state"] == "damaged":
			d["found"] = true
			any = true
	sfx(&"relay")
	if not any:
		say("LOCATE: no unrepaired impact or leak zone.")
		return
	var s2: String = active_site if active_site != "" and dmg[active_site]["state"] == "damaged" else _first_damaged()
	var typ: String = SITES[s2][0]
	say("LOCATE: %s — %s, severity %d. %s" % [SITE_NAME[s2], {"puncture": "PENETRATION (linked to the B-04 leak)", "seam": "SEAM LEAK (make-up gas use)", "impact": "IMPACT on the MMOD cover"}[typ], int(dmg[s2]["sev"]),
		"EVA needed for the permanent repair (ring %s)." % SITES[s2][4]], 5.5)


func _first_damaged() -> String:
	for s in SITES:
		if dmg[s]["state"] == "damaged":
			return s
	return ""


var verified: bool = false
var deferred: String = ""


func _verify() -> void:
	var s: String = active_site
	if s == "":
		say("VERIFY: no hull order open.")
		return
	var e: Node = _eva()
	if e != null and (e.outside or e.suited):
		say("VERIFY from inside, out of the suit.")
		return
	var d: Dictionary = dmg[s]
	var net: Node = sys()
	var typ: String = SITES[s][0]
	if d["state"] == "repaired" or (typ == "impact" and int(d["sev"]) <= 1 and bool(d["probed"])):
		if typ == "puncture" and net != null:
			var ok: bool = net.leak_flow("B04") < 0.001 and net.pressure("B04") > 99.0
			if not ok:
				sfx(&"fail")
				say("VERIFY: B-04 is not back at station pressure yet (%.1f kPa) — equalise / hold-test it (L09)." % net.pressure("B04"), 4.5)
				return
		if typ == "seam" and net != null and net.leak_flow("A") > 0.01:
			sfx(&"fail")
			say("VERIFY: make-up gas still flowing — the seam is not sealed.")
			return
		verified = true
		sfx(&"success")
		say("VERIFY: %s — %s." % [SITE_NAME[s], "no breach, recorded" if typ == "impact" and int(d["sev"]) <= 1 else "repaired and holding"])
	else:
		sfx(&"fail")
		say("VERIFY: %s still %s." % [SITE_NAME[s], "damaged" if bool(d["found"]) else "not located (LOCATE first)"])


func _defer() -> void:
	var s: String = active_site
	if s == "" or dmg[s]["state"] != "damaged":
		say("DEFER: nothing to defer.")
		return
	var clr: Node = get_tree().get_first_node_in_group(&"clearance")
	var net: Node = sys()
	if s == "lower" and net != null and net.leak_flow("B04") > 0.05 and net.hatch_open("B04"):
		sfx(&"fail")
		say("DEFER refused: the B-04 penetration is still venting — patch it inside or isolate B-04 first (L09).", 4.5)
		return
	if clr != null and not clr.allows("eva"):
		deferred = "deferred_eva"
	elif _need_part(s) != &"" and not _part_exists(_need_part(s)) and not bool(dmg[s]["fitted"]):
		deferred = "deferred_part"
	elif s == "lower":
		deferred = "stabilized"          # held inside (patch / isolation), defect remains
	else:
		deferred = "deferred"
	sfx(&"success")
	say("Exterior repair DEFERRED (%s) — the site stays on the hull monitor." % deferred.replace("_", " "))


func _need_part(s: String) -> StringName:
	match SITES[s][0]:
		"puncture": return &"hull_patch_kit"
		"seam": return &"seam_seal_kit"
		"impact": return &"hull_panel" if int(dmg[s]["sev"]) >= 2 else &""
	return &""


func _part_exists(kind: StringName) -> bool:
	for p in get_tree().get_nodes_in_group(&"deck_b_part"):
		if p.get("item_id") == kind and not p.is_queued_for_deletion():
			return true
	return false


func _next_word(site: String) -> String:
	var d: Dictionary = dmg[site]
	if d["state"] == "none":
		return "Probe sweep (hull inspection probe)"
	if d["state"] == "repaired":
		return "Check the repair"
	if not bool(d["inspected"]):
		return "Inspect the damage (probe)"
	var typ: String = SITES[site][0]
	if typ == "impact" and int(d["sev"]) <= 1:
		return "Seal probe (record: no breach)"
	if typ == "impact" and not bool(d["removed"]):
		return "Remove the damaged panel" if (d["bolts"] as Array).size() >= 4 else "Back out a fastener"
	if not bool(d["prep"]) and typ != "impact":
		return "Prepare the surface"
	if not bool(d["fitted"]):
		return {"puncture": "Fit the patch plate (caddy)", "seam": "Lay the sealant bead (caddy)", "impact": "Fit the replacement panel (caddy)"}[typ]
	if int(d["align"]) != 0:
		return "Slide the patch into line"
	if not bool(d["seated"]):
		return "Seat the patch"
	if (d["bolts"] as Array).size() < 4:
		return "Torque a fastener (cross pattern)"
	return "Seal probe"


# ------------------------------------------------------------ the model
## A debris strike from the daily roll (rare; never before Deck B
## routine; the lower puncture only once Workshop access exists).
func strike_from_roll(d: int, tier: int) -> void:
	var r: int = absi(hash([d, "strike"])) % 3
	var site: String = ["impact", "seam", "lower"][r]
	if site == "lower" and tier < 2:
		site = "impact"
	strike(site, 1 + absi(hash([d, "ssev"])) % 3)
	for a in get_tree().get_nodes_in_group(&"station_ai"):
		a.event(&"hull_alert")


func strike(site: String, sev: int) -> void:
	if dmg[site]["state"] == "damaged":
		return
	dmg[site] = _fresh(site)
	dmg[site]["state"] = "damaged"
	dmg[site]["sev"] = clampi(sev, 1, 3)
	dmg[site]["day"] = day()
	var net: Node = sys()
	var lid: String = SITES[site][5]
	if net != null and lid != "":
		net.inject_leak(lid, sev)
	if net != null:
		net._log("HULL: impact sensor event — %s zone" % SITE_NAME[site].split(" ")[0])
	_refresh()


func clear_damage() -> void:
	for s in SITES:
		dmg[s] = _fresh(s)
	var net: Node = sys()
	if net != null:
		for lid in ["hull_b04", "hull_seam"]:
			net.press["leaks"] = net.press["leaks"].filter(func(x): return String(x["id"]) != lid)
	verified = false
	deferred = ""
	_refresh()


func _process(_delta: float) -> void:
	# A06 is raised by a REAL hull event once the monitor can see it: an
	# impact-sensor event, or the make-up flow a seam leak costs.
	_poll_t += _delta
	if _poll_t < 0.5:
		return
	_poll_t = 0.0
	var clr: Node = get_tree().get_first_node_in_group(&"clearance")
	if _dp != null and clr != null and clr.has_method("deck_b_tier") and int(clr.deck_b_tier()) >= 1 and not _dp.has_open_order(&"a06_hull"):
		for s in SITES:
			var d: Dictionary = dmg[s]
			if d["state"] == "damaged" and int(d.get("raised_day", -1)) != day():
				if s == "lower" and not bool(sys().leak("hull_b04").get("found", false)) and sys().press_alarm() < 1:
					continue      # the puncture surfaces through L09 first
				d["raised_day"] = day()
				_dp.raise_order(&"a06_hull", "%s — hull %s" % [SITE_NAME[s], {"puncture": "penetration", "seam": "seam leak", "impact": "impact"}[SITES[s][0]]])
				break
	_refresh()
var _poll_t: float = 0.0


func _refresh() -> void:
	for s in _vis:
		var v: Dictionary = _vis[s]
		var d: Dictionary = dmg[s]
		var typ: String = SITES[s][0]
		var damaged: bool = d["state"] == "damaged"
		(v["damaged"] as Node3D).visible = damaged and not (typ == "impact" and bool(d["removed"]))
		(v["patch"] as Node3D).visible = bool(d["fitted"]) and (damaged or (d["state"] == "repaired" and typ == "puncture"))
		(v["repaired"] as Node3D).visible = d["state"] == "repaired"
		(v["old_panel"] as Node3D).visible = damaged and typ == "impact" and bool(d["removed"]) and not bool(d["fitted"])
		if typ == "puncture":
			(v["patch"] as Node3D).position = Vector3(0.03 * float(d["align"]), 0, 0.026)   # over the curled blanket
			var fr: Node3D = (v["damaged"] as Node3D).get_node_or_null("Frost")
			if fr != null:
				fr.visible = damaged and _leak_live()
		var b: Array = d["bolts"]
		for k in (v["bolts"] as Array).size():
			var bn: Node3D = v["bolts"][k]
			bn.position.z = 0.012 if b.has(k) else 0.03
	if _mon != null:
		var rows: Array = []
		for s in SITES:
			var d2: Dictionary = dmg[s]
			rows.append("%-6s %s" % [s.to_upper(), "OK" if d2["state"] == "none" else ("%s S%d%s" % [d2["state"].to_upper().left(4), int(d2["sev"]), "" if d2["found"] else "?"])])
		var net: Node = sys()
		_mon.text = "%s\nMAKEUP %.2f%s" % ["\n".join(rows), float(net.press["makeup_flow"]) if net != null else 0.0, "\nVERIFIED" if verified else ""]


# ------------------------------------------------------------ A06 order
func task_rearm(t: StringName, seed: int) -> void:
	if t != &"a06_hull":
		return
	verified = false
	deferred = ""
	active_site = _first_damaged()
	if active_site == "":
		# A raise without a recorded hit (developer / story): a strike from
		# the seed, never the puncture before Workshop access.
		var clr: Node = get_tree().get_first_node_in_group(&"clearance")
		var tier: int = int(clr.deck_b_tier()) if clr != null and clr.has_method("deck_b_tier") else 1
		var pool: Array = ["impact", "seam"] + (["lower"] if tier >= 2 else [])
		active_site = pool[absi(seed) % pool.size()]
		strike(active_site, 1 + absi(seed / 3) % 3)


func task_done(t: StringName) -> bool:
	if t != &"a06_hull" or active_site == "":
		return t != &"a06_hull"
	var d: Dictionary = dmg[active_site]
	var typ: String = SITES[active_site][0]
	if verified:
		var res: String = "inspected_no_breach" if typ == "impact" and int(d["sev"]) <= 1 else "repaired"
		close_task(t, res, SITE_NAME[active_site], "%s (severity %d)" % [typ, int(d["sev"])], "probe, %s" % ("recorded" if res == "inspected_no_breach" else "exterior repair, cross-torqued, seal probe"), "verified from inside")
		if res == "inspected_no_breach":
			d["state"] = "none"
		return true
	if deferred != "":
		close_task(t, deferred, SITE_NAME[active_site], "%s (severity %d)" % [typ, int(d["sev"])], "located on the hull monitor; %s" % ("temporary patch inside" if deferred == "stabilized" else "exterior repair deferred"), "site remains on the hull monitor")
		return true
	return false


func task_next(t: StringName) -> Dictionary:
	if t != &"a06_hull" or active_site == "":
		return {}
	var d: Dictionary = dmg[active_site]
	var e: Node = _eva()
	if not bool(d["found"]):
		return next("Airlock HULL MONITOR: LOCATE the damage", "LOCATE")
	if d["state"] == "repaired" or (SITES[active_site][0] == "impact" and int(d["sev"]) <= 1 and bool(d["probed"])):
		if e != null and (e.outside or e.suited):
			return next("Return inside, stow the suit", "RETURN")
		return next("HULL MONITOR: VERIFY from inside", "VERIFY")
	var need: StringName = _need_part(active_site)
	if not (e != null and e.outside):
		if need != &"" and _caddy_item([need]) == null and not bool(d.get("fitted", false)):
			return next("Load the %s into the SUIT CADDY (EVA repair stock) — or DEFER" % Part.KINDS[need]["name"], "LOAD CADDY")
		return {"action": "Suit up (A01 status), airlock OUT, tether to %s, grab the %s handhold" % [SITES[active_site][4], SITE_NAME[active_site]], "short": "EVA", "room": &"airlock"}
	if not e.at_worksite("hull_" + active_site):
		return {"action": "Tether to %s and grab the %s handhold" % [SITES[active_site][4], SITE_NAME[active_site]], "short": "WORKSITE", "room": &"airlock"}
	return {"action": _next_word(active_site), "short": "HULL WORK", "room": &"airlock"}


func task_progress(t: StringName) -> String:
	if t != &"a06_hull" or active_site == "":
		return ""
	var d: Dictionary = dmg[active_site]
	return "%s · %s · fasteners %d/4" % [SITE_NAME[active_site], d["state"], (d["bolts"] as Array).size()]


func task_detail(t: StringName) -> Array:
	if t != &"a06_hull" or active_site == "":
		return []
	return ["Site %s (ring %s), %s severity %d" % [SITE_NAME[active_site], SITES[active_site][4], SITES[active_site][0], int(dmg[active_site]["sev"])],
		"Inside: LOCATE / VERIFY / DEFER at the hull monitor. Outside: probe, prepare, fit, cross-torque, seal probe."]


func task_feasible(_t: StringName) -> bool:
	return true                    # deferral always exists


func task_severity(t: StringName) -> int:
	return 2 if t == &"a06_hull" and active_site == "lower" else 1


## Story-gated anomaly hook (foundation only, NEVER in normal play): a
## site that LOOKS already repaired, with a service record naming nobody.
## preview = developer F8 (no state written, nothing advanced).
func repaired_by_unknown(site: String, preview: bool) -> Dictionary:
	var rec := {"day": day(), "site": SITE_NAME.get(site, site), "text": "patch installed — technician: (blank)", "preview": preview}
	if not preview:
		anomaly_log.append(rec)
	return rec


func state_dict() -> Dictionary:
	return {"outcome": outcome.duplicate(), "dmg": dmg.duplicate(true), "active_site": active_site, "verified": verified, "deferred": deferred, "anomaly_log": anomaly_log.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	outcome = d.get("outcome", {})
	var dd: Dictionary = d.get("dmg", {})
	for s in SITES:
		dmg[s] = _fresh(s)
		if dd.has(s):
			for k in dd[s]:
				dmg[s][k] = dd[s][k]
			var b: Array = []
			for x in Array(dmg[s]["bolts"]):
				b.append(int(x))
			dmg[s]["bolts"] = b
	active_site = String(d.get("active_site", ""))
	verified = bool(d.get("verified", false))
	deferred = String(d.get("deferred", ""))
	anomaly_log = Array(d.get("anomaly_log", []))
	_refresh()
