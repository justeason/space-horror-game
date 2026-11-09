extends Node
## Round 41 Priorities 13-17: the STORY EVENT director -- one small,
## common architecture for the psychological-horror beats, deliberately
## SEPARATE from DayPlan (maintenance stays authoritative there; events
## only OBSERVE station / task / player state and never create work).
##
## Locked narrative phases (GAME_DESIGN): day 1-5 PHASE 1 "This is my
## job" (no events at all), day 6-11 PHASE 2 "Something is wrong" (rare,
## subtle contradictions), day 12+ PHASE 3 "I don't know what reality is".
##
## Every event has a STABLE id and:
##   min_day / phase gate, chance (a DETERMINISTIC per-day roll: hash of
##   the day + id, so a reload never re-rolls), cooldown_days, max_plays,
##   an eligibility check on live state, a start, a safe stop (cancellable
##   at any moment, leaves nothing behind), and saved played/seen state.
## Pacing: at most ONE event is armed per day; an armed event still needs
## its live conditions, so missing it costs nothing (no punishment, no
## mandatory camera watching). No popups, no announcements, no music
## stingers, no explanation, no identity.
##
## Implemented (enabled):
##   corridor_presence -- the corridor camera INT-02 (Junction -> Control)
##     shows a dark, motionless person-shaped outline BEHIND the seated
##     technician. It is on the CAMERA_ONLY layer: the player's eyes, the
##     mirror and the window never render it; it has no collision. It
##     appears only after the technician has watched INT-02 for a while
##     (and has watched it on an EARLIER day, so the normal view is
##     familiar), and is gone the instant they stand, turn round or leave
##     the feed (or after a few seconds).
##   window_mismatch -- while the technician looks out of the observation
##     port, the shared courtyard view and camera EXT-03 start to DISAGREE
##     (observation_discrepancy.gd "displaced": a tethered tool bag drifts
##     by the mast in the window, but sits by the hatch on camera) for a
##     short while, then both agree again.
## Foundations (registered, DISABLED -- later rounds turn them on through
## the same API): hatch_handle, blind_spot_object, wrong_reading,
## radio_contact, laptop_inconsistency.

const CAMERA_ONLY := 1 << 18
const EVENTS := {
	&"corridor_presence": {"min_day": 7, "chance": 0.55, "cooldown_days": 3, "max_plays": 3, "enabled": true},
	&"window_mismatch": {"min_day": 9, "chance": 0.5, "cooldown_days": 4, "max_plays": 2, "enabled": true},
	&"hatch_handle": {"min_day": 14, "chance": 0.4, "cooldown_days": 5, "max_plays": 1, "enabled": false},
	&"blind_spot_object": {"min_day": 12, "chance": 0.4, "cooldown_days": 4, "max_plays": 2, "enabled": false},
	&"wrong_reading": {"min_day": 10, "chance": 0.4, "cooldown_days": 4, "max_plays": 2, "enabled": false},
	&"radio_contact": {"min_day": 15, "chance": 1.0, "cooldown_days": 99, "max_plays": 1, "enabled": false},
	&"laptop_inconsistency": {"min_day": 16, "chance": 0.4, "cooldown_days": 6, "max_plays": 1, "enabled": false},
}
const PRESENCE_WATCH_S := 6.0      # continuous INT-02 viewing before it can appear
const PRESENCE_MAX_S := 9.0
const PRESENCE_SEEN_S := 1.2       # on screen this long while watched = seen
const WINDOW_GAZE_S := 2.5
const WINDOW_EVENT_S := 40.0
## Where the outline stands, by play count (always far from the camera,
## small on the feed): just inside the Control Room doorway, half hidden
## by the west jamb; then mid-room; then right behind the operator's stool.
const PRESENCE_SPOTS := [Vector3(-0.55, 0.0, 1.75), Vector3(0.35, 0.0, 1.0), Vector3(0.22, 0.0, 0.3)]

@export var day_plan_path: NodePath = ^"../DayPlan"
var _dp: Node
## id -> {plays, last_day, armed_day, seen}
var state: Dictionary = {}
var feed_days: Dictionary = {}     # camera id -> [days it was watched]
var armed_for_day: int = -1        # the day the arming roll was made for
var active: StringName = &""
var history: Array = []            # [{id, day, event}] (session log, tests)
var _watch_id: String = ""
var _watch_s: float = 0.0
var _last_feed_ms: int = 0
var _active_t: float = 0.0
var _on_screen_s: float = 0.0
var _gaze_s: float = 0.0
var _presence: Node3D
var _poll: float = 0.0


