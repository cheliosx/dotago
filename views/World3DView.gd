class_name World3DView
extends View3DCtrl
## 三维战略大地图。
## 交互（与战场统一）：
##   左键点击 / 单指点按   → 查看：英雄 / 城镇 / 矿场 / 营地 / 宝箱 的信息面板；点空白关闭
##   右键点击 / 单指拖动   → 行军：寻路走过去，抵达后自动占领 / 开战
##   双指拖动 / 捏合 / 滚轮 → 平移与缩放

const ELEV := {
	"water": 0.12, "swamp": 0.22, "road": 0.28, "plain": 0.30,
	"forest": 0.38, "hill": 0.55, "mountain": 0.95,
}

# --- 三维节点 ---
var terrain_mi: MeshInstance3D
var overlay_mi: MeshInstance3D
var props_root: Node3D
var obj_root: Node3D
var hero_root: Node3D

# --- UI ---
var topbar: PanelContainer
var hud: HBoxContainer

# --- 数据缓存 ---
var hero_nodes := {}      # id -> Node3D
var hero_rings := {}      # id -> Node3D
var hero_paths := {}      # id -> Array[Vector3]
var hero_labels := {}     # id -> Label3D
var last_sig := ""
var _end_shown := false

# --- 查看目标 / 指令目标 ---
var inspect := {"kind": "", "id": 0}
var hover_cell := Vector2i(-1, -1)
var cmd_cell := Vector2i(-1, -1)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if Game.tiles.is_empty():
		Game.new_game("crystal_maiden")
	build_viewport()
	_build_scene()
	_build_ui()
	build_sheet()
	map_bounds = Hex3D.bounds(Game.COLS, Game.ROWS, HEX_S)
	Game.changed.connect(refresh)
	refresh()
	var h := Game.selected_hero()
	if not h.is_empty():
		center_on(_hero_world(h.pos), false)
	dist = 19.0
	dist_target = 19.0
	_update_camera()
	set_process(true)

# ==================================================================== 场景
func _build_scene() -> void:
	terrain_mi = MeshInstance3D.new()
	terrain_mi.material_override = terrain_material()
	world.add_child(terrain_mi)

	overlay_mi = MeshInstance3D.new()
	overlay_mi.material_override = overlay_material()
	world.add_child(overlay_mi)

	props_root = Node3D.new()
	world.add_child(props_root)
	obj_root = Node3D.new()
	world.add_child(obj_root)
	hero_root = Node3D.new()
	world.add_child(hero_root)

func _tile_color(c: Vector2i, t: String) -> Color:
	var base := Color(DB.TERRAIN[t].color)
	var jitter := (Hex3D.hash01(c, 7) - 0.5) * 0.10
	base = base.lightened(jitter) if jitter > 0.0 else base.darkened(-jitter)
	if not Game.is_explored(c):
		return Color("#0c1119")
	if not Game.is_visible(c):
		return base.lerp(Color("#080b12"), 0.55)
	return base

func build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key in Game.tiles:
		var c: Vector2i = Game.tiles[key].c
		var t: String = Game.terrain(c)
		var top := _tile_color(c, t)
		var side := top.darkened(0.46)
		var h: float = float(ELEV.get(t, 0.30))
		Hex3D.add_prism(st, c, HEX_S, 0.965, -0.45, h, top, side)
	terrain_mi.mesh = st.commit()

func _prop_mesh() -> Mesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.42
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	return cone

