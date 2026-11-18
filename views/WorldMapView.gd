class_name WorldMapView
extends View3DCtrl
## 连续地形主地图（魔兽争霸 / 魔兽世界式）。
## · 地形、河流、树林、光照与所有兴趣点都在可编辑场景 world/WorldMap.tscn 里，
##   酒馆 / 铁匠铺 / 矿场 / 野怪营地都是预制品实例，拖一下就换位置。
## · 交互：**点一下 = 查看 / 走去**，**拖动 = 平移镜头**（左右键、单指双指都一样），
##   没有右键指令。英雄走到目标附近后自动判定事件，弹出「占领 / 攻击 / 进入」菜单。

const MAP_SCENE := "res://world/WorldMap.tscn"
const WALK_SPEED := 9.0
const CELL := 1.5
const INTERACT_RANGE := 9.0

var map_root: Node3D
var terrain: WorldTerrain
const NAV_N := 80
var nav_solid := PackedByteArray()
var nav_off := Vector2i(-40, -40)
var pois: Array = []
var hero_nodes := {}
var hero_paths := {}
var hero_tween_ids := {}
var inspect_poi: WorldPoi = null
var inspect_hero := -1
var topbar: PanelContainer
var hud: HBoxContainer
var menu_layer: Control = null
var event_layer: Control = null
var pending_poi: WorldPoi = null   # 点了哪个地点，走到后弹它的事件
var _last_tap_poi: WorldPoi = null
var _last_tap_ms := 0
var _end_shown := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 主地图的手势：拖动只平移镜头，右键不下指令
	drag_commands = false
	right_click_commands = false
	if Game.towns.is_empty() or not Game.use_map_world:
		# 直接从场景运行本视图时的兜底
		if Game.heroes.is_empty():
			Game.new_game("crystal_maiden")
	build_viewport()
	_load_map()
	_build_ui()
	build_sheet()
	_build_nav()
	_spawn_heroes()
	map_bounds = Rect2(-terrain.map_size * 0.5, -terrain.map_size * 0.5, terrain.map_size, terrain.map_size)
	pitch = deg_to_rad(52.0)
	cam_max = 88.0     # 能拉到看全图
	dist = 46.0
	dist_target = 46.0
	var h := Game.selected_hero()
	if not h.is_empty():
		center_on(_hero_wpos(h), false)
	_update_camera()
	Game.map_terrain = terrain
	Game.changed.connect(refresh)
	Game.defense_prompt.connect(_on_defense_prompt)
	refresh()
	# 读档 / 切回地图时如果还有没处理完的告急，立刻补弹
	if not Game.pending_defenses.is_empty():
		_on_defense_prompt.call_deferred()

func _load_map() -> void:
	var ps: PackedScene = load(MAP_SCENE)
	map_root = ps.instantiate()
	world.add_child(map_root)
	terrain = map_root.get_node_or_null("Terrain") as WorldTerrain
	for n in map_root.get_node_or_null("Pois").get_children():
		if n is WorldPoi:
			pois.append(n)

func _hero_wpos(h: Dictionary) -> Vector3:
	var w: Vector3 = h.get("wpos", Vector3.ZERO)
	if w == Vector3.ZERO:
		w = Game.map_spawn
	if terrain != null:
		w.y = terrain.height_at(w.x, w.z)
	return w

# ==================================================================== 寻路
## 自己写 BFS：网格 80×80、每格 1.5 米，水里/陡坡/建筑内不可走。
## （AStarGrid2D 在这个项目里出现过「两端都可走却返回空路径」的情况，换成自己算更可控）
func _build_nav() -> void:
	nav_solid.resize(NAV_N * NAV_N)
	nav_solid.fill(0)
	for gy in range(NAV_N):
		for gx in range(NAV_N):
			var wx := float(gx + nav_off.x) * CELL
			var wz := float(gy + nav_off.y) * CELL
			var blocked := false
			if absf(wx) > terrain.map_size * 0.44 or absf(wz) > terrain.map_size * 0.44:
				blocked = true
			else:
				var h := terrain.height_at(wx, wz)
				if h < 0.4:
					blocked = true
				else:
					var slope: float = absf(terrain.height_at(wx + 1.2, wz) - h) + absf(terrain.height_at(wx, wz + 1.2) - h)
					if slope > 2.2:
						blocked = true
			if blocked:
				nav_solid[gy * NAV_N + gx] = 1
	# 建筑周围不可通行
	for p in pois:
		var b := _cell_of(p.global_position)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := b + Vector2i(dx, dy)
				if _in_nav(c):
					nav_solid[c.y * NAV_N + c.x] = 1
	# 英雄脚下必须可走
	for h in Game.heroes:
		if bool(h.is_ai):
			continue
		var c2 := _cell_of(_hero_wpos(h))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c3 := c2 + Vector2i(dx, dy)
				if _in_nav(c3):
					nav_solid[c3.y * NAV_N + c3.x] = 0

func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.z / CELL)) - nav_off

