extends RefCounted
## Traffic model identities are independent of the six existing collision kinds.
## Immutable meshes and paint materials are shared by every pooled instance.

const VehicleMesh = preload("res://scripts/vehicle_mesh.gd")
const Tuning = preload("res://scripts/stage_two_tuning.gd")
enum Model { PULSE, RELAY, SOLAR, TORQUE, VECTOR, ATLAS, NOMAD, HAULER, APEX, EXECUTIVE, MOTO }
const COUNT: int = 11
const NAMES: Array[String] = ["Pulse Coupe", "Relay Van", "Solar GT", "Torque Muscle", "Vector Hatch", "Atlas SUV", "Nomad Wagon", "Hauler Pickup", "Apex Supercar", "Executive Sedan", "Street Moto"]
const COLORS: Array[String] = ["#307db4", "#7541ad", "#b78239", "#a83c46", "#238a91", "#468553", "#d9e0db", "#bd6435", "#9da9bb", "#554071", "#e8419a"]
# CAR=1, VAN=2, WIDE=3 retain their height/length categories.
# Each model has its own visible and physical width; the original three stay unchanged.
const KINDS: Array[int] = [1, 2, 3, 3, 1, 2, 2, 2, 3, 3, 1]
const WIDTHS: Array[float] = [2.0, 2.4, 2.8, 3.1, 1.8, 3.0, 2.3, 3.2, 2.6, 2.7, 0.9]
static var _materials: Dictionary = {}


static func display_name(model: int) -> String:
	return NAMES[clampi(model, 0, COUNT - 1)]


static func kind_for_model(model: int) -> int:
	return KINDS[clampi(model, 0, COUNT - 1)]


static func default_model(kind: int) -> int:
	return clampi(kind - 1, 0, 2)


static func dimensions(model: int) -> Vector3:
	model = clampi(model, 0, COUNT - 1)
	var size: Vector3 = [Vector3(2.0, 1.05, 4.4), Vector3(2.4, 1.9, 5.0), Vector3(2.8, 1.4, 4.8)][kind_for_model(model) - 1]
	size.x = WIDTHS[model]
	if model == Model.MOTO:
		size = Vector3(WIDTHS[model], 1.75, 2.2)
	size.x *= Tuning.TRAFFIC_SCALE
	size.z *= Tuning.TRAFFIC_SCALE
	return size


