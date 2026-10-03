class_name DriveAudio
extends Node

const SAMPLE_RATE: int = 22050
const Director = preload("res://scripts/difficulty_director.gd")

var engine: AudioStreamPlayer
var boost_loop: AudioStreamPlayer
var music: AudioStreamPlayer
var police_loop: AudioStreamPlayer
var cues: Dictionary = {}


func _ready() -> void:
	for bus_name in ["Music", "Engine", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	engine = _player("Engine", _synthesize("engine", 1.0, true), -22.0)
	boost_loop = _player("Engine", _synthesize("boost", 1.0, true), -25.0)
	music = _player("Music", _synthesize("music", 4.363636, true), -22.0)
	cues["ui"] = _player("UI", _synthesize("ui", 0.10), -17.0)
	cues["near_miss"] = _player("SFX", _synthesize("near_miss", 0.18), -14.0)
	cues["crash"] = _player("SFX", _synthesize("crash", 0.28), -12.0)
	cues["pothole"] = _player("SFX", _synthesize("pothole", 0.18), -13.0)
	police_loop = _player("SFX", _synthesize("siren", 1.0, true), -25.0)
	music.play()


func set_driving(driving: bool, speed: float, boosting: bool) -> void:
	if driving and not engine.playing:
		engine.play()
	elif not driving and engine.playing:
		engine.stop()
	engine.pitch_scale = 0.95 + clampf((speed - Director.INITIAL_SPEED) / (Director.MAX_BOOST_SPEED - Director.INITIAL_SPEED), 0.0, 1.0) * 0.9
	if driving and boosting and not boost_loop.playing:
		boost_loop.play()
	elif (not driving or not boosting) and boost_loop.playing:
		boost_loop.stop()


func play_cue(cue: String) -> void:
	if cues.has(cue):
		cues[cue].play()


func set_police(enabled: bool) -> void:
	if enabled and not police_loop.playing:
		police_loop.play()
	elif not enabled:
		police_loop.stop()


func stop_all() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()


func stop_transients() -> void:
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
	var notes: Array[float] = [110.0, 164.8138, 220.0, 293.6648, 110.0, 146.8324, 195.9977, 261.6256]
	var noise := RandomNumberGenerator.new()
	noise.seed = 618
	for index in range(samples):
		var time := float(index) / SAMPLE_RATE
		var value := 0.0
		var envelope := minf(1.0, time * 100.0) * minf(1.0, (duration - time) * 45.0)
		match kind:
			"engine":
				value = sin(TAU * 45.0 * time) * 0.45 + sin(TAU * 90.0 * time) * 0.15 + sin(TAU * 135.0 * time) * 0.08
				envelope = 1.0
			"boost":
				value = sin(TAU * 120.0 * time) * 0.18 + sin(TAU * 240.0 * time) * 0.10 + noise.randf_range(-0.08, 0.08)
				envelope = 1.0
			"ui": value = sin(TAU * 660.0 * time) * 0.4
			"near_miss": value = sin(TAU * (440.0 * time + 900.0 * time * time)) * 0.45
			"crash": value = (noise.randf_range(-0.7, 0.7) + sin(TAU * 70.0 * time) * 0.3) * exp(-time * 13.0)
			"pothole": value = (sin(TAU * 52.0 * time) * 0.6 + noise.randf_range(-0.2, 0.2)) * exp(-time * 20.0)
			"siren":
				var tone := 660.0 if time < 0.5 else 880.0
				value = sin(TAU * tone * time) * 0.20
				envelope = 1.0
			"music":
				var beat := time * 110.0 / 60.0
				var beat_time := fmod(beat, 1.0)
				var frequency := notes[int(beat) % notes.size()]
				var note_envelope := minf(1.0, beat_time * 22.0) * exp(-beat_time * 5.0)
				value = sin(TAU * frequency * time) * note_envelope * 0.35 + sin(TAU * 55.0 * time) * 0.12
				value += sin(TAU * frequency * 2.0 * time) * note_envelope * 0.07
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
