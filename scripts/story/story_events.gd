extends Node
## Round 41 / Round 42: the STORY EVENT director -- one small, common
## architecture for the psychological-horror beats, deliberately SEPARATE
## from DayPlan (maintenance stays authoritative there; events only
## OBSERVE station / task / player state and never create work, never
## change real equipment state).
##
## ROUND 42: PHASES ARE NARRATIVE, NOT CALENDAR.
##   PHASE 1 "This is my job."  No anomalies at all. Ends only when ALL of:
##     intro_complete   -- the first shift has been worked and slept through;
##     station_familiar -- the technician has closed >= 3 different kinds of
##                         duty AND used the surveillance feeds on two
##                         different days (knows what "normal" looks like);
##     handover_read    -- a DELIBERATE narrative act: the previous
##                         technician's handover note has been read on the
##                         personal laptop (the assistant mentions the note
##                         once the technician is familiar with the station).
##   PHASE 2 "Something is wrong."  Rare, subtle contradictions. "Late"
##     phase 2 (harder-to-dismiss events) once two DIFFERENT anomalies
##     were actually SEEN (noticed), not merely played.
##   PHASE 3 "I don't know what reality is."  Requires three different
##     anomalies seen AND two INVESTIGATIONS (the technician physically
##     checked: turned to look behind them during the presence, went to the
##     airlock after the hatch handle moved, compared the wall panel with
##     the workstation...). Phase 3 unlocks the abnormal variants.
##   The calendar day, shift progress, proficiency and equipment condition
##   are separate systems; working 20 uneventful days stays phase 1.
##
## Every event has a STABLE id, a name, a minimum phase (and stage), a
## DETERMINISTIC daily roll (hash of day + id: a reload never re-rolls),
## cooldown_days, max_plays, live conditions (`needs`, shown to developers),
## a start, a SAFE stop (cancellable at any moment, leaves nothing behind),
## and saved played / seen state. Pacing: at most ONE event armed per day;
## an armed event still needs its live conditions, so missing it costs
## nothing. No popups, no announcements, no music stingers, no explanation.
##
## Implemented: corridor_presence, window_mismatch, hatch_handle,
## wrong_reading. Registered but UNAVAILABLE (not implemented -- never
## listed as functional): blind_spot_object, radio_contact,
## laptop_inconsistency.
##
## DEVELOPER LAYER (debug builds only, scripts/dev/dev_panel.gd): trigger /
## preview / cancel / reset / mark seen / enable, a phase OVERRIDE -- all
## transient: dev_* calls never count plays unless asked, and the override
## is never written into a save.

const CAMERA_ONLY := 1 << 18
const DIRECT_ONLY := 1 << 19
## id -> registry entry.
const EVENTS := {
	&"corridor_presence": {"name": "Presence behind the operator", "phase": 2, "late": false, "chance": 0.55, "cooldown_days": 3, "max_plays": 3, "enabled": true, "implemented": true,
		"needs": "Seated at the workstation, Cameras page, INT-02 watched for 6 s (and on an earlier day). Ends on stand / turn round / feed change.",
		"variants": ["normal", "abnormal"]},
	&"window_mismatch": {"name": "Window / camera disagree", "phase": 2, "late": false, "chance": 0.5, "cooldown_days": 4, "max_plays": 2, "enabled": true, "implemented": true,
		"needs": "Standing at the Control Room observation port, looking out 2.5 s (EXT-03 watched on an earlier day).",
		"variants": ["normal"]},
	&"wrong_reading": {"name": "Contradictory instrument", "phase": 2, "late": false, "chance": 0.45, "cooldown_days": 4, "max_plays": 2, "enabled": true, "implemented": true,
		"needs": "Looking at the Control Room ENVIRONMENT wall panel (within 3 m) for 1.5 s. The workstation keeps the true value.",
		"variants": ["normal", "abnormal"]},
	&"hatch_handle": {"name": "Outer hatch handle turns", "phase": 2, "late": true, "chance": 0.45, "cooldown_days": 5, "max_plays": 2, "enabled": true, "implemented": true,
		"needs": "Inside the station, away from the airlock. A knock sounds at the airlock; on INT-07 (chamber camera) the outer hatch's dogging lever turns. Going to the airlock ends it.",
		"variants": ["normal", "abnormal"]},
	&"note_extra_item": {"name": "Daily note: an item nobody issued", "phase": 2, "late": false, "chance": 0.4, "cooldown_days": 5, "max_plays": 2, "enabled": true, "implemented": true,
		"needs": "Open TODAY'S NOTE on the laptop. One extra checklist line is shown (presentation only); it is gone the next time the note is opened. The note's History (archive) shows it was never issued.",
		"variants": ["normal", "abnormal"]},
	&"phantom_cycle": {"name": "Airlock heard cycling (nothing commanded)", "phase": 2, "late": false, "chance": 0.4, "cooldown_days": 4, "max_plays": 2, "enabled": true, "implemented": true,
		"needs": "Inside, 8 m+ from the airlock, not suited. The airlock's latch + vent hiss + latch play FROM the airlock; no state change, no log entry. Going there = a check; the AIRLOCK record shows no cycle.",
		"variants": ["normal"]},
	&"access_ghost": {"name": "Access log: an entry you didn't make", "phase": 2, "late": false, "chance": 0.35, "cooldown_days": 5, "max_plays": 1, "enabled": true, "implemented": true,
		"needs": "A module not yet entered today. The ACCESS record (workstation RECORDS) shows '<ROOM> · entered · TECH-1' earlier today (presentation only). Seen when the record is read.",
		"variants": ["normal"]},
	&"family_misremember": {"name": "Family letter quotes something never written", "phase": 2, "late": true, "chance": 0.5, "cooldown_days": 99, "max_plays": 1, "enabled": true, "implemented": true,
		"needs": "A family answer already delivered (not on day 1). Its displayed text gains one detail the technician never wrote; 'Sent letters' shows the real reply.",
		"variants": ["normal"]},
	&"window_figure": {"name": "Figure behind the tunnel port (Chapter One climax)", "phase": 2, "late": false, "chance": 0.0, "cooldown_days": 999, "max_plays": 1, "enabled": true, "implemented": true,
		"needs": "READY after one anomaly seen (or 2 quiet phase-2 days), not day 1. Shown ONLY when visible from the Control Room port; reacts to a direct gaze; guided once a day if ignored. See window_encounter.gd.",
		"variants": ["normal"]},
	&"blind_spot_object": {"name": "Object in a camera blind spot", "phase": 2, "late": true, "chance": 0.4, "cooldown_days": 4, "max_plays": 2, "enabled": false, "implemented": false,
		"needs": "NOT IMPLEMENTED (future round).", "variants": []},
	&"radio_contact": {"name": "Unknown radio contact", "phase": 3, "late": false, "chance": 1.0, "cooldown_days": 99, "max_plays": 1, "enabled": false, "implemented": false,
		"needs": "NOT IMPLEMENTED (future round).", "variants": []},
	&"laptop_inconsistency": {"name": "Personal laptop anomaly", "phase": 3, "late": false, "chance": 0.4, "cooldown_days": 6, "max_plays": 1, "enabled": false, "implemented": false,
		"needs": "NOT IMPLEMENTED (future round).", "variants": []},
}
const MILESTONES := ["intro_complete", "station_familiar", "handover_read", "late_phase_2", "reality_doubt"]
const FAMILIAR_DUTIES := 3
const PRESENCE_WATCH_S := 6.0      # continuous INT-02 viewing before it can appear
const PRESENCE_MAX_S := 9.0
const PRESENCE_SEEN_S := 1.2       # on screen this long while watched = seen
const WINDOW_GAZE_S := 2.5
const WINDOW_EVENT_S := 40.0
const READING_GAZE_S := 1.5
const READING_MAX_S := 30.0
const READING_AWAY_S := 4.0
const HATCH_MAX_S := 75.0
const HATCH_SEEN_S := 1.5
## Round 42: INT-02 now looks from the Life Support bend down the Junction
## and the corridor to the Control Room. The presence stands on that
## approach, BEHIND the seated technician: first far down the Junction,
## then in the corridor, then just inside the Control Room doorway; the
## abnormal (phase 3) variant stands right behind the stool.
const PRESENCE_SPOTS := [Vector3(-0.2, 0.0, 4.9), Vector3(-0.22, 0.0, 2.9), Vector3(0.3, 0.0, 1.45)]
const PRESENCE_CLOSE := Vector3(0.18, 0.0, 0.25)
## The wrong reading: true values stay in the model; only the wall panel lies.
const READING_OVERRIDE := {
	"normal": {"CABIN PRESSURE": "CABIN PRESSURE  96.8 kPa  LOW"},
	"abnormal": {"CABIN PRESSURE": "CABIN PRESSURE  0.0 kPa  LOW", "O2 PARTIAL": "O2 PARTIAL      0.0 kPa  LOW"},
}

