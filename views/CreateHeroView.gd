class_name CreateHeroView
extends Control
## 创建英雄 = 新建一份存档。
## 选一位统帅 → 输入英雄名字 → 开始战役，立刻落盘并进入大地图。

const ORDER := ["crystal_maiden", "antimage", "luna", "lina", "skeleton_king", "nevermore", "lich", "axe"]

var chosen := "crystal_maiden"
var cards := {}
var detail: VBoxContainer
var name_edit: LineEdit
var err: Label
var last_default := ""

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var hb := UI.hbox(30)
	margin.add_child(hb)

	# ---------------- 左：选英雄 + 起名
	var left_panel := UI.panel(Color("#171d2b"), UI.C_BORDER, 10)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.12
	hb.add_child(left_panel)
	var left := UI.vbox(12)
	left_panel.add_child(left)
	left.add_child(UI.label("◆  新 的 战 役", 14, UI.C_GOLD))
	left.add_child(UI.title("创 建 英 雄", 34))
	left.add_child(UI.label("选一位统帅，再给他 / 她起一个只属于这局战役的名字。创建后会自动生成一份存档。", 13, UI.C_MUTED))
	left.add_child(UI.line(UI.C_GOLD_DIM))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	for key in ORDER:
		var d: Dictionary = DB.HEROES[key]
		var b := UI.button("%s  ·  %s" % [d.name, d.klass], Callable(self, "_pick").bind(key), 15, Vector2(0, 52), Color(d.color))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		cards[key] = b

	left.add_child(UI.line(UI.C_GOLD_DIM))
	left.add_child(UI.label("英雄名字", 14, UI.C_GOLD))
	name_edit = LineEdit.new()
	name_edit.max_length = 12
	name_edit.placeholder_text = "输入英雄名字（必填，最多 12 字）"
	name_edit.add_theme_font_override("font", UI.font())
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.add_theme_color_override("font_color", UI.C_TEXT)
	name_edit.add_theme_color_override("font_placeholder_color", UI.C_MUTED)
	name_edit.add_theme_color_override("caret_color", UI.C_GOLD)
	name_edit.add_theme_stylebox_override("normal", UI.sb(Color("#121826"), UI.C_GOLD_DIM, 6, 2))
	name_edit.add_theme_stylebox_override("focus", UI.sb(Color("#161f30"), UI.C_GOLD, 6, 2))
	name_edit.custom_minimum_size = Vector2(0, 46)
	name_edit.text_changed.connect(func(_t): err.text = "")
	name_edit.text_submitted.connect(func(_t): _start())
	left.add_child(name_edit)

	err = UI.label("", 13, UI.C_RED)
	left.add_child(err)

	var row := UI.hbox(10)
	left.add_child(row)
	row.add_child(UI.ghost_button("← 返回存档列表", func(): Game.goto("title", {}), 14))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(UI.button("开 始 征 战  ▶", _start, 19, Vector2(220, 52)))

	# ---------------- 右：英雄详情
	var right_panel := UI.panel(Color("#141a26"), UI.C_BORDER, 10)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	hb.add_child(right_panel)
	var right := UI.vbox(10)
	right_panel.add_child(right)
	right.add_child(UI.title("统帅档案", 20))
	detail = UI.vbox(10)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail)

	select(chosen, true)

func _pick(key: String) -> void:
	select(key, false)

func select(key: String, force_name: bool) -> void:
	chosen = key
	for k in cards:
		var b: Button = cards[k]
		var on: bool = k == key
		b.add_theme_stylebox_override("normal", UI.sb(Color("#2d3b52") if on else UI.C_PANEL2,
			Color(DB.HEROES[k].color) if on else UI.C_GOLD_DIM, 5, 2 if on else 1))
	# 名字还没被改过时，跟着换默认名
	if force_name or name_edit == null or name_edit.text.strip_edges() == "" or name_edit.text == last_default:
		last_default = String(DB.HEROES[key].name)
		if name_edit != null:
			name_edit.text = last_default
	refresh_detail()

func refresh_detail() -> void:
	for c in detail.get_children():
		detail.remove_child(c)
		c.queue_free()
	var d: Dictionary = DB.HEROES[chosen]
	var top := UI.hbox(16)
	detail.add_child(top)
	var em := TitleView.Emblem.new()
	em.tint = Color(d.color)
	em.glyph = String(d.name).substr(0, 1)
	em.radius = 44.0
	em.custom_minimum_size = Vector2(104, 104)
	top.add_child(em)
	var info := UI.vbox(5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UI.title(d.name, 24))
	info.add_child(UI.label("%s  ·  %s" % [d.en, d.title], 13, Color(d.color)))
	info.add_child(UI.label("攻 %d   防 %d   力 %d   智 %d" % [d.atk, d.def, d.power, d.knowledge], 15, UI.C_TEXT))
	var sp := ""
	for s in d.spells:
		sp += DB.SPELLS[s].name + "  "
	info.add_child(UI.label("初始法术：" + sp, 12, UI.C_MUTED))
	detail.add_child(UI.line(UI.C_GOLD_DIM))
	var bio := UI.label(d.bio, 14, UI.C_TEXT)
	bio.custom_minimum_size = Vector2(0, 86)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(bio)
	var skills := ""
	for k in d.skills:
		skills += "%s Lv%d   " % [DB.SKILLS[k].name, d.skills[k]]
	detail.add_child(UI.label("天赋：" + skills, 13, UI.C_GOLD))
	var army := ""
	for s in d.army:
		army += "%s×%d   " % [DB.UNITS[s.unit].name, s.count]
	detail.add_child(UI.label("起始部队：" + army, 13, UI.C_MUTED))
	detail.add_child(UI.line(UI.C_GOLD_DIM))
	var tip := UI.label("新战役从第 1 天开始，你会带着这位英雄出现在银月城。\n" +
		"每结束一个回合自动存档；也可以在 ☰ 菜单手动保存。", 12, UI.C_MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(tip)

func _start() -> void:
	var nm := name_edit.text.strip_edges()
	if nm == "":
		err.text = "请先输入英雄名字"
		name_edit.grab_focus()
		return
	if nm.length() > 12:
		err.text = "名字最多 12 个字"
		return
	var id := Saves.new_game(chosen, nm)
	if id == "":
		err.text = "存档写入失败，请检查磁盘权限或 user:// 目录"
		return
	Game.say("已创建存档：%s" % nm)
	Game.goto("world", {})