func build_props() -> void:
	for ch in props_root.get_children():
		props_root.remove_child(ch)
		ch.queue_free()
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for key in Game.tiles:
		var c: Vector2i = Game.tiles[key].c
		if not Game.is_explored(c):
			continue
		var vis := Game.is_visible(c)
		var t: String = Game.terrain(c)
		var y: float = float(ELEV.get(t, 0.30))
		var dim := 1.0 if vis else 0.55
		match t:
			"forest":
				for i in range(3):
					var off := Hex3D.jitter(c, HEX_S, 11 + i * 17) * 0.72
					var sc := 0.55 + Hex3D.hash01(c, 31 + i) * 0.35
					var p := Hex3D.to_world(c, HEX_S) + Vector3(off.x, y, off.y)
					transforms.append(Transform3D(Basis().scaled(Vector3(sc, sc * (0.9 + 0.4 * Hex3D.hash01(c, 5 + i)), sc)),
						p + Vector3(0, 0.42 * sc, 0)))
					colors.append(Color("#2f5233").lerp(Color("#4d7a45"), Hex3D.hash01(c, 41 + i)) * dim)
			"mountain":
				var off2 := Hex3D.jitter(c, HEX_S, 3) * 0.35
				var p2 := Hex3D.to_world(c, HEX_S) + Vector3(off2.x, y - 0.04, off2.y)
				var sc2 := 0.82 + Hex3D.hash01(c, 9) * 0.3
				transforms.append(Transform3D(Basis().scaled(Vector3(sc2, sc2 * 1.35, sc2)), p2 + Vector3(0, 0.68 * sc2, 0)))
				colors.append(Color("#6f7480") * dim)
			"hill":
				var off3 := Hex3D.jitter(c, HEX_S, 23) * 0.7
				var p3 := Hex3D.to_world(c, HEX_S) + Vector3(off3.x, y - 0.02, off3.y)
				var sc3 := 0.55 + Hex3D.hash01(c, 13) * 0.3
				transforms.append(Transform3D(Basis().scaled(Vector3(sc3, sc3 * 1.1, sc3)), p3 + Vector3(0, 0.34 * sc3, 0)))
				colors.append(Color("#7a6d50") * dim)
			"swamp":
				for i2 in range(2):
					var off4 := Hex3D.jitter(c, HEX_S, 51 + i2 * 7) * 0.8
					var p4 := Hex3D.to_world(c, HEX_S) + Vector3(off4.x, y + 0.02, off4.y)
					var sc4 := 0.28 + Hex3D.hash01(c, 61 + i2) * 0.14
					transforms.append(Transform3D(Basis().scaled(Vector3(sc4, sc4 * 0.55, sc4)), p4 + Vector3(0, 0.14 * sc4, 0)))
					colors.append(Color("#3d4a2e") * dim)
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _prop_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var pmat := StandardMaterial3D.new()
	pmat.vertex_color_use_as_albedo = true
	pmat.roughness = 0.9
	mmi.material_override = pmat
	props_root.add_child(mmi)

# ==================================================================== 高亮层
func build_overlay() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := Game.selected_hero()
	var reach := {}
	if not h.is_empty():
		reach = Game.reachable(h)
	# 可走范围：只铺已探索的格子，边界线只画外沿
	var lit := {}
	for key in reach:
		var c0 := Hex.from_key(key)
		if Game.is_explored(c0):
			lit[key] = true
	for key in lit:
		var c := Hex.from_key(key)
		var y: float = float(ELEV.get(Game.terrain(c), 0.30)) + 0.03
		Hex3D.add_face(st, c, HEX_S, 0.90, y, Color(1.0, 0.84, 0.34, 0.20))
	add_region_edges(st, lit, HEX_S, func(c: Vector2i) -> float:
		return float(ELEV.get(Game.terrain(c), 0.30)) + 0.034,
		Color(1.0, 0.86, 0.40, 0.85), 0.075)
	# 右键 / 拖动时的高亮目标格
	if cmd_cell.x >= 0 and Game.tiles.has(Hex.key(cmd_cell)):
		var yc: float = float(ELEV.get(Game.terrain(cmd_cell), 0.30)) + 0.05
		Hex3D.add_outline(st, cmd_cell, HEX_S, 0.93, yc, Color(1.0, 0.55, 0.25, 0.95), 0.10)
	# 悬停
	if hover_cell.x >= 0 and Game.tiles.has(Hex.key(hover_cell)):
		var yh: float = float(ELEV.get(Game.terrain(hover_cell), 0.30)) + 0.055
		Hex3D.add_outline(st, hover_cell, HEX_S, 0.94, yh, Color(1, 1, 1, 0.85), 0.09)
	overlay_mi.mesh = st.commit()