@export var day_plan_path: NodePath = ^"../DayPlan"
var _dp: Node
## id -> {plays, last_day, armed_day, seen}
var state: Dictionary = {}
var feed_days: Dictionary = {}     # camera id -> [days it was watched]
var armed_for_day: int = -1        # the day the arming roll was made for
var active: StringName = &""
var active_variant: String = ""
var active_dev: bool = false       # started from the developer layer (not counted)
var history: Array = []            # [{id, day, event}] (session log, tests)
## Narrative state (saved).
var story_phase: int = 1
var milestones: Array = []         # completed milestone ids, in order
var duty_kinds: Array = []         # distinct duty kinds closed (familiarity)
var investigations: Array = []     # event ids the technician physically checked
## Developer layer (never saved).
var dev_phase_override: int = 0    # 0 = none
var dev_enabled: Dictionary = {}   # id -> bool runtime override
var _dev_snapshot: Dictionary = {}
var _watch_id: String = ""
var _watch_s: float = 0.0
var _last_feed_ms: int = 0
var _active_t: float = 0.0
var _on_screen_s: float = 0.0
var _gaze_s: float = 0.0
var _away_s: float = 0.0
var _presence: Node3D
var _poll: float = 0.0
var _hatch_clones: Array = []
var _hatch_saved_layers: Array = []
var _hatch_sound: AudioStreamPlayer3D
var _hatch_seen_since: float = -1.0
var _pending_investigation: Dictionary = {}   # id -> seconds left to go and check
## Round 43 Priority 21: the INVESTIGATION framework. Evidence the
## technician gathered (observations of an anomaly, physical checks, station
## records that contradict what was seen), linked by event id. Optional:
## nothing points at it, nothing requires it; it only feeds the story
## milestones (a record contradiction counts as an investigation).
var evidence: Array = []           # [{event, day, kind: observation|check|contradiction, text, ref}]
## record id -> the events it can contradict (what the record shows).
const RECORD_LINKS := {
	"note_archive": {"events": ["note_extra_item"], "text": "The note archive shows one revision, no edits -- the extra line was never issued."},
	"environment_log": {"events": ["wrong_reading"], "text": "The environment log shows normal cabin pressure all day."},
	"airlock_log": {"events": ["phantom_cycle"], "text": "The airlock activity log records no cycle at that time."},
	"access_log": {"events": ["access_ghost", "window_figure"], "text": "The access log records no one in the airlock tunnel but the technician."},
	"camera_log": {"events": ["window_figure"], "text": "The cameras logged nothing unusual in the airlock section."},
	"sent_mail": {"events": ["family_misremember"], "text": "The sent letter does not contain the detail the answer quotes."},
}
const NOTE_LINES := {"normal": "Check the corridor feed before bed.", "abnormal": "Leave the corridor feed on tonight. It helps."}
var _note_overlay: Dictionary = {}
var _note_shown: bool = false
## Round 44: presentation overlays for station records / letters.
var _record_overlay: Dictionary = {}      # kind -> [{day, t, text}]
var _family_overlay: Dictionary = {}      # conv -> extra text
var _access_room: String = ""
var _closed_today: int = 0
var journal: Node
var inner: Node
var family: Node
var window: Node
const ACCESS_ROOMS := {&"storage": "STORAGE", &"engineering": "ENGINEERING", &"life_support": "LIFE SUPPORT", &"communications": "COMMS"}
const FAMILY_EXTRA := "And you said the corridor light keeps you awake. Try an eye mask?"
const THOUGHTS := {
	"note_archive": ["I didn't write that. Did I?", "那不是我写的。是吗？"],
	"airlock_log": ["No cycle logged. I heard it.", "没有循环记录。可我听见了。"],
	"access_log": ["That's strange. I haven't been in %s today.", "奇怪。我今天没去过%s。"],
	"sent_mail": ["That's not what I wrote.", "我不是这么写的。"],
	"environment_log": ["Those readings shouldn't be different.", "这些读数不该不一样。"],
	"camera_log": ["Nothing on the cameras. Nothing at all.", "摄像头什么也没拍到。什么都没有。"],
	"window_record": ["Nobody was logged in the tunnel. Nobody but me.", "隧道里没有任何记录。只有我。"],
	"heard_phantom": ["Was that the airlock?", "是气闸的声音吗？"],
	"note_seen": ["Was that always on the list?", "清单上一直有这一项吗？"],
	"mail_seen": ["When did I tell her that?", "我什么时候跟她说过这个？"],
}