static func build(model: int) -> Node3D:
	model = clampi(model, 0, COUNT - 1)
	if model == Model.MOTO:
		return _build_moto()
	var visual := Node3D.new()
	visual.name = ["CarVisual", "VanVisual", "WideVisual"][model] if model < 3 else NAMES[model].replace(" ", "") + "Visual"
	visual.set_meta("traffic_model", model)
	var prefix: String = ["TrafficCar", "TrafficVan", "TrafficWide"][model] if model < 3 else "Traffic" + NAMES[model].replace(" ", "")
	var size := dimensions(model)
	var width := size.x
	var detail_scale: float = width / [2.0, 2.4, 2.8][kind_for_model(model) - 1]
	var length := size.z
	var half := width * 0.5
	var tip := length * 0.5
	var body_top: float = [0.77, 0.91, 0.92, 0.89, 0.79, 1.12, 0.91, 0.97, 0.65, 0.93][model]
	var roof_top: float = [1.15, 1.90, 1.47, 1.39, 1.16, 1.92, 1.55, 1.72, 1.05, 1.46][model]
	var paint := _material(COLORS[model], 0.02)
	var dark := _material("#101426", 0.0)
	var rubber := _material("#070a12", 0.0)
	rubber.metallic = 0.0
	rubber.roughness = 0.85
	var metal := _material("#9aafc8", 0.0)
	metal.metallic = 0.85
	var glass := _material("#17394d", 0.04)
	glass.metallic = 0.75
	glass.roughness = 0.17
	var tail := _material("#ff355d", 2.1)
	var white := _material("#d9f9ff", 1.5)
	var cyan := _material("#42bacc", 0.65)
	# Individual station heights/widths make the silhouettes distinct, while
	# every point stays inside that model's physical footprint.
	var nose_width := 0.76
	var rear_width := 0.82
	if model == Model.TORQUE or model == Model.EXECUTIVE:
		nose_width = 0.88
		rear_width = 0.90
	elif model == Model.APEX:
		nose_width = 0.65
		rear_width = 0.92
	elif model == Model.ATLAS or model == Model.HAULER:
		nose_width = 0.87
		rear_width = 0.95
	VehicleMesh.hull(visual, prefix + "Body", [Vector4(-tip + 0.03, half * nose_width, 0.28, body_top * 0.66), Vector4(-tip * 0.72, half * 0.96, 0.26, body_top * 0.87), Vector4(-tip * 0.30, half, 0.26, body_top), Vector4(tip * 0.52, half, 0.26, body_top), Vector4(tip * 0.88, half * 0.97, 0.28, body_top * 0.97), Vector4(tip - 0.04, half * rear_width, 0.31, body_top * 0.87)], 0.10, paint)
	if model == Model.RELAY:
		VehicleMesh.canopy(visual, prefix + "Glass", half * 0.83, half * 0.70, body_top, roof_top, Vector4(-1.92, -1.13, -0.10, 0.55), glass)
		VehicleMesh.hull(visual, prefix + "Cargo", [Vector4(-0.12, half * 0.74, body_top, roof_top), Vector4(1.92, half * 0.88, body_top, roof_top), Vector4(2.34, half * 0.77, body_top, 1.72)], 0.14, paint)
		VehicleMesh.box(visual, "RearWindow", Vector3(0, 1.34, 2.352), Vector3(1.42, 0.43, 0.022), glass)
		VehicleMesh.box(visual, "CargoSeam", Vector3(0, 1.28, 2.37), Vector3(0.026, 0.80, 0.02), dark)
	else:
		var cabin := Vector4(-tip * 0.42, -tip * 0.14, tip * 0.31, tip * 0.67)
		if model == Model.TORQUE:
			cabin = Vector4(-0.60, -0.15, 0.80, 1.25)
		elif model == Model.VECTOR:
			cabin = Vector4(-0.95, -0.45, 1.22, 1.78)
		elif model == Model.ATLAS:
			cabin = Vector4(-1.42, -0.92, 1.25, 1.88)
		elif model == Model.NOMAD:
			cabin = Vector4(-1.28, -0.80, 1.68, 2.05)
		elif model == Model.HAULER:
			cabin = Vector4(-1.60, -1.10, 0.06, 0.26)
		elif model == Model.APEX:
			cabin = Vector4(-1.12, -0.58, 0.50, 1.26)
		elif model == Model.EXECUTIVE:
			cabin = Vector4(-1.14, -0.68, 0.68, 1.16)
		var roof_width := half * 0.62
		if model in [Model.VECTOR, Model.ATLAS, Model.NOMAD, Model.HAULER]:
			roof_width = half * 0.73
		VehicleMesh.canopy(visual, prefix + "Glass", half * 0.80, roof_width, body_top, roof_top, cabin, glass)
		VehicleMesh.hull(visual, prefix + "Roof", [Vector4(cabin.y - 0.015, roof_width + 0.02, roof_top, roof_top + 0.025), Vector4(cabin.z + 0.015, roof_width + 0.02, roof_top, roof_top + 0.025)], 0.008, paint)
		if model in [Model.PULSE, Model.SOLAR, Model.APEX]:
			for vent in range(3):
				VehicleMesh.box(visual, "RearDeckVent", Vector3(0, body_top + 0.012, tip * 0.76 + vent * 0.07), Vector3(width * 0.50, 0.018, 0.025), dark)
	VehicleMesh.box(visual, "RearFascia", Vector3(0, body_top * 0.77, tip - 0.015), Vector3(width * 0.78, 0.16, 0.025), dark)
	if model <= Model.SOLAR:
		VehicleMesh.box(visual, "RearLightBar", Vector3(0, body_top * 0.85, tip + 0.008), Vector3(width * 0.69, 0.045, 0.026), tail)
	VehicleMesh.box(visual, "RearDiffuser", Vector3(0, 0.31, tip - 0.13), Vector3(width * 0.77, 0.15, 0.22), dark)
	VehicleMesh.box(visual, "FrontSplitter", Vector3(0, 0.26, -tip + 0.11), Vector3(width * 0.80, 0.055, 0.20), dark)
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		VehicleMesh.box(visual, "FrontLight", Vector3(side * width * 0.26, body_top * 0.66, -tip + 0.04), Vector3(width * 0.24, 0.035, 0.025), white)
		VehicleMesh.box(visual, "SideBlade", Vector3(side * (half - 0.035), 0.36, 0), Vector3(0.055, 0.14, length * 0.63), dark)
		VehicleMesh.box(visual, "SideAccent", Vector3(side * (half - 0.003), 0.41, 0), Vector3(0.008, 0.024, length * 0.58), cyan)
		match model:
			Model.RELAY, Model.NOMAD:
				VehicleMesh.box(visual, "VerticalTail" + side_name, Vector3(side * width * 0.36, 1.18, tip - 0.10), Vector3(0.075, 0.67 if model == Model.RELAY else 0.45, 0.035), tail)
				VehicleMesh.box(visual, "CargoTrim" if model == Model.RELAY else "WagonRoofRail", Vector3(side * width * 0.445, 1.08 if model == Model.RELAY else roof_top + 0.055, 0.91), Vector3(0.025, 0.07, 1.85), dark)
			Model.SOLAR:
				VehicleMesh.box(visual, "TailHook" + side_name, Vector3(side * width * 0.34, 0.70, tip + 0.008), Vector3(0.055, 0.14, 0.026), tail)
				VehicleMesh.box(visual, "AeroIntake", Vector3(side * width * 0.39, 0.80, 1.04), Vector3(0.11, 0.06, 0.30), dark)
			Model.TORQUE:
				for light in range(3):
					VehicleMesh.box(visual, "TripleTail" + side_name + str(light), Vector3(side * (0.58 + light * 0.19) * detail_scale, 0.78, tip + 0.008), Vector3(0.10 * detail_scale, 0.17, 0.026), tail)
				VehicleMesh.box(visual, "RacingStripe", Vector3(side * 0.29 * detail_scale, body_top + 0.018, -1.33), Vector3(0.17 * detail_scale, 0.022, 0.87), dark)
				VehicleMesh.box(visual, "RoofStripe", Vector3(side * 0.29 * detail_scale, roof_top + 0.035, 0.32), Vector3(0.17 * detail_scale, 0.015, 0.80), dark)
			Model.VECTOR:
				VehicleMesh.box(visual, "LTailUpright" + side_name, Vector3(side * 0.67 * detail_scale, 0.94, tip - 0.07), Vector3(0.07 * detail_scale, 0.25, 0.032), tail)
				VehicleMesh.box(visual, "LTailFoot" + side_name, Vector3(side * 0.52 * detail_scale, 0.82, tip - 0.07), Vector3(0.36 * detail_scale, 0.06, 0.032), tail)
			Model.ATLAS:
				VehicleMesh.box(visual, "SquareTail" + side_name, Vector3(side * 0.74 * detail_scale, 1.14, tip - 0.08), Vector3(0.23 * detail_scale, 0.25, 0.035), tail)
				VehicleMesh.box(visual, "TailCenter" + side_name, Vector3(side * 0.74 * detail_scale, 1.14, tip - 0.055), Vector3(0.12 * detail_scale, 0.13, 0.012), dark)
				VehicleMesh.box(visual, "SUVRoofRail", Vector3(side * 0.66 * detail_scale, roof_top + 0.055, 0.16), Vector3(0.06 * detail_scale, 0.04, 1.86), dark)
			Model.HAULER:
				VehicleMesh.box(visual, "BedSide" + side_name, Vector3(side * 0.92 * detail_scale, 1.12, 1.27), Vector3(0.16 * detail_scale, 0.44, 1.96), paint)
				VehicleMesh.box(visual, "PickupTail" + side_name, Vector3(side * 0.85 * detail_scale, 0.96, tip - 0.065), Vector3(0.16 * detail_scale, 0.26, 0.035), tail)
			Model.APEX:
				for offset in [-0.13, 0.13]:
					var light := VehicleMesh.cylinder(visual, "RoundTail" + side_name + str(offset), Vector3((side * 0.75 + offset) * detail_scale, 0.53, tip + 0.008), 0.075 * detail_scale, 0.026, tail)
					light.rotation.x = PI * 0.5
				VehicleMesh.box(visual, "WingSupport", Vector3(side * 0.70 * detail_scale, 0.88, 1.91), Vector3(0.07 * detail_scale, 0.48, 0.16), dark)
				VehicleMesh.box(visual, "ApexIntake", Vector3(side * 1.09 * detail_scale, 0.55, 0.69), Vector3(0.13 * detail_scale, 0.11, 0.48), dark)
			Model.EXECUTIVE:
				VehicleMesh.box(visual, "RectangularTail" + side_name, Vector3(side * 0.79 * detail_scale, 0.80, tip + 0.008), Vector3(0.48 * detail_scale, 0.12, 0.026), tail)
				VehicleMesh.box(visual, "ChromeTrim", Vector3(side * (half - 0.032), 0.74, 0.10), Vector3(0.026, 0.032, 2.76), metal)
		var radius := 0.40 if model == Model.ATLAS else (0.38 if kind_for_model(model) == 2 else 0.34)
		for axle in [-length * 0.30, length * 0.30]:
			var wheel_name := "Wheel" + ("Left" if side < 0.0 else "Right") + ("Front" if axle < 0.0 else "Rear")
			var wheel := VehicleMesh.cylinder(visual, wheel_name, Vector3(side * (half - 0.12), radius + 0.07, axle), radius, 0.21, rubber)
			wheel.rotation.z = PI * 0.5
			VehicleMesh.cylinder(wheel, "AlloyRim", Vector3(0, -side * 0.108, 0), radius * 0.73, 0.014, metal)
			VehicleMesh.cylinder(wheel, "AeroHub", Vector3(0, -side * 0.118, 0), radius * 0.50, 0.008, dark)
			VehicleMesh.cylinder(wheel, "HubAccent", Vector3(0, -side * 0.126, 0), radius * 0.19, 0.008, cyan)
	if model == Model.VECTOR:
		VehicleMesh.box(visual, "HatchSpoiler", Vector3(0, roof_top + 0.02, 1.45), Vector3(1.38 * detail_scale, 0.08, 0.20), paint)
	elif model == Model.HAULER:
		VehicleMesh.box(visual, "OpenBedFloor", Vector3(0, body_top + 0.022, 1.28), Vector3(1.69 * detail_scale, 0.035, 1.96), dark)
		VehicleMesh.box(visual, "Tailgate", Vector3(0, 1.11, 2.26), Vector3(1.77 * detail_scale, 0.42, 0.13), paint)
	elif model == Model.APEX:
		VehicleMesh.box(visual, "ApexRearWing", Vector3(0, 1.13, 1.91), Vector3(2.30 * detail_scale, 0.085, 0.35), dark)
	elif model == Model.EXECUTIVE:
		VehicleMesh.box(visual, "ChromeRearTrim", Vector3(0, 0.65, tip + 0.008), Vector3(2.0 * detail_scale, 0.025, 0.026), metal)
	return visual


