class_name View3DCtrl
extends Control
## 三维视图基类：SubViewport + 相机 + 手势 + 底部信息面板 + 三维几何小工具。
## 大地图（World3DView）与战场（BattleView）共用同一套操作：
##
##   左键点击 / 单指点按          → on_tap()      查看
##   右键点击 / 单指按住拖动       → on_command()  下指令（移动、攻击、施法）
##   左键拖动（桌面）              → 平移镜头
##   双指拖动 / 双指捏合 / 滚轮    → 平移 / 缩放
##
## 触摸端没有右键，所以「按住拖动」就是指令手势：松手时脚下那一格即目标，
## 拖动过程中会持续高亮目标格（on_command_hover）。

const HEX_S := 1.0
const CAM_MIN := 6.0
const CAM_MAX := 44.0
const TAP_SLOP := 14.0
const TAP_TIME := 700
const MOUSE_KEY := 1000

var vp: SubViewport
var svc: SubViewportContainer
var world: Node3D
var cam: Camera3D

var focus := Vector3.ZERO
var focus_target := Vector3.ZERO
var dist := 19.0
var dist_target := 19.0
var pitch := deg_to_rad(56.0)
var map_bounds := Rect2()
var clamp_bounds := true
var bounds_margin := 3.0

var pointers := {}
var tap_pos := Vector2.ZERO
var tap_time := 0
var moved := 0.0
var pinch_prev := -1.0
var pinch_mid := Vector2.ZERO
var cmd_drag := false
var multi := false   # 本次手势用过双指：结束时不触发查看/指令

var sheet: PanelContainer
var sheet_shown := false
var sheet_tween: Tween
var hint: Label

var _mats := {}

# ==================================================================== 场景
func build_viewport() -> void:
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)

	vp = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)

	world = Node3D.new()
	world.name = "World"
	vp.add_child(world)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0a0f18")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#7e94b8")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54, -38, 0)
	sun.light_color = Color("#ffe9c4")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 148, 0)
	fill.light_color = Color("#7fb4e8")
	fill.light_energy = 0.35
	world.add_child(fill)

	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.1
	cam.far = 260.0
	cam.current = true
	world.add_child(cam)
	_update_camera()

func _update_camera() -> void:
	if cam == null:
		return
	var off := Vector3(0, sin(pitch), cos(pitch)) * dist
	cam.position = focus + off
	cam.look_at(focus + Vector3(0, 0.6, 0), Vector3.UP)

func _process(delta: float) -> void:
	dist = lerpf(dist, dist_target, minf(1.0, delta * 8.0))
	focus = focus.lerp(focus_target, minf(1.0, delta * 12.0))
	_update_camera()

func center_on(p: Vector3, animate: bool = true) -> void:
	focus_target = Vector3(p.x, 0.0, p.z)
	_clamp_focus()
	if not animate:
		focus = focus_target
	_update_camera()

func _clamp_focus() -> void:
	if not clamp_bounds or map_bounds.size == Vector2.ZERO:
		return
	focus_target.x = clampf(focus_target.x, map_bounds.position.x - bounds_margin, map_bounds.end.x + bounds_margin)
	focus_target.z = clampf(focus_target.z, map_bounds.position.y - bounds_margin, map_bounds.end.y + bounds_margin)

func _pan(d: Vector2) -> void:
	if cam == null:
		return
	var per_px := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / maxf(1.0, size.y)
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	focus_target += (-right * d.x + fwd * d.y) * per_px
	_clamp_focus()

func zoom_by(factor: float, animated: bool = true) -> void:
	dist_target = clampf(dist_target * factor, CAM_MIN, CAM_MAX)
	if not animated:
		dist = dist_target
		_update_camera()

