extends Node
## 全局游戏状态（Autoload 名：Game）
## 负责：世界生成、移动力与寻路、回合结算、经济、AI、战斗前后结算。

signal changed
signal goto_view(view: String, payload: Dictionary)
signal toast(text: String)
signal popup(title: String, body: String, cb: Callable)

const COLS := 16
const ROWS := 11
const VISION := 3

var rng := RandomNumberGenerator.new()
var day := 1
var res := {}
var tiles := {}
var towns := []
var mines := []
var camps := []
var caches := []
var heroes := []
var id_counter := 1
var selected := 0
var faction := "sentinel"
var enemy_faction := "scourge"
var explored := {}
var visible_cells := {}
var journal := []
var inventory := []
var pending_battle := {}
var game_over := ""
var ai_power := 0
var turn_busy := false

# ------------------------------------------------------------------ 初始化
func _ready() -> void:
	rng.randomize()

func new_game(hero_key: String) -> void:
	rng.randomize()
	day = 1
	res = {"gold": 6500, "wood": 22, "ore": 16, "crystal": 8, "essence": 3}
	tiles = {}
	towns = []
	mines = []
	camps = []
	caches = []
	heroes = []
	id_counter = 1
	explored = {}
	visible_cells = {}
	journal = []
	inventory = ["iron_sword", "amulet"]
	pending_battle = {}
	game_over = ""
	ai_power = 0

	generate_terrain()
	place_world()

	var start := Vector2i(3, 8)
	force_clear(start)
	var h := create_hero(hero_key, false, start)
	selected = h.id
	var eh1 := create_hero("skeleton_king", true, Vector2i(12, 2))
	eh1.army = [{"unit": "ghoul", "count": 26}, {"unit": "skeleton_archer", "count": 12}, {"unit": "ogre", "count": 4}]
	var eh2 := create_hero("lich", true, Vector2i(13, 3))
	eh2.army = [{"unit": "ghoul", "count": 18}, {"unit": "skeleton_archer", "count": 18}, {"unit": "necromancer", "count": 5}]

	add_log("第 1 天 · %s 在银月城接过近卫军团的旌旗。" % h.name)
	add_log("目标：夺取矿脉、扩张城镇、击溃天灾军团。")
	compute_vision()
	changed.emit()

func generate_terrain() -> void:
	for y in range(ROWS):
		for x in range(COLS):
			var c := Vector2i(x, y)
			var t := "plain"
			var v := rng.randf()
			if v < 0.17:
				t = "forest"
			elif v < 0.25:
				t = "hill"
			elif v < 0.30:
				t = "swamp"
			elif v < 0.35:
				t = "mountain"
			elif v < 0.39:
				t = "water"
			tiles[Hex.key(c)] = {"c": c, "t": t}
	# 保证两座主城之间有一条可通行的古道
	make_road(Vector2i(3, 8), Vector2i(7, 5))
	make_road(Vector2i(7, 5), Vector2i(12, 2))
	make_road(Vector2i(7, 5), Vector2i(10, 8))

func make_road(a: Vector2i, b: Vector2i) -> void:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(steps + 1):
		var t := float(i) / float(max(1, steps))
		var c := Vector2i(roundi(lerpf(float(a.x), float(b.x), t)), roundi(lerpf(float(a.y), float(b.y), t)))
		for n in [c, Vector2i(c.x + 1, c.y), Vector2i(c.x, c.y + 1)]:
			if tiles.has(Hex.key(n)):
				tiles[Hex.key(n)].t = "road"

func force_clear(c: Vector2i) -> void:
	for n in [c] + Hex.neighbors(c):
		if tiles.has(Hex.key(n)) and int(DB.TERRAIN[tiles[Hex.key(n)].t].cost) >= 99:
			tiles[Hex.key(n)].t = "plain"