func _ready() -> void:
	add_to_group(&"story_events")
	add_to_group(&"r35_equipment")      # SaveGame persists state_dict()/load_dict()
	_dp = get_node_or_null(day_plan_path)
	for id in EVENTS:
		state[id] = _blank()
	_presence = _build_presence()
	journal = load("res://scripts/story/journal.gd").new()
	journal.name = "Journal"
	add_child(journal)
	inner = load("res://scripts/story/inner_voice.gd").new()
	inner.name = "InnerVoice"
	add_child(inner)
	family = load("res://scripts/story/family_mail.gd").new()
	family.name = "FamilyMail"
	add_child(family)
	window = load("res://scripts/story/window_encounter.gd").new()
	window.name = "WindowEncounter"
	add_child(window)
	if _dp != null:
		if _dp.has_signal(&"order_closed"):
			_dp.order_closed.connect(func(t): note_duty(String(t)); _closed_today += 1; journal.on_order_closed(String(t)))
		if _dp.has_signal(&"task_completed"):
			_dp.task_completed.connect(func(t): if t != &"c01": note_duty(String(t)))
		if _dp.has_signal(&"day_started"):
			_dp.day_started.connect(_on_day_started)
	# Round 42: the developer panel exists ONLY in debug / development
	# builds (never in an exported release build).
	if OS.is_debug_build():
		var panel: CanvasLayer = load("res://scripts/dev/dev_panel.gd").new()
		panel.name = "DevPanel"
		panel.setup(get_parent(), self)
		get_parent().add_child.call_deferred(panel)


static func _blank() -> Dictionary:
	return {"plays": 0, "last_day": -99, "armed_day": -1, "seen": false}


func day() -> int:
	return int(_dp.day_number) if _dp != null else 1


## The CURRENT narrative phase (a developer override wins, transiently).
func phase() -> int:
	return dev_phase_override if dev_phase_override > 0 else story_phase


func late_phase_2() -> bool:
	return phase() >= 3 or (phase() == 2 and (dev_phase_override > 0 or milestones.has("late_phase_2")))


func current_milestone() -> String:
	return String(milestones.back()) if not milestones.is_empty() else "(none)"


func _root() -> Node:
	return get_parent()


# ---------------------------------------------------------- milestones
func has_milestone(m: String) -> bool:
	return milestones.has(m)


func _add_milestone(m: String) -> void:
	if milestones.has(m):
		return
	milestones.append(m)
	history.append({"id": "milestone", "day": day(), "event": m})


## Ordinary work feeds FAMILIARITY only -- never the horror phase by itself.
func note_duty(kind: String) -> void:
	if kind != "" and not duty_kinds.has(kind):
		duty_kinds.append(kind)
	_check_milestones()


## Deliberate narrative discoveries (the laptop handover note, ...).
func on_story_discovery(id: String) -> void:
	if id == "handover_read" and has_milestone("station_familiar"):
		_add_milestone("handover_read")
	elif id == "handover_read":
		# Read early: remembered, counts once the station is familiar.
		if not investigations.has("_handover_early"):
			investigations.append("_handover_early")
	_check_milestones()


func familiar_progress() -> Dictionary:
	var days: Dictionary = {}
	for k in feed_days:
		for d in feed_days[k]:
			days[int(d)] = true
	return {"duties": duty_kinds.size(), "feed_days": days.size()}


func _check_milestones() -> void:
	if day() >= 2:
		_add_milestone("intro_complete")
	var fp: Dictionary = familiar_progress()
	if has_milestone("intro_complete") and int(fp["duties"]) >= FAMILIAR_DUTIES and int(fp["feed_days"]) >= 2:
		if not has_milestone("station_familiar"):
			_add_milestone("station_familiar")
			# The assistant (helpful, phase 1) points at the waiting note --
			# an ordinary admin reminder, never a horror explanation.
			if is_inside_tree():
				get_tree().call_group(&"assistant_hooks", &"handover_note_waiting")
	if has_milestone("station_familiar") and investigations.has("_handover_early"):
		_add_milestone("handover_read")
	if story_phase == 1 and has_milestone("intro_complete") and has_milestone("station_familiar") and has_milestone("handover_read"):
		story_phase = 2
		history.append({"id": "phase", "day": day(), "event": "phase_2"})
		if journal != null:
			journal.on_milestone("phase_2")
	if story_phase >= 2 and seen_count() >= 2:
		_add_milestone("late_phase_2")
	var inv: int = investigations.filter(func(x): return not String(x).begins_with("_")).size()
	if story_phase == 2 and seen_count() >= 3 and inv >= 2:
		_add_milestone("reality_doubt")
		story_phase = 3
		history.append({"id": "phase", "day": day(), "event": "phase_3"})
		if journal != null:
			journal.on_milestone("phase_3")


func seen_count() -> int:
	var n := 0
	for id in state:
		if bool(state[id]["seen"]):
			n += 1
	return n


func _investigated(id: String) -> void:
	if not investigations.has(id):
		investigations.append(id)
	history.append({"id": id, "day": day(), "event": "investigated"})
	_add_evidence(id, "check", "Checked in person: nothing out of place.", "")
	if journal != null:
		journal.on_checked(id)
	_check_milestones()


