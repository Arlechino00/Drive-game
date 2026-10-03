class_name VisualWorld
extends Node3D

var environment: Environment
var sun_material: ShaderMaterial
var halo_material: ShaderMaterial
var sky_material: ShaderMaterial
var effects_amount: float = 1.0
var secret_level: bool = false
var backdrop_palette: Array[Dictionary] = []


func _ready() -> void:
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/horizon.gdshader")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9a94bd")
	environment.ambient_light_energy = 0.9
	# Fog-free silhouettes and unshaded accents remain strong in Compatibility.
	environment.fog_enabled = true
	environment.fog_density = 0.0011
	environment.fog_light_color = Color("#21122f")
	environment.fog_sky_affect = 0.0
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.light_color = Color("#f6b7cc")
	light.light_energy = 1.1
	light.rotation_degrees = Vector3(-48, 25, 0)
	add_child(light)
	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color("#79c4ee")
	rim_light.light_energy = 0.6
	rim_light.rotation_degrees = Vector3(-22, -145, 0)
	add_child(rim_light)
	_build_sun()
	_build_mountains()
	_build_skyline()
	set_effects(effects_amount)


func set_effects(amount: float) -> void:
	effects_amount = clampf(amount, 0.0, 1.0)
	if sun_material != null:
		sun_material.set_shader_parameter("effects_amount", effects_amount)
	if halo_material != null:
		halo_material.set_shader_parameter("effects_amount", effects_amount)
	if sky_material != null:
		sky_material.set_shader_parameter("effects_amount", effects_amount)
	for entry in backdrop_palette:
		(entry.material as StandardMaterial3D).emission_energy_multiplier = entry.emission * effects_amount
	if environment != null:
		# Godot 4.6 Compatibility supports a simpler glow implementation.
		environment.glow_enabled = effects_amount > 0.0
		environment.glow_intensity = effects_amount * 0.55
		environment.glow_bloom = effects_amount * 0.035
		environment.glow_hdr_threshold = 0.75
		environment.glow_hdr_scale = 0.4
	# Extra emission changes; hazard luminance stays stable at effects zero.


func set_secret_level(enabled: bool) -> void:
	secret_level = enabled
	var amount := 1.0 if enabled else 0.0
	sun_material.set_shader_parameter("secret_amount", amount)
	sky_material.set_shader_parameter("secret_amount", amount)
	halo_material.set_shader_parameter("secret_amount", amount)
	for entry in backdrop_palette:
		var material: StandardMaterial3D = entry.material
		material.albedo_color = entry.secret if enabled else entry.sunset
		material.emission = material.albedo_color
	environment.ambient_light_color = Color("#819fc9") if enabled else Color("#9a94bd")
	environment.ambient_light_energy = 0.82 if enabled else 0.9
	environment.fog_light_color = Color("#111a35") if enabled else Color("#21122f")


func _build_sun() -> void:
	halo_material = ShaderMaterial.new()
	halo_material.shader = preload("res://shaders/sun_halo.gdshader")
	var halo := MeshInstance3D.new()
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(250, 250)
	halo.mesh = halo_quad
	halo.material_override = halo_material
	halo.position = Vector3(0, 88, -481)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	sun_material = ShaderMaterial.new()
	sun_material.shader = preload("res://shaders/sunset.gdshader")
	var sun := MeshInstance3D.new()
	sun.name = "SlicedSun"
	var disc := QuadMesh.new()
	disc.size = Vector2(154, 154)
	sun.mesh = disc
	sun.material_override = sun_material
	sun.position = Vector3(0, 88, -480)
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)


func _build_mountains() -> void:
	for layer in range(3):
		var material := _backdrop_material(Color.WHITE, Color("#629bff"))
		material.vertex_color_use_as_albedo = true
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var depth: float = [-440.0, -392.0, -320.0][layer]
		var base: Color = [Color("#563b59"), Color("#382d4d"), Color("#20283d")][layer]
		# Distinct profiles and triangular faces separate the three silhouettes.
		# The central valley leaves the highway and sliced sunset unobstructed.
		for peak in range(72):
			var x := -720.0 + peak * 20.0
			var left := Vector3(x, _ridge_height(x, layer), depth)
			var right := Vector3(x + 20, _ridge_height(x + 20, layer), depth)
			var toe := Vector3(x + 7.0, maxf(0.0, minf(left.y, right.y) * 0.32), depth)
			vertices.append_array(PackedVector3Array([Vector3(x, -5, depth), left, toe, left, right, toe, toe, right, Vector3(x + 20, -5, depth), Vector3(x, -5, depth), toe, Vector3(x + 20, -5, depth)]))
			for face_color in [base.darkened(0.08), base.lightened(0.045), base, base.darkened(0.12)]:
				for corner in range(3):
					colors.append(face_color)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mountains := MeshInstance3D.new()
		mountains.name = "MountainRidge%d" % layer
		mountains.mesh = mesh
		mountains.material_override = material
		mountains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mountains)


