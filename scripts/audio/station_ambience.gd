extends Node3D
## Round 28 Priority 6: grounded spacecraft ambience. Three quiet, looping,
## procedurally generated beds (no external audio assets), each positioned
## in its room and driven ONLY by real equipment state -- never by scripted
## "horror" cues:
##
## - Ventilation (Living Quarters / Control Room): a constant low air hum.
## - Engineering machinery: steady transformer hum; while the Engineering
##   power fault is open (DayPlan.fault_target set and the panel not yet
##   repaired) it carries an irregular electrical crackle, which stops the
##   moment the panel is repaired.
## - Life Support air circulation: a soft broadband airflow, noticeably
##   quieter/strained while the filter housing's airflow is isolated for
##   service, restored when the procedure completes.
##
## Volumes are kept low (-24..-30 dB) so the beds sit under footsteps and
## mechanical SFX. Headless runs (dummy audio driver) still build and drive
## every player, so state logic is testable without hearing it.

@export var day_plan_path: NodePath
@export var electrical_panel_path: NodePath
@export var filter_station_path: NodePath
@export var vent_position: Vector3 = Vector3(1.5, 2.4, 0.5)
@export var engineering_position: Vector3 = Vector3(-4.2, 1.2, 5.0)
@export var life_support_position: Vector3 = Vector3(-2.9, 1.6, 10.8)

const SAMPLE_RATE := 22050

var vent: AudioStreamPlayer3D
var engineering: AudioStreamPlayer3D
var engineering_fault: AudioStreamPlayer3D
var life_support: AudioStreamPlayer3D

@onready var _day_plan: Node = get_node_or_null(day_plan_path)
@onready var _panel: Node = get_node_or_null(electrical_panel_path)
@onready var _filter: Node = get_node_or_null(filter_station_path)


func _ready() -> void:
	vent = _make("VentilationHum", vent_position, _build_hum(60.0, 0.35, 0.25, 2.0), -27.0, 7.0)
	engineering = _make("EngineeringHum", engineering_position, _build_hum(50.0, 0.5, 0.12, 2.0), -24.0, 6.0)
	engineering_fault = _make("EngineeringFaultCrackle", engineering_position, _build_crackle(2.0), -60.0, 6.0)
	life_support = _make("LifeSupportAirflow", life_support_position, _build_hum(90.0, 0.15, 0.6, 2.0), -26.0, 6.0)
	_apply_state()


func _process(delta: float) -> void:
	_apply_state(delta)


## Release the looping playbacks on exit (otherwise the audio server still
## holds them at shutdown and Godot reports leaked AudioStreamWAV/Playback
## instances).
func _exit_tree() -> void:
	for p in [vent, engineering, engineering_fault, life_support]:
		if p != null:
			p.stop()
			p.stream = null


## True when all four beds are built with looping streams (and playing,
## if a real audio driver is present).
func beds_running() -> bool:
	for p in [vent, engineering, engineering_fault, life_support]:
		if p == null or p.stream == null or (p.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
			return false
		if AudioServer.get_driver_name() != "Dummy" and not p.playing:
			return false
	return true


func engineering_fault_active() -> bool:
	if _day_plan == null or _day_plan.fault_target == &"":
		return false
	return _panel == null or not _panel.is_repaired()


func life_support_isolated() -> bool:
	return _filter != null and _filter.has_method("is_isolated") and _filter.is_isolated()


## Round 31 Priority 8D: equipment START/STOP is audible -- the Life Support
## airflow spins down when the housing is isolated and spins back up when
## airflow is restored (pitch/volume ramp over ~1.5 s instead of a switch),
## and the Engineering crackle fades in/out with the real fault.
var _ls_k: float = 1.0      # 1 = running, 0 = isolated
var _fault_k: float = 0.0


func _apply_state(delta: float = 0.0) -> void:
	var step: float = 1.0 if delta <= 0.0 else delta / 1.5
	_ls_k = move_toward(_ls_k, 0.0 if life_support_isolated() else 1.0, step)
	_fault_k = move_toward(_fault_k, 1.0 if engineering_fault_active() else 0.0, step * 2.0)
	engineering_fault.volume_db = lerpf(-80.0, -26.0, _fault_k) if _fault_k > 0.0 else -80.0
	life_support.volume_db = lerpf(-34.0, -26.0, _ls_k)
	life_support.pitch_scale = lerpf(0.85, 1.0, _ls_k)


func life_support_spin() -> float:
	return _ls_k


func _make(n: String, pos: Vector3, stream: AudioStreamWAV, db: float, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = n
	p.stream = stream
	p.volume_db = db
	p.unit_size = unit_size
	p.max_distance = 14.0
	p.position = pos
	add_child(p)
	# Under the headless "Dummy" audio driver nothing is ever mixed, and a
	# started looping playback is never released before shutdown (Godot
	# then reports leaked AudioStreamWAV/Playback instances) -- so only
	# start playback when a real audio driver is running.
	if AudioServer.get_driver_name() != "Dummy":
		p.play()
	return p


## Looping hum: fundamental + 2 harmonics + filtered noise (air).
func _build_hum(freq: float, tone: float, noise: float, seconds: float) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 1000.0)
	var lp := 0.0
	# Whole number of cycles so the loop is seamless.
	var f: float = round(freq * seconds) / seconds
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.04
		var v: float = tone * (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.25 + sin(TAU * f * 3.0 * t) * 0.1) + noise * lp * 2.5
		data.encode_s16(i * 2, int(clampf(v * 0.5, -1.0, 1.0) * 32767.0))
	return _wav(data, n)


## Irregular electrical crackle (sparse clicks + a buzzing 100Hz edge).
func _build_crackle(seconds: float) -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var env := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		if rng.randf() < 0.0009:
			env = 1.0
		env *= 0.9965
		var buzz: float = signf(sin(TAU * 100.0 * t)) * 0.15 * env
		var v: float = (rng.randf_range(-1.0, 1.0) * 0.6 + buzz) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return _wav(data, n)


func _wav(data: PackedByteArray, frames: int) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = frames
	return s
