## 主场景（等距视角版）
## 组装所有游戏系统，启动战斗
extends Node

@onready var camera: CameraController = $CameraController
@onready var battle_manager: BattleManager = $BattleManager
@onready var hud: CanvasLayer = $HUD
@onready var map_generator: MapGenerator = $GameWorld/MapGenerator
@onready var game_world: Node2D = $GameWorld

## teams.json 路径
const TEAMS_JSON_PATH: String = "res://prefabs/teams/teams.json"
## 单位类型到场景节点名的映射
const UNIT_NODE_NAMES: Dictionary = {
	"fighter": "Fighter",
	"saber": "Saber",
	"lancer": "Lancer",
	"archer": "Archer",
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 启动时进入菜单模式：只显示 HUD 下的 MainMenu，隐藏游戏世界与战斗相关节点
	_enter_menu_mode()


## 进入菜单模式：仅显示主菜单，隐藏地图/玩家/战斗UI
func _enter_menu_mode() -> void:
	# 隐藏动态生成的地图与玩家
	game_world.visible = false
	_hide_all_units()
	# HUD 内仅显示 GameMenu（含 MainMenu），隐藏其他游戏 UI
	if hud.has_node("BottomPanel"):
		hud.get_node("BottomPanel").visible = false
	if hud.has_node("Controls"):
		hud.get_node("Controls").visible = false
	# 连接 GameMenu 的开始游戏信号
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu and game_menu.has_signal("new_game_requested"):
		if not game_menu.new_game_requested.is_connected(_enter_game_mode):
			game_menu.new_game_requested.connect(_enter_game_mode)


## 隐藏场景中所有单位节点
func _hide_all_units() -> void:
	for unit_type in UNIT_NODE_NAMES:
		var node_name: String = UNIT_NODE_NAMES[unit_type]
		var node: Node = get_node_or_null(node_name)
		if node:
			node.visible = false


## 进入游戏模式：显示地图与游戏 UI，启动战斗
func _enter_game_mode() -> void:
	game_world.visible = true
	# 从 teams.json 读取单位初始位置
	_init_units_from_teams_json()
	if hud.has_node("BottomPanel"):
		hud.get_node("BottomPanel").visible = true
	if hud.has_node("Controls"):
		hud.get_node("Controls").visible = true
	# 隐藏主菜单
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu:
		game_menu.visible = false
	# 相机配置
	camera.zoom = Vector2(1.0, 1.0)
	camera.position = Vector2(0, -30)
	camera.set_map_bounds(Rect2(-600, -450, 1200, 900))
	camera.make_current()
	# 连接战斗管理器信号
	if not battle_manager.turn_changed.is_connected(_on_turn_changed):
		battle_manager.turn_changed.connect(_on_turn_changed)
	if not battle_manager.state_changed.is_connected(_on_state_changed):
		battle_manager.state_changed.connect(_on_state_changed)
	if not battle_manager.battle_result.is_connected(_on_battle_result):
		battle_manager.battle_result.connect(_on_battle_result)
	if not battle_manager.unit_selected.is_connected(_on_unit_selected):
		battle_manager.unit_selected.connect(_on_unit_selected)
	if not battle_manager.message_shown.is_connected(_on_message_shown):
		battle_manager.message_shown.connect(_on_message_shown)
	# 启动战斗
	battle_manager.setup_battle(camera, hud)


## 从 teams.json 读取单位配置，初始化场景中对应单位的初始位置
func _init_units_from_teams_json() -> void:
	var json_text: String = FileAccess.get_file_as_string(TEAMS_JSON_PATH)
	if json_text.is_empty():
		push_warning("teams.json 未找到或为空")
		return
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		push_warning("teams.json 解析失败: %s" % json.get_error_message())
		return
	var teams_data: Dictionary = json.data
	for key in teams_data:
		var unit_info: Dictionary = teams_data[key]
		var unit_type: String = unit_info.get("type", "")
		var coord_x: int = unit_info.get("coord_x", 0)
		var coord_y: int = unit_info.get("coord_y", 0)
		var coord: Vector2i = Vector2i(coord_x, coord_y)
		# 查找场景中对应名称的节点
		var node_name: String = UNIT_NODE_NAMES.get(unit_type, "")
		if node_name.is_empty():
			continue
		var unit_node: Node = get_node_or_null(node_name)
		if unit_node == null:
			continue
		_set_unit_grid_coord(unit_node, coord)
		unit_node.visible = true
		DebugLog.debug_nospam("init_units", "单位 %s 初始位置 (%d, %d)" % [unit_type, coord_x, coord_y])


## 设置单位（Player/Enemy 节点）的 grid_coord 并同步世界位置
## Fighter/Swordman 是 CharacterBody2D，Unit 是其子节点
func _set_unit_grid_coord(unit_node: Node, coord: Vector2i) -> void:
	# 查找 Unit 子节点
	var unit: Unit = null
	for child in unit_node.get_children():
		if child is Unit:
			unit = child as Unit
			break
	if unit == null:
		return
	unit.grid_coord = coord
	# 同步父节点世界位置到地块中心（与 unit.gd _sync_position_to_tile 保持一致）
	var tile_center: Vector2 = HexUtils.axial_to_pixel(coord.x, coord.y)
	tile_center.y -= 25.0
	(unit_node as Node2D).global_position = tile_center


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
	
func _on_turn_changed(turn: int, team: String) -> void:
	hud.update_turn(turn, team)

func _on_state_changed(new_state: int) -> void:
	#hud.update_state_hint(new_state)
	if new_state == BattleManager.BattleState.SELECT_UNIT:
		#hud.hide_unit_info()
		pass

func _on_battle_result(victory: bool) -> void:
	if victory:
		hud.show_message("战斗胜利！所有敌人已被消灭！", 5.0)
	else:
		hud.show_message("战斗失败...我方全灭...", 5.0)

func _on_unit_selected(unit: Unit) -> void:
	hud.show_unit_info(unit)

func _on_message_shown(text: String) -> void:
	hud.show_message(text, 1.5)
