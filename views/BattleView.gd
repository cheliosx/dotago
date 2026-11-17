class_name BattleView
extends View3DCtrl
## 三维战场（20×13 六边形战棋）。
##
## 交互：
##   左键点击 / 单指点按   → 选我方单位（出现可移动区域）；点敌方单位查看情报；点空地取消选择
##   右键点击 / 单指拖动   → 让选中单位移动；已点亮普攻/技能时，右键 = 对目标施放
##   底部面板：普攻 + 4 个兵种技能（带冷却，冷却中按钮变灰）
##   双指拖动平移、捏合缩放
##
## 回合：每回合按速度排行动顺序；轮到玩家时，可自由选择任一未行动的我方单位。

const BCOLS := 20
const BROWS := 13
const ELEV := 0.30
const MOVE_T := 0.12

# ---------------------------------------------------------------- 规则状态
var b: Dictionary = {}
var h: Dictionary = {}
var foe: Dictionary = {}
var biome := "plain"
var stacks := []
var order := []
var turn_idx := 0
var round_no := 1
var active := -1          # 我方当前选中的单位 / 敌方正在行动的单位
var reach := {}
var obstacles := []
var hero_cast := false
var foe_cast := false
var busy := false
var finished := false
var log_lines := []
var mana := 0
var rng := RandomNumberGenerator.new()
var pending_skill := ""   # "" / "attack" / "skill:<id>" / "spell:<id>"
var anim_lock := false

# ---------------------------------------------------------------- 三维节点
var terrain_mi: MeshInstance3D
var overlay_mi: MeshInstance3D
var piece_root: Node3D
var blocker_root: Node3D
var fx_root: Node3D
var unit_nodes := {}
var unit_holders := {}
var unit_labels := {}
var unit_rings := {}
var unit_bars := {}
var unit_hp_frac := {}     # idx -> 目标血条比例（_process 里平滑逼近）
var unit_dying := {}
var anim_ignore := {}

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

# ==================================================================== 场景
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
	fx_root = Node3D.new()
	world.add_child(fx_root)

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
	for key in reach:
		var c := Hex.from_key(key)
		Hex3D.add_face(st, c, HEX_S, 0.88, ELEV + 0.03, Color(1.0, 0.90, 0.42, 0.34))
	if reach.size() > 0:
		add_region_edges(st, reach, HEX_S, func(_c: Vector2i) -> float: return ELEV + 0.034,
			Color(1.0, 0.92, 0.50, 1.0), 0.11)
	# 敌方单位红环；点亮技能后有效目标再加亮
	for s in stacks:
		if int(s.count) <= 0 or int(s.side) == 0:
			continue
		var armed := pending_skill != ""
		var col := Color(1.0, 0.55, 0.35, 1.0) if armed else Color(0.88, 0.36, 0.32, 0.9)
		Hex3D.add_outline(st, s.pos, HEX_S, 0.90, ELEV + 0.035, col, 0.11 if armed else 0.09)
	# 点亮普攻 / 技能后：把「能打到的范围」整体铺出来
	if pending_skill != "" and active >= 0:
		var rng := _pending_range()
		if rng > 0:
			var area := {}
			var sp: Vector2i = stacks[active].pos
			for yy in range(BROWS):
				for xx in range(BCOLS):
					var cc := Vector2i(xx, yy)
					if cc == sp or Hex.dist(sp, cc) > rng:
						continue
					area[Hex.key(cc)] = true
					Hex3D.add_face(st, cc, HEX_S, 0.86, ELEV + 0.035, Color(1.0, 0.42, 0.30, 0.16))
			if area.size() > 0:
				add_region_edges(st, area, HEX_S, func(_c: Vector2i) -> float: return ELEV + 0.042,
					Color(1.0, 0.52, 0.34, 0.95), 0.09)
	# 范围技能（aoe）的落点预览
	if pending_skill != "":
		var rad := _pending_radius()
		if rad > 0 and cmd_cell.x >= 0:
			for y in range(BROWS):
				for x in range(BCOLS):
					var cc := Vector2i(x, y)
					if Hex.dist(cc, cmd_cell) <= rad:
						Hex3D.add_face(st, cc, HEX_S, 0.80, ELEV + 0.05, Color(0.95, 0.55, 0.30, 0.20))
		if cmd_cell.x >= 0:
			Hex3D.add_outline(st, cmd_cell, HEX_S, 0.93, ELEV + 0.06, Color(1.0, 0.60, 0.25, 0.95), 0.10)
	if hover_cell.x >= 0:
		Hex3D.add_outline(st, hover_cell, HEX_S, 0.94, ELEV + 0.065, Color(1, 1, 1, 0.8), 0.08)
	overlay_mi.mesh = st.commit()