func place_world() -> void:
	towns = [
		make_town("银月城", Vector2i(2, 8), "sentinel", {"hall": 1, "tavern": 1}),
		make_town("寒骸堡", Vector2i(13, 2), "scourge", {"hall": 2, "barracks": 1}),
		make_town("灰谷哨站", Vector2i(7, 5), "neutral", {"hall": 1, "barracks": 1}),
		make_town("遗迹之城", Vector2i(11, 8), "neutral", {"hall": 1, "mage_tower": 1}),
	]
	mines = [
		make_mine("gold", Vector2i(4, 9), []),
		make_mine("wood", Vector2i(1, 4), [{"unit": "kobold", "count": 14}]),
		make_mine("ore", Vector2i(5, 2), [{"unit": "wolf", "count": 8}]),
		make_mine("crystal", Vector2i(9, 1), [{"unit": "golem", "count": 4}]),
		make_mine("essence", Vector2i(14, 7), [{"unit": "ogre", "count": 7}]),
		make_mine("gold", Vector2i(10, 4), [{"unit": "wolf", "count": 10}]),
		make_mine("wood", Vector2i(13, 9), []),
		make_mine("ore", Vector2i(3, 6), [{"unit": "kobold", "count": 18}]),
	]
	camps = [
		make_camp("腐化狼穴", Vector2i(6, 8), [{"unit": "wolf", "count": 9}], {"gold": 900, "crystal": 2}),
		make_camp("食人魔营地", Vector2i(8, 3), [{"unit": "ogre", "count": 6}], {"gold": 1200, "ore": 5}),
		make_camp("远古遗迹", Vector2i(12, 6), [{"unit": "golem", "count": 5}], {"gold": 1800, "essence": 3}),
		make_camp("亡灵前哨", Vector2i(9, 9), [{"unit": "skeleton_archer", "count": 14}, {"unit": "ghoul", "count": 10}], {"gold": 1400}),
	]
	caches = [
		make_cache("遗落的补给箱", Vector2i(4, 6), {"gold": 700, "wood": 5}),
		make_cache("法师的遗物", Vector2i(8, 7), {"crystal": 4, "essence": 2}),
		make_cache("商队残骸", Vector2i(11, 2), {"gold": 900}),
		make_cache("符文石匣", Vector2i(2, 2), {"ore": 6, "crystal": 2}),
	]
	for o in towns + mines + camps + caches:
		force_clear(o.pos)

func make_town(n: String, p: Vector2i, owner: String, b: Dictionary) -> Dictionary:
	var army := []
	if owner == "neutral":
		army = [{"unit": "kobold", "count": 16}, {"unit": "wolf", "count": 6}]
	elif owner == "scourge":
		army = [{"unit": "ghoul", "count": 24}, {"unit": "skeleton_archer", "count": 12}]
	return {"id": next_id(), "kind": "town", "name": n, "pos": p, "owner": owner,
			"buildings": b.duplicate(true), "garrison": army, "guarded": army.size() > 0}

func make_mine(r: String, p: Vector2i, guards: Array) -> Dictionary:
	return {"id": next_id(), "kind": "mine", "name": DB.RES[r].name + "矿", "pos": p,
			"res": r, "owner": "", "guards": guards.duplicate(true), "guarded": guards.size() > 0}

func make_camp(n: String, p: Vector2i, guards: Array, reward: Dictionary) -> Dictionary:
	return {"id": next_id(), "kind": "camp", "name": n, "pos": p,
			"guards": guards.duplicate(true), "guarded": true, "reward": reward.duplicate()}

func make_cache(n: String, p: Vector2i, reward: Dictionary) -> Dictionary:
	return {"id": next_id(), "kind": "cache", "name": n, "pos": p, "reward": reward.duplicate()}

func next_id() -> int:
	var i := id_counter
	id_counter += 1
	return i

# ------------------------------------------------------------------ 英雄
func create_hero(def_id: String, is_ai: bool, pos: Vector2i) -> Dictionary:
	var d: Dictionary = DB.HEROES[def_id]
	var h := {
		"id": next_id(), "def": def_id, "name": d.name, "en": d.en, "title": d.title,
		"color": d.color, "klass": d.klass, "faction": d.faction, "is_ai": is_ai,
		"level": 1, "xp": 0, "atk": d.atk, "defense": d.def, "power": d.power, "knowledge": d.knowledge,
		"skill": d.skills.duplicate(), "skill_points": 0,
		"items": {"weapon": "", "armor": "", "helm": "", "boots": "", "trinket": "", "book": ""},
		"spells": d.spells.duplicate(), "army": [], "pos": pos,
		"mp": 12, "mana": 0, "alive": true, "bio": d.bio,
	}
	for s in d.army:
		h.army.append({"unit": s.unit, "count": s.count})
	h.mana = max_mana(h)
	h.mp = max_mp(h)
	if is_ai:
		h.level = 3
		h.atk += 1
		h.defense += 1
	heroes.append(h)
	return h

