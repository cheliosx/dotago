extends SceneTree
## 生成 world/WorldMap.tscn（主地图）。
## 手写 tscn 容易错，这里用代码搭好场景再 pack 存盘，之后就能在编辑器里当普通场景编辑。

const SIZE := 120.0

var terrain: WorldTerrain

func _initialize() -> void:
	terrain = WorldTerrain.new()
	terrain.map_size = SIZE
	terrain.resolution = 120

	var root := Node3D.new()
	root.name = "WorldMap"

	# ---------------- 环境与光照
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#5b8ec4")
	sky_mat.sky_horizon_color = Color("#cdd9e2")
	sky_mat.ground_horizon_color = Color("#b9b39a")
	sky_mat.ground_bottom_color = Color("#4b5240")
	sky_mat.sun_angle_max = 22.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_light_color = Color("#c3ccd4")
	env.fog_density = 0.006
	env.fog_sky_affect = 0.4
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46, -52, 0)
	sun.light_color = Color("#ffe9c8")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.light_angular_distance = 0.6
	root.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-30, 140, 0)
	fill.light_color = Color("#93b6e0")
	fill.light_energy = 0.35
	root.add_child(fill)

	# ---------------- 地形
	var t := MeshInstance3D.new()
	t.name = "Terrain"
	t.set_script(load("res://world/Terrain.gd"))
	t.map_size = SIZE
	t.resolution = 120
	t.height_scale = 7.5
	t.noise_seed = 20261118
	t.river_width = 6.0
	t.river_depth = 2.4
	root.add_child(t)

	# ---------------- 水面
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE * 2.6, SIZE * 2.6)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	water.mesh = plane
	water.position = Vector3(0, 0.12, 0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.13, 0.28, 0.38, 0.82)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.12
	wmat.metallic = 0.35
	water.material_override = wmat
	root.add_child(water)

	# ---------------- 树（自动散布，避开 POI）
	var trees := MultiMeshInstance3D.new()
	trees.name = "Trees"
	trees.set_script(load("res://world/TreeScatter.gd"))
	trees.terrain_path = NodePath("../Terrain")
	trees.tree_count = 420
	trees.scatter_seed = 7717
	root.add_child(trees)

	# ---------------- 兴趣点
	var pois := Node3D.new()
	pois.name = "Pois"
	root.add_child(pois)

	var spots := [
		# ---------------- 玩家营地（出生点）
		{"name": "BasePlayer", "kind": "base", "title": "近卫营地", "owner": "sentinel",
			"guards": ["militia:14", "archer:6"], "at": Vector2(-36, 8)},
		# ---------------- 四方势力营地（地图外围）
		{"name": "BaseScourge", "kind": "base", "title": "寒骸堡", "owner": "scourge",
			"guards": ["ghoul:22", "skeleton_archer:12"], "at": Vector2(38, 32)},
		{"name": "BaseClaw", "kind": "base", "title": "赤爪营地", "owner": "claw",
			"guards": ["ogre:10", "militia:18"], "at": Vector2(44, -12)},
		{"name": "BaseIron", "kind": "base", "title": "铁誓壁垒", "owner": "iron",
			"guards": ["knight:8", "archer:14"], "at": Vector2(-10, -40)},
		{"name": "BaseAsh", "kind": "base", "title": "灰烬祭坛", "owner": "ash",
			"guards": ["necromancer:8", "ghoul:16"], "at": Vector2(12, 44)},
		# ---------------- 金矿与伐木场
		{"name": "MineGold1", "kind": "mine", "title": "金矿", "resource": "gold",
			"guards": ["kobold:10"], "at": Vector2(-16, 20)},
		{"name": "MineGold2", "kind": "mine", "title": "富金矿", "resource": "gold",
			"guards": ["wolf:8"], "at": Vector2(24, 6)},
		{"name": "Lumber1", "kind": "mine", "title": "伐木场", "resource": "wood",
			"guards": ["kobold:8"], "at": Vector2(-30, -20)},
		{"name": "Lumber2", "kind": "mine", "title": "北岭伐木场", "resource": "wood",
			"guards": ["ogre:5"], "at": Vector2(6, -8)},
		{"name": "MineOre", "kind": "mine", "title": "秘银矿脉", "resource": "ore",
			"guards": ["wolf:9"], "at": Vector2(18, 28)},
		{"name": "MineCrystal", "kind": "mine", "title": "水晶矿洞", "resource": "crystal",
			"guards": ["golem:4"], "at": Vector2(34, 18)},
		# ---------------- 城镇与商店
		{"name": "TownSilver", "kind": "town", "title": "银月城", "owner": "sentinel", "at": Vector2(-24, 2)},
		{"name": "TownScourge", "kind": "town", "title": "霜歌城", "owner": "scourge", "at": Vector2(28, 40)},
		{"name": "Tavern", "kind": "tavern", "title": "血月酒馆", "at": Vector2(-26, -18)},
		{"name": "Smith", "kind": "smith", "title": "铁砧铁匠铺", "at": Vector2(-19, -27)},
		# ---------------- 野怪营地（中立资源点）
		{"name": "CampWolf", "kind": "camp", "title": "腐化狼穴", "guards": ["wolf:10"], "at": Vector2(-3, 31)},
		{"name": "CampOgre", "kind": "camp", "title": "食人魔营地", "guards": ["ogre:6"], "at": Vector2(33, -8)},
		{"name": "CampGolem", "kind": "camp", "title": "远古遗迹", "guards": ["golem:5"], "at": Vector2(14, 8)},
	]
	var avoid: Array[Vector3] = []
	for s in spots:
		var pos := _find_spot(s.at)
		var poi := Node3D.new()
		poi.name = String(s.name)
		poi.set_script(load("res://world/Poi.gd"))
		poi.kind = String(s.kind)
		poi.title = String(s.title)
		poi.resource = String(s.get("resource", "gold"))
		poi.owner_id = String(s.get("owner", ""))
		var g: PackedStringArray = PackedStringArray()
		for x in s.get("guards", []):
			g.append(String(x))
		poi.guards = g
		poi.position = pos
		pois.add_child(poi)
		avoid.append(pos)
	trees.avoid_points = avoid
	trees.avoid_radius = 8.0

	# ---------------- 英雄出生点
	var spawn := Marker3D.new()
	spawn.name = "HeroSpawn"
	spawn.position = _find_spot(Vector2(-34, 3)) + Vector3(0, 0.2, 0)
	root.add_child(spawn)

	_set_owner_recursive(root, root)

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		print("pack 失败: ", err)
		quit(1)
		return
	err = ResourceSaver.save(ps, "res://world/WorldMap.tscn")
	print("保存 WorldMap.tscn: ", err, " 子节点 ", root.get_child_count())
	for s in spots:
		print("  ", s.name, " @ ", _find_spot(s.at))
	quit()