# ==================================================================== 棋子
func _make_unit(s: Dictionary) -> Node3D:
	var idx := int(s.idx)
	var u: Dictionary = DB.UNITS[s.unit]
	var col := Color(u.color)
	var fac := UI.C_BLUE if int(s.side) == 0 else UI.C_RED
	var node := Node3D.new()
	node.position = _cell_pos(s.pos)
	node.scale = Vector3(1.5, 1.5, 1.5)
	var holder := Node3D.new()
	node.add_child(holder)
	unit_holders[idx] = holder

	add_cyl(holder, Vector3(0, 0.05, 0), 0.34, 0.10, fac.darkened(0.45), 12)
	if int(u.range) > 2:
		add_cyl(holder, Vector3(0, 0.42, 0), 0.14, 0.72, col.darkened(0.25), 8, 0.06)
	else:
		var sz := Vector3(0.34, 0.56, 0.34) if int(u.tier) >= 4 else Vector3(0.30, 0.44, 0.30)
		add_box(holder, Vector3(0, 0.05 + sz.y * 0.5, 0), sz, col.darkened(0.3))
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.11
	sp.height = 0.22
	head.mesh = sp
	head.material_override = mat(col.lightened(0.25))
	head.position = Vector3(0, 0.82, 0)
	holder.add_child(head)

	var bar := Node3D.new()
	bar.position = Vector3(0, 1.22, 0)
	var bg := add_box(bar, Vector3.ZERO, Vector3(0.70, 0.09, 0.02), Color("#11151d"))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fill := add_box(bar, Vector3.ZERO, Vector3(0.70, 0.08, 0.03), UI.C_GREEN if int(s.side) == 0 else UI.C_RED)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.name = "Fill"
	holder.add_child(bar)
	unit_bars[idx] = bar

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
	holder.add_child(ring)
	unit_rings[idx] = ring

	unit_labels[idx] = add_label(holder, "×%d" % int(s.count), Vector3(0, 1.62, 0), col.lightened(0.2), 32)
	piece_root.add_child(node)
	var frac := float(s.top_hp) / float(maxf(1, int(u.hp)))
	unit_hp_frac[idx] = frac
	fill.scale.x = 0.70 * frac
	fill.position.x = -0.35 * (1.0 - frac)
	return node

func sync_units() -> void:
	for s in stacks:
		var idx := int(s.idx)
		if int(s.count) <= 0:
			if unit_nodes.has(idx) and not unit_dying.has(idx):
				_die(idx)
			continue
		if not unit_nodes.has(idx):
			unit_nodes[idx] = _make_unit(s)
		var node: Node3D = unit_nodes[idx]
		node.visible = true
		if not anim_ignore.has(idx):
			node.position = _cell_pos(s.pos)
		var u: Dictionary = DB.UNITS[s.unit]
		var l: Label3D = unit_labels[idx]
		if idx == active or inspect_idx == idx:
			l.text = "%s ×%d" % [u.name, int(s.count)]
			l.font_size = 38
		else:
			l.text = "×%d" % int(s.count)
			l.font_size = 32
		l.modulate = Color(u.color).lightened(0.2)
		unit_hp_frac[idx] = clampf(float(s.top_hp) / float(maxf(1, int(u.hp))), 0.0, 1.0)
		var ring: Node3D = unit_rings[idx]
		ring.visible = idx == active
		var tag := "防" if s.defending else ""
		var badge: Node = unit_holders[idx].get_node_or_null("Badge")
		if tag == "":
			if badge != null:
				badge.queue_free()
		elif badge == null:
			var bl := add_label(unit_holders[idx], tag, Vector3(0.36, 1.26, 0), UI.C_GOLD, 30)
			bl.name = "Badge"
		else:
			badge.text = tag

func _die(idx: int) -> void:
	if unit_dying.has(idx):
		return
	unit_dying[idx] = true
	var node: Node3D = unit_nodes.get(idx, null)
	if node == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector3(0.05, 0.05, 0.05), 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "position:y", node.position.y - 0.5, 0.34)
	tw.tween_property(node, "rotation:y", node.rotation.y + 2.2, 0.34)
	tw.set_parallel(false)
	tw.tween_callback(func(): node.visible = false)

func _process(delta: float) -> void:
	super(delta)
	# 血条平滑：数值已在规则层结算，这里把视觉追上去
	for idx in unit_bars.keys():
		var bar: Node3D = unit_bars[idx]
		var fill: MeshInstance3D = bar.get_node_or_null("Fill")
		if fill == null:
			continue
		var target: float = clampf(float(unit_hp_frac.get(idx, 1.0)), 0.02, 1.0)
		var cur: float = fill.scale.x / 0.70
		var nx: float = lerpf(cur, target, minf(1.0, delta * 7.0))
		fill.scale.x = 0.70 * nx
		fill.position.x = -0.35 * (1.0 - nx)
	# 技能已点亮：选中单位的金环做呼吸式放大，提示「正在选目标」
	if pending_skill != "" and active >= 0 and unit_rings.has(active):
		var pulse := 1.0 + 0.12 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.009))
		(unit_rings[active] as Node3D).scale = Vector3(pulse, 1.0, pulse)

# ==================================================================== 规则
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
	# 被动技能：开局永久加成攻击 / 防御 / 速度
	var ps: Dictionary = DB.unit_passive(uid)
	return {"idx": idx, "unit": uid, "count": maxi(1, count), "top_hp": int(u.hp),
			"side": side_id, "pos": pos, "acted": false, "retaliated": false,
			"defending": false, "waited": false, "buff_def": int(ps.get("def", 0)), "slow": 0,
			"atk_bonus": int(ps.get("atk", 0)), "spd_bonus": int(ps.get("spd", 0)), "cd": {}}

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
	return int(u.spd) + int(side_hero_stats(s.side).spd) - int(s.slow) + int(s.get("spd_bonus", 0))

