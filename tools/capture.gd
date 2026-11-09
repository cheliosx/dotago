extends SceneTree

var frames := 0
var G: Node = null

func _process(_d) -> bool:
	frames += 1
	if frames == 1:
		G = root.get_node_or_null("/root/Game")
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	elif frames == 12:
		var img := root.get_texture().get_image()
		img.save_png("E:/godotProject/dotago/tools/shot_title.png")
		print("saved title")
	elif frames == 13:
		G.new_game("crystal_maiden")
		G.goto("world", {})
	elif frames == 26:
		var img2 := root.get_texture().get_image()
		img2.save_png("E:/godotProject/dotago/tools/shot_world.png")
		print("saved world")
	elif frames == 27:
		var camp = G.camps[0]
		var h = G.selected_hero()
		G.start_battle(h, camp, camp.guards, "camp")
	elif frames == 40:
		var img3 := root.get_texture().get_image()
		img3.save_png("E:/godotProject/dotago/tools/shot_battle.png")
		print("saved battle")
		return true
	return false
