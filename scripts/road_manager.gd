class_name RoadManager
extends Node3D

const SEGMENT_LENGTH: float = 40.0
const Tuning = preload("res://scripts/stage_two_tuning.gd")
# Preview plus the rear recycling margin; allocate once and reuse on restart.
const SEGMENT_COUNT: int = int(Tuning.LOOK_AHEAD_MAX / SEGMENT_LENGTH) + 6
const ROAD_WIDTH: float = 16.0
const CHUNKS_PER_SECTION: int = 10
const CHUNK_SCRIPT = preload("res://scripts/road_chunk.gd")
const SECTION_NAMES: Array[String] = ["OPEN GRID", "CITY EDGE", "NEON CANOPY"]

var segments: Array[Node3D] = []
var road_material: StandardMaterial3D
var cyan_material: StandardMaterial3D
var pink_material: StandardMaterial3D
var grid_material: StandardMaterial3D
var materials: Dictionary = {}
var _road_phase := 0.0
var _road_cycles := 0


func _ready() -> void:
	road_material = _material(Color("#0d101f"), 0.0)
	# One seamless asphalt texture is shared by the entire recycled highway.
	var noise := FastNoiseLite.new()
	noise.seed = 914
	noise.frequency = 0.18
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color("#131a2a"), Color("#283248")])
	texture.color_ramp = ramp
	road_material.albedo_color = Color.WHITE
	road_material.albedo_texture = texture
	road_material.uv1_scale = Vector3(8, 20, 1)
	road_material.roughness = 0.48
	road_material.metallic = 0.22
	road_material.metallic_specular = 0.3
	cyan_material = _material(Color("#2bdbe9"), 1.4)
	pink_material = _material(Color("#e833a2"), 1.25)
	grid_material = _material(Color("#34243e"), 0.18)
	materials = {
		"road": road_material, "cyan": cyan_material,
		"pink": pink_material, "grid": grid_material,
		"dark": _material(Color("#111326"), 0.0),
		"city": _material(Color("#15162c"), 0.0),
		"amber": _material(Color("#ffab66"), 1.1),
		"windows": _material(Color("#6161ab"), 0.65),
		"marking": _material(Color("#c7b6dd"), 0.25),
		"rail": _material(Color("#34435b"), 0.0),
		"ground": _material(Color("#100d20"), 0.0),
	}
	# The digital landscape stays dark even under the car's cool rim lighting.
	materials.ground.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in range(SEGMENT_COUNT):
		var segment: Node3D = CHUNK_SCRIPT.new()
		segment.name = "RoadSegment%02d" % index
		segment.build(materials)
		add_child(segment)
		segments.append(segment)
	reset_road()


func reset_road() -> void:
	_road_phase = 0.0
	_road_cycles = 0
	for index in range(segments.size()):
		segments[index].position.z = SEGMENT_LENGTH - index * SEGMENT_LENGTH
		segments[index].configure(index - 1, CHUNKS_PER_SECTION)


func advance(distance_delta: float) -> void:
	if distance_delta <= 0.0:
		return
	var ring_length := SEGMENT_COUNT * SEGMENT_LENGTH
	_road_phase += distance_delta
	_road_cycles += floori(_road_phase / ring_length)
	_road_phase = fposmod(_road_phase, ring_length)
	for index in range(segments.size()):
		var segment := segments[index]
		# One double-precision phase avoids independent position drift across the
		# larger road ring, and handles delayed frames without repeated recycling.
		var at_z := SEGMENT_LENGTH - index * SEGMENT_LENGTH + _road_phase
		var cycle := _road_cycles
		if at_z >= SEGMENT_LENGTH + 60.0:
			at_z -= ring_length
			cycle += 1
		segment.position.z = at_z
		var chunk_index := index - 1 + cycle * SEGMENT_COUNT
		if segment.chunk_index != chunk_index:
			segment.configure(chunk_index, CHUNKS_PER_SECTION)


func get_section_name() -> String:
	# A chunk extends back 40 m from its endpoint.
	for segment in segments:
		if segment.position.z >= 0.0 and segment.position.z < SEGMENT_LENGTH:
			return SECTION_NAMES[segment.category]
	return SECTION_NAMES[0]


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.1
	material.roughness = 0.75
	if glow > 0.0:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