func hero(id: int) -> Dictionary:
	for h in heroes:
		if int(h.id) == id:
			return h
	return {}

func player_heroes() -> Array:
	var out := []
	for h in heroes:
		if not h.is_ai and h.alive:
			out.append(h)
	return out

func selected_hero() -> Dictionary:
	var h := hero(selected)
	if h.is_empty():
		var p := player_heroes()
		if p.size() > 0:
			selected = p[0].id
			return p[0]
	return h

func hero_stats(h: Dictionary) -> Dictionary:
	var s := {"atk": int(h.atk), "def": int(h.defense), "power": int(h.power), "knowledge": int(h.knowledge), "spd": 0}
	for slot in DB.SLOTS:
		var it: String = h.items.get(slot, "")
		if it != "" and DB.ITEMS.has(it):
			for k in ["atk", "def", "power", "knowledge", "spd"]:
				s[k] += int(DB.ITEMS[it].get(k, 0))
	return s

func max_mp(h: Dictionary) -> int:
	var v := 12 + int(h.skill.get("logistics", 0)) * 2
	for slot in DB.SLOTS:
		var it: String = h.items.get(slot, "")
		if it != "" and DB.ITEMS.has(it):
			v += int(DB.ITEMS[it].get("mp", 0))
	return v

func max_mana(h: Dictionary) -> int:
	var v := 10 * int(h.knowledge) + int(h.skill.get("wisdom", 0)) * 6
	for slot in DB.SLOTS:
		var it: String = h.items.get(slot, "")
		if it != "" and DB.ITEMS.has(it):
			v += int(DB.ITEMS[it].get("mana", 0))
	return v

func army_strength(army: Array) -> int:
	var total := 0
	for s in army:
		if DB.UNITS.has(s.unit):
			var u: Dictionary = DB.UNITS[s.unit]
			total += int(s.count) * (int(u.hp) + int(u.atk) * 3 + int(u.def) * 2)
	return total

func army_add(h: Dictionary, unit_id: String, count: int) -> void:
	for s in h.army:
		if s.unit == unit_id:
			s.count += count
			return
	if h.army.size() < 7:
		h.army.append({"unit": unit_id, "count": count})
	else:
		h.army[0].count += count

func add_xp(h: Dictionary, amount: int) -> void:
	h.xp += amount
	var gained := 0
	while h.xp >= DB.level_xp(int(h.level)) and h.level < 30:
		h.xp -= DB.level_xp(int(h.level))
		h.level += 1
		h.skill_points += 1
		gained += 1
		match h.klass:
			"法师":
				h.power += 1
				h.knowledge += 1
			"游侠":
				h.atk += 1
				h.defense += 1
			_:
				h.atk += 1
				h.defense += 1
		if int(h.level) % 3 == 0:
			h.power += 1
	if gained > 0:
		add_log("%s 升到了 %d 级，获得 %d 点技能点！" % [h.name, h.level, gained])
		h.mana = max_mana(h)

func learn_skill(h: Dictionary, skill_id: String) -> String:
	if h.skill_points <= 0:
		return "没有可用技能点"
	var cur := int(h.skill.get(skill_id, 0))
	if cur >= 3:
		return "该技能已满级"
	if cur == 0 and h.skill.keys().size() >= 5:
		return "最多掌握 5 种技能"
	h.skill[skill_id] = cur + 1
	h.skill_points -= 1
	if skill_id == "logistics":
		h.mp = max_mp(h)
	if skill_id == "wisdom":
		h.mana = max_mana(h)
	add_log("%s 的「%s」提升到 %d 级。" % [h.name, DB.SKILLS[skill_id].name, cur + 1])
	changed.emit()
	return "习得成功"