# ------------------------------------------------------- investigation
func _add_evidence(event_id: String, kind: String, text: String, ref: String) -> void:
	for e in evidence:
		if e["event"] == event_id and e["kind"] == kind and e["ref"] == ref and int(e["day"]) == day():
			return
	evidence.append({"event": event_id, "day": day(), "kind": kind, "text": text, "ref": ref})


## An anomaly was noticed (seen) -- an open question.
func observe(event_id: String, text: String) -> void:
	_add_evidence(event_id, "observation", text, "")
	if journal != null:
		journal.on_observed(event_id)


## "none" | "observed" | "checked" | "contradicted"
func investigation_state(event_id: String) -> String:
	var st := "none"
	for e in evidence:
		if e["event"] != event_id:
			continue
		match String(e["kind"]):
			"contradiction": return "contradicted"
			"check": st = "checked"
			"observation":
				if st == "none":
					st = "observed"
	return st


## A station / personal RECORD was consulted. If it covers an anomaly the
## technician has observed, the record contradicts the experience: that is
## evidence, and counts as an investigation.
func on_record_checked(record_id: String) -> void:
	var link: Dictionary = RECORD_LINKS.get(record_id, {})
	for ev in Array(link.get("events", [])):
		if investigation_state(String(ev)) in ["observed", "checked"] or (active == StringName(ev) and not active_dev):
			var first: bool = investigation_state(String(ev)) != "contradicted"
			_add_evidence(String(ev), "contradiction", String(link["text"]), record_id)
			if not investigations.has(String(ev)):
				investigations.append(String(ev))
				history.append({"id": String(ev), "day": day(), "event": "investigated"})
			if first:
				if journal != null:
					journal.on_contradiction(String(ev), record_id)
				_thought("window_record" if String(ev) == "window_figure" else record_id)
			_check_milestones()


func evidence_for(event_id: String) -> Array:
	return evidence.filter(func(e): return e["event"] == event_id)


# ---------------------------------------------------- laptop presentation
## Round 43 Priority 22: PRESENTATION-ONLY overlays for laptop documents.
## The laptop asks at display time; nothing here ever writes the player's
## own data or the documents themselves.
func laptop_overlays(doc_id: String) -> Array:
	if doc_id == "daily_note" and not _note_overlay.is_empty():
		return [_note_overlay]
	return []


## The laptop opened a document. TODAY'S NOTE: an armed note anomaly starts
## on this opening; the NEXT opening finds the note normal again.
func on_document_opened(doc_id: String) -> void:
	if doc_id != "daily_note":
		return
	if active == &"note_extra_item":
		if _note_shown:
			stop(true)          # opened again: the line is simply not there
		else:
			_note_shown = true  # (a developer-started preview: show it now)
		return
	if active == &"" and is_armed(&"note_extra_item") and not _emergency():
		var variant: String = "abnormal" if phase() >= 3 else "normal"
		if _start(&"note_extra_item", variant):
			_note_shown = true
			_thought("note_seen")


# ------------------------------------------------------------- arming
func is_enabled(id: StringName) -> bool:
	if not EVENTS.has(id) or not bool(EVENTS[id]["implemented"]):
		return false
	return bool(dev_enabled.get(id, EVENTS[id]["enabled"]))


## Why an event cannot arm today ("" = it can) -- shown in the dev panel.
func eligibility(id: StringName) -> String:
	if not EVENTS.has(id):
		return "unknown event"
	var e: Dictionary = EVENTS[id]
	if not bool(e["implemented"]):
		return "not implemented"
	if not is_enabled(id):
		return "disabled"
	if phase() < int(e["phase"]):
		return "needs phase %d (now %d)" % [int(e["phase"]), phase()]
	if bool(e["late"]) and not late_phase_2():
		return "needs late phase 2 (2 different anomalies seen)"
	var st: Dictionary = state[id]
	if int(st["plays"]) >= int(e["max_plays"]):
		return "played %d/%d" % [int(st["plays"]), int(e["max_plays"])]
	if day() - int(st["last_day"]) < int(e["cooldown_days"]):
		return "cooldown until day %d" % (int(st["last_day"]) + int(e["cooldown_days"]))
	return ""


## Deterministic daily arming: at most one event, never below its phase,
## respecting cooldown / max plays. Same day + same history -> same result.
func _arm_today() -> void:
	var d: int = day()
	if armed_for_day == d:
		return
	armed_for_day = d
	if phase() < 2:
		return
	for id in EVENTS:
		if eligibility(id) != "":
			continue
		var roll: int = absi(hash([d, String(id), "story"])) % 100
		if roll < int(float(EVENTS[id]["chance"]) * 100.0):
			state[id]["armed_day"] = d
			return


func is_armed(id: StringName) -> bool:
	return state.has(id) and int(state[id]["armed_day"]) == day() and int(state[id]["last_day"]) != day()


func armed_id() -> StringName:
	for id in state:
		if is_armed(id):
			return id
	return &""


## Debug builds: arm an event for today regardless of the roll / phase --
## every live condition still applies ("trigger when available").
func debug_arm(id: StringName) -> bool:
	if not OS.is_debug_build() or not state.has(id) or not bool(EVENTS[id]["implemented"]):
		return false
	armed_for_day = day()
	for k in state:
		if int(state[k]["armed_day"]) == day():
			state[k]["armed_day"] = -1
	state[id]["armed_day"] = day()
	if int(state[id]["last_day"]) == day():
		state[id]["last_day"] = -99
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
		_check_milestones()


func watched_before_today(id: String) -> bool:
	return Array(feed_days.get(id, [])).any(func(x): return int(x) < day())


func _shell() -> Node:
	return _root().get_node_or_null("Interactables/WorkstationConsole/WorkstationScreen/Shell") if _root() != null else null


func _ws_in_use() -> bool:
	var ws: Node = _root().get_node_or_null("WorkstationState")
	return ws != null and ws.has_method("is_in_use") and ws.is_in_use()


func _feed_on_screen(cam_id: String) -> bool:
	var sh: Node = _shell()
	return sh != null and int(sh.page) == 1 and String(sh.selected_cam) == cam_id and Time.get_ticks_msec() - _last_feed_ms < 600


func _watching(cam_id: String) -> bool:
	return _ws_in_use() and _feed_on_screen(cam_id)