func _in_nav(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < NAV_N and c.y < NAV_N

func _walkable(c: Vector2i) -> bool:
	return _in_nav(c) and nav_solid[c.y * NAV_N + c.x] == 0

func _world_of_cell(c: Vector2i) -> Vector3:
	var wx := float(c.x + nav_off.x) * CELL
	var wz := float(c.y + nav_off.y) * CELL
	return Vector3(wx, terrain.height_at(wx, wz), wz)

func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if _walkable(cell):
		return cell
	var best := Vector2i(-999, -999)
	var bd := 9999.0
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var c := cell + Vector2i(dx, dy)
			if not _walkable(c):
				continue
			var d := Vector2(dx, dy).length()
			if d < bd:
				bd = d
				best = c
	return best

func _bfs(from: Vector2i, to: Vector2i) -> Array:
	if not _walkable(from) or not _walkable(to):
		return []
	var prev := {}
	var seen := {}
	var queue := [from]
	seen[from] = true
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var guard := 0
	while not queue.is_empty() and guard < NAV_N * NAV_N:
		guard += 1
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			break
		for d in dirs:
			var n: Vector2i = cur + d
			if seen.has(n) or not _walkable(n):
				continue
			# 斜走不允许穿墙角
			if d.x != 0 and d.y != 0:
				if not _walkable(Vector2i(cur.x + d.x, cur.y)) or not _walkable(Vector2i(cur.x, cur.y + d.y)):
					continue
			seen[n] = true
			prev[n] = cur
			queue.append(n)
	if not seen.has(to):
		return []
	var path: Array = []
	var c := to
	var limit := 0
	while c != from and limit < NAV_N * NAV_N:
		limit += 1
		path.push_front(c)
		c = prev[c]
	return path

func _path_to(target: Vector3) -> Array:
	var hero_pos := _hero_wpos(Game.selected_hero())
	var from := _cell_of(hero_pos)
	var to := _nearest_walkable(_cell_of(target))
	var cells: Array = []
	if to != Vector2i(-999, -999):
		cells = _bfs(from, to)
	# 走不到就逐步缩短目标，至少走到能到的地方
	var shrink := 0.75
	while cells.is_empty() and shrink > 0.15:
		var mid := hero_pos.lerp(target, shrink)
		var mid_cell := _nearest_walkable(_cell_of(mid))
		if mid_cell != Vector2i(-999, -999):
			cells = _bfs(from, mid_cell)
		shrink -= 0.2
	var out: Array = []
	for c in cells:
		out.append(_world_of_cell(c))
	return out

# ==================================================================== 英雄
func _spawn_heroes() -> void:
	for h in Game.heroes:
		if not bool(h.alive):
			continue
		var node := _make_hero(h)
		hero_nodes[int(h.id)] = node

func _make_hero(h: Dictionary) -> Node3D:
	var node := Node3D.new()
	var col := Color(h.color)
	var pos := _hero_wpos(h)
	node.position = pos
	# 底座 + 身体 + 头 + 武器（与战场同一套造型语言）
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.45
	cm.height = 0.12
	cm.radial_segments = 14
	base.mesh = cm
	var fac_col := Game.faction_color(String(h.faction))
	base.material_override = mat(fac_col.darkened(0.45))
	base.position = Vector3(0, 0.06, 0)
	node.add_child(base)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 0.95
	body.mesh = cap
	body.material_override = mat(col.darkened(0.3))
	body.position = Vector3(0, 0.62, 0)
	node.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.18
	sp.height = 0.36
	head.mesh = sp
	head.material_override = mat(col.lightened(0.3))
	head.position = Vector3(0, 1.2, 0)
	node.add_child(head)
	var sword := add_box(node, Vector3(0.34, 0.75, 0.05), Vector3(0.07, 0.9, 0.07), col.lightened(0.15))
	sword.rotation.z = -0.2
	# 常驻阵营环：站在地图上一眼就能分清敌我（玩家蓝、敌方各自的势力色）
	var fac_ring := Node3D.new()
	var ft := TorusMesh.new()
	ft.inner_radius = 0.62
	ft.outer_radius = 0.74
	ft.rings = 24
	ft.ring_segments = 6
	var fmi := MeshInstance3D.new()
	fmi.mesh = ft
	fmi.material_override = mat(fac_col, true)
	fmi.rotation.x = deg_to_rad(90)
	fmi.position = Vector3(0, 0.07, 0)
	fac_ring.add_child(fmi)
	node.add_child(fac_ring)

	var ring := Node3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.62
	torus.rings = 24
	torus.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat(Color("#d8b45a"), true)
	mi.rotation.x = deg_to_rad(90)
	mi.position = Vector3(0, 0.1, 0)
	ring.add_child(mi)
	ring.visible = int(h.id) == Game.selected
	ring.name = "Ring"
	node.add_child(ring)
	var name_col := Color("#d8efff") if String(h.faction) == Game.faction else Color("#ff6b57")
	add_label(node, "%s  Lv.%d" % [h.name, h.level], Vector3(0, 2.05, 0), name_col, 72, true, true)
	map_root.add_child(node)
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
		var step := WALK_SPEED * delta
		var hh := Game.hero(int(id))
		if to.length() <= step:
			node.position = Vector3(wp.x, wp.y, wp.z)
			path.pop_front()
			if not hh.is_empty():
				hh.wpos = node.position
			if path.is_empty():
				hero_paths.erase(id)
				_on_hero_arrived(int(id))
		else:
			node.position += to.normalized() * step
			node.position.y = terrain.height_at(node.position.x, node.position.z)
			if not hh.is_empty():
				hh.wpos = node.position
			if to.length() > 0.01:
				var target_yaw := atan2(to.x, to.z)
				node.rotation.y = lerp_angle(node.rotation.y, target_yaw, minf(1.0, delta * 8.0))
	# AI 英雄：回合结算时坐标被直接改掉，这里平滑滑过去，避免瞬移
	for id in hero_nodes.keys():
		if hero_paths.has(id):
			continue
		var hh2 := Game.hero(int(id))
		if hh2.is_empty() or not bool(hh2.alive) or not bool(hh2.is_ai):
			continue
		var nd: Node3D = hero_nodes[id]
		var tw := _hero_wpos(hh2)
		if nd.position.distance_to(tw) > 0.08:
			nd.position = nd.position.lerp(tw, minf(1.0, delta * 4.0))
			var tdir := tw - nd.position
			if Vector2(tdir.x, tdir.z).length() > 0.1:
				nd.rotation.y = lerp_angle(nd.rotation.y, atan2(tdir.x, tdir.z), minf(1.0, delta * 6.0))
	# 选中光环常亮
	for id in hero_nodes.keys():
		var ring := (hero_nodes[id] as Node3D).get_node_or_null("Ring")
		if ring != null:
			(ring as Node3D).visible = int(id) == Game.selected
	# 拉远时把地名/人名在世界上放大，保证屏幕上字号稳定
	_update_label_scale()
	# 目标点标记：呼吸缩放，走到就消失
	if is_instance_valid(move_marker):
		var s := 1.0 + 0.18 * sin(float(Time.get_ticks_msec()) * 0.006)
		move_marker.scale = Vector3(s, 1.0, s)
		if hero_paths.is_empty():
			_clear_marker()

## 相机越远，Label3D 的世界尺寸越大（屏幕上字号基本不变）
var _label_dist := -1.0

func _update_label_scale() -> void:
	if absf(dist - _label_dist) < 0.5:
		return
	_label_dist = dist
	var k := clampf(dist / 46.0, 0.85, 1.35)
	for l in _all_world_labels():
		if not l.has_meta("px0"):
			l.set_meta("px0", l.pixel_size)
		l.pixel_size = float(l.get_meta("px0")) * k

func _all_world_labels() -> Array:
	var out: Array = []
	for poi in pois:
		if poi == null or not is_instance_valid(poi):
			continue
		for n in poi.find_children("*", "Label3D", true, false):
			out.append(n)
	for id in hero_nodes.keys():
		var node: Node3D = hero_nodes[id]
		if not is_instance_valid(node):
			continue
		for n2 in node.find_children("*", "Label3D", true, false):
			out.append(n2)
	return out

func _move_hero_to(target: Vector3, keep_sheet: bool = false, poi: WorldPoi = null) -> void:
	var h := Game.selected_hero()
	if h.is_empty():
		return
	var id := int(h.id)
	var path := _path_to(target)
	if path.is_empty():
		Game.say("那边过不去")
		pending_poi = null
		_clear_marker()
		return
	hero_paths[id] = path
	pending_poi = poi
	_spawn_marker(path[path.size() - 1])
	if not keep_sheet:
		hide_sheet()

# ==================================================================== 到达事件
## 走到目的地后判定附近有没有可交互的东西，有就弹菜单
func _on_hero_arrived(id: int) -> void:
	_clear_marker()
	if id != Game.selected:
		return
	var h := Game.hero(id)
	if h.is_empty():
		return
	var poi := pending_poi
	pending_poi = null
	if poi != null and not is_instance_valid(poi):
		poi = null
	var hp := _hero_wpos(h)
	if poi == null:
		poi = _poi_near(hp, 6.5)
	if poi == null:
		refresh()
		return
	hide_sheet()
	_close_event()   # 到达事件优先于之前可能还开着的菜单
	_ask_poi(poi)

func _poi_near(p: Vector3, radius: float) -> WorldPoi:
	var best: WorldPoi = null
	var bd := radius
	for q in pois:
		var poi := q as WorldPoi
		if poi == null or not is_instance_valid(poi):
			continue
		var d := Vector2(poi.global_position.x - p.x, poi.global_position.z - p.z).length()
		if d < bd:
			bd = d
			best = poi
	return best

## 到达后的事件菜单：金矿问是否占领 / 野怪问是否开打 / 城镇问是否进入
func _ask_poi(poi: WorldPoi) -> void:
	var ref := _poi_ref(poi)
	match poi.kind:
		"mine":
			var guards: Array = ref.get("guards", []).duplicate()
			for gg in ref.get("garrison", []):
				guards.append(gg)
			var own := _poi_owner(poi)
			var res_name := String(DB.RES.get(poi.resource, DB.RES["gold"]).name)
			var daily := int(DB.RES.get(poi.resource, DB.RES["gold"]).daily)
			if own == Game.faction:
				_event_popup("矿场 · " + poi.display_name(),
					"这处%s已经在你的掌控之下，每日为你产出 %d %s。" % [res_name, daily, res_name],
					"知道了", UI.C_GOLD, Callable(), "关闭")
				return
			if guards.is_empty():
				_event_popup("发现矿场 · " + poi.display_name(),
					"无主的%s，没有守军。\n占领后每天产出 %d %s。" % [res_name, daily, res_name],
					"占 领", UI.C_GOLD, func(): _capture_poi(poi))
			else:
				_event_popup("发现守军 · " + poi.display_name(),
					"守军：%s\n击溃守军即可占领，每日产出 %d %s。" % [_guards_text(guards), daily, res_name],
					"发起战斗", UI.C_RED, func(): _attack_poi(poi))
		"camp":
			var guards2: Array = ref.get("guards", [])
			if guards2.is_empty():
				_event_popup("营地 · " + poi.display_name(), "这里已经没有敌人了。",
					"知道了", UI.C_MUTED, Callable(), "关闭")
				return
			_event_popup("野怪 · " + poi.display_name(),
				"守军：%s\n击败后可获得金币与装备。" % _guards_text(guards2),
				"攻击怪物", UI.C_RED, func(): _attack_poi(poi))
		"town":
			var town_owner := String(ref.get("owner", ""))
			var town_gar: Array = ref.get("garrison", [])
			if town_owner == Game.faction:
				_event_popup("城镇 · " + poi.display_name(),
					"你的城镇。可以进入管理建筑、募兵、招募英雄。",
					"进入城镇", UI.C_GOLD, func():
						var t := _poi_ref(poi)
						if not t.is_empty():
							Game.goto("town", {"town_id": int(t.id)}))
			elif town_gar.is_empty():
				_event_popup("空城 · " + poi.display_name(),
					"%s 的城镇，守备空虚。
可以直接占领。" % Game.faction_name(town_owner),
					"占 领", UI.C_GOLD, func(): _capture_poi(poi))
			else:
				_event_popup("敌方城镇 · " + poi.display_name(),
					"%s 占据着这里。\n守军：%s" % [Game.faction_name(town_owner), _guards_text(town_gar)],
					"攻 城", UI.C_RED, func(): _attack_poi(poi))
		"base":
			var base_owner := String(ref.get("owner", ""))
			var base_gar: Array = ref.get("garrison", [])
			if base_owner == Game.faction:
				_event_popup("营地 · " + poi.display_name(),
					"你的营地。可以招募英雄与士兵，也能派驻军队防守。",
					"进入营地", UI.C_GOLD, func(): _open_poi_sheet(poi))
			elif base_gar.is_empty():
				_event_popup("发现营地 · " + poi.display_name(),
					"%s 的营地，守备空虚。\n占领它，对方就只剩流窜的英雄。" % Game.faction_name(base_owner),
					"占 领", UI.C_GOLD, func(): _capture_poi(poi))
			else:
				_event_popup("敌对营地 · " + poi.display_name(),
					"%s 的营地。\n守军：%s\n攻破它，这方势力便失去根基。" % [Game.faction_name(base_owner), _guards_text(base_gar)],
					"攻 打", UI.C_RED, func(): _attack_poi(poi))
		"tavern":
			_event_popup("酒馆 · " + poi.display_name(),
				"在这里花 2500 金币与 8 木材可以招募一位新英雄，招募后他会出现在门前。",
				"进入酒馆", Color("#ffb066"), func(): _open_poi_sheet(poi))
		"smith":
			_event_popup("铁匠铺 · " + poi.display_name(),
				"买卖装备：买入按标价，卖出按半价回收。",
				"进入铁匠铺", Color("#c9d2dd"), func(): _open_poi_sheet(poi))

func _open_poi_sheet(poi: WorldPoi) -> void:
	inspect_poi = poi
	inspect_hero = -1
	show_sheet()

# ==================================================================== 事件弹窗
func _event_popup(title: String, body: String, ok_text: String, ok_col: Color,
		on_ok: Callable, cancel_text: String = "稍后再说", on_cancel: Callable = Callable(),
		dismissable: bool = true) -> void:
	if is_instance_valid(event_layer):
		return
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.58)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点弹窗外的暗色区域也能关掉（和面板的习惯一致）
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if not dismissable:
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_event()
			if on_cancel.is_valid():
				on_cancel.call())
	add_child(shade)
	event_layer = shade
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(cc)
	var card := UI.panel(Color("#1c2231"), ok_col, 12)
	card.custom_minimum_size = Vector2(520, 0)
	cc.add_child(card)
	var pad := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(k, 22)
	card.add_child(pad)
	var v := UI.vbox(12)
	pad.add_child(v)
	v.add_child(UI.title(title, 24))
	v.add_child(UI.line(UI.C_GOLD_DIM))
	var body_l := UI.label(body, 15, UI.C_TEXT)
	body_l.custom_minimum_size = Vector2(470, 0)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body_l)
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UI.button(ok_text, func():
		_close_event()
		if on_ok.is_valid():
			on_ok.call(), 16, Vector2(150, 42), ok_col))
	row.add_child(UI.ghost_button(cancel_text, func():
		_close_event()
		if on_cancel.is_valid():
			on_cancel.call(), 15))

