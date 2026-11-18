extends SceneTree
## 多势力对抗验收：
##   玩家营地 / 敌方营地 → 驻军派兵 → 招募士兵与英雄 → 结束回合（AI 行军）
##   → 据点被进攻时弹「死守 / 撤退」→ 撤退后产出丢失 → 消灭所有势力判定胜利

var step := 0
var timer := 0
var G: Node = null
var main_ref: Node = null
var view: Node = null
var base: Node = null
var gold_mine: Dictionary = {}

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
			print("[F] 势力 %d 个：" % G.factions.size())
			for f in G.factions:
				print("     %s（%s）玩家=%s 存活=%s" % [f.name, f.id, str(f.is_player), str(G.faction_alive(String(f.id)))])
			print("[F] 营地 %d · 矿场/伐木场 %d · 城镇 %d · 英雄 %d" % [
				G.bases.size(), G.mines.size(), G.towns.size(), G.heroes.size()])
			for b in G.bases:
				print("     营地 %s owner=%s 驻军=%d wpos=%s" % [b.name, b.owner, (b.garrison as Array).size(), str(b.wpos)])
			base = _find_poi(v, "base")
			print("[F] 玩家营地节点 = %s" % String((base as Node).title))
			step = 3
			timer = 0
		3:
			if timer > 35:
				_save("shot_f_map")
				v.call("zoom_by", 2.4, false)
				step = 30
				timer = 0
		30:
			if timer > 18:
				_save("shot_f_overview")
				v.call("zoom_by", 0.4, false)
				v.call("center_on", (base as Node3D).global_position)
				step = 4
				timer = 0
		4:
			if timer > 20:
				v.call("on_tap", _poi_screen(v, base))
				print("[F] 点自己营地 → 面板=%s" % str(v.get("sheet_shown")))
				step = 5
				timer = 0
		5:
			if timer > 8:
				_save("shot_f_base")
				# 打开驻军弹窗
				v.call("_garrison_modal", v.call("_poi_ref", base))
				print("[F] 驻军弹窗 = %s" % str(v.get("event_layer") != null))
				step = 6
				timer = 0
		6:
			if timer > 8:
				_save("shot_f_garrison")
				var ref: Dictionary = v.call("_poi_ref", base)
				var before := (ref.garrison as Array).duplicate(true)
				var h: Dictionary = G.selected_hero()
				var uid := String((h.army as Array)[0].unit)
				print("[F] 派兵前：英雄 %s ×%d，驻军 %s" % [uid, int((h.army as Array)[0].count), _gar_str(before)])
				G.garrison_add(ref, uid, 5, h)
				print("[F] 派兵后：英雄 ×%d，驻军 %s" % [int((h.army as Array)[0].count), _gar_str(ref.garrison)])
				step = 7
				timer = 0
		7:
			if timer > 6:
				v.call("_close_event")
				v.call("_recruit_modal", v.call("_poi_ref", base))
				step = 8
				timer = 0
		8:
			if timer > 8:
				_save("shot_f_recruit")
				print("[F] 招募弹窗 = %s" % str(v.get("event_layer") != null))
				var g0 := int(G.res.gold)
				var w0 := int(G.res.wood)
				var msg: String = G.recruit(int((v.call("_poi_ref", base) as Dictionary).id), "archer", 5)
				print("[F] 招募结果：%s（金币 %d→%d，木材 %d→%d）" % [msg, g0, int(G.res.gold), w0, int(G.res.wood)])
				step = 9
				timer = 0
		9:
			if timer > 6:
				v.call("_close_event")
				# 招募英雄
				var owned_before := 0
				for h in G.heroes:
					if not bool(h.is_ai):
						owned_before += 1
				var hm: String = G.hire_hero(int((v.call("_poi_ref", base) as Dictionary).id), "luna")
				var owned_after := 0
				for h in G.heroes:
					if not bool(h.is_ai):
						owned_after += 1
				print("[F] 招募英雄：%s（英雄 %d→%d）" % [hm, owned_before, owned_after])
				v.call("_sync_hero_nodes")
				step = 10
				timer = 0
		10:
			if timer > 10:
				# 结束回合，观察 AI 行军
				var ai_before := {}
				for h in G.heroes:
					if bool(h.is_ai):
						ai_before[int(h.id)] = h.get("wpos", Vector3.ZERO)
				G.end_turn()
				var moved := 0
				for h in G.heroes:
					if not bool(h.is_ai):
						continue
					var b0: Vector3 = ai_before.get(int(h.id), Vector3.ZERO)
					var b1: Vector3 = h.get("wpos", Vector3.ZERO)
					if b0.distance_to(b1) > 0.5:
						moved += 1
				print("[F] 结束回合：第 %d 天，AI 移动了 %d 个单位，待处理防守 %d" % [
					int(G.day), moved, (G.pending_defenses as Array).size()])
				step = 11
				timer = 0
		11:
			if timer > 12:
				_save("shot_f_turn")
				step = 12
				timer = 0
		12:
			# 构造一次玩家矿场被进攻
			if timer > 2:
				var mine := _first_owned_mine()
				if mine.is_empty():
					# 先占一个：直接把矿给玩家
					gold_mine = G.mines[0]
					G.mines[0].owner = G.faction
					mine = G.mines[0]
				mine["garrison"] = [{"unit": "militia", "count": 6}]
				mine["owner"] = G.faction
				var foe = null
				for h in G.heroes:
					if bool(h.is_ai) and bool(h.alive):
						foe = h
						break
				foe["wpos"] = (mine.wpos as Vector3) + Vector3(4.0, 0.0, 0.0)
				foe.army = [{"unit": "ogre", "count": 30}]
				print("[F] 让 %s 进攻 %s（对方战力 %d，守军战力 %d）" % [
					foe.name, String(mine.name), G.army_strength(foe.army), G.garrison_strength(mine)])
				G.end_turn()
				print("[F] 告急队列 %d，awaiting=%s" % [
					(G.pending_defenses as Array).size(), str(G.awaiting_defense)])
				step = 13
				timer = 0
		13:
			if timer > 10:
				_save("shot_f_defense")
				print("[F] 防守弹窗 = %s / %s" % [str(v.get("event_layer") != null), _popup_text(v)])
				var mine2 := _first_owned_mine()
				print("[F] 撤退前 矿场归属 = %s" % String(mine2.get("owner", "")))
				step = 14
				timer = 0
		14:
			if timer > 4:
				var ok := _press_button(v, ["撤 退"])
				print("[F] 点撤退 = %s" % str(ok))
				step = 15
				timer = 0
		15:
			if timer > 8:
				var mine3 := _first_owned_mine()
				print("[F] 撤退后 该矿场归属 = %s，awaiting=%s，第 %d 天" % [
					_mine_owner_by_id(), str(G.awaiting_defense), int(G.day)])
				step = 16
				timer = 0
		16:
			if timer > 4:
				# 消灭所有敌对势力 → 胜利判定
				for b in G.bases:
					if String(b.owner) != G.faction:
						b.owner = G.faction
				for h in G.heroes:
					if bool(h.is_ai):
						h.alive = false
				G.check_game_over()
				print("[F] 消灭所有势力后 game_over = %s（应 win）" % String(G.game_over))
				print("[F] 目标行：%s" % G.objective())
				print("[F] 完成")
				return true
	return false

