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
## enemys.json 路径
const ENEMYS_JSON_PATH: String = "res://prefabs/enemys/enemys.json"
## 单位类型到场景节点名的映射
const UNIT_NODE_NAMES: Dictionary = {
	"fighter": "Fighter",
	"saber": "Saber",
	"lancer": "Lancer",
	"archer": "Archer",
}
## 敌方单位类型到场景节点名的映射
const ENEMY_NODE_NAMES: Dictionary = {
	"enemy1": "Enemy1",
	"enemy2": "Enemy2",
	"enemy3": "Enemy3",
	"enemy4": "Enemy4",
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
		# 连接继续游戏信号（从主菜单载入最新存档）
		if game_menu.has_signal("continue_game_requested") and not game_menu.continue_game_requested.is_connected(_on_continue_game):
			game_menu.continue_game_requested.connect(_on_continue_game)
		# 连接返回主菜单信号
		if game_menu.has_signal("main_menu_requested") and not game_menu.main_menu_requested.is_connected(_on_back_to_main_menu):
			game_menu.main_menu_requested.connect(_on_back_to_main_menu)


## 隐藏场景中所有单位节点（友方与敌方）
func _hide_all_units() -> void:
	for unit_type in UNIT_NODE_NAMES:
		var node_name: String = UNIT_NODE_NAMES[unit_type]
		var node: Node = get_node_or_null(node_name)
		if node:
			node.visible = false
	for unit_type in ENEMY_NODE_NAMES:
		var node_name: String = ENEMY_NODE_NAMES[unit_type]
		var node: Node = get_node_or_null(node_name)
		if node:
			node.visible = false


## 进入游戏模式：显示地图与游戏 UI，启动战斗
func _enter_game_mode() -> void:
	game_world.visible = true
	# 从 teams.json 读取友方单位初始位置
	_init_units_from_teams_json()
	# 从 enemys.json 读取敌方单位初始位置
	_init_enemies_from_json()
	if hud.has_node("BottomPanel"):
		hud.get_node("BottomPanel").visible = false
	if hud.has_node("Controls"):
		hud.get_node("Controls").visible = false
	# 隐藏主菜单（保持 GameMenu 本身可见以处理 ESC 输入，仅隐藏内部菜单）
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu:
		game_menu.hide_pause_menu()
		# 连接 GameMenu 的保存/读取/重试信号
		if not game_menu.save_requested.is_connected(_on_save_requested):
			game_menu.save_requested.connect(_on_save_requested)
		if not game_menu.load_requested.is_connected(_on_load_requested):
			game_menu.load_requested.connect(_on_load_requested)
		if not game_menu.retry_battle_requested.is_connected(_on_retry_battle):
			game_menu.retry_battle_requested.connect(_on_retry_battle)
		if not game_menu.main_menu_requested.is_connected(_on_back_to_main_menu):
			game_menu.main_menu_requested.connect(_on_back_to_main_menu)
		if not game_menu.continue_game_requested.is_connected(_on_continue_game):
			game_menu.continue_game_requested.connect(_on_continue_game)
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
	# 自动保存初始状态（用于 RETRYBATTLE）
	SaveManager.cache_initial_state(battle_manager.player_units, battle_manager.enemy_units)


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


## 从 enemys.json 读取敌方单位配置，初始化场景中对应敌方单位的初始位置
func _init_enemies_from_json() -> void:
	var json_text: String = FileAccess.get_file_as_string(ENEMYS_JSON_PATH)
	if json_text.is_empty():
		push_warning("enemys.json 未找到或为空")
		return
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		push_warning("enemys.json 解析失败: %s" % json.get_error_message())
		return
	var enemys_data: Dictionary = json.data
	for key in enemys_data:
		var unit_info: Dictionary = enemys_data[key]
		var unit_type: String = unit_info.get("type", "")
		var coord_x: int = unit_info.get("coord_x", 0)
		var coord_y: int = unit_info.get("coord_y", 0)
		var coord: Vector2i = Vector2i(coord_x, coord_y)
		# 查找场景中对应名称的敌方节点
		var node_name: String = ENEMY_NODE_NAMES.get(unit_type, "")
		if node_name.is_empty():
			continue
		var unit_node: Node = get_node_or_null(node_name)
		if unit_node == null:
			continue
		_set_unit_grid_coord(unit_node, coord)
		unit_node.visible = true
		DebugLog.debug_nospam("init_enemies", "敌方单位 %s 初始位置 (%d, %d)" % [unit_type, coord_x, coord_y])


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
	# 重置单位到初始状态（恢复血量、法力、回合状态、朝向等）
	unit.reset_to_initial_state()
	unit.grid_coord = coord
	# 同步父节点世界位置到地块中心（与 unit.gd _sync_position_to_tile 保持一致）
	var tile_center: Vector2 = HexUtils.axial_to_pixel(coord.x, coord.y)
	tile_center.y -= 25.0
	(unit_node as Node2D).global_position = tile_center


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


## 处理 ESC 键：游戏中切换暂停菜单
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu == null or not game_menu.is_in_game:
		return
	# 若存档/读档面板正在显示，ESC 关闭面板并恢复暂停菜单
	if game_menu.save_load_panel.visible:
		game_menu.save_load_panel.visible = false
		game_menu.main_menu.visible = true
		get_viewport().set_input_as_handled()
		return
	# 暂停菜单已显示，ESC 恢复游戏
	if game_menu.is_pause_menu_visible():
		game_menu.hide_pause_menu()
		get_viewport().set_input_as_handled()
		return
	# 显示暂停菜单
	game_menu.show_pause_menu()
	get_viewport().set_input_as_handled()
	
	
func _on_turn_changed(turn: int, team: String) -> void:
	if hud and hud.has_method("update_turn"):
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


## ==================== 存档/读档/重试 ====================

## 点击 SAVE 按钮并选择存档槽位
func _on_save_requested(slot: int) -> void:
	var state: Dictionary = battle_manager.get_current_state()
	var file_name: String = SaveManager.save_to_slot(
		slot,
		state["player_units"],
		state["enemy_units"],
		state["turn_count"],
		state["current_team"]
	)
	if not file_name.is_empty():
		hud.show_message("已保存到存档槽位 %d" % (slot + 1), 1.5)
	else:
		hud.show_message("保存失败", 1.5)

## 点击 LOAD 按钮并选择存档槽位
func _on_load_requested(slot: int) -> void:
	var save_data: SaveData = SaveManager.load_from_slot(slot)
	if save_data == null:
		hud.show_message("存档槽位 %d 无存档" % (slot + 1), 1.5)
		return
	# 确保处于游戏模式（首次从主菜单载入存档）
	if not game_world.visible:
		game_world.visible = true
		if hud.has_node("BottomPanel"):
			hud.get_node("BottomPanel").visible = false
		if hud.has_node("Controls"):
			hud.get_node("Controls").visible = false
		# 初始化单位（从 JSON 读取初始位置，后续会被存档数据覆盖）
		_init_units_from_teams_json()
		_init_enemies_from_json()
		# 启动战斗管理器（注册单位）
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
		battle_manager.setup_battle(camera, hud)
	# 恢复战斗状态（覆盖初始位置）
	battle_manager.restore_from_save_data(save_data)
	# 隐藏菜单
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu:
		game_menu.is_in_game = true
		game_menu.hide_pause_menu()
	hud.show_message("已载入存档 %d" % (slot + 1), 1.5)

## 点击 RETRYBATTLE 按钮：重置到初始状态
func _on_retry_battle() -> void:
	var initial_state: SaveData = SaveManager.get_initial_state()
	if initial_state == null:
		hud.show_message("无初始状态可重置", 1.5)
		return
	battle_manager.restore_from_save_data(initial_state)
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu:
		game_menu.hide_pause_menu()
	hud.show_message("战斗已重置", 1.5)


## 点击 MAINMENU 按钮：返回主菜单
func _on_back_to_main_menu() -> void:
	# 标记不在游戏中
	var game_menu: Control = hud.get_node_or_null("GameMenu")
	if game_menu:
		game_menu.is_in_game = false
		game_menu.has_saved_game = true
		game_menu.show_main_menu(true)
	# 隐藏游戏世界
	game_world.visible = false
	_hide_all_units()
	if hud.has_node("BottomPanel"):
		hud.get_node("BottomPanel").visible = false
	if hud.has_node("Controls"):
		hud.get_node("Controls").visible = false


## 点击 CONTINUE 按钮：载入最新的存档
func _on_continue_game() -> void:
	# 查找最新的存档槽位（按保存时间，这里简化为按槽位顺序查找第一个有存档的）
	var latest_slot: int = -1
	var latest_time: String = ""
	for i in range(SaveManager.MAX_SLOTS):
		var save_data: SaveData = SaveManager.load_from_slot(i)
		if save_data != null:
			if latest_slot < 0 or save_data.save_time > latest_time:
				latest_slot = i
				latest_time = save_data.save_time
	if latest_slot < 0:
		hud.show_message("无存档可载入", 1.5)
		return
	# 复用 _on_load_requested 进行载入
	_on_load_requested(latest_slot)