func _close_event() -> void:
	if is_instance_valid(event_layer):
		event_layer.queue_free()
	event_layer = null

# ==================================================================== 驻军 / 招募
## 通用居中弹窗，返回内容容器
func _modal_card(title: String, col: Color, width: float = 580.0) -> VBoxContainer:
	if is_instance_valid(event_layer):
		event_layer.queue_free()
		event_layer = null
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_event())
	add_child(shade)
	event_layer = shade
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(cc)
	var card := UI.panel(Color("#1c2231"), col, 12)
	card.custom_minimum_size = Vector2(width, 0)
	cc.add_child(card)
	var pad := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(k, 20)
	card.add_child(pad)
	var v := UI.vbox(10)
	pad.add_child(v)
	v.add_child(UI.title(title, 22))
	v.add_child(UI.line(UI.C_GOLD_DIM))
	return v

## 驻守 / 调兵：从英雄部队派人进据点，或把驻军收回
func _garrison_modal(site: Dictionary) -> void:
	var h := Game.selected_hero()
	var v := _modal_card("%s · 驻军" % String(site.name), UI.C_GOLD)
	if h.is_empty():
		v.add_child(UI.label("没有可调动的英雄", 13, UI.C_MUTED))
		v.add_child(UI.button("关闭", _close_event, 14, Vector2(120, 36), UI.C_MUTED))
		return
	v.add_child(UI.label("英雄部队 · 点数字派去驻守", 12, UI.C_MUTED))
	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 8)
	row1.add_theme_constant_override("v_separation", 8)
	v.add_child(row1)
	if (h.army as Array).is_empty():
		row1.add_child(UI.label("英雄没有部队", 12, UI.C_MUTED))
	for st in h.army:
		if not DB.UNITS.has(st.unit):
			continue
		var uid := String(st.unit)
		var cnt := int(st.count)
		var box := UI.panel(Color("#243044"), Game.faction_color(String(h.faction)), 6)
		var pad := MarginContainer.new()
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			pad.add_theme_constant_override(k, 6)
		box.add_child(pad)
		var cv := UI.vbox(3)
		pad.add_child(cv)
		cv.add_child(UI.label("%s ×%d" % [String(DB.UNITS[uid].name), cnt], 11, UI.C_TEXT))
		var br := UI.hbox(4)
		cv.add_child(br)
		br.add_child(UI.button("1", Callable(self, "_do_garrison_add").bind(site, uid, 1), 11, Vector2(32, 26), UI.C_GREEN))
		br.add_child(UI.button("5", Callable(self, "_do_garrison_add").bind(site, uid, 5), 11, Vector2(32, 26), UI.C_GREEN))
		br.add_child(UI.button("全部", Callable(self, "_do_garrison_add").bind(site, uid, cnt), 11, Vector2(44, 26), UI.C_GOLD))
		row1.add_child(box)

	v.add_child(UI.label("据点驻军 · 点数字收回", 12, UI.C_MUTED))
	var gar: Array = site.get("garrison", [])
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 8)
	row2.add_theme_constant_override("v_separation", 8)
	v.add_child(row2)
	if gar.is_empty():
		row2.add_child(UI.label("空 —— 敌人来了只能直接丢掉", 12, UI.C_MUTED))
	for g in gar:
		if not DB.UNITS.has(g.unit):
			continue
		var uid2 := String(g.unit)
		var cnt2 := int(g.count)
		var box2 := UI.panel(Color("#33262a"), UI.C_RED, 6)
		var pad2 := MarginContainer.new()
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			pad2.add_theme_constant_override(k, 6)
		box2.add_child(pad2)
		var cv2 := UI.vbox(3)
		pad2.add_child(cv2)
		cv2.add_child(UI.label("%s ×%d" % [String(DB.UNITS[uid2].name), cnt2], 11, UI.C_TEXT))
		var br2 := UI.hbox(4)
		cv2.add_child(br2)
		br2.add_child(UI.button("1", Callable(self, "_do_garrison_take").bind(site, uid2, 1), 11, Vector2(32, 26), UI.C_MUTED))
		br2.add_child(UI.button("5", Callable(self, "_do_garrison_take").bind(site, uid2, 5), 11, Vector2(32, 26), UI.C_MUTED))
		br2.add_child(UI.button("全部", Callable(self, "_do_garrison_take").bind(site, uid2, cnt2), 11, Vector2(44, 26), UI.C_GOLD))
		row2.add_child(box2)

	var foot := UI.hbox(8)
	v.add_child(foot)
	foot.add_child(UI.ghost_button("关闭", _close_event, 13))