func _first_owned_mine() -> Dictionary:
	for m in G.mines:
		if String(m.owner) == String(G.faction):
			return m
	return {}

func _mine_owner_by_id() -> String:
	if gold_mine.is_empty():
		return "?"
	return String(gold_mine.get("owner", "?"))

func _gar_str(arr: Array) -> String:
	var parts := []
	for g in arr:
		parts.append("%s×%d" % [String(g.unit), int(g.count)])
	return "、".join(parts) if not parts.is_empty() else "空"

func _find_poi(v: Node, kind: String) -> Node:
	for p in v.get("pois"):
		if String((p as Node).kind) == kind and String((p as Node).owner_id) == "sentinel":
			return p
	for p in v.get("pois"):
		if String((p as Node).kind) == kind:
			return p
	return null

func _poi_screen(v: Node, poi: Node) -> Vector2:
	var cam: Camera3D = v.get("cam")
	return cam.unproject_position((poi as Node3D).global_position + Vector3(0, 2.2, 0))

func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)

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

func _save(name: String) -> void:
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	img.save_png("E:/godotProject/dotago/tools/%s.png" % name)
	print("[F] saved ", name)

func _sn(n: Node) -> String:
	if n == null or n.get_script() == null:
		return "无"
	return String(n.get_script().resource_path).get_file()

func _view() -> Node:
	if main_ref == null:
		return null
	var content := main_ref.get_child(1)
	if content == null or content.get_child_count() == 0:
		return null
	return content.get_child(0)
