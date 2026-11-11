extends Node
## Round 37 Priorities 4-7 and 12: ONE derivation of "what needs doing,
## where, and how urgently" -- read by the workstation map, the emergency
## banner, the wristwatch, the warning beacons and the station assistant,
## so the same failure can never show differently in different places.
##
## Severity: 0 NORMAL, 1 ROUTINE, 2 WARNING, 3 EMERGENCY.
##   - every open assignment row (DayPlan.order_rows) carries its
##     equipment's own order_severity() (vent dirt/airflow, seal leak,
##     breaker state, power overload, thermal hot spot ...);
##   - equipment conditions WITHOUT an open order are duties too, from
##     the equipment itself: a tripped breaker (room dark) -> WARNING in
##     Engineering; an overloaded Bus A -> EMERGENCY;
##   - a room's status = the highest severity among its duties.
## Emergency: the equipment's emergency_info() -- a REAL pending timed
## consequence (today: Bus A overload -> B-03 trip). Its countdown is the
## equipment's own timer: it pauses with the tree, is saved with the
## equipment, and disappears when the cause is cleared or the
## consequence happens.
## Nothing here is saved: everything is reconstructed from authoritative
## equipment / DayPlan state.

const GS = preload("res://scripts/station/game_settings.gd")
enum Sev { NORMAL, ROUTINE, WARNING, EMERGENCY }
const SEV_NAMES := ["NORMAL", "ROUTINE", "WARNING", "EMERGENCY"]
const MAP_ROOMS := [&"living_quarters", &"control_room", &"main_junction", &"communications", &"life_support", &"engineering", &"storage", &"airlock"]
const ROOM_NAMES := {&"living_quarters": "QUARTERS", &"control_room": "CONTROL", &"main_junction": "JUNCTION", &"communications": "COMMS", &"life_support": "LIFE SUPPORT", &"engineering": "ENGINEERING", &"storage": "STORAGE", &"airlock": "AIRLOCK"}
## Red warning beacons: [room, wall-mounted position, facing (yaw deg)].
const BEACONS := [
	[&"engineering", Vector3(-2.68, 2.55, 4.2), -90.0],
	[&"engineering", Vector3(-5.74, 2.55, 5.8), 90.0],
	[&"main_junction", Vector3(-0.95, 2.35, 6.1), 90.0],   # corridor at the Engineering doorway
	[&"life_support", Vector3(-1.38, 2.55, 11.4), -90.0],
	[&"airlock", Vector3(-4.35, 2.25, -0.2), -90.0],
]
## Rooms whose emergency also lights a neighbouring corridor beacon.
const CORRIDOR_FOR := {&"engineering": &"main_junction"}

@export var day_plan_path: NodePath = ^"../DayPlan"
@export var hud_path: NodePath = ^"../Player/HUD"
var _dp: Node
var _beacons: Array = []          # [{room, light, lens}]
var _banner: PanelContainer
var _banner_label: Label
var _banner_icon: Label
var _t: float = 0.0
var _last_emergency_id: String = ""
var _alert_30_done: bool = false
var alert_log: Array = []         # [{id, kind, t}]


func _ready() -> void:
	add_to_group(&"station_status")
	_dp = get_node_or_null(day_plan_path)
	_build_beacons()
	_build_banner()


func _eq(n: String) -> Node:
	return get_parent().get_node_or_null("Equipment/" + n) if get_parent() != null else null


