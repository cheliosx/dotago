extends SceneTree
## 截图局部放大工具：-- <src> <x> <y> <w> <h> <scale> <out>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 7:
		print("用法: <src> <x> <y> <w> <h> <scale> <out>")
		quit()
		return
	var img := Image.load_from_file(a[0])
	if img == null:
		print("载入失败")
		quit()
		return
	var region := img.get_region(Rect2i(int(a[1]), int(a[2]), int(a[3]), int(a[4])))
	var sc := float(a[5])
	region.resize(int(region.get_width() * sc), int(region.get_height() * sc), Image.INTERPOLATE_NEAREST)
	region.save_png(a[6])
	print("saved ", a[6], " ", region.get_width(), "x", region.get_height())
	quit()
