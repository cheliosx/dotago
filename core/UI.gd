class_name UI
extends RefCounted
## 暗黑奇幻（魔兽风格）统一 UI 皮肤 + 控件工厂
## 全部由代码构建，保证 iPad / 桌面任意分辨率下都能自适应。

const C_VOID     := Color("#0b0e15")
const C_BG       := Color("#121722")
const C_PANEL    := Color("#1b2130")
const C_PANEL2   := Color("#232b3d")
const C_BORDER   := Color("#6b5836")
const C_GOLD     := Color("#d8b45a")
const C_GOLD_DIM := Color("#8a743f")
const C_TEXT     := Color("#e9e2d2")
const C_MUTED    := Color("#9aa3b2")
const C_BLUE     := Color("#5fb8e8")
const C_RED      := Color("#e0645c")
const C_GREEN    := Color("#78c48a")
const C_PURPLE   := Color("#b48ae0")

static var _font: Font = null
static var _theme: Theme = null

static func font() -> Font:
	if _font == null:
		var f = load("res://assets/fonts/NotoSansSC.ttf")
		if f == null:
			f = ThemeDB.fallback_font
		_font = f
	return _font

static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 16
		_theme = t
	return _theme

static func col(s: String) -> Color:
	return Color(s)

static func sb(bg: Color, border: Color = C_BORDER, radius: int = 6, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

static func panel(bg: Color = C_PANEL, border: Color = C_BORDER, radius: int = 8) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, radius))
	return p

static func label(text: String, size: int = 16, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# 短标签（资源数字、按钮旁文字）不换行，否则在 HBox 里会被挤成竖排
	if text.length() > 24:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func title(text: String, size: int = 24) -> Label:
	return label(text, size, C_GOLD)

static func button(text: String, cb: Callable, size: int = 16, min_size: Vector2 = Vector2(0, 42), accent: Color = C_GOLD) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", sb(C_PANEL2, accent.darkened(0.35), 5, 2))
	b.add_theme_stylebox_override("hover", sb(accent.darkened(0.55), accent, 5, 2))
	b.add_theme_stylebox_override("pressed", sb(accent.darkened(0.3), accent, 5, 2))
	b.add_theme_stylebox_override("disabled", sb(Color("#191c25"), Color("#3a3d47"), 5, 1))
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("#5b6070"))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func ghost_button(text: String, cb: Callable, size: int = 14) -> Button:
	return button(text, cb, size, Vector2(0, 34), Color("#4a5568"))

static func rich(text: String, size: int = 15, color: Color = C_TEXT) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", font())
	r.add_theme_font_override("bold_font", font())
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.text = text
	return r

static func bar(value: float, maximum: float, color: Color, width: float = 200, height: float = 14) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0
	p.max_value = maxf(1.0, maximum)
	p.value = clampf(value, 0, p.max_value)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, height)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", sb(Color("#0d1119"), Color("#3b414d"), 3, 1))
	return p

static func hsep(height: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

static func line(color: Color = C_BORDER, thickness: int = 2) -> HSeparator:
	var s := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_top = thickness / 2.0
	style.content_margin_bottom = thickness / 2.0
	s.add_theme_stylebox_override("separator", style)
	return s

static func vbox(gap: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func hbox(gap: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s

static func chip(text: String, color: Color = C_GOLD) -> PanelContainer:
	var p := panel(color.darkened(0.78), color.darkened(0.25), 4)
	var l := label(text, 13, color)
	p.add_child(l)
	return p

## 全屏渐变背景（绘制在 Main 的底层 Control 上由 Backdrop 调用）
static func draw_backdrop(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	var steps := 12
	var h := rect.size.y / float(steps)
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		canvas.draw_rect(Rect2(rect.position.x, rect.position.y + i * h, rect.size.x, h + 1), top.lerp(bottom, t))

static func draw_ornament(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	# 四角金色花纹
	var d := 26.0
	var w := 2.0
	for sx in [rect.position.x + 14, rect.end.x - 14 - d]:
		for sy in [rect.position.y + 14, rect.end.y - 14 - d]:
			canvas.draw_line(Vector2(sx, sy), Vector2(sx + d, sy), color, w)
			canvas.draw_line(Vector2(sx, sy), Vector2(sx, sy + d), color, w)
			canvas.draw_rect(Rect2(sx + d - 5, sy + d - 5, 5, 5), color)