# ------------------------------------------------------------------ 地图查询
func tile(c: Vector2i) -> Dictionary:
	return tiles.get(Hex.key(c), {})

func terrain(c: Vector2i) -> String:
	var t := tile(c)
	return t.t if not t.is_empty() else "water"

func terrain_cost(c: Vector2i) -> int:
	return int(DB.TERRAIN[terrain(c)].cost)

func object_at(c: Vector2i) -> Dictionary:
	for h in heroes:
		if h.alive and h.pos == c:
			return {"kind": "hero", "ref": h}
	for t in towns:
		if t.pos == c:
			return {"kind": "town", "ref": t}
	for m in mines:
		if m.pos == c:
			return {"kind": "mine", "ref": m}
	for cp in camps:
		if cp.pos == c:
			return {"kind": "camp", "ref": cp}
	for ca in caches:
		if ca.pos == c:
			return {"kind": "cache", "ref": ca}
	return {}

func blocked(c: Vector2i) -> bool:
	var o := object_at(c)
	return not o.is_empty() and o.kind != "cache"

func compute_vision() -> void:
	visible_cells.clear()
	var sources := []
	for h in heroes:
		if not h.is_ai and h.alive:
			sources.append([h.pos, VISION + int(h.skill.get("wisdom", 0)) / 2])
	for t in towns:
		if t.owner == faction:
			sources.append([t.pos, 2])
	for s in sources:
		var p: Vector2i = s[0]
		var r: int = int(s[1])
		for key in tiles:
			var c: Vector2i = tiles[key].c
			if Hex.dist(p, c) <= r:
				visible_cells[key] = true
				explored[key] = true

func is_explored(c: Vector2i) -> bool:
	return explored.has(Hex.key(c))

func is_visible(c: Vector2i) -> bool:
	return visible_cells.has(Hex.key(c))

# ------------------------------------------------------------------ 移动
func reachable(h: Dictionary, budget: int = -1) -> Dictionary:
	if budget < 0:
		budget = int(h.mp)
	var me: Node = self
	var cost_fn := func(c: Vector2i) -> int:
		return me.terrain_cost(c)
	var pass_fn := func(c: Vector2i) -> bool:
		if not me.tiles.has(Hex.key(c)):
			return false
		if me.terrain_cost(c) >= 99:
			return false
		for other in me.heroes:
			if other.alive and other.id != h.id and other.pos == c:
				return false
		return not me.blocked(c)
	var reach := Hex.flood(h.pos, budget, cost_fn, pass_fn)
	reach.erase(Hex.key(h.pos))
	# 允许「以相邻可达格为跳板」进入有对象的格子（占领 / 开战 / 进城）
	var frontier := [h.pos]
	for key in reach:
		frontier.append(Hex.from_key(key))
	var extra := {}
	for c in frontier:
		var base := 0 if c == h.pos else int(reach[Hex.key(c)])
		for n in Hex.neighbors(c):
			if not tiles.has(Hex.key(n)) or not blocked(n):
				continue
			if reach.has(Hex.key(n)) or extra.has(Hex.key(n)):
				continue
			var step := terrain_cost(n)
			if step < 99 and base + step <= budget:
				extra[Hex.key(n)] = base + step
	for key in extra:
		reach[key] = extra[key]
	return reach

func path_to(h: Dictionary, dest: Vector2i) -> Array:
	var reach := reachable(h)
	if not reach.has(Hex.key(dest)):
		return []
	var cur := dest
	var path: Array = []
	var guard := 0
	while cur != h.pos and guard < 400:
		guard += 1
		path.append(cur)
		var c := int(reach[Hex.key(cur)])
		var step := terrain_cost(cur)
		var found := false
		for n in Hex.neighbors(cur):
			if n == h.pos and c - step == 0:
				cur = h.pos
				found = true
				break
			if reach.has(Hex.key(n)) and int(reach[Hex.key(n)]) == c - step:
				cur = n
				found = true
				break
		if not found:
			return []
	path.reverse()
	return path

func move_hero(h: Dictionary, dest: Vector2i) -> bool:
	var reach := reachable(h)
	if not reach.has(Hex.key(dest)):
		return false
	var cost := int(reach[Hex.key(dest)])
	if cost > int(h.mp):
		return false
	h.mp -= cost
	h.pos = dest
	arrive(h, dest)
	compute_vision()
	changed.emit()
	return true

