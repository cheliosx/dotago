class_name WorldView
extends Control

class WorldMap extends Control:
	var view: Control = null
	var reach := {}
	var hover := Vector2i(-1, -1)
	var hex_size := 28.0
	var origin := Vector2.ZERO
	var anim_from := Vector2.ZERO
	var anim_to := Vector2.ZERO
	var anim_t := 1.0
	var anim_hero := -1

	func _process(delta: float) -> void:
		if anim_t < 1.0:
			anim_t = minf(1.0, anim_t + delta * 3.5)
			queue_redraw()

	func animate(from_c: Vector2i, to_c: Vector2i, hero_id: int) -> void:
		anim_from = Hex.center(from_c, hex_size)
		anim_to = Hex.center(to_c, hex_size)
		anim_hero = hero_id
		anim_t = 0.0
		queue_redraw()

	func txt(pos: Vector2, s: String, fs: int, col: Color, centered: bool = true) -> void:
		var f := UI.font()
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := pos.x - (w / 2.0 if centered else 0.0)
		draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func txt_bg(pos: Vector2, s: String, fs: int, col: Color) -> void:
		var f := UI.font()
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(pos.x - w / 2.0 - 4, pos.y - fs, w + 8, fs + 4), Color("#080b12", 0.74))
		txt(pos, s, fs, col)

	func poly(c: Vector2i, shrink: float = 0.0) -> PackedVector2Array:
		var p := Hex.polygon(c, hex_size, shrink)
		var out := PackedVector2Array()
		for v in p:
			out.append(v + origin)
		return out

	func _draw() -> void:
		if view == null or size.x < 10:
			return
		var dw := Hex.SQRT3 * (float(Game.COLS) + 0.5) + 1.0
		var dh := 1.5 * float(Game.ROWS - 1) + 2.0
		hex_size = clampf(minf((size.x - 22) / dw, (size.y - 22) / dh), 13.0, 44.0)
		var bw := dw * hex_size
		var bh := dh * hex_size
		origin = Vector2((size.x - bw) / 2.0 + Hex.SQRT3 * hex_size / 2.0, (size.y - bh) / 2.0 + hex_size)

		# 地形
		for key in Game.tiles:
			var c: Vector2i = Game.tiles[key].c
			var explored: bool = Game.is_explored(c)
			var vis: bool = Game.is_visible(c)
			var t: String = Game.terrain(c)
			var base := Color(DB.TERRAIN[t].color)
			if not explored:
				base = Color("#0e1420")
			elif not vis:
				base = base.lerp(Color("#0a0d15"), 0.58)
			var pts := poly(c, 0.8)
			draw_colored_polygon(pts, base)
			var edge := Color("#39435a", 0.55) if not explored else Color("#c9b78d", 0.16)
			for i in range(6):
				draw_line(pts[i], pts[(i + 1) % 6], edge, 1.0)
			if explored and t == "forest" and vis:
				var p := Hex.center(c, hex_size) + origin
				draw_circle(p + Vector2(-6, 2), 4.0, Color("#1d3826"))
				draw_circle(p + Vector2(4, -3), 5.0, Color("#264a30"))
			if explored and t == "mountain" and vis:
				var p2 := Hex.center(c, hex_size) + origin
				var tri := PackedVector2Array([p2 + Vector2(-13, 8), p2 + Vector2(-2, -10), p2 + Vector2(10, 8)])
				draw_colored_polygon(tri, Color("#7b7d86"))
			if explored and t == "water" and vis:
				var p3 := Hex.center(c, hex_size) + origin
				draw_line(p3 + Vector2(-11, 3), p3 + Vector2(-3, 3), Color("#4f89a8", 0.7), 2.0)
				draw_line(p3 + Vector2(1, 8), p3 + Vector2(10, 8), Color("#4f89a8", 0.7), 2.0)

		# 可达范围
		for key in reach:
			var c := Hex.from_key(key)
			var pts := poly(c, 2.0)
			draw_colored_polygon(pts, Color(0.85, 0.71, 0.32, 0.16))
			for i in range(6):
				draw_line(pts[i], pts[(i + 1) % 6], Color(0.9, 0.76, 0.35, 0.55), 1.4)

		# 建筑与地图物件
		for o in Game.towns + Game.mines + Game.camps + Game.caches:
			if not Game.is_explored(o.pos):
				continue
			var p := Hex.center(o.pos, hex_size) + origin
			var dim := 0.55 if not Game.is_visible(o.pos) else 1.0
			var a := Color(1, 1, 1, dim)
			match o.kind:
				"town": draw_town(p, o, a)
				"mine": draw_mine(p, o, a)
				"camp": draw_glyph(p, "怪", Color("#d0684c"), a)
				"cache": draw_glyph(p, "宝", Color("#d8b45a"), a)

		# 英雄
		for h in Game.heroes:
			if not h.alive:
				continue
			if h.is_ai and not Game.is_visible(h.pos):
				continue
			var p := Hex.center(h.pos, hex_size) + origin
			if int(h.id) == anim_hero and anim_t < 1.0 and anim_from != Vector2.ZERO:
				p = anim_from.lerp(anim_to, anim_t) + origin
			draw_hero(p, h)

		# 悬停框 + 浮动名称（避免相邻格的长名称互相压叠）
		if hover.x >= 0 and Game.tiles.has(Hex.key(hover)):
			var pts := poly(hover, 1.5)
			for i in range(6):
				draw_line(pts[i], pts[(i + 1) % 6], Color("#ffffff", 0.65), 2.0)
			if Game.is_explored(hover):
				var o := Game.object_at(hover)
				var caption := ""
				if not o.is_empty():
					caption = String(o.ref.name)
				else:
					caption = String(DB.TERRAIN[Game.terrain(hover)].name)
				if caption != "":
					var tp := Hex.center(hover, hex_size) + origin + Vector2(0, -hex_size - 5)
					txt_bg(tp, caption, 13, UI.C_GOLD)

	func draw_glyph(p: Vector2, g: String, col: Color, a: Color) -> void:
		# 物件全名仅在悬停浮层中显示，避免相邻格文字互相压叠
		var c := col * a
		draw_circle(p, 14.0, Color("#10141d", 0.85 * a.a))
		draw_arc(p, 14.0, 0, TAU, 32, c, 2.0)
		txt(p + Vector2(0, 6), g, 16, c)

	func draw_mine(p: Vector2, o: Dictionary, a: Color) -> void:
		var col := Color(DB.RES[o.res].color) * a
		var diamond := PackedVector2Array([p + Vector2(0, -14), p + Vector2(11, 0), p + Vector2(0, 14), p + Vector2(-11, 0)])
		draw_colored_polygon(diamond, col.darkened(0.35))
		for i in range(4):
			draw_line(diamond[i], diamond[(i + 1) % 4], col, 1.5)
		txt(p + Vector2(0, 5), DB.RES[o.res].short, 14, Color("#11141c", a.a))
		var owner_mark := ""
		if o.owner == Game.faction:
			owner_mark = "◆"
		elif o.owner == Game.enemy_faction:
			owner_mark = "▲"
		txt_bg(p + Vector2(0, 26), owner_mark + DB.RES[o.res].short, 11, Color(DB.RES[o.res].color, a.a))

	func draw_town(p: Vector2, o: Dictionary, a: Color) -> void:
		var col := Color(DB.FACTIONS[o.owner].color) * a
		var body := Rect2(p.x - 15, p.y - 6, 30, 17)
		draw_rect(body, Color("#20242e", a.a))
		draw_rect(body, col.darkened(0.4), false, 1.5)
		for i in range(3):
			draw_rect(Rect2(p.x - 15 + i * 11, p.y - 11, 7, 6), col.darkened(0.25))
		draw_rect(Rect2(p.x - 3, p.y - 1, 6, 12), col)
		draw_line(p + Vector2(0, -12), p + Vector2(0, -22), UI.C_GOLD * a, 1.5)
		var flag := PackedVector2Array([p + Vector2(0, -22), p + Vector2(11, -19), p + Vector2(0, -16)])
		draw_colored_polygon(flag, col)
		txt_bg(p + Vector2(0, 27), o.name, 11, Color("#f0e7d0", a.a))

	func draw_hero(p: Vector2, h: Dictionary) -> void:
		var col := Color(h.color)
		var sel: bool = int(h.id) == Game.selected and not bool(h.is_ai)
		var r := 17.0
		if sel:
			draw_arc(p, r + 7, 0, TAU, 48, UI.C_GOLD, 2.5)
			draw_arc(p, r + 10, -PI / 2, -PI / 2 + TAU * (float(h.mp) / float(maxf(1.0, float(Game.max_mp(h))))), 32, UI.C_BLUE, 2.5)
		draw_circle(p, r + 2, Color("#080b12", 0.85))
		draw_circle(p, r, col.darkened(0.72))
		draw_arc(p, r, 0, TAU, 40, col if not h.is_ai else UI.C_RED, 2.5)
		txt(p + Vector2(0, 7), String(h.name).substr(0, 1), 19, col.lightened(0.5))
		draw_circle(p + Vector2(13, 13), 8.0, Color("#0d121b"))
		draw_arc(p + Vector2(13, 13), 8.0, 0, TAU, 24, UI.C_GOLD, 1.4)
		txt(p + Vector2(13, 17), str(h.level), 11, UI.C_GOLD)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var c := pick(event.position)
			if c != hover:
				hover = c
				queue_redraw()
				if view.has_method("on_hover"):
					view.call("on_hover", c)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var c := pick(event.position)
			if c.x >= 0 and view.has_method("on_map_click"):
				view.call("on_map_click", c)

	func pick(p: Vector2) -> Vector2i:
		var cells := []
		for key in Game.tiles:
			cells.append(Game.tiles[key].c)
		return Hex.nearest(p - origin, hex_size, cells)