func _do_garrison_add(site: Dictionary, uid: String, n: int) -> void:
	var h := Game.selected_hero()
	if h.is_empty():
		return
	var msg := Game.garrison_add(site, uid, maxi(1, n), h)
	Game.say(msg)
	_close_event()
	_garrison_modal(site)
	refresh()

func _do_garrison_take(site: Dictionary, uid: String, n: int) -> void:
	var h := Game.selected_hero()
	if h.is_empty():
		return
	var msg := Game.garrison_take(site, uid, maxi(1, n), h)
	Game.say(msg)
	_close_event()
	_garrison_modal(site)
	refresh()

## 招募士兵：金币 + 木材
func _recruit_modal(site: Dictionary) -> void:
	var h := Game.selected_hero()
	var v := _modal_card("%s · 招募士兵" % String(site.name), UI.C_GREEN, 620)
	v.add_child(UI.label("现有  金币 %d   木材 %d" % [
		int(Game.res.get("gold", 0)), int(Game.res.get("wood", 0))], 13, UI.C_GOLD))
	var pool: Array = DB.RECRUITS.get(String(h.faction), [])
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for uid in pool:
		var u: Dictionary = DB.UNITS[uid]
		var c1 := Game.unit_cost(String(uid), 1)
		var c5 := Game.unit_cost(String(uid), 5)
		var box := UI.panel(Color("#22303a"), Color(u.color), 6)
		var cv := UI.vbox(2)
		box.add_child(cv)
		cv.add_child(nowrap("  %s  " % String(u.name), 12, Color(u.color)))
		cv.add_child(nowrap("  %d金 + %d木  " % [int(c1.gold), int(c1.wood)], 11, UI.C_MUTED))
		var br := UI.hbox(4)
		cv.add_child(br)
		var ok1: bool = DB.can_afford(Game.res, c1)
		var b1 := UI.button("×1", Callable(self, "_do_recruit").bind(site, String(uid), 1), 11, Vector2(40, 26), UI.C_GREEN)
		b1.disabled = not ok1
		br.add_child(b1)
		var b5 := UI.button("×5", Callable(self, "_do_recruit").bind(site, String(uid), 5), 11, Vector2(40, 26), UI.C_GREEN)
		b5.disabled = not DB.can_afford(Game.res, c5)
		br.add_child(b5)
		grid.add_child(box)
	v.add_child(UI.ghost_button("关闭", _close_event, 13))

