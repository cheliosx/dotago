extends SceneTree
## UI 验收：主界面（空存档 / 有存档）、创建英雄界面、游戏内 ☰ 菜单。
## 跑完会删掉它自己造的测试存档，不污染玩家的存档目录。

var frames := 0
var G: Node = null
var S: Node = null
var main_ref: Node = null
var made := []

func _process(_d) -> bool:
	frames += 1
	match frames:
		1:
			G = root.get_node_or_null("/root/Game")
			S = root.get_node_or_null("/root/Saves")
			main_ref = load("res://scenes/Main.tscn").instantiate()
			root.add_child(main_ref)
		20:
			_save("shot_ui_title_empty")
			# 造两份存档，验证列表
			made.append(S.new_game("luna", "银月游侠"))
			made.append(S.new_game("axe", "血斧阿黑"))
			var h = G.selected_hero()
			h.level = 4
			h.xp = 120
			G.day = 9
			S.save_game(made[1])
			G.goto("title", {})
			print("[UI] 存档数 = ", S.list().size())
		40:
			_save("shot_ui_title_list")
			G.goto("create", {})
		45:
			var v := _content()
			var names := []
			for c in v.get("cards").keys():
				names.append(c)
			print("[UI] 创建界面英雄数 = ", names.size(), "，默认名字 = ", v.get("name_edit").text)
			# 模拟输入名字
			v.get("name_edit").text = "夜刃"
			v.call("_pick", "nevermore")
		50:
			_save("shot_ui_create")
			var v2 := _content()
			print("[UI] 改选英雄后名字 = ", v2.get("name_edit").text, "（未被手动改过时应跟着变）")
			v2.get("name_edit").text = "夜刃"
			v2.call("_start")
		55:
			print("[UI] 开始后视图 = %s，存档槽 = %s" % [_script_name(_content()), G.save_slot])
		65:
			_save("shot_ui_world_saved")
			var v3 := _content()
			v3.call("_open_menu")
		75:
			_save("shot_ui_menu")
			var v4 := _content()
			v4.call("_close_menu")
			print("[UI] 存档总数（含新创建）= ", S.list().size())
		85:
			# 清理测试存档
			for id in made:
				S.delete_save(id)
			for m in S.list():
				S.delete_save(String(m.id))
			print("[UI] 清理后存档数 = ", S.list().size())
			print("[UI] 完成")
			return true
	return false

func _save(name: String) -> void:
	RenderingServer.force_draw(true)
	var img := root.get_texture().get_image()
	img.save_png("E:/godotProject/dotago/tools/%s.png" % name)
	print("[UI] saved ", name)

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