func eff_atk(s: Dictionary) -> int:
	return int(DB.UNITS[s.unit].atk) + int(s.get("atk_bonus", 0))

func start_round() -> void:
	if finished:
		return
	hero_cast = false
	foe_cast = false
	for s in stacks:
		s.acted = false
		s.retaliated = false
		s.defending = false
		var cd: Dictionary = s.cd
		for k in cd.keys():
			cd[k] = maxi(0, int(cd[k]) - 1)
	order = []
	for s in stacks:
		if int(s.count) > 0:
			order.append(int(s.idx))
	var cmp := func(a, b2): return eff_speed(stacks[a]) > eff_speed(stacks[b2])
	order.sort_custom(cmp)
	turn_idx = 0
	pending_skill = ""
	active = -1
	reach = {}
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
	var i2: int = order[turn_idx]
	if int(stacks[i2].side) == 1:
		active = i2
		busy = true
		pending_skill = ""
		reach = {}
		hint.text = "敌方行动：%s" % DB.UNITS[stacks[i2].unit].name
		refresh_view()
		ai_act(i2)
	else:
		# 玩家回合：不锁定具体单位，等玩家点选任一未行动的我方单位
		active = -1
		busy = false
		pending_skill = ""
		reach = {}
		hint.text = "你的回合 · 点击我方单位选择行动（右键移动 / 选技能后点目标）"
		refresh_view()

func player_can_act() -> bool:
	return not finished and not busy and not anim_lock \
		and turn_idx < order.size() and int(stacks[order[turn_idx]].side) == 0

func recompute_reach() -> void:
	reach = {}
	if active < 0 or int(stacks[active].side) != 0:
		return
	if pending_skill != "":
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

# ==================================================================== 选择与指令
func select_unit(idx: int) -> void:
	if finished or busy or anim_lock:
		return
	if active >= 0:
		hint.text = "先结束当前单位的行动"
		return
	var s: Dictionary = stacks[idx]
	if int(s.side) != 0:
		inspect_idx = idx
		show_sheet()
		return
	if s.acted:
		hint.text = "%s 本回合已行动" % DB.UNITS[s.unit].name
		return
	if not player_can_act():
		hint.text = "现在还不能行动"
		return
	active = idx
	pending_skill = ""
	recompute_reach()
	center_on(_cell_pos(s.pos))
	hint.text = "已选择 %s：右键移动，或点下方普攻 / 技能后选目标" % DB.UNITS[s.unit].name
	refresh_view()

func deselect() -> void:
	if active < 0:
		return
	active = -1
	pending_skill = ""
	reach = {}
	hint.text = "点击我方单位选择行动"
	refresh_view()

func on_command(pos: Vector2) -> void:
	cmd_cell = Vector2i(-1, -1)
	var c := cell_at_screen(pos)
	if c.x < 0:
		build_overlay()
		return
	command_at(c)
	build_overlay()

func command_at(c: Vector2i) -> void:
	if finished or busy or anim_lock:
		return
	if pending_skill != "":
		use_pending(c)
		return
	if active < 0:
		hint.text = "先点击我方单位"
		return
	var target := stack_at(c)
	if target >= 0 and int(stacks[target].side) == 1:
		hint.text = "先用下方「普攻」或技能选中攻击方式"
		return
	if reach.has(Hex.key(c)) and cell_free(c):
		_do_move(active, c)
	else:
		hint.text = "该格无法到达，或已被占据"

func _do_move(idx: int, dest: Vector2i) -> void:
	var s: Dictionary = stacks[idx]
	var path := _path_from_reach(s.pos, dest)
	if path.is_empty():
		hint.text = "找不到路径"
		return
	anim_lock = true
	anim_ignore[idx] = true
	s.pos = dest
	reach = {}
	refresh_view()
	await move_along(idx, path)
	anim_ignore.erase(idx)
	anim_lock = false
	pending_skill = ""
	center_on(_cell_pos(dest))
	# 一次行动只能做一件事：移动完就结束，不能再攻击
	hint.text = "%s 移动完毕，本回合行动结束" % DB.UNITS[s.unit].name
	end_action()

func _path_from_reach(from: Vector2i, to: Vector2i) -> Array:
	if not reach.has(Hex.key(to)):
		return []
	var path: Array = []
	var cur := to
	var guard := 0
	while cur != from and guard < 64:
		guard += 1
		path.append(cur)
		var c := int(reach[Hex.key(cur)])
		var found := false
		for n in Hex.neighbors(cur):
			if n == from and c - 1 == 0:
				cur = from
				found = true
				break
			if reach.has(Hex.key(n)) and int(reach[Hex.key(n)]) == c - 1:
				cur = n
				found = true
				break
		if not found:
			return [to]
	path.reverse()
	return path

