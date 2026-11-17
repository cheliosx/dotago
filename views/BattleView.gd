class_name BattleView
extends View3DCtrl
## 三维战场（20×13 六边形战棋）。
## 交互与大地图统一：
##   左键点击 / 单指点按   → 查看：部队信息面板；点空白关闭
##   右键点击 / 单指拖动   → 指令：移动、攻击、施法
##   双指拖动 / 捏合 / 滚轮 → 平移与缩放
## 规则（行动顺序、攻击反击、法术、AI、自动战斗、战后结算）与旧版完全一致。

const BCOLS := 20
const BROWS := 13
const ELEV := 0.30

# ---------------------------------------------------------------- 规则状态
var b: Dictionary = {}
var h: Dictionary = {}
var foe: Dictionary = {}
var biome := "plain"
var stacks := []
var order := []
var turn_idx := 0
var round_no := 1
var active := -1
var mode := "normal"
var spell_id := ""
var reach := {}
var obstacles := []
var hero_cast := false
var foe_cast := false
var busy := false
var finished := false
var log_lines := []
var mana := 0
var rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------- 三维节点
var terrain_mi: MeshInstance3D
var overlay_mi: MeshInstance3D
var piece_root: Node3D
var blocker_root: Node3D
var unit_nodes := {}    # idx -> Node3D
var unit_labels := {}   # idx -> Label3D
var unit_rings := {}    # idx -> Node3D
var unit_bars := {}     # idx -> Node3D（血条容器）
var unit_targets := {}  # idx -> Vector3

# ---------------------------------------------------------------- UI
var topbar: PanelContainer
var side: PanelContainer
var actions: PanelContainer
var hud_row: HBoxContainer
var side_box: VBoxContainer
var action_row: HBoxContainer
var hover_cell := Vector2i(-1, -1)
var cmd_cell := Vector2i(-1, -1)
var inspect_idx := -1

func setup(_p: Dictionary) -> void:
	pass

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.randomize()
	b = Game.pending_battle.duplicate(false)
	if b.is_empty():
		Game.goto("world", {})
		return
	h = Game.hero(int(b.hero_id))
	foe = b.enemy_hero
	biome = String(b.get("biome", "plain"))
	mana = int(h.mana)

	build_viewport()
	# 右侧留给行动顺序面板：三维视口只占左侧，避免单位和面板互相遮挡
	svc.offset_right = -312
	_build_scene()
	_build_ui()
	build_sheet()
	map_bounds = Hex3D.bounds(BCOLS, BROWS, HEX_S)
	bounds_margin = 2.0
	pitch = deg_to_rad(66.0)
	dist = 38.0
	dist_target = 38.0
	center_on(Hex3D.to_world(Vector2i(BCOLS / 2, BROWS / 2), HEX_S), false)

	setup_stacks()
	build_board()
	build_overlay()
	sync_units()
	start_round()

# ==================================================================== 场景搭建
func _build_scene() -> void:
	terrain_mi = MeshInstance3D.new()
	terrain_mi.material_override = terrain_material()
	world.add_child(terrain_mi)
	overlay_mi = MeshInstance3D.new()
	overlay_mi.material_override = overlay_material()
	world.add_child(overlay_mi)
	blocker_root = Node3D.new()
	world.add_child(blocker_root)
	piece_root = Node3D.new()
	world.add_child(piece_root)

func _cell_pos(c: Vector2i) -> Vector3:
	return Hex3D.to_world(c, HEX_S) + Vector3(0, ELEV, 0)

func _zone_color(c: Vector2i) -> Color:
	var base := Color(DB.TERRAIN.get(biome, DB.TERRAIN.plain).color).darkened(0.34)
	if (c.x + c.y) % 2 == 0:
		base = base.lightened(0.045)
	if c.x <= 4:
		base = base.lerp(Color("#1d4f68"), 0.40)
	elif c.x >= BCOLS - 5:
		base = base.lerp(Color("#692a2a"), 0.38)
	elif absi(c.x - BCOLS / 2) <= 1:
		base = base.lightened(0.05)
	return base

func build_board() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(BROWS):
		for x in range(BCOLS):
			var c := Vector2i(x, y)
			var top := _zone_color(c)
			Hex3D.add_prism(st, c, HEX_S, 0.965, -0.5, ELEV, top, top.darkened(0.5))
	terrain_mi.mesh = st.commit()

	# 障碍物：几块岩石
	for c in obstacles:
		var node := Node3D.new()
		node.position = _cell_pos(c)
		add_cyl(node, Vector3(0, 0.04, 0), 0.44, 0.08, Color("#2b303c"), 6)
		add_cone(node, Vector3(-0.10, 0.30, 0.06), 0.36, 0.56, Color("#4a4f5c"), 5)
		add_cone(node, Vector3(0.18, 0.20, -0.12), 0.26, 0.38, Color("#5d6373"), 5)
		blocker_root.add_child(node)