var topbar: HBoxContainer
var sidebar: VBoxContainer
var map: WorldMap
var hint_label: Label

func _ready() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)
	var v := UI.vbox(10)
	root.add_child(v)

	topbar = UI.hbox(10)
	topbar.custom_minimum_size = Vector2(0, 58)
	v.add_child(topbar)

	var body := UI.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var map_frame := UI.panel(Color("#0e121b"), UI.C_BORDER, 8)
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_stretch_ratio = 2.7
	body.add_child(map_frame)
	map = WorldMap.new()
	map.view = self
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.add_child(map)

	var side_frame := UI.panel(Color("#171d2b"), UI.C_BORDER, 8)
	side_frame.custom_minimum_size = Vector2(310, 0)
	body.add_child(side_frame)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_frame.add_child(side_scroll)
	sidebar = UI.vbox(10)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(sidebar)

	hint_label = UI.label("点击高亮六边形移动英雄", 13, UI.C_MUTED)
	hint_label.custom_minimum_size = Vector2(0, 24)
	v.add_child(hint_label)

	Game.changed.connect(refresh)
	if not Game.tiles.is_empty() and Game.game_over == "":
		pass
	if Game.game_over != "":
		show_end()
	refresh()

func refresh() -> void:
	if not is_instance_valid(topbar):
		return
	build_topbar()
	build_sidebar()
	var h := Game.selected_hero()
	map.reach = Game.reachable(h) if not h.is_empty() else {}
	map.queue_redraw()

