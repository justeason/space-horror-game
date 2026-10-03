extends AudioStreamPlayer3D
## Plays footstep sounds during node-to-node movement.
##
## No sampled audio assets exist in this repo yet, so the footstep sound is
## synthesized once at startup (short noise burst + decaying "thud" tone)
## rather than left silent. This is a genuine, working sound — just
## synthetic — and can be swapped for a sampled .wav later without any
## change to how/when it's triggered.

const SAMPLE_RATE := 22050
const DURATION_SEC := 0.12


func _ready() -> void:
	stream = _build_footstep_stream()
	bus = "Master"


## Call once per footstep. Slight pitch/volume variance avoids a
## machine-gun "identical click" feel across repeated steps.
func play_step() -> void:
	pitch_scale = randf_range(0.9, 1.1)
	volume_db = randf_range(-2.0, 1.0)
	play()


func _build_footstep_stream() -> AudioStreamWAV:
	var frame_count := int(SAMPLE_RATE * DURATION_SEC)
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in frame_count:
		var t := float(i) / float(frame_count)
		var envelope := pow(1.0 - t, 3.0)
		var noise := rng.randf_range(-1.0, 1.0)
		var thud := sin(t * PI * 18.0)
		var sample := clampf((noise * 0.45 + thud * 0.6) * envelope, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