# ==================================================================== 地图物件
func build_objects() -> void:
	for ch in obj_root.get_children():
		obj_root.remove_child(ch)
		ch.queue_free()
	for o in Game.towns + Game.mines + Game.camps + Game.caches:
		var c: Vector2i = o.pos
		if not Game.is_explored(c):
			continue
		if not Game.is_visible(c) and not _is_mine(o):
			continue
		var node := Node3D.new()
		node.position = Hex3D.to_world(c, HEX_S) + Vector3(0, float(ELEV.get(Game.terrain(c), 0.30)), 0)
		match String(o.kind):
			"town": _deco_town(node, o)
			"mine": _deco_mine(node, o)
			"camp": _deco_camp(node, o)
			"cache": _deco_cache(node, o)
		obj_root.add_child(node)

func _is_mine(o: Dictionary) -> bool:
	if o.kind == "town" or o.kind == "mine":
		return o.owner == Game.faction
	return false

func _deco_town(node: Node3D, o: Dictionary) -> void:
	var col := Color(DB.FACTIONS[o.owner].color)
	add_cyl(node, Vector3(0, 0.03, 0), 0.62, 0.06, col.darkened(0.55), 6)
	add_box(node, Vector3(-0.16, 0.24, 0.05), Vector3(0.52, 0.42, 0.46), Color("#39404e"))
	add_box(node, Vector3(0.20, 0.32, -0.08), Vector3(0.34, 0.58, 0.34), Color("#454d5c"))
	add_box(node, Vector3(0.02, 0.30, 0.24), Vector3(0.26, 0.52, 0.26), Color("#2f3542"))
	add_cone(node, Vector3(0.20, 0.72, -0.08), 0.28, 0.26, col.darkened(0.25), 4)
	add_cone(node, Vector3(-0.16, 0.55, 0.05), 0.36, 0.22, col.darkened(0.35), 4)
	add_cyl(node, Vector3(0.46, 0.62, 0.30), 0.03, 1.2, Color("#c9a227"), 5)
	add_box(node, Vector3(0.62, 1.06, 0.30), Vector3(0.24, 0.16, 0.02), col)
	add_label(node, String(o.name), Vector3(0, 1.72, 0), Color("#f0e7d0"), 42)

func _deco_mine(node: Node3D, o: Dictionary) -> void:
	var col := Color(DB.RES[o.res].color)
	add_cyl(node, Vector3(0, 0.03, 0), 0.46, 0.05, Color("#20242e"), 6)
	add_box(node, Vector3(-0.10, 0.28, 0.02), Vector3(0.30, 0.52, 0.30), col, 0.5)
	add_box(node, Vector3(0.16, 0.18, -0.10), Vector3(0.20, 0.34, 0.20), col.darkened(0.25), -0.4)
	add_box(node, Vector3(-0.38, 0.16, 0.30), Vector3(0.06, 0.36, 0.06), Color("#6b5334"))
	add_box(node, Vector3(0.30, 0.16, 0.34), Vector3(0.06, 0.36, 0.06), Color("#6b5334"))
	add_box(node, Vector3(-0.04, 0.34, 0.32), Vector3(0.74, 0.05, 0.05), Color("#7a6038"))
	add_label(node, String(o.name), Vector3(0, 0.92, 0), col, 34)
	if o.owner == Game.faction or o.owner == Game.enemy_faction:
		var mark := "◆" if o.owner == Game.faction else "▲"
		add_label(node, mark, Vector3(0.42, 0.72, 0), Color(DB.FACTIONS[o.owner].color), 34)

func _deco_camp(node: Node3D, o: Dictionary) -> void:
	add_cone(node, Vector3(0, 0.28, 0), 0.42, 0.56, Color("#5a3630"), 6)
	add_cyl(node, Vector3(0.30, 0.10, 0.24), 0.12, 0.10, Color("#3a2a22"), 6)
	add_label(node, "怪 · " + String(o.name), Vector3(0, 0.86, 0), Color("#e08a72"), 34)

func _deco_cache(node: Node3D, o: Dictionary) -> void:
	add_box(node, Vector3(0, 0.18, 0), Vector3(0.46, 0.36, 0.46), Color("#8a6a34"))
	add_box(node, Vector3(0, 0.18, 0), Vector3(0.50, 0.08, 0.50), Color("#d8b45a"))
	add_label(node, "宝 · " + String(o.name), Vector3(0, 0.72, 0), Color("#e8cd88"), 30)

