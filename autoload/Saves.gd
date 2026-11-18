extends Node
## 存档管理（Autoload 名：Saves）
## 一份存档 = 一局战役。文件放在 user://saves/<存档id>.sav，
## 内容是 var_to_str 序列化的 {meta, state} 字典——var_to_str 能无损保存 Vector2i 等内置类型，
## 比 JSON 省掉一整套坐标编解码。
##
## 约定：只在「大地图 / 标题」这类没有进行中战斗的时刻存档（pending_battle 为空），
## 所以战场不需要序列化。

signal changed

const DIR := "user://saves"
const EXT := ".sav"
const VER := 1

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

# ------------------------------------------------------------------ 读写文件
func _path(id: String) -> String:
	return DIR.path_join(id + EXT)

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	if not txt.begins_with("{"):
		return {}
	var v = str_to_var(txt)
	return v if v is Dictionary else {}

func _ids() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(EXT):
			out.append(n.get_basename())
		n = d.get_next()
	d.list_dir_end()
	return out

## 存档列表（按保存时间倒序）
func list() -> Array:
	var out := []
	for id in _ids():
		var rec := _read(_path(id))
		if rec.is_empty() or not rec.has("meta"):
			continue
		var m: Dictionary = (rec.meta as Dictionary).duplicate(true)
		m["id"] = id
		m["corrupt"] = not rec.has("state")
		out.append(m)
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out

func count() -> int:
	return _ids().size()

# ------------------------------------------------------------------ 存 / 读
func snapshot() -> Dictionary:
	return {
		"day": Game.day,
		"res": Game.res,
		"tiles": Game.tiles,
		"towns": Game.towns,
		"mines": Game.mines,
		"camps": Game.camps,
		"caches": Game.caches,
		"bases": Game.bases,
		"factions": Game.factions,
		"heroes": Game.heroes,
		"id_counter": Game.id_counter,
		"selected": Game.selected,
		"faction": Game.faction,
		"enemy_faction": Game.enemy_faction,
		"explored": Game.explored,
		"journal": Game.journal,
		"inventory": Game.inventory,
		"ai_power": Game.ai_power,
	}

func meta_from_state(st: Dictionary) -> Dictionary:
	var me: Dictionary = {}
	for h in st.get("heroes", []):
		if not bool(h.get("is_ai", false)) and bool(h.get("alive", true)):
			me = h
			break
	var owned_towns := 0
	for t in st.get("towns", []):
		if String(t.get("owner", "")) == String(st.get("faction", "sentinel")):
			owned_towns += 1
	var owned_mines := 0
	for m in st.get("mines", []):
		if String(m.get("owner", "")) == String(st.get("faction", "sentinel")):
			owned_mines += 1
	var army := 0
	for s in me.get("army", []):
		army += int(s.get("count", 0))
	return {
		"ver": VER,
		"saved_at": int(Time.get_unix_time_from_system()),
		"hero_name": String(me.get("name", "无名英雄")),
		"hero_def": String(me.get("def", "crystal_maiden")),
		"hero_color": String(me.get("color", "#d8b45a")),
		"hero_klass": String(me.get("klass", "")),
		"hero_title": String(me.get("title", "")),
		"level": int(me.get("level", 1)),
		"day": int(st.get("day", 1)),
		"army": army,
		"towns": owned_towns,
		"mines": owned_mines,
	}

## 保存当前进度；slot_id 为空表示新建一份存档
func save_game(slot_id: String = "") -> String:
	var st := snapshot()
	var meta := meta_from_state(st)
	var id := slot_id
	if id == "":
		id = "%d_%04d" % [int(meta.saved_at), randi() % 10000]
	else:
		var old := _read(_path(id))
		if old.has("meta") and (old.meta as Dictionary).has("saved_at"):
			meta["created_at"] = int(old.meta.created_at)
	if not meta.has("created_at"):
		meta["created_at"] = int(meta.saved_at)
	var f := FileAccess.open(_path(id), FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败：" + _path(id))
		return ""
	f.store_string(var_to_str({"meta": meta, "state": st}))
	f.close()
	Game.save_slot = id
	changed.emit()
	return id

## 开一局新战役并立刻落盘，返回新存档 id
func new_game(hero_def: String, hero_name: String) -> String:
	Game.new_game(hero_def, hero_name)
	return save_game()

func load_game(slot_id: String) -> bool:
	var rec := _read(_path(slot_id))
	if rec.is_empty() or not rec.has("state"):
		return false
	Game.restore(rec.state)
	Game.save_slot = slot_id
	Game.goto("world", {})
	return true

func delete_save(slot_id: String) -> bool:
	var d := DirAccess.open(DIR)
	if d == null:
		return false
	var err := d.remove(slot_id + EXT)
	if err == OK:
		if Game.save_slot == slot_id:
			Game.save_slot = ""
		changed.emit()
		return true
	return false

# ------------------------------------------------------------------ 展示辅助
func fmt_time(ts: int) -> String:
	var bias := 0
	var tz := Time.get_time_zone_from_system()
	if not tz.is_empty():
		bias = int(tz.get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(ts + bias)
	return "%04d-%02d-%02d  %02d:%02d" % [int(d.year), int(d.month), int(d.day), int(d.hour), int(d.minute)]
