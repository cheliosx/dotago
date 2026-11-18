@tool
class_name WorldPoi
extends Node3D
## 地图上的兴趣点（预制品根节点）。可在编辑器里拖拽摆放、改数值，实时看到外观。
## kind：tavern 酒馆（招英雄） / smith 铁匠铺（买卖装备） / mine 矿场与伐木场 /
##       camp 野怪营地 / town 城镇 / base 势力营地（每方一个，被攻破即失去根基）

@export_enum("tavern", "smith", "mine", "camp", "town", "base") var kind := "mine"
@export var title := "无名之地"
@export var resource := "gold"
@export var owner_id := ""
@export var guards := PackedStringArray(["wolf:8"])
@export var biome := "plain"
@export var build_on_ready := true

func _ready() -> void:
	if not Engine.is_editor_hint():
		_snap_to_terrain()
	if build_on_ready:
		rebuild()
	if not Engine.is_editor_hint():
		add_to_group("poi")

## 运行时按地形高度贴地：编辑器里改了地形参数也不会让建筑悬空
func _snap_to_terrain() -> void:
	var t := _terrain()
	if t != null:
		position.y = t.height_at(global_position.x, global_position.z)

func _terrain() -> WorldTerrain:
	var p := get_parent()
	while p != null:
		for c in p.get_children():
			if c is WorldTerrain:
				return c
		p = p.get_parent()
	return null

func guard_list() -> Array:
	var out := []
	for g in guards:
		var parts := String(g).split(":")
		if parts.size() == 2 and DB.UNITS.has(parts[0]):
			out.append({"unit": parts[0], "count": int(parts[1])})
	return out

## 各单位站到哪儿（POI 正前方一点，避免和模型重叠）
func stand_pos() -> Vector3:
	return global_position + Vector3(0, 0, 2.6)

func display_name() -> String:
	# 标题本身已经说明是什么（金矿 / 秘银矿脉 / 伐木场），不再拼资源名避免「秘银矿脉（秘银矿矿）」
	return title

