extends RefCounted
## Small cached meshes shared by the hero and pooled traffic. Z-negative is front.

static var _hulls: Dictionary = {}
static var _boxes: Dictionary = {}
static var _cylinders: Dictionary = {}


static func hull(parent: Node3D, node_name: String, stations: Array[Vector4], bevel: float, material: Material) -> MeshInstance3D:
	if not _hulls.has(node_name):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rings: Array[PackedVector3Array] = []
		for station in stations:
			var z := station.x
			var width := station.y
			var bottom := station.z
			var top := station.w
			var chamfer := minf(bevel, (top - bottom) * 0.45)
			rings.append(PackedVector3Array([Vector3(-width + chamfer, bottom, z), Vector3(width - chamfer, bottom, z), Vector3(width, bottom + chamfer, z), Vector3(width, top - chamfer, z), Vector3(width - chamfer, top, z), Vector3(-width + chamfer, top, z), Vector3(-width, top - chamfer, z), Vector3(-width, bottom + chamfer, z)]))
		for index in range(rings.size() - 1):
			for edge in range(8):
				var next := (edge + 1) % 8
				quad(surface, rings[index][edge], rings[index + 1][edge], rings[index + 1][next], rings[index][next])
		for edge in range(8):
			var next := (edge + 1) % 8
			triangle(surface, Vector3(0, (stations[0].z + stations[0].w) * 0.5, stations[0].x), rings[0][edge], rings[0][next])
			triangle(surface, Vector3(0, (stations[-1].z + stations[-1].w) * 0.5, stations[-1].x), rings[-1][next], rings[-1][edge])
		_hulls[node_name] = surface.commit()
	return instance(parent, node_name, _hulls[node_name], Vector3.ZERO, material)


static func canopy(parent: Node3D, node_name: String, base_width: float, roof_width: float, floor_y: float, roof_y: float, z_positions: Vector4, material: Material) -> MeshInstance3D:
	if not _hulls.has(node_name):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fl := Vector3(-base_width, floor_y, z_positions.x)
		var fr := Vector3(base_width, floor_y, z_positions.x)
		var rfl := Vector3(-roof_width, roof_y, z_positions.y)
		var rfr := Vector3(roof_width, roof_y, z_positions.y)
		var rl := Vector3(-base_width, floor_y, z_positions.w)
		var rr := Vector3(base_width, floor_y, z_positions.w)
		var rrl := Vector3(-roof_width, roof_y, z_positions.z)
		var rrr := Vector3(roof_width, roof_y, z_positions.z)
		quad(surface, fl, fr, rfr, rfl)
		quad(surface, fr, rr, rrr, rfr)
		quad(surface, rr, rl, rrl, rrr)
		quad(surface, rl, fl, rfl, rrl)
		quad(surface, rfl, rfr, rrr, rrl)
		_hulls[node_name] = surface.commit()
	return instance(parent, node_name, _hulls[node_name], Vector3.ZERO, material)


static func box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	if not _boxes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_boxes[size] = mesh
	return instance(parent, node_name, _boxes[size], center, material)


static func cylinder(parent: Node3D, node_name: String, center: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var key := Vector2(radius, height)
	if not _cylinders.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 16
		mesh.rings = 1
		_cylinders[key] = mesh
	return instance(parent, node_name, _cylinders[key], center, material)


static func instance(parent: Node3D, node_name: String, mesh: Mesh, center: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = node_name
	part.mesh = mesh
	part.material_override = material
	part.position = center
	parent.add_child(part)
	return part


static func quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	triangle(surface, a, b, c)
	triangle(surface, a, c, d)


static func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Clockwise faces and explicit flat normals keep the facets crisp.
	var normal := (c - a).cross(b - a).normalized()
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)