# ---------------------------------------------------------------- 技能
func arm_skill(sid: String) -> void:
	if finished or busy or anim_lock or active < 0:
		return
	if int(stacks[active].side) != 0:
		return
	# 统一成带前缀的 key：技能 "skill:<id>"，普攻 "attack"
	var key := sid if sid == "attack" else "skill:" + sid
	if pending_skill == key:
		pending_skill = ""
		recompute_reach()
		hint.text = "已取消"
		refresh_view()
		return
	if sid != "attack":
		if int(stacks[active].cd.get(sid, 0)) > 0:
			hint.text = "技能冷却中"
			return
		var sd: Dictionary = DB.UNIT_SKILLS.get(sid, {})
		if sd.is_empty():
			return
		if String(sd.type) == "buff_self":
			_apply_self_buff(sid)
			return
	pending_skill = key
	reach = {}
	var nm := "普攻"
	if sid != "attack":
		nm = String(DB.UNIT_SKILLS[sid].name)
	hint.text = "已选择「%s」：点击 / 右键 目标" % nm
	refresh_view()

func _pending_range() -> int:
	if active < 0:
		return 0
	if pending_skill == "attack":
		return int(DB.UNITS[stacks[active].unit].range)
	if pending_skill.begins_with("skill:"):
		return int(DB.UNIT_SKILLS.get(pending_skill.substr(6), {}).get("range", 1))
	if pending_skill.begins_with("spell:"):
		return 6
	return 0

func _pending_radius() -> int:
	if pending_skill == "attack" or pending_skill == "":
		return 0
	if pending_skill.begins_with("skill:"):
		var sd: Dictionary = DB.UNIT_SKILLS.get(pending_skill.substr(6), {})
		return int(sd.get("radius", 0))
	if pending_skill.begins_with("spell:"):
		var sp: Dictionary = DB.SPELLS.get(pending_skill.substr(6), {})
		return int(sp.get("radius", 0))
	return 0

func use_pending(c: Vector2i) -> void:
	if pending_skill == "":
		return
	if pending_skill == "attack":
		_use_attack(c)
	elif pending_skill.begins_with("skill:"):
		_use_skill(pending_skill.substr(6), c)
	elif pending_skill.begins_with("spell:"):
		_cast_hero_spell(c)

func _use_attack(c: Vector2i) -> void:
	var s: Dictionary = stacks[active]
	var u: Dictionary = DB.UNITS[s.unit]
	var t := stack_at(c)
	if t < 0 or int(stacks[t].side) != 1:
		hint.text = "请选择敌方单位"
		return
	var d := Hex.dist(s.pos, c)
	if d > int(u.range):
		hint.text = "超出射程（%d 格），先移动靠近" % int(u.range)
		return
	if int(u.range) <= 1 and d != 1:
		hint.text = "近战需要贴身"
		return
	var ranged := int(u.range) > 1 and d >= 2
	pending_skill = ""
	reach = {}
	anim_lock = true
	refresh_view()
	await _strike(active, t, ranged)
	attack(active, t, ranged)
	anim_lock = false
	if check_end():
		return
	end_action()

func _use_skill(sid: String, c: Vector2i) -> void:
	var sd: Dictionary = DB.UNIT_SKILLS.get(sid, {})
	if sd.is_empty():
		return
	var s: Dictionary = stacks[active]
	var dist := Hex.dist(s.pos, c)
	var srange := int(sd.get("range", 1))
	if dist > srange:
		hint.text = "超出施法距离（%d 格）" % srange
		return
	var typ := String(sd.type)
	if typ == "heal":
		var t2 := stack_at(c)
		if t2 < 0 or int(stacks[t2].side) != 0:
			hint.text = "请选择友军"
			return
	elif typ != "aoe" and typ != "line":
		var t3 := stack_at(c)
		if t3 < 0 or int(stacks[t3].side) != 1:
			hint.text = "请选择敌方单位"
			return
	pending_skill = ""
	reach = {}
	anim_lock = true
	refresh_view()
	stacks[active].cd[sid] = int(sd.get("cd", 1))
	if typ == "heal":
		await _strike(active, -1, false, _cell_pos(stacks[stack_at(c)].pos))
		_heal_ally(stack_at(c), float(sd.get("mult", 0.6)))
	elif typ == "line":
		await _strike(active, -1, true, _cell_pos(c))
		for t in stacks:
			if int(t.count) > 0 and int(t.side) == 1 and t.pos.y == c.y:
				_skill_damage(active, t, float(sd.get("mult", 1.0)))
	elif typ == "aoe":
		await _strike(active, -1, true, _cell_pos(c))
		_aoe_burst(c, int(sd.get("radius", 1)), Color(sd.get("color", "#e0a060")))
		for t in stacks:
			if int(t.count) > 0 and int(t.side) == 1 and Hex.dist(t.pos, c) <= int(sd.get("radius", 1)):
				_skill_damage(active, t, float(sd.get("mult", 1.0)), int(sd.get("slow", 0)))
	else:
		var tg := stack_at(c)
		await _strike(active, tg, srange > 1)
		_skill_damage(active, stacks[tg], float(sd.get("mult", 1.0)), int(sd.get("slow", 0)))
		if int(sd.get("mana", 0)) > 0:
			mana = mini(Game.max_mana(h), mana + int(sd.mana))
	add_log("%s 施放「%s」。" % [DB.UNITS[s.unit].name, String(sd.name)])
	anim_lock = false
	if check_end():
		return
	end_action()

