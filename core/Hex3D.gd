class_name Hex3D
extends RefCounted
## 六边形地图的三维布局与几何生成。
## 平面坐标 (x, y) 直接映射为世界坐标 (x, z)，因此与 Hex.gd / WorldView 的
## odd-r 偏移坐标、邻居表、距离公式完全一致；三维视图不需要另写一套六边形数学。

const SQRT3 := 1.7320508075688772

## 偏移坐标 → 世界坐标（格子中心，y = 0）
static func to_world(c: Vector2i, s: float) -> Vector3:
	var p := Hex.center(c, s)
	return Vector3(p.x, 0.0, p.y)

## 世界坐标（地面平面 XZ）→ 偏移坐标，越界与否由调用方判断
static func from_world(p: Vector3, s: float) -> Vector2i:
	# 尖顶六边形：pixel → axial
	var q := (SQRT3 / 3.0 * p.x - p.z / 3.0) / s
	var r := (2.0 / 3.0 * p.z) / s
	var fy := -q - r
	var rx := roundi(q)
	var ry := roundi(fy)
	var rz := roundi(r)
	var dx := absf(float(rx) - q)
	var dy := absf(float(ry) - fy)
	var dz := absf(float(rz) - r)
	# cube round：修正偏差最大的那一维
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Hex.axial_to_offset(Vector2i(rx, rz))

## 六个顶点的世界坐标（尖顶朝向，与 Hex.polygon 的角度一致）
static func corners(c: Vector2i, s: float, radius_scale: float = 1.0) -> PackedVector3Array:
	var ctr := to_world(c, s)
	var out := PackedVector3Array()
	for i in range(6):
		var ang := deg_to_rad(float(60 * i - 30))
		out.append(ctr + Vector3(cos(ang), 0.0, sin(ang)) * s * radius_scale)
	return out

## 往 SurfaceTool 里追加一块六棱柱（顶面 + 六个侧面 + 裙边），带顶点色。
## y_base 一般取负值，让相邻格子拼成连续地壳，看起来像一整片地形而不是漂浮的薄片。
static func add_prism(st: SurfaceTool, c: Vector2i, s: float, radius_scale: float,
		y_base: float, y_top: float, top_col: Color, side_col: Color) -> void:
	var pts := corners(c, s, radius_scale)
	var ctr := to_world(c, s)
	var top_ctr := Vector3(ctr.x, y_top, ctr.z)
	for i in range(6):
		var a := pts[i]
		var b := pts[(i + 1) % 6]
		var a_top := Vector3(a.x, y_top, a.z)
		var b_top := Vector3(b.x, y_top, b.z)
		var a_base := Vector3(a.x, y_base, a.z)
		var b_base := Vector3(b.x, y_base, b.z)
		# 顶面
		st.set_color(top_col)
		st.set_normal(Vector3.UP)
		st.add_vertex(top_ctr)
		st.add_vertex(a_top)
		st.add_vertex(b_top)
		# 侧面
		var n := Vector3(a.x + b.x - 2.0 * ctr.x, 0.0, a.z + b.z - 2.0 * ctr.z).normalized()
		st.set_color(side_col)
		st.set_normal(n)
		st.add_vertex(a_base)
		st.add_vertex(a_top)
		st.add_vertex(b_top)
		st.set_color(side_col)
		st.set_normal(n)
		st.add_vertex(a_base)
		st.add_vertex(b_top)
		st.add_vertex(b_base)

## 单条边（i 号边 = 第 i 与 i+1 个顶点之间），用于画“可走范围的边界”
static func add_edge(st: SurfaceTool, c: Vector2i, s: float, radius_scale: float,
		y: float, i: int, col: Color, width: float = 0.08) -> void:
	var pts := corners(c, s, radius_scale)
	var a := pts[i]
	var b := pts[(i + 1) % 6]
	var dir := b - a
	if dir.length() < 0.0001:
		return
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * width * 0.5
	var a0 := Vector3(a.x, y, a.z) - side
	var a1 := Vector3(a.x, y, a.z) + side
	var b0 := Vector3(b.x, y, b.z) - side
	var b1 := Vector3(b.x, y, b.z) + side
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(a0)
	st.add_vertex(b0)
	st.add_vertex(b1)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(a0)
	st.add_vertex(b1)
	st.add_vertex(a1)