func _do_recruit(site: Dictionary, uid: String, n: int) -> void:
	var msg := Game.recruit(int(site.id), uid, n)
	Game.say(msg)
	_close_event()
	_recruit_modal(site)
	refresh()

## 招募英雄
func _hire_modal(site: Dictionary) -> void:
	var v := _modal_card("%s · 招募英雄" % String(site.name), UI.C_BLUE, 560)
	v.add_child(UI.label("花费 2500 金币 + 8 木材。现有 金币 %d · 木材 %d" % [
		int(Game.res.get("gold", 0)), int(Game.res.get("wood", 0))], 13, UI.C_GOLD))
	var owned := {}
	for hh in Game.heroes:
		owned[String(hh.def)] = true
	for key in DB.HEROES:
		var d: Dictionary = DB.HEROES[key]
		if String(d.faction) != Game.faction:
			continue
		var row := UI.hbox(8)
		var nm := UI.label("%s · %s · %s" % [d.name, d.klass, d.title], 13, Color(d.color))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		if owned.has(key):
			row.add_child(UI.label("已在麾下", 12, UI.C_MUTED))
		else:
			var b := UI.button("招募", Callable(self, "_do_hire").bind(site, key), 12, Vector2(80, 30), UI.C_GOLD)
			b.disabled = int(Game.res.get("gold", 0)) < 2500 or int(Game.res.get("wood", 0)) < 8
			row.add_child(b)
		v.add_child(row)
	v.add_child(UI.ghost_button("关闭", _close_event, 13))

func _do_hire(site: Dictionary, def_id: String) -> void:
	var msg := Game.hire_hero(int(site.id), def_id)
	Game.say(msg)
	_close_event()
	_sync_hero_nodes()
	refresh()

## 据点易主后重刷建筑颜色（营地旗、城镇旗都跟着势力走）
func _sync_poi_owners() -> void:
	for poi in pois:
		if poi == null or not is_instance_valid(poi):
			continue
		var ref := _poi_ref(poi)
		if ref.is_empty():
			continue
		var own := String(ref.get("owner", ""))
		if own != String(poi.owner_id):
			poi.owner_id = own
			poi.rebuild()

## 新增英雄后补建 3D 节点
func _sync_hero_nodes() -> void:
	for h in Game.heroes:
		if hero_nodes.has(int(h.id)):
			continue
		if not bool(h.alive):
			continue
		var node := _make_hero(h)
		hero_nodes[int(h.id)] = node

# ==================================================================== 防守事件
func _on_defense_prompt() -> void:
	if Game.pending_defenses.is_empty():
		return
	var ev: Dictionary = Game.pending_defenses[0]
	var body := "敌军：%s 的部队（战力 %d）\n\n你的守军：%s（战力 %d）\n\n死守：按兵力对比结算，守得住就保住产出，守不住就全灭。\n撤退：部队撤到后方营地，但这个据点连同它的产出归对方。" % [
		String(ev.attacker), int(ev.attacker_strength),
		_guards_text(ev.defense), int(ev.defense_strength)]
	_event_popup("据点告急 · " + String(ev.name), body, "死 守", UI.C_RED,
		func(): Game.resolve_defense(false), "撤 退",
		func(): Game.resolve_defense(true), false)

# ==================================================================== 目标标记
var move_marker: Node3D = null

func _spawn_marker(p: Vector3) -> void:
	_clear_marker()
	var n := Node3D.new()
	# 地面光斑：让目标点在草地上也一眼看到
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.92
	cm.bottom_radius = 0.92
	cm.height = 0.02
	cm.radial_segments = 24
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.0, 0.86, 0.40, 0.34)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.74, 0.20)
	dm.emission_energy_multiplier = 1.5
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = dm
	disc.position = Vector3(0, 0.08, 0)
	n.add_child(disc)
	# 外圈
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.86
	torus.rings = 20
	torus.ring_segments = 8
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.86, 0.40, 0.95)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.76, 0.24)
	m.emission_energy_multiplier = 1.8
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	n.add_child(mi)
	n.position = Vector3(p.x, p.y + 0.10, p.z)
	map_root.add_child(n)
	move_marker = n

func _clear_marker() -> void:
	if is_instance_valid(move_marker):
		move_marker.queue_free()
	move_marker = null

# ==================================================================== 拾取
func pick_ground(p: Vector2) -> Vector3:
	var from := cam.project_ray_origin(p)
	var to := from + cam.project_ray_normal(p) * 600.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var res := world.get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return Vector3.INF
	return res.position