## 屏幕坐标 → 地面平面（y = height）上的世界点
func ground_hit(p: Vector2, height: float = 0.45) -> Vector3:
	if cam == null:
		return Vector3.ZERO
	var origin := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var t := (height - origin.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	return origin + dir * t

# ==================================================================== 输入
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton:
		if event.device == -1:
			return  # 触摸模拟出来的鼠标事件，避免与 ScreenTouch 重复处理
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.14)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# 鼠标右键 = 下指令（移动 / 攻击 / 施法）
			if event.pressed:
				on_command(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(MOUSE_KEY, event.position)
			else:
				_release(MOUSE_KEY, event.position)
	elif event is InputEventMouseMotion:
		if event.device == -1:
			return
		if pointers.has(MOUSE_KEY):
			_drag(MOUSE_KEY, event.position)
		else:
			on_hover(event.position)
	accept_event()

func _press(key: int, pos: Vector2) -> void:
	pointers[key] = pos
	if pointers.size() == 1:
		tap_pos = pos
		tap_time = Time.get_ticks_msec()
		moved = 0.0
		cmd_drag = false
		multi = false
	elif pointers.size() == 2:
		var pts := pointers.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		pinch_prev = a.distance_to(b)
		pinch_mid = (a + b) * 0.5
		# 一旦是双指手势，就不再当查看/指令处理，避免缩放收尾误下指令
		multi = true
		cmd_drag = false

func _drag(key: int, pos: Vector2) -> void:
	if not pointers.has(key):
		return
	var prev: Vector2 = pointers[key]
	pointers[key] = pos
	if pointers.size() == 1:
		if multi:
			return
		moved += (pos - prev).length()
		if moved <= 8.0:
			return
		if key == MOUSE_KEY:
			_pan(pos - prev)     # 桌面：左键拖动平移
		else:
			cmd_drag = true      # 触摸：按住拖动 = 下指令
			on_command_hover(pos)
	elif pointers.size() == 2:
		var pts := pointers.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var cur := a.distance_to(b)
		if pinch_prev > 1.0 and cur > 1.0:
			zoom_by(pinch_prev / cur, false)
			pinch_prev = cur
		var mid := (a + b) * 0.5
		_pan(mid - pinch_mid)
		pinch_mid = mid
		moved += 10.0

func _release(key: int, pos: Vector2) -> void:
	if not pointers.has(key):
		return
	pointers.erase(key)
	if not pointers.is_empty():
		return
	if multi:
		multi = false
		cmd_drag = false
		pinch_prev = -1.0
		return
	if cmd_drag:
		cmd_drag = false
		on_command_hover_end()
		on_command(pos)
		return
	var dt := Time.get_ticks_msec() - tap_time
	if moved < TAP_SLOP and dt < TAP_TIME:
		on_tap(pos)
	pinch_prev = -1.0

# ------- 子类实现 -------
func on_tap(_pos: Vector2) -> void:
	pass

func on_command(_pos: Vector2) -> void:
	pass

func on_command_hover(_pos: Vector2) -> void:
	pass

func on_command_hover_end() -> void:
	pass

func on_hover(_pos: Vector2) -> void:
	pass

# ==================================================================== 底部信息面板
func build_sheet() -> void:
	sheet = UI.panel(Color("#161d2b"), UI.C_GOLD, 10)
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.visible = false
	add_child(sheet)
	# 容器的最小高度要等子节点重排之后才准，晚一帧变高时把底边重新贴住屏幕
	sheet.resized.connect(_pin_sheet_bottom)

func _pin_sheet_bottom() -> void:
	if sheet_shown and is_instance_valid(sheet):
		sheet.position.y = size.y - 12.0 - sheet.size.y

func show_sheet() -> void:
	sheet_shown = true
	sheet.visible = true
	fill_sheet()
	_layout_sheet(true)

func hide_sheet() -> void:
	if not sheet_shown:
		return
	sheet_shown = false
	_layout_sheet(true)

func fill_sheet() -> void:
	pass

func _layout_sheet(animate: bool) -> void:
	# 宽度给足、高度由内容决定；内容超出会被裁掉，所以不能写死高度
	var w := minf(size.x - 28.0, 1060.0)
	sheet.size.x = w
	sheet.reset_size()
	if sheet.size.x < w:
		sheet.size.x = w
	var h := sheet.size.y
	var x := (size.x - sheet.size.x) * 0.5
	var target_y := size.y - h - 12.0 if sheet_shown else size.y + 10.0
	# 先杀掉上一段滑动动画：否则「刚关掉又立刻打开」时，关闭动画的收尾回调会把面板再隐藏掉
	if sheet_tween != null and sheet_tween.is_valid():
		sheet_tween.kill()
	if animate:
		sheet_tween = create_tween()
		sheet_tween.tween_property(sheet, "position", Vector2(x, target_y), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if not sheet_shown:
			sheet_tween.tween_callback(_hide_sheet_if_closed)
	else:
		sheet.position = Vector2(x, target_y)
		sheet.visible = sheet_shown

func _hide_sheet_if_closed() -> void:
	if not sheet_shown:
		sheet.visible = false

## 面板高度不随宽度抖动的标签
func nowrap(text: String, size: int, col: Color) -> Label:
	var l := UI.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(sheet):
		_layout_sheet(false)
		if hint != null:
			hint.size = Vector2(size.x - 36, 20)

# ==================================================================== 三维小工具
func mat(col: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [col.to_html(true), str(unshaded)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.88
	m.metallic = 0.05
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m

func add_box(parent: Node3D, pos: Vector3, sz: Vector3, col: Color, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat(col)
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi

func add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, col: Color, segs: int = 8, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat(col)
	mi.position = pos
	parent.add_child(mi)
	return mi

func add_cone(parent: Node3D, pos: Vector3, radius: float, height: float, col: Color, segs: int = 6) -> MeshInstance3D:
	return add_cyl(parent, pos, radius, height, col, segs, 0.0)

func add_label(parent: Node3D, text: String, pos: Vector3, col: Color, size_px: int = 42, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font()
	l.font_size = size_px
	l.pixel_size = 0.0085
	l.modulate = col
	l.outline_size = 5
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = false
	# 文字不投影：Label3D 默认会投影，文字影子贴在旁边地形上看起来像重影
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = pos
	parent.add_child(l)
	return l

func terrain_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func overlay_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## 只给「区域外沿」画轮廓线，避免每格描边形成一片噪声
func add_region_edges(st: SurfaceTool, lit: Dictionary, s: float, y_of: Callable, col: Color, width: float = 0.075) -> void:
	var me := self
	for key in lit:
		var c := Hex.from_key(key)
		var y: float = y_of.call(c)
		for i in range(6):
			var out := Hex3D.edge_outward(c, s, i)
			var probe := Hex3D.to_world(c, s) + out * s * 1.08
			var nb := Hex3D.from_world(probe, s)
			if lit.has(Hex.key(nb)):
				continue
			Hex3D.add_edge(st, c, s, 0.92, y, i, col, width)