func _player_cam() -> Camera3D:
	return _root().get_node_or_null("Player/LookPivot/PitchPivot/Camera3D") as Camera3D


func _emergency() -> bool:
	var st: Node = _root().get_node_or_null("StationStatus")
	return st != null and not st.emergency().is_empty()


func _eva_busy() -> bool:
	var e: Node = get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null
	return e != null and e.has_method("is_eva_active") and e.is_eva_active()


func _looking_at(target: Vector3, max_d: float, min_dot: float) -> bool:
	var cam: Camera3D = _player_cam()
	if cam == null:
		return false
	var to: Vector3 = target - cam.global_position
	return to.length() < max_d and (-cam.global_basis.z).dot(to.normalized()) > min_dot


func _readout() -> Node:
	return _root().get_node_or_null("EnvironmentReadout")


func _airlock() -> Node:
	return get_tree().get_first_node_in_group(&"airlock") if is_inside_tree() else null


func _near_airlock() -> bool:
	var cam: Camera3D = _player_cam()
	return cam != null and cam.global_position.x < -3.6 and cam.global_position.z < 0.6 and cam.global_position.z > -3.2


func _far_from_airlock(m: float) -> bool:
	var cam: Camera3D = _player_cam()
	return cam != null and cam.global_position.distance_to(Vector3(-4.8, 1.6, -1.5)) >= m and cam.global_position.y < 3.0


## A module the technician has not entered today (from the access log's
## own first-entry record), or "" if none. dev: any (Storage first).
func _unvisited_room(dev: bool) -> String:
	var lg: Node = get_tree().get_first_node_in_group(&"station_log")
	for r in ACCESS_ROOMS:
		if dev or lg == null or not lg.visited_today(r):
			return ACCESS_ROOMS[r]
	return ""


## A family thread whose answer has been delivered.
func _family_target() -> String:
	if family == null:
		return ""
	for c in family.ORDER:
		if family.answer_delivered(c):
			return c
	return ""


func _thought(id: String) -> void:
	if inner == null or not THOUGHTS.has(id):
		return
	var en: String = THOUGHTS[id][0]
	var zh: String = THOUGHTS[id][1]
	if id == "access_log":
		var room: String = _access_room if _access_room != "" else "STORAGE"
		en = en % room.capitalize()
		zh = zh % room
	inner.think(id, en, zh)


# ------------------------------------------------- records + letters
## Presentation overlay lines for a station record kind (station_log.gd).
func record_overlays(kind: String) -> Array:
	return Array(_record_overlay.get(kind, []))


func family_overlay(conv: String) -> String:
	return String(_family_overlay.get(conv, ""))


## A record view was opened (workstation RECORDS tabs / laptop).
## Reading a record that carries an active anomaly = noticing it.
func on_record_viewed(record_id: String) -> void:
	if record_id == "access_log" and active == &"access_ghost":
		if not active_dev:
			var st: Dictionary = state[&"access_ghost"]
			st["seen"] = true
			observe("access_ghost", EVENTS[&"access_ghost"]["name"])
		var lg: Node = get_tree().get_first_node_in_group(&"station_log")
		var room_key: StringName = &""
		for r in ACCESS_ROOMS:
			if ACCESS_ROOMS[r] == _access_room:
				room_key = r
		if lg == null or not lg.visited_today(room_key):
			on_record_checked("access_log")
	else:
		on_record_checked(record_id)


## A letter thread was opened on the laptop.
func on_letter_opened(conv: String) -> void:
	if active == &"family_misremember" and _family_overlay.has(conv):
		if not active_dev:
			state[&"family_misremember"]["seen"] = true
			observe("family_misremember", EVENTS[&"family_misremember"]["name"])
		_thought("mail_seen")


# ------------------------------------------------------- day + chapter
func _on_day_started(d: int) -> void:
	if journal != null and d > 1:
		journal.on_shift_summary(d - 1, _closed_today)
	_closed_today = 0
	# Presentation anomalies tied to a day end with it.
	if active in [&"access_ghost", &"family_misremember"]:
		stop(bool(state[active]["seen"]))
	_check_milestones()
	_check_chapter()


## Round 44 Priority 17: CHAPTER ONE ends (a demo stopping point, never a
## lock) once phase 2 has begun and EITHER one contradiction was found
## through a record, OR (the player missed every clue) four more days
## have passed in phase 2. Several routes: note archive, airlock log,
## access log, sent letters, environment log.
var phase2_day: int = -1
signal chapter_complete(chapter: int)


func chapter_one_complete() -> bool:
	return milestones.has("chapter_1")


func _check_chapter() -> void:
	if chapter_one_complete() or story_phase < 2:
		return
	if phase2_day < 0:
		phase2_day = day()
	# Round 45: the chapter's climax is the WINDOW ENCOUNTER. It ends once the
	# figure was witnessed and followed up (a physical check or a record
	# that contradicts it) -- or simply the morning after. A long quiet
	# fallback (8 phase-2 days) guarantees the chapter can always end.
	var wd: int = int(window.witnessed_day) if window != null else -1
	var followed: bool = investigation_state("window_figure") in ["checked", "contradicted"]
	if (wd >= 0 and (followed or day() > wd)) or day() >= phase2_day + 8:
		_add_milestone("chapter_1")
		if journal != null:
			journal.on_milestone("chapter_1")
		chapter_complete.emit(1)
		_show_chapter_card()


func _show_chapter_card() -> void:
	if not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 9
	layer.name = "ChapterCard"
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	var l := Label.new()
	l.text = "END OF CHAPTER ONE\n\nThe station keeps its own records.\nSo do you.\n\n(the station runs on — keep playing)"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	layer.add_child(l)
	get_parent().add_child(layer)
	var tw := layer.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(bg, "color:a", 0.0, 1.5)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(layer.queue_free)


