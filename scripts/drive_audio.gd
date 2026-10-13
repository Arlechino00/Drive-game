class_name DriveAudio
extends Node

const SAMPLE_RATE: int = 22050
const Director = preload("res://scripts/difficulty_director.gd")
const MUSIC_BPM := 110.0
const MUSIC_BEATS := 64
static var _music_stream: AudioStreamWAV
static var _tension_stream: AudioStreamWAV

var engine: AudioStreamPlayer
var boost_loop: AudioStreamPlayer
var music: AudioStreamPlayer
var music_tension: AudioStreamPlayer
var police_loop: AudioStreamPlayer
var wind: AudioStreamPlayer
var cues: Dictionary = {}
var _driving_intensity := 0.0
var _police_active := false
var _event_tension := 0.0


func _ready() -> void:
	for bus_name in ["Music", "Engine", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	engine = _player("Engine", _synthesize("engine", 1.0, true), -22.0)
	boost_loop = _player("Engine", _synthesize("boost", 1.0, true), -25.0)
	# One sixteen-bar arrangement is shared across restarts and scene instances.
	if _music_stream == null:
		_music_stream = _synthesize("music", MUSIC_BEATS * 60.0 / MUSIC_BPM, true)
		_tension_stream = _synthesize("tension", 8.0 * 60.0 / MUSIC_BPM, true)
	music = _player("Music", _music_stream, -22.0)
	music_tension = _player("Music", _tension_stream, -48.0)
	cues["ui"] = _player("UI", _synthesize("ui", 0.10), -17.0)
	cues["near_miss"] = _player("SFX", _synthesize("near_miss", 0.18), -14.0)
	cues["crash"] = _player("SFX", _synthesize("crash", 0.28), -12.0)
	cues["pothole"] = _player("SFX", _synthesize("pothole", 0.18), -13.0)
	cues["capture"] = _player("SFX", _synthesize("capture", 0.25), -16.0)
	police_loop = _player("SFX", _synthesize("siren", 1.0, true), -25.0)
	wind = _player("Engine", _synthesize("wind", 1.0, true), -36.0)
	music.play()
	music_tension.play()

func _process(delta: float) -> void:
	var tension := maxf(_event_tension, 1.0 if _police_active else 0.0)
	var target := -48.0 + _driving_intensity * 15.0 + tension * 8.0
	music_tension.volume_db = move_toward(music_tension.volume_db, target, maxf(0.0, delta) * 12.0)

func set_tension(amount: float) -> void:
	_event_tension = clampf(amount, 0.0, 1.0)


func set_driving(driving: bool, speed: float, boosting: bool) -> void:
	if driving and not engine.playing:
		engine.play()
	elif not driving and engine.playing:
		engine.stop()
	var intensity := 1.0 - exp(-maxf(0.0, speed - Director.INITIAL_SPEED) / 75.0)
	_driving_intensity = intensity if driving else 0.0
	engine.pitch_scale = 0.95 + intensity * 1.2
	wind.volume_db = -36.0 + intensity * 14.0
	wind.pitch_scale = 0.85 + intensity * 0.5
	if driving and not wind.playing:
		wind.play()
	elif not driving:
		wind.stop()
	if driving and boosting and not boost_loop.playing:
		boost_loop.play()
	elif (not driving or not boosting) and boost_loop.playing:
		boost_loop.stop()


func play_cue(cue: String) -> void:
	if cues.has(cue):
		cues[cue].play()


func set_police(enabled: bool) -> void:
	_police_active = enabled
	if enabled and not police_loop.playing:
		police_loop.play()
	elif not enabled:
		police_loop.stop()


func stop_all() -> void:
	_driving_intensity = 0.0
	_police_active = false
	_event_tension = 0.0
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()


func stop_transients() -> void:
	_police_active = false
	_event_tension = 0.0
	for cue in cues.values():
		cue.stop()
	boost_loop.stop()
	police_loop.stop()


func _exit_tree() -> void:
	stop_all()


func _player(bus_name: String, stream: AudioStream, level: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	player.stream = stream
	player.volume_db = level
	add_child(player)
	return player


func _synthesize(kind: String, duration: float, loop: bool = false) -> AudioStreamWAV:
	var samples := maxi(1, roundi(duration * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(samples * 2)
	var roots := [45, 41, 48, 43, 45, 48, 41, 43]
	var melody := [0, 7, 12, 15, 7, 12, 19, 12]
	var noise := RandomNumberGenerator.new()
	noise.seed = 618
	for index in range(samples):
		var time := float(index) / SAMPLE_RATE
		var value := 0.0
		var envelope := minf(1.0, time * 100.0) * minf(1.0, (duration - time) * 45.0)
		match kind:
			"wind":
				value = noise.randf_range(-0.22, 0.22)
				envelope = 1.0
			"engine":
				value = sin(TAU * 45.0 * time) * 0.45 + sin(TAU * 90.0 * time) * 0.15 + sin(TAU * 135.0 * time) * 0.08
				envelope = 1.0
			"boost":
				value = sin(TAU * 120.0 * time) * 0.18 + sin(TAU * 240.0 * time) * 0.10 + noise.randf_range(-0.08, 0.08)
				envelope = 1.0
			"ui": value = sin(TAU * 660.0 * time) * 0.4
			"capture": value = sin(TAU * (880.0 if time < 0.12 else 1100.0) * time) * 0.35
			"near_miss": value = sin(TAU * (440.0 * time + 900.0 * time * time)) * 0.45
			"crash": value = (noise.randf_range(-0.7, 0.7) + sin(TAU * 70.0 * time) * 0.3) * exp(-time * 13.0)
			"pothole": value = (sin(TAU * 52.0 * time) * 0.6 + noise.randf_range(-0.2, 0.2)) * exp(-time * 20.0)
			"siren":
				var tone := 660.0 if time < 0.5 else 880.0
				value = sin(TAU * tone * time) * 0.20
				envelope = 1.0
			"music":
				var beat := time * MUSIC_BPM / 60.0
				var beat_time := fmod(beat, 1.0)
				var phrase := floori(beat / 8.0)
				var root_note: int = roots[phrase % roots.size()]
				var bass := 440.0 * pow(2.0, (root_note - 69.0) / 12.0)
				var note: int = root_note + melody[(int(beat) + phrase * 3) % melody.size()]
				var frequency := 440.0 * pow(2.0, (note - 69.0) / 12.0)
				var note_envelope := minf(1.0, beat_time * 22.0) * exp(-beat_time * 5.0)
				var density := 0.65 if phrase in [0, 4] else 1.0
				value = sin(TAU * frequency * time) * note_envelope * 0.28 * density
				value += sin(TAU * frequency * 2.0 * time) * note_envelope * 0.055
				value += sin(TAU * bass * 0.5 * time) * 0.10 * exp(-beat_time * 2.0)
				value += sin(TAU * (48.0 * time + 0.5 * (1.0 - exp(-beat_time * 35.0)))) * exp(-beat_time * 18.0) * 0.10
				if phrase % 4 >= 2:
					value += sin(TAU * frequency * 1.5 * time) * note_envelope * 0.035
			"tension":
				var pulse := fmod(time * MUSIC_BPM / 60.0 * 2.0, 1.0)
				var pulse_envelope := minf(1.0, pulse * 30.0) * exp(-pulse * 6.0)
				value = (sin(TAU * 220.0 * time) + sin(TAU * 330.0 * time) * 0.3) * pulse_envelope * 0.18
		data.encode_s16(index * 2, roundi(clampf(value * envelope, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples
	return stream
