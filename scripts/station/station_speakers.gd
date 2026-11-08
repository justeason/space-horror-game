extends Node3D
## Round 37 Priority 3: the station's INTERCOM SPEAKERS -- small ceiling-
## mounted units (grille, trim ring, activity LED), one per room plus one
## for the central junction / corridors. Ceiling-mounted so they never
## block walking or any interaction (no colliders at all).
##
## Every station voice line, chime and alert tone plays through ONE chosen
## unit as a positional AudioStreamPlayer3D on the "Intercom" bus (routed
## into "Voice", so the Voice / Master volume settings apply): the unit of
## the room the player is in, else the nearest one. The unit is chosen at
## the START of a line and kept for its whole duration (no jumping between
## speakers mid-sentence). The Intercom bus adds a light, intelligible
## "intercom" colouring (band-limited, faint short room reflection).

## [id, position (ceiling underside), room volume centre, room volume size]
const UNITS := [
	[&"living_quarters", Vector3(4.6, 2.78, 1.6), Vector3(3.7, 1.5, 0.5), Vector3(4.0, 3.2, 4.0)],
	[&"control_room", Vector3(0.6, 2.98, 1.2), Vector3(0.0, 1.5, 0.5), Vector3(2.8, 3.2, 3.4)],
	[&"engineering", Vector3(-3.4, 3.18, 6.2), Vector3(-4.2, 1.6, 5.0), Vector3(3.2, 3.4, 3.8)],
	[&"life_support", Vector3(-3.8, 3.18, 10.2), Vector3(-2.9, 1.6, 10.8), Vector3(3.2, 3.4, 2.4)],
	[&"storage", Vector3(-6.0, 3.18, 8.6), Vector3(-6.5, 1.6, 8.0), Vector3(2.2, 3.4, 2.2)],
	[&"communications", Vector3(2.6, 3.18, 6.4), Vector3(2.4, 1.6, 7.1), Vector3(4.2, 3.4, 2.4)],
	[&"airlock", Vector3(-4.8, 2.58, -0.8), Vector3(-4.8, 1.4, 0.25), Vector3(1.0, 2.8, 5.7)],
	[&"main_junction", Vector3(0.4, 2.58, 4.5), Vector3(0.0, 1.4, 4.5), Vector3(2.0, 2.8, 2.0)],
]
const BUS := "Intercom"

var units: Dictionary = {}       # id -> {root, player, led: StandardMaterial3D, glow: OmniLight3D}
var _active: StringName = &""
var play_log: Array = []         # [{unit, kind, t}] (tests / diagnostics)


func _ready() -> void:
	add_to_group(&"station_speakers")
	ensure_bus()
	for u in UNITS:
		_build_unit(u[0], u[1])
	# Round 38: the EVA suit radio -- the station voice while outside comes
	# through the helmet (in-head, not from a room speaker).
	var radio := AudioStreamPlayer.new()
	radio.name = "SuitRadio"
	radio.bus = BUS
	add_child(radio)
	var radio_tone := AudioStreamPlayer.new()
	radio_tone.bus = BUS
	add_child(radio_tone)
	units[&"suit_radio"] = {"root": self, "player": radio, "tone": radio_tone, "led": StandardMaterial3D.new(), "glow": OmniLight3D.new()}


