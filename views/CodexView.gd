class_name CodexView
extends Control

var body: HBoxContainer
var detail: VBoxContainer

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(k, 24)
	add_child(margin)
	var v := UI.vbox(12)
	margin.add_child(v)
	var head := UI.hbox(12)
	head.custom_minimum_size = Vector2(0, 52)
	head.add_child(UI.button("← 返回", func(): Game.goto("world" if not Game.tiles.is_empty() else "title", {}), 15, Vector2(120, 42), UI.C_MUTED))
	head.add_child(UI.title("编年史 · 世界观图鉴", 27))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UI.label("Dota1 英雄与艾泽拉斯式暗黑奇幻叙事", 13, UI.C_MUTED))
	v.add_child(head)
	body = UI.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	# 左：序章 + 图鉴目录
	var left := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	left.custom_minimum_size = Vector2(340, 0)
	body.add_child(left)
	var ls := UI.scroll(UI.vbox(10))
	left.add_child(ls)
	var lv: VBoxContainer = ls.get_child(0)
	lv.add_child(UI.title("序章", 20))
	for p in DB.STORY_INTRO:
		var l := UI.label(p, 13, UI.C_TEXT)
		l.custom_minimum_size = Vector2(290, 0)
		lv.add_child(l)
	lv.add_child(UI.line(UI.C_GOLD_DIM))
	lv.add_child(UI.title("词条", 20))
	for i in range(DB.LORE.size()):
		var entry: Dictionary = DB.LORE[i]
		lv.add_child(UI.button("◆ " + String(entry.title), Callable(self, "_show_lore").bind(i), 14, Vector2(0, 38), UI.C_MUTED))
	lv.add_child(UI.line(UI.C_GOLD_DIM))
	lv.add_child(UI.title("战术手册", 20))
	for t in DB.TIPS:
		var tl := UI.label("· " + String(t), 12, UI.C_MUTED)
		tl.custom_minimum_size = Vector2(290, 0)
		lv.add_child(tl)

	# 右：词条详情 + 战报 + 英雄传记
	var right := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rs := UI.scroll(UI.vbox(12))
	right.add_child(rs)
	detail = rs.get_child(0)
	_show_lore(0)

func _show_lore(i: int) -> void:
	for c in detail.get_children():
		detail.remove_child(c)
		c.queue_free()
	var e: Dictionary = DB.LORE[i]
	detail.add_child(UI.title(String(e.title), 26))
	detail.add_child(UI.line(UI.C_GOLD_DIM))
	var l := UI.label(String(e.text), 17, UI.C_TEXT)
	l.custom_minimum_size = Vector2(520, 0)
	detail.add_child(l)
	detail.add_child(UI.hsep(14))
	detail.add_child(UI.title("英雄传记", 21))
	for key in DB.HEROES:
		var h: Dictionary = DB.HEROES[key]
		var card := UI.panel(Color("#202838"), Color(h.color), 5)
		var cv := UI.vbox(3)
		card.add_child(cv)
		cv.add_child(UI.label("%s  ·  %s  ·  %s" % [h.name, h.en, h.title], 15, Color(h.color)))
		var b := UI.label(String(h.bio), 12, UI.C_MUTED)
		b.custom_minimum_size = Vector2(500, 0)
		cv.add_child(b)
		detail.add_child(card)
	detail.add_child(UI.hsep(12))
	detail.add_child(UI.title("战役日志", 21))
	if Game.journal.is_empty():
		detail.add_child(UI.label("尚无记录。", 13, UI.C_MUTED))
	for line in Game.journal:
		var jl := UI.label("· " + String(line), 12, UI.C_MUTED)
		jl.custom_minimum_size = Vector2(520, 0)
		detail.add_child(jl)