func arrive(h: Dictionary, pos: Vector2i) -> void:
	var o := object_at(pos)
	if o.is_empty():
		return
	var ref: Dictionary = o.ref
	match o.kind:
		"cache":
			DB.gain(res, ref.reward)
			add_log("%s 打开了%s，获得 %s。" % [h.name, ref.name, DB.res_text(ref.reward)])
			toast.emit("%s：%s" % [ref.name, DB.res_text(ref.reward)])
			caches.erase(ref)
		"mine":
			if ref.owner == faction:
				toast.emit("这座%s已归近卫军团所有" % ref.name)
			elif ref.guarded and not h.is_ai:
				start_battle(h, ref, ref.guards, "mine")
			else:
				capture_mine(h, ref)
		"town":
			if ref.owner == faction:
				toast.emit("进入 %s" % ref.name)
			elif ref.guarded and not h.is_ai:
				start_battle(h, ref, ref.garrison, "town")
			else:
				capture_town(h, ref)
		"camp":
			if not h.is_ai:
				start_battle(h, ref, ref.guards, "camp")
		"hero":
			if ref.id != h.id and ref.is_ai != h.is_ai:
				if not h.is_ai:
					start_battle(h, ref, ref.army, "hero")
				else:
					auto_battle_ai(h, ref)

func capture_mine(h: Dictionary, m: Dictionary) -> void:
	var f := faction if not h.is_ai else enemy_faction
	m.owner = f
	m.guarded = false
	m.guards = []
	add_log("%s 占领了%s，每日产出 %s。" % [h.name, m.name, DB.RES[m.res].name])
	toast.emit("占领 %s！" % m.name)

func capture_town(h: Dictionary, t: Dictionary) -> void:
	var f := faction if not h.is_ai else enemy_faction
	t.owner = f
	t.guarded = false
	t.garrison = []
	add_log("%s 拿下了 %s。" % [h.name, t.name])
	toast.emit("占领 %s！" % t.name)

func auto_battle_ai(attacker: Dictionary, defender: Dictionary) -> void:
	# AI 之间的战斗用战力快速结算，保证回合节奏
	if army_strength(attacker.army) > army_strength(defender.army) * 1.2:
		defender.army = []
		defender.alive = false
		add_log("斥候来报：%s 被天灾军团击溃了。" % defender.name)
	else:
		attacker.army = []
		attacker.alive = false
		add_log("%s 击退了天灾英雄 %s。" % [defender.name, attacker.name])

# ------------------------------------------------------------------ 战斗
func battle_reward(army: Array, kind: String) -> Dictionary:
	var value := army_strength(army)
	var r := {"gold": int(clampf(float(value) * 0.35, 200, 4000))}
	if kind == "town":
		r.gold = int(r.gold) + 1500
		r.wood = 5
	elif kind == "camp":
		r.crystal = rng.randi_range(1, 3)
	if rng.randf() < 0.45:
		r.essence = 1
	return r

func start_battle(h: Dictionary, ref: Dictionary, enemy_army: Array, kind: String) -> void:
	var enemy_hero_data: Dictionary = {}
	if kind == "hero":
		enemy_hero_data = {
			"name": ref.name, "level": ref.level, "color": ref.color,
			"spells": ref.spells.duplicate(), "mana": ref.mana,
		}
	else:
		var enemies := DB.HEROES.keys()
		var edef: Dictionary = DB.HEROES[enemies[rng.randi() % enemies.size()]]
		enemy_hero_data = {"name": edef.name + "的意志", "level": maxi(1, int(day / 4)), "color": "#b06a6a", "spells": ["arcane_bolt"], "mana": 30}
	pending_battle = {
		"hero_id": h.id,
		"enemy_army": enemy_army.duplicate(true),
		"enemy_hero": enemy_hero_data,
		"kind": kind,
		"ref": ref,
		"reward": battle_reward(enemy_army, kind),
		"xp": int(clampf(float(army_strength(enemy_army)) * 0.55, 120, 9000)),
		"biome": terrain(h.pos),
	}
	goto("battle", {})

