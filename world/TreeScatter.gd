@tool
class_name TreeScatter
extends MultiMeshInstance3D
## 在陆地（高度合适、坡度平缓、远离河道与建筑）上成片种树。
## 树 = 圆柱树干 + 两层锥形树冠，三个 MultiMesh 共用同一批实例位置。

@export var terrain_path: NodePath
@export var tree_count := 320
@export var scatter_seed := 7717
@export var avoid_points: Array[Vector3] = []
@export var avoid_radius := 7.0
@export var build_on_ready := true

func _ready() -> void:
	if build_on_ready:
		rebuild()

func _terrain() -> WorldTerrain:
	if terrain_path != NodePath():
		return get_node_or_null(terrain_path) as WorldTerrain
	var p := get_parent()
	while p != null:
		if p is WorldTerrain:
			return p
		p = p.get_parent()
	return null

func rebuild() -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	var spots: Array[Transform3D] = []
	var tries := 0
	var half: float = terrain.map_size * 0.46
	while spots.size() < tree_count and tries < tree_count * 30:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var y: float = terrain.height_at(x, z)
		if y < 0.9 or y > 6.2:
			continue
		var slope: float = absf(terrain.height_at(x + 1.2, z) - y) + absf(terrain.height_at(x, z + 1.2) - y)
		if slope > 1.5:
			continue
		var blocked := false
		for ap in avoid_points:
			if Vector2(ap.x - x, ap.z - z).length() < avoid_radius:
				blocked = true
				break
		if blocked:
			continue
		var s := rng.randf_range(0.75, 1.45)
		spots.append(Transform3D(Basis().scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), Vector3(x, y, z)))

	_build_layer("Trunks", _trunk_mesh(), spots, Color("#4a3a28"), 0.55)
	_build_layer("Crowns", _crown_mesh(), spots, Color("#33502f"), 1.85)
	_build_layer("Tops", _top_mesh(), spots, Color("#3d5c36"), 2.75)

func _build_layer(layer_name: String, m: Mesh, spots: Array[Transform3D], col: Color, y_off: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		mm.set_instance_transform(i, spots[i])
	var node := get_node_or_null(layer_name) as MultiMeshInstance3D
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = layer_name
		add_child(node)
	node.multimesh = mm
	node.position = Vector3(0, y_off, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	node.material_override = mat

func _trunk_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.10
	m.bottom_radius = 0.16
	m.height = 1.1
	m.radial_segments = 6
	return m

func _crown_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.95
	m.height = 1.7
	m.radial_segments = 7
	return m

func _top_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.62
	m.height = 1.3
	m.radial_segments = 7
	return m
