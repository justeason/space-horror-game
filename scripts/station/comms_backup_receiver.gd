extends "res://scripts/station/equipment_base.gd"
## Round 42 Priority 28, COMMS TASK B -- BACKUP RECEIVER TEST.
## The backup receiver rack unit ("RX-B", Communications east wall, north
## of the alcove) is proved once in a while: switch the station from the
## MAIN to the BACKUP receiver (it needs a couple of seconds to lock),
## step through its three channels A / B / C and LOG each one's gain /
## noise against the main receiver, then switch back to MAIN. One channel
## (order seed, saved) reads noisy -- logging it flags it in the
## maintenance log for the antenna diagnostics. Real comparison values,
## physical selector, lamps and readout; the order closes itself when all
## three are logged and MAIN is restored.

const CHANNELS := ["A", "B", "C"]
const LOCK_S := 2.0

var on_backup: bool = false
var chan: int = 0
var logged: Array = [true, true, true]
var degraded: int = -1
var lock_t: float = 0.0
var _mode_lever: Node3D
var _chan_knob: Node3D
var _readout: Label3D
var _main_lamp: StandardMaterial3D
var _bk_lamp: StandardMaterial3D
var _log_lamps: Array = []


func _ready() -> void:
	_base_ready(&"backup_rx")
	box(Vector3(0.48, 0.3, 0.12), Vector3(0, 1.18, -0.06), Color(0.17, 0.18, 0.2))
	box(Vector3(0.5, 0.025, 0.13), Vector3(0, 1.34, -0.055), Color(0.3, 0.6, 0.85))
	label("RX-B  BACKUP RECEIVER", Vector3(0, 1.3, 0.004), 11)
	# MAIN / BACKUP lever.
	_mode_lever = Node3D.new()
	_mode_lever.position = Vector3(-0.17, 1.17, 0.0)
	add_child(_mode_lever)
	box(Vector3(0.022, 0.08, 0.022), Vector3(0, 0.035, 0.015), Color(0.85, 0.2, 0.15), _mode_lever)
	label("MAIN  BKUP", Vector3(-0.17, 1.245, 0.005), 8)
	part(&"mode", Vector3(0.08, 0.12, 0.06), Vector3(-0.17, 1.19, 0.02))
	_main_lamp = lamp(Vector3(-0.2, 1.1, 0.006))
	_bk_lamp = lamp(Vector3(-0.14, 1.1, 0.006))
	# Channel knob.
	_chan_knob = Node3D.new()
	_chan_knob.position = Vector3(-0.04, 1.16, 0.01)
	add_child(_chan_knob)
	var kc := CSGCylinder3D.new()
	kc.radius = 0.028
	kc.height = 0.025
	kc.rotation_degrees.x = 90.0
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.1, 0.1, 0.11)
	kc.material = km
	_chan_knob.add_child(kc)
	box(Vector3(0.006, 0.03, 0.01), Vector3(0, 0.013, 0.014), Color(0.95, 0.95, 0.9), _chan_knob)
	label("A  B  C", Vector3(-0.04, 1.215, 0.005), 8)
	part(&"chan", Vector3(0.07, 0.07, 0.06), Vector3(-0.04, 1.16, 0.02))
	# Readout + LOG.
	box(Vector3(0.16, 0.08, 0.01), Vector3(0.1, 1.18, 0.002), Color(0.03, 0.05, 0.05))
	_readout = label("", Vector3(0.1, 1.18, 0.009), 9, Color(0.55, 0.95, 0.75))
	box(Vector3(0.07, 0.035, 0.02), Vector3(0.1, 1.1, 0.01), Color(0.2, 0.45, 0.7))
	label("LOG", Vector3(0.1, 1.1, 0.022), 8)
	part(&"log", Vector3(0.09, 0.05, 0.05), Vector3(0.1, 1.1, 0.02))
	for i in 3:
		_log_lamps.append(lamp(Vector3(0.2, 1.21 - i * 0.04, 0.006), null, 0.008))
	_refresh()


func locked() -> bool:
	return on_backup and lock_t >= LOCK_S


## [gain dB, noise dB] for the CURRENT receiver path.
func reading() -> Array:
	if not on_backup:
		return [33.0, 3.0]
	if not locked():
		return [0.0, 0.0]
	return [31.0 - chan * 0.5, 13.0 if chan == degraded else 4.0 + chan * 0.5]


