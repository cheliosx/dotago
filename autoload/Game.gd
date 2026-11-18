extends Node
## 全局游戏状态（Autoload 名：Game）
## 负责：世界生成、移动力与寻路、回合结算、经济、AI、战斗前后结算。

signal changed
signal goto_view(view: String, payload: Dictionary)
signal toast(text: String)
signal popup(title: String, body: String, cb: Callable)
## 有势力正在进攻玩家的据点，需要玩家选「死守 / 撤退」
signal defense_prompt

const COLS := 26
const ROWS := 17
const VISION := 4

var rng := RandomNumberGenerator.new()
var day := 1
var res := {}
var tiles := {}
var towns := []
var mines := []
var camps := []
var caches := []
var bases := []          # 势力营地（每方一个，被占领 = 该势力失去根基）
var factions := []       # 势力状态：id/name/color/alive/is_player/base_poi
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
var pending_defenses := []   # 本回合 AI 打到玩家据点的记录，等玩家逐个决定
var awaiting_defense := false
var save_slot := ""   # 当前存档 id（对应 autoload/Saves 里的文件）
var use_map_world := false
var map_spawn := Vector3.ZERO
var map_terrain = null   # 主地图 Terrain 节点（WorldMapView 赋值），AI 用它判断能否走

# ------------------------------------------------------------------ 初始化
func _ready() -> void:
	rng.randomize()