func _apply_self_buff(sid: String) -> void:
	var sd: Dictionary = DB.UNIT_SKILLS[sid]
	var s: Dictionary = stacks[active]
	s.cd[sid] = int(sd.get("cd", 1))
	if int(sd.get("atk", 0)) > 0:
		s.atk_bonus = int(s.atk_bonus) + int(sd.atk)
	if int(sd.get("def", 0)) > 0:
		s.buff_def = int(s.buff_def) + int(sd.def)
	s.defending = true
	_burst(_cell_pos(s.pos) + Vector3(0, 0.5, 0), Color(sd.get("color", "#d8b45a")), 2.4)
	_float_text(_cell_pos(s.pos) + Vector3(0, 1.5, 0), String(sd.name), UI.C_GOLD, 42)
	add_log("%s 施放「%s」。" % [DB.UNITS[s.unit].name, String(sd.name)])
	hint.text = "「%s」生效" % String(sd.name)
	end_action()

func _heal_ally(idx: int, mult: float) -> void:
	var t: Dictionary = stacks[idx]
	var u: Dictionary = DB.UNITS[t.unit]
	var src: Dictionary = stacks[active]
	var amount := int(float(int(src.count) * eff_atk(src)) * mult)
	var pool := DB.unit_hp_pool(int(t.count), int(t.top_hp), t.unit) + amount
	t.count = int(ceil(float(pool) / float(u.hp)))
	t.top_hp = pool - (int(t.count) - 1) * int(u.hp)
	_float_text(_cell_pos(t.pos) + Vector3(0, 1.4, 0), "+%d" % amount, UI.C_GREEN, 46)
	add_log("%s 治疗了 %s（+%d）。" % [DB.UNITS[src.unit].name, u.name, amount])

func _skill_damage(src_idx: int, t: Dictionary, mult: float, slow := 0) -> void:
	var src: Dictionary = stacks[src_idx]
	if int(t.count) <= 0:
		return
	var au: Dictionary = DB.UNITS[src.unit]
	var tu: Dictionary = DB.UNITS[t.unit]
	var ah := side_hero_stats(int(src.side))
	var dh := side_hero_stats(int(t.side))
	var atk_bonus := 1.0 + 0.05 * float(int(ah.atk) - int(dh.def)) + 0.08 * float(side_skill(int(src.side), "offense"))
	var def_bonus := 1.0 + 0.05 * float(int(dh.def) - int(ah.atk)) + 0.06 * float(side_skill(int(t.side), "armorer"))
	var reduction: float = clampf(0.03 * float(int(tu.def)) * def_bonus, 0.0, 0.62)
	var dmg: float = float(int(src.count)) * float(eff_atk(src)) * mult * maxf(0.35, atk_bonus) * (1.0 - reduction)
	if t.defending:
		dmg *= 0.75
	if int(t.buff_def) > 0:
		dmg *= maxf(0.5, 1.0 - 0.05 * float(t.buff_def))
	dmg *= rng.randf_range(0.92, 1.08)
	var before := int(t.count)
	apply_damage(t, dmg)
	_hit_fx(int(t.idx), int(dmg), Color("#ffb070"))
	if slow > 0:
		t.slow = int(t.slow) + slow
	add_log("%s 命中 %s，造成 %d 点伤害（消灭 %d）。" % [au.name, tu.name, int(dmg), before - int(t.count)])

# ---------------------------------------------------------------- 普攻规则（含反击）
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
	var dmg: float = float(int(a.count)) * float(eff_atk(a)) * maxf(0.35, atk_bonus) * (1.0 - reduction)
	if ranged and Hex.dist(a.pos, t.pos) <= 1:
		dmg *= 0.5
	if t.defending:
		dmg *= 0.75
	if int(t.buff_def) > 0:
		dmg *= maxf(0.5, 1.0 - 0.05 * float(t.buff_def))
	dmg *= rng.randf_range(0.9, 1.1)
	var before := int(t.count)
	apply_damage(t, dmg)
	_hit_fx(int(t.idx), int(dmg), Color("#ffd27a"))
	add_log("%s %s %s，造成 %d 点伤害，消灭 %d 个。" % [au.name, "射击" if ranged else "攻击", tu.name, int(dmg), before - int(t.count)])
	if int(t.count) > 0 and not ranged and not t.retaliated and Hex.dist(a.pos, t.pos) <= 1 and int(DB.UNITS[t.unit].range) <= 2:
		t.retaliated = true
		var rdmg: float = float(int(t.count)) * float(eff_atk(t)) * 0.6 * (1.0 - clampf(0.03 * float(int(au.def)), 0.0, 0.5))
		apply_damage(a, rdmg)
		_hit_fx(int(a.idx), int(rdmg), Color("#ff8f6a"))
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

# ==================================================================== 动画
func move_along(idx: int, path: Array) -> void:
	var node: Node3D = unit_nodes.get(idx, null)
	var holder: Node3D = unit_holders.get(idx, null)
	if node == null:
		return
	for c in path:
		var target := _cell_pos(c)
		var tw := create_tween()
		tw.tween_property(node, "position", target, MOVE_T).set_trans(Tween.TRANS_SINE)
		if holder != null:
			var tw2 := create_tween()
			tw2.tween_property(holder, "position:y", 0.16, MOVE_T * 0.5)
			tw2.tween_property(holder, "position:y", 0.0, MOVE_T * 0.5)
		await tw.finished

