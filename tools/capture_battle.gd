extends SceneTree
## 战场交互与动画验收：选人 → 出现移动范围 → 右键移动（有过程）→ 普攻 → 扣血飘字。
## 用状态机推进（等 AI 回合结束），而不是写死帧号。

var step := 0
var timer := 0
var G: Node = null
var main_ref: Node = null
var view: Node = null
var me_idx := -1
var me2 := -1
var skill_id := ""
var move_target := Vector2i(-1, -1)

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
			# 把英雄挪到野怪旁边并下指令进战斗
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
				print("[B] 进入战场 = %s，单位 %d 个" % [_sn(bv), bv.get("stacks").size()])
				step = 4
				timer = 0
		4:
			# 等敌方 AI 打完，轮到我方
			if bv != null and not bool(bv.get("busy")) and bool(bv.call("player_can_act")):
				print("[B] 轮到我方：active=%d" % int(bv.get("active")))
				step = 5
		5:
			# 点我方第一个单位
			for s in bv.get("stacks"):
				if int(s.side) == 0 and int(s.count) > 0:
					me_idx = int(s.idx)
					break
			var cam: Camera3D = bv.get("cam")
			var sp := cam.unproject_position(bv.call("_cell_pos", _stack(bv, me_idx).pos) + Vector3(0, 0.4, 0))
			bv.call("on_tap", sp)
			var reach: Dictionary = bv.get("reach")
			print("[B] 选中 idx=%d，可移动格 %d，底部按钮 %d 个" % [int(bv.get("active")), reach.size(), _btn_count(bv)])
			step = 6
			timer = 0
		6:
			if timer > 8:
				_save("shot_b_select")
				step = 7
		7:
			# 朝敌人方向走 3 格
			var reach2: Dictionary = bv.get("reach")
			var pos: Vector2i = _stack(bv, me_idx).pos
			var best := Vector2i(-1, -1)
			for key in reach2:
				var c := Hex.from_key(key)
				if c.x == pos.x + 3:
					best = c
			if best.x < 0 and reach2.size() > 0:
				best = Hex.from_key(reach2.keys()[reach2.size() - 1])
			move_target = best
			var cam2: Camera3D = bv.get("cam")
			bv.call("on_command", cam2.unproject_position(bv.call("_cell_pos", best) + Vector3(0, 0.4, 0)))
			print("[B] 右键移动 %s → %s" % [pos, best])
			step = 8
			timer = 0
		8:
			if timer == 4:
				_save("shot_b_move_mid")
				print("[B] 移动中：棋子坐标 = %s" % _node_pos(bv, me_idx))
			if timer > 26:
				_save("shot_b_move_done")
				print("[B] 状态：active=%d busy=%s anim_lock=%s finished=%s" % [int(bv.get("active")), str(bv.get("busy")), str(bv.get("anim_lock")), str(bv.get("finished"))])
				print("[B] 到达：棋子坐标 = %s，格子 = %s" % [_node_pos(bv, me_idx), _stack(bv, me_idx).pos])
				step = 9
		9:
			# 等移动动画彻底结束（anim_lock），再把敌人搬到隔壁测普攻
			if bool(bv.get("anim_lock")):
				return false
			var me := _stack(bv, me_idx)
			var enemy = null
			for s in bv.get("stacks"):
				if int(s.side) == 1 and int(s.count) > 0:
					enemy = s
					break
			if enemy != null:
				enemy.pos = Hex.neighbors(me.pos)[0]
				enemy.count = 40
				enemy.top_hp = int(DB.UNITS[enemy.unit].hp)
				for s0 in bv.get("stacks"):
					if int(s0.side) == 0:
						s0.count = 40
						s0.top_hp = int(DB.UNITS[s0.unit].hp)
				bv.call("sync_units")
				bv.call("build_overlay")
				bv.call("arm_skill", "attack")
				print("[B] 点亮普攻：pending=%s，敌方在 %s" % [String(bv.get("pending_skill")), enemy.pos])
			step = 10
			timer = 0
		10:
			if timer > 6:
				_save("shot_b_armed")
				step = 11
		11:
			var enemy2 = null
			for s in bv.get("stacks"):
				if int(s.side) == 1 and int(s.count) > 0:
					enemy2 = s
					break
			var cam3: Camera3D = bv.get("cam")
			var sp3 := cam3.unproject_position(bv.call("_cell_pos", enemy2.pos) + Vector3(0, 0.4, 0))
			bv.call("on_tap", sp3)
			print("[B] 点击敌人普攻（数量 %d）" % int(enemy2.count))
			step = 12
			timer = 0
		12:
			if timer == 20:
				_save("shot_b_hit")
			if timer > 30:
				var enemy3 = null
				for s in bv.get("stacks"):
					if int(s.side) == 1:
						enemy3 = s
						break
				print("[B] 敌方剩余 %d，日志：%s" % [int(enemy3.count), String(bv.get("log_lines")[0])])
				_save("shot_b_after")
				step = 13
		13:
			if timer % 45 == 0:
				print("[B] 等待我方回合：busy=%s anim=%s active=%d turn=%d/%d round=%d finished=%s" % [
					str(bv.get("busy")), str(bv.get("anim_lock")), int(bv.get("active")),
					int(bv.get("turn_idx")), (bv.get("order") as Array).size(), int(bv.get("round_no")), str(bv.get("finished"))])
			# 等下一个我方单位，测技能 + CD
			if bv != null and not bool(bv.get("busy")) and not bool(bv.get("anim_lock")) and bool(bv.call("player_can_act")):
				for s2 in bv.get("stacks"):
					if int(s2.side) == 0 and int(s2.count) > 0 and int(s2.idx) != me_idx:
						me2 = int(s2.idx)
						break
				var cam4: Camera3D = bv.get("cam")
				bv.call("on_tap", cam4.unproject_position(bv.call("_cell_pos", _stack(bv, me2).pos) + Vector3(0, 0.4, 0)))
				var skills := DB.unit_skills(String(_stack(bv, me2).unit))
				skill_id = String(skills[0])
				print("[B] 选中第二个单位 idx=%d，技能=%s" % [me2, str(skills)])
				step = 14
				timer = 0
		14:
			# 把敌人搬到旁边，点亮技能
			if timer > 4:
				var enemy4 = null
				for s3 in bv.get("stacks"):
					if int(s3.side) == 1 and int(s3.count) > 0:
						enemy4 = s3
						break
				enemy4.pos = Hex.neighbors(_stack(bv, me2).pos)[0]
				enemy4.count = 40
				enemy4.top_hp = int(DB.UNITS[enemy4.unit].hp)
				bv.call("sync_units")
				bv.call("build_overlay")
				bv.call("arm_skill", skill_id)
				print("[B] 点亮技能 %s → pending=%s" % [skill_id, String(bv.get("pending_skill"))])
				step = 15
				timer = 0
		15:
			if timer > 6:
				_save("shot_b_skill_armed")
				var enemy5 = null
				for s4 in bv.get("stacks"):
					if int(s4.side) == 1 and int(s4.count) > 0:
						enemy5 = s4
						break
				var cam6: Camera3D = bv.get("cam")
				bv.call("on_tap", cam6.unproject_position(bv.call("_cell_pos", enemy5.pos) + Vector3(0, 0.4, 0)))
				print("[B] 释放技能（敌方 %d）hint=%s" % [int(enemy5.count), String((bv.get("hint") as Label).text)])
				step = 16
				timer = 0
		16:
			if timer == 22:
				_save("shot_b_skill_hit")
				print("[B] 施放后 hint=%s pending=%s" % [String((bv.get("hint") as Label).text), String(bv.get("pending_skill"))])
			if timer > 45:
				var st6 = bv.get("stacks")
				var enemy6 = null
				for s5 in st6:
					if int(s5.side) == 1:
						enemy6 = s5
						break
				print("[B] 技能后敌方 %d，本次冷却 = %s" % [int(enemy6.count), str(_stack(bv, me2).cd)])
				var disabled := []
				for c in (bv.get("action_row") as HBoxContainer).get_children():
					if c is Button:
						disabled.append("%s:%s" % [String(c.text), str(c.disabled)])
				print("[B] 按钮状态 = %s" % str(disabled))
				_save("shot_b_skill_after")
				print("[B] 完成")
				return true
	return false

func _stack(bv: Node, idx: int) -> Dictionary:
	for s in bv.get("stacks"):
		if int(s.idx) == idx:
			return s
	return {}

func _btn_count(bv: Node) -> int:
	var row: HBoxContainer = bv.get("action_row")
	if row == null:
		return -1
	var n := 0
	for c in row.get_children():
		if c is Button:
			n += 1
	return n

func _node_pos(bv: Node, idx: int) -> String:
	var nodes: Dictionary = bv.get("unit_nodes")
	if not nodes.has(idx):
		return "无"
	return str((nodes[idx] as Node3D).position)

func _save(name: String) -> void:
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	img.save_png("E:/godotProject/dotago/tools/%s.png" % name)
	print("[B] saved ", name)

func _sn(n: Node) -> String:
	if n == null or n.get_script() == null:
		return "无"
	return String(n.get_script().resource_path).get_file()

func _battle() -> Node:
	var n := _content()
	if n == null:
		return null
	if n.get_script() == null:
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
