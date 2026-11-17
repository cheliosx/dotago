extends SceneTree
## 3D 地图 + 3D 战场的可视化验收脚本（会真实开窗渲染）。
## 验证新交互：左键/点击=查看、右键/拖动=移动、点空白关闭面板、平移缩放、进战斗、战场查看。
## 同时做几何自检：世界坐标往返、屏幕点选命中、屏幕右键命中。

var frames := 0
var G: Node = null
var main_ref: Node = null
var view: Node = null

func _process(_d) -> bool:
	frames += 1
	match frames:
		1:
			G = root.get_node_or_null("/root/Game")
			main_ref = load("res://scenes/Main.tscn").instantiate()
			root.add_child(main_ref)
		30:
			G.new_game("crystal_maiden")
			G.goto("world", {})
			view = _content()
			var bad := 0
			for key in G.tiles:
				var c: Vector2i = G.tiles[key].c
				if Hex3D.from_world(Hex3D.to_world(c, 1.0), 1.0) != c:
					bad += 1
			print("[3D] 坐标往返：错格 %d / %d" % [bad, G.tiles.size()])
		75:
			_save("shot3d_world")
			# 左键 / 点按 = 查看
			var h = G.selected_hero()
			var sp := _screen_of(h.pos, 0.5)
			var back: Vector2i = view.call("cell_at_screen", sp)
			print("[3D] 屏幕点选：英雄格 %s → 屏幕 %s → 反查 %s = %s" % [h.pos, sp, back, str(back == h.pos)])
			view.call("on_tap", sp)
			print("[3D] 点英雄后 面板=%s kind=%s" % [str(view.get("sheet_shown")), str(view.get("inspect"))])
		85:
			_save("shot3d_sheet")
			# 点空白关闭
			view.call("on_tap", Vector2(430, 130))
			print("[3D] 点空白后 面板=%s（应为 false）" % str(view.get("sheet_shown")))
		92:
			# 查看矿场
			var mine = G.mines[0]
			view.call("on_tap", _screen_of(mine.pos, 0.5))
			print("[3D] 查看矿场 → kind=%s 面板=%s" % [str(view.get("inspect")), str(view.get("sheet_shown"))])
		100:
			_save("shot3d_mine")
			# 查看城镇
			var town = G.towns[0]
			view.call("on_tap", _screen_of(town.pos, 0.6))
			print("[3D] 查看城镇 → kind=%s 面板=%s" % [str(view.get("inspect")), str(view.get("sheet_shown"))])
		110:
			_save("shot3d_town")
		115:
			view.call("hide_sheet")
			pass
		120:
			# 右键 / 拖动 = 移动（用屏幕坐标走完整链路）
			var h2 = G.selected_hero()
			var reach: Dictionary = G.reachable(h2)
			var target := Vector2i(-1, -1)
			for key in reach:
				var c := Hex.from_key(key)
				var d := Hex.dist(h2.pos, c)
				if d >= 2 and d <= 5 and G.object_at(c).is_empty():
					target = c
					break
			var before: Vector2i = h2.pos
			view.call("on_command", _screen_of(target, 0.5))
			print("[3D] 右键目标 %s：英雄 %s → %s，剩余移动力 %d" % [target, before, G.selected_hero().pos, G.selected_hero().mp])
		150:
			_save("shot3d_walk")
		155:
			var f0: Vector3 = view.get("focus_target")
			for i in range(10):
				view.call("_pan", Vector2(-26, 0))
			view.call("zoom_by", 0.7)
			print("[3D] 拖动：focus %s → %s，dist → %.1f" % [f0, view.get("focus_target"), view.get("dist_target")])
		185:
			_save("shot3d_pan")
		190:
			# 进战场：先站到野怪旁边再右键它
			var camp = G.camps[0]
			var h4 = G.selected_hero()
			h4.pos = Hex.neighbors(camp.pos)[0]
			h4.mp = 40
			G.changed.emit()
			view.call("on_command", _screen_of(camp.pos, 0.4))
			print("[3D] 右键野怪：pending_battle.kind = ", G.pending_battle.get("kind", "无"))
		215:
			var bv := _content()
			var sts = bv.get("stacks")
			print("[3D] 战场脚本 = %s，单位 %d 个" % [_script_name(bv), sts.size()])
			_save("shot3d_battle")
			# 战场里点击单位 = 查看
			var picked = null
			for s in sts:
				if int(s.side) == 1 and int(s.count) > 0:
					picked = s
					break
			if picked != null:
				var pt: Vector3 = bv.call("_cell_pos", picked.pos)
				var cam: Camera3D = bv.get("cam")
				var sp := cam.unproject_position(pt + Vector3(0, 0.4, 0))
				bv.call("on_tap", sp)
				print("[3D] 战场点单位 → 面板=%s（应为 true），目标 idx=%d" % [str(bv.get("sheet_shown")), int(picked.idx)])
		230:
			var bv2 := _content()
			_save("shot3d_battle_sheet")
			bv2.call("on_tap", Vector2(60, 300))
			print("[3D] 战场点空白 → 面板=%s（应为 false）" % str(bv2.get("sheet_shown")))
		240:
			var bv3 := _content()
			bv3.call("auto_battle")
			print("[3D] 自动战斗：finished=%s 我方%d 敌方%d" % [str(bv3.get("finished")), bv3.call("alive_count", 0), bv3.call("alive_count", 1)])
		255:
			_save("shot3d_battle_end")
			print("[3D] 完成")
			return true
	return false

func _screen_of(cell: Vector2i, y: float) -> Vector2:
	var cam: Camera3D = view.get("cam")
	return cam.unproject_position(Hex3D.to_world(cell, 1.0) + Vector3(0, y, 0))

func _save(name: String) -> void:
	# 窗口被遮挡时 Godot 可能跳过绘制，取到的会是上一帧
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	img.save_png("E:/godotProject/dotago/tools/%s.png" % name)
	print("[3D] saved ", name)

func _script_name(n: Node) -> String:
	if n == null or n.get_script() == null:
		return "无"
	return String(n.get_script().resource_path).get_file()

func _content() -> Node:
	if main_ref == null:
		return null
	var content := main_ref.get_child(1)
	if content == null or content.get_child_count() == 0:
		return null
	return content.get_child(0)