func _ridge_height(x: float, layer: int) -> float:
	var ridge := 32.0 - layer * 4.0 + sin(x * (0.021 + layer * 0.007) + layer * 1.7) * (16.0 - layer * 2.5) + sin(x * 0.083 + layer) * 6.0
	return maxf(7.0, ridge) * lerpf(0.12, 1.0, smoothstep(30.0, 125.0, absf(x)))


func _build_skyline() -> void:
	var violet := _backdrop_material(Color("#ae78bb"), Color("#7d91d1"), 0.22)
	var cyan := _backdrop_material(Color("#62b4c5"), Color("#66aedb"), 0.28)
	var amber := _backdrop_material(Color("#c4936b"), Color("#6d98cb"), 0.15)
	var window_materials: Array[StandardMaterial3D] = [violet, cyan, amber]
	for layer in range(2):
		var bodies: Array[Transform3D] = []
		var neon: Array[Transform3D] = []
		var windows: Array = [[], [], []]
		var buildings := 40 if layer == 0 else 32
		var per_side := buildings >> 1
		var body_material := _backdrop_material(Color("#29243f") if layer == 0 else Color("#161d32"), Color("#1c2947") if layer == 0 else Color("#111e35"))
		for index in range(buildings):
			var side := -1.0 if index < per_side else 1.0
			var column := index % per_side
			var x := side * (43.0 + column * 13.0 + layer * 4.0)
			var height := 16.0 + float((index * 17 + layer * 9) % 32)
			var z := -366.0 if layer == 0 else -278.0
			z -= (column % 3) * 9.0
			var width := 7.0 + float(column % 4) * 1.4
			var depth := 7.0 + float(column % 3)
			# Landmarks rise at the sides; lower blocks frame the central valley.
			if column == 3 or column == 10:
				height += 16.0
			if column < 2:
				height *= 0.58
			bodies.append(_box_transform(Vector3(x, height * 0.5 - 1.0, z), Vector3(width, height, depth)))
			var stepped := column % 3 != 1
			if stepped:
				bodies.append(_box_transform(Vector3(x, height + 2.0, z), Vector3(width * 0.6, 5.0, depth * 0.72)))
				if column % 3 == 0:
					bodies.append(_box_transform(Vector3(x, height + 5.2, z), Vector3(width * 0.33, 2.5, depth * 0.5)))
			if column % 4 == 0:
				bodies.append(_box_transform(Vector3(x, height + 8.0, z), Vector3(0.22, 12.0, 0.22)))
				neon.append(_box_transform(Vector3(x, height + 14.0, z), Vector3(0.38, 0.32, 0.38)))
			neon.append(_box_transform(Vector3(x, height - 1.0, z + depth * 0.5 + 0.03), Vector3(width * 0.88, 0.18, 0.08)))
			if column % 5 == 3:
				neon.append(_box_transform(Vector3(x + side * width * 0.3, height * 0.62, z + depth * 0.5 + 0.03), Vector3(0.16, height * 0.55, 0.08)))
			for row in range(floori(height / 2.2) - 1):
				for pane in range(4):
					if (row * 7 + pane * 3 + index * 2) % 7 < 3:
						var tone := (index + (pane >> 1)) % 3
						windows[tone].append(_box_transform(Vector3(x + (pane - 1.5) * width * 0.19, 1.6 + row * 2.2, z + depth * 0.5 + 0.03), Vector3(0.56, 0.34, 0.06)))
		_batch_boxes(bodies, body_material, "SkylineBodies%d" % layer)
		_batch_boxes(neon, violet if layer == 0 else cyan, "SkylineAccents%d" % layer)
		for tone in range(3):
			var transforms: Array[Transform3D] = []
			transforms.assign(windows[tone])
			_batch_boxes(transforms, window_materials[tone], "SkylineWindows%dTone%d" % [layer, tone])


func _batch_boxes(transforms: Array[Transform3D], material: Material, batch_name: String) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = batch_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for index in range(transforms.size()):
		batch.set_instance_transform(index, transforms[index])
	instance.multimesh = batch
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("authored_transforms", transforms)
	add_child(instance)


func _box_transform(center: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), center)


func _backdrop_material(sunset: Color, secret: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = sunset
	material.disable_fog = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = emission > 0.0
	material.emission = sunset
	backdrop_palette.append({"material": material, "sunset": sunset, "secret": secret, "emission": emission})
	return material