func finish_battle(win: bool, survivors: Array, mana_left: int) -> Dictionary:
	var b := pending_battle
	var h := hero(int(b.get("hero_id", selected)))
	var summary := {"win": win, "xp": 0, "loot": {}, "levels": 0, "item": "", "name": ""}
	if h.is_empty():
		return summary
	h.mana = clampi(mana_left, 0, max_mana(h))
	if win:
		var clean := []
		for s in survivors:
			if int(s.count) > 0:
				clean.append({"unit": s.unit, "count": int(s.count)})
		h.army = clean
		var xp := int(b.xp)
		add_xp(h, xp)
		summary.xp = xp
		var loot: Dictionary = b.reward.duplicate()
		DB.gain(res, loot)
		summary.loot = loot
		var ref: Dictionary = b.ref
		summary.name = ref.name
		match b.kind:
			"mine":
				capture_mine(h, ref)
			"town":
				capture_town(h, ref)
				if not ref.buildings.has("hall"):
					ref.buildings.hall = 1
			"camp":
				camps.erase(ref)
				var keys := DB.ITEMS.keys()
				var item: String = keys[rng.randi() % keys.size()]
				inventory.append(item)
				summary.item = DB.ITEMS[item].name
				add_log("在%s中找到了「%s」。" % [ref.name, summary.item])
			"hero":
				ref.alive = false
				ref.army = []
				add_log("%s 击败了天灾英雄 %s！" % [h.name, ref.name])
		add_log("战斗胜利：%s 获得 %d 经验、%s。" % [h.name, xp, DB.res_text(loot)])
	else:
		h.army = [{"unit": "militia", "count": 8}]
		h.mp = 0
		for t in towns:
			if t.owner == faction:
				h.pos = t.pos
				break
		h.mana = max_mana(h)
		add_log("%s 战败撤退到最近的城镇，部队损失殆尽。" % h.name)
	compute_vision()
	check_game_over()
	changed.emit()
	return summary

# ------------------------------------------------------------------ 经济与建造
func income() -> void:
	var earned := {}
	for t in towns:
		if t.owner == faction:
			earned.gold = int(earned.get("gold", 0)) + 500 * int(t.buildings.get("hall", 0))
			if t.buildings.has("silo"):
				for k in ["wood", "ore", "crystal", "essence"]:
					earned[k] = int(earned.get(k, 0)) + 1
	for m in mines:
		if m.owner == faction:
			earned[m.res] = int(earned.get(m.res, 0)) + int(DB.RES[m.res].daily)
		elif m.owner == enemy_faction:
			ai_power += 1
	DB.gain(res, earned)
	if not earned.is_empty():
		add_log("回合收入：%s" % DB.res_text(earned))

func build(town_id: int, bid: String) -> String:
	var t := find_by_id(towns, town_id)
	if t.is_empty():
		return "找不到城镇"
	if t.owner != faction:
		return "必须先占领这座城镇"
	var d: Dictionary = DB.BUILDINGS[bid]
	var lvl := int(t.buildings.get(bid, 0))
	if lvl >= int(d.max):
		return "已达到最高等级"
	if not DB.can_afford(res, d.cost):
		return "资源不足：" + DB.res_text(d.cost)
	DB.pay(res, d.cost)
	t.buildings[bid] = lvl + 1
	if bid == "mage_tower":
		var pool := ["frost_nova", "arcane_bolt", "holy_light", "dragon_slave", "frost_armor", "death_pulse"]
		var h := selected_hero()
		if not h.is_empty():
			var s: String = pool[rng.randi() % pool.size()]
			if not h.spells.has(s):
				h.spells.append(s)
				add_log("魔法塔落成，%s 习得了「%s」。" % [h.name, DB.SPELLS[s].name])
	add_log("%s 建成了 %s（%d 级）。" % [t.name, d.name, lvl + 1])
	changed.emit()
	return "建造完成：" + d.name