# ==================================================================== 英雄
func sync_heroes() -> void:
	for h in Game.heroes:
		var id := int(h.id)
		if not h.alive:
			if hero_nodes.has(id):
				hero_nodes[id].visible = false
			continue
		if not hero_nodes.has(id):
			hero_nodes[id] = _make_hero_node(h)
		var node: Node3D = hero_nodes[id]
		node.visible = (not h.is_ai) or Game.is_visible(h.pos)
		if not hero_paths.has(id):
			var target := _hero_world(h.pos)
			if node.position.distance_to(target) < 0.05:
				node.position = target
			else:
				node.position = node.position.lerp(target, 0.35)
		var ring: Node3D = hero_rings[id]
		ring.visible = (id == Game.selected) and not bool(h.is_ai)
		var l: Label3D = hero_labels[id]
		if id == Game.selected and not bool(h.is_ai):
			l.text = "%s  Lv.%d" % [h.name, h.level]
			l.font_size = 40
		else:
			l.text = "Lv.%d" % int(h.level)
			l.font_size = 30
		l.modulate = Color(h.color) if not h.is_ai else Color("#ff9a90")

func _hero_world(c: Vector2i) -> Vector3:
	return Hex3D.to_world(c, HEX_S) + Vector3(0, float(ELEV.get(Game.terrain(c), 0.30)), 0)

func _make_hero_node(h: Dictionary) -> Node3D:
	var id := int(h.id)
	var node := Node3D.new()
	node.position = _hero_world(h.pos)
	node.scale = Vector3(1.25, 1.25, 1.25)
	var col := Color(h.color)
	add_cyl(node, Vector3(0, 0.06, 0), 0.34, 0.10, col.darkened(0.55), 12)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 0.62
	body.mesh = cap
	body.material_override = mat(col.darkened(0.35))
	body.position = Vector3(0, 0.42, 0)
	node.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.13
	sp.height = 0.26
	head.mesh = sp
	head.material_override = mat(col.lightened(0.25))
	head.position = Vector3(0, 0.82, 0)
	node.add_child(head)
	var weapon := add_box(node, Vector3(0.24, 0.52, 0.02), Vector3(0.05, 0.62, 0.05), col.lightened(0.1))
	weapon.rotation.z = -0.22
	var ring := Node3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.36
	torus.outer_radius = 0.46
	torus.rings = 24
	torus.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat(Color("#d8b45a"), true)
	mi.rotation.x = deg_to_rad(90)
	mi.position = Vector3(0, 0.09, 0)
	ring.add_child(mi)
	ring.visible = false
	node.add_child(ring)
	hero_rings[id] = ring
	hero_labels[id] = add_label(node, "%s  Lv.%d" % [h.name, h.level], Vector3(0, 1.18, 0), col, 40)
	hero_root.add_child(node)
	return node

func _process(delta: float) -> void:
	super(delta)
	for id in hero_paths.keys():
		var node: Node3D = hero_nodes.get(id, null)
		if node == null:
			hero_paths.erase(id)
			continue
		var path: Array = hero_paths[id]
		if path.is_empty():
			hero_paths.erase(id)
			continue
		var wp: Vector3 = path[0]
		var to := wp - node.position
		to.y = 0.0
		var step := 5.5 * delta
		if to.length() <= step:
			node.position = Vector3(wp.x, wp.y, wp.z)
			path.pop_front()
			if path.is_empty():
				hero_paths.erase(id)
		else:
			node.position += to.normalized() * step

# ==================================================================== 刷新
func _fog_signature() -> String:
	var s := "%d|%d|%d" % [Game.tiles.size(), Game.explored.size(), Game.visible_cells.size()]
	for h in Game.heroes:
		s += "|%d,%d,%s" % [h.pos.x, h.pos.y, str(h.alive)]
	return s

func refresh() -> void:
	if not is_instance_valid(topbar):
		return
	var sig := _fog_signature()
	if sig != last_sig:
		last_sig = sig
		build_terrain()
		build_props()
	build_overlay()
	build_objects()
	sync_heroes()
	_build_hud()
	if sheet_shown:
		fill_sheet()
		_layout_sheet(false)
	if Game.game_over != "":
		_show_end()

