extends Node
## Round 45 Priorities 22-23: the Control Room workstation's PHYSICAL
## TOGGLES now do real things (audit: WsSwitchPower / Comms / LifeSupport /
## Lighting and the standalone Aux switch were decorative -- their own doc
## said so; the ControlPanel pair keeps its existing task role).
##
##   DIAG     (was "Power")     workstation DETAIL mode: technical lines,
##                              units and ranges on Operations / Records;
##                              off = the short visual default.
##   COMMS    (MAIN / BACKUP)   routes the receiver: drives the REAL backup
##                              receiver (comms_backup_receiver.on_backup);
##                              flipping the rack lever moves this switch too.
##   E-TEST   (was "Life Supp") the Junction EMERGENCY-LIGHT TEST: drives
##                              the real test switch (junction_emergency_
##                              lights.test_on) -- usable for that job.
##   LIGHTING (ROOM / SCREEN)   Control Room main light normal / dimmed for
##                              screen work (and the port view at night).
##   MONITOR  (was "Aux")       the workstation camera monitor's power: off =
##                              no feed rendered ("MONITOR OFF").
## Each switch's lever + lamp always matches the state it controls (synced
## from the equipment every few frames), the workstation shows it, and the
## state is saved (equipment-owned states save with their equipment).

const BIND := {
	"diag": ["Interactables/WsSwitchPower", "Diag"],
	"comms": ["Interactables/WsSwitchComms", "Comms"],
	"etest": ["Interactables/WsSwitchLifeSupport", "E-Test"],
	"lighting": ["Interactables/WsSwitchLighting", "Lighting"],
	"monitor": ["Interactables/ToggleSwitch", "Monitor"],
}
const ROOM_LIGHT := "Lights/Light_ControlRoom"
const ROOM_NORMAL := 0.9
const ROOM_SCREEN := 0.3

var diag: bool = false
var lighting_normal: bool = true
var monitor_on: bool = true
var _sw: Dictionary = {}
var _poll: float = 0.0
var _busy: bool = false
signal changed(id: String, on: bool)


func _ready() -> void:
	add_to_group(&"console_toggles")
	add_to_group(&"r35_equipment")
	_bind.call_deferred()


func _root() -> Node:
	return get_parent().get_parent()


func _bind() -> void:
	for id in BIND:
		var sw: Node = _root().get_node_or_null(BIND[id][0])
		if sw == null:
			continue
		_sw[id] = sw
		sw.switch_label = BIND[id][1]
		var lb: Label3D = sw.get_node_or_null("Label3D") as Label3D
		if lb != null:
			lb.text = BIND[id][1]
		sw.state_changed.connect(func(on): _on_switch(id, on))
	_sync_switches()
	_apply_light()


func _elights() -> Node:
	return _root().get_node_or_null("Equipment/JunctionEmergencyLights")


func comms_main() -> bool:
	var rx: Node = _root().get_node_or_null("Equipment/CommsBackupReceiver")
	return rx == null or not bool(rx.on_backup)


func etest_on() -> bool:
	var el: Node = _elights()
	return el != null and bool(el.test_on)


func state(id: String) -> bool:
	match id:
		"diag": return diag
		"comms": return comms_main()
		"etest": return etest_on()
		"lighting": return lighting_normal
		"monitor": return monitor_on
	return false


func _on_switch(id: String, on: bool) -> void:
	if _busy:
		return
	match id:
		"diag":
			diag = on
		"comms":
			var rx: Node = _root().get_node_or_null("Equipment/CommsBackupReceiver")
			if rx != null and bool(rx.on_backup) == on:
				rx.on_part(&"mode")          # the real receiver flips
		"etest":
			var el: Node = _elights()
			if el != null and bool(el.test_on) != on:
				el.on_part(&"test")
		"lighting":
			lighting_normal = on
			_apply_light()
		"monitor":
			monitor_on = on
	var lg: Node = get_tree().get_first_node_in_group(&"station_log")
	if lg != null and id in ["comms", "etest", "monitor"]:
		lg.record("camera" if id != "etest" else "environment", {"comms": "Console: comms routed to %s" % ("MAIN" if comms_main() else "BACKUP"),
			"etest": "Console: emergency-light test %s" % ("ON" if etest_on() else "OFF"), "monitor": "Console: camera monitor %s" % ("ON" if monitor_on else "OFF")}[id])
	_sync_switches()
	changed.emit(id, state(id))


## Every switch shows the state it controls (equipment can change it too).
func _sync_switches() -> void:
	_busy = true
	for id in _sw:
		var sw: Node = _sw[id]
		var want: bool = state(id)
		if bool(sw.is_on) != want:
			sw.is_on = want
			sw._apply_state()
	_busy = false


func _apply_light() -> void:
	var l: Light3D = _root().get_node_or_null(ROOM_LIGHT) as Light3D
	if l != null:
		l.light_energy = ROOM_NORMAL if lighting_normal else ROOM_SCREEN


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.2:
		_poll = 0.0
		_sync_switches()


func state_dict() -> Dictionary:
	return {"diag": diag, "lighting": lighting_normal, "monitor": monitor_on}


func load_dict(d: Dictionary) -> void:
	diag = bool(d.get("diag", false))
	lighting_normal = bool(d.get("lighting", true))
	monitor_on = bool(d.get("monitor", true))
	_apply_light()
	_sync_switches()