func recruit(town_id: int, unit_id: String, count: int) -> String:
	var t := find_by_id(towns, town_id)
	var h := selected_hero()
	if t.is_empty() or h.is_empty():
		return "无法招募"
	if t.owner != faction:
		return "城镇不属于你"
	if Hex.dist(t.pos, h.pos) > 2:
		return "英雄必须驻扎在城镇附近"
	var u: Dictionary = DB.UNITS[unit_id]
	var cost := {"gold": int(u.cost) * count}
	if not DB.can_afford(res, cost):
		return "金币不足，需要 %d" % int(cost.gold)
	DB.pay(res, cost)
	army_add(h, unit_id, count)
	changed.emit()
	return "招募了 %d 名%s" % [count, u.name]

func hire_hero(town_id: int, def_id: String) -> String:
	var t := find_by_id(towns, town_id)
	if t.is_empty() or not t.buildings.has("tavern"):
		return "需要酒馆"
	if not DB.can_afford(res, {"gold": 2500}):
		return "金币不足，需要 2500"
	if DB.HEROES[def_id].faction != faction:
		return "该英雄不属于近卫军团"
	for h in heroes:
		if h.def == def_id:
			return "这位英雄已经在你的麾下"
	DB.pay(res, {"gold": 2500})
	var pos: Vector2i = t.pos
	for n in Hex.neighbors(t.pos):
		if not blocked(n) and terrain_cost(n) < 99:
			pos = n
			break
	var nh := create_hero(def_id, false, pos)
	add_log("%s 在 %s 的酒馆加入了近卫军团。" % [nh.name, t.name])
	compute_vision()
	changed.emit()
	return "%s 已加入" % nh.name

func buy_item(town_id: int, item_id: String) -> String:
	var t := find_by_id(towns, town_id)
	if t.is_empty() or not t.buildings.has("forge"):
		return "需要铁匠铺"
	if not DB.can_afford(res, {"gold": int(DB.ITEMS[item_id].price)}):
		return "金币不足"
	DB.pay(res, {"gold": int(DB.ITEMS[item_id].price)})
	inventory.append(item_id)
	changed.emit()
	return "购得「%s」" % DB.ITEMS[item_id].name

func equip(hero_id: int, item: String) -> String:
	var h := hero(hero_id)
	if h.is_empty():
		return "英雄不存在"
	var slot: String = DB.ITEMS[item].slot
	var old: String = h.items.get(slot, "")
	if old != "":
		inventory.append(old)
	inventory.erase(item)
	h.items[slot] = item
	h.mana = mini(int(h.mana), max_mana(h))
	changed.emit()
	return "装备「%s」" % DB.ITEMS[item].name

func unequip(hero_id: int, slot: String) -> void:
	var h := hero(hero_id)
	if h.is_empty():
		return
	var old: String = h.items.get(slot, "")
	if old != "":
		inventory.append(old)
		h.items[slot] = ""
	changed.emit()

func trade(give_key: String, take_key: String) -> String:
	var amount := 5
	if int(res.get(give_key, 0)) < amount:
		return "资源不足"
	res[give_key] = int(res[give_key]) - amount
	res[take_key] = int(res.get(take_key, 0)) + 3
	changed.emit()
	return "交易完成"

func find_by_id(arr: Array, id: int) -> Dictionary:
	for x in arr:
		if int(x.id) == id:
			return x
	return {}

# ------------------------------------------------------------------ 回合
func end_turn() -> void:
	if turn_busy or game_over != "":
		return
	turn_busy = true
	for h in heroes:
		if h.is_ai and h.alive:
			ai_turn(h)
	day += 1
	income()
	for h in heroes:
		if h.alive:
			h.mp = max_mp(h)
			var regen := 2 + int(h.skill.get("wisdom", 0)) * 2
			for t in towns:
				if t.owner == (enemy_faction if h.is_ai else faction):
					regen += int(t.buildings.get("mage_tower", 0))
			h.mana = mini(max_mana(h), int(h.mana) + regen)
	if day % 3 == 0:
		random_event()
	compute_vision()
	check_game_over()
	turn_busy = false
	toast.emit("第 %d 天 · 回合结算完成" % day)
	changed.emit()

