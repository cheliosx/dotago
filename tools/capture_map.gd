extends SceneTree
## 主地图交互验收：
##   点击 = 查看 / 走去，拖动 = 平移镜头（不再有右键指令）
##   走到目标附近 → 自动弹事件菜单（金矿问是否占领 / 野怪问是否开打）

var step := 0
var timer := 0
var G: Node = null
var main_ref: Node = null
var view: Node = null
var mine: Node = null
var camp: Node = null
var focus_before := Vector3.ZERO

func _process(_d) -> bool:
	timer += 1
	var v := _view()
	match step:
		0:
			G = root.get_node_or_null("/root/Game")
			main_ref = load("res://scenes/Main.tscn").instantiate()
			root.add_child(main_ref)
			step = 1
		1:
			G.new_game("crystal_maiden")
			G.goto("world", {})
			step = 2
			timer = 0
		2:
			if v == null or _sn(v) != "WorldMapView.gd":
				return false
			view = v
			print("[M] 视图 = %s，城镇 %d 矿场 %d 营地 %d 英雄 %d" % [
				_sn(view), G.towns.size(), G.mines.size(), G.camps.size(), G.heroes.size()])
			mine = _find_poi(v, "mine")
			camp = _find_poi(v, "camp")
			print("[M] 测试矿场 = %s，营地 = %s" % [
				String((mine as Node).title) if mine != null else "无",
				String((camp as Node).title) if camp != null else "无"])
			step = 3
			timer = 0
		3:
			if timer > 40:
				_save("shot_map")
				# 把镜头挪到矿场（模拟玩家拖过去），再点它
				v.call("center_on", (mine as Node3D).global_position)
				step = 4
				timer = 0
		4:
			if timer > 25:
				var sp: Vector2 = _poi_screen(v, mine)
				print("[M] 矿场屏幕坐标 %s（在屏幕内=%s）" % [sp, str(sp.x > 0 and sp.y > 0 and sp.x < 1280 and sp.y < 800)])
				v.call("on_tap", sp)
				var path: Dictionary = v.get("hero_paths")
				print("[M] 单击矿场 → 面板=%s 英雄是否移动=%s（应为 false）" % [
					str(v.get("sheet_shown")), str(not path.is_empty())])
				step = 40
				timer = 0
		40:
			if timer > 16:
				_save("shot_map_inspect")
				# 双击同一地点 = 前往（先补一次点击刷新时间戳，再立刻点第二下）
				var sp3: Vector2 = _poi_screen(v, mine)
				v.call("on_tap", sp3)
				v.call("on_tap", sp3)
				var path2: Dictionary = v.get("hero_paths")
				var pend = v.get("pending_poi")
				print("[M] 双击矿场 → 已出发=%s 目标=%s" % [
					str(not path2.is_empty()),
					String((pend as Node).title) if pend != null else "无"])
				step = 5
				timer = 0
		5:
			# 等英雄走到（路径排空）
			if timer > 20:
				var path2: Dictionary = v.get("hero_paths")
				if path2.is_empty():
					var el = v.get("event_layer")
					print("[M] 到达目的地，事件弹窗=%s" % str(el != null and is_instance_valid(el)))
					step = 6
					timer = 0
				elif timer > 700:
					print("[M] 超时：还没走到，路径剩余 %d" % (path2.values()[0] as Array).size())
					step = 10
		6:
			if timer > 8:
				_save("shot_map_event")
				print("[M] 弹窗文本 = %s" % _popup_text(v))
				print("[M] 弹窗按钮 = %s" % str(_popup_buttons(v)))
				step = 7
				timer = 0
		7:
			# 点「发起战斗」→ 应该进入 3D 战场
			if timer > 4:
				var ok := _press_button(v, ["发起战斗", "占 领"])
				print("[M] 点击弹窗按钮 = %s" % str(ok))
				step = 8
				timer = 0
		8:
			if timer > 6:
				print("[M] 战斗入口视图 = %s（应为 BattleView.gd）" % _sn(v))
				G.goto("world", {})
				step = 9
				timer = 0
		9:
			# 回到地图，清掉一个矿场的守军，验证「占领」分支
			if timer > 30:
				v = _view()
				if v == null or _sn(v) != "WorldMapView.gd":
					return false
				view = v
				mine = _find_poi(v, "mine")
				camp = _find_poi(v, "camp")
				var ref: Dictionary = v.call("_poi_ref", mine)
				ref.guards = []
				ref.guarded = false
				v.call("_ask_poi", mine)
				print("[M] 无守军矿场事件 = %s" % _popup_text(v))
				print("[M] 按钮 = %s" % str(_popup_buttons(v)))
				step = 10
				timer = 0
		10:
			if timer > 6:
				_save("shot_map_event_capture")
				var ok2 := _press_button(v, ["占 领"])
				print("[M] 点击「占 领」= %s" % str(ok2))
				step = 11
				timer = 0
		11:
			if timer > 8:
				var own: String = String(v.call("_poi_owner", mine))
				print("[M] 占领后归属=%s 弹窗还开着=%s" % [own, str(v.get("event_layer") != null)])
				_save("shot_map_after")
				# 站在旁边再点一次：应当直接弹事件菜单，而不是先开面板
				var h2 = G.selected_hero()
				var d2: float = (v.call("_hero_wpos", h2) as Vector3).distance_to((mine as Node3D).global_position)
				v.call("on_tap", _poi_screen(v, mine))
				print("[M] 旁边点矿场（距离 %.1f 米）→ 弹窗=%s 面板=%s 按钮=%s" % [
					d2, str(v.get("event_layer") != null), str(v.get("sheet_shown")),
					str(_popup_buttons(v))])
				v.call("_close_event")
				step = 12
				timer = 0
		12:
			# 拖动 = 平移镜头，且不触发查看
			if timer > 4:
				focus_before = v.get("focus_target")
				var mid := Vector2(700, 400)
				v.call("_press", 1000, mid)
				for i in range(1, 13):
					v.call("_drag", 1000, mid + Vector2(i * 12, i * 4))
				v.call("_release", 1000, mid + Vector2(144, 48))
				var after: Vector3 = v.get("focus_target")
				print("[M] 拖动平移：focus %s → %s（变化 %.2f 米）面板=%s" % [
					focus_before, after, focus_before.distance_to(after), str(v.get("sheet_shown"))])
				step = 13
				timer = 0
		13:
			# 点空地：面板关闭 + 出发（挑一个远离所有地点的方向）
			if timer > 4:
				var h = G.selected_hero()
				var from: Vector3 = v.call("_hero_wpos", h)
				var best_target := from
				for ang in [0.0, 0.7, 1.4, 2.1, 2.8, 3.5, 4.2, 4.9, 5.6]:
					var t := from + Vector3(cos(ang) * 11.0, 0, sin(ang) * 11.0)
					var okp := true
					for q in v.get("pois"):
						if Vector2((q as Node3D).global_position.x - t.x, (q as Node3D).global_position.z - t.z).length() < 12.0:
							okp = false
							break
					if okp:
						best_target = t
						break
				v.call("on_tap", _world_screen(v, best_target))
				var path3: Dictionary = v.get("hero_paths")
				print("[M] 点空地 %s → 面板=%s 出发=%s 路径点=%d" % [
					best_target, str(v.get("sheet_shown")), str(not path3.is_empty()),
					(path3.get(int(h.id), []) as Array).size()])
				step = 14
				timer = 0
		14:
			if timer == 14:
				_save("shot_map_walk")
			if timer > 70:
				step = 15
				timer = 0
		15:
			# 野怪营地：验证到达事件文案与按钮
			if timer > 2:
				v.call("_ask_poi", camp)
				print("[M] 营地事件 = %s" % _popup_text(v))
				print("[M] 营地按钮 = %s" % str(_popup_buttons(v)))
				step = 16
				timer = 0
		16:
			if timer > 8:
				_save("shot_map_camp_event")
				print("[M] 完成")
				return true
	return false