func _poi_at_screen(p: Vector2) -> WorldPoi:
	# 屏幕判定：只认落在建筑名牌附近 58px 内的点击（原来 90px 会把旁边的空地也算进来）
	var best: WorldPoi = null
	var bd := 58.0
	for poi in pois:
		var wp: Vector3 = (poi as WorldPoi).global_position + Vector3(0, 2.2, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var d := sp.distance_to(p)
		if d < bd:
			bd = d
			best = poi
	# 兜底：点在建筑脚下（射线落点离建筑 4.5 米内）
	if best == null:
		var g := pick_ground(p)
		if g != Vector3.INF:
			var bw := 4.5
			for q in pois:
				var poi2 := q as WorldPoi
				if poi2 == null or not is_instance_valid(poi2):
					continue
				var dd := Vector2(poi2.global_position.x - g.x, poi2.global_position.z - g.z).length()
				if dd < bw:
					bw = dd
					best = poi2
	return best

func _hero_at_screen(p: Vector2) -> int:
	var best := -1
	var bd := 52.0
	for id in hero_nodes.keys():
		var node: Node3D = hero_nodes[id]
		var wp := node.position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(p)
		if d < bd:
			bd = d
			best = int(id)
	return best

func on_tap(pos: Vector2) -> void:
	# 事件弹窗挡着时不穿透
	if is_instance_valid(event_layer):
		return
	# 1) 点英雄 → 查看
	var hid := _hero_at_screen(pos)
	if hid >= 0:
		var h := Game.hero(hid)
		if not h.is_empty():
			Game.selected = hid
			inspect_hero = hid
			inspect_poi = null
			show_sheet()
		return
	# 2) 点地点 = 只看情报，绝不让英雄自己跑（之前误触就在这里）。
	#    真要过去可以：点面板里的「前 往」，或者双击这个地点。
	var poi := _poi_at_screen(pos)
	if poi != null:
		var now := Time.get_ticks_msec()
		var dbl := poi == _last_tap_poi and now - _last_tap_ms < 380
		_last_tap_poi = poi
		_last_tap_ms = now
		inspect_poi = poi
		inspect_hero = -1
		var hh := Game.selected_hero()
		var near := not hh.is_empty() and _hero_wpos(hh).distance_to(poi.global_position) <= INTERACT_RANGE
		if dbl and not near:
			# 双击远处地点 = 前往；已经在旁边时双击等同单击（没有"前往"的意义）
			_last_tap_poi = null
			_go_to_poi(poi)
			return
		if near:
			# 自己人据点：直接开面板（驻军 / 招募）；敌对据点：弹「是否进攻」
			var r := _poi_ref(poi)
			if String(r.get("owner", "")) == Game.faction:
				show_sheet()
			else:
				hide_sheet()
				_ask_poi(poi)
		else:
			show_sheet()
		return
	# 3) 点空地 → 关面板，英雄走过去
	var p := pick_ground(pos)
	hide_sheet()
	if p == Vector3.INF:
		pending_poi = null
		return
	_move_hero_to(p)

## 右键指令已停用（主地图只用点击与拖动）
func on_command(_pos: Vector2) -> void:
	pass

## 点了某个地点：已经在交互范围内就只查看，否则寻路走过去
func _go_to_poi(poi: WorldPoi) -> void:
	var h := Game.selected_hero()
	if h.is_empty():
		return
	if _hero_wpos(h).distance_to(poi.global_position) <= INTERACT_RANGE:
		return
	_move_hero_to(poi.stand_pos(), true, poi)

func on_hover(_pos: Vector2) -> void:
	pass

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
	hint = UI.label("点一下：查看　·　点空地：行走　·　双击地点：前往　·　拖动：平移镜头", 13, UI.C_MUTED)
	hint.position = Vector2(18, 78)
	hint.add_theme_constant_override("outline_size", 3)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(hint)

func refresh() -> void:
	if not is_instance_valid(topbar):
		return
	_sync_hero_nodes()
	_sync_poi_owners()
	_build_hud()
	if sheet_shown:
		fill_sheet()
		_layout_sheet(false)
	if Game.game_over != "" and not _end_shown:
		_end_shown = true
		var win := Game.game_over == "win"
		Game.dialog("战役结束 · " + ("胜利" if win else "失败"),
			("地图上所有敌对势力都被消灭了，金矿与伐木场尽在掌握。\n\n用时 %d 天。" % Game.day) if win
				else "营地被踏平，最后的统帅也倒下了。",
			func(): Game.goto("title", {}))

func _build_hud() -> void:
	for c in hud.get_children():
		hud.remove_child(c)
		c.queue_free()
	var crest := UI.panel(Color("#16394f"), UI.C_BLUE, 6)
	hud.add_child(crest)
	crest.add_child(UI.label("近卫", 16, Color("#bfe6ff")))
	hud.add_child(UI.label("第 %d 天" % Game.day, 18, UI.C_GOLD))
	if not Game.factions.is_empty():
		var total := 0
		var dead := 0
		for f in Game.factions:
			if bool(f.is_player):
				continue
			total += 1
			if not Game.faction_alive(String(f.id)):
				dead += 1
		hud.add_child(UI.label("已灭 %d/%d" % [dead, total], 14, UI.C_GOLD))
	for k in DB.RES_ORDER:
		var p := UI.panel(Color("#1b2231"), UI.C_GOLD_DIM, 5)
		p.add_child(UI.label("%s %d" % [DB.RES[k].short, int(Game.res.get(k, 0))], 13, Color(DB.RES[k].color)))
		hud.add_child(p)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(sp)
	hud.add_child(UI.ghost_button("－", func(): zoom_by(1.2), 16))
	hud.add_child(UI.ghost_button("＋", func(): zoom_by(0.84), 16))
	hud.add_child(UI.ghost_button("◎", _center_hero, 16))
	hud.add_child(UI.ghost_button("☰", _open_menu, 16))
	hud.add_child(UI.ghost_button("英雄", func():
		hide_sheet()
		Game.goto("hero", {}), 14))
	hud.add_child(UI.button("结束回合 ▶", _end_turn, 15, Vector2(126, 40), UI.C_GOLD))

func _center_hero() -> void:
	var h := Game.selected_hero()
	if not h.is_empty():
		center_on(_hero_wpos(h))

func _end_turn() -> void:
	if Game.awaiting_defense:
		Game.say("先处理据点告急")
		return
	Game.end_turn()
	if Game.game_over != "":
		refresh()

func _open_menu() -> void:
	if is_instance_valid(menu_layer):
		return
	hide_sheet()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	menu_layer = shade
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(cc)
	var card := UI.panel(Color("#1c2231"), UI.C_GOLD, 10)
	card.custom_minimum_size = Vector2(420, 0)
	cc.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.title("战役菜单", 24))
	v.add_child(UI.line(UI.C_GOLD_DIM))
	var h := Game.selected_hero()
	if not h.is_empty():
		v.add_child(nowrap("%s  Lv.%d  ·  第 %d 天" % [h.name, h.level, Game.day], 15, Color(h.color)))
	v.add_child(UI.button("保存进度", func():
		Saves.save_game(Game.save_slot)
		_close_menu()
		Game.say("已保存"), 15, Vector2(0, 42)))
	v.add_child(UI.button("返回标题", func():
		Saves.save_game(Game.save_slot)
		_close_menu()
		Game.goto("title", {}), 15, Vector2(0, 42), UI.C_MUTED))
	v.add_child(UI.ghost_button("六边形旧地图（对照）", func():
		_close_menu()
		Game.goto("worldhex", {}), 13))
	v.add_child(UI.ghost_button("关闭", _close_menu, 14))

func _close_menu() -> void:
	if is_instance_valid(menu_layer):
		menu_layer.queue_free()
	menu_layer = null

