extends SceneTree

var frames := 0
var G: Node = null
var main_ref: Node = null

func _process(_d) -> bool:
	frames += 1
	if frames == 1:
		G = root.get_node_or_null("/root/Game")
		main_ref = load("res://scenes/Main.tscn").instantiate()
		root.add_child(main_ref)
	elif frames == 12:
		var img := root.get_texture().get_image()
		img.save_png("E:/godotProject/dotago/tools/shot_title.png")
		print("saved title")
	elif frames == 13:
		G.new_game("crystal_maiden")
		G.goto("world2d", {})
	elif frames == 25:
		# 演示：走到无守军金矿上并占领（截图里应出现 ◆ 归属标记、目标计数 1/8）
		var mine = G.mines[0]
		var h2 = G.selected_hero()
		h2.pos = Hex.neighbors(mine.pos)[0]
		h2.mp = 30
		G.changed.emit()
		var wv = main_ref.get_child(1).get_child(0)
		wv.call("on_map_click", mine.pos)
		print("click mine -> owner = ", mine.owner, " | ", G.objective())
	elif frames == 44:
		var img2 := root.get_texture().get_image()
		img2.save_png("E:/godotProject/dotago/tools/shot_world.png")
		print("saved world")
	elif frames == 45:
		# 端到端：模拟玩家真实点击「怪」格，必须切进战斗界面
		var camp = G.camps[0]
		var h = G.selected_hero()
		h.pos = Hex.neighbors(camp.pos)[0]
		h.mp = 40
		G.changed.emit()
		var view = main_ref.get_child(1).get_child(0)
		view.call("on_map_click", camp.pos)
		print("click camp -> pending_battle.kind = ", G.pending_battle.get("kind", "无"))
	elif frames == 46:
		var bv = main_ref.get_child(1).get_child(0)
		if bv.get_script() != null and String(bv.get_script().resource_path).ends_with("BattleView.gd"):
			for s in bv.stacks:
				print("  stack side=", s.side, " unit=", s.unit, " pos=", s.pos, " count=", s.count)
	elif frames == 58:
		var img3 := root.get_texture().get_image()
		img3.save_png("E:/godotProject/dotago/tools/shot_battle.png")
		print("saved battle")
		return true
	return false