# ------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if _dp == null:
		return
	if _watch_id != "" and Time.get_ticks_msec() - _last_feed_ms < 600:
		_watch_s += delta
	for k in _pending_investigation.keys():
		_pending_investigation[k] = float(_pending_investigation[k]) - delta
		if (k == "hatch_handle" or k == "phantom_cycle") and _near_airlock():
			_pending_investigation.erase(k)
			_investigated(k)
		elif float(_pending_investigation.get(k, 0.0)) <= 0.0:
			_pending_investigation.erase(k)
	if active != &"":
		_update_active(delta)
		return
	_poll += delta
	if _poll < 0.25:
		return
	var dt: float = _poll
	_poll = 0.0
	_arm_today()
	var armed: StringName = armed_id()
	if armed == &"" or _emergency():
		_gaze_s = 0.0
		return
	var variant: String = "abnormal" if phase() >= 3 and EVENTS[armed]["variants"].has("abnormal") else "normal"
	match armed:
		&"corridor_presence":
			if _presence_ready():
				_start(armed, variant)
		&"window_mismatch":
			if _gazing_at_window():
				_gaze_s += dt
				if _gaze_s >= WINDOW_GAZE_S and watched_before_today("EXT-03"):
					_start(armed, variant)
			else:
				_gaze_s = 0.0
		&"wrong_reading":
			var r: Node3D = _readout() as Node3D
			if r != null and _looking_at(r.global_position, 3.0, 0.75):
				_gaze_s += dt
				if _gaze_s >= READING_GAZE_S:
					_start(armed, variant)
			else:
				_gaze_s = 0.0
		&"hatch_handle":
			if not _eva_busy() and not _near_airlock() and float(_dp.shift_elapsed_s) > 60.0:
				_start(armed, variant)
		&"phantom_cycle":
			if not _eva_busy() and _far_from_airlock(8.0) and float(_dp.shift_elapsed_s) > 90.0 and day() > 1:
				_start(armed, variant)
		&"access_ghost":
			if float(_dp.shift_elapsed_s) > 120.0 and _unvisited_room(false) != "" and day() > 1:
				_start(armed, variant)
		&"family_misremember":
			if day() > 1 and _family_target() != "":
				_start(armed, variant)


func _presence_ready() -> bool:
	return _watching("INT-02") and _watch_s >= PRESENCE_WATCH_S and watched_before_today("INT-02") \
		and float(_dp.shift_elapsed_s) > 90.0


func _gazing_at_window() -> bool:
	var win: Node3D = _root().get_node_or_null("Interactables/WallWatchWindow") as Node3D
	if win == null or _ws_in_use():
		return false
	return _looking_at(win.global_position, 2.6, 0.8)


func _start(id: StringName, variant: String = "normal", dev: bool = false) -> bool:
	if active != &"":
		return false
	active = id
	active_variant = variant
	active_dev = dev
	_active_t = 0.0
	_on_screen_s = 0.0
	_away_s = 0.0
	_hatch_seen_since = -1.0
	history.append({"id": String(id), "day": day(), "event": "start", "variant": variant, "dev": dev})
	match id:
		&"corridor_presence":
			var spot: Vector3 = PRESENCE_CLOSE if variant == "abnormal" else PRESENCE_SPOTS[mini(int(state[id]["plays"]), PRESENCE_SPOTS.size() - 1)]
			_presence.position = spot
			_presence.visible = true
		&"window_mismatch":
			var od: Node = get_tree().get_first_node_in_group(&"observation_discrepancy")
			if od == null or not od.trigger("displaced", WINDOW_EVENT_S, "event"):
				_abort_start()
				return false
		&"wrong_reading":
			var r: Node = _readout()
			if r == null or not r.has_method("set_display_override"):
				_abort_start()
				return false
			r.set_display_override(READING_OVERRIDE.get(variant, READING_OVERRIDE["normal"]), "story:wrong_reading")
		&"hatch_handle":
			if not _hatch_begin():
				_abort_start()
				return false
		&"note_extra_item":
			_note_overlay = {"kind": "extra_item", "text": NOTE_LINES.get(variant, NOTE_LINES["normal"]), "event": "note_extra_item"}
			_note_shown = false
		&"phantom_cycle":
			var snd: Node = get_tree().get_first_node_in_group(&"station_sounds")
			if snd == null:
				_abort_start()
				return false
			snd.phantom_cycle()
		&"access_ghost":
			var room: String = _unvisited_room(dev)
			if room == "":
				_abort_start()
				return false
			_access_room = room
			var m: int = maxi((_dp.clock_minutes() if _dp != null else 600) - 25 - absi(hash([day(), "ghost"])) % 30, 8 * 60)
			_record_overlay["access"] = [{"day": day(), "t": "%02d:%02d" % [m / 60, m % 60], "text": "%s · entered · TECH-1" % room}]
		&"family_misremember":
			var conv: String = _family_target()
			if conv == "":
				_abort_start()
				return false
			_family_overlay = {conv: FAMILY_EXTRA}
		&"window_figure":
			# Developer start only (normal play runs window_encounter.gd).
			window.dev_spawn()
	return true


func _abort_start() -> void:
	history.append({"id": String(active), "day": day(), "event": "start_failed"})
	active = &""
	active_variant = ""
	active_dev = false


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
			if turned and _on_screen_s >= PRESENCE_SEEN_S and not active_dev:
				_investigated("corridor_presence")
			var limit: float = PRESENCE_MAX_S if not active_dev else 30.0
			if (not watching and not active_dev) or turned or (not _ws_in_use() and not active_dev) or _active_t >= limit:
				stop(_on_screen_s >= PRESENCE_SEEN_S)
		&"window_mismatch":
			var od: Node = get_tree().get_first_node_in_group(&"observation_discrepancy")
			if od == null or not od.is_active():
				stop(true)
		&"wrong_reading":
			var r: Node3D = _readout() as Node3D
			var looking: bool = r != null and _looking_at(r.global_position, 3.2, 0.7)
			if looking:
				_on_screen_s += delta
				_away_s = 0.0
			else:
				_away_s += delta
			# Comparing with the workstation while it lies = investigating.
			if _ws_in_use() and _on_screen_s >= READING_GAZE_S and not active_dev:
				_investigated("wrong_reading")
			if _active_t >= READING_MAX_S or (_away_s >= READING_AWAY_S and _on_screen_s > 0.5):
				stop(_on_screen_s >= READING_GAZE_S)
		&"note_extra_item":
			if _active_t >= 900.0:
				stop(true)
		&"phantom_cycle":
			var snd2: Node = get_tree().get_first_node_in_group(&"station_sounds")
			if snd2 == null or (not snd2.phantom_active() and _active_t > 5.0):
				# Heard (the whole station hears the airlock). Going there
				# within a few minutes counts as checking it.
				_thought("heard_phantom")
				stop(true)
		&"access_ghost", &"family_misremember":
			pass        # presentation lasts the day; seen when the record / letter is read
		&"window_figure":
			if window.stage in ["done", "locked"] or _active_t > 60.0:
				stop(window.stage == "done")
		&"hatch_handle":
			_hatch_animate()
			if _feed_on_screen("EXT-02") or _feed_on_screen("INT-07"):
				_on_screen_s += delta
			if _near_airlock():
				# Close inspection: the handle is simply normal.
				var seen: bool = _on_screen_s >= HATCH_SEEN_S
				if seen and not active_dev:
					_investigated("hatch_handle")
				stop(seen)
			elif _active_t >= HATCH_MAX_S or _eva_busy():
				stop(_on_screen_s >= HATCH_SEEN_S)