## The Intercom bus (created once per process): band-limited, faint room
## reflection, sending into Voice.
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	if AudioServer.get_bus_index("Voice") == -1:
		preload("res://scripts/station/game_settings.gd")._ensure_buses()
	AudioServer.add_bus()
	var i: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Voice")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 220.0
	AudioServer.add_bus_effect(i, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 6200.0
	AudioServer.add_bus_effect(i, lp)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.18
	rv.damping = 0.7
	rv.wet = 0.08
	rv.dry = 1.0
	AudioServer.add_bus_effect(i, rv)


func _build_unit(id: StringName, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Speaker_%s" % String(id)
	add_child(root)
	root.global_position = pos
	var mat := func(c: Color, metal: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = 0.55
		return m
	var ring := CSGCylinder3D.new()
	ring.radius = 0.095
	ring.height = 0.025
	ring.sides = 24
	ring.position.y = -0.012
	ring.material = mat.call(Color(0.62, 0.64, 0.66), 0.5)
	root.add_child(ring)
	var grille := CSGCylinder3D.new()
	grille.radius = 0.075
	grille.height = 0.006
	grille.sides = 24
	grille.position.y = -0.026
	grille.material = mat.call(Color(0.12, 0.13, 0.14), 0.3)
	root.add_child(grille)
	for k in 5:
		var slot := CSGBox3D.new()
		slot.size = Vector3(0.11 - absf(k - 2) * 0.02, 0.003, 0.006)
		slot.position = Vector3(0, -0.03, -0.03 + 0.015 * k)
		slot.material = mat.call(Color(0.3, 0.32, 0.34), 0.6)
		root.add_child(slot)
	var led := CSGSphere3D.new()
	led.radius = 0.006
	led.position = Vector3(0.08, -0.026, 0.0)
	var lm := StandardMaterial3D.new()
	lm.emission_enabled = true
	lm.albedo_color = Color(0.1, 0.25, 0.22)
	lm.emission = Color(0, 0, 0)
	led.material = lm
	root.add_child(led)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.35, 1.0, 0.85)
	glow.light_energy = 0.0
	glow.omni_range = 0.6
	glow.shadow_enabled = false
	glow.position.y = -0.06
	root.add_child(glow)
	var player := AudioStreamPlayer3D.new()
	player.name = "Voice"
	player.bus = BUS
	player.unit_size = 3.0
	player.max_distance = 22.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.position.y = -0.05
	root.add_child(player)
	var tone := AudioStreamPlayer3D.new()
	tone.name = "Tone"
	tone.bus = BUS
	tone.unit_size = 3.0
	tone.max_distance = 22.0
	tone.position.y = -0.05
	root.add_child(tone)
	units[id] = {"root": root, "player": player, "tone": tone, "led": lm, "glow": glow}


## The room volume containing a world point, or "" (corridor / tunnel).
static func room_at(p: Vector3) -> StringName:
	for u in UNITS:
		var c: Vector3 = u[2]
		var h: Vector3 = u[3] * 0.5
		if absf(p.x - c.x) <= h.x and absf(p.y - c.y) <= h.y and absf(p.z - c.z) <= h.z:
			return u[0]
	return &""


## The unit that should speak to a listener at `p`: its room's, else the
## nearest unit.
func unit_for(p: Vector3) -> StringName:
	var r: StringName = room_at(p)
	if r != &"" and units.has(r):
		return r
	var best: StringName = &""
	var bd := INF
	for id in units:
		if id == &"suit_radio":
			continue
		var d: float = (units[id]["root"] as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = id
	return best


func unit_position(id: StringName) -> Vector3:
	return (units[id]["root"] as Node3D).global_position if units.has(id) else Vector3.ZERO


## Plays a voice line on one unit (stops any line on every unit first:
## one voice at a time on the station).
func play_voice(id: StringName, stream: AudioStream, pitch: float = 1.0) -> bool:
	stop_voice()
	if not units.has(id) or stream == null:
		return false
	var pl: Node = units[id]["player"]
	pl.stream = stream
	pl.pitch_scale = pitch
	pl.play()
	_active = id
	play_log.append({"unit": String(id), "kind": "voice", "t": Time.get_ticks_msec()})
	return true


func play_tone(id: StringName, stream: AudioStream, volume_db: float = 0.0) -> bool:
	if not units.has(id) or stream == null:
		return false
	var pl: Node = units[id]["tone"]
	pl.stream = stream
	pl.volume_db = volume_db
	pl.play()
	play_log.append({"unit": String(id), "kind": "tone", "t": Time.get_ticks_msec()})
	return true


func stop_voice() -> void:
	for id in units:
		var pl: Node = units[id]["player"]
		if pl.playing:
			pl.stop()
	_active = &""


func voice_playing() -> bool:
	return _active != &"" and units.has(_active) and units[_active]["player"].playing


func active_unit() -> StringName:
	return _active


## Activity indicator: LED + faint glow on the unit currently speaking (or
## sounding a tone).
func _process(_d: float) -> void:
	for id in units:
		var u: Dictionary = units[id]
		if id == &"suit_radio":
			continue
		var on: bool = u["player"].playing or u["tone"].playing or id == _lit
		var m: StandardMaterial3D = u["led"]
		m.emission = Color(0.3, 1.0, 0.8) * 1.6 if on else Color(0, 0, 0)
		m.albedo_color = Color(0.3, 1.0, 0.8) if on else Color(0.1, 0.25, 0.22)
		(u["glow"] as OmniLight3D).light_energy = 0.35 if on else 0.0


## Lights a unit's indicator while the OS-TTS fallback speaks (that audio
## is not positional, but the source is still shown).
var _lit: StringName = &""


func set_lit(id: StringName) -> void:
	_lit = id


func is_lit(id: StringName) -> bool:
	if not units.has(id):
		return false
	return (units[id]["glow"] as OmniLight3D).light_energy > 0.0