## 出手动作：近战前冲再回位，远程射出一发光弹
func _strike(a_idx: int, t_idx: int, ranged: bool, target_pos := Vector3.ZERO) -> void:
	var node: Node3D = unit_nodes.get(a_idx, null)
	if node == null:
		return
	var dest := target_pos
	if dest == Vector3.ZERO and t_idx >= 0:
		dest = _cell_pos(stacks[t_idx].pos)
	if ranged:
		_shoot(node.position + Vector3(0, 0.95, 0), dest + Vector3(0, 0.5, 0), Color(DB.UNITS[stacks[a_idx].unit].color))
		await get_tree().create_timer(0.18).timeout
	else:
		var holder: Node3D = unit_holders.get(a_idx, null)
		if holder == null:
			return
		var dir := Vector3(dest.x - node.position.x, 0, dest.z - node.position.z)
		if dir.length() > 0.01:
			dir = dir.normalized()
		var tw := create_tween()
		tw.tween_property(holder, "position", dir * 0.55, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(holder, "position", Vector3.ZERO, 0.16)
		await tw.finished

func _shoot(from: Vector3, to: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.13
	sp.height = 0.26
	mi.mesh = sp
	mi.material_override = mat(col.lightened(0.3), true)
	mi.position = from
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "position", to, 0.2).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(mi.queue_free)

func _hit_fx(idx: int, dmg: int, col: Color) -> void:
	var node: Node3D = unit_nodes.get(idx, null)
	if node == null:
		return
	var holder: Node3D = unit_holders.get(idx, null)
	_burst(node.position + Vector3(0, 0.6, 0), col)
	_float_text(node.position + Vector3(0.35, 2.35, 0), "-%d" % dmg, col, 64)
	if holder != null:
		var tw := create_tween()
		tw.tween_property(holder, "scale", Vector3(1.14, 0.86, 1.14), 0.07)
		tw.tween_property(holder, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_ELASTIC)

func _aoe_burst(c: Vector2i, _radius: int, col: Color) -> void:
	_burst(_cell_pos(c) + Vector3(0, 0.3, 0), col, 2.6)

func _burst(pos: Vector3, col: Color, grow: float = 1.8) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.22
	sp.height = 0.44
	mi.mesh = sp
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = pos
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(grow, grow, grow), 0.3)
	tw.tween_property(m, "albedo_color", Color(col.r, col.g, col.b, 0.0), 0.3)
	tw.set_parallel(false)
	tw.tween_callback(mi.queue_free)

func _float_text(pos: Vector3, text: String, col: Color, size: int = 44) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font()
	l.font_size = size
	l.pixel_size = 0.013
	l.modulate = col
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = pos
	fx_root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", pos + Vector3(0.2, 1.25, 0), 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.85)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)

# ==================================================================== 行动结束
func end_action() -> void:
	if active >= 0:
		stacks[active].acted = true
	active = -1
	pending_skill = ""
	turn_idx += 1
	reach = {}
	next_turn()

func action_defend() -> void:
	if finished or busy or anim_lock or active < 0:
		return
	stacks[active].defending = true
	add_log("%s 进入防御姿态。" % DB.UNITS[stacks[active].unit].name)
	end_action()

# ---------------------------------------------------------------- 英雄法术
func select_spell(sid: String) -> void:
	if finished or busy or anim_lock or active < 0 or int(stacks[active].side) != 0:
		hint.text = "请先选择一个我方单位"
		return
	if hero_cast:
		hint.text = "本回合英雄已经施法"
		return
	if int(DB.SPELLS[sid].cost) > mana:
		hint.text = "魔法值不足"
		return
	pending_skill = "spell:" + sid
	if DB.SPELLS[sid].type == "drain_all":
		_cast_hero_spell(Vector2i(-1, -1))
		return
	reach = {}
	hint.text = "施法模式：点击 / 右键 选择目标（「%s」）" % DB.SPELLS[sid].name
	refresh_view()

func _cast_hero_spell(c: Vector2i) -> void:
	var sid := pending_skill.substr(6)
	if not DB.SPELLS.has(sid):
		pending_skill = ""
		return
	var sd: Dictionary = DB.SPELLS[sid]
	var cost := int(sd.cost)
	if cost > mana:
		hint.text = "魔法值不足"
		pending_skill = ""
		return
	var typ := String(sd.type)
	var power := float(sd.power) * (1.0 + 0.18 * float(side_skill(0, "sorcery"))) * (1.0 + 0.05 * float(Game.hero_stats(h).power))
	var hit := 0
	if typ == "drain_all":
		for s in stacks:
			if s.side == 1 and int(s.count) > 0:
				apply_damage(s, power * 0.7)
				_hit_fx(int(s.idx), int(power * 0.7), Color("#c58be8"))
				hit += 1
		mana = mini(Game.max_mana(h), mana + 4)
	elif typ == "line":
		for s in stacks:
			if s.side == 1 and int(s.count) > 0 and s.pos.y == c.y:
				apply_damage(s, power)
				_hit_fx(int(s.idx), int(power), Color("#ffd27a"))
				hit += 1
	elif typ == "aoe":
		_aoe_burst(c, int(sd.radius), Color("#86c9e0"))
		for s in stacks:
			if s.side == 1 and int(s.count) > 0 and Hex.dist(s.pos, c) <= int(sd.radius):
				apply_damage(s, power)
				_hit_fx(int(s.idx), int(power), Color("#86c9e0"))
				hit += 1
	elif typ == "single":
		var t := stack_at(c)
		if t < 0 or stacks[t].side != 1:
			hint.text = "请选择一支敌军"
			return
		apply_damage(stacks[t], power)
		_hit_fx(t, int(power), Color("#ffd27a"))
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
		_float_text(_cell_pos(stacks[t2].pos) + Vector3(0, 1.4, 0), "+%d" % int(power), UI.C_GREEN, 46)
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
	pending_skill = ""
	recompute_reach()
	if check_end():
		return
	refresh_view()

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
	_hit_fx(target, int(dmg), Color("#c58be8"))
	add_log("%s 施放了奥术弹，突袭我军！" % foe.name)