## Safe stop: hides everything the event showed; records the play (unless
## it was a developer preview).
func stop(seen: bool = false) -> void:
	if active == &"":
		return
	var id: StringName = active
	var dev: bool = active_dev
	active = &""
	active_variant = ""
	active_dev = false
	_presence.visible = false
	match id:
		&"window_mismatch":
			var od: Node = get_tree().get_first_node_in_group(&"observation_discrepancy")
			if od != null and od.is_active():
				od.clear()
		&"wrong_reading":
			var r: Node = _readout()
			if r != null and r.has_method("clear_display_override"):
				r.clear_display_override()
		&"hatch_handle":
			_hatch_end()
			if seen and not dev:
				_pending_investigation["hatch_handle"] = 120.0
		&"note_extra_item":
			_note_overlay = {}
		&"phantom_cycle":
			var snd3: Node = get_tree().get_first_node_in_group(&"station_sounds")
			if snd3 != null:
				snd3.stop_phantom()
			if seen and not dev:
				_pending_investigation["phantom_cycle"] = 240.0
		&"access_ghost":
			_record_overlay.erase("access")
		&"family_misremember":
			_family_overlay = {}
		&"window_figure":
			if window.stage != "done":
				window.dev_reset()
	if seen and not dev and id != &"window_figure":
		observe(String(id), EVENTS[id]["name"])
	if not dev:
		var st: Dictionary = state[id]
		st["plays"] = int(st["plays"]) + 1
		st["last_day"] = day()
		st["seen"] = bool(st["seen"]) or seen
	_watch_s = 0.0
	_gaze_s = 0.0
	history.append({"id": String(id), "day": day(), "event": "stop", "seen": seen, "dev": dev})
	if not dev:
		_check_milestones()


func presence_visible() -> bool:
	return _presence != null and _presence.visible


func presence_node() -> Node3D:
	return _presence


