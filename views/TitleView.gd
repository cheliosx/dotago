class_name TitleView
extends Control
## 主界面 = 存档列表。
## 一份存档就是一局战役（一位自己命名的英雄），点「创建英雄」进入建号界面。

class Emblem extends Control:
	var tint := Color.WHITE
	var glyph := "英"
	var radius := 46.0
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(radius, minf(size.x, size.y) * 0.5)
		draw_circle(c, r + 4, Color(0, 0, 0, 0.35))
		draw_circle(c, r, tint.darkened(0.72))
		draw_arc(c, r, 0, TAU, 64, tint, maxf(1.5, r * 0.06))
		draw_arc(c, r - r * 0.14, 0, TAU, 64, tint.darkened(0.3), 1.0)
		for i in range(6):
			var a := TAU * float(i) / 6.0 - PI / 2.0
			var p := c + Vector2(cos(a), sin(a)) * (r + 1)
			draw_circle(p, maxf(1.5, r * 0.06), UI.C_GOLD)
		var f := UI.font()
		var ts := int(r * 0.95)
		var w := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, ts).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y + ts * 0.35), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, tint.lightened(0.4))

var list_box: VBoxContainer
var delete_armed := ""

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
	left.size_flags_stretch_ratio = 1.02
	hb.add_child(left)
	left.add_child(UI.label("◆  DOTA  HEROES  ◆  回合制策略 RPG", 15, UI.C_GOLD))
	var big := UI.label("冰 封 王 座", 56, Color("#f3e6c0"))
	big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	big.add_theme_constant_override("shadow_offset_x", 3)
	big.add_theme_constant_override("shadow_offset_y", 4)
	left.add_child(big)
	left.add_child(UI.label("探索 · 扩张 · 经营 · 征服 —— 以英雄为核心载体的 4X 战棋", 17, UI.C_MUTED))
	left.add_child(UI.line(UI.C_GOLD_DIM))
	var intro := UI.rich(
		"[color=#c8d6e5]" + DB.STORY_INTRO[0] + "[/color]\n\n" +
		DB.STORY_INTRO[1] + "\n\n" + DB.STORY_INTRO[2], 15)
	intro.custom_minimum_size = Vector2(0, 210)
	intro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(intro)
	var row := UI.hbox(12)
	left.add_child(row)
	row.add_child(UI.ghost_button("世界观与图鉴", func(): Game.goto("codex", {}) ))
	row.add_child(UI.ghost_button("玩法说明", show_help))
	left.add_child(UI.label("Godot 4.7  ·  3D 大地图 / 3D 战场  ·  触控与鼠标通用  ·  原型 v0.2", 13, UI.C_MUTED))

	# ---------------- 右侧：存档
	var right_panel := UI.panel(Color("#171d2b"), UI.C_BORDER, 10)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.15
	hb.add_child(right_panel)
	var right := UI.vbox(12)
	right_panel.add_child(right)
	var head := UI.hbox(10)
	right.add_child(head)
	head.add_child(UI.title("战 役 存 档", 24))
	var cnt := Saves.list().size()
	head.add_child(UI.chip(("共 %d 份" % cnt) if cnt > 0 else "尚无存档", UI.C_GOLD))
	right.add_child(UI.label("每一份存档就是一位自己命名的英雄与其战役进度", 13, UI.C_MUTED))

	var sc := UI.scroll(UI.vbox(10))
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 300)
	right.add_child(sc)
	list_box = sc.get_child(0)
	right.add_child(UI.line(UI.C_GOLD_DIM))
	var create := UI.button("◆   创 建 英 雄   ◆", func(): Game.goto("create", {}), 21, Vector2(0, 56))
	right.add_child(create)
	right.add_child(UI.label("创建英雄会新开一局战役，并立刻生成一份存档", 12, UI.C_MUTED))
	build_list()