# ================================================================ model
## Every duty: [{room, tag, action, severity, id}] (open orders first).
func duties() -> Array:
	var out: Array = []
	if _dp == null:
		return out
	# Day 1 (no workday): the orientation tasks, from DayPlan's own fields.
	if int(_dp.workday) == 0:
		var room: StringName = _dp.get_outstanding_task_room()
		if room != &"":
			var act: String = "Check in at the workstation"
			var sev := Sev.ROUTINE
			if _dp.is_task_done(&"c01"):
				if room == &"engineering" and _dp.fault_target != &"":
					act = "Repair the power fault"
					sev = Sev.WARNING
				elif room == &"engineering":
					act = "Tighten loose connection"
				elif room == &"storage":
					act = "Get the spare wire"
				else:
					act = "Verify the repair"
			out.append({"room": room, "tag": "ORIENT", "action": act, "severity": sev, "id": "DAY1"})
	var has_breaker_order: bool = _dp.has_open_order(&"breaker")
	var has_power_order: bool = _dp.has_open_order(&"power")
	for r in _dp.order_rows():
		if r.get("done", false):
			continue
		var room: StringName = StringName(r.get("room", &""))
		if room == &"":
			room = &"control_room"
		out.append({"room": room, "tag": String(r["tag"]), "action": String(r["action"]), "severity": int(r.get("severity", 1)), "id": String(r["id"])})
	var br: Node = _eq("BreakerPanel")
	if br != null and not has_breaker_order:
		for i in br.BREAKERS.size():
			if not br.on[i]:
				out.append({"room": &"engineering", "tag": "BREAKER", "action": "Reset breaker %s" % br.BREAKERS[i]["id"], "severity": Sev.WARNING, "id": "COND-%s" % br.BREAKERS[i]["id"]})
	var sa: Node = _eq("SolarArrays")
	if sa != null and not (_dp.has_open_order(&"solar_coupler") or _dp.has_open_order(&"solar_hinge") or _dp.has_open_order(&"solar_clean")):
		var cd: Dictionary = sa.condition_duty()
		if not cd.is_empty():
			out.append(cd)
	var pw: Node = _eq("PowerDistribution")
	if pw != null and not has_power_order and pw.is_overloaded():
		out.append({"room": &"engineering", "tag": "LOADS", "action": "Reduce Bus A load", "severity": Sev.EMERGENCY, "id": "COND-overload"})
	# Round 46: story PRESENTATION duties (e.g. a calibration the workstation
	# denies). Display only -- never DayPlan state.
	var se: Node = get_tree().get_first_node_in_group(&"story_events") if is_inside_tree() else null
	if se != null and se.has_method("workstation_overlay"):
		out += se.workstation_overlay()
	return out


## room -> {severity, duties: [...]}, for every map room.
func rooms() -> Dictionary:
	var out := {}
	for r in MAP_ROOMS:
		out[r] = {"severity": Sev.NORMAL, "duties": []}
	for d in duties():
		var room: StringName = d["room"]
		if not out.has(room):
			out[room] = {"severity": Sev.NORMAL, "duties": []}
		out[room]["duties"].append(d)
		out[room]["severity"] = maxi(int(out[room]["severity"]), int(d["severity"]))
	return out


func room_severity(room: StringName) -> int:
	return int(rooms().get(room, {"severity": 0})["severity"])


## The active timed emergency (the most urgent), or {}.
func emergency() -> Dictionary:
	var best: Dictionary = {}
	var eq: Node = get_parent().get_node_or_null("Equipment") if get_parent() != null else null
	if eq == null:
		return best
	for n in eq.get_children():
		if n.has_method("emergency_info"):
			var e: Dictionary = n.emergency_info()
			if not e.is_empty() and (best.is_empty() or float(e["seconds"]) < float(best["seconds"])):
				best = e
	return best


static func clock(seconds: float) -> String:
	var s: int = ceili(maxf(seconds, 0.0))
	return "%02d:%02d" % [s / 60, s % 60]


## "POWER OVERLOAD · ENGINEERING · 01:24"
func emergency_line() -> String:
	var e: Dictionary = emergency()
	if e.is_empty():
		return ""
	return "%s · %s · %s" % [e["title"], ROOM_NAMES.get(StringName(e["room"]), "STATION"), clock(float(e["seconds"]))]


# ============================================================ presentation
func _process(delta: float) -> void:
	_t += delta
	var e: Dictionary = emergency()
	_update_banner(e)
	_update_beacons(e)
	_update_alerts(e)


func _build_banner() -> void:
	var hud: Node = get_node_or_null(hud_path)
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "EmergencyBannerLayer"
	add_child(layer)
	var root := Control.new()
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.offset_left = -270.0
	root.offset_right = 270.0
	root.offset_top = 6.0
	root.offset_bottom = 38.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_banner = PanelContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.03, 0.02, 0.86)
	sb.border_color = Color(1.0, 0.3, 0.2)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(5)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	_banner.add_theme_stylebox_override("panel", sb)
	root.add_child(_banner)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_banner.add_child(h)
	_banner_icon = Label.new()
	_banner_icon.text = "!"
	_banner_icon.add_theme_font_size_override("font_size", 18)
	_banner_icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	h.add_child(_banner_icon)
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 16)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.88))
	h.add_child(_banner_label)
	_banner.visible = false
	preload("res://scripts/station/station_ai.gd")._ignore_mouse(layer)


