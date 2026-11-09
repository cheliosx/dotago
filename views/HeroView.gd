class_name HeroView
extends Control

var hero_id := -1
var header: HBoxContainer
var body: HBoxContainer
var hint: Label

func setup(p: Dictionary) -> void:
	hero_id = int(p.get("hero_id", -1))

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(k, 20)
	add_child(margin)
	var v := UI.vbox(10)
	margin.add_child(v)
	header = UI.hbox(12)
	header.custom_minimum_size = Vector2(0, 52)
	v.add_child(header)
	body = UI.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	hint = UI.label("", 14, UI.C_GOLD)
	hint.custom_minimum_size = Vector2(0, 26)
	v.add_child(hint)
	Game.changed.connect(refresh)
	refresh()

func current_hero() -> Dictionary:
	if hero_id > 0:
		var h := Game.hero(hero_id)
		if not h.is_empty() and not h.is_ai:
			return h
	var s := Game.selected_hero()
	if not s.is_empty():
		hero_id = int(s.id)
	return s

func refresh() -> void:
	if not is_instance_valid(header):
		return
	for c in header.get_children():
		header.remove_child(c)
		c.queue_free()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var h := current_hero()
	header.add_child(UI.button("← 大地图", func(): Game.goto("world", {}), 15, Vector2(120, 42), UI.C_MUTED))
	header.add_child(UI.title("英雄殿堂", 26))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	header.add_child(UI.label("可用技能点：" + str(h.skill_points) if not h.is_empty() else "", 16, UI.C_GOLD))
	header.add_child(UI.ghost_button("切换英雄", func(): _cycle_hero()))
	if h.is_empty():
		body.add_child(UI.label("没有可用英雄", 20, UI.C_RED))
		return
	body.add_child(left_column(h))
	body.add_child(middle_column(h))
	body.add_child(right_column(h))

func _cycle_hero() -> void:
	var list := Game.player_heroes()
	if list.size() < 2:
		hint.text = "目前只有一名英雄，去城镇酒馆招募更多"
		return
	var idx := 0
	for i in range(list.size()):
		if int(list[i].id) == hero_id:
			idx = i
	hero_id = int(list[(idx + 1) % list.size()].id)
	Game.selected = hero_id
	refresh()

func left_column(h: Dictionary) -> Control:
	var f := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	f.custom_minimum_size = Vector2(300, 0)
	var s := UI.scroll(UI.vbox(10))
	f.add_child(s)
	var v: VBoxContainer = s.get_child(0)
	var col := Color(h.color)
	v.add_child(UI.title(h.name, 27))
	v.add_child(UI.label("%s  ·  %s  ·  Lv.%d" % [h.en, h.title, h.level], 14, col))
	v.add_child(UI.hsep(4))
	var bio := UI.label(h.bio, 13, UI.C_MUTED)
	bio.custom_minimum_size = Vector2(260, 0)
	v.add_child(bio)
	v.add_child(UI.line(UI.C_GOLD_DIM))
	var st := Game.hero_stats(h)
	v.add_child(UI.title("基础属性", 18))
	for line in [
		["攻击", st.atk, "直接加成全军伤害"],
		["防御", st.def, "直接减免全军受伤"],
		["力量", st.power, "决定法术威力"],
		["知识", st.knowledge, "决定魔法值上限"],
	]:
		var row := UI.hbox(8)
		row.add_child(UI.label(String(line[0]) + "  " + str(line[1]), 17, UI.C_GOLD))
		var d := UI.label(String(line[2]), 12, UI.C_MUTED)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(d)
		v.add_child(row)
	v.add_child(UI.label("经验 %d / %d" % [h.xp, DB.level_xp(int(h.level))], 13, UI.C_MUTED))
	v.add_child(UI.bar(float(h.xp), float(DB.level_xp(int(h.level))), UI.C_GOLD, 260, 12))
	v.add_child(UI.label("魔法 %d / %d     移动力 %d / %d" % [h.mana, Game.max_mana(h), h.mp, Game.max_mp(h)], 13, UI.C_BLUE))
	v.add_child(UI.bar(float(h.mana), float(Game.max_mana(h)), UI.C_PURPLE, 260, 10))
	v.add_child(UI.line(UI.C_GOLD_DIM))
	v.add_child(UI.title("随军部队", 18))
	for stack in h.army:
		var u: Dictionary = DB.UNITS[stack.unit]
		var row2 := UI.hbox(8)
		var l := UI.label("%s  ×%d" % [u.name, int(stack.count)], 14, Color(u.color))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(l)
		row2.add_child(UI.label("速%d 攻%d" % [u.spd, u.atk], 11, UI.C_MUTED))
		v.add_child(row2)
	v.add_child(UI.label("军队战力  %d" % Game.army_strength(h.army), 14, UI.C_GOLD))
	return f