func _process(delta: float) -> void:
	if on_backup and lock_t < LOCK_S:
		lock_t += delta
		if lock_t >= LOCK_S:
			sfx(&"click")
		_refresh()


func on_part(id: StringName) -> void:
	match id:
		&"mode":
			on_backup = not on_backup
			lock_t = 0.0
			sfx(&"latch")
			say("Receiver: %s." % ("BACKUP — acquiring" if on_backup else "MAIN"))
			if not on_backup and _dp != null and logged.all(func(v): return v) and degraded >= 0:
				_dp.log_event("Backup receiver test done (CH %s noisy — flagged)" % CHANNELS[degraded])
		&"chan":
			chan = (chan + 1) % 3
			sfx(&"click")
		&"log":
			if not on_backup:
				say("Switch to BACKUP to log its channels.")
				return
			if not locked():
				say("Backup still acquiring — wait for RX LOCK.")
				return
			logged[chan] = true
			sfx(&"success" if chan != degraded else &"fail")
			var r: Array = reading()
			say("CH %s logged: gain %.1f dB, noise %.1f dB%s" % [CHANNELS[chan], r[0], r[1], "  — HIGH, flagged" if chan == degraded else ""])
	_refresh()


func part_prompt(id: StringName) -> String:
	match id:
		&"mode": return "Click: receiver to %s" % ("MAIN" if on_backup else "BACKUP")
		&"chan": return "Click: backup channel (now %s)" % CHANNELS[chan]
		&"log": return "Click: LOG channel %s" % CHANNELS[chan] if locked() else "LOG (backup must be locked)"
	return ""


func _refresh() -> void:
	if _mode_lever != null:
		_mode_lever.rotation_degrees.z = -35.0 if on_backup else 35.0
		_chan_knob.rotation_degrees.z = 40.0 - chan * 40.0
		set_lamp(_main_lamp, Color(0.3, 0.9, 0.4), not on_backup)
		set_lamp(_bk_lamp, Color(1.0, 0.65, 0.15) if not locked() else Color(0.3, 0.9, 0.4), on_backup)
		for i in 3:
			set_lamp(_log_lamps[i], Color(1.0, 0.3, 0.2) if (logged[i] and i == degraded) else Color(0.3, 0.9, 0.4), logged[i])
	if _readout != null:
		var r: Array = reading()
		if on_backup and not locked():
			_readout.text = "BKUP CH %s\nACQUIRING..." % CHANNELS[chan]
		else:
			_readout.text = "%s\nG %.1f  N %.1f dB" % ["MAIN" if not on_backup else "BKUP CH %s" % CHANNELS[chan], r[0], r[1]]


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	degraded = rng.randi() % 3
	logged = [false, false, false]
	on_backup = false
	chan = 0
	lock_t = 0.0
	_refresh()


func order_severity() -> int:
	return 1 if not order_done() else 0


func order_feasible() -> bool:
	return not on_backup


func order_done() -> bool:
	return logged.all(func(v): return v) and not on_backup


func order_next() -> Dictionary:
	var r := &"communications"
	if not logged.all(func(v): return v):
		if not on_backup:
			return {"action": "RX-B: switch to the BACKUP receiver", "short": "TO BACKUP", "room": r}
		for i in 3:
			if not logged[i]:
				return {"action": "Log backup channel %s" % CHANNELS[i], "short": "LOG CH %s" % CHANNELS[i], "room": r}
	return {"action": "Switch back to the MAIN receiver", "short": "TO MAIN", "room": r}


func order_progress() -> String:
	return "%d/3" % logged.filter(func(v): return v).size()


func order_detail() -> Array:
	var lines: Array = ["Backup receiver RX-B (Communications). Path: %s." % ("BACKUP" if on_backup else "MAIN")]
	for i in 3:
		lines.append("CH %s: %s" % [CHANNELS[i], ("noise HIGH (flagged)" if i == degraded else "nominal") if logged[i] else "not logged"])
	return lines


func state_dict() -> Dictionary:
	return {"on_backup": on_backup, "chan": chan, "logged": logged.duplicate(), "degraded": degraded}


func load_dict(d: Dictionary) -> void:
	on_backup = bool(d.get("on_backup", false))
	chan = clampi(int(d.get("chan", 0)), 0, 2)
	logged = Array(d.get("logged", logged)).map(func(v): return bool(v))
	degraded = int(d.get("degraded", -1))
	lock_t = 0.0
	_refresh()