func _update_banner(e: Dictionary) -> void:
	if _banner == null:
		return
	# Seated at the workstation, its own emergency strip shows it (the HUD
	# banner would sit on the monitor's tab bar).
	var ws: Node = get_parent().get_node_or_null("WorkstationState") if get_parent() != null else null
	var seated: bool = ws != null and ws.has_method("is_in_use") and ws.is_in_use()
	_banner.visible = not e.is_empty() and not seated
	if e.is_empty():
		return
	_banner_label.text = "%s · %s · %s   %s" % [e["title"], ROOM_NAMES.get(StringName(e["room"]), ""), clock(float(e["seconds"])), String(e.get("action", ""))]
	var steady: bool = bool(GS.get_value("steady_warnings"))
	_banner_icon.modulate.a = 1.0 if steady else 0.55 + 0.45 * absf(sin(_t * 2.2))


func banner_text() -> String:
	return _banner_label.text if _banner != null and _banner.visible else ""


func _build_beacons() -> void:
	for b in BEACONS:
		var root := Node3D.new()
		root.name = "WarningBeacon_%s_%d" % [String(b[0]), _beacons.size()]
		add_child(root)
		root.global_position = b[1]
		root.rotation_degrees.y = b[2]
		var base := CSGBox3D.new()
		base.size = Vector3(0.12, 0.08, 0.04)
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.2, 0.21, 0.22)
		base.material = bm
		root.add_child(base)
		var lens := CSGCylinder3D.new()
		lens.radius = 0.035
		lens.height = 0.05
		lens.rotation_degrees.x = 90.0
		lens.position.z = 0.04
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.35, 0.05, 0.04)
		lm.emission_enabled = true
		lm.emission = Color(0, 0, 0)
		lens.material = lm
		root.add_child(lens)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.12, 0.08)
		light.light_energy = 0.0
		light.omni_range = 3.2
		light.shadow_enabled = false
		light.position.z = 0.12
		root.add_child(light)
		_beacons.append({"room": b[0], "light": light, "lens": lm, "root": root})


## Rooms whose beacons are active now.
func alarm_rooms(e: Dictionary = {}) -> Array:
	if e.is_empty():
		e = emergency()
	if e.is_empty():
		return []
	var out: Array = [StringName(e["room"])]
	if CORRIDOR_FOR.has(StringName(e["room"])):
		out.append(CORRIDOR_FOR[StringName(e["room"])])
	return out


func _update_beacons(e: Dictionary) -> void:
	var active: Array = alarm_rooms(e)
	var steady: bool = bool(GS.get_value("steady_warnings"))
	# Slow, controlled pulse (0.5 Hz, no strobe); steady when requested.
	var k: float = 0.75 if steady else 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * PI))
	for b in _beacons:
		var on: bool = b["room"] in active
		(b["light"] as OmniLight3D).light_energy = 1.1 * k if on else 0.0
		var m: StandardMaterial3D = b["lens"]
		m.emission = Color(1.0, 0.15, 0.1) * (2.0 * k) if on else Color(0, 0, 0)
		m.albedo_color = Color(0.9, 0.12, 0.08) if on else Color(0.35, 0.05, 0.04)


func beacon_energy(room: StringName) -> float:
	for b in _beacons:
		if b["room"] == room:
			return (b["light"] as OmniLight3D).light_energy
	return 0.0


## Positional alert tone on the affected room's speaker: at onset, and once
## more with 30 s left (escalation) -- never continuously.
func _update_alerts(e: Dictionary) -> void:
	var id: String = String(e.get("id", ""))
	if id != _last_emergency_id:
		_last_emergency_id = id
		_alert_30_done = false
		if id != "":
			_alert(StringName(e["room"]), "onset")
	elif id != "" and not _alert_30_done and float(e["seconds"]) <= 30.0:
		_alert_30_done = true
		_alert(StringName(e["room"]), "escalation")


var _tone: AudioStreamWAV


func _alert(room: StringName, kind: String) -> void:
	alert_log.append({"room": String(room), "kind": kind, "t": _t})
	var sp: Node = get_tree().get_first_node_in_group(&"station_speakers") if is_inside_tree() else null
	if sp == null:
		return
	if _tone == null:
		_tone = _build_tone()
	sp.play_tone(room if sp.units.has(room) else sp.unit_for(sp.unit_position(room)), _tone, -4.0)


## Two-tone intercom alert (two short descending pairs), synthesized.
static func _build_tone() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.1)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t: float = float(i) / rate
		var seg: int = int(t / 0.275)
		var lt: float = fmod(t, 0.275)
		var f: float = 740.0 if seg % 2 == 0 else 587.0
		var env: float = minf(lt * 60.0, 1.0) * clampf((0.24 - lt) * 30.0, 0.0, 1.0)
		var smp: float = (sin(TAU * f * t) * 0.55 + sin(TAU * f * 3.0 * t) * 0.08) * env * 0.45
		bytes.encode_s16(i * 2, int(clampf(smp, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = bytes
	return s