func _set_owner_recursive(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_set_owner_recursive(c, root)

## 全图扫一遍可建点，然后取离期望位置最近的一个
var _candidates: Array[Vector3] = []

func _scan_candidates() -> void:
	if not _candidates.is_empty():
		return
	var half := SIZE * 0.45
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var h := terrain.height_at(x, z)
			if h >= 1.0 and h <= 6.6:
				var slope: float = absf(terrain.height_at(x + 1.6, z) - h) + absf(terrain.height_at(x, z + 1.6) - h)
				if slope < 1.2:
					_candidates.append(Vector3(roundf(x), h - 0.05, roundf(z)))
			z += 2.0
		x += 2.0

var _placed: Array[Vector3] = []

func _find_spot(at: Vector2) -> Vector3:
	_scan_candidates()
	var best := Vector3(at.x, 2.0, at.y)
	var bd := 1e20
	for c in _candidates:
		var d := Vector2(c.x - at.x, c.z - at.y).length()
		if d >= bd:
			continue
		# 和已放好的点至少隔开 11 米，避免全挤在一起
		var too_close := false
		for q in _placed:
			if Vector2(q.x - c.x, q.z - c.z).length() < 11.0:
				too_close = true
				break
		if too_close:
			continue
		bd = d
		best = c
	_placed.append(best)
	return best