func build_topbar() -> void:
	for c in topbar.get_children():
		topbar.remove_child(c)
		c.queue_free()
	var crest := UI.panel(Color("#16394f"), UI.C_BLUE, 6)
	topbar.add_child(crest)
	crest.add_child(UI.label("近卫", 17, Color("#bfe6ff")))
	topbar.add_child(UI.label("第 %d 天" % Game.day, 19, UI.C_GOLD))
	for k in DB.RES_ORDER:
		var p := UI.panel(Color("#1b2231"), UI.C_GOLD_DIM, 5)
		var l := UI.label("%s %s %d" % [DB.RES[k].short, DB.RES[k].name, int(Game.res.get(k, 0))], 14, Color(DB.RES[k].color))
		p.add_child(l)
		topbar.add_child(p)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topbar.add_child(spacer)
	topbar.add_child(UI.ghost_button("城镇", func(): _open_town()))
	topbar.add_child(UI.ghost_button("图鉴", func(): Game.goto("codex", {})))
	topbar.add_child(UI.ghost_button("英雄", func(): Game.goto("hero", {})))
	var endb := UI.button("结束回合 ▶", func(): _end_turn(), 17, Vector2(140, 44), UI.C_GOLD)
	topbar.add_child(endb)

func _open_town() -> void:
	for t in Game.towns:
		if t.owner == Game.faction:
			Game.goto("town", {"town_id": int(t.id)})
			return
	Game.say("还没有属于近卫军团的城镇")

func _end_turn() -> void:
	Game.end_turn()
	if Game.game_over != "":
		show_end()

