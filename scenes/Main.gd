extends Control
## 根控制器：全屏背景、视图切换、全局提示与模态窗

class Backdrop extends Control:
	var grain: Texture2D = null
	var vignette: Texture2D = null

	func _ready() -> void:
		grain = load("res://assets/img/grain.png")
		vignette = load("res://assets/img/vignette.png")
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UI.draw_backdrop(self, r, Color("#121a28"), Color("#070910"))
		# 星尘
		for i in range(90):
			var sx := fmod(float(i) * 137.31 + sin(float(i) * 3.7) * 53.0, size.x)
			var sy := fmod(float(i) * 71.17 + cos(float(i) * 2.3) * 41.0, size.y * 0.62)
			var a := 0.08 + 0.20 * (sin(float(i) * 5.1) * 0.5 + 0.5)
			draw_circle(Vector2(sx, sy), 1.1 + fmod(float(i), 3.0) * 0.35, Color("#cfe4ff", a))
		# 远处冷光
		var glow := Vector2(size.x * 0.75, size.y * 0.34)
		for i in range(9):
			var rr := 260.0 - float(i) * 26.0
			draw_circle(glow, rr, Color("#2e7f9c", 0.012))
		# 冰封王座：左侧冰棘
		draw_ice_spires(size.x * 0.06, size.y, 0.85)
		draw_ice_spires(size.x * 0.20, size.y, 0.55)
		# 世界之树：右侧巨树剪影
		draw_world_tree(Vector2(size.x * 0.79, size.y * 1.02), 1.0)
		# 底部远景山脊剪影
		var base := size.y
		for layer in range(3):
			var col := Color("#161d2b").lerp(Color("#0a0d14"), float(layer) / 3.0)
			var pts := PackedVector2Array()
			pts.append(Vector2(0, base))
			var seedv := 17.0 + layer * 41.0
			for i in range(13):
				var x := size.x * float(i) / 12.0
				var y := base - 70.0 - layer * 42.0 - (sin(i * 1.7 + seedv) * 0.5 + 0.5) * (60.0 + layer * 26.0)
				pts.append(Vector2(x, y))
			pts.append(Vector2(size.x, base))
			draw_colored_polygon(pts, col)
		# 细密六边形暗纹
		var line_col := Color("#c9a227", 0.05)
		for gy in range(9):
			for gx in range(15):
				var c := Vector2i(gx, gy)
				var pts := Hex.polygon(c, 30.0)
				var off := Vector2(-20.0, 10.0)
				for i in range(6):
					draw_line(pts[i] + off, pts[(i + 1) % 6] + off, line_col, 1.0)
		# 颗粒质感 + 暗角
		if grain != null:
			draw_texture_rect(grain, r, true, Color(1, 1, 1, 0.55))
		if vignette != null:
			draw_texture_rect(vignette, r, false, Color(1, 1, 1, 0.85))
		UI.draw_ornament(self, Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color("#c9a227").darkened(0.35))

	func draw_ice_spires(cx: float, ground: float, scale: float) -> void:
		var h := size.y * 0.42 * scale
		for i in range(5):
			var x := cx + float(i - 2) * 26.0 * scale
			var top := ground - h * (0.55 + 0.45 * (sin(float(i) * 2.1 + cx) * 0.5 + 0.5))
			var w := 22.0 * scale
			var tri := PackedVector2Array([Vector2(x - w, ground), Vector2(x, top), Vector2(x + w, ground)])
			draw_colored_polygon(tri, Color("#1b3448", 0.72))
			draw_line(Vector2(x, top), Vector2(x + w * 0.4, ground - h * 0.35), Color("#5fb8e8", 0.18), 1.5)

	func draw_world_tree(root_pos: Vector2, scale: float) -> void:
		var h := size.y * 0.58 * scale
		var trunk_w := 46.0 * scale
		# 主干
		var trunk := PackedVector2Array([
			root_pos + Vector2(-trunk_w * 1.5, 0),
			root_pos + Vector2(-trunk_w * 0.55, -h * 0.72),
			root_pos + Vector2(-trunk_w * 0.25, -h),
			root_pos + Vector2(trunk_w * 0.25, -h),
			root_pos + Vector2(trunk_w * 0.55, -h * 0.72),
			root_pos + Vector2(trunk_w * 1.5, 0),
		])
		draw_colored_polygon(trunk, Color("#0c1a1b", 0.88))
		# 根系
		for i in range(5):
			var dx := float(i - 2) * 40.0 * scale
			draw_line(root_pos + Vector2(0, -20.0 * scale), root_pos + Vector2(dx * 2.2, 18.0 * scale), Color("#0c1a1b", 0.85), 12.0 * scale)
		# 枝干
		for i in range(7):
			var a := -PI / 2.0 + float(i - 3) * 0.38
			var start := root_pos + Vector2(0, -h * (0.62 + 0.04 * float(i % 3)))
			var length := h * (0.30 + 0.05 * float(i % 3))
			var end := start + Vector2(cos(a), sin(a)) * length
			draw_line(start, end, Color("#0c1a1b", 0.9), (11.0 - float(i % 3) * 2.0) * scale)
			draw_line(end, end + Vector2(cos(a - 0.5), sin(a - 0.5)) * length * 0.35, Color("#0c1a1b", 0.75), 5.0 * scale)
		# 树冠光晕
		var crown := root_pos + Vector2(0, -h * 0.92)
		for i in range(7):
			var rr := 150.0 * scale - float(i) * 17.0 * scale
			draw_circle(crown, rr, Color("#2c8f7e", 0.018))
		for i in range(11):
			var a := TAU * float(i) / 11.0
			var p := crown + Vector2(cos(a), sin(a)) * (92.0 + 24.0 * sin(float(i) * 2.3)) * scale
			draw_circle(p, (40.0 + 12.0 * sin(float(i) * 4.1)) * scale, Color("#12332f", 0.55))
		draw_circle(crown, 46.0 * scale, Color("#2f8f78", 0.10))