func _ready() -> void:
	add_to_group(&"story_events")
	add_to_group(&"r35_equipment")      # SaveGame persists state_dict()/load_dict()
	_dp = get_node_or_null(day_plan_path)
	for id in EVENTS:
		state[id] = {"plays": 0, "last_day": -99, "armed_day": -1, "seen": false}
	_presence = _build_presence()


static func phase_for_day(day: int) -> int:
	return 1 if day <= 5 else (2 if day <= 11 else 3)


func day() -> int:
	return int(_dp.day_number) if _dp != null else 1


func phase() -> int:
	return phase_for_day(day())


func _root() -> Node:
	return get_parent()


# ------------------------------------------------------------- arming
## Deterministic daily arming: at most one event, never before its day,
## respecting cooldown / max plays. Same day + same history -> same result.
func _arm_today() -> void:
	var d: int = day()
	if armed_for_day == d:
		return
	armed_for_day = d
	for id in EVENTS:
		var e: Dictionary = EVENTS[id]
		var st: Dictionary = state[id]
		if not e["enabled"] or d < int(e["min_day"]) or int(st["plays"]) >= int(e["max_plays"]):
			continue
		if d - int(st["last_day"]) < int(e["cooldown_days"]):
			continue
		var roll: int = absi(hash([d, String(id), "story"])) % 100
		if roll < int(float(e["chance"]) * 100.0):
			st["armed_day"] = d
			return


func is_armed(id: StringName) -> bool:
	return state.has(id) and int(state[id]["armed_day"]) == day() and int(state[id]["last_day"]) != day()


## Tests / tools (debug builds): arm an event for today regardless of the
## roll -- every live condition still applies.
func debug_arm(id: StringName) -> bool:
	if not OS.is_debug_build() or not state.has(id):
		return false
	armed_for_day = day()
	for k in state:
		if int(state[k]["armed_day"]) == day():
			state[k]["armed_day"] = -1
	state[id]["armed_day"] = day()
	return true


# ---------------------------------------------------------- observation
## workstation_shell.gd calls this while a feed is on screen.
func on_feed_viewed(id: String) -> void:
	var now: int = Time.get_ticks_msec()
	if id != _watch_id or now - _last_feed_ms > 600:
		_watch_id = id
		_watch_s = 0.0
	_last_feed_ms = now
	var days: Array = feed_days.get(id, [])
	if not days.has(day()):
		days.append(day())
		feed_days[id] = days


func watched_before_today(id: String) -> bool:
	return Array(feed_days.get(id, [])).any(func(x): return int(x) < day())


func _shell() -> Node:
	return _root().get_node_or_null("Interactables/WorkstationConsole/WorkstationScreen/Shell") if _root() != null else null


func _ws_in_use() -> bool:
	var ws: Node = _root().get_node_or_null("WorkstationState")
	return ws != null and ws.has_method("is_in_use") and ws.is_in_use()


func _watching(cam_id: String) -> bool:
	var sh: Node = _shell()
	return _ws_in_use() and sh != null and int(sh.page) == 1 and String(sh.selected_cam) == cam_id and Time.get_ticks_msec() - _last_feed_ms < 600


func _player_cam() -> Camera3D:
	return _root().get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") as Camera3D


func _emergency() -> bool:
	var st: Node = _root().get_node_or_null("StationStatus")
	return st != null and not st.emergency().is_empty()


# ------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if _dp == null:
		return
	if _watch_id != "" and Time.get_ticks_msec() - _last_feed_ms < 600:
		_watch_s += delta
	if active != &"":
		_update_active(delta)
		return
	_poll += delta
	if _poll < 0.25:
		return
	var dt: float = _poll
	_poll = 0.0
	_arm_today()
	if is_armed(&"corridor_presence") and _presence_ready():
		_start(&"corridor_presence")
	elif is_armed(&"window_mismatch"):
		if _gazing_at_window():
			_gaze_s += dt
			if _gaze_s >= WINDOW_GAZE_S and watched_before_today("EXT-03") and not _emergency():
				_start(&"window_mismatch")
		else:
			_gaze_s = 0.0


func _presence_ready() -> bool:
	return _watching("INT-02") and _watch_s >= PRESENCE_WATCH_S and watched_before_today("INT-02") \
		and float(_dp.shift_elapsed_s) > 90.0 and not _emergency()


func _gazing_at_window() -> bool:
	var cam: Camera3D = _player_cam()
	var win: Node3D = _root().get_node_or_null("Interactables/WallWatchWindow") as Node3D
	if cam == null or win == null or _ws_in_use():
		return false
	var to: Vector3 = win.global_position - cam.global_position
	return to.length() < 2.6 and (-cam.global_basis.z).dot(to.normalized()) > 0.8