func build_overlay() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 可移动格
	for key in reach:
		var c := Hex.from_key(key)
		Hex3D.add_face(st, c, HEX_S, 0.88, ELEV + 0.03, Color(1.0, 0.90, 0.42, 0.34))
	if reach.size() > 0:
		add_region_edges(st, reach, HEX_S, func(_c: Vector2i) -> float: return ELEV + 0.034,
			Color(1.0, 0.92, 0.50, 1.0), 0.11)
	# 敌方单位：红环提示可攻击目标
	for s in stacks:
		if int(s.count) <= 0 or int(s.side) == 0:
			continue
		Hex3D.add_outline(st, s.pos, HEX_S, 0.90, ELEV + 0.035, Color(0.88, 0.36, 0.32, 0.95), 0.09)
	# 施法模式：全盘淡紫
	if mode == "spell":
		for y in range(BROWS):
			for x in range(BCOLS):
				Hex3D.add_face(st, Vector2i(x, y), HEX_S, 0.86, ELEV + 0.045, Color(0.70, 0.54, 0.88, 0.10))
	# 指令目标 / 悬停
	if cmd_cell.x >= 0:
		Hex3D.add_outline(st, cmd_cell, HEX_S, 0.93, ELEV + 0.05, Color(1.0, 0.55, 0.25, 0.95), 0.10)
	if hover_cell.x >= 0:
		Hex3D.add_outline(st, hover_cell, HEX_S, 0.94, ELEV + 0.055, Color(1, 1, 1, 0.85), 0.09)
	overlay_mi.mesh = st.commit()

# ==================================================================== 单位棋子
func _make_unit(s: Dictionary) -> Node3D:
	var idx := int(s.idx)
	var u: Dictionary = DB.UNITS[s.unit]
	var col := Color(u.color)
	var fac := UI.C_BLUE if int(s.side) == 0 else UI.C_RED
	var node := Node3D.new()
	node.position = _cell_pos(s.pos)
	node.scale = Vector3(1.5, 1.5, 1.5)
	add_cyl(node, Vector3(0, 0.05, 0), 0.40, 0.10, fac.darkened(0.45), 12)
	# 躯干：远程兵细高、重甲兵方块、其余矮方块
	var body: MeshInstance3D
	if int(u.range) > 2:
		body = add_cyl(node, Vector3(0, 0.42, 0), 0.14, 0.72, col.darkened(0.25), 8, 0.06)
	else:
		var sz := Vector3(0.34, 0.56, 0.34) if int(u.tier) >= 4 else Vector3(0.30, 0.44, 0.30)
		body = add_box(node, Vector3(0, 0.05 + sz.y * 0.5, 0), sz, col.darkened(0.3))
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.11
	sp.height = 0.22
	head.mesh = sp
	head.material_override = mat(col.lightened(0.25))
	head.position = Vector3(0, 0.82, 0)
	node.add_child(head)
	# 血条（容器 + 底色 + 填充，填充用 X 缩放表示比例）
	var bar := Node3D.new()
	bar.position = Vector3(0, 1.02, 0)
	var bg := add_box(bar, Vector3.ZERO, Vector3(0.62, 0.06, 0.02), Color("#11151d"))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fill := add_box(bar, Vector3.ZERO, Vector3(0.62, 0.05, 0.03), UI.C_GREEN if int(s.side) == 0 else UI.C_RED)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(bar)
	unit_bars[idx] = bar
	# 行动中光环
	var ring := Node3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.54
	torus.rings = 24
	torus.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat(Color("#d8b45a"), true)
	mi.rotation.x = deg_to_rad(90)
	mi.position = Vector3(0, 0.12, 0)
	ring.add_child(mi)
	ring.visible = false
	node.add_child(ring)
	unit_rings[idx] = ring
	unit_labels[idx] = add_label(node, "%s ×%d" % [u.name, int(s.count)], Vector3(0, 1.26, 0), col.lightened(0.15), 40)
	piece_root.add_child(node)
	return node

func sync_units() -> void:
	for s in stacks:
		var idx := int(s.idx)
		if int(s.count) <= 0:
			if unit_nodes.has(idx):
				unit_nodes[idx].visible = false
			continue
		if not unit_nodes.has(idx):
			unit_nodes[idx] = _make_unit(s)
			unit_targets[idx] = _cell_pos(s.pos)
		var node: Node3D = unit_nodes[idx]
		node.visible = true
		unit_targets[idx] = _cell_pos(s.pos)
		if node.position.distance_to(_cell_pos(s.pos)) > 3.0:
			node.position = _cell_pos(s.pos)
		var u: Dictionary = DB.UNITS[s.unit]
		var l: Label3D = unit_labels[idx]
		l.text = "%s ×%d" % [u.name, int(s.count)]
		l.modulate = Color(u.color).lightened(0.15)
		var bar: Node3D = unit_bars[idx]
		var frac := clampf(float(s.top_hp) / float(maxf(1, int(u.hp))), 0.0, 1.0)
		var fill: MeshInstance3D = bar.get_child(1)
		fill.scale.x = maxf(0.02, frac)
		fill.position.x = -0.31 * (1.0 - frac)
		var ring: Node3D = unit_rings[idx]
		ring.visible = idx == active