# ==================================================================== 面板
func fill_sheet() -> void:
	for c in sheet.get_children():
		sheet.remove_child(c)
		c.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(k, 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	sheet.add_child(margin)
	if inspect_hero >= 0:
		_fill_hero(margin)
	elif inspect_poi != null:
		_fill_poi(margin)
	else:
		sheet_shown = false

func _fill_hero(root: MarginContainer) -> void:
	var h := Game.hero(inspect_hero)
	if h.is_empty():
		sheet_shown = false
		return
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(340, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title("%s  Lv.%d" % [h.name, h.level], 24))
	nr.add_child(UI.chip("统帅" if int(h.id) == Game.selected else "待命", UI.C_GOLD))
	left.add_child(UI.label("%s · %s · %s" % [h.title, h.klass, Game.faction_name(String(h.faction))], 13, Color(h.color)))
	var st := Game.hero_stats(h)
	left.add_child(UI.label("攻 %d   防 %d   力 %d   智 %d" % [st.atk, st.def, st.power, st.knowledge], 15, UI.C_TEXT))
	left.add_child(UI.label("魔法 %d / %d" % [int(h.mana), Game.max_mana(h)], 14, UI.C_PURPLE))
	left.add_child(UI.bar(float(h.mana), float(Game.max_mana(h)), UI.C_PURPLE, 280, 10))
	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("军 队", 13, UI.C_MUTED))
	var total := 0
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 8)
	fr.add_theme_constant_override("v_separation", 6)
	mid.add_child(fr)
	for s in h.army:
		if not DB.UNITS.has(s.unit):
			continue
		total += int(s.count)
		var card := UI.panel(Color(DB.UNITS[s.unit].color).darkened(0.72), Color(DB.UNITS[s.unit].color), 5)
		var cv := UI.vbox(1)
		card.add_child(cv)
		cv.add_child(UI.label(DB.UNITS[s.unit].name, 13, Color(DB.UNITS[s.unit].color)))
		cv.add_child(UI.label("×%d" % int(s.count), 15, UI.C_TEXT))
		fr.add_child(card)
	mid.add_child(nowrap("总兵力 %d · 战力 %d" % [total, Game.army_strength(h.army)], 13, UI.C_MUTED))
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(190, 0)
	row.add_child(right)
	if String(h.faction) != Game.faction:
		# 敌方英雄：可以直接开战，击败后该势力就少一员
		right.add_child(UI.button("发起战斗", func():
			hide_sheet()
			Game.start_battle(Game.selected_hero(), h, h.army, "hero"), 15, Vector2(180, 42), UI.C_RED))
		right.add_child(nowrap("击败后该势力失去这名统帅", 11, UI.C_MUTED))
	elif int(h.id) == Game.selected:
		right.add_child(UI.button("英雄面板", func():
			hide_sheet()
			Game.goto("hero", {}), 15, Vector2(180, 40)))
		right.add_child(UI.button("技能 / 法术", func():
			hide_sheet()
			Game.goto("hero", {"tab": 1}), 15, Vector2(180, 40)))
	else:
		right.add_child(UI.button("切换为当前统帅", func():
			Game.selected = int(h.id)
			hide_sheet()
			refresh(), 15, Vector2(180, 40)))
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

func _fill_poi(root: MarginContainer) -> void:
	var poi := inspect_poi
	var ref := _poi_ref(poi)
	var owner_id := String(ref.get("owner", ""))
	var col := Game.faction_color(owner_id) if owner_id != "" else Color("#d8b45a")
	var row := UI.hbox(18)
	root.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(340, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title(poi.display_name(), 23))
	if poi.kind != "tavern" and poi.kind != "smith":
		nr.add_child(UI.chip(Game.faction_name(owner_id), col))
	var h := Game.selected_hero()
	var dist := 999.0
	if not h.is_empty():
		dist = _hero_wpos(h).distance_to(poi.global_position)
	var near := dist <= INTERACT_RANGE
	left.add_child(UI.label("距英雄 %.0f 米%s" % [dist, " · 可交互" if near else " · 走近才能交互"], 13, UI.C_MUTED))

	var mid := UI.vbox(5)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(206, 0)
	row.add_child(right)

	match poi.kind:
		"tavern":
			left.add_child(nowrap("招募新的英雄：2500 金币 + 8 木材。", 13, UI.C_TEXT))
			_build_tavern_actions(mid, right, poi, near)
		"smith":
			left.add_child(nowrap("买卖装备：买入按标价，卖出按半价回收。", 13, UI.C_TEXT))
			_build_smith_actions(mid, right, poi, near)
		"camp":
			var guards: Array = ref.get("guards", [])
			left.add_child(nowrap("野怪营地，守军 %s。" % _guards_text(guards), 13, UI.C_TEXT))
			left.add_child(nowrap("击败后获得金币与装备，营地会被清除。", 12, UI.C_MUTED))
			_garrison_lines(mid, ref)
			var b := UI.button("发起战斗", func(): _attack_poi(poi), 15, Vector2(190, 42), UI.C_RED)
			b.disabled = not near or guards.is_empty()
			right.add_child(b)
		_:
			# ---- 矿场 / 伐木场 / 城镇 / 势力营地
			var guards2: Array = ref.get("guards", [])
			var gar: Array = ref.get("garrison", [])
			if poi.kind == "mine":
				var rn := String(DB.RES[poi.resource].name)
				left.add_child(nowrap("每日产出 %d %s。" % [int(DB.RES[poi.resource].daily), rn], 14,
					col if owner_id == Game.faction else UI.C_TEXT))
			elif poi.kind == "town":
				left.add_child(nowrap("城镇：可建造建筑、募兵、买装备。", 13, UI.C_MUTED))
			elif poi.kind == "base":
				left.add_child(nowrap("势力营地。攻破它，这方势力就只剩流窜的英雄。", 13, UI.C_MUTED))
			if guards2.size() > 0:
				left.add_child(nowrap("守军 %s" % _guards_text(guards2), 13, UI.C_TEXT))
			left.add_child(nowrap("驻军 %s" % _guards_text(gar), 13, UI.C_TEXT if gar.size() > 0 else UI.C_MUTED))
			_garrison_lines(mid, ref)

			if owner_id == Game.faction:
				right.add_child(UI.button("驻守 / 调兵", func(): _garrison_modal(ref), 14, Vector2(190, 40), UI.C_GOLD))
				right.add_child(UI.button("招募士兵", func(): _recruit_modal(ref), 14, Vector2(190, 40), UI.C_GREEN))
				if poi.kind == "base" or poi.kind == "town":
					right.add_child(UI.button("招募英雄", func(): _hire_modal(ref), 14, Vector2(190, 40), UI.C_BLUE))
				if poi.kind == "town":
					right.add_child(UI.button("进入城镇", func():
						hide_sheet()
						Game.goto("town", {"town_id": int(ref.id)}), 14, Vector2(190, 40)))
			else:
				var can_fight: bool = (guards2.size() + gar.size()) > 0
				var b2 := UI.button("发起战斗", func(): _attack_poi(poi), 15, Vector2(190, 42), UI.C_RED)
				b2.disabled = not near or not can_fight
				right.add_child(b2)
				if not can_fight:
					var b3 := UI.button("直接占领", func(): _capture_poi(poi), 14, Vector2(190, 40), UI.C_GOLD)
					b3.disabled = not near
					right.add_child(b3)
				if not near:
					right.add_child(nowrap("先走到附近", 11, UI.C_MUTED))

	if not near:
		right.add_child(UI.button("前 往 · %.0f 米" % dist, func(): _go_to_poi(poi), 14, Vector2(190, 42), UI.C_GOLD))
	else:
		right.add_child(UI.label("已在交互范围", 11, UI.C_MUTED))
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