## 格子某条边的外法线方向（世界 XZ），用于判断某条边是否落在区域边界上
static func edge_outward(c: Vector2i, s: float, i: int) -> Vector3:
	var pts := corners(c, s)
	var a := pts[i]
	var b := pts[(i + 1) % 6]
	var mid := (a + b) * 0.5
	var ctr := to_world(c, s)
	var out := Vector3(mid.x - ctr.x, 0.0, mid.z - ctr.z)
	if out.length() < 0.0001:
		return Vector3.ZERO
	return out.normalized()

## 平铺的单层六边形面片（用于高亮 / 悬停 / 选中环）
static func add_face(st: SurfaceTool, c: Vector2i, s: float, radius_scale: float,
		y: float, col: Color) -> void:
	var pts := corners(c, s, radius_scale)
	var ctr := to_world(c, s)
	var center := Vector3(ctr.x, y, ctr.z)
	for i in range(6):
		var a := pts[i]
		var b := pts[(i + 1) % 6]
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(center)
		st.add_vertex(Vector3(a.x, y, a.z))
		st.add_vertex(Vector3(b.x, y, b.z))

## 只画六边形描边（悬停框），用细长四边形近似线宽
static func add_outline(st: SurfaceTool, c: Vector2i, s: float, radius_scale: float,
		y: float, col: Color, width: float = 0.06) -> void:
	var pts := corners(c, s, radius_scale)
	var ctr := to_world(c, s)
	var center := Vector3(ctr.x, y, ctr.z)
	for i in range(6):
		var a := pts[i]
		var b := pts[(i + 1) % 6]
		var dir := (b - a)
		var side := Vector3(-dir.z, 0.0, dir.x).normalized() * width * 0.5
		var inner_a := a + (center - a).normalized() * width
		var inner_b := b + (center - b).normalized() * width
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a.x, y, a.z) - side)
		st.add_vertex(Vector3(b.x, y, b.z) - side)
		st.add_vertex(Vector3(inner_b.x, y, inner_b.z) - side)
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a.x, y, a.z) - side)
		st.add_vertex(Vector3(inner_b.x, y, inner_b.z) - side)
		st.add_vertex(Vector3(inner_a.x, y, inner_a.z) - side)
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a.x, y, a.z) + side)
		st.add_vertex(Vector3(inner_b.x, y, inner_b.z) + side)
		st.add_vertex(Vector3(b.x, y, b.z) + side)
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(a.x, y, a.z) + side)
		st.add_vertex(Vector3(inner_a.x, y, inner_a.z) + side)
		st.add_vertex(Vector3(inner_b.x, y, inner_b.z) + side)

## 整张地图在世界里的包围盒（XZ），用于限制镜头平移范围
static func bounds(cols: int, rows: int, s: float) -> Rect2:
	var a := to_world(Vector2i(0, 0), s)
	var b := to_world(Vector2i(cols - 1, rows - 1), s)
	var min_x: float = minf(a.x, b.x) - s * SQRT3 * 0.5
	var max_x: float = maxf(a.x, b.x) + s * SQRT3 * 0.5
	var min_z: float = a.z - s
	var max_z: float = b.z + s
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)

## 格子内某个“相对坐标”的世界位置（摆放道具、随机散布用）
static func jitter(c: Vector2i, s: float, salt: int) -> Vector2:
	var h1 := hash01(c, salt)
	var h2 := hash01(c, salt + 91)
	var ang := h1 * TAU
	var rad := sqrt(h2) * s * 0.55
	return Vector2(cos(ang), sin(ang)) * rad

static func hash01(c: Vector2i, salt: int) -> float:
	var v := sin(float(c.x) * 12.9898 + float(c.y) * 78.233 + float(salt) * 37.719) * 43758.5453
	return absf(v - floor(v))