func _start(id: StringName) -> void:
	active = id
	_active_t = 0.0
	_on_screen_s = 0.0
	history.append({"id": String(id), "day": day(), "event": "start"})
	match id:
		&"corridor_presence":
			var spot: Vector3 = PRESENCE_SPOTS[mini(int(state[id]["plays"]), PRESENCE_SPOTS.size() - 1)]
			_presence.position = spot
			_presence.visible = true
		&"window_mismatch":
			var od: Node = get_tree().get_first_node_in_group(&"observation_discrepancy")
			if od == null or not od.trigger("displaced", WINDOW_EVENT_S, "event"):
				stop(false)


func _update_active(delta: float) -> void:
	_active_t += delta
	match active:
		&"corridor_presence":
			var watching: bool = _watching("INT-02")
			if watching:
				_on_screen_s += delta
			# The technician checks (turns toward the doorway behind them),
			# stands up, or leaves the feed -> it is simply not there.
			var cam: Camera3D = _player_cam()
			var turned: bool = cam != null and (-cam.global_basis.z).z > 0.25
			if not watching or turned or not _ws_in_use() or _active_t >= PRESENCE_MAX_S:
				stop(_on_screen_s >= PRESENCE_SEEN_S)
		&"window_mismatch":
			var od: Node = get_tree().get_first_node_in_group(&"observation_discrepancy")
			if od == null or not od.is_active():
				stop(true)


## Safe stop: hides everything the event showed; records the play.
func stop(seen: bool = false) -> void:
	if active == &"":
		return
	var id: StringName = active
	active = &""
	_presence.visible = false
	if id == &"window_mismatch":
		var od: Node = get_tree().get_first_node_in_group(&"observation_discrepancy")
		if od != null and od.is_active():
			od.clear()
	var st: Dictionary = state[id]
	st["plays"] = int(st["plays"]) + 1
	st["last_day"] = day()
	st["seen"] = bool(st["seen"]) or seen
	_watch_s = 0.0
	_gaze_s = 0.0
	history.append({"id": String(id), "day": day(), "event": "stop", "seen": seen})


func presence_visible() -> bool:
	return _presence != null and _presence.visible


func presence_node() -> Node3D:
	return _presence


# ------------------------------------------------------------- visuals
## A dark, faceless, motionless person-shaped outline (no features, no
## detail -- an absence of light in a human shape). CAMERA_ONLY layer,
## no collision, no shadow.
func _build_presence() -> Node3D:
	var root := Node3D.new()
	root.name = "CorridorPresence"
	var host: Node = _root()
	host.add_child.call_deferred(root)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.035, 0.04)      # dim, matte -- room light still models its shape
	m.roughness = 1.0
	var add := func(mesh: Mesh, pos: Vector3, scl: Vector3) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.position = pos
		mi.scale = scl
		mi.layers = CAMERA_ONLY
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var cap := CapsuleMesh.new()
	cap.radius = 0.19
	cap.height = 1.05
	add.call(cap, Vector3(0, 1.12, 0), Vector3(1.0, 1.0, 0.62))      # torso
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.25
	add.call(head, Vector3(0, 1.72, 0.0), Vector3.ONE)
	var limb := CapsuleMesh.new()
	limb.radius = 0.07
	limb.height = 0.85
	add.call(limb, Vector3(-0.1, 0.45, 0), Vector3.ONE)              # legs
	add.call(limb, Vector3(0.1, 0.45, 0), Vector3.ONE)
	var arm := CapsuleMesh.new()
	arm.radius = 0.055
	arm.height = 0.72
	add.call(arm, Vector3(-0.25, 1.12, 0), Vector3.ONE)             # arms hang
	add.call(arm, Vector3(0.25, 1.12, 0), Vector3.ONE)
	root.visible = false
	return root


# ---------------------------------------------------------- save / load
## Transient state (an event in progress) is never saved: a load starts
## with nothing showing, and today's arming is reproduced deterministically.
func state_dict() -> Dictionary:
	var ev := {}
	for id in state:
		ev[String(id)] = state[id].duplicate()
	return {"events": ev, "feed_days": feed_days.duplicate(true), "armed_for_day": armed_for_day}


func load_dict(d: Dictionary) -> void:
	if active != &"":
		stop(false)
		history.pop_back()
	var ev: Dictionary = d.get("events", {})
	for id in state:
		if ev.has(String(id)):
			var src: Dictionary = ev[String(id)]
			state[id] = {"plays": int(src.get("plays", 0)), "last_day": int(src.get("last_day", -99)), "armed_day": int(src.get("armed_day", -1)), "seen": bool(src.get("seen", false))}
	feed_days = {}
	var fd: Dictionary = d.get("feed_days", {})
	for k in fd:
		feed_days[String(k)] = Array(fd[k]).map(func(x): return int(x))
	armed_for_day = int(d.get("armed_for_day", -1))