static func _build_moto() -> Node3D:
	# Motorcycle and rider; the rear (tail light) faces +Z toward the player.
	var visual := Node3D.new()
	visual.name = "StreetMotoVisual"
	visual.set_meta("traffic_model", Model.MOTO)
	var tip := dimensions(Model.MOTO).z * 0.5
	var paint := _material(COLORS[Model.MOTO], 0.05)
	var dark := _material("#101426", 0.0)
	var rubber := _material("#070a12", 0.0)
	var jacket := _material("#1b2238", 0.0)
	var skin := _material("#c8906a", 0.0)
	var helmet := _material("#42bacc", 0.65)
	for axle in [-tip + 0.36, tip - 0.36]:
		var wheel := VehicleMesh.cylinder(visual, "MotoWheel", Vector3(0, 0.36, axle), 0.34, 0.16, rubber)
		wheel.rotation.z = PI * 0.5
	VehicleMesh.box(visual, "MotoFrame", Vector3(0, 0.62, 0), Vector3(0.34, 0.36, tip * 1.3), dark)
	VehicleMesh.box(visual, "MotoTank", Vector3(0, 0.88, -0.28), Vector3(0.44, 0.26, 0.62), paint)
	VehicleMesh.box(visual, "MotoFairing", Vector3(0, 0.96, -tip + 0.42), Vector3(0.5, 0.42, 0.3), paint)
	VehicleMesh.box(visual, "MotoSeat", Vector3(0, 0.84, 0.32), Vector3(0.36, 0.1, 0.62), dark)
	VehicleMesh.box(visual, "MotoTail", Vector3(0, 0.8, tip - 0.2), Vector3(0.3, 0.07, 0.04), _material("#ff355d", 2.1))
	VehicleMesh.box(visual, "MotoHeadlight", Vector3(0, 1.0, -tip + 0.26), Vector3(0.22, 0.1, 0.03), _material("#d9f9ff", 1.5))
	# Rider: legs, leaning torso, arms to the bars, helmeted head.
	for side in [-1.0, 1.0]:
		VehicleMesh.box(visual, "RiderLeg", Vector3(side * 0.22, 0.72, 0.12), Vector3(0.14, 0.42, 0.5), jacket)
		var arm := VehicleMesh.box(visual, "RiderArm", Vector3(side * 0.26, 1.22, -0.32), Vector3(0.1, 0.1, 0.55), jacket)
		arm.rotation.x = 0.45
		VehicleMesh.box(visual, "RiderHand", Vector3(side * 0.26, 1.08, -0.6), Vector3(0.1, 0.09, 0.1), skin)
	var torso := VehicleMesh.box(visual, "RiderTorso", Vector3(0, 1.28, 0.12), Vector3(0.48, 0.62, 0.3), jacket)
	torso.rotation.x = -0.5
	VehicleMesh.cylinder(visual, "RiderHelmet", Vector3(0, 1.62, -0.06), 0.16, 0.3, helmet).rotation.x = PI * 0.5
	return visual


static func _material(color: String, glow: float) -> StandardMaterial3D:
	var key := color + "/" + str(glow)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.metallic = 0.6
		material.roughness = 0.31
		if glow > 0.0:
			material.emission_enabled = true
			material.emission = Color(color)
			material.emission_energy_multiplier = glow
		_materials[key] = material
	return _materials[key]
