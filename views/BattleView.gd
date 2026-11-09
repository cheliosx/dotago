class_name BattleView
extends Control

const BCOLS := 13
const BROWS := 9

class BattleBoard extends Control:
	const BCOLS := 13
	const BROWS := 9
	var view: Control = null
	var hex_size := 30.0
	var origin := Vector2.ZERO
	var hover := Vector2i(-1, -1)

	func txt(pos: Vector2, s: String, fs: int, col: Color, centered: bool = true) -> void:
		var f := UI.font()
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(pos.x - (w / 2.0 if centered else 0.0), pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func poly(c: Vector2i, shrink: float = 0.0) -> PackedVector2Array:
		var p := Hex.polygon(c, hex_size - shrink)
		var out := PackedVector2Array()
		for v in p:
			out.append(v + origin)
		return out

	func _draw() -> void:
		if view == null or size.x < 10:
			return
		var dw := Hex.SQRT3 * (float(BCOLS) + 0.5) + 1.0
		var dh := 1.5 * float(BROWS - 1) + 2.0
		hex_size = clampf(minf((size.x - 18) / dw, (size.y - 18) / dh), 16.0, 48.0)
		var bw := dw * hex_size
		var bh := dh * hex_size
		origin = Vector2((size.x - bw) / 2.0 + Hex.SQRT3 * hex_size / 2.0, (size.y - bh) / 2.0 + hex_size)

		var biome: String = view.biome
		var base_col := Color(DB.TERRAIN.get(biome, DB.TERRAIN.plain).color).darkened(0.28)
		for y in range(BROWS):
			for x in range(BCOLS):
				var c := Vector2i(x, y)
				var pts := poly(c, 1.0)
				var col := base_col
				if (x + y) % 2 == 0:
					col = col.lightened(0.045)
				# 双方部署区的阵营色调
				if x <= 2:
					col = col.lerp(Color("#1d4f68"), 0.42)
				elif x >= BCOLS - 3:
					col = col.lerp(Color("#692a2a"), 0.40)
				elif x == 6:
					col = col.lightened(0.05)
				draw_colored_polygon(pts, col)
				for i in range(6):
					draw_line(pts[i], pts[(i + 1) % 6], Color("#0b0e14", 0.55), 1.0)
		# 施法模式：全场淡紫提示
		if view.mode == "spell":
			for y in range(BROWS):
				for x in range(BCOLS):
					var c := Vector2i(x, y)
					draw_colored_polygon(poly(c, 3.0), Color("#b48ae0", 0.10))
		# 可达格
		if view.mode != "spell":
			for key in view.reach:
				var c := Hex.from_key(key)
				var pts := poly(c, 3.0)
				draw_colored_polygon(pts, Color("#5fb8e8", 0.20))
				for i in range(6):
					draw_line(pts[i], pts[(i + 1) % 6], Color("#8fd6f5", 0.55), 1.3)
		# 障碍物
		for o in view.obstacles:
			var p := Hex.center(o, hex_size) + origin
			var rock := PackedVector2Array([p + Vector2(-15, 9), p + Vector2(-8, -9), p + Vector2(6, -12), p + Vector2(15, 5), p + Vector2(9, 11)])
			draw_colored_polygon(rock, Color("#545866"))
			draw_polyline(rock + PackedVector2Array([rock[0]]), Color("#868b99"), 1.5)
		# 单位
		for s in view.stacks:
			if int(s.count) <= 0:
				continue
			draw_stack(s)
		# 悬停
		if hover.x >= 0:
			var pts := poly(hover, 1.0)
			for i in range(6):
				draw_line(pts[i], pts[(i + 1) % 6], Color("#ffffff", 0.75), 2.0)

	func draw_stack(s: Dictionary) -> void:
		var u: Dictionary = DB.UNITS[s.unit]
		var p := Hex.center(s.pos, hex_size) + origin
		var col := Color(u.color)
		var border := UI.C_BLUE if s.side == 0 else UI.C_RED
		var r := hex_size * 0.62
		if int(s.idx) == view.active:
			draw_arc(p, r + 6, 0, TAU, 48, UI.C_GOLD, 3.0)
		draw_circle(p + Vector2(0, 3), r + 2, Color(0, 0, 0, 0.45))
		draw_circle(p, r, col.darkened(0.72))
		draw_arc(p, r, 0, TAU, 42, border, 2.5)
		txt(p + Vector2(0, 7), String(u.name).substr(0, 1), 20, col.lightened(0.45))
		# 数量牌
		var badge := Rect2(p.x - 19, p.y + r - 4, 38, 17)
		draw_rect(badge, Color("#0c1019", 0.95), true)
		draw_rect(badge, border, false, 1.2)
		txt(p + Vector2(0, r + 9), "×" + str(s.count), 12, Color.WHITE)
		# 生命条（顶部单位剩余血量）
		var frac := clampf(float(s.top_hp) / float(maxf(1, int(u.hp))), 0.0, 1.0)
		var bw := r * 1.7
		draw_rect(Rect2(p.x - bw / 2.0, p.y - r - 9, bw, 4), Color("#11151d"))
		draw_rect(Rect2(p.x - bw / 2.0, p.y - r - 9, bw * frac, 4), UI.C_GREEN if s.side == 0 else UI.C_RED)
		if int(s.buff_def) > 0:
			txt(p + Vector2(0, -r - 13), "霜甲", 10, UI.C_BLUE)
		if s.defending:
			txt(p + Vector2(0, -r - 13), "防御", 10, UI.C_GOLD)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var c := pick(event.position)
			if c != hover:
				hover = c
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var c := pick(event.position)
			if c.x >= 0 and view.has_method("on_board_click"):
				view.call("on_board_click", c)

	func pick(p: Vector2) -> Vector2i:
		var cells := []
		for y in range(BROWS):
			for x in range(BCOLS):
				cells.append(Vector2i(x, y))
		return Hex.nearest(p - origin, hex_size, cells)

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

var header: HBoxContainer
var body: HBoxContainer
var actions: HBoxContainer
var side: VBoxContainer
var hint: Label
var board: BattleBoard

func setup(p: Dictionary) -> void:
	pass

func _ready() -> void:
	rng.randomize()
	# 浅拷贝：保留 ref 对真实矿场 / 城镇 / 英雄的引用，战后才能正确结算归属
	b = Game.pending_battle.duplicate(false)
	if b.is_empty():
		Game.goto("world", {})
		return
	h = Game.hero(int(b.hero_id))
	foe = b.enemy_hero
	biome = String(b.get("biome", "plain"))
	mana = int(h.mana)
	build_ui()
	setup_stacks()
	start_round()

func build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(k, 14)
	add_child(margin)
	var v := UI.vbox(8)
	margin.add_child(v)
	header = UI.hbox(10)
	header.custom_minimum_size = Vector2(0, 50)
	v.add_child(header)
	body = UI.hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var frame := UI.panel(Color("#0e121b"), UI.C_BORDER, 8)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 3.0
	body.add_child(frame)
	board = BattleBoard.new()
	board.view = self
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(board)
	var sf := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	sf.custom_minimum_size = Vector2(268, 0)
	body.add_child(sf)
	var sc := UI.scroll(UI.vbox(9))
	sf.add_child(sc)
	side = sc.get_child(0)
	actions = UI.hbox(8)
	actions.custom_minimum_size = Vector2(0, 50)
	v.add_child(actions)
	hint = UI.label("战斗开始", 14, UI.C_GOLD)
	hint.custom_minimum_size = Vector2(0, 24)
	v.add_child(hint)

func setup_stacks() -> void:
	var p_slots := [Vector2i(2, 1), Vector2i(2, 3), Vector2i(2, 5), Vector2i(2, 7), Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 6)]
	var e_slots := [Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5), Vector2i(10, 7), Vector2i(12, 2), Vector2i(12, 4), Vector2i(12, 6)]
	obstacles = [Vector2i(6, 0), Vector2i(6, 8), Vector2i(5, 4), Vector2i(7, 4)]
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
		hint.text = "轮到 %s（速度 %d）· 点击蓝色格移动，点击敌军攻击" % [DB.UNITS[stacks[active].unit].name, eff_speed(stacks[active])]
	refresh_ui()
	board.queue_redraw()

