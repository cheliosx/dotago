extends SceneTree
## 战场验收：选人 → 出移动范围 → 点亮普攻（出攻击范围 + 按钮高亮）→ 命中飘字 →
## 另一个单位右键移动（有过程，且移动即结束行动）。

var step := 0
var timer := 0
var G: Node = null
var main_ref: Node = null
var view: Node = null
var me_idx := -1
var me2 := -1

func _process(_d) -> bool:
	timer += 1
	var bv := _battle()
	match step:
		0:
			G = root.get_node_or_null("/root/Game")
			main_ref = load("res://scenes/Main.tscn").instantiate()
			root.add_child(main_ref)
			step = 1
		1:
			G.new_game("crystal_maiden")
			G.goto("world", {})
			view = _content()
			step = 2
		2:
			var camp = G.camps[0]
			var h = G.selected_hero()
			h.pos = Hex.neighbors(camp.pos)[0]
			h.mp = 40
			G.changed.emit()
			view.call("move_to_cell", camp.pos)
			step = 3
			timer = 0
		3:
			if bv != null:
				print("[B] 进入战场，单位 %d 个" % (bv.get("stacks") as Array).size())
				step = 4
		4:
			if bv != null and not bool(bv.get("busy")) and bool(bv.call("player_can_act")):
				for s in bv.get("stacks"):
					if int(s.side) == 0 and int(s.count) > 0:
						me_idx = int(s.idx)
						break
				var cam: Camera3D = bv.get("cam")
				bv.call("on_tap", cam.unproject_position(bv.call("_cell_pos", _stack(bv, me_idx).pos) + Vector3(0, 0.4, 0)))
				print("[B] 选中 idx=%d：可移动格 %d，按钮 = %s" % [
					int(bv.get("active")), (bv.get("reach") as Dictionary).size(), str(_btn_texts(bv))])
				step = 5
				timer = 0
		5:
			if timer > 8:
				_save("shot_b_select")
				bv.call("arm_skill", "attack")
				print("[B] 点亮普攻：pending=%s，作用距离=%d 格" % [
					String(bv.get("pending_skill")), int(bv.call("_pending_range"))])
				step = 6
				timer = 0
		6:
			if timer > 8:
				_save("shot_b_armed")
				print("[B] 按钮（点亮后）= %s" % str(_btn_texts(bv)))
				var enemy = null
				for s2 in bv.get("stacks"):
					if int(s2.side) == 1 and int(s2.count) > 0:
						enemy = s2
						break
				enemy.pos = Hex.neighbors(_stack(bv, me_idx).pos)[0]
				enemy.count = 40
				enemy.top_hp = int(DB.UNITS[enemy.unit].hp)
				for s0 in bv.get("stacks"):
					if int(s0.side) == 0:
						s0.count = 40
						s0.top_hp = int(DB.UNITS[s0.unit].hp)
				bv.call("sync_units")
				bv.call("build_overlay")
				var cam2: Camera3D = bv.get("cam")
				bv.call("on_tap", cam2.unproject_position(bv.call("_cell_pos", enemy.pos) + Vector3(0, 0.4, 0)))
				print("[B] 点击敌人释放普攻（敌方 %d）" % int(enemy.count))
				step = 7
				timer = 0
		7:
			if timer == 20:
				_save("shot_b_hit")
			if timer > 40:
				var enemy3 = null
				for s3 in bv.get("stacks"):
					if int(s3.side) == 1:
						enemy3 = s3
						break
				print("[B] 普攻后敌方 %d，日志：%s" % [int(enemy3.count), String(bv.get("log_lines")[0])])
				step = 8
				timer = 0
		8:
			if bv != null and not bool(bv.get("busy")) and not bool(bv.get("anim_lock")) and bool(bv.call("player_can_act")):
				for s4 in bv.get("stacks"):
					if int(s4.side) == 0 and int(s4.count) > 0 and int(s4.idx) != me_idx:
						me2 = int(s4.idx)
						break
				if me2 < 0:
					print("[B] 没有第二个可行动单位，跳过移动测试")
					return true
				var cam4: Camera3D = bv.get("cam")
				bv.call("on_tap", cam4.unproject_position(bv.call("_cell_pos", _stack(bv, me2).pos) + Vector3(0, 0.4, 0)))
				var reach: Dictionary = bv.get("reach")
				var pos: Vector2i = _stack(bv, me2).pos
				var dest := Vector2i(-1, -1)
				for key in reach:
					var c := Hex.from_key(key)
					if c.x == pos.x + 3:
						dest = c
				if dest.x < 0 and reach.size() > 0:
					dest = Hex.from_key(reach.keys()[reach.size() - 1])
				bv.call("on_command", cam4.unproject_position(bv.call("_cell_pos", dest) + Vector3(0, 0.4, 0)))
				print("[B] 第二个单位 %s → 右键移动到 %s（移动后行动结束）" % [pos, dest])
				step = 9
				timer = 0
		9:
			if timer == 5:
				_save("shot_b_move_mid")
			if timer > 32:
				_save("shot_b_move_done")
				var st = _stack(bv, me2)
				print("[B] 移动后：格子=%s acted=%s 当前 active=%d（应为 -1，说明已结束行动）" % [
					st.pos, str(st.acted), int(bv.get("active"))])
				print("[B] 完成")
				return true
	return false

func _btn_texts(bv: Node) -> Array:
	var out := []
	var row: HBoxContainer = bv.get("action_row")
	if row == null:
		return out
	for c in row.get_children():
		if c is Button:
			out.append("%s%s" % [String(c.text), "(禁用)" if c.disabled else ""])
		elif c is PanelContainer:
			out.append("[被动面板]")
	return out

func _stack(bv: Node, idx: int) -> Dictionary:
	for s in bv.get("stacks"):
		if int(s.idx) == idx:
			return s
	return {}

func _save(name: String) -> void:
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	img.save_png("E:/godotProject/dotago/tools/%s.png" % name)
	print("[B] saved ", name)

func _battle() -> Node:
	var n := _content()
	if n == null or n.get_script() == null:
		return null
	if String(n.get_script().resource_path).get_file() != "BattleView.gd":
		return null
	return n

func _content() -> Node:
	if main_ref == null:
		return null
	var content := main_ref.get_child(1)
	if content == null or content.get_child_count() == 0:
		return null
	return content.get_child(0)