# ==================================================================== UI
func _build_ui() -> void:
	topbar = UI.panel(Color("#141a26"), UI.C_GOLD_DIM, 8)
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topbar.offset_left = 12
	topbar.offset_right = -12
	topbar.offset_top = 10
	topbar.offset_bottom = 72
	topbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(topbar)

	hud = UI.hbox(8)
	topbar.add_child(hud)

	hint = UI.label("点击查看 · 右键 / 按住拖动 行军 · 双指拖动平移", 13, UI.C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.position = Vector2(18, 78)
	add_child(hint)

func _build_hud() -> void:
	for c in hud.get_children():
		hud.remove_child(c)
		c.queue_free()
	var crest := UI.panel(Color("#16394f"), UI.C_BLUE, 6)
	hud.add_child(crest)
	crest.add_child(UI.label("近卫", 16, Color("#bfe6ff")))
	hud.add_child(UI.label("第 %d 天" % Game.day, 18, UI.C_GOLD))
	for k in DB.RES_ORDER:
		var p := UI.panel(Color("#1b2231"), UI.C_GOLD_DIM, 5)
		p.add_child(UI.label("%s %d" % [DB.RES[k].short, int(Game.res.get(k, 0))], 13, Color(DB.RES[k].color)))
		hud.add_child(p)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)
	hud.add_child(UI.ghost_button("－", func(): zoom_by(1.25), 16))
	hud.add_child(UI.ghost_button("＋", func(): zoom_by(0.8), 16))
	hud.add_child(UI.ghost_button("◎", _center_hero, 16))
	hud.add_child(UI.ghost_button("城镇", _open_town, 14))
	hud.add_child(UI.ghost_button("图鉴", func(): Game.goto("codex", {}), 14))
	hud.add_child(UI.ghost_button("英雄", _open_hero_panel, 14))
	hud.add_child(UI.button("结束回合 ▶", _end_turn, 15, Vector2(126, 40), UI.C_GOLD))

func _center_hero() -> void:
	var h := Game.selected_hero()
	if not h.is_empty():
		center_on(_hero_world(h.pos))

func _open_town() -> void:
	for t in Game.towns:
		if t.owner == Game.faction:
			Game.goto("town", {"town_id": int(t.id)})
			return
	Game.say("还没有属于近卫军团的城镇")

func _open_hero_panel() -> void:
	hide_sheet()
	Game.goto("hero", {})

func _open_hero_skills() -> void:
	hide_sheet()
	Game.goto("hero", {"tab": 1})

func _enter_town(town_id: int) -> void:
	hide_sheet()
	Game.goto("town", {"town_id": town_id})

func _end_turn() -> void:
	Game.end_turn()
	if Game.game_over != "":
		_show_end()

func _show_end() -> void:
	if not is_inside_tree() or Game.game_over == "" or _end_shown:
		return
	_end_shown = true
	var win := Game.game_over == "win"
	Game.dialog("战役结束 · " + ("胜利" if win else "失败"),
		("天灾军团已被驱逐，世界之树重新抽出新芽。\n\n用时 %d 个回合。" % Game.day) if win else "近卫军团的旌旗倒下了。\n\n再试一次，也许该更早抢占矿场。",
		func(): Game.goto("title", {}))

# ==================================================================== 查看面板
func fill_sheet() -> void:
	for c in sheet.get_children():
		sheet.remove_child(c)
		c.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	sheet.add_child(margin)
	match String(inspect.kind):
		"hero": _fill_hero(margin)
		"town": _fill_town(margin)
		"mine": _fill_mine(margin)
		"camp": _fill_camp(margin)
		"cache": _fill_cache(margin)
		_: sheet_shown = false