func recompute_reach() -> void:
	reach = {}
	if active < 0 or stacks[active].side != 0 or mode == "spell":
		return
	var s: Dictionary = stacks[active]
	var u: Dictionary = DB.UNITS[s.unit]
	var me: Node = self
	var cost_fn := func(c: Vector2i) -> int: return 1
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

# ------------------------------------------------------------- 玩家输入
func on_board_click(c: Vector2i) -> void:
	if finished or busy or active < 0 or stacks[active].side != 0:
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
	if best_d <= 1:
		return best
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
	if finished or busy or active < 0 or stacks[active].side != 0:
		return
	stacks[active].defending = true
	add_log("%s 进入防御姿态。" % DB.UNITS[stacks[active].unit].name)
	end_action()

func action_wait() -> void:
	if finished or busy or active < 0 or stacks[active].side != 0:
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
	if finished or busy or active < 0 or stacks[active].side != 0:
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
	add_log("选择法术「%s」，点击目标格施放。" % DB.SPELLS[sid].name)
	if DB.SPELLS[sid].type == "drain_all":
		cast_spell(Vector2i(-1, -1))
		return
	hint.text = "施法模式：点击目标（友军法术请点我方单位）"
	refresh_ui()
	board.queue_redraw()

func cancel_spell() -> void:
	mode = "normal"
	spell_id = ""
	recompute_reach()
	refresh_ui()
	board.queue_redraw()

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
			hint.text = "请点击一支敌军"
			return
		apply_damage(stacks[t], power)
		hit = 1
	elif typ == "heal":
		var t2 := stack_at(c)
		if t2 < 0 or stacks[t2].side != 0:
			hint.text = "请点击一支友军"
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
			hint.text = "请点击一支友军"
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
	refresh_ui()
	board.queue_redraw()

