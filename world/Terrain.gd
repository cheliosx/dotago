@tool
class_name WorldTerrain
extends MeshInstance3D
## 连续地形（可在编辑器里实时看到）。
## 高度 = fbm 噪声 - 河道下切，河流沿 x = river_curve(z) 走，水面用独立平面。
## 顶点色按高度/坡度混合：河滩沙地 → 草地 → 林地 → 岩石。
## 同时生成碰撞体，供鼠标拾取与（以后的）物理使用。

@export var map_size := 120.0
@export var resolution := 120
@export var height_scale := 7.0
@export var noise_seed := 20261118
@export var river_width := 6.0
@export var river_depth := 2.2
@export var build_on_ready := true

var _noise := FastNoiseLite.new()

func _ready() -> void:
	if build_on_ready:
		rebuild()

func river_center_x(z: float) -> float:
	return 12.0 * sin(z * 0.045) + 6.0 * sin(z * 0.013 + 1.7)

func height_at(x: float, z: float) -> float:
	_noise.seed = noise_seed
	_noise.frequency = 0.012
	_noise.fractal_octaves = 4
	# 基础抬升：让大部分陆地在水平面之上，只留下河谷与湖泊
	var h := 4.2 + _noise.get_noise_2d(x, z) * height_scale
	h += _noise.get_noise_2d(x * 2.7, z * 2.7) * height_scale * 0.18
	# 外圈压低，形成海岸感
	var r := maxf(absf(x), absf(z)) / (map_size * 0.5)
	if r > 0.78:
		h -= (r - 0.78) * 26.0
	# 河道下切
	var dx := absf(x - river_center_x(z))
	if dx < river_width * 2.2:
		var k: float = clampf(1.0 - dx / (river_width * 2.2), 0.0, 1.0)
		h -= pow(k, 1.4) * (river_depth + 1.2)
	return h

func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < 0.15

func rebuild() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(8, resolution)
	var step := map_size / float(n)
	var half := map_size * 0.5
	var heights := []
	heights.resize((n + 1) * (n + 1))
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -half + float(ix) * step
			var z := -half + float(iz) * step
			heights[iz * (n + 1) + ix] = height_at(x, z)

	for iz in range(n):
		for ix in range(n):
			var x0 := -half + float(ix) * step
			var z0 := -half + float(iz) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var h00: float = heights[iz * (n + 1) + ix]
			var h10: float = heights[iz * (n + 1) + ix + 1]
			var h01: float = heights[(iz + 1) * (n + 1) + ix]
			var h11: float = heights[(iz + 1) * (n + 1) + ix + 1]
			_tri(st, Vector3(x0, h00, z0), Vector3(x0, h01, z1), Vector3(x1, h11, z1))
			_tri(st, Vector3(x0, h00, z0), Vector3(x1, h11, z1), Vector3(x1, h10, z0))
	mesh = st.commit()
	if material_override == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# 碰撞：用同一批三角面
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(mesh.get_faces())
	var body := get_node_or_null("Body") as StaticBody3D
	if body == null and is_inside_tree():
		body = StaticBody3D.new()
		body.name = "Body"
		add_child(body)
	if body != null:
		var cs := body.get_node_or_null("Shape") as CollisionShape3D
		if cs == null:
			cs = CollisionShape3D.new()
			cs.name = "Shape"
			body.add_child(cs)
		cs.shape = shape

func _color_for(h: float) -> Color:
	# 高度分层：湿地 → 沙滩 → 草地 → 林地 → 岩坡 → 山顶
	if h < 0.25:
		return Color("#6d6552")
	if h < 1.05:
		return Color("#9c8f6b").lerp(Color("#6f8a4c"), (h - 0.25) / 0.8)
	if h < 2.2:
		return Color("#6f8a4c").lerp(Color("#5d7a42"), (h - 1.05) / 1.15)
	if h < 5.0:
		return Color("#5d7a42").lerp(Color("#4a6234"), (h - 2.2) / 2.8)
	if h < 6.6:
		return Color("#4a6234").lerp(Color("#6f6f66"), (h - 5.0) / 1.6)
	return Color("#7d7e78").lerp(Color("#9c9e98"), clampf((h - 6.6) / 3.0, 0.0, 1.0))

## 位置哈希，用来给顶点色加一点点噪声，避免大片纯色块
func _jitter(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return (v - floor(v)) * 0.07 - 0.035

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	var col := _color_for((a.y + b.y + c.y) / 3.0)
	# 陡坡刷成岩石色
	if absf(nrm.y) < 0.72:
		col = col.lerp(Color("#77756c"), 0.55)
	# 顶点色走线性空间，否则 sRGB 值直接当线性用会整片过曝
	col = Color(col.r * (1.0 + _jitter(a.x, a.z)), col.g * (1.0 + _jitter(a.x, a.z)), col.b * (1.0 + _jitter(a.x, a.z)))
	col = col.srgb_to_linear()
	st.set_color(col)
	st.set_normal(nrm)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(nrm)
	st.add_vertex(c)
	st.set_color(col)
	st.set_normal(nrm)
	st.add_vertex(b)
