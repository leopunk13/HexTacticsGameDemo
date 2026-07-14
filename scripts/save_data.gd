extends Resource
class_name SaveData

## 存档标题（显示在存档槽中）
@export var title: String = ""
## 存档创建时间（ISO 格式字符串）
@export var save_time: String = ""
## 存档文件名（不含路径）
@export var file_name: String = ""

## ===== 战斗状态数据 =====
## 当前回合数
@export var turn_count: int = 1
## 当前回合队伍（"PLAYER" 或 "ENEMY"）
@export var current_team: String = "PLAYER"

## 友方单位状态列表
## 每个元素为 Dictionary，包含：unit_name, grid_coord(x,y), health, max_health,
## mana, max_mana, has_moved, has_attacked, is_turn_ended, facing_direction(x,y),
## is_dead, team
@export var player_units_data: Array = []
## 敌方单位状态列表（结构同上）
@export var enemy_units_data: Array = []