# ------------------------------------------------------------- 伤害与攻击
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

# ------------------------------------------------------------- AI
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
		var one := func(c: Vector2i) -> int: return 1
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
	while not finished and guard < 200:
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
	board.queue_redraw()

# ------------------------------------------------------------- 结束
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

# ------------------------------------------------------------- 界面刷新
func refresh_ui() -> void:
	if not is_instance_valid(header):
		return
	for c in header.get_children():
		header.remove_child(c)
		c.queue_free()
	for c in actions.get_children():
		actions.remove_child(c)
		c.queue_free()
	for c in side.get_children():
		side.remove_child(c)
		c.queue_free()

	header.add_child(UI.label("◆ %s  Lv.%d" % [h.name, h.level], 19, UI.C_BLUE))
	header.add_child(UI.label("魔法 %d / %d" % [mana, Game.max_mana(h)], 15, UI.C_PURPLE))
	header.add_child(UI.bar(float(mana), float(Game.max_mana(h)), UI.C_PURPLE, 130, 10))
	header.add_child(UI.label("VS", 17, UI.C_GOLD))
	header.add_child(UI.label("▲ %s" % String(foe.name), 18, UI.C_RED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	header.add_child(UI.label("第 %d 回合" % round_no, 17, UI.C_GOLD))
	header.add_child(UI.label("我方 %d / 敌方 %d" % [alive_count(0), alive_count(1)], 14, UI.C_MUTED))

	var can_act: bool = not finished and not busy and active >= 0 and int(stacks[active].side) == 0
	actions.add_child(UI.button("防御", func(): action_defend(), 15, Vector2(100, 42), UI.C_MUTED))
	actions.add_child(UI.button("等待", func(): action_wait(), 15, Vector2(100, 42), UI.C_MUTED))
	actions.add_child(UI.button("自动战斗", func(): auto_battle(), 15, Vector2(130, 42), UI.C_GREEN))
	actions.add_child(UI.button("撤退", func(): finish(false), 14, Vector2(90, 42), UI.C_RED))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(sp2)
	var tip := UI.label("远程贴身减半 · 每回合可施法一次", 13, UI.C_MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_OFF
	actions.add_child(tip)
	for a in actions.get_children():
		if a is Button:
			a.disabled = not can_act

	side.add_child(UI.title("行动顺序", 18))
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
		side.add_child(row)
	side.add_child(UI.line(UI.C_GOLD_DIM))
	side.add_child(UI.title("英雄法术", 18))
	side.add_child(UI.label("本回合%s" % ("已施法" if hero_cast else "可施法 1 次"), 12, UI.C_MUTED))
	for sid in h.spells:
		var sd: Dictionary = DB.SPELLS[sid]
		var btn := UI.button("%s  %d魔" % [sd.name, int(sd.cost)], Callable(self, "select_spell").bind(sid), 13, Vector2(0, 36), UI.C_PURPLE)
		btn.disabled = hero_cast or int(sd.cost) > mana or not can_act or finished
		if spell_id == sid:
			btn.text = "◆ " + String(sd.name)
		side.add_child(btn)
		if spell_id == sid:
			var d := UI.label(String(sd.desc), 11, UI.C_MUTED)
			d.custom_minimum_size = Vector2(230, 0)
			side.add_child(d)
	if mode == "spell":
		side.add_child(UI.button("取消施法", func(): cancel_spell(), 13, Vector2(0, 34), UI.C_RED))
	side.add_child(UI.line(UI.C_GOLD_DIM))
	side.add_child(UI.title("战斗记录", 17))
	var n := 0
	for l2 in log_lines:
		if n >= 9:
			break
		var jl := UI.label("· " + String(l2), 11, UI.C_MUTED)
		jl.custom_minimum_size = Vector2(230, 0)
		side.add_child(jl)
		n += 1