func middle_column(h: Dictionary) -> Control:
	var f := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.size_flags_stretch_ratio = 1.15
	var s := UI.scroll(UI.vbox(10))
	f.add_child(s)
	var v: VBoxContainer = s.get_child(0)
	v.add_child(UI.title("技能树", 22))
	v.add_child(UI.label("每次升级获得 1 点技能点，最多掌握 5 种技能，每种最高 3 级", 13, UI.C_MUTED))
	for sid in DB.SKILLS:
		var d: Dictionary = DB.SKILLS[sid]
		var lvl := int(h.skill.get(sid, 0))
		var card := UI.panel(Color("#202838"), UI.C_GOLD if lvl > 0 else UI.C_GOLD_DIM, 6)
		var cv := UI.hbox(10)
		card.add_child(cv)
		var badge := UI.panel(Color("#2b3550"), UI.C_BLUE, 4)
		badge.add_child(UI.label(d.icon, 20, UI.C_BLUE))
		cv.add_child(badge)
		var info := UI.vbox(3)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(info)
		info.add_child(UI.label("%s    Lv.%d / 3" % [d.name, lvl], 16))
		info.add_child(UI.label(d.desc, 12, UI.C_MUTED))
		var pips := UI.hbox(4)
		for i in range(3):
			var pip := UI.panel(UI.C_GOLD if i < lvl else Color("#2a3040"), UI.C_GOLD_DIM, 3)
			pip.custom_minimum_size = Vector2(26, 8)
			pips.add_child(pip)
		info.add_child(pips)
		var b := UI.button("+" if lvl < 3 else "满", Callable(self, "_learn").bind(sid), 15, Vector2(46, 42), UI.C_GOLD)
		b.disabled = lvl >= 3 or h.skill_points <= 0
		cv.add_child(b)
		v.add_child(card)
	v.add_child(UI.line(UI.C_GOLD_DIM))
	v.add_child(UI.title("法术书", 20))
	for sp in h.spells:
		var sd: Dictionary = DB.SPELLS[sp]
		var row := UI.hbox(8)
		var name_l := UI.label(sd.name, 15, UI.C_PURPLE)
		name_l.custom_minimum_size = Vector2(84, 0)
		row.add_child(name_l)
		var cost_l := UI.label("%d魔" % int(sd.cost), 12, UI.C_BLUE)
		cost_l.custom_minimum_size = Vector2(44, 0)
		row.add_child(cost_l)
		var desc := UI.label(sd.desc, 12, UI.C_MUTED)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.custom_minimum_size = Vector2(180, 0)
		row.add_child(desc)
		v.add_child(row)
	v.add_child(UI.label("在魔法塔建成时，英雄有机会领悟新的法术。", 12, UI.C_MUTED))
	return f

func right_column(h: Dictionary) -> Control:
	var f := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	f.custom_minimum_size = Vector2(330, 0)
	var s := UI.scroll(UI.vbox(10))
	f.add_child(s)
	var v: VBoxContainer = s.get_child(0)
	v.add_child(UI.title("装备栏", 21))
	v.add_child(UI.label("点击已装备的装备可卸下", 12, UI.C_MUTED))
	for slot in DB.SLOTS:
		var iid: String = h.items.get(slot, "")
		var label_text := "%s：%s" % [DB.SLOT_NAMES[slot], DB.ITEMS[iid].name if iid != "" else "空"]
		var b := UI.button(label_text, Callable(self, "_unequip").bind(slot), 13, Vector2(0, 38), UI.C_GOLD if iid != "" else UI.C_MUTED)
		b.disabled = iid == ""
		v.add_child(b)
	v.add_child(UI.line(UI.C_GOLD_DIM))
	v.add_child(UI.title("背包", 20))
	if Game.inventory.is_empty():
		v.add_child(UI.label("背包空空如也。野怪营地与铁匠铺可以获得装备。", 13, UI.C_MUTED))
	else:
		var counts := {}
		for iid in Game.inventory:
			counts[iid] = int(counts.get(iid, 0)) + 1
		for iid in counts:
			var it: Dictionary = DB.ITEMS[iid]
			var card := UI.panel(Color("#202838"), Color(it.get("color", "#c9a227")), 5)
			var cv := UI.vbox(3)
			card.add_child(cv)
			cv.add_child(UI.label("%s  ×%d  [%s]" % [it.name, int(counts[iid]), DB.SLOT_NAMES[it.slot]], 14, UI.C_GOLD))
			cv.add_child(UI.label(it.desc, 12, UI.C_MUTED))
			var stats := ""
			for k in [["atk", "攻"], ["def", "防"], ["power", "力"], ["knowledge", "智"], ["mana", "魔"], ["mp", "移动"], ["spd", "速"]]:
				if it.has(k[0]):
					stats += "%s+%d " % [k[1], int(it[k[0]])]
			cv.add_child(UI.label(stats if stats != "" else "无属性加成", 12, UI.C_BLUE))
			cv.add_child(UI.button("装备", Callable(self, "_equip").bind(iid), 13, Vector2(0, 32), UI.C_GOLD))
			v.add_child(card)
	v.add_child(UI.line(UI.C_GOLD_DIM))
	v.add_child(UI.title("指挥官提示", 17))
	v.add_child(UI.label("英雄不直接上场，但攻防会加成整支军队，并可每回合施放一次法术。", 13, UI.C_MUTED))
	return f

func _learn(sid: String) -> void:
	hint.text = Game.learn_skill(current_hero(), sid)

func _equip(iid: String) -> void:
	hint.text = Game.equip(hero_id, iid)

func _unequip(slot: String) -> void:
	Game.unequip(hero_id, slot)
	hint.text = "已卸下装备"