var content: Control
var overlay: Control

func _ready() -> void:
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Backdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	Game.goto_view.connect(_on_goto)
	Game.toast.connect(_on_toast)
	Game.popup.connect(_on_popup)
	_on_goto("title", {})

func _on_goto(view: String, payload: Dictionary) -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	var v: Control
	match view:
		"title":  v = TitleView.new()
		"world":  v = WorldView.new()
		"town":   v = TownView.new()
		"hero":   v = HeroView.new()
		"battle": v = BattleView.new()
		"codex":  v = CodexView.new()
		_: v = WorldView.new()
	if payload.has("town_id") and v.has_method("setup"):
		v.call("setup", payload)
	elif v.has_method("setup"):
		v.call("setup", payload)
	content.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_toast(text: String) -> void:
	var p := UI.panel(Color("#20283a"), UI.C_GOLD, 6)
	var l := UI.label("  " + text + "  ", 16, UI.C_GOLD)
	p.add_child(l)
	p.reset_size()
	p.position = Vector2((size.x - p.size.x) / 2.0, 96)
	overlay.add_child(p)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

func _on_popup(title: String, body: String, cb: Callable) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)
	var card := UI.panel(Color("#1c2231"), UI.C_GOLD, 10)
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var v := UI.vbox(14)
	card.add_child(v)
	v.add_child(UI.title(title, 26))
	v.add_child(UI.line(UI.C_GOLD_DIM))
	var body_l := UI.label(body, 17, UI.C_TEXT)
	body_l.custom_minimum_size = Vector2(500, 0)
	v.add_child(body_l)
	var ok := UI.button("继续", func(): _close_popup(shade, cb), 17, Vector2(160, 44))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ok)

func _close_popup(shade: Control, cb: Callable) -> void:
	shade.queue_free()
	if cb.is_valid():
		cb.call()