func _fill_hero(root: MarginContainer) -> void:
	var h: Dictionary = Game.hero(int(inspect.id))
	if h.is_empty():
		sheet_shown = false
		return
	var is_enemy: bool = bool(h.is_ai)
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(330, 0)
	row.add_child(left)
	var name_row := UI.hbox(8)
	left.add_child(name_row)
	name_row.add_child(UI.title("%s  Lv.%d" % [h.name, h.level], 24))
	name_row.add_child(UI.chip("敌方英雄" if is_enemy else "我方统帅", UI.C_RED if is_enemy else UI.C_GOLD))
	left.add_child(UI.label("%s · %s · %s" % [h.title, h.klass, h.faction], 13, Color(h.color)))
	var st := Game.hero_stats(h)
	left.add_child(UI.label("攻 %d    防 %d    力 %d    智 %d" % [st.atk, st.def, st.power, st.knowledge], 15, UI.C_TEXT))
	left.add_child(UI.label("移动力  %d / %d" % [int(h.mp), Game.max_mp(h)], 14, UI.C_BLUE))
	left.add_child(UI.bar(float(h.mp), float(Game.max_mp(h)), UI.C_BLUE, 300, 10))
	left.add_child(UI.label("魔法值  %d / %d" % [int(h.mana), Game.max_mana(h)], 14, UI.C_PURPLE))
	left.add_child(UI.bar(float(h.mana), float(Game.max_mana(h)), UI.C_PURPLE, 300, 10))

	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("军 队", 13, UI.C_MUTED))
	var total := 0
	var army_row := HFlowContainer.new()
	army_row.add_theme_constant_override("h_separation", 8)
	army_row.add_theme_constant_override("v_separation", 6)
	mid.add_child(army_row)
	for s in h.army:
		if not DB.UNITS.has(s.unit):
			continue
		var u: Dictionary = DB.UNITS[s.unit]
		total += int(s.count)
		var card := UI.panel(Color(u.color).darkened(0.72), Color(u.color), 5)
		var cv := UI.vbox(1)
		card.add_child(cv)
		cv.add_child(UI.label(u.name, 13, Color(u.color)))
		cv.add_child(UI.label("×%d" % int(s.count), 15, UI.C_TEXT))
		army_row.add_child(card)
	mid.add_child(nowrap("总兵力 %d  ·  战力 %d  ·  经验 %d/%d" % [
		total, Game.army_strength(h.army), int(h.xp), DB.level_xp(int(h.level))], 13, UI.C_MUTED))
	var terrain_name: String = DB.TERRAIN[Game.terrain(h.pos)].name
	var o := Game.ground_at(h.pos)
	var where := "位于 %s" % terrain_name
	if not o.is_empty():
		where += "  ·  %s" % o.ref.name
	mid.add_child(nowrap(where, 13, UI.C_GOLD))

	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(200, 0)
	row.add_child(right)
	if not is_enemy:
		right.add_child(UI.button("英雄面板", _open_hero_panel, 15, Vector2(190, 40)))
		right.add_child(UI.button("技能 / 法术", _open_hero_skills, 15, Vector2(190, 40)))
		var own_town := Game.ground_at(h.pos)
		if not own_town.is_empty() and own_town.kind == "town" and own_town.ref.owner == Game.faction:
			var tid := int(own_town.ref.id)
			right.add_child(UI.button("进入城镇", func(): _enter_town(tid), 15, Vector2(190, 40)))
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

func _fill_town(root: MarginContainer) -> void:
	var t: Dictionary = Game.find_by_id(Game.towns, int(inspect.id))
	if t.is_empty():
		sheet_shown = false
		return
	var fac := String(t.owner)
	var col := Color(DB.FACTIONS[fac].color)
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(380, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title(String(t.name), 24))
	nr.add_child(UI.chip(String(DB.FACTIONS[fac].name), col))
	left.add_child(UI.label("城镇 · 坐标 (%d, %d)" % [t.pos.x, t.pos.y], 13, UI.C_MUTED))
	var guard := 0
	for g in t.garrison:
		guard += int(g.count)
	left.add_child(nowrap("驻军 %s" % ("无" if guard == 0 else "%d 人" % guard), 14, UI.C_TEXT))
	var bld := []
	for k in t.buildings:
		if int(t.buildings[k]) > 0 and DB.BUILDINGS.has(k):
			bld.append("%s Lv.%d" % [DB.BUILDINGS[k].name, int(t.buildings[k])])
	left.add_child(nowrap("建筑 " + ("、".join(bld) if bld.size() > 0 else "—"), 13, UI.C_MUTED))

	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("要 塞", 13, UI.C_MUTED))
	mid.add_child(nowrap("占领后每日提供金币与魔法值回复，也可作为英雄撤退点。" if fac != Game.faction else "这是你的城镇，可以建造、募兵、招募第二英雄。", 13, UI.C_TEXT))
	var h := Game.selected_hero()
	if not h.is_empty():
		var d := Hex.dist(h.pos, t.pos)
		mid.add_child(nowrap("距当前统帅 %d 格%s" % [d, "（相邻，可进入）" if d <= 1 else ""], 13, UI.C_GOLD))

	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(200, 0)
	row.add_child(right)
	if fac == Game.faction:
		var tid := int(t.id)
		var hh := Game.selected_hero()
		var near: bool = not hh.is_empty() and Hex.dist(hh.pos, t.pos) <= 1
		var b := UI.button("进入城镇", func(): _enter_town(tid), 15, Vector2(190, 40))
		b.disabled = not near
		right.add_child(b)
		if not near:
			right.add_child(nowrap("需要英雄走到城镇旁", 11, UI.C_MUTED))
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