func rebuild() -> void:
	for c in get_children():
		if c.name.begins_with("_build"):
			remove_child(c)
			c.queue_free()
	var holder := Node3D.new()
	holder.name = "_build"
	add_child(holder)
	match kind:
		"tavern": _build_tavern(holder)
		"smith": _build_smith(holder)
		"mine": _build_mine(holder)
		"camp": _build_camp(holder)
		"town": _build_town(holder)
		"base": _build_base(holder)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _box(parent: Node3D, pos: Vector3, sz: Vector3, col: Color, ry := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation.y = ry
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, col: Color, segs := 8, top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if top < 0.0 else top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = _mat(col)
	mi.position = pos
	parent.add_child(mi)
	return mi

func _label(parent: Node3D, text: String, y: float, col: Color, size := 44) -> void:
	var fs := size * 2
	var l := Label3D.new()
	l.text = text
	l.font = UI.world_font()
	l.font_size = fs
	l.pixel_size = 0.0132
	l.modulate = col
	l.outline_size = maxi(6, int(round(float(fs) * 0.105)))
	l.outline_modulate = Color(0, 0, 0, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 穿树可见：地名被树挡住是最主要的"看不清"原因
	l.no_depth_test = true
	l.render_priority = 2
	# 缩小时必须走 mipmap，否则字形贴图会采样成黑白噪点
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = Vector3(0, y, 0)
	parent.add_child(l)

## 当前归属的势力色（无主 = 中立灰）
func _owner_color() -> Color:
	return Color(DB.FACTIONS.get(owner_id, DB.FACTIONS["neutral"]).color)

## 地名颜色：无主浅白、我方浅蓝、敌对红（魔兽式）
func _name_color() -> Color:
	if owner_id == "":
		return Color("#fff6e8")
	if owner_id == "sentinel":
		return Color("#d8efff")
	return Color("#ff7a65")

## 队伍旗：归属一眼可见
func _flag(parent: Node3D, base: Vector3, h: float, col: Color) -> void:
	_cyl(parent, base + Vector3(0, h * 0.5, 0), 0.075, h, Color("#b9924a"), 6)
	_box(parent, base + Vector3(0.5, h - 0.42, 0), Vector3(1.0, 0.62, 0.05), col)

func _build_tavern(p: Node3D) -> void:
	_box(p, Vector3(0, 0.06, 0), Vector3(4.2, 0.12, 3.8), Color("#6d5b42"))
	_box(p, Vector3(0, 1.5, 0), Vector3(3.6, 2.8, 3.0), Color("#8d6e4c"))
	# 屋顶
	var roof := _box(p, Vector3(0, 3.1, 0), Vector3(4.1, 0.35, 3.5), Color("#5a3a2a"))
	roof.rotation.z = 0.0
	_cyl(p, Vector3(0, 3.5, 0), 2.3, 1.3, Color("#7a3f2c"), 4)
	# 门窗
	_box(p, Vector3(0, 1.0, -1.55), Vector3(0.9, 1.7, 0.08), Color("#3a2a1c"))
	_box(p, Vector3(-1.3, 1.6, -1.55), Vector3(0.7, 0.7, 0.08), Color("#d8b45a"))
	_box(p, Vector3(1.3, 1.6, -1.55), Vector3(0.7, 0.7, 0.08), Color("#d8b45a"))
	# 酒幌
	_cyl(p, Vector3(2.1, 2.2, 1.2), 0.07, 3.2, Color("#c9a227"), 6)
	_box(p, Vector3(2.6, 2.9, 1.2), Vector3(0.9, 0.6, 0.05), Color("#c94f3d"))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffb066")
	lamp.light_energy = 2.2
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, 2.6, -1.9)
	p.add_child(lamp)
	_label(p, "酒 馆", 4.6, Color("#ffd98a"), 48)

func _build_smith(p: Node3D) -> void:
	_box(p, Vector3(0, 0.06, 0), Vector3(3.8, 0.12, 3.4), Color("#5d5a55"))
	_box(p, Vector3(0, 1.3, 0), Vector3(3.2, 2.4, 2.8), Color("#6b6560"))
	_box(p, Vector3(0, 2.7, 0), Vector3(3.6, 0.3, 3.1), Color("#4b4540"))
	# 烟囱
	_box(p, Vector3(1.1, 3.4, 0.6), Vector3(0.6, 1.6, 0.6), Color("#55504b"))
	# 熔炉红光
	_box(p, Vector3(-0.9, 0.7, -1.5), Vector3(1.1, 1.1, 0.9), Color("#3b2b24"))
	var fire := _box(p, Vector3(-0.9, 0.7, -1.05), Vector3(0.7, 0.5, 0.08), Color("#ff7a3d"))
	fire.material_override = _mat(Color("#ff7a3d"))
	var glow := OmniLight3D.new()
	glow.light_color = Color("#ff8a45")
	glow.light_energy = 3.0
	glow.omni_range = 8.0
	glow.position = Vector3(-0.9, 1.0, -1.2)
	p.add_child(glow)
	# 铁砧
	_box(p, Vector3(1.4, 0.55, -1.4), Vector3(0.8, 0.5, 0.5), Color("#3a3d42"))
	_box(p, Vector3(1.4, 0.85, -1.4), Vector3(1.0, 0.18, 0.6), Color("#4a4e55"))
	_label(p, "铁匠铺", 4.0, Color("#c9d2dd"), 46)

func _build_mine(p: Node3D) -> void:
	var col := Color(DB.RES.get(resource, DB.RES["gold"]).color)
	if resource == "wood":
		_build_lumber(p)
		return
	_box(p, Vector3(-1.2, 1.1, 0), Vector3(0.7, 2.2, 1.6), Color("#5b5f66"))
	_box(p, Vector3(1.2, 1.1, 0), Vector3(0.7, 2.2, 1.6), Color("#5b5f66"))
	_box(p, Vector3(0, 2.35, 0), Vector3(3.2, 0.5, 1.7), Color("#4a4e55"))
	_box(p, Vector3(0, 0.9, 0), Vector3(2.4, 1.8, 0.4), Color("#1c1a18"))
	# 矿车轨道
	_box(p, Vector3(0, 0.08, -2.2), Vector3(0.7, 0.12, 4.2), Color("#4a4038"))
	# 矿石
	_box(p, Vector3(-1.6, 0.5, -1.6), Vector3(0.55, 0.9, 0.55), col, 0.5)
	_box(p, Vector3(-1.1, 0.35, -1.9), Vector3(0.4, 0.6, 0.4), col.darkened(0.25), -0.4)
	_flag(p, Vector3(2.0, 0, 1.5), 4.4, _owner_color())
	_label(p, display_name(), 3.2, _name_color(), 42)

func _build_camp(p: Node3D) -> void:
	_cyl(p, Vector3(-0.8, 1.0, 0.2), 1.5, 1.9, Color("#6b3a30"), 6)
	_cyl(p, Vector3(0.9, 0.8, -0.4), 1.1, 1.5, Color("#7a4a3a"), 6)
	# 篝火
	_cyl(p, Vector3(0.1, 0.06, 1.5), 0.6, 0.12, Color("#3a2b22"), 8)
	_box(p, Vector3(0.1, 0.3, 1.5), Vector3(0.35, 0.45, 0.35), Color("#ff7a3d"))
	var fire := OmniLight3D.new()
	fire.light_color = Color("#ff8a45")
	fire.light_energy = 2.4
	fire.omni_range = 7.0
	fire.position = Vector3(0.1, 0.6, 1.5)
	p.add_child(fire)
	# 骨头 / 图腾
	_cyl(p, Vector3(-1.9, 1.1, -1.2), 0.09, 2.2, Color("#c9c0aa"), 6)
	_label(p, title, 3.3, Color("#ffbe8a"), 40)

func _build_town(p: Node3D) -> void:
	var col := _owner_color()
	# 领地基座：一块势力色的夯土，远处也能分清是谁的城
	_cyl(p, Vector3(0, 0.05, 0), 4.2, 0.12, col.darkened(0.62), 12)
	_box(p, Vector3(0, 0.08, 0), Vector3(5.0, 0.14, 4.4), Color("#6d5b42"))
	# 主楼 / 副楼：石色压上势力色，像 WC3 的队伍色建筑
	_box(p, Vector3(-1.0, 1.4, 0), Vector3(2.2, 2.6, 2.2), col.darkened(0.58))
	_box(p, Vector3(1.2, 1.1, 0.4), Vector3(1.8, 2.0, 1.8), col.darkened(0.66))
	# 窗与门
	_box(p, Vector3(-1.0, 1.6, -1.12), Vector3(0.8, 1.2, 0.06), Color("#20242c"))
	_box(p, Vector3(1.2, 1.4, -0.52), Vector3(0.6, 0.9, 0.06), Color("#20242c"))
	_cyl(p, Vector3(-1.0, 3.0, 0), 1.7, 1.2, col.darkened(0.28), 4)
	_cyl(p, Vector3(2.6, 1.8, -1.4), 0.08, 3.6, Color("#b9924a"), 6)
	_box(p, Vector3(3.0, 3.2, -1.4), Vector3(1.0, 0.66, 0.05), col.lightened(0.12))
	_label(p, title, 4.2, _name_color(), 46)

## 伐木场：工棚 + 木堆 + 锯木架
func _build_lumber(p: Node3D) -> void:
	_box(p, Vector3(0, 0.07, 0), Vector3(4.6, 0.14, 3.6), Color("#6d5b42"))
	_box(p, Vector3(1.0, 1.25, 0), Vector3(3.2, 2.2, 2.4), Color("#8d6e4c"))
	_box(p, Vector3(1.0, 2.5, 0), Vector3(3.6, 0.32, 2.8), Color("#5a3a2a"))
	_box(p, Vector3(1.0, 1.0, -1.22), Vector3(0.9, 1.7, 0.08), Color("#3a2a1c"))
	# 木堆（横放的圆木）
	for i in range(3):
		var lg := _cyl(p, Vector3(-1.9, 0.34 + i * 0.5, 0.6), 0.28, 3.0, Color("#8a6a42"), 8)
		lg.rotation.z = PI * 0.5
	for i in range(2):
		var lg2 := _cyl(p, Vector3(-1.9, 0.34 + i * 0.5, -0.9), 0.26, 2.6, Color("#7d5f3c"), 8)
		lg2.rotation.z = PI * 0.5
	# 锯木架
	_box(p, Vector3(-0.4, 0.9, -1.6), Vector3(0.16, 1.8, 0.16), Color("#6b4f33"))
	_box(p, Vector3(0.7, 0.9, -1.6), Vector3(0.16, 1.8, 0.16), Color("#6b4f33"))
	_box(p, Vector3(0.15, 1.8, -1.6), Vector3(1.6, 0.16, 0.16), Color("#a8804f"))
	_flag(p, Vector3(-2.4, 0, 1.6), 4.2, _owner_color())
	_label(p, display_name(), 3.4, _name_color(), 42)

## 势力营地：栅栏 + 帐篷 + 旗，旗色跟着势力走
func _build_base(p: Node3D) -> void:
	var col := _owner_color()
	var fname := String(DB.FACTIONS.get(owner_id, DB.FACTIONS["neutral"]).name)
	_cyl(p, Vector3(0, 0.06, 0), 5.6, 0.14, col.darkened(0.55), 14)
	# 木栅栏一圈
	for i in range(14):
		var a := TAU * float(i) / 14.0
		var r := 4.9
		_cyl(p, Vector3(cos(a) * r, 0.92, sin(a) * r), 0.17, 1.85, Color("#6b4f33"), 6)
	# 帐篷
	_cyl(p, Vector3(-2.0, 1.15, 0.6), 1.75, 2.3, col.darkened(0.5), 6)
	_cyl(p, Vector3(2.2, 0.95, -0.8), 1.35, 1.9, col.darkened(0.62), 6)
	_cyl(p, Vector3(0.2, 1.6, -2.0), 2.15, 3.2, col.darkened(0.38), 6)
	# 主旗
	_cyl(p, Vector3(0.2, 4.2, 2.6), 0.11, 6.4, Color("#c9a227"), 6)
	_box(p, Vector3(1.0, 6.6, 2.6), Vector3(1.5, 1.0, 0.06), col)
	# 篝火
	_cyl(p, Vector3(0.2, 0.06, 2.2), 0.72, 0.12, Color("#3a2b22"), 8)
	_box(p, Vector3(0.2, 0.36, 2.2), Vector3(0.42, 0.52, 0.42), Color("#ff7a3d"))
	var fire := OmniLight3D.new()
	fire.light_color = Color("#ff8a45")
	fire.light_energy = 2.6
	fire.omni_range = 8.0
	fire.position = Vector3(0.2, 0.7, 2.2)
	p.add_child(fire)
	_label(p, title, 7.4, _name_color(), 46)
	if fname != "":
		# 势力名并进标题下方，字号略小但不再单独占一行
		_label(p, fname, 6.3, col.lightened(0.45), 26)
