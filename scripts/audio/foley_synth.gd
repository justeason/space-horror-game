extends RefCounted
## Round 48 Priorities 14-19: PHYSICAL FOLEY, synthesised offline-style at
## load (no external assets, no network): every sound is built from what
## the real event is made of --
##   impacts      a short broadband contact transient + the struck object's
##                resonant MODES (frequency, decay, level per mode) + the
##                structure it is mounted on (a low thump);
##   liquids      band-limited noise shaped by the flow (slow amplitude
##                modulation, a few bubble blips), no tonal "slurp";
##   friction     noise through a band filter with a stroke envelope that is
##                phase-locked to the visible motion.
## Deterministic (fixed seeds), mono 16-bit 22.05 kHz, peak-normalised to a
## per-sound target so levels are set in one place (station_sounds.KIND_DB).
## Limitation (documented): synthesis approximates recorded foley; a human
## listening pass is still required (MILESTONE1_DESIGN.md, Round 48).

const SR := 22050


static func to_wav(buf: PackedFloat32Array, peak: float = 0.8) -> AudioStreamWAV:
	var mx: float = 0.0
	for v in buf:
		mx = maxf(mx, absf(v))
	var g: float = peak / mx if mx > 0.0 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	return s


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * SR))
	return b


## White noise (deterministic).
static func _noise(n: int, seed_v: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = r.randf_range(-1.0, 1.0)
	return b


## RBJ biquad band-pass (constant 0 dB peak gain), in place.
static func _bandpass(b: PackedFloat32Array, f0: float, q: float) -> PackedFloat32Array:
	var w: float = TAU * f0 / SR
	var alpha: float = sin(w) / (2.0 * q)
	var a0: float = 1.0 + alpha
	var b0: float = alpha / a0
	var b2: float = -alpha / a0
	var a1: float = -2.0 * cos(w) / a0
	var a2: float = (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var x: float = b[i]
		var y: float = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		b[i] = y
	return b


## One-pole low-pass, in place.
static func _lowpass(b: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a: float = exp(-TAU * fc / SR)
	var y := 0.0
	for i in b.size():
		y = (1.0 - a) * b[i] + a * y
		b[i] = y
	return b


## One-pole high-pass, in place.
static func _highpass(b: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a: float = exp(-TAU * fc / SR)
	var y := 0.0
	var xp := 0.0
	for i in b.size():
		y = a * (y + b[i] - xp)
		xp = b[i]
		b[i] = y
	return b


## Adds a struck object: modes [[freq, decay_s, level]] starting at `at` s.
static func _modes(b: PackedFloat32Array, at: float, modes: Array, gain: float = 1.0, detune: float = 1.0) -> void:
	var i0: int = int(at * SR)
	for m in modes:
		var f: float = float(m[0]) * detune
		var dec: float = float(m[1])
		var lv: float = float(m[2]) * gain
		var n: int = mini(int(dec * 7.0 * SR), b.size() - i0)
		var ph: float = float(hash([m[0], at]) % 628) / 100.0
		for k in n:
			var t: float = float(k) / SR
			b[i0 + k] += sin(TAU * f * t + ph) * exp(-t / dec) * lv * minf(t * SR / 6.0, 1.0)


## Adds a noise transient (contact) band-limited around f0.
static func _contact(b: PackedFloat32Array, at: float, dur: float, f0: float, q: float, level: float, seed_v: int) -> void:
	var n: int = int(dur * SR)
	var nz: PackedFloat32Array = _bandpass(_noise(n, seed_v), f0, q)
	var i0: int = int(at * SR)
	for k in mini(n, b.size() - i0):
		var t: float = float(k) / float(n)
		b[i0 + k] += nz[k] * level * pow(1.0 - t, 3.0)


## Adds shaped noise: env(t01) -> gain, through a band filter.
static func _shaped(b: PackedFloat32Array, at: float, dur: float, f0: float, q: float, level: float, seed_v: int, env: Callable) -> void:
	var n: int = int(dur * SR)
	var nz: PackedFloat32Array = _bandpass(_noise(n, seed_v), f0, q)
	var i0: int = int(at * SR)
	for k in mini(n, b.size() - i0):
		b[i0 + k] += nz[k] * level * float(env.call(float(k) / float(n), float(k) / SR))


# ---------------------------------------------------------------- impacts

## A knuckle on the thick observation-port glass, heard from INSIDE the
## module: the knock reaches the ear through the pane and its metal frame
## (structure-borne), so it is a dull, dense "tock" with a short glassy
## ring and a low frame thump -- not a door knock (no wood, no room boom).
static func glass_knock(variant: int = 0) -> AudioStreamWAV:
	var b := _buf(0.55)
	var dt: float = 1.0 + 0.025 * float(variant - 1)
	_contact(b, 0.0, 0.004, 3200.0, 0.8, 0.5, 11 + variant)                   # knuckle contact
	_modes(b, 0.001, [[410.0, 0.085, 1.0], [980.0, 0.055, 0.8], [1690.0, 0.04, 0.5], [2620.0, 0.026, 0.3], [3840.0, 0.018, 0.14]], 1.7, dt)   # pane
	_modes(b, 0.002, [[118.0, 0.1, 0.45], [176.0, 0.07, 0.22]], 1.0, dt)     # frame / hull thump
	_modes(b, 0.004, [[2930.0, 0.28, 0.035], [4150.0, 0.2, 0.025]], 1.0, dt)  # faint hull ring
	return to_wav(_lowpass(b, 6500.0), 0.85)


## A gloved fist on the outer airlock hatch -- heavy steel: a deep thud and
## a long, low metallic ring (clearly NOT the glass knock).
static func hatch_knock(variant: int = 0) -> AudioStreamWAV:
	var b := _buf(1.2)
	var dt: float = 1.0 + 0.02 * float(variant - 1)
	_contact(b, 0.0, 0.012, 700.0, 0.7, 0.6, 21 + variant)
	_modes(b, 0.002, [[68.0, 0.2, 1.0], [96.0, 0.14, 0.6]], 1.0, dt)
	_modes(b, 0.003, [[310.0, 0.55, 0.32], [742.0, 0.38, 0.2], [1287.0, 0.26, 0.11], [2034.0, 0.15, 0.06]], 1.0, dt)
	return to_wav(_lowpass(b, 4000.0), 0.9)


## A ceramic mug set down on the metal galley counter.
static func cup_down() -> AudioStreamWAV:
	var b := _buf(0.35)
	_contact(b, 0.0, 0.003, 4000.0, 1.0, 0.4, 31)
	_modes(b, 0.0, [[1930.0, 0.05, 0.6], [3320.0, 0.035, 0.4], [5100.0, 0.02, 0.2]])
	_modes(b, 0.0, [[190.0, 0.04, 0.8]])
	# a tiny second contact (the base settles)
	_modes(b, 0.045, [[1930.0, 0.03, 0.25], [3320.0, 0.02, 0.15]])
	return to_wav(b, 0.7)


## Lifting the mug off the counter: a soft ceramic scrape + tick.
static func cup_lift() -> AudioStreamWAV:
	var b := _buf(0.22)
	_shaped(b, 0.0, 0.12, 2600.0, 1.2, 0.35, 32, func(u, _t): return sin(u * PI))
	_modes(b, 0.11, [[2250.0, 0.02, 0.35]])
	return to_wav(b, 0.45)


## A sip of hot tea: short, airy, a little liquid at the lip -- no slurp.
static func sip() -> AudioStreamWAV:
	var b := _buf(0.42)
	_shaped(b, 0.0, 0.3, 3400.0, 0.9, 0.5, 41, func(u, t): return pow(sin(u * PI), 1.5) * (0.75 + 0.25 * sin(t * TAU * 37.0)))
	var r := RandomNumberGenerator.new()
	r.seed = 42
	for k in 4:                                                                # a few tiny liquid blips
		_modes(b, 0.06 + r.randf() * 0.2, [[r.randf_range(700.0, 1300.0), 0.012, 0.18]])
	return to_wav(_lowpass(b, 7000.0), 0.55)


## A swallow: a soft, low, closed gulp.
static func swallow() -> AudioStreamWAV:
	var b := _buf(0.28)
	var n: int = b.size()
	for k in n:
		var t: float = float(k) / SR
		var f: float = 210.0 - 90.0 * minf(t / 0.12, 1.0)
		b[k] += sin(TAU * f * t) * exp(-pow((t - 0.07) / 0.045, 2.0)) * 0.6
	_shaped(b, 0.02, 0.14, 450.0, 0.8, 0.5, 43, func(u, _t): return sin(u * PI))
	return to_wav(_lowpass(b, 1800.0), 0.5)


## Small liquid movement in the cup as it tilts.
static func liquid_tilt() -> AudioStreamWAV:
	var b := _buf(0.5)
	_shaped(b, 0.0, 0.5, 900.0, 1.4, 0.4, 44, func(u, t): return sin(u * PI) * (0.6 + 0.4 * sin(t * TAU * 6.0)))
	return to_wav(b, 0.3)


# ------------------------------------------------------------------ meals

## A foil/plastic meal pouch handled: sparse crinkles.
static func pouch_crinkle(seed_v: int = 51, seconds: float = 0.35) -> AudioStreamWAV:
	var b := _buf(seconds)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var t := 0.0
	while t < seconds - 0.03:
		_contact(b, t, r.randf_range(0.004, 0.012), r.randf_range(3000.0, 6500.0), 1.5, r.randf_range(0.3, 1.0), r.randi())
		t += r.randf_range(0.008, 0.045)
	return to_wav(_highpass(b, 1500.0), 0.5)


## The pouch's seal torn open.
static func pouch_tear() -> AudioStreamWAV:
	var b := _buf(0.45)
	_shaped(b, 0.0, 0.32, 3800.0, 0.7, 0.8, 52, func(u, t): return pow(sin(u * PI), 0.7) * (0.5 + 0.5 * absf(sin(t * TAU * 47.0))))
	return to_wav(_highpass(b, 1200.0), 0.6)


## A soft bite of pouch food (a paste, not a crunch).
static func bite() -> AudioStreamWAV:
	var b := _buf(0.14)
	_shaped(b, 0.0, 0.1, 900.0, 0.8, 0.6, 53, func(u, _t): return pow(1.0 - u, 2.0))
	_modes(b, 0.0, [[230.0, 0.03, 0.35]])
	return to_wav(_lowpass(b, 2500.0), 0.45)


## Two quiet, closed-mouth chews.
static func chew() -> AudioStreamWAV:
	var b := _buf(0.62)
	for k in 2:
		_shaped(b, 0.04 + k * 0.27, 0.16, 520.0, 0.9, 0.6, 54 + k, func(u, _t): return sin(u * PI))
	return to_wav(_lowpass(b, 1500.0), 0.4)


## A fork touching the tray.
static func fork_clink() -> AudioStreamWAV:
	var b := _buf(0.3)
	_contact(b, 0.0, 0.002, 6000.0, 1.0, 0.3, 61)
	_modes(b, 0.0, [[2820.0, 0.06, 0.6], [4630.0, 0.04, 0.35], [7050.0, 0.025, 0.15]])
	return to_wav(b, 0.4)


## The dinner tray set down / slid back on the counter.
static func tray_down() -> AudioStreamWAV:
	var b := _buf(0.45)
	_shaped(b, 0.0, 0.16, 1100.0, 0.8, 0.5, 62, func(u, _t): return sin(u * PI))
	_contact(b, 0.15, 0.004, 2500.0, 1.0, 0.5, 63)
	_modes(b, 0.15, [[160.0, 0.06, 0.9], [1340.0, 0.05, 0.3], [2410.0, 0.03, 0.18]])
	return to_wav(b, 0.6)


# ------------------------------------------------------------- toothbrush

## The brush taken from (or put back into) its holder: a light plastic tap.
static func brush_tap() -> AudioStreamWAV:
	var b := _buf(0.12)
	_contact(b, 0.0, 0.003, 3000.0, 1.0, 0.4, 71)
	_modes(b, 0.0, [[1240.0, 0.018, 0.5], [2620.0, 0.012, 0.3]])
	return to_wav(b, 0.4)


## Bristles on teeth for `seconds`, the stroke envelope PHASE-LOCKED to the
## visible scrub (player_body: offset = sin(consume_t * TAU * hz)), starting
## at consume time `t0`. Heard inside the mouth: band-limited, soft.
static func brush_scrub(seconds: float, hz: float, t0: float) -> AudioStreamWAV:
	var b := _buf(seconds)
	_shaped(b, 0.0, seconds, 4200.0, 0.8, 0.6, 72, func(u, t):
		var stroke: float = absf(sin((t0 + t) * TAU * hz))
		var speed: float = absf(cos((t0 + t) * TAU * hz))           # loudest mid-stroke
		var fade: float = minf(u * seconds / 0.08, 1.0) * minf((1.0 - u) * seconds / 0.08, 1.0)
		return (0.35 + 0.65 * speed) * (0.6 + 0.4 * stroke) * fade)
	return to_wav(_lowpass(b, 6000.0), 0.4)


# ------------------------------------------------------------------ basil

## Water from the small can onto potting soil: a soft trickle with drops.
static func trickle(seconds: float = 0.7) -> AudioStreamWAV:
	var b := _buf(seconds)
	_shaped(b, 0.0, seconds, 1600.0, 0.9, 0.35, 81, func(u, t): return minf(u * 10.0, 1.0) * minf((1.0 - u) * 6.0, 1.0) * (0.7 + 0.3 * sin(t * TAU * 11.0)))
	var r := RandomNumberGenerator.new()
	r.seed = 82
	for k in 9:
		_modes(b, r.randf() * (seconds - 0.05), [[r.randf_range(500.0, 1100.0), 0.01, 0.2]])
	return to_wav(_lowpass(b, 5000.0), 0.4)