func update_units_states() -> void:
	# 状态徽标（防御 / 等待 / 霜甲）
	for s in stacks:
		var idx := int(s.idx)
		if int(s.count) <= 0 or not unit_nodes.has(idx):
			continue
		var tag := ""
		if s.defending:
			tag = "防"
		elif int(s.buff_def) > 0:
			tag = "霜"
		elif s.waited:
			tag = "待"
		var node: Node3D = unit_nodes[idx]
		var badge = node.get_node_or_null("Badge")
		if tag == "":
			if badge != null:
				badge.queue_free()
			continue
		if badge == null:
			var l := add_label(node, tag, Vector3(0.34, 1.24, 0), UI.C_GOLD, 30)
			l.name = "Badge"
		else:
			badge.text = tag

func _process(delta: float) -> void:
	super(delta)
	for idx in unit_targets.keys():
		var node: Node3D = unit_nodes.get(idx, null)
		if node == null:
			continue
		var target: Vector3 = unit_targets[idx]
		if node.position.distance_to(target) > 0.02:
			node.position = node.position.lerp(target, minf(1.0, delta * 9.0))

# ==================================================================== 规则（与原版一致）
func setup_stacks() -> void:
	var p_slots := [Vector2i(3, 1), Vector2i(3, 3), Vector2i(3, 5), Vector2i(3, 7), Vector2i(3, 9), Vector2i(1, 2), Vector2i(1, 4)]
	var e_slots := [Vector2i(16, 1), Vector2i(16, 3), Vector2i(16, 5), Vector2i(16, 7), Vector2i(16, 9), Vector2i(18, 2), Vector2i(18, 4)]
	obstacles = [Vector2i(10, 0), Vector2i(10, 12), Vector2i(9, 4), Vector2i(11, 4), Vector2i(9, 8), Vector2i(11, 8), Vector2i(10, 6)]
	var idx := 0
	var pi := 0
	var ei := 0
	for s in h.army:
		if pi >= p_slots.size():
			break
		stacks.append(make_stack(idx, s.unit, int(s.count), 0, p_slots[pi]))
		idx += 1
		pi += 1
	for s in b.enemy_army:
		if ei >= e_slots.size():
			break
		stacks.append(make_stack(idx, s.unit, int(s.count), 1, e_slots[ei]))
		idx += 1
		ei += 1
	add_log("【%s】遭遇 %s，敌军 %d 支部队。" % [h.name, foe.name, b.enemy_army.size()])

func make_stack(idx: int, uid: String, count: int, side_id: int, pos: Vector2i) -> Dictionary:
	var u: Dictionary = DB.UNITS[uid]
	return {"idx": idx, "unit": uid, "count": maxi(1, count), "top_hp": int(u.hp),
			"side": side_id, "pos": pos, "acted": false, "retaliated": false,
			"defending": false, "waited": false, "buff_def": 0, "slow": 0}

func side_hero_stats(side_id: int) -> Dictionary:
	if side_id == 0:
		return Game.hero_stats(h)
	var lv := int(foe.get("level", 1))
	return {"atk": lv, "def": lv, "power": lv, "knowledge": lv, "spd": 0}

func side_skill(side_id: int, key: String) -> int:
	if side_id == 1:
		return 0
	return int(h.skill.get(key, 0))

func eff_speed(s: Dictionary) -> int:
	var u: Dictionary = DB.UNITS[s.unit]
	return int(u.spd) + int(side_hero_stats(s.side).spd) - int(s.slow)

func start_round() -> void:
	if finished:
		return
	hero_cast = false
	foe_cast = false
	for s in stacks:
		s.acted = false
		s.retaliated = false
		s.defending = false
	order = []
	for s in stacks:
		if int(s.count) > 0:
			order.append(int(s.idx))
	var cmp := func(a, b2): return eff_speed(stacks[a]) > eff_speed(stacks[b2])
	order.sort_custom(cmp)
	turn_idx = 0
	add_log("—— 第 %d 回合 ——" % round_no)
	foe_hero_spell()
	next_turn()

func next_turn() -> void:
	if finished:
		return
	if check_end():
		return
	while turn_idx < order.size():
		var i: int = order[turn_idx]
		if int(stacks[i].count) <= 0 or stacks[i].acted:
			turn_idx += 1
		else:
			break
	if turn_idx >= order.size():
		round_no += 1
		if round_no > 40:
			finish(false)
			return
		start_round()
		return
	active = order[turn_idx]
	recompute_reach()
	if stacks[active].side == 1:
		busy = true
		ai_act(active)
	else:
		busy = false
		hint.text = "轮到 %s（速度 %d）· 右键 / 按住拖动 移动或攻击" % [DB.UNITS[stacks[active].unit].name, eff_speed(stacks[active])]
	refresh_view()

func recompute_reach() -> void:
	reach = {}
	if active < 0 or stacks[active].side != 0 or mode == "spell":
		return
	var s: Dictionary = stacks[active]
	var u: Dictionary = DB.UNITS[s.unit]
	var me: Node = self
	var cost_fn := func(_c: Vector2i) -> int: return 1
	var pass_fn := func(c: Vector2i) -> bool: return me.cell_free(c)
	var f := Hex.flood(s.pos, int(u.move), cost_fn, pass_fn)
	f.erase(Hex.key(s.pos))
	reach = f