func _fill_mine(root: MarginContainer) -> void:
	var m: Dictionary = Game.find_by_id(Game.mines, int(inspect.id))
	if m.is_empty():
		sheet_shown = false
		return
	var rcol := Color(DB.RES[m.res].color)
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(380, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title(String(m.name), 24))
	nr.add_child(UI.chip(String(DB.RES[m.res].name), rcol))
	var owner_txt := "无主"
	if m.owner == Game.faction:
		owner_txt = "我方占领"
	elif m.owner == Game.enemy_faction:
		owner_txt = "天灾占领"
	left.add_child(nowrap("归属 %s · 坐标 (%d, %d)" % [owner_txt, m.pos.x, m.pos.y], 13, UI.C_MUTED))
	var guard := 0
	for g in m.guards:
		guard += int(g.count)
	left.add_child(nowrap("守军 %s" % ("无" if guard == 0 else "%d 人" % guard), 14, UI.C_TEXT))
	left.add_child(nowrap("每日产出 %d %s" % [int(DB.RES[m.res].daily), DB.RES[m.res].name], 14, rcol))

	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("情 报", 13, UI.C_MUTED))
	mid.add_child(nowrap("有守军时需要战斗才能占领；无守军走上去即占领。" if guard > 0 else "无守军，走上去即可占领。", 13, UI.C_TEXT))
	var h := Game.selected_hero()
	if not h.is_empty():
		mid.add_child(nowrap("距当前统帅 %d 格" % Hex.dist(h.pos, m.pos), 13, UI.C_GOLD))
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(200, 0)
	row.add_child(right)
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

func _fill_camp(root: MarginContainer) -> void:
	var cp: Dictionary = Game.find_by_id(Game.camps, int(inspect.id))
	if cp.is_empty():
		sheet_shown = false
		return
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(380, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title(String(cp.name), 24))
	nr.add_child(UI.chip("野怪营地", UI.C_RED))
	left.add_child(UI.label("坐标 (%d, %d)" % [cp.pos.x, cp.pos.y], 13, UI.C_MUTED))
	var guard := 0
	for g in cp.guards:
		guard += int(g.count)
	left.add_child(nowrap("守军 %d 人" % guard, 14, UI.C_TEXT))
	left.add_child(nowrap("战利品 %s" % DB.res_text(cp.reward), 14, UI.C_GOLD))
	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("情 报", 13, UI.C_MUTED))
	for g in cp.guards:
		if DB.UNITS.has(g.unit):
			mid.add_child(nowrap("%s ×%d" % [DB.UNITS[g.unit].name, int(g.count)], 13, UI.C_TEXT))
	var h := Game.selected_hero()
	if not h.is_empty():
		mid.add_child(nowrap("距当前统帅 %d 格 · 右键或按住拖动发起进攻" % Hex.dist(h.pos, cp.pos), 13, UI.C_GOLD))
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(200, 0)
	row.add_child(right)
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

func _fill_cache(root: MarginContainer) -> void:
	var ca: Dictionary = Game.find_by_id(Game.caches, int(inspect.id))
	if ca.is_empty():
		sheet_shown = false
		return
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(380, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title(String(ca.name), 24))
	nr.add_child(UI.chip("宝箱", UI.C_GOLD))
	left.add_child(UI.label("坐标 (%d, %d)" % [ca.pos.x, ca.pos.y], 13, UI.C_MUTED))
	left.add_child(nowrap("内容 %s" % DB.res_text(ca.reward), 14, UI.C_GOLD))
	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("情 报", 13, UI.C_MUTED))
	mid.add_child(nowrap("走过去即可拾取，不触发战斗。", 13, UI.C_TEXT))
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(200, 0)
	row.add_child(right)
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

