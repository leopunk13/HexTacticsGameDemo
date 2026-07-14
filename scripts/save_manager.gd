extends Node
## 存档管理器（Autoload 单例）
## 负责战斗状态的保存、读取和初始状态缓存

const SAVE_DIR: String = "user://saves/"
const SAVE_EXTENSION: String = ".tres"
const MAX_SLOTS: int = 6
## 初始状态缓存文件（自动保存，用于 RETRYBATTLE）
const INITIAL_STATE_PATH: String = "user://saves/initial_state.tres"

## 自动保存的初始状态（战斗开始时缓存）
var _initial_state: SaveData = null

## 是否存在已保存的初始状态
func has_initial_state() -> bool:
	return _initial_state != null

## 获取初始状态
func get_initial_state() -> SaveData:
	return _initial_state

## 缓存初始状态（战斗开始时调用）
func cache_initial_state(player_units: Array, enemy_units: Array) -> SaveData:
	_initial_state = _build_save_data("INITIAL_STATE", player_units, enemy_units, 1, "PLAYER")
	return _initial_state

## 保存当前战斗状态到指定槽位
## 返回保存的文件名（不含路径），失败返回空字符串
func save_to_slot(slot: int, player_units: Array, enemy_units: Array, turn_count: int, current_team: String) -> String:
	_ensure_save_dir()
	var title: String = "SAVE FILE %s" % Time.get_datetime_string_from_system(false, true)
	var save_data: SaveData = _build_save_data(title, player_units, enemy_units, turn_count, current_team)
	save_data.save_time = Time.get_datetime_string_from_system(false, true)
	var file_name: String = "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	save_data.file_name = file_name
	var path: String = SAVE_DIR + file_name
	var err: int = ResourceSaver.save(save_data, path)
	if err != OK:
		push_error("保存存档失败: %s, 错误码: %d" % [path, err])
		return ""
	return file_name

## 从指定槽位读取存档
func load_from_slot(slot: int) -> SaveData:
	var path: String = SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SaveData

## 判断指定槽位是否有存档
func has_slot_data(slot: int) -> bool:
	var path: String = SAVE_DIR + "save_slot_%d%s" % [slot, SAVE_EXTENSION]
	return ResourceLoader.exists(path)

## 获取所有存档槽位数据（索引 0~MAX_SLOTS-1，无存档则为 null）
func get_all_slots() -> Array:
	var slots: Array = []
	for i in range(MAX_SLOTS):
		slots.append(load_from_slot(i))
	return slots

## 构建存档数据
func _build_save_data(title: String, player_units: Array, enemy_units: Array, turn_count: int, current_team: String) -> SaveData:
	var data: SaveData = SaveData.new()
	data.title = title
	data.turn_count = turn_count
	data.current_team = current_team
	data.player_units_data = _serialize_units(player_units)
	data.enemy_units_data = _serialize_units(enemy_units)
	return data

## 序列化单位列表为可保存的 Dictionary 数组
func _serialize_units(units: Array) -> Array:
	var result: Array = []
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		var unit_dict: Dictionary = {
			"unit_name": unit.get_parent().name if unit.get_parent() else unit.unit_name,
			"grid_x": unit.grid_coord.x,
			"grid_y": unit.grid_coord.y,
			"health": unit.health,
			"max_health": unit.max_health,
			"mana": unit.mana,
			"max_mana": unit.max_mana,
			"has_moved": unit.has_moved,
			"has_attacked": unit.has_attacked,
			"is_turn_ended": unit.is_turn_ended,
			"facing_x": unit.facing_direction.x,
			"facing_y": unit.facing_direction.y,
			"is_dead": unit.is_dead,
			"team": int(unit.team),
		}
		result.append(unit_dict)
	return result

## 确保存档目录存在
func _ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

## 清除所有存档文件（开始新游戏时调用）
func clear_all_saves() -> void:
	_initial_state = null
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(SAVE_EXTENSION) or file_name.ends_with(".remap")):
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