# ------------------------------------------------------- hatch handle
## The OUTER hatch's handle assemblies stay exactly where they are for the
## eyes (moved to DIRECT_ONLY); CAMERA_ONLY copies take their place on the
## surveillance feeds and turn. The real airlock state is never touched.
func _hatch_begin() -> bool:
	var a: Node = _airlock()
	if a == null or not a.has_method("outer_handles") or a.outer_open or a.sequence != "":
		return false
	_hatch_clones = []
	_hatch_saved_layers = []
	for h in a.outer_handles():
		var hn: Node3D = h
		var layers: Array = []
		for v in hn.find_children("*", "VisualInstance3D", true, false):
			layers.append((v as VisualInstance3D).layers)
			(v as VisualInstance3D).layers = DIRECT_ONLY
		_hatch_saved_layers.append(layers)
		var c: Node3D = hn.duplicate()
		c.name = String(hn.name) + "_CamOnly"
		hn.get_parent().add_child(c)
		c.transform = hn.transform
		var j := 0
		for v in c.find_children("*", "VisualInstance3D", true, false):
			# Keep the sunlit EXTERIOR bit (outer face) so the copy is lit
			# exactly like the real handle on EXT-02.
			(v as VisualInstance3D).layers = CAMERA_ONLY | (int(layers[mini(j, layers.size() - 1)]) & (1 << 11))
			j += 1
			(v as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hatch_clones.append(c)
	# A dull mechanical knock at the hatch (heard faintly from the station).
	if _hatch_sound == null:
		_hatch_sound = AudioStreamPlayer3D.new()
		_hatch_sound.name = "HatchKnock"
		_hatch_sound.bus = "SFX"
		_hatch_sound.unit_size = 6.0
		_hatch_sound.max_distance = 18.0
		_hatch_sound.stream = _knock_stream()
		add_child(_hatch_sound)
	_hatch_sound.global_position = Vector3(-4.8, 1.0, -2.4)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		_hatch_sound.play()
	return true


## Turn profile: still -> a slow quarter-twist -> held -> eases back, with
## a tiny tremor; the abnormal variant turns further and twice.
func hatch_twist_deg() -> float:
	if active != &"hatch_handle":
		return 0.0
	var t: float = fmod(_active_t, 14.0)
	var amp: float = 110.0 if active_variant == "abnormal" else 55.0
	var k: float = 0.0
	if t < 2.0:
		k = 0.0
	elif t < 5.0:
		k = smoothstep(2.0, 5.0, t)
	elif t < 8.0:
		k = 1.0
	elif t < 10.5:
		k = 1.0 - smoothstep(8.0, 10.5, t)
	return amp * k + (sin(_active_t * 23.0) * 0.8 if k > 0.05 else 0.0)


func _hatch_animate() -> void:
	var deg: float = hatch_twist_deg()
	for c in _hatch_clones:
		if is_instance_valid(c):
			(c as Node3D).rotation_degrees.z = deg


func _hatch_end() -> void:
	for c in _hatch_clones:
		if is_instance_valid(c):
			(c as Node).queue_free()
			(c as Node3D).visible = false
	_hatch_clones = []
	var a: Node = _airlock()
	if a != null and a.has_method("outer_handles"):
		var hs: Array = a.outer_handles()
		for i in mini(hs.size(), _hatch_saved_layers.size()):
			var vs: Array = (hs[i] as Node3D).find_children("*", "VisualInstance3D", true, false)
			for j in mini(vs.size(), (_hatch_saved_layers[i] as Array).size()):
				(vs[j] as VisualInstance3D).layers = int(_hatch_saved_layers[i][j])
	_hatch_saved_layers = []


func hatch_clone_count() -> int:
	return _hatch_clones.filter(func(c): return is_instance_valid(c)).size()


static func _knock_stream() -> AudioStreamWAV:
	var rate := 22050
	var n: int = int(rate * 1.1)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / rate
		var v: float = 0.0
		for hit in [0.0, 0.42]:
			var u: float = t - hit
			if u >= 0.0:
				v += sin(u * TAU * 70.0) * exp(-u * 18.0) * 0.8 + (randf() - 0.5) * exp(-u * 60.0) * 0.4
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


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


# ---------------------------------------------------- developer layer
## All of these refuse in release builds (the panel itself is never built
## there either -- scripts/dev/dev_panel.gd).
func dev_allowed() -> bool:
	return OS.is_debug_build()


## Snapshot the story state the first time a developer touches it, so the
## test session can be rolled back ("restore pre-test state").
func _dev_touch() -> void:
	if _dev_snapshot.is_empty():
		_dev_snapshot = state_dict()


## Start NOW, bypassing the narrative gate and live conditions. `count`:
## record it as a real play (seen / plays); default is a PREVIEW that
## leaves progression untouched.
func dev_trigger(id: StringName, variant: String = "normal", count: bool = false) -> bool:
	if not dev_allowed() or not EVENTS.has(id) or not bool(EVENTS[id]["implemented"]):
		return false
	_dev_touch()
	if active != &"":
		dev_cancel()
	var ok: bool = _start(id, variant, not count)
	if ok and id == &"corridor_presence" and not count:
		_on_screen_s = PRESENCE_SEEN_S
	return ok


func dev_cancel() -> void:
	if active == &"":
		return
	var was_dev: bool = active_dev
	active_dev = true          # never counted
	stop(false)
	if not was_dev:
		history.append({"id": "dev", "day": day(), "event": "cancelled_real_event"})


func dev_reset(id: StringName) -> void:
	if not dev_allowed() or not state.has(id):
		return
	_dev_touch()
	if active == id:
		dev_cancel()
	state[id] = _blank()


func dev_set_seen(id: StringName, seen: bool) -> void:
	if not dev_allowed() or not state.has(id):
		return
	_dev_touch()
	state[id]["seen"] = seen


func dev_set_enabled(id: StringName, on: bool) -> void:
	if not dev_allowed() or not EVENTS.has(id):
		return
	dev_enabled[id] = on


func dev_set_phase_override(p: int) -> void:
	if not dev_allowed():
		return
	dev_phase_override = clampi(p, 0, 3)
	armed_for_day = -1          # re-roll today under the forced phase (transient)


## Back to normal simulation: no override, nothing active, every runtime
## enable reverted, the story state as it was before the first dev action.
func dev_restore() -> void:
	if active != &"":
		dev_cancel()
	dev_phase_override = 0
	dev_enabled = {}
	if not _dev_snapshot.is_empty():
		var snap: Dictionary = _dev_snapshot
		_dev_snapshot = {}
		load_dict(snap)
	armed_for_day = -1


func dev_has_snapshot() -> bool:
	return not _dev_snapshot.is_empty()


# ---------------------------------------------------------- save / load
## Transient state (an event in progress, the developer override) is never
## saved: a load starts with nothing showing, and today's arming is
## reproduced deterministically.
func state_dict() -> Dictionary:
	var ev := {}
	for id in state:
		ev[String(id)] = state[id].duplicate()
	return {"events": ev, "feed_days": feed_days.duplicate(true), "armed_for_day": armed_for_day,
		"story": {"version": 2, "phase": story_phase, "milestones": milestones.duplicate(), "duties": duty_kinds.duplicate(), "investigations": investigations.duplicate(), "evidence": evidence.duplicate(true), "phase2_day": phase2_day, "closed_today": _closed_today}}


func load_dict(d: Dictionary) -> void:
	if active != &"":
		active_dev = true
		stop(false)
		history.pop_back()
	var ev: Dictionary = d.get("events", {})
	for id in state:
		state[id] = _blank()
		if ev.has(String(id)):
			var src: Dictionary = ev[String(id)]
			state[id] = {"plays": int(src.get("plays", 0)), "last_day": int(src.get("last_day", -99)), "armed_day": int(src.get("armed_day", -1)), "seen": bool(src.get("seen", false))}
	feed_days = {}
	var fd: Dictionary = d.get("feed_days", {})
	for k in fd:
		feed_days[String(k)] = Array(fd[k]).map(func(x): return int(x))
	armed_for_day = int(d.get("armed_for_day", -1))
	var sd: Dictionary = d.get("story", {})
	if sd.is_empty():
		# Round 41 save (day-based phases): MIGRATE. Played / seen flags are
		# kept; a technician who already experienced an anomaly stays in
		# phase 2 (milestones marked as migrated), otherwise phase 1 with
		# the intro credited from the calendar.
		milestones = []
		duty_kinds = []
		investigations = []
		story_phase = 1
		var any_played := false
		for id in state:
			if int(state[id]["plays"]) > 0:
				any_played = true
		if day() >= 2:
			milestones.append("intro_complete")
		if any_played:
			for m in ["intro_complete", "station_familiar", "handover_read"]:
				if not milestones.has(m):
					milestones.append(m)
			milestones.append("migrated_r41")
			story_phase = 2
	else:
		story_phase = clampi(int(sd.get("phase", 1)), 1, 3)
		milestones = Array(sd.get("milestones", [])).map(func(x): return String(x))
		duty_kinds = Array(sd.get("duties", [])).map(func(x): return String(x))
		investigations = Array(sd.get("investigations", [])).map(func(x): return String(x))
	phase2_day = int(sd.get("phase2_day", -1))
	_closed_today = int(sd.get("closed_today", 0))
	evidence = []
	for e in Array(sd.get("evidence", [])):
		if e is Dictionary:
			evidence.append({"event": String(e.get("event", "")), "day": int(e.get("day", 0)), "kind": String(e.get("kind", "")), "text": String(e.get("text", "")), "ref": String(e.get("ref", ""))})
	_check_milestones()