# ==================================================================== 交互
func cell_at_screen(p: Vector2) -> Vector2i:
	var hit := ground_hit(p, 0.45)
	var cell := Hex3D.from_world(hit, HEX_S)
	if not Game.tiles.has(Hex.key(cell)):
		return Vector2i(-1, -1)
	return cell

## 左键 / 点按 = 查看
func on_tap(pos: Vector2) -> void:
	var cell := cell_at_screen(pos)
	if cell.x < 0:
		hide_sheet()
		return
	inspect_cell(cell)

func inspect_cell(cell: Vector2i) -> void:
	if not Game.tiles.has(Hex.key(cell)):
		hide_sheet()
		return
	for h in Game.heroes:
		if h.alive and h.pos == cell and (not h.is_ai or Game.is_visible(cell)):
			if not h.is_ai:
				Game.selected = int(h.id)
				refresh()
			inspect = {"kind": "hero", "id": int(h.id)}
			show_sheet()
			return
	var o := Game.ground_at(cell)
	if not o.is_empty() and Game.is_explored(cell):
		inspect = {"kind": String(o.kind), "id": int(o.ref.id)}
		show_sheet()
		return
	# 空地 = 空白位置：有面板就关掉
	hide_sheet()

## 右键 / 按住拖动 = 行军
func on_command(pos: Vector2) -> void:
	cmd_cell = Vector2i(-1, -1)
	var cell := cell_at_screen(pos)
	if cell.x < 0:
		return
	move_to_cell(cell)

func move_to_cell(cell: Vector2i) -> bool:
	if Game.game_over != "" or not Game.tiles.has(Hex.key(cell)):
		return false
	var me := Game.selected_hero()
	if me.is_empty():
		return false
	if cell == me.pos:
		inspect_cell(cell)
		return false
	if not Game.is_explored(cell):
		Game.say("那片区域仍被迷雾笼罩")
		return false
	var reach := Game.reachable(me)
	if not reach.has(Hex.key(cell)):
		Game.say("本回合走不到那里：移动力不足或被阻挡")
		return false
	var path := Game.path_to(me, cell)
	var from: Vector2i = me.pos
	if not Game.move_hero(me, cell):
		return false
	hide_sheet()
	_walk(me, from, path, cell)
	refresh()
	return true

func _walk(h: Dictionary, from: Vector2i, path: Array, dest: Vector2i) -> void:
	var id := int(h.id)
	if not hero_nodes.has(id):
		return
	var pts: Array = []
	for c in path:
		pts.append(_hero_world(c))
	if pts.is_empty():
		pts.append(_hero_world(dest))
	hero_paths[id] = pts
	hero_nodes[id].position = _hero_world(from)

func on_command_hover(pos: Vector2) -> void:
	var cell := cell_at_screen(pos)
	if cell != cmd_cell:
		cmd_cell = cell
		build_overlay()
	_update_hint(cell)

func on_command_hover_end() -> void:
	if cmd_cell.x >= 0:
		cmd_cell = Vector2i(-1, -1)
		build_overlay()

func on_hover(pos: Vector2) -> void:
	var cell := cell_at_screen(pos)
	if cell != hover_cell:
		hover_cell = cell
		build_overlay()
		_update_hint(cell)

func _update_hint(cell: Vector2i = Vector2i(-2, -2)) -> void:
	if hint == null:
		return
	if cell == Vector2i(-2, -2):
		cell = hover_cell
	if cell.x < 0 or not Game.tiles.has(Hex.key(cell)):
		hint.text = "点击查看 · 右键 / 按住拖动 行军 · 双指拖动平移"
		return
	if not Game.is_explored(cell):
		hint.text = "迷雾笼罩的未知区域"
		return
	var t := Game.terrain(cell)
	var msg := "%s · 移动消耗 %d" % [DB.TERRAIN[t].name, Game.terrain_cost(cell)]
	var o := Game.ground_at(cell)
	if not o.is_empty():
		msg = "%s  ·  %s" % [o.ref.name, msg]
	var hero := Game.selected_hero()
	if not hero.is_empty():
		var reach := Game.reachable(hero)
		if reach.has(Hex.key(cell)):
			msg += "  ·  行军消耗 %d 移动力" % int(reach[Hex.key(cell)])
	hint.text = msg
