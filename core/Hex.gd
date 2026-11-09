class_name Hex
extends RefCounted
## 尖顶六边形 / odd-r 偏移坐标 的通用数学工具（大地图与战场共用）

const SQRT3 := 1.7320508075688772

static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

static func from_key(s: String) -> Vector2i:
	var p := s.split(",")
	return Vector2i(int(p[0]), int(p[1]))

static func offset_to_axial(c: Vector2i) -> Vector2i:
	return Vector2i(c.x - (c.y - (c.y & 1)) / 2, c.y)

static func axial_to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + (a.y - (a.y & 1)) / 2, a.y)

static func dist(a: Vector2i, b: Vector2i) -> int:
	var aa := offset_to_axial(a)
	var bb := offset_to_axial(b)
	var dx := aa.x - bb.x
	var dz := aa.y - bb.y
	var dy := -dx - dz
	return int((absi(dx) + absi(dy) + absi(dz)) / 2)

static func neighbors(c: Vector2i) -> Array:
	# odd-r: 奇数行右移半格
	var even_rows := [[1, 0], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1]]
	var odd_rows := [[1, 0], [1, -1], [0, -1], [-1, 0], [0, 1], [1, 1]]
	var table: Array = odd_rows if (c.y & 1) == 1 else even_rows
	var out := []
	for d in table:
		out.append(Vector2i(c.x + int(d[0]), c.y + int(d[1])))
	return out

static func center(c: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (float(c.x) + 0.5 * float(c.y & 1)), size * 1.5 * float(c.y))

static func polygon(c: Vector2i, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ctr := center(c, size)
	for i in range(6):
		var ang := deg_to_rad(float(60 * i - 30))
		pts.append(ctr + Vector2(cos(ang), sin(ang)) * size)
	return pts

static func board_size(cols: int, rows: int, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (float(cols) + 0.5) + size, size * 1.5 * float(rows - 1) + size * 2.0)

## 从一批候选格中找到离像素点最近的一格（点击命中测试，格数少时足够快）
static func nearest(p: Vector2, size: float, cells: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e20
	for c in cells:
		var d: float = center(c, size).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	if best_d > size * size * 1.35:
		return Vector2i(-1, -1)
	return best

## 从 start 出发的 Dijkstra，返回 {cell_key: cost}，受 max_cost 限制
static func flood(start: Vector2i, max_cost: int, cost_fn: Callable, passable_fn: Callable) -> Dictionary:
	var out := {key(start): 0}
	var frontier := [start]
	while frontier.size() > 0:
		# 简单选最小代价（格数少，无需二叉堆）
		var bi := 0
		for i in range(1, frontier.size()):
			if int(out[key(frontier[i])]) < int(out[key(frontier[bi])]):
				bi = i
		var cur: Vector2i = frontier.pop_at(bi)
		var base := int(out[key(cur)])
		for n in neighbors(cur):
			if not passable_fn.call(n):
				continue
			var step := int(cost_fn.call(n))
			if step >= 99:
				continue
			var nc := base + step
			if nc > max_cost:
				continue
			if not out.has(key(n)) or nc < int(out[key(n)]):
				out[key(n)] = nc
				frontier.append(n)
	return out

## flood 结果的回溯路径（不含起点），parent 由 path_to 构造
static func line_cells(a: Vector2i, b: Vector2i, max_len: int) -> Array:
	# 战场直线法术：沿六边形方向尽量朝目标延伸
	var out := [a]
	var cur := a
	for _i in range(max_len):
		var best := cur
		var bd := dist(cur, b)
		for n in neighbors(cur):
			var d := dist(n, b)
			if d < bd:
				bd = d
				best = n
		if best == cur:
			break
		cur = best
		out.append(cur)
		if cur == b:
			break
	return out