func build_sidebar() -> void:
	for c in sidebar.get_children():
		sidebar.remove_child(c)
		c.queue_free()
	var h := Game.selected_hero()
	sidebar.add_child(UI.label("统帅", 13, UI.C_MUTED))
	if h.is_empty():
		sidebar.add_child(UI.label("没有可用英雄", 17, UI.C_RED))
		return
	var card := UI.panel(Color("#202a3c"), Color(h.color), 6)
	sidebar.add_child(card)
	var cv := UI.vbox(6)
	card.add_child(cv)
	cv.add_child(UI.title("%s  Lv.%d" % [h.name, h.level], 21))
	cv.add_child(UI.label("%s  ·  %s" % [h.title, h.klass], 13, Color(h.color)))
	var st := Game.hero_stats(h)
	cv.add_child(UI.label("攻 %d   防 %d   力 %d   智 %d" % [st.atk, st.def, st.power, st.knowledge], 14))
	cv.add_child(UI.label("移动力  %d / %d" % [h.mp, Game.max_mp(h)], 14, UI.C_BLUE))
	cv.add_child(UI.bar(float(h.mp), float(Game.max_mp(h)), UI.C_BLUE, 260, 10))
	cv.add_child(UI.label("魔法值  %d / %d" % [h.mana, Game.max_mana(h)], 14, UI.C_PURPLE))
	cv.add_child(UI.bar(float(h.mana), float(Game.max_mana(h)), UI.C_PURPLE, 260, 10))
	cv.add_child(UI.label("经验  %d / %d" % [h.xp, DB.level_xp(int(h.level))], 13, UI.C_MUTED))
	cv.add_child(UI.bar(float(h.xp), float(DB.level_xp(int(h.level))), UI.C_GOLD, 260, 8))
	var btns := UI.hbox(6)
	cv.add_child(btns)
	btns.add_child(UI.ghost_button("英雄面板", func(): Game.goto("hero", {}), 13))
	btns.add_child(UI.ghost_button("法术 / 技能", func(): Game.goto("hero", {"tab": 1}), 13))
	sidebar.add_child(UI.line(UI.C_GOLD_DIM))

	sidebar.add_child(UI.label("军 队", 13, UI.C_MUTED))
	var total := 0
	for s in h.army:
		var u: Dictionary = DB.UNITS[s.unit]
		total += int(s.count)
		var row := UI.hbox(8)
		var dot := UI.panel(Color(u.color).darkened(0.7), Color(u.color), 4)
		dot.add_child(UI.label(String(u.name).substr(0, 1), 14, Color(u.color)))
		row.add_child(dot)
		var l := UI.label(u.name, 14, UI.C_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.label("×%d" % int(s.count), 15, UI.C_GOLD))
		sidebar.add_child(row)
	sidebar.add_child(UI.label("总兵力 %d  ·  战力 %d" % [total, Game.army_strength(h.army)], 13, UI.C_MUTED))
	sidebar.add_child(UI.line(UI.C_GOLD_DIM))

	sidebar.add_child(UI.label("当前目标", 13, UI.C_MUTED))
	sidebar.add_child(UI.label(Game.objective(), 14, UI.C_GOLD))
	sidebar.add_child(UI.label("◆ 占领所有天灾城镇并击败其英雄", 13, UI.C_MUTED))
	sidebar.add_child(UI.line(UI.C_GOLD_DIM))

	sidebar.add_child(UI.label("战 报", 13, UI.C_MUTED))
	var n := 0
	for line in Game.journal:
		if n >= 8:
			break
		var jl := UI.label("· " + String(line), 12, UI.C_MUTED)
		jl.custom_minimum_size = Vector2(270, 0)
		sidebar.add_child(jl)
		n += 1
	sidebar.add_child(UI.line(UI.C_GOLD_DIM))
	sidebar.add_child(UI.label("地图：◆我方  ▲敌方  金色格=本回合可达", 12, UI.C_MUTED))

func on_hover(c: Vector2i) -> void:
	if c.x < 0 or not Game.is_explored(c):
		hint_label.text = "未探索的迷雾区域"
		return
	var t: String = Game.terrain(c)
	var o := Game.object_at(c)
	var msg := "%s  ·  移动消耗 %d" % [DB.TERRAIN[t].name, Game.terrain_cost(c)]
	if not o.is_empty():
		msg = o.ref.name + "  ·  " + msg
	if map.reach.has(Hex.key(c)):
		msg += "  ·  消耗 %d 移动力" % int(map.reach[Hex.key(c)])
	hint_label.text = msg

func on_map_click(c: Vector2i) -> void:
	if Game.game_over != "":
		return
	var h := Game.selected_hero()
	if h.is_empty():
		return
	var o := Game.object_at(c)
	# 切换己方英雄 / 进入己方城镇
	if not o.is_empty() and o.kind == "hero" and not o.ref.is_ai:
		Game.selected = o.ref.id
		refresh()
		return
	if not o.is_empty() and o.kind == "town" and o.ref.owner == Game.faction:
		if Hex.dist(c, h.pos) <= 1:
			Game.goto("town", {"town_id": o.ref.id})
		else:
			Game.say("英雄需要走到城镇旁边才能进入")
		return
	if not Game.is_explored(c):
		Game.say("那片区域仍被迷雾笼罩")
		return
	if not map.reach.has(Hex.key(c)):
		Game.say("本回合无法到达（移动力不足或被阻挡）")
		return
	if not o.is_empty() and o.kind == "cache":
		pass
	var old: Vector2i = h.pos
	var ok := Game.move_hero(h, c)
	if ok:
		map.animate(old, c, int(h.id))
	refresh()

func show_end() -> void:
	var win := Game.game_over == "win"
	Game.dialog("战役结束 · " + ("胜利" if win else "失败"),
		("天灾军团已被驱逐，世界之树重新抽出新芽。\n\n用时 %d 个回合。" % Game.day) if win else "近卫军团的旌旗倒下了。\n\n再试一次，也许该更早抢占矿场。",
		func(): Game.goto("title", {}))
