extends AudioStreamPlayer
## Small procedural sound bank for maintenance-interaction feedback
## (wire disconnect/reconnect clicks, breaker clunk, screw ratchet,
## success/fail tones, calibration lock-in chime). Same convention as
## scripts/audio/footstep_player.gd: no sampled audio assets exist in
## this repo, so every sound is synthesized once at startup rather than
## left silent. Non-positional (AudioStreamPlayer, not …3D) because
## this plays for focused UI feedback, not a thing happening at a point
## in the 3D world.

const SAMPLE_RATE := 22050

var _streams: Dictionary = {}


func _ready() -> void:
	bus = "SFX"   # Round 34: real audio buses (Settings sliders)
	_streams[&"click"] = _build_click()
	_streams[&"clunk"] = _build_clunk()
	_streams[&"success"] = _build_success()
	_streams[&"fail"] = _build_fail()
	_streams[&"ratchet"] = _build_ratchet()
	# Round 35: equipment feedback (restrained, mechanical; no stingers).
	_streams[&"breaker"] = _tone(0.12, func(t, i): return (sin(t * TAU * 180.0) * 0.6 + (fmod(float(i) * 12.9898, 1.0) - 0.5) * 0.8) * pow(1.0 - t, 8.0))
	_streams[&"relay"] = _tone(0.09, func(t, _i): return sin(t * TAU * 2400.0) * (pow(1.0 - t * 2.0, 6.0) if t < 0.5 else pow(1.0 - (t - 0.5) * 2.0, 6.0) * 0.7))
	_streams[&"hiss"] = _tone(1.1, func(t, i): return (fmod(sin(float(i) * 78.233) * 43758.5453, 1.0) - 0.5) * 0.35 * (1.0 - t) * minf(t * 8.0, 1.0))
	_streams[&"latch"] = _tone(0.07, func(t, _i): return sin(t * TAU * 650.0) * pow(1.0 - t, 5.0) * 0.8)
	_streams[&"insert"] = _tone(0.22, func(t, i): return ((fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.2 * (1.0 - t) + (sin(t * TAU * 900.0) * pow(maxf(1.0 - (t - 0.8) * 5.0, 0.0), 4.0) * 0.7 if t > 0.8 else 0.0)))
	_streams[&"warn"] = _tone(0.5, func(t, _i): return sin(t * TAU * (660.0 if t < 0.5 else 520.0)) * 0.35 * (1.0 if fmod(t, 0.5) < 0.4 else 0.0))
	_streams[&"power_down"] = _tone(0.6, func(t, _i): return sin(t * TAU * (220.0 - 150.0 * t) * 1.0) * 0.4 * (1.0 - t))
	_streams[&"power_up"] = _tone(0.6, func(t, _i): return sin(t * TAU * (90.0 + 200.0 * t)) * 0.4 * minf(t * 4.0, 1.0) * (1.0 - t * 0.5))
	_streams[&"scrub"] = _tone(0.18, func(t, i): return (fmod(sin(float(i) * 3.7) * 9301.0, 1.0) - 0.5) * 0.4 * sin(t * PI))


## `kind` is one of &"click"/&"clunk"/&"success"/&"fail"/&"ratchet".
## Unknown kinds are silently ignored (defensive no-op, same spirit as
## terminal_connector.gd's own "should be unreachable, but harmless if
## it happens" convention) rather than erroring out of a minigame over
## a sound.
func play_kind(kind: StringName) -> void:
	if not _streams.has(kind):
		return
	stream = _streams[kind]
	pitch_scale = randf_range(0.97, 1.03)
	play()


func _tone(duration_sec: float, build: Callable) -> AudioStreamWAV:
	var frame_count := int(SAMPLE_RATE * duration_sec)
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)
	for i in frame_count:
		var t: float = float(i) / float(frame_count)
		var sample: float = clampf(build.call(t, i), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Short, dry connector click -- a correct disconnect/reconnect action.
func _build_click() -> AudioStreamWAV:
	return _tone(0.05, func(t, _i):
		var envelope: float = pow(1.0 - t, 6.0)
		var tone: float = sin(t * TAU * 1200.0)
		return tone * envelope * 0.8
	)


## Heavier mechanical clunk -- breaker/isolation toggle.
func _build_clunk() -> AudioStreamWAV:
	return _tone(0.16, func(t, _i):
		var envelope: float = pow(1.0 - t, 3.0)
		var tone: float = sin(t * TAU * 90.0)
		var rng_noise: float = randf_range(-1.0, 1.0)
		return (tone * 0.75 + rng_noise * 0.25) * envelope
	)


## Short rising two-note chime -- a stage/task fully succeeds.
func _build_success() -> AudioStreamWAV:
	return _tone(0.22, func(t, _i):
		var freq: float = 660.0 if t < 0.5 else 880.0
		var local_t: float = fmod(t, 0.5) * 2.0
		var envelope: float = pow(1.0 - local_t, 2.0)
		return sin(t * TAU * freq) * envelope * 0.7
	)


## Short descending buzz -- an incorrect action (recoverable, not punitive).
func _build_fail() -> AudioStreamWAV:
	return _tone(0.18, func(t, _i):
		var freq: float = lerp(260.0, 140.0, t)
		var envelope: float = pow(1.0 - t, 1.5)
		return sin(t * TAU * freq) * envelope * 0.6
	)


## Three quick ratchet ticks -- one screw turn.
func _build_ratchet() -> AudioStreamWAV:
	return _tone(0.12, func(t, _i):
		var tick_phase: float = fmod(t * 3.0, 1.0)
		var envelope: float = pow(1.0 - tick_phase, 8.0)
		var noise: float = randf_range(-1.0, 1.0)
		return noise * envelope * 0.5
	)