func cell_free(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= BCOLS or c.y >= BROWS:
		return false
	if c in obstacles:
		return false
	for s in stacks:
		if int(s.count) > 0 and s.pos == c:
			return false
	return true

func stack_at(c: Vector2i) -> int:
	for s in stacks:
		if int(s.count) > 0 and s.pos == c:
			return int(s.idx)
	return -1

func alive_count(side_id: int) -> int:
	var n := 0
	for s in stacks:
		if s.side == side_id and int(s.count) > 0:
			n += 1
	return n

func check_end() -> bool:
	if finished:
		return true
	if alive_count(1) == 0:
		finish(true)
		return true
	if alive_count(0) == 0:
		finish(false)
		return true
	return false

# ==================================================================== 指令
func command_at(c: Vector2i) -> void:
	if finished or busy or active < 0:
		hint.text = "等待敌方行动……"
		return
	if int(stacks[active].side) != 0:
		return
	if mode == "spell":
		cast_spell(c)
		return
	var s: Dictionary = stacks[active]
	var u: Dictionary = DB.UNITS[s.unit]
	var target := stack_at(c)
	if target >= 0 and stacks[target].side == 1:
		var d := Hex.dist(s.pos, c)
		var adjacent_enemy := has_adjacent_enemy(s)
		if int(u.range) > 1 and d >= 2 and d <= int(u.range) and not adjacent_enemy:
			attack(active, target, true)
			end_action()
		else:
			var dest := best_approach(s, c)
			if dest.x >= 0:
				s.pos = dest
				var nd := Hex.dist(s.pos, c)
				var can_hit := (nd <= 1) or (int(u.range) > 1 and nd >= 2 and nd <= int(u.range))
				if can_hit:
					attack(active, target, int(u.range) > 1 and nd >= 2)
				else:
					add_log("%s 向目标推进。" % u.name)
			else:
				hint.text = "无法接近该目标"
				return
			end_action()
		return
	if reach.has(Hex.key(c)) and cell_free(c):
		s.pos = c
		add_log("%s 移动到 (%d,%d)。" % [u.name, c.x, c.y])
		end_action()
	else:
		hint.text = "该格无法到达，或已被占据"

func has_adjacent_enemy(s: Dictionary) -> bool:
	for n in Hex.neighbors(s.pos):
		var t := stack_at(n)
		if t >= 0 and stacks[t].side != s.side:
			return true
	return false

func best_approach(s: Dictionary, target: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999
	var candidates := [s.pos]
	for key in reach:
		candidates.append(Hex.from_key(key))
	for c in candidates:
		var d := Hex.dist(c, target)
		if d == 0:
			continue
		if d < best_d and (c == s.pos or cell_free(c)):
			best_d = d
			best = c
	return best

func end_action() -> void:
	if active < 0:
		return
	stacks[active].acted = true
	active = -1
	turn_idx += 1
	mode = "normal"
	spell_id = ""
	next_turn()

func action_defend() -> void:
	if finished or busy or active < 0 or int(stacks[active].side) != 0:
		return
	stacks[active].defending = true
	add_log("%s 进入防御姿态。" % DB.UNITS[stacks[active].unit].name)
	end_action()

func action_wait() -> void:
	if finished or busy or active < 0 or int(stacks[active].side) != 0:
		return
	var s: Dictionary = stacks[active]
	if s.waited:
		hint.text = "本回合已经等待过"
		return
	s.waited = true
	order.append(active)
	active = -1
	turn_idx += 1
	next_turn()

func select_spell(sid: String) -> void:
	if finished or busy or active < 0 or int(stacks[active].side) != 0:
		hint.text = "请等待我方部队行动"
		return
	if hero_cast:
		hint.text = "本回合英雄已经施法"
		return
	if int(DB.SPELLS[sid].cost) > mana:
		hint.text = "魔法值不足"
		return
	spell_id = sid
	mode = "spell"
	reach = {}
	add_log("选择法术「%s」，右键（或按住拖动）选择目标。" % DB.SPELLS[sid].name)
	if DB.SPELLS[sid].type == "drain_all":
		cast_spell(Vector2i(-1, -1))
		return
	hint.text = "施法模式：右键 / 按住拖动 选择目标（友军法术点我方单位）"
	refresh_view()

func cancel_spell() -> void:
	mode = "normal"
	spell_id = ""
	recompute_reach()
	refresh_view()

func cast_spell(c: Vector2i) -> void:
	var sd: Dictionary = DB.SPELLS[spell_id]
	var cost := int(sd.cost)
	if cost > mana:
		hint.text = "魔法值不足"
		return
	var typ: String = sd.type
	var power := float(sd.power) * (1.0 + 0.18 * float(side_skill(0, "sorcery"))) * (1.0 + 0.05 * float(Game.hero_stats(h).power))
	var hit := 0
	if typ == "drain_all":
		for s in stacks:
			if s.side == 1 and int(s.count) > 0:
				apply_damage(s, power * 0.7)
				hit += 1
		mana = mini(Game.max_mana(h), mana + 4)
	elif typ == "line":
		for s in stacks:
			if s.side == 1 and int(s.count) > 0 and s.pos.y == c.y:
				apply_damage(s, power)
				hit += 1
	elif typ == "aoe":
		for s in stacks:
			if s.side == 1 and int(s.count) > 0 and Hex.dist(s.pos, c) <= int(sd.radius):
				apply_damage(s, power)
				hit += 1
	elif typ == "single":
		var t := stack_at(c)
		if t < 0 or stacks[t].side != 1:
			hint.text = "请选择一支敌军"
			return
		apply_damage(stacks[t], power)
		hit = 1
	elif typ == "heal":
		var t2 := stack_at(c)
		if t2 < 0 or stacks[t2].side != 0:
			hint.text = "请选择一支友军"
			return
		var u: Dictionary = DB.UNITS[stacks[t2].unit]
		var pool := DB.unit_hp_pool(int(stacks[t2].count), int(stacks[t2].top_hp), stacks[t2].unit) + int(power) * int(u.hp) / 10
		stacks[t2].count = int(ceil(float(pool) / float(u.hp)))
		stacks[t2].top_hp = pool - (int(stacks[t2].count) - 1) * int(u.hp)
		hit = 1
		add_log("「神圣之光」治疗了 %s。" % u.name)
	elif typ == "buff_def":
		var t3 := stack_at(c)
		if t3 < 0 or stacks[t3].side != 0:
			hint.text = "请选择一支友军"
			return
		stacks[t3].buff_def = int(stacks[t3].buff_def) + int(sd.power)
		hit = 1
		add_log("「霜甲术」强化了 %s 的护甲。" % DB.UNITS[stacks[t3].unit].name)
	if hit == 0 and typ != "heal" and typ != "buff_def":
		hint.text = "法术没有命中任何目标"
		return
	mana -= cost
	hero_cast = true
	add_log("%s 施放「%s」。" % [h.name, sd.name])
	mode = "normal"
	spell_id = ""
	if check_end():
		return
	recompute_reach()
	refresh_view()

# ==================================================================== 伤害
func attack(a_idx: int, t_idx: int, ranged: bool) -> void:
	var a: Dictionary = stacks[a_idx]
	var t: Dictionary = stacks[t_idx]
	if int(a.count) <= 0 or int(t.count) <= 0:
		return
	var au: Dictionary = DB.UNITS[a.unit]
	var tu: Dictionary = DB.UNITS[t.unit]
	var ah := side_hero_stats(a.side)
	var dh := side_hero_stats(t.side)
	var atk_bonus := 1.0 + 0.05 * float(int(ah.atk) - int(dh.def)) + 0.08 * float(side_skill(a.side, "offense"))
	if ranged:
		atk_bonus += 0.12 * float(side_skill(a.side, "archery"))
	var def_bonus := 1.0 + 0.05 * float(int(dh.def) - int(ah.atk)) + 0.06 * float(side_skill(t.side, "armorer"))
	var reduction: float = clampf(0.03 * float(int(tu.def)) * def_bonus, 0.0, 0.62)
	var dmg: float = float(int(a.count)) * float(int(au.atk)) * maxf(0.35, atk_bonus) * (1.0 - reduction)
	if ranged and Hex.dist(a.pos, t.pos) <= 1:
		dmg *= 0.5
	if t.defending:
		dmg *= 0.75
	if int(t.buff_def) > 0:
		dmg *= maxf(0.5, 1.0 - 0.05 * float(t.buff_def))
	dmg *= rng.randf_range(0.9, 1.1)
	var before := int(t.count)
	apply_damage(t, dmg)
	var killed := before - int(t.count)
	add_log("%s %s %s，造成 %d 点伤害，消灭 %d 个。" % [au.name, "射击" if ranged else "攻击", tu.name, int(dmg), killed])
	if int(t.count) > 0 and not ranged and not t.retaliated and Hex.dist(a.pos, t.pos) <= 1 and int(DB.UNITS[t.unit].range) <= 2:
		t.retaliated = true
		var rdmg: float = float(int(t.count)) * float(int(tu.atk)) * 0.6 * (1.0 - clampf(0.03 * float(int(au.def)), 0.0, 0.5))
		apply_damage(a, rdmg)
		add_log("%s 进行了反击。" % tu.name)

func apply_damage(s: Dictionary, dmg: float) -> void:
	var u: Dictionary = DB.UNITS[s.unit]
	var pool := DB.unit_hp_pool(int(s.count), int(s.top_hp), s.unit)
	pool -= int(maxf(1.0, dmg))
	if pool <= 0:
		s.count = 0
		s.top_hp = 0
		return
	s.count = int(ceil(float(pool) / float(u.hp)))
	s.top_hp = pool - (int(s.count) - 1) * int(u.hp)
	if int(s.top_hp) <= 0:
		s.count -= 1
		s.top_hp = int(u.hp)

func foe_hero_spell() -> void:
	if foe_cast or int(foe.get("mana", 0)) < 4 or round_no % 2 == 0:
		return
	var target := -1
	var best := -1
	for s in stacks:
		if s.side == 0 and int(s.count) > 0 and int(s.count) * int(DB.UNITS[s.unit].atk) > best:
			best = int(s.count) * int(DB.UNITS[s.unit].atk)
			target = int(s.idx)
	if target < 0:
		return
	foe_cast = true
	foe.mana = int(foe.get("mana", 0)) - 4
	var dmg := 18.0 * (1.0 + 0.08 * float(int(foe.get("level", 1))))
	apply_damage(stacks[target], dmg)
	add_log("%s 施放了奥术弹，突袭我军！" % foe.name)

# ==================================================================== AI
func ai_act(idx: int) -> void:
	await get_tree().create_timer(0.28).timeout
	if finished:
		return
	var s: Dictionary = stacks[idx]
	if int(s.count) <= 0:
		busy = false
		end_action()
		return
	var u: Dictionary = DB.UNITS[s.unit]
	var target := nearest_foe(s)
	if target < 0:
		busy = false
		end_action()
		return
	var d := Hex.dist(s.pos, stacks[target].pos)
	if int(u.range) > 1 and d >= 2 and d <= int(u.range) and not has_adjacent_enemy(s):
		attack(idx, target, true)
	else:
		var one := func(_c: Vector2i) -> int: return 1
		var free_fn := func(c: Vector2i) -> bool: return cell_free(c)
		var f := Hex.flood(s.pos, int(u.move), one, free_fn)
		var best_cell: Vector2i = s.pos
		var best_d := Hex.dist(s.pos, stacks[target].pos)
		for key in f:
			var cc := Hex.from_key(key)
			var dd := Hex.dist(cc, stacks[target].pos)
			if dd < best_d:
				best_d = dd
				best_cell = cc
		if best_cell != s.pos:
			s.pos = best_cell
		if Hex.dist(s.pos, stacks[target].pos) <= 1 or (int(u.range) > 1 and Hex.dist(s.pos, stacks[target].pos) <= int(u.range)):
			attack(idx, target, int(u.range) > 1 and Hex.dist(s.pos, stacks[target].pos) > 1)
	busy = false
	end_action()

func nearest_foe(s: Dictionary) -> int:
	var best := -1
	var bd := 999
	for t in stacks:
		if t.side != s.side and int(t.count) > 0:
			var d := Hex.dist(s.pos, t.pos)
			if d < bd:
				bd = d
				best = int(t.idx)
	return best

func auto_battle() -> void:
	if finished:
		return
	add_log("指挥官下令全军自动作战……")
	var guard := 0
	while not finished and guard < 300:
		guard += 1
		for s in stacks:
			if int(s.count) <= 0 or s.side != 0:
				continue
			var t := nearest_foe(s)
			if t >= 0:
				attack(int(s.idx), t, int(DB.UNITS[s.unit].range) > 1)
		if check_end():
			break
		for s2 in stacks:
			if int(s2.count) <= 0 or s2.side != 1:
				continue
			var t2 := nearest_foe(s2)
			if t2 >= 0:
				attack(int(s2.idx), t2, int(DB.UNITS[s2.unit].range) > 1)
		if check_end():
			break
	busy = false
	if not finished:
		finish(alive_count(0) > alive_count(1))
	refresh_view()

# ==================================================================== 结束
func finish(win: bool) -> void:
	if finished:
		return
	finished = true
	busy = true
	mode = "normal"
	var survivors := []
	for s in stacks:
		if s.side == 0 and int(s.count) > 0:
			survivors.append({"unit": s.unit, "count": int(s.count)})
	var summary := Game.finish_battle(win, survivors, mana)
	Game.pending_battle = {}
	show_result(win, summary)

func show_result(win: bool, summary: Dictionary) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(cc)
	var card := UI.panel(Color("#1c2231"), UI.C_GOLD if win else UI.C_RED, 10)
	card.custom_minimum_size = Vector2(560, 0)
	cc.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.title("战斗胜利" if win else "战斗失利", 30))
	v.add_child(UI.line(UI.C_GOLD_DIM))
	var lines := ""
	if win:
		lines += "击败了 %s 的部队。\n\n" % String(summary.get("name", "敌军"))
		lines += "英雄经验  +%d\n" % int(summary.get("xp", 0))
		lines += "战利品    %s\n" % DB.res_text(summary.get("loot", {}))
		if String(summary.get("item", "")) != "":
			lines += "获得装备  「%s」\n" % String(summary.item)
		lines += "\n幸存部队已保留，可继续征战。"
	else:
		lines = "%s 部队溃败，英雄撤退至最近的城镇。\n\n吸取教训：优先升级魔法塔与远程兵种，别让远程单位被贴身。" % h.name
	var l := UI.label(lines, 17, UI.C_TEXT)
	l.custom_minimum_size = Vector2(500, 0)
	v.add_child(l)
	var btn := UI.button("返回大地图", func(): Game.goto("world", {}), 18, Vector2(200, 48))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(btn)

func add_log(s: String) -> void:
	log_lines.push_front(s)
	if log_lines.size() > 30:
		log_lines.resize(30)

# ==================================================================== UI
func _build_ui() -> void:
	topbar = UI.panel(Color("#141a26"), UI.C_GOLD_DIM, 8)
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topbar.offset_left = 12
	topbar.offset_right = -12
	topbar.offset_top = 10
	topbar.offset_bottom = 74
	topbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(topbar)
	hud_row = UI.hbox(8)
	topbar.add_child(hud_row)

	side = UI.panel(Color("#141a26"), UI.C_BORDER, 8)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.anchor_bottom = 1.0
	side.offset_left = -300
	side.offset_right = -12
	side.offset_top = 82
	side.offset_bottom = -86
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(side)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(sc)
	side_box = UI.vbox(7)
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(side_box)

	actions = UI.panel(Color("#141a26"), UI.C_GOLD_DIM, 8)
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	actions.offset_left = 12
	actions.offset_right = -12
	actions.offset_top = -74
	actions.offset_bottom = -12
	actions.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(actions)
	action_row = UI.hbox(8)
	actions.add_child(action_row)

	hint = UI.label("战斗开始 · 点击查看 · 右键 / 按住拖动 移动攻击", 13, UI.C_GOLD)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.position = Vector2(18, 80)
	add_child(hint)

func refresh_view() -> void:
	if not is_instance_valid(topbar):
		return
	build_overlay()
	sync_units()
	update_units_states()
	_build_hud()
	_build_side()
	_build_actions()
	if sheet_shown:
		fill_sheet()
		_layout_sheet(false)

func _build_hud() -> void:
	for c in hud_row.get_children():
		hud_row.remove_child(c)
		c.queue_free()
	hud_row.add_child(UI.label("◆ %s  Lv.%d" % [h.name, h.level], 18, UI.C_BLUE))
	hud_row.add_child(UI.label("魔法 %d/%d" % [mana, Game.max_mana(h)], 14, UI.C_PURPLE))
	hud_row.add_child(UI.bar(float(mana), float(Game.max_mana(h)), UI.C_PURPLE, 120, 10))
	hud_row.add_child(UI.label("VS", 16, UI.C_GOLD))
	hud_row.add_child(UI.label("▲ %s" % String(foe.name), 17, UI.C_RED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_row.add_child(sp)
	hud_row.add_child(UI.label("第 %d 回合" % round_no, 16, UI.C_GOLD))
	hud_row.add_child(UI.label("我方 %d / 敌方 %d" % [alive_count(0), alive_count(1)], 14, UI.C_MUTED))

func _build_side() -> void:
	for c in side_box.get_children():
		side_box.remove_child(c)
		c.queue_free()
	side_box.add_child(UI.title("行动顺序", 17))
	for i in order:
		var s: Dictionary = stacks[i]
		if int(s.count) <= 0:
			continue
		var u: Dictionary = DB.UNITS[s.unit]
		var row := UI.hbox(6)
		var dot := UI.panel(Color(u.color).darkened(0.7), UI.C_BLUE if s.side == 0 else UI.C_RED, 3)
		dot.add_child(UI.label("我" if s.side == 0 else "敌", 11, UI.C_TEXT))
		row.add_child(dot)
		var l := UI.label("%s ×%d" % [u.name, int(s.count)], 12, UI.C_GOLD if int(s.idx) == active else UI.C_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.label("速%d" % eff_speed(s), 11, UI.C_MUTED))
		side_box.add_child(row)
	side_box.add_child(UI.line(UI.C_GOLD_DIM))
	side_box.add_child(UI.title("英雄法术", 17))
	side_box.add_child(nowrap("本回合%s" % ("已施法" if hero_cast else "可施法 1 次"), 12, UI.C_MUTED))
	var can_act: bool = not finished and not busy and active >= 0 and int(stacks[active].side) == 0
	for sid in h.spells:
		var sd: Dictionary = DB.SPELLS[sid]
		var btn := UI.button("%s  %d魔" % [sd.name, int(sd.cost)], Callable(self, "select_spell").bind(sid), 13, Vector2(0, 34), UI.C_PURPLE)
		btn.disabled = hero_cast or int(sd.cost) > mana or not can_act or finished
		if spell_id == sid:
			btn.text = "◆ " + String(sd.name)
		side_box.add_child(btn)
	if mode == "spell":
		side_box.add_child(UI.button("取消施法", cancel_spell, 13, Vector2(0, 32), UI.C_RED))
	side_box.add_child(UI.line(UI.C_GOLD_DIM))
	side_box.add_child(UI.title("战斗记录", 16))
	var n := 0
	for l2 in log_lines:
		if n >= 8:
			break
		var jl := UI.label("· " + String(l2), 11, UI.C_MUTED)
		jl.custom_minimum_size = Vector2(246, 0)
		jl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_box.add_child(jl)
		n += 1

func _build_actions() -> void:
	for c in action_row.get_children():
		action_row.remove_child(c)
		c.queue_free()
	var can_act: bool = not finished and not busy and active >= 0 and int(stacks[active].side) == 0
	var bd := UI.button("防御", action_defend, 15, Vector2(96, 40), UI.C_MUTED)
	bd.disabled = not can_act
	action_row.add_child(bd)
	var bw := UI.button("等待", action_wait, 15, Vector2(96, 40), UI.C_MUTED)
	bw.disabled = not can_act
	action_row.add_child(bw)
	var ba := UI.button("自动战斗", auto_battle, 15, Vector2(126, 40), UI.C_GREEN)
	ba.disabled = finished
	action_row.add_child(ba)
	var br := UI.button("撤退", func(): finish(false), 14, Vector2(88, 40), UI.C_RED)
	br.disabled = finished
	action_row.add_child(br)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(sp)
	action_row.add_child(nowrap("点击查看 · 右键移动/攻击 · 双指平移缩放 · 远程贴身减半", 12, UI.C_MUTED))

# ==================================================================== 查看面板
func fill_sheet() -> void:
	for c in sheet.get_children():
		sheet.remove_child(c)
		c.queue_free()
	if inspect_idx < 0 or inspect_idx >= stacks.size():
		sheet_shown = false
		return
	var s: Dictionary = stacks[inspect_idx]
	if int(s.count) <= 0:
		sheet_shown = false
		return
	var u: Dictionary = DB.UNITS[s.unit]
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	sheet.add_child(margin)

	var row := UI.hbox(18)
	margin.add_child(row)
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(360, 0)
	row.add_child(left)
	var nr := UI.hbox(8)
	left.add_child(nr)
	nr.add_child(UI.title(String(u.name), 24))
	nr.add_child(UI.chip("我方" if int(s.side) == 0 else "敌方", UI.C_BLUE if int(s.side) == 0 else UI.C_RED))
	left.add_child(UI.label("%s · %d 级兵种 · 坐标 (%d, %d)" % [
		"远程" if int(u.range) > 2 else ("飞行" if String(u.trait) == "飞行" else "近战"),
		int(u.tier), s.pos.x, s.pos.y], 13, UI.C_MUTED))
	left.add_child(UI.label("数量 ×%d    单体生命 %d / %d" % [int(s.count), int(s.top_hp), int(u.hp)], 14, UI.C_TEXT))
	left.add_child(UI.bar(float(s.top_hp), float(u.hp), UI.C_GREEN if int(s.side) == 0 else UI.C_RED, 300, 10))
	left.add_child(nowrap("攻 %d  防 %d  速 %d  射程 %d" % [int(u.atk), int(u.def), eff_speed(s), int(u.range)], 14, UI.C_TEXT))

	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("状 态", 13, UI.C_MUTED))
	var tags := []
	if s.defending:
		tags.append("防御姿态（受伤 -25%）")
	if int(s.buff_def) > 0:
		tags.append("霜甲 +%d" % int(s.buff_def))
	if s.waited:
		tags.append("本回合已等待")
	if bool(s.acted):
		tags.append("本回合已行动")
	if int(s.idx) == active:
		tags.append("正在行动")
	if tags.is_empty():
		tags.append("无")
	mid.add_child(nowrap(" · ".join(tags), 13, UI.C_GOLD))
	var dmg := float(int(s.count)) * float(int(u.atk))
	mid.add_child(nowrap("估算输出 约 %d 点/次（不含英雄与克制修正）" % int(dmg), 12, UI.C_MUTED))
	if not is_equal_approx(float(u.hp), 0.0):
		var total := DB.unit_hp_pool(int(s.count), int(s.top_hp), s.unit)
		mid.add_child(nowrap("总生命池 %d" % total, 12, UI.C_MUTED))
	if int(s.side) == 1 and int(s.count) > 0:
		mid.add_child(nowrap("右键 / 按住拖动 该部队即可发起攻击", 12, UI.C_RED))

	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(180, 0)
	row.add_child(right)
	if int(s.idx) == active and not finished:
		right.add_child(UI.button("原地防御", action_defend, 14, Vector2(170, 38)))
		right.add_child(UI.button("等待", action_wait, 14, Vector2(170, 38)))
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

# ==================================================================== 查看 / 指令入口
func cell_at_screen(p: Vector2) -> Vector2i:
	var hit := ground_hit(p, ELEV + 0.05)
	var cell := Hex3D.from_world(hit, HEX_S)
	if cell.x < 0 or cell.y < 0 or cell.x >= BCOLS or cell.y >= BROWS:
		return Vector2i(-1, -1)
	return cell

func on_tap(pos: Vector2) -> void:
	var c := cell_at_screen(pos)
	if c.x < 0:
		hide_sheet()
		return
	var idx := stack_at(c)
	if idx < 0:
		hide_sheet()
		return
	inspect_idx = idx
	show_sheet()

func on_command(pos: Vector2) -> void:
	cmd_cell = Vector2i(-1, -1)
	var c := cell_at_screen(pos)
	if c.x < 0:
		build_overlay()
		return
	command_at(c)
	build_overlay()

func on_command_hover(pos: Vector2) -> void:
	var c := cell_at_screen(pos)
	if c != cmd_cell:
		cmd_cell = c
		build_overlay()

func on_command_hover_end() -> void:
	if cmd_cell.x >= 0:
		cmd_cell = Vector2i(-1, -1)
		build_overlay()

func on_hover(pos: Vector2) -> void:
	var c := cell_at_screen(pos)
	if c != hover_cell:
		hover_cell = c
		build_overlay()