func ai_turn(h: Dictionary) -> void:
	h.mp = max_mp(h)
	var targets := []
	for m in mines:
		if m.owner != enemy_faction:
			targets.append(m.pos)
	for t in towns:
		if t.owner == "neutral":
			targets.append(t.pos)
	if targets.is_empty():
		return
	var cmp := func(a, b): return Hex.dist(h.pos, a) < Hex.dist(h.pos, b)
	targets.sort_custom(cmp)
	var goal: Vector2i = targets[0]
	var reach := reachable(h)
	var best: Vector2i = h.pos
	var best_d := Hex.dist(h.pos, goal)
	for key in reach:
		var c := Hex.from_key(key)
		var o := object_at(c)
		if not o.is_empty() and o.kind == "hero" and not o.ref.is_ai:
			continue
		var d := Hex.dist(c, goal)
		if d < best_d:
			best_d = d
			best = c
	if best != h.pos:
		var cost := int(reach[Hex.key(best)])
		h.mp -= cost
		h.pos = best
		arrive(h, best)
	if day % 4 == 0:
		var pool: Array = DB.RECRUITS[enemy_faction]
		var u: String = pool[rng.randi() % mini(4, pool.size())]
		var found := false
		for s in h.army:
			if s.unit == u:
				s.count += 4 + int(ai_power / 6)
				found = true
				break
		if not found:
			h.army.append({"unit": u, "count": 4})
	if day % 6 == 0:
		var ph := player_heroes()
		if ph.size() > 0 and Hex.dist(h.pos, ph[0].pos) <= 5:
			var loss := mini(int(res.gold), 400)
			res.gold = int(res.gold) - loss
			add_log("天灾英雄 %s 突袭了补给线，损失 %d 金币。" % [h.name, loss])

func random_event() -> void:
	var e: Dictionary = DB.EVENTS[rng.randi() % DB.EVENTS.size()]
	var eff: Dictionary = e.effect
	for k in ["gold", "wood", "ore", "crystal", "essence"]:
		if eff.has(k):
			res[k] = int(res.get(k, 0)) + int(eff[k])
	if eff.has("mana"):
		for h in player_heroes():
			h.mana = max_mana(h)
	if eff.has("troops"):
		for h in player_heroes():
			army_add(h, "militia", 6)
	if eff.has("camp"):
		var cells := tiles.keys()
		var k: String = cells[rng.randi() % cells.size()]
		var c: Vector2i = tiles[k].c
		if not blocked(c) and terrain_cost(c) < 99 and not is_visible(c):
			camps.append(make_camp("新的腐化巢穴", c, [{"unit": "wolf", "count": 8}], {"gold": 700}))
	add_log("【%s】%s" % [e.title, e.text])
	popup.emit(e.title, e.text, Callable())

func check_game_over() -> void:
	if game_over != "":
		return
	var enemy_towns := 0
	var my_towns := 0
	for t in towns:
		if t.owner == enemy_faction:
			enemy_towns += 1
		elif t.owner == faction:
			my_towns += 1
	var enemy_heroes := 0
	for h in heroes:
		if h.is_ai and h.alive:
			enemy_heroes += 1
	if enemy_towns == 0 and enemy_heroes == 0:
		game_over = "win"
		popup.emit("世界之树仍在生长", "天灾军团的最后一座城邦已经陷落，冰封王座的低语终于沉寂。\n\n你用 %d 个回合守住了这片大陆。" % day, Callable())
	elif my_towns == 0 and player_heroes().is_empty():
		game_over = "lose"
		popup.emit("长夜降临", "近卫军团的旌旗倒下了。世界之树的最后一点绿意，被霜雪覆盖。", Callable())

func objective() -> String:
	var mine_count := 0
	for m in mines:
		if m.owner == faction:
			mine_count += 1
	var town_count := 0
	for t in towns:
		if t.owner == faction:
			town_count += 1
	return "已占领 %d/8 座矿场 · %d/4 座城镇 · 第 %d 天" % [mine_count, town_count, day]

# ------------------------------------------------------------------ 工具
func add_log(s: String) -> void:
	journal.push_front(s)
	if journal.size() > 80:
		journal.resize(80)

func goto(view: String, payload: Dictionary = {}) -> void:
	goto_view.emit(view, payload)

func say(s: String) -> void:
	toast.emit(s)

func dialog(t: String, body: String, cb: Callable = Callable()) -> void:
	popup.emit(t, body, cb)