# ---------------------------------------------------------------- 工具
func _find_poi(v: Node, kind: String) -> Node:
	for p in v.get("pois"):
		if String((p as Node).kind) == kind:
			return p
	return null

func _poi_screen(v: Node, poi: Node) -> Vector2:
	var cam: Camera3D = v.get("cam")
	return cam.unproject_position((poi as Node3D).global_position + Vector3(0, 2.2, 0))

func _world_screen(v: Node, wp: Vector3) -> Vector2:
	var cam: Camera3D = v.get("cam")
	return cam.unproject_position(wp)

func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)

func _popup_buttons(v: Node) -> Array:
	var out: Array = []
	var el = v.get("event_layer")
	if el != null and is_instance_valid(el):
		_collect_buttons(el, out)
	var names: Array = []
	for b in out:
		names.append(String((b as Button).text))
	return names

func _popup_text(v: Node) -> String:
	var el = v.get("event_layer")
	if el == null or not is_instance_valid(el):
		return "无"
	var labels: Array = []
	_collect_labels(el, labels)
	return " | ".join(labels)

func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(String((n as Label).text))
	for c in n.get_children():
		_collect_labels(c, out)

func _press_button(v: Node, names: Array) -> bool:
	var out: Array = []
	var el = v.get("event_layer")
	if el == null or not is_instance_valid(el):
		return false
	_collect_buttons(el, out)
	for b in out:
		if names.has(String((b as Button).text)):
			(b as Button).emit_signal("pressed")
			return true
	return false

func _save(name: String) -> void:
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	img.save_png("E:/godotProject/dotago/tools/%s.png" % name)
	print("[M] saved ", name)

func _sn(n: Node) -> String:
	if n == null or n.get_script() == null:
		return "无"
	return String(n.get_script().resource_path).get_file()

func _view() -> Node:
	return _content()

func _content() -> Node:
	if main_ref == null:
		return null
	var content := main_ref.get_child(1)
	if content == null or content.get_child_count() == 0:
		return null
	return content.get_child(0)
