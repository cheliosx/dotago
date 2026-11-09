class_name TitleView
extends Control

class Emblem extends Control:
	var tint := Color.WHITE
	var glyph := "英"
	var radius := 46.0
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, radius + 7, Color(0, 0, 0, 0.35))
		draw_circle(c, radius, tint.darkened(0.72))
		draw_arc(c, radius, 0, TAU, 64, tint, 3.0)
		draw_arc(c, radius - 7, 0, TAU, 64, tint.darkened(0.3), 1.0)
		for i in range(6):
			var a := TAU * float(i) / 6.0 - PI / 2.0
			var p := c + Vector2(cos(a), sin(a)) * (radius + 1)
			draw_circle(p, 3.0, UI.C_GOLD)
		var f := UI.font()
		var ts := 42
		var w := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, ts).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y + ts * 0.35), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, tint.lightened(0.4))

var chosen := "crystal_maiden"
var cards := {}
var detail: VBoxContainer
var emblem: Emblem

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var hb := UI.hbox(36)
	margin.add_child(hb)

	# ---------------- 左侧：标题与叙事
	var left := UI.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	hb.add_child(left)
	var kicker := UI.label("◆  DOTA  HEROES  ◆  回合制策略 RPG", 15, UI.C_GOLD)
	left.add_child(kicker)
	var big := UI.label("冰 封 王 座", 58, Color("#f3e6c0"))
	big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	big.add_theme_constant_override("shadow_offset_x", 3)
	big.add_theme_constant_override("shadow_offset_y", 4)
	left.add_child(big)
	left.add_child(UI.label("探索 · 扩张 · 经营 · 征服 —— 以英雄为核心载体的 4X 战棋", 17, UI.C_MUTED))
	left.add_child(UI.hsep(6))
	left.add_child(UI.line(UI.C_GOLD_DIM))
	var intro := UI.rich(
		"[color=#c8d6e5]" + DB.STORY_INTRO[0] + "[/color]\n\n" +
		DB.STORY_INTRO[1] + "\n\n" + DB.STORY_INTRO[2] + "\n\n" +
		"[color=#d8b45a]" + DB.STORY_INTRO[3] + "[/color]", 16)
	intro.custom_minimum_size = Vector2(0, 250)
	intro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(intro)
	var row := UI.hbox(12)
	left.add_child(row)
	row.add_child(UI.ghost_button("世界观与图鉴", func(): Game.goto("codex", {})))
	row.add_child(UI.ghost_button("玩法说明", func(): show_help()))
	var start := UI.button("◆   开 始 征 战   ◆", func(): _start_game(), 24, Vector2(300, 62))
	left.add_child(start)
	left.add_child(UI.label("Godot 4.7  ·  竖屏/横屏自适应  ·  触控与鼠标通用  ·  原型 v0.1", 13, UI.C_MUTED))

	# ---------------- 右侧：英雄选择
	var right_panel := UI.panel(Color("#171d2b"), UI.C_BORDER, 10)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	hb.add_child(right_panel)
	var right := UI.vbox(12)
	right_panel.add_child(right)
	right.add_child(UI.title("选择你的统帅", 24))
	right.add_child(UI.label("近卫军团 · 英雄会随战斗升级、习得技能、穿戴神装", 14, UI.C_MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	for key in ["crystal_maiden", "antimage", "luna", "lina"]:
		var d: Dictionary = DB.HEROES[key]
		var b := UI.button("%s  ·  %s" % [d.name, d.klass], Callable(self, "_pick").bind(key), 15, Vector2(0, 58), Color(d.color))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		cards[key] = b
	var sep := UI.line(UI.C_GOLD_DIM)
	right.add_child(sep)
	detail = UI.vbox(10)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail)
	var tipbox := UI.panel(Color("#1f2838"), UI.C_GOLD_DIM, 6)
	right.add_child(tipbox)
	var tv := UI.vbox(5)
	tipbox.add_child(tv)
	tv.add_child(UI.label("◆ 战役目标", 15, UI.C_GOLD))
	var tl := UI.label("探索迷雾、占领 8 座矿场与 4 座城镇，最终摧毁天灾军团。英雄是核心：升级、技能、装备与法术会直接改变战局。", 13, UI.C_MUTED)
	tv.add_child(tl)
	select(chosen)

func _start_game() -> void:
	Game.new_game(chosen)
	Game.goto("world", {})

func _pick(key: String) -> void:
	select(key)

func select(key: String) -> void:
	chosen = key
	for k in cards:
		var b: Button = cards[k]
		b.add_theme_stylebox_override("normal", UI.sb(UI.C_PANEL2 if k != key else Color("#2d3b52"), Color(DB.HEROES[k].color) if k == key else UI.C_GOLD_DIM, 5, 2 if k == key else 1))
	refresh_detail()

func refresh_detail() -> void:
	for c in detail.get_children():
		detail.remove_child(c)
		c.queue_free()
	var d: Dictionary = DB.HEROES[chosen]
	var top := UI.hbox(16)
	detail.add_child(top)
	emblem = Emblem.new()
	emblem.tint = Color(d.color)
	emblem.glyph = String(d.name).substr(0, 1)
	emblem.custom_minimum_size = Vector2(108, 108)
	top.add_child(emblem)
	var info := UI.vbox(5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UI.title(d.name, 26))
	info.add_child(UI.label("%s  ·  %s" % [d.en, d.title], 14, Color(d.color)))
	info.add_child(UI.label("攻 %d   防 %d   力 %d   智 %d" % [d.atk, d.def, d.power, d.knowledge], 15, UI.C_TEXT))
	var sp := ""
	for s in d.spells:
		sp += DB.SPELLS[s].name + "  "
	info.add_child(UI.label("初始法术：" + sp, 13, UI.C_MUTED))
	detail.add_child(UI.line(UI.C_GOLD_DIM))
	var bio := UI.label(d.bio, 15, UI.C_TEXT)
	bio.custom_minimum_size = Vector2(0, 90)
	detail.add_child(bio)
	var skills := ""
	for k in d.skills:
		skills += "%s Lv%d   " % [DB.SKILLS[k].name, d.skills[k]]
	detail.add_child(UI.label("天赋：" + skills, 14, UI.C_GOLD))
	var army := ""
	for s in d.army:
		army += "%s×%d   " % [DB.UNITS[s.unit].name, s.count]
	detail.add_child(UI.label("起始部队：" + army, 14, UI.C_MUTED))

func show_help() -> void:
	var t := "玩法说明"
	var b := "【战略层 · 每个回合】\n" + \
		"点击高亮六边形移动英雄（消耗移动力）；占领矿场获取每日资源；进入城镇建造兵营、魔法塔与酒馆；点击野怪营地或敌方英雄发起战斗。\n\n" + \
		"【战斗层 · 回合制战棋】\n" + \
		"按兵种速度决定行动顺序。点击高亮格移动，点击敌军攻击；远程单位被贴身时伤害减半；英雄每回合可施放一次法术，不占用部队行动。\n\n" + \
		"【RPG 成长】\n" + \
		"战斗获得经验 → 升级 → 属性成长与技能点 → 技能树、装备栏、法术书。英雄的攻防会直接加成整支军队。\n\n" + \
		"【胜利条件】\n" + \
		"占领天灾军团全部城镇并击败其所有英雄。"
	Game.dialog(t, b)