func build_list() -> void:
	if list_box == null:
		return
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	var saves := Saves.list()
	if saves.is_empty():
		var empty := UI.panel(Color("#1b2231"), UI.C_GOLD_DIM, 8)
		list_box.add_child(empty)
		var ev := UI.vbox(8)
		empty.add_child(ev)
		ev.add_child(UI.label("还没有任何战役", 18, UI.C_GOLD))
		ev.add_child(UI.label("点下面的「创建英雄」开始第一局：\n先选一位统帅，再给他/她起个名字。", 14, UI.C_MUTED))
		var hint := UI.label("提示：中途每结束一个回合会自动保存，也可以在右上角 ☰ 菜单里手动存档。", 12, UI.C_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ev.add_child(hint)
		return
	for m in saves:
		list_box.add_child(_card(m))

func _card(m: Dictionary) -> Control:
	var id := String(m.get("id", ""))
	var col := Color(String(m.get("hero_color", "#d8b45a")))
	var p := UI.panel(Color("#1c2434"), col.darkened(0.25), 8)
	var hb := UI.hbox(12)
	p.add_child(hb)
	var em := Emblem.new()
	em.tint = col
	em.glyph = String(m.get("hero_name", "英")).substr(0, 1)
	em.radius = 26.0
	em.custom_minimum_size = Vector2(62, 62)
	hb.add_child(em)
	var info := UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	var name_row := UI.hbox(8)
	info.add_child(name_row)
	name_row.add_child(UI.title(String(m.get("hero_name", "无名英雄")), 20))
	name_row.add_child(UI.chip("Lv.%d" % int(m.get("level", 1)), UI.C_GOLD))
	info.add_child(UI.label("%s · %s" % [String(m.get("hero_title", "")), String(m.get("hero_klass", ""))], 12, col))
	info.add_child(UI.label("第 %d 天 · 城镇 %d · 矿场 %d · 兵力 %d" % [
		int(m.get("day", 1)), int(m.get("towns", 0)), int(m.get("mines", 0)), int(m.get("army", 0))], 13, UI.C_TEXT))
	info.add_child(UI.label("保存于 " + Saves.fmt_time(int(m.get("saved_at", 0))), 11, UI.C_MUTED))
	var btns := UI.vbox(6)
	btns.custom_minimum_size = Vector2(96, 0)
	hb.add_child(btns)
	var go := UI.button("继续", Callable(self, "_resume").bind(id), 14, Vector2(94, 34), col)
	btns.add_child(go)
	var del_text := "再点确认" if delete_armed == id else "删除"
	var del := UI.ghost_button(del_text, Callable(self, "_arm_delete").bind(id), 12)
	if delete_armed == id:
		del.add_theme_color_override("font_color", UI.C_RED)
	btns.add_child(del)
	return p

func _resume(id: String) -> void:
	if not Saves.load_game(id):
		Game.say("这份存档读取失败")

func _arm_delete(id: String) -> void:
	if delete_armed != id:
		delete_armed = id
		build_list()
		return
	Saves.delete_save(id)
	delete_armed = ""
	build_list()

func show_help() -> void:
	var b := "【大地图】\n左键点击 / 单指点按 = 查看英雄、城镇、矿场、营地、宝箱；点空白处关闭面板。\n右键点击 / 单指按住拖动 = 行军或进攻。双指拖动平移、捏合缩放。\n\n" + \
		"【战场】\n同样点击查看、右键或拖动下指令。按兵种速度决定行动顺序，远程单位被贴身时伤害减半，英雄每回合可施法一次。\n\n" + \
		"【成长】\n战斗获得经验 → 升级 → 属性与技能点 → 技能树、装备、法术书。\n\n" + \
		"【存档】\n一份存档 = 一位英雄的一局战役。每结束一个回合会自动保存，也可在 ☰ 菜单手动存档。\n\n" + \
		"【胜利条件】\n占领天灾军团全部城镇并击败其所有英雄。"
	Game.dialog("玩法说明", b)