## 面板中列：驻军明细（最多 5 行，避免面板过高）
func _garrison_lines(mid: VBoxContainer, ref: Dictionary) -> void:
	var gar: Array = ref.get("garrison", [])
	if gar.is_empty():
		mid.add_child(nowrap("据点没有驻军 —— 敌人来了只能直接丢掉。", 12, UI.C_MUTED))
		return
	mid.add_child(UI.label("驻 军", 12, UI.C_MUTED))
	var shown := 0
	for g in gar:
		if not DB.UNITS.has(g.unit):
			continue
		mid.add_child(nowrap("%s ×%d" % [DB.UNITS[g.unit].name, int(g.count)], 12, UI.C_TEXT))
		shown += 1
		if shown >= 5:
			break

func _guards_text(guards: Array) -> String:
	var parts := []
	for g in guards:
		if DB.UNITS.has(g.unit):
			parts.append("%s×%d" % [DB.UNITS[g.unit].name, int(g.count)])
	return "、".join(parts) if parts.size() > 0 else "无"

func _build_tavern_actions(mid: VBoxContainer, right: VBoxContainer, poi: WorldPoi, near: bool) -> void:
	mid.add_child(UI.label("可招募的英雄", 13, UI.C_MUTED))
	var owned := {}
	for h in Game.heroes:
		owned[String(h.def)] = true
	var shown := 0
	for key in DB.HEROES:
		var d: Dictionary = DB.HEROES[key]
		if String(d.faction) != Game.faction:
			continue
		var row := UI.hbox(8)
		var nm := UI.label("%s · %s" % [d.name, d.klass], 13, Color(d.color))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		if owned.has(key):
			row.add_child(UI.label("已在麾下", 12, UI.C_MUTED))
		else:
			var b := UI.button("招募 2500+8木", func():
				_recruit_hero(key, poi), 12, Vector2(140, 32), UI.C_GOLD)
			b.disabled = not near or int(Game.res.get("gold", 0)) < 2500 or int(Game.res.get("wood", 0)) < 8
			row.add_child(b)
		mid.add_child(row)
		shown += 1
	if shown == 0:
		mid.add_child(nowrap("没有可招募的英雄", 12, UI.C_MUTED))
	if not near:
		right.add_child(nowrap("走到酒馆门口才能招募", 11, UI.C_MUTED))

func _build_smith_actions(mid: VBoxContainer, right: VBoxContainer, _poi: WorldPoi, near: bool) -> void:
	mid.add_child(UI.label("出售（买入价）", 13, UI.C_MUTED))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	mid.add_child(grid)
	for key in DB.ITEMS:
		var it: Dictionary = DB.ITEMS[key]
		var price := int(it.price)
		var b := UI.button("%s  %d金" % [it.name, price], func(): _buy_item(key), 11, Vector2(150, 34), Color("#c9d2dd"))
		b.disabled = not near or int(Game.res.get("gold", 0)) < price
		b.tooltip_text = String(it.desc)
		grid.add_child(b)
	mid.add_child(UI.label("背包（半价回收）", 13, UI.C_MUTED))
	var inv_grid := HFlowContainer.new()
	inv_grid.add_theme_constant_override("h_separation", 6)
	inv_grid.add_theme_constant_override("v_separation", 6)
	mid.add_child(inv_grid)
	if Game.inventory.is_empty():
		inv_grid.add_child(nowrap("空", 12, UI.C_MUTED))
	for key in Game.inventory:
		if not DB.ITEMS.has(key):
			continue
		var sell := int(int(DB.ITEMS[key].price) * 0.5)
		var b2 := UI.button("卖出 %s  +%d金" % [DB.ITEMS[key].name, sell], func(): _sell_item(key), 11, Vector2(170, 34), UI.C_MUTED)
		b2.disabled = not near
		inv_grid.add_child(b2)
	if not near:
		right.add_child(nowrap("走到铁匠铺才能交易", 11, UI.C_MUTED))

# ==================================================================== 交互动作
func _poi_ref(poi: WorldPoi) -> Dictionary:
	var arr: Array = []
	match poi.kind:
		"mine": arr = Game.mines
		"camp": arr = Game.camps
		"town": arr = Game.towns
		"base": arr = Game.bases
		"": return {}
	for x in arr:
		if String(x.get("poi", "")) == String(poi.name):
			return x
	return {}

func _poi_owner(poi: WorldPoi) -> String:
	var ref := _poi_ref(poi)
	return String(ref.get("owner", ""))

func _attack_poi(poi: WorldPoi) -> void:
	var h := Game.selected_hero()
	var ref := _poi_ref(poi)
	if h.is_empty() or ref.is_empty():
		return
	var guards: Array = ref.get("guards", []).duplicate()
	for g in ref.get("garrison", []):
		guards.append(g)
	if guards.is_empty():
		Game.say("这里没有守军")
		return
	hide_sheet()
	Game.selected = int(h.id)
	Game.start_battle(h, ref, guards, poi.kind, "plain")

func _capture_poi(poi: WorldPoi) -> void:
	var ref := _poi_ref(poi)
	if ref.is_empty():
		return
	var h := Game.selected_hero()
	if poi.kind == "base":
		Game.capture_base(h, ref)
	elif poi.kind == "town":
		Game.capture_town(h, ref)
	else:
		Game.capture_mine(h, ref)
	Game.say("占领 %s！" % ref.name)
	hide_sheet()
	refresh()

func _recruit_hero(def_id: String, poi: WorldPoi) -> void:
	if int(Game.res.get("gold", 0)) < 2500 or int(Game.res.get("wood", 0)) < 8:
		Game.say("需要 2500 金币与 8 木材")
		return
	Game.res.gold = int(Game.res.gold) - 2500
	Game.res.wood = int(Game.res.wood) - 8
	var spawn := poi.stand_pos()
	spawn.y = terrain.height_at(spawn.x, spawn.z)
	var nh := Game.create_hero(def_id, false, Vector2i(roundi(spawn.x), roundi(spawn.z)))
	nh["wpos"] = spawn
	Game.heroes.append(nh)
	Game.add_log("%s 在酒馆加入了近卫军团。" % nh.name)
	var node := _make_hero(nh)
	hero_nodes[int(nh.id)] = node
	Game.say("%s 加入了队伍" % nh.name)
	hide_sheet()
	refresh()

func _buy_item(key: String) -> void:
	var it: Dictionary = DB.ITEMS[key]
	var price := int(it.price)
	if int(Game.res.get("gold", 0)) < price:
		Game.say("金币不足")
		return
	Game.res.gold = int(Game.res.gold) - price
	Game.inventory.append(key)
	Game.add_log("买入 %s。" % it.name)
	Game.say("买下 %s" % it.name)
	refresh()

func _sell_item(key: String) -> void:
	if not Game.inventory.has(key):
		return
	Game.inventory.erase(key)
	var sell := int(int(DB.ITEMS[key].price) * 0.5)
	Game.res.gold = int(Game.res.gold) + sell
	Game.add_log("卖出 %s，得到 %d 金币。" % [DB.ITEMS[key].name, sell])
	Game.say("卖出 %s  +%d金" % [DB.ITEMS[key].name, sell])
	refresh()
