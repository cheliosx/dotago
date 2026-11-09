class_name TownView
extends Control

var town_id := -1
var header: HBoxContainer
var body: HBoxContainer
var hint: Label

func setup(p: Dictionary) -> void:
	town_id = int(p.get("town_id", -1))
	if town_id < 0:
		for t in Game.towns:
			if t.owner == Game.faction:
				town_id = int(t.id)
				break

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(k, 20)
	add_child(margin)
	var v := UI.vbox(10)
	margin.add_child(v)
	header = UI.hbox(12)
	header.custom_minimum_size = Vector2(0, 54)
	v.add_child(header)
	body = UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	hint = UI.label("", 14, UI.C_GOLD)
	hint.custom_minimum_size = Vector2(0, 26)
	v.add_child(hint)
	Game.changed.connect(refresh)
	refresh()

func refresh() -> void:
	if not is_instance_valid(header):
		return
	for c in header.get_children():
		header.remove_child(c)
		c.queue_free()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var t := Game.find_by_id(Game.towns, town_id)
	if t.is_empty():
		hint.text = "城镇不存在"
		return
	var col := Color(DB.FACTIONS[t.owner].color)
	header.add_child(UI.button("← 大地图", func(): Game.goto("world", {}), 15, Vector2(120, 42), UI.C_MUTED))
	header.add_child(UI.title("◆ " + String(t.name), 27))
	header.add_child(UI.label(DB.FACTIONS[t.owner].name + "  ·  " + str(t.buildings.size()) + " 座建筑", 15, col))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	for k in DB.RES_ORDER:
		header.add_child(UI.label("%s %d" % [DB.RES[k].short, int(Game.res.get(k, 0))], 14, Color(DB.RES[k].color)))

	# 左：建筑
	var left_frame := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	left_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_frame.size_flags_stretch_ratio = 1.25
	body.add_child(left_frame)
	var ls := UI.scroll(UI.vbox(10))
	left_frame.add_child(ls)
	var lv: VBoxContainer = ls.get_child(0)
	lv.add_child(UI.title("城镇建设", 21))
	lv.add_child(UI.label("每回合只能建设，但一天内可建设多座建筑（消耗资源）", 13, UI.C_MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	lv.add_child(grid)
	for bid in DB.BUILDINGS:
		grid.add_child(building_card(t, bid))

	# 右：招兵 / 铁匠 / 酒馆 / 市场
	var right_frame := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	right_frame.custom_minimum_size = Vector2(420, 0)
	body.add_child(right_frame)
	var rs := UI.scroll(UI.vbox(12))
	right_frame.add_child(rs)
	var rv: VBoxContainer = rs.get_child(0)
	rv.add_child(UI.title("募兵与后勤", 21))
	var h := Game.selected_hero()
	if not h.is_empty():
		rv.add_child(UI.label("接收部队的英雄：%s（需靠近城镇）" % h.name, 13, UI.C_MUTED))
	var recruits: Array = DB.RECRUITS[Game.faction]
	for uid in recruits:
		var u: Dictionary = DB.UNITS[uid]
		var row := UI.hbox(8)
		var badge := UI.panel(Color(u.color).darkened(0.7), Color(u.color), 4)
		badge.add_child(UI.label(String(u.name).substr(0, 1), 14, Color(u.color)))
		row.add_child(badge)
		var info := UI.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label("%s  (T%d)" % [u.name, u.tier], 14))
		info.add_child(UI.label("生命%d 攻%d 防%d 速%d %s" % [u.hp, u.atk, u.def, u.spd, u.trait], 11, UI.C_MUTED))
		row.add_child(info)
		var b := UI.button("×5  %d金" % (int(u.cost) * 5), Callable(self, "_recruit").bind(uid), 13, Vector2(112, 40), Color(u.color))
		var unlocked: bool = t.buildings.has("barracks") or (int(u.range) > 1 and t.buildings.has("archery")) or (int(u.tier) >= 3 and t.buildings.has("mage_tower")) or int(u.tier) == 1
		b.disabled = not unlocked or not DB.can_afford(Game.res, {"gold": int(u.cost) * 5}) or t.owner != Game.faction
		row.add_child(b)
		rv.add_child(row)
	rv.add_child(UI.line(UI.C_GOLD_DIM))

	rv.add_child(UI.title("铁匠铺 · 装备", 18))
	if not t.buildings.has("forge"):
		rv.add_child(UI.label("尚未建造铁匠铺", 13, UI.C_MUTED))
	else:
		for iid in DB.ITEMS:
			var it: Dictionary = DB.ITEMS[iid]
			var row2 := UI.hbox(8)
			var l := UI.label("%s [%s]  %s" % [it.name, DB.SLOT_NAMES[it.slot], it.desc], 12, UI.C_TEXT)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(l)
			var bb := UI.button("%d金" % int(it.price), Callable(self, "_buy").bind(iid), 12, Vector2(78, 34), UI.C_GOLD)
			bb.disabled = not DB.can_afford(Game.res, {"gold": int(it.price)})
			row2.add_child(bb)
			rv.add_child(row2)
	rv.add_child(UI.line(UI.C_GOLD_DIM))

	rv.add_child(UI.title("酒馆 · 招募英雄", 18))
	if not t.buildings.has("tavern"):
		rv.add_child(UI.label("尚未建造酒馆", 13, UI.C_MUTED))
	else:
		for key in ["crystal_maiden", "antimage", "luna", "lina"]:
			var d: Dictionary = DB.HEROES[key]
			var exists := false
			for hh in Game.heroes:
				if hh.def == key:
					exists = true
			var row3 := UI.hbox(8)
			var l3 := UI.label("%s · %s" % [d.name, d.title], 13, Color(d.color))
			l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row3.add_child(l3)
			var b3 := UI.button("已在麾下" if exists else "2500 金", Callable(self, "_hire").bind(key), 12, Vector2(100, 34), Color(d.color))
			b3.disabled = exists or int(Game.res.gold) < 2500
			row3.add_child(b3)
			rv.add_child(row3)
	rv.add_child(UI.line(UI.C_GOLD_DIM))
	rv.add_child(UI.title("市场 · 资源互换", 18))
	if not t.buildings.has("market"):
		rv.add_child(UI.label("尚未建造市场", 13, UI.C_MUTED))
	else:
		var trades := [["wood", "ore"], ["ore", "wood"], ["crystal", "essence"], ["essence", "crystal"]]
		for tr in trades:
			var a: String = tr[0]
			var b2: String = tr[1]
			var b4 := UI.button("5 %s  →  3 %s" % [DB.RES[a].name, DB.RES[b2].name], Callable(self, "_trade").bind(a, b2), 12, Vector2(0, 34), UI.C_MUTED)
			rv.add_child(b4)
	rv.add_child(UI.hsep(10))
	rv.add_child(UI.label("背包中的装备请到「英雄面板」穿戴", 13, UI.C_MUTED))

func building_card(t: Dictionary, bid: String) -> PanelContainer:
	var d: Dictionary = DB.BUILDINGS[bid]
	var lvl := int(t.buildings.get(bid, 0))
	var card := UI.panel(Color("#202838"), UI.C_GOLD_DIM if lvl == 0 else UI.C_GOLD, 6)
	card.custom_minimum_size = Vector2(0, 128)
	var v := UI.vbox(5)
	card.add_child(v)
	var head := UI.hbox(8)
	head.add_child(UI.label(d.icon, 20, UI.C_GOLD))
	head.add_child(UI.label(d.name + ("  Lv.%d" % lvl if lvl > 0 else ""), 16, UI.C_TEXT))
	v.add_child(head)
	var desc := UI.label(d.desc, 12, UI.C_MUTED)
	desc.custom_minimum_size = Vector2(210, 0)
	v.add_child(desc)
	if lvl < int(d.max):
		v.add_child(UI.label(DB.res_text(d.cost), 12, UI.C_GOLD))
	var b := UI.button("建造 / 升级" if lvl > 0 else "建造", Callable(self, "_build").bind(bid), 13, Vector2(0, 34), UI.C_GOLD)
	b.disabled = lvl >= int(d.max) or not DB.can_afford(Game.res, d.cost) or t.owner != Game.faction
	if lvl >= int(d.max):
		b.text = "已满级"
	v.add_child(b)
	return card

func _build(bid: String) -> void:
	hint.text = Game.build(town_id, bid)

func _recruit(uid: String) -> void:
	hint.text = Game.recruit(town_id, uid, 5)

func _buy(iid: String) -> void:
	hint.text = Game.buy_item(town_id, iid)

func _hire(key: String) -> void:
	hint.text = Game.hire_hero(town_id, key)

func _trade(a: String, b: String) -> void:
	hint.text = Game.trade(a, b)