# ==================================================================== AI
func ai_act(idx: int) -> void:
	await get_tree().create_timer(0.32).timeout
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
	var rng := int(u.range)
	# AI 与玩家同规则：一次行动只能打或只能走
	if d <= rng:
		var shot := rng > 1 and d >= 2
		await _strike(idx, target, shot)
		attack(idx, target, shot)
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
			var path := _bfs_path(s.pos, best_cell, int(u.move))
			s.pos = best_cell
			if not path.is_empty():
				anim_ignore[idx] = true
				center_on(_cell_pos(best_cell))
				refresh_view()
				await move_along(idx, path)
				anim_ignore.erase(idx)
				refresh_view()
	busy = false
	if check_end():
		return
	end_action()

func _bfs_path(from: Vector2i, to: Vector2i, max_steps: int) -> Array:
	var one := func(_c: Vector2i) -> int: return 1
	var free_fn := func(c: Vector2i) -> bool: return cell_free(c) or c == to
	var f := Hex.flood(from, max_steps, one, free_fn)
	if not f.has(Hex.key(to)):
		return []
	var path: Array = []
	var cur := to
	var guard := 0
	while cur != from and guard < 64:
		guard += 1
		path.append(cur)
		var c := int(f[Hex.key(cur)])
		var found := false
		for n in Hex.neighbors(cur):
			if n == from and c - 1 == 0:
				cur = from
				found = true
				break
			if f.has(Hex.key(n)) and int(f[Hex.key(n)]) == c - 1:
				cur = n
				found = true
				break
		if not found:
			return [to]
	path.reverse()
	return path

func has_adjacent_enemy(s: Dictionary) -> bool:
	for n in Hex.neighbors(s.pos):
		var t := stack_at(n)
		if t >= 0 and stacks[t].side != s.side:
			return true
	return false

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
	side.offset_bottom = -96
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
	actions.offset_top = -88
	actions.offset_bottom = -12
	actions.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(actions)
	action_row = UI.hbox(6)
	actions.add_child(action_row)

	hint = UI.label("战斗开始 · 点击我方单位选择行动", 13, UI.C_GOLD)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.position = Vector2(18, 80)
	add_child(hint)

