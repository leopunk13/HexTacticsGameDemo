## 主场景（等距视角版）
## 组装所有游戏系统，启动战斗
extends Node


var camera: CameraController
var battle_manager: BattleManager
var hud: CanvasLayer
var map_generator: MapGenerator

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 创建相机（等距视角下相机初始位置稍微偏上）
	camera = CameraController.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(1.0, 1.0)
	camera.position = Vector2(0, -30)
	camera.set_map_bounds(Rect2(-600, -450, 1200, 900))
	add_child(camera)
	camera.make_current()
	# 生成地图
	map_generator = MapGenerator.new()
	add_child(map_generator)
	
	# 创建HUD
	hud = CanvasLayer.new()
	hud.name = "HUD"
	var hud_script: Script = load("res://scripts/hud.gd")
	hud.set_script(hud_script)
	add_child(hud)
	
	# 创建战斗管理器
	battle_manager = BattleManager.new()
	battle_manager.name = "BattleManager"
	add_child(battle_manager)
	# 连接信号
	battle_manager.turn_changed.connect(_on_turn_changed)
	battle_manager.state_changed.connect(_on_state_changed)
	battle_manager.battle_result.connect(_on_battle_result)
	battle_manager.unit_selected.connect(_on_unit_selected)
	battle_manager.message_shown.connect(_on_message_shown)

	# 设置HUD
	#hud.battle_manager = battle_manager

	# 启动战斗
	battle_manager.setup_battle(camera, hud)
	#
	
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
	
func _on_turn_changed(turn: int, team: String) -> void:
	hud.update_turn(turn, team)

func _on_state_changed(new_state: int) -> void:
	#hud.update_state_hint(new_state)
	if new_state == BattleManager.BattleState.SELECT_UNIT:
		hud.hide_unit_info()

func _on_battle_result(victory: bool) -> void:
	if victory:
		hud.show_message("战斗胜利！所有敌人已被消灭！", 5.0)
	else:
		hud.show_message("战斗失败...我方全灭...", 5.0)

func _on_unit_selected(unit: Unit) -> void:
	hud.show_unit_info(unit)

func _on_message_shown(text: String) -> void:
	hud.show_message(text, 1.5)