func new_game(hero_key: String, hero_name: String = "", use_map: bool = true) -> void:
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
	bases = []
	factions = []
	pending_defenses = []
	awaiting_defense = false

	use_map_world = use_map
	if use_map:
		build_map_world()
	else:
		generate_terrain()
		place_world()

	var start := Vector2i(4, 13)
	var spawn := Vector3.ZERO
	if use_map:
		start = Vector2i(roundi(map_spawn.x), roundi(map_spawn.z))
		spawn = map_spawn
		# 开局站在自己营地门口，方便立刻招募与派兵
		if not factions.is_empty():
			var pb := base_of(faction)
			if not pb.is_empty():
				spawn = (pb.wpos as Vector3) + Vector3(0, 0, 7.0)
				spawn.y = pb.wpos.y
				start = Vector2i(roundi(spawn.x), roundi(spawn.z))
	else:
		force_clear(start)
	var h := create_hero(hero_key, false, start)
	h["wpos"] = spawn if use_map else Vector3.ZERO
	var custom := hero_name.strip_edges()
	if custom != "":
		h.name = custom
	selected = h.id
	if use_map and not factions.is_empty():
		# 每个敌对势力一位统帅，守在自己的营地
		for f in factions:
			if bool(f.is_player):
				continue
			var b := base_of(String(f.id))
			if b.is_empty():
				continue
			var eh := create_hero(String(f.hero_def), true, Vector2i(roundi(b.wpos.x), roundi(b.wpos.z)), String(f.id))
			eh["wpos"] = b.wpos + Vector3(3.0, 0.0, 2.5)
			eh["pos"] = Vector2i(roundi(eh.wpos.x), roundi(eh.wpos.z))
			eh.level = 2
	else:
		var eh1 := create_hero("skeleton_king", true, Vector2i(20, 2))
		eh1.army = [{"unit": "ghoul", "count": 26}, {"unit": "skeleton_archer", "count": 12}, {"unit": "ogre", "count": 4}]
		var eh2 := create_hero("lich", true, Vector2i(22, 4))
		eh2.army = [{"unit": "ghoul", "count": 18}, {"unit": "skeleton_archer", "count": 18}, {"unit": "necromancer", "count": 5}]

	add_log("第 1 天 · %s 在营地接过近卫军团的旌旗。" % h.name)
	add_log("目标：占领金矿与伐木场，消灭地图上所有敌对势力。")
	# 大图上开局先给一片已知区域，否则只剩脚下几格亮着，看不出地形骨架
	for src in ([start, Vector2i(3, 13)] if not use_map else []):
		for key in tiles:
			var cc: Vector2i = tiles[key].c
			if Hex.dist(src, cc) <= 6:
				explored[key] = true
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
	make_road(Vector2i(4, 13), Vector2i(12, 9))
	make_road(Vector2i(12, 9), Vector2i(21, 3))
	make_road(Vector2i(12, 9), Vector2i(18, 13))
	make_road(Vector2i(12, 9), Vector2i(10, 16))
	make_road(Vector2i(12, 9), Vector2i(8, 4))

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
		make_town("银月城", Vector2i(3, 13), "sentinel", {"hall": 1, "tavern": 1}),
		make_town("寒骸堡", Vector2i(21, 3), "scourge", {"hall": 2, "barracks": 1}),
		make_town("灰谷哨站", Vector2i(12, 9), "neutral", {"hall": 1, "barracks": 1}),
		make_town("遗迹之城", Vector2i(18, 13), "neutral", {"hall": 1, "mage_tower": 1}),
	]
	mines = [
		make_mine("gold", Vector2i(6, 14), []),
		make_mine("wood", Vector2i(1, 8), [{"unit": "kobold", "count": 14}]),
		make_mine("ore", Vector2i(9, 3), [{"unit": "wolf", "count": 8}]),
		make_mine("crystal", Vector2i(16, 1), [{"unit": "golem", "count": 4}]),
		make_mine("essence", Vector2i(23, 12), [{"unit": "ogre", "count": 7}]),
		make_mine("gold", Vector2i(17, 7), [{"unit": "wolf", "count": 10}]),
		make_mine("wood", Vector2i(21, 15), []),
		make_mine("ore", Vector2i(4, 10), [{"unit": "kobold", "count": 18}]),
		make_mine("gold", Vector2i(13, 12), [{"unit": "kobold", "count": 10}]),
		make_mine("wood", Vector2i(20, 10), [{"unit": "wolf", "count": 9}]),
		make_mine("crystal", Vector2i(25, 6), [{"unit": "golem", "count": 5}]),
		make_mine("essence", Vector2i(8, 6), [{"unit": "golem", "count": 3}]),
	]
	camps = [
		make_camp("腐化狼穴", Vector2i(10, 13), [{"unit": "wolf", "count": 9}], {"gold": 900, "crystal": 2}),
		make_camp("食人魔营地", Vector2i(14, 5), [{"unit": "ogre", "count": 6}], {"gold": 1200, "ore": 5}),
		make_camp("远古遗迹", Vector2i(19, 11), [{"unit": "golem", "count": 5}], {"gold": 1800, "essence": 3}),
		make_camp("亡灵前哨", Vector2i(15, 15), [{"unit": "skeleton_archer", "count": 14}, {"unit": "ghoul", "count": 10}], {"gold": 1400}),
		make_camp("冰霜裂隙", Vector2i(7, 4), [{"unit": "golem", "count": 4}, {"unit": "wolf", "count": 6}], {"gold": 1600, "crystal": 3}),
		make_camp("蛛后巢穴", Vector2i(23, 7), [{"unit": "kobold", "count": 20}], {"gold": 1500, "wood": 6}),
		make_camp("腐化墓园", Vector2i(18, 2), [{"unit": "ghoul", "count": 16}], {"gold": 1300}),
	]
	caches = [
		make_cache("遗落的补给箱", Vector2i(7, 12), {"gold": 700, "wood": 5}),
		make_cache("法师的遗物", Vector2i(14, 10), {"crystal": 4, "essence": 2}),
		make_cache("商队残骸", Vector2i(17, 4), {"gold": 900}),
		make_cache("符文石匣", Vector2i(2, 4), {"ore": 6, "crystal": 2}),
		make_cache("沉没的宝库", Vector2i(24, 15), {"gold": 1200, "crystal": 3}),
		make_cache("巨魔的祭品", Vector2i(11, 6), {"essence": 2, "gold": 600}),
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
	return {"id": next_id(), "kind": "mine", "name": DB.MINE_NAMES[r], "pos": p,
			"res": r, "owner": "", "guards": guards.duplicate(true), "guarded": guards.size() > 0,
			"garrison": []}

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
func create_hero(def_id: String, is_ai: bool, pos: Vector2i, fac: String = "") -> Dictionary:
	var d: Dictionary = DB.HEROES[def_id]
	var h := {
		"id": next_id(), "def": def_id, "name": d.name, "en": d.en, "title": d.title,
		"color": d.color, "klass": d.klass, "faction": (fac if fac != "" else String(d.faction)), "is_ai": is_ai,
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

## 从可编辑场景 world/WorldMap.tscn 读取兴趣点，生成本局的世界数据。
## 场景负责「摆在哪、叫什么」，Game 负责「谁占领、有多少守军」等动态状态。
func build_map_world() -> void:
	towns = []
	mines = []
	camps = []
	caches = []
	bases = []
	factions = []
	var ps: PackedScene = load("res://world/WorldMap.tscn")
	if ps == null:
		push_error("WorldMap.tscn 载入失败")
		return
	var inst := ps.instantiate()
	for n in _walk(inst):
		if n is Marker3D and n.name == "HeroSpawn":
			map_spawn = (n as Marker3D).position
			continue
		if not n.has_method("guard_list"):
			continue
		var w: Vector3 = (n as Node3D).position
		var hexp := Vector2i(roundi(w.x), roundi(w.z))
		var guards: Array = n.call("guard_list")
		match String(n.kind):
			"town":
				towns.append({"id": next_id(), "kind": "town", "name": String(n.title),
					"pos": hexp, "owner": String(n.owner_id), "buildings": {"hall": 1},
					"garrison": [], "guarded": false, "wpos": w, "poi": String(n.name)})
			"mine":
				mines.append({"id": next_id(), "kind": "mine", "name": String(n.title),
					"pos": hexp, "res": String(n.resource), "owner": "",
					"guards": guards, "guarded": guards.size() > 0, "wpos": w, "poi": String(n.name)})
			"camp":
				var cnt := 0
				for g in guards:
					cnt += int(g.count)
				camps.append({"id": next_id(), "kind": "camp", "name": String(n.title),
					"pos": hexp, "guards": guards, "guarded": true,
					"reward": {"gold": 700 + cnt * 70, "crystal": 2},
					"wpos": w, "poi": String(n.name)})
			"base":
				bases.append({"id": next_id(), "kind": "base", "name": String(n.title),
					"pos": hexp, "owner": String(n.owner_id), "garrison": guards,
					"wpos": w, "poi": String(n.name)})
	inst.free()
	# 玩家初始城镇补一点驻军，避免开局空城
	for t in towns:
		if t.owner == faction and (t.garrison as Array).is_empty():
			t.garrison = [{"unit": "militia", "count": 10}]
	for m in mines:
		if not m.has("garrison"):
			m["garrison"] = []
	init_factions()

## 每个 base 对应一方势力。hero_def 决定该势力统帅用哪位英雄的数据。
const FACTION_HERO_DEFS := {
	"scourge": "lich", "claw": "axe", "iron": "skeleton_king", "ash": "nevermore",
}

func init_factions() -> void:
	factions = []
	for b in bases:
		var id := String(b.owner)
		if id == "":
			continue
		if _find_faction(id).size() > 0:
			continue
		var d: Dictionary = DB.FACTIONS.get(id, DB.FACTIONS["neutral"])
		factions.append({
			"id": id, "name": String(d.name), "color": String(d.color),
			"desc": String(d.get("desc", "")),
			"alive": true, "is_player": id == faction,
			"hero_def": String(FACTION_HERO_DEFS.get(id, "skeleton_king")),
		})

func _find_faction(id: String) -> Dictionary:
	for f in factions:
		if String(f.id) == id:
			return f
	return {}

func faction_name(id: String) -> String:
	if id == "":
		return "无主"
	var d: Dictionary = DB.FACTIONS.get(id, {})
	return String(d.get("name", id)) if not d.is_empty() else id

func faction_color(id: String) -> Color:
	var d: Dictionary = DB.FACTIONS.get(id, {})
	return Color(d.get("color", "#b8ac90")) if not d.is_empty() else Color("#b8ac90")

## 势力自己的营地（被占领后 owner 会变，所以不能只按 owner 找）
func base_of(fac_id: String) -> Dictionary:
	for b in bases:
		if String(b.owner) == fac_id:
			return b
	return {}

func base_by_poi(poi_name: String) -> Dictionary:
	for b in bases:
		if String(b.get("poi", "")) == poi_name:
			return b
	return {}

## 某势力还活着吗：有营地或有英雄
func faction_alive(fac_id: String) -> bool:
	for b in bases:
		if String(b.owner) == fac_id:
			return true
	for h in heroes:
		if bool(h.alive) and String(h.faction) == fac_id:
			return true
	return false

func player_power() -> int:
	var n := 0
	for b in bases:
		if String(b.owner) == faction:
			n += 1
	for m in mines:
		if String(m.owner) == faction:
			n += 1
	return n

func _walk(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

# ------------------------------------------------------------------ 地图查询
func tile(c: Vector2i) -> Dictionary:
	return tiles.get(Hex.key(c), {})

func terrain(c: Vector2i) -> String:
	var t := tile(c)
	return t.t if not t.is_empty() else "water"

func terrain_cost(c: Vector2i) -> int:
	return int(DB.TERRAIN[terrain(c)].cost)

## 只查地面物件（城镇 / 矿场 / 营地 / 宝箱），不含英雄。
## 英雄抵达后会站在该格上，若用 object_at 会先命中自己，导致抵达交互永远失效。
func ground_at(c: Vector2i) -> Dictionary:
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

## 格子上的对象；exclude_hero_id 用于「忽略站在该格上的某个英雄」。
func object_at(c: Vector2i, exclude_hero_id: int = -1) -> Dictionary:
	for h in heroes:
		if h.alive and h.pos == c and int(h.id) != exclude_hero_id:
			return {"kind": "hero", "ref": h}
	return ground_at(c)

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
			if n == h.pos:
				continue
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
	# 英雄已站在 pos 上，必须先取地面物件；否则 object_at 会命中自己
	var o := ground_at(pos)
	if o.is_empty():
		var other := object_at(pos, int(h.id))
		if not other.is_empty() and other.kind == "hero":
			o = other
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
			if ref.owner == String(h.faction):
				if not h.is_ai:
					toast.emit("这座%s已经属于你的势力" % ref.name)
			elif ref.guarded and not h.is_ai:
				start_battle(h, ref, ref.guards, "mine")
			else:
				capture_mine(h, ref)
		"town":
			if ref.owner == String(h.faction):
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
	var f := String(h.faction)
	var old_owner := String(m.owner)
	m.owner = f
	m.guarded = false
	m.guards = []
	m["garrison"] = []
	add_log("%s 占领了%s，每日产出 %d %s。" % [h.name, m.name, int(DB.RES[m.res].daily), DB.RES[m.res].name])
	if f == faction:
		toast.emit("占领 %s！" % m.name)
	elif old_owner == faction:
		add_log("%s 被%s夺走了！" % [m.name, faction_name(f)])
	check_game_over()
	changed.emit()

func capture_town(h: Dictionary, t: Dictionary) -> void:
	var f := String(h.faction)
	var old_owner := String(t.owner)
	t.owner = f
	t.guarded = false
	t.garrison = []
	add_log("%s 拿下了 %s。" % [h.name, t.name])
	if f == faction:
		toast.emit("占领 %s！" % t.name)
	elif old_owner == faction:
		add_log("%s 失守了！" % t.name)
	check_game_over()
	changed.emit()

## 营地被攻破：该势力失去根基，只剩英雄还在流窜
func capture_base(h: Dictionary, b: Dictionary, keep_garrison: bool = false) -> void:
	var f := String(h.faction)
	var old_owner := String(b.owner)
	b.owner = f
	if not keep_garrison:
		b.garrison = []
	add_log("%s 攻破了 %s 的营地！" % [h.name, faction_name(old_owner)])
	if f == faction:
		toast.emit("攻破 %s！" % b.name)
	elif old_owner == faction:
		add_log("我们的营地 %s 陷落了。" % b.name)
	check_game_over()
	changed.emit()

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

func start_battle(h: Dictionary, ref: Dictionary, enemy_army: Array, kind: String, biome_override: String = "") -> void:
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
		"biome": biome_override if biome_override != "" else terrain(h.pos),
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
			"base":
				capture_base(h, ref)
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
		var home := {}
		for t in towns:
			if String(t.owner) == faction:
				home = t
				break
		if home.is_empty():
			for bb in bases:
				if String(bb.owner) == faction:
					home = bb
					break
		if not home.is_empty():
			h.pos = home.pos
			if use_map_world and home.has("wpos"):
				h["wpos"] = home.wpos + Vector3(0, 0, 3.0)
		h.mana = max_mana(h)
		add_log("%s 战败撤退，部队损失殆尽。" % h.name)
	compute_vision()
	check_game_over()
	changed.emit()
	return summary

# ------------------------------------------------------------------ 经济与建造
func income() -> void:
	var earned := {}
	# 城镇：大厅产金，仓库补各种资源
	for t in towns:
		if t.owner == faction:
			earned.gold = int(earned.get("gold", 0)) + 500 * int(t.buildings.get("hall", 0))
			if t.buildings.has("silo"):
				for k in ["wood", "ore", "crystal", "essence"]:
					earned[k] = int(earned.get(k, 0)) + 1
	# 营地（都城）：基础收入，撑着早期经济
	for b in bases:
		if b.owner == faction:
			earned.gold = int(earned.get("gold", 0)) + 600
			earned.wood = int(earned.get("wood", 0)) + 6
	# 矿场 / 伐木场：只有归属你的才产出；被别的势力拿着就变成对方的力量
	for m in mines:
		if m.owner == faction:
			earned[m.res] = int(earned.get(m.res, 0)) + int(DB.RES[m.res].daily)
		elif m.owner != "":
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

## 据点（城镇或营地）与英雄的距离：主地图用米，六边形地图用格
func site_distance(h: Dictionary, site: Dictionary) -> float:
	if use_map_world and site.has("wpos"):
		var hw: Vector3 = h.get("wpos", Vector3.ZERO)
		var sw: Vector3 = site.get("wpos", Vector3.ZERO)
		return Vector2(hw.x - sw.x, hw.z - sw.z).length()
	return float(Hex.dist(h.pos, site.pos))

func site_by_id(site_id: int) -> Dictionary:
	for t in towns:
		if int(t.id) == site_id:
			return t
	for b in bases:
		if int(b.id) == site_id:
			return b
	for m in mines:
		if int(m.id) == site_id:
			return m
	return {}

## 兵种价格：金币 + 木材（每 200 金折 1 木）
func unit_cost(unit_id: String, count: int) -> Dictionary:
	var u: Dictionary = DB.UNITS[unit_id]
	var gold := int(u.cost) * count
	return {"gold": gold, "wood": maxi(1, int(ceil(float(gold) / 200.0)))}

func recruit(site_id: int, unit_id: String, count: int) -> String:
	var t := site_by_id(site_id)
	var h := selected_hero()
	if t.is_empty() or h.is_empty():
		return "无法招募"
	if String(t.owner) != faction:
		return "据点不属于你"
	if not DB.RECRUITS.get(String(h.faction), []).has(unit_id):
		return "你的势力无法招募该兵种"
	if site_distance(h, t) > (16.0 if use_map_world else 2.0):
		return "英雄必须驻扎在据点附近"
	var cost := unit_cost(unit_id, count)
	if not DB.can_afford(res, cost):
		var short := ""
		for k in cost:
			if int(res.get(k, 0)) < int(cost[k]):
				short += "%s缺 %d  " % [DB.RES[k].name, int(cost[k]) - int(res.get(k, 0))]
		return "资源不足：" + short.strip_edges()
	DB.pay(res, cost)
	army_add(h, unit_id, count)
	changed.emit()
	return "招募了 %d 名%s" % [count, DB.UNITS[unit_id].name]

func hire_hero(site_id: int, def_id: String) -> String:
	var t := site_by_id(site_id)
	if t.is_empty():
		return "找不到据点"
	# 城镇需要酒馆；自己的营地本身就是招募点
	if String(t.kind) == "town" and not (t.get("buildings", {}) as Dictionary).has("tavern"):
		return "需要酒馆"
	if String(t.owner) != faction:
		return "据点不属于你"
	var cost := {"gold": 2500, "wood": 8}
	if not DB.can_afford(res, cost):
		return "需要 2500 金币与 8 木材"
	if DB.HEROES[def_id].faction != faction:
		return "该英雄不属于近卫军团"
	for h in heroes:
		if h.def == def_id:
			return "这位英雄已经在你的麾下"
	DB.pay(res, cost)
	var pos: Vector2i = t.pos
	if use_map_world:
		for n in Hex.neighbors(t.pos):
			if not blocked(n) and terrain_cost(n) < 99:
				pos = n
				break
	var nh := create_hero(def_id, false, pos)
	if use_map_world and t.has("wpos"):
		nh["wpos"] = t.wpos + Vector3(0, 0, 4.0)
	add_log("%s 加入了近卫军团，驻地 %s。" % [nh.name, t.name])
	compute_vision()
	changed.emit()
	return "%s 已加入" % nh.name

# ------------------------------------------------------------------ 驻军
func garrison_strength(site: Dictionary) -> int:
	return army_strength(site.get("garrison", []))

## 从英雄部队抽调兵力驻守据点
func garrison_add(site: Dictionary, unit_id: String, count: int, h: Dictionary) -> String:
	var have := 0
	for s in h.army:
		if s.unit == unit_id:
			have = int(s.count)
	var n := mini(count, have)
	if n <= 0:
		return "没有可派出的部队"
	for s in h.army:
		if s.unit == unit_id:
			s.count -= n
	h.army = h.army.filter(func(x): return int(x.count) > 0)
	if not site.has("garrison"):
		site["garrison"] = []
	var found := false
	for g in site.garrison:
		if String(g.unit) == unit_id:
			g.count = int(g.count) + n
			found = true
			break
	if not found:
		site.garrison.append({"unit": unit_id, "count": n})
	add_log("%s 派出 %d 名%s驻守 %s。" % [h.name, n, DB.UNITS[unit_id].name, site.name])
	changed.emit()
	return "驻守 %d 名%s" % [n, DB.UNITS[unit_id].name]

## 把据点驻军收回英雄部队
func garrison_take(site: Dictionary, unit_id: String, count: int, h: Dictionary) -> String:
	var have := 0
	for g in site.get("garrison", []):
		if String(g.unit) == unit_id:
			have = int(g.count)
	var n := mini(count, have)
	if n <= 0:
		return "据点里没有这支部队"
	for g in site.get("garrison", []):
		if String(g.unit) == unit_id:
			g.count = int(g.count) - n
	site["garrison"] = (site.get("garrison", []) as Array).filter(func(x): return int(x.count) > 0)
	army_add(h, unit_id, n)
	add_log("%s 从 %s 撤出 %d 名%s。" % [h.name, site.name, n, DB.UNITS[unit_id].name])
	changed.emit()
	return "撤出 %d 名%s" % [n, DB.UNITS[unit_id].name]

## 己方领地：城镇 / 营地 / 矿场 / 伐木场
func my_sites() -> Array:
	var out := []
	for t in towns:
		if String(t.owner) == faction:
			out.append(t)
	for b in bases:
		if String(b.owner) == faction:
			out.append(b)
	for m in mines:
		if String(m.owner) == faction:
			out.append(m)
	return out

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
	pending_defenses = []
	if use_map_world and not factions.is_empty():
		ai_phase()
	else:
		for h in heroes:
			if h.is_ai and h.alive:
				ai_turn(h)
	# 有势力打到玩家据点：先让玩家决定死守还是撤退，再结算回合
	if pending_defenses.is_empty():
		settle_turn()
	else:
		awaiting_defense = true
		defense_prompt.emit()

## 玩家处理完所有「被进攻」事件之后，才真正结束这一回合
func settle_turn() -> void:
	awaiting_defense = false
	pending_defenses = []
	day += 1
	income()
	for h in heroes:
		if h.alive:
			h.mp = max_mp(h)
			var regen := 2 + int(h.skill.get("wisdom", 0)) * 2
			var fac_id := String(h.faction)
			for t in towns:
				if String(t.owner) == fac_id:
					regen += int(t.buildings.get("mage_tower", 0))
			h.mana = mini(max_mana(h), int(h.mana) + regen)
	if day % 3 == 0:
		random_event()
	compute_vision()
	check_game_over()
	turn_busy = false
	# 每回合自动落盘，防止忘记存档丢进度
	if save_slot != "" and game_over == "":
		Saves.save_game(save_slot)
	toast.emit("第 %d 天 · 回合结算完成" % day)
	changed.emit()

# ------------------------------------------------------------------ 多势力 AI
func ai_phase() -> void:
	for f in factions:
		if bool(f.is_player):
			continue
		if not faction_alive(String(f.id)):
			f.alive = false
			continue
		for h in heroes:
			if not h.alive or not h.is_ai or String(h.faction) != String(f.id):
				continue
			_ai_hero_turn(h, f)

func _ai_hero_turn(h: Dictionary, f: Dictionary) -> void:
	# 兵源：每 3 天补一批，强度跟着全局 ai_power 走
	if day % 3 == 0:
		var pool: Array = DB.RECRUITS.get(String(f.id), [])
		if not pool.is_empty():
			army_add(h, String(pool[mini(2, pool.size() - 1)]), 3 + int(ai_power / 8))
	var goal := _ai_pick_target(h, f)
	if goal.is_empty():
		return
	if not use_map_world or map_terrain == null:
		return
	var tw: Vector3 = goal.get("wpos", Vector3.ZERO)
	_ai_advance(h, tw, 14.0)
	var hp: Vector3 = h.get("wpos", Vector3.ZERO)
	if Vector2(hp.x - tw.x, hp.z - tw.z).length() <= 6.5:
		_ai_attack_site(h, goal)

func _ai_pick_target(h: Dictionary, f: Dictionary) -> Dictionary:
	var best := {}
	var bd := 1e20
	var hp: Vector3 = h.get("wpos", Vector3.ZERO)
	var cands := []
	cands.append_array(bases)
	cands.append_array(towns)
	cands.append_array(mines)
	for s in cands:
		var owner := String(s.get("owner", ""))
		if owner == String(f.id):
			continue
		# 空矿只在没野怪时才去（AI 不和野怪纠缠）
		if owner == "" and (s.get("guards", []) as Array).size() > 0:
			continue
		var sw: Vector3 = s.get("wpos", Vector3.ZERO)
		var d := Vector2(hp.x - sw.x, hp.z - sw.z).length()
		if d < bd:
			bd = d
			best = s
	return best

## 沿地形朝目标推进（挑一个最朝向目标且能走的方向，绕过水面与陡坡）
func _ai_advance(h: Dictionary, target: Vector3, budget: float) -> void:
	var cur: Vector3 = h.get("wpos", target)
	var flat := Vector3(target.x - cur.x, 0.0, target.z - cur.z)
	var dist := flat.length()
	var move := minf(budget, maxf(0.0, dist - 4.5))
	if move < 0.5 or dist < 0.01:
		return
	var dir := flat.normalized()
	var best := cur
	var best_score := -1e9
	for i in range(24):
		var ang := TAU * float(i) / 24.0
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var p := cur + d * move
		if not _ai_walkable(p):
			continue
		var score := d.dot(dir) * 12.0
		if score > best_score:
			best_score = score
			best = p
	if best == cur:
		return
	best.y = _ai_height(best.x, best.z) + 0.05
	h["wpos"] = best
	h["pos"] = Vector2i(roundi(best.x), roundi(best.z))

func _ai_height(x: float, z: float) -> float:
	return 0.5 if map_terrain == null else float(map_terrain.height_at(x, z))

func _ai_walkable(p: Vector3) -> bool:
	if map_terrain == null:
		return true
	var half: float = float(map_terrain.map_size) * 0.44
	if absf(p.x) > half or absf(p.z) > half:
		return false
	var hh := _ai_height(p.x, p.z)
	if hh < 0.5:
		return false
	var slope: float = absf(_ai_height(p.x + 1.4, p.z) - hh) + absf(_ai_height(p.x, p.z + 1.4) - hh)
	return slope < 2.4

func _site_defense(ref: Dictionary) -> Array:
	var out := []
	for g in ref.get("garrison", []):
		out.append(g)
	for g in ref.get("guards", []):
		out.append(g)
	return out

func _ai_attack_site(h: Dictionary, ref: Dictionary) -> void:
	var owner := String(ref.get("owner", ""))
	var defense := _site_defense(ref)
	if defense.is_empty():
		ref["owner"] = String(h.faction)
		ref["garrison"] = []
		ref["guards"] = []
		ref["guarded"] = false
		add_log("%s 的军队占领了 %s。" % [faction_name(String(h.faction)), String(ref.name)])
		return
	if owner == faction:
		# 玩家的据点：挂起，等玩家选死守 / 撤退
		pending_defenses.append({
			"site_id": int(ref.id), "kind": String(ref.get("kind", "mine")), "name": String(ref.name),
			"attacker": String(h.name), "attacker_faction": String(h.faction),
			"attacker_strength": army_strength(h.army),
			"defense": defense.duplicate(true),
			"defense_strength": army_strength(defense),
			"hero_id": int(h.id),
		})
		add_log("%s 的军队正在进攻 %s！" % [faction_name(String(h.faction)), String(ref.name)])
		return
	# AI 之间：战力快速结算，保证回合不卡
	if army_strength(h.army) > army_strength(defense) * 1.1:
		ref["owner"] = String(h.faction)
		ref["garrison"] = []
		ref["guards"] = []
		ref["guarded"] = false
		_scale_army(h, 0.75)
		add_log("%s 夺取了 %s。" % [faction_name(String(h.faction)), String(ref.name)])
	else:
		_scale_defense(ref, 0.7)
		_scale_army(h, 0.6)
		add_log("%s 进攻 %s 失败。" % [faction_name(String(h.faction)), String(ref.name)])

func _scale_army(h: Dictionary, f: float) -> void:
	var arr := []
	for s in h.army:
		var n := int(round(float(s.count) * f))
		if n > 0:
			arr.append({"unit": String(s.unit), "count": n})
	h.army = arr if not arr.is_empty() else [{"unit": "militia", "count": 3}]

func _scale_defense(ref: Dictionary, f: float) -> void:
	var arr := []
	for s in ref.get("garrison", []):
		var n := int(round(float(s.count) * f))
		if n > 0:
			arr.append({"unit": String(s.unit), "count": n})
	ref["garrison"] = arr
	var ga := []
	for s in ref.get("guards", []):
		var n2 := int(round(float(s.count) * f))
		if n2 > 0:
			ga.append({"unit": String(s.unit), "count": n2})
	ref["guards"] = ga

## 玩家对「据点被进攻」做决定：retreat = 撤退（丢产出、保住兵），否则死守
func resolve_defense(retreat: bool) -> void:
	if pending_defenses.is_empty():
		return
	var ev: Dictionary = pending_defenses.pop_front()
	_apply_defense(ev, retreat)
	check_game_over()
	if pending_defenses.is_empty():
		awaiting_defense = false
		settle_turn()
	else:
		defense_prompt.emit()
	changed.emit()

func _apply_defense(ev: Dictionary, retreat: bool) -> void:
	var ref := site_by_id(int(ev.site_id))
	if ref.is_empty():
		return
	var atk := hero(int(ev.hero_id))
	var atk_fac := String(ev.attacker_faction)
	if retreat:
		var moved := _retreat_garrison(ref)
		ref["owner"] = atk_fac
		ref["garrison"] = []
		ref["guards"] = []
		ref["guarded"] = false
		if moved > 0:
			add_log("你放弃 %s，%d 支部队撤往后方，产出随之丢失。" % [String(ref.name), moved])
		else:
			add_log("你放弃 %s，驻军就地解散。" % String(ref.name))
		toast.emit("放弃 %s" % String(ref.name))
		return
	var ds := army_strength(ref.get("garrison", []))
	var as_ := army_strength(atk.army) if not atk.is_empty() else int(ev.attacker_strength)
	if ds >= as_ * 0.85:
		_scale_defense(ref, 0.7)
		if not atk.is_empty():
			_scale_army(atk, 0.55)
		add_log("守军击退了 %s，%s 仍在你手中。" % [String(ev.attacker), String(ref.name)])
		toast.emit("%s 守住了" % String(ref.name))
	else:
		ref["owner"] = atk_fac
		ref["garrison"] = []
		ref["guards"] = []
		ref["guarded"] = false
		if not atk.is_empty():
			_scale_army(atk, 0.6)
		add_log("守军全灭，%s 落入 %s 之手。" % [String(ref.name), faction_name(atk_fac)])
		toast.emit("%s 失守" % String(ref.name))

func _retreat_garrison(ref: Dictionary) -> int:
	var total := 0
	var home := {}
	for b in bases:
		if String(b.owner) == faction:
			home = b
			break
	if home.is_empty():
		for t in towns:
			if String(t.owner) == faction:
				home = t
				break
	for g in ref.get("garrison", []):
		total += int(g.count)
		if home.is_empty():
			continue
		if not home.has("garrison"):
			home["garrison"] = []
		var found := false
		for hg in home.get("garrison", []):
			if String(hg.unit) == String(g.unit):
				hg.count = int(hg.count) + int(g.count)
				found = true
				break
		if not found:
			home["garrison"].append({"unit": String(g.unit), "count": int(g.count)})
	return total

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
	if eff.has("camp") and not tiles.is_empty():
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
	# ---- 多势力地图：消灭所有敌对势力即获胜
	if not factions.is_empty():
		var alive_enemies := 0
		for f in factions:
			if bool(f.is_player):
				continue
			var alive := faction_alive(String(f.id))
			f.alive = alive
			if alive:
				alive_enemies += 1
		if alive_enemies == 0:
			game_over = "win"
			popup.emit("大地重归寂静", "最后一面敌旗倒下了。金矿、伐木场与道路都在你手里。\n\n共用 %d 个回合。" % day, Callable())
			return
		var my_base := false
		for b in bases:
			if String(b.owner) == faction:
				my_base = true
		if not my_base and player_heroes().is_empty():
			game_over = "lose"
			popup.emit("长夜降临", "营地被踏平，最后一位统帅也倒下了。", Callable())
		return
	# ---- 旧的六边形地图：按天灾城镇与英雄判定
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
	if not factions.is_empty():
		var alive := 0
		var total := 0
		for f in factions:
			if bool(f.is_player):
				continue
			total += 1
			if faction_alive(String(f.id)):
				alive += 1
		var gold_n := 0
		var wood_n := 0
		for m in mines:
			if String(m.owner) != faction:
				continue
			if String(m.res) == "wood":
				wood_n += 1
			else:
				gold_n += 1
		return "剩余势力 %d/%d · 矿场 %d · 伐木场 %d · 第 %d 天" % [alive, total, gold_n, wood_n, day]
	var mine_count := 0
	for m in mines:
		if m.owner == faction:
			mine_count += 1
	var town_count := 0
	for t in towns:
		if t.owner == faction:
			town_count += 1
	return "已占领 %d/%d 座矿场 · %d/%d 座城镇 · 第 %d 天" % [mine_count, mines.size(), town_count, towns.size(), day]

# ------------------------------------------------------------------ 存档
## 从存档还原（写档在 autoload/Saves.gd，这里只负责读回来）。
## 可见格不存盘：载入后按英雄与城镇位置重算，省得存档还带着过期视野。
func restore(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	res = (d.get("res", {}) as Dictionary).duplicate(true)
	tiles = (d.get("tiles", {}) as Dictionary).duplicate(true)
	towns = (d.get("towns", []) as Array).duplicate(true)
	mines = (d.get("mines", []) as Array).duplicate(true)
	camps = (d.get("camps", []) as Array).duplicate(true)
	caches = (d.get("caches", []) as Array).duplicate(true)
	bases = (d.get("bases", []) as Array).duplicate(true)
	factions = (d.get("factions", []) as Array).duplicate(true)
	heroes = (d.get("heroes", []) as Array).duplicate(true)
	explored = (d.get("explored", {}) as Dictionary).duplicate(true)
	journal = (d.get("journal", []) as Array).duplicate(true)
	inventory = (d.get("inventory", []) as Array).duplicate(true)
	id_counter = int(d.get("id_counter", 1))
	selected = int(d.get("selected", 0))
	faction = String(d.get("faction", "sentinel"))
	enemy_faction = String(d.get("enemy_faction", "scourge"))
	ai_power = int(d.get("ai_power", 0))
	# 战斗态不入档：清掉临时状态，保证载入后一定能从大地图继续
	pending_battle = {}
	game_over = ""
	turn_busy = false
	pending_defenses = []
	awaiting_defense = false
	visible_cells.clear()
	compute_vision()
	changed.emit()

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