func refresh_view() -> void:
	if not is_instance_valid(topbar):
		return
	build_overlay()
	sync_units()
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
	hud_row.add_child(UI.bar(float(mana), float(Game.max_mana(h)), UI.C_PURPLE, 110, 10))
	hud_row.add_child(UI.label("VS", 15, UI.C_GOLD))
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
	side_box.add_child(UI.title("行动顺序", 16))
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
		if bool(s.acted):
			l.add_theme_color_override("font_color", UI.C_MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.label("速%d" % eff_speed(s), 11, UI.C_MUTED))
		side_box.add_child(row)
	side_box.add_child(UI.line(UI.C_GOLD_DIM))
	side_box.add_child(UI.title("英雄法术", 16))
	side_box.add_child(nowrap("每回合 1 次，不占用部队行动" + ("（已施法）" if hero_cast else ""), 11, UI.C_MUTED))
	for sid in h.spells:
		var sd: Dictionary = DB.SPELLS[sid]
		var btn := UI.button("%s  %d魔" % [sd.name, int(sd.cost)], Callable(self, "select_spell").bind(sid), 12, Vector2(0, 32), UI.C_PURPLE)
		btn.disabled = hero_cast or int(sd.cost) > mana or finished or busy or active < 0
		if pending_skill == "spell:" + sid:
			btn.text = "◆ " + String(sd.name)
		side_box.add_child(btn)
	side_box.add_child(UI.line(UI.C_GOLD_DIM))
	side_box.add_child(UI.title("战斗记录", 15))
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
	var can := not finished and not busy and not anim_lock and active >= 0 and int(stacks[active].side) == 0
	if active < 0:
		action_row.add_child(nowrap("点击我方单位开始行动", 14, UI.C_MUTED))
		var sp0 := Control.new()
		sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_row.add_child(sp0)
		var ba0 := UI.button("自动战斗", auto_battle, 14, Vector2(120, 40), UI.C_GREEN)
		ba0.disabled = finished
		action_row.add_child(ba0)
		var br0 := UI.button("撤退", func(): finish(false), 13, Vector2(84, 40), UI.C_RED)
		br0.disabled = finished
		action_row.add_child(br0)
		return
	var s: Dictionary = stacks[active]
	var atk_btn := UI.button("普攻", Callable(self, "arm_skill").bind("attack"), 15, Vector2(96, 48), UI.C_GOLD)
	atk_btn.disabled = not can
	atk_btn.tooltip_text = "普通攻击（近战会被反击）\n射程 %d 格" % int(DB.UNITS[s.unit].range)
	if pending_skill == "attack":
		atk_btn.text = "◆ 普攻 · 选目标"
		atk_btn.add_theme_stylebox_override("normal", UI.sb(Color("#4a3212"), Color("#ffc65a"), 5, 2))
		atk_btn.add_theme_stylebox_override("hover", UI.sb(Color("#5a3d16"), Color("#ffd77a"), 5, 2))
	action_row.add_child(atk_btn)
	# 唯一的主动技能
	var asid := DB.unit_active(s.unit)
	if DB.UNIT_SKILLS.has(asid):
		var sd: Dictionary = DB.UNIT_SKILLS[asid]
		var cd := int(s.cd.get(asid, 0))
		var txt := "◆ " + String(sd.name)
		if cd > 0:
			txt += "  CD %d" % cd
		var ab := UI.button(txt, Callable(self, "arm_skill").bind(asid), 14, Vector2(126, 48), Color(sd.get("color", "#b48ae0")))
		ab.disabled = (not can) or cd > 0
		ab.tooltip_text = "%s\n%s\n射程 %d 格 · 冷却 %d 回合" % [
			String(sd.name), String(sd.desc), int(sd.get("range", 1)), int(sd.cd)]
		if pending_skill == "skill:" + asid:
			ab.text = "◆ " + String(sd.name) + " · 选目标"
			ab.add_theme_stylebox_override("normal", UI.sb(Color("#3a2450"), Color("#d8a6ff"), 5, 2))
			ab.add_theme_stylebox_override("hover", UI.sb(Color("#472c60"), Color("#e8c0ff"), 5, 2))
		action_row.add_child(ab)
	# 被动技能：只展示，不可点
	var ps: Dictionary = DB.unit_passive(s.unit)
	if not ps.is_empty():
		var chip := UI.panel(Color("#1f2a33"), UI.C_GREEN, 5)
		chip.custom_minimum_size = Vector2(176, 48)
		var cv := UI.vbox(2)
		chip.add_child(cv)
		cv.add_child(UI.label("被动 · " + String(ps.name), 12, UI.C_GREEN))
		cv.add_child(UI.label(String(ps.desc), 10, UI.C_MUTED))
		chip.tooltip_text = "被动技能，开局自动生效"
		action_row.add_child(chip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(sp)
	var bd := UI.button("防御", action_defend, 13, Vector2(72, 48), UI.C_MUTED)
	bd.disabled = not can
	action_row.add_child(bd)
	var be := UI.button("结束行动", end_action, 13, Vector2(88, 48), UI.C_MUTED)
	be.disabled = not can
	action_row.add_child(be)
	var ba := UI.button("自动战斗", auto_battle, 12, Vector2(104, 40), UI.C_GREEN)
	ba.disabled = finished
	action_row.add_child(ba)
	var br := UI.button("撤退", func(): finish(false), 12, Vector2(68, 40), UI.C_RED)
	br.disabled = finished
	action_row.add_child(br)

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
	left.add_child(nowrap("攻 %d  防 %d  速 %d  射程 %d" % [eff_atk(s), int(u.def), eff_speed(s), int(u.range)], 14, UI.C_TEXT))
	var mid := UI.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	mid.add_child(UI.label("技 能", 13, UI.C_MUTED))
	var asid := DB.unit_active(s.unit)
	if DB.UNIT_SKILLS.has(asid):
		var sd: Dictionary = DB.UNIT_SKILLS[asid]
		var cd := int(s.cd.get(asid, 0))
		mid.add_child(nowrap("主动 · %s%s（射程 %d 格，CD %d）" % [String(sd.name),
			("，剩 %d 回合" % cd) if cd > 0 else "，可用", int(sd.get("range", 1)), int(sd.cd)], 12, Color(sd.get("color", "#b48ae0"))))
		mid.add_child(nowrap(String(sd.desc), 11, UI.C_TEXT))
	var ps: Dictionary = DB.unit_passive(s.unit)
	if not ps.is_empty():
		mid.add_child(nowrap("被动 · %s — %s" % [String(ps.name), String(ps.desc)], 12, UI.C_GREEN))
	var right := UI.vbox(8)
	right.custom_minimum_size = Vector2(170, 0)
	row.add_child(right)
	right.add_child(UI.ghost_button("关闭", hide_sheet, 14))

# ==================================================================== 输入
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
	# 点亮普攻/技能时，左键直接对目标释放
	if pending_skill != "":
		use_pending(c)
		return
	var idx := stack_at(c)
	if idx < 0:
		if active >= 0:
			deselect()
		else:
			hide_sheet()
		return
	if int(stacks[idx].side) == 0:
		if active < 0:
			select_unit(idx)
		else:
			hint.text = "已选中 %s，先结束其行动" % DB.UNITS[stacks[active].unit].name
		return
	inspect_idx = idx
	show_sheet()

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
		if pending_skill != "":
			cmd_cell = c
		build_overlay()
