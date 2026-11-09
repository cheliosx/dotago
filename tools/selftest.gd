extends SceneTree

var stage := 0
var main: Node = null
var G: Node = null
var report := []

func note(s: String) -> void:

	report.append(s)
	print("[TEST] ", s)

func _process(_delta) -> bool:
	stage += 1
	match stage:
		1:
			G = root.get_node_or_null("/root/Game")
			note("autoload Game 可用 = " + str(G != null))
			main = load("res://scenes/Main.tscn").instantiate()
			root.add_child(main)
			note("Main.tscn 实例化，子节点 = " + str(main.get_child_count()))
		2:
			G.new_game("crystal_maiden")
			G.goto("world", {})
			var h = G.selected_hero()
			note("新游戏：第%d天 资源%s 英雄%s 部队%d支 地图%d格 迷雾%d格" % [G.day, str(G.res), h.name, h.army.size(), G.tiles.size(), G.explored.size()])
			var reach = G.reachable(h)
			note("可达格 = " + str(reach.size()))
			if reach.size() > 0:
				var k = reach.keys()[0]
				var c = Hex.from_key(k)
				var ok = G.move_hero(h, c)
				note("移动英雄到 (%d,%d) = %s 剩余移动力 %d" % [c.x, c.y, str(ok), h.mp])
		3:
			var tid = -1
			for t in G.towns:
				if t.owner == G.faction:
					tid = int(t.id)
					break
			G.goto("town", {"town_id": tid})
			note("城镇界面：" + str(G.build(tid, "barracks")))
			note("招募：" + str(G.recruit(tid, "militia", 5)))
			note("建造魔法塔：" + str(G.build(tid, "mage_tower")))
		4:
			G.goto("hero", {})
			var h2 = G.selected_hero()
			h2.skill_points = 2
			note("技能：" + str(G.learn_skill(h2, "offense")))
			note("装备：" + str(G.equip(int(h2.id), "iron_sword")))
			G.goto("codex", {})
			note("图鉴词条 = " + str(DB.LORE.size()) + "，英雄 = " + str(DB.HEROES.size()) + "，兵种 = " + str(DB.UNITS.size()))
		5:
			var camp = G.camps[0]
			var hh = G.selected_hero()
			G.start_battle(hh, camp, camp.guards, "camp")
			note("进入战斗：敌军 %d 支，奖励 %s" % [camp.guards.size(), str(G.pending_battle.reward)])
		6:
			var bv = find_view("BattleView")
			if bv != null:
				note("BattleView 就绪，单位 %d 个，行动顺序 %d" % [bv.stacks.size(), bv.order.size()])
				bv.auto_battle()
				note("自动战斗结束：finished=%s 我方%d 敌方%d" % [str(bv.finished), bv.alive_count(0), bv.alive_count(1)])
			else:
				note("!! 未找到 BattleView")
		7:
			note("战后：英雄等级%d 经验%d 部队%d 金币%d 背包%d" % [G.hero(G.selected).level, G.hero(G.selected).xp, G.hero(G.selected).army.size(), G.res.gold, G.inventory.size()])
			G.goto("world", {})
			for i in range(3):
				G.end_turn()
			note("三个回合后：第%d天 金币%d 日志%d条 迷雾%d格" % [G.day, G.res.gold, G.journal.size(), G.explored.size()])
		8:
			note("=== 集成测试完成，共 %d 步 ===" % stage)
			return true
	return false

func find_view(cls: String) -> Node:
	var stack := [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.get_class() == cls or (n.get_script() != null and String(n.get_script().resource_path).get_file() == cls + ".gd"):
			return n
		for c in n.get_children():
			stack.append(c)
	return null
