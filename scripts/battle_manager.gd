## 战斗管理器
## 管理回合制战斗流程、单位选择、移动和攻击逻辑
extends Node2D
class_name BattleManager

## 节点引用
var camera: CameraController = null
var hud: CanvasLayer = null

## 战斗状态枚举
enum BattleState {
	IDLE,            ## 空闲
	SELECT_UNIT,     ## 选择单位
	SELECT_MOVE,     ## 选择移动目标
	SELECT_ATTACK,   ## 选择攻击目标
	SELECT_FACING,   ## 选择朝向（移动后）
	UNIT_MOVING,     ## 单位移动中
	ENEMY_TURN,      ## 敌方回合
	BATTLE_OVER,     ## 战斗结束
}

## 当前状态
var state: int = BattleState.SELECT_UNIT

## 当前选中的单位
var selected_unit: Unit = null

## 是否正在执行异步行动（攻击/移动），防止重入
var _is_processing_action: bool = false
## 朝向选择完成后是否结束当前单位回合（攻击后为 true，移动后为 false）
var _end_turn_after_facing: bool = false
## 移动后待攻击的目标（用于"移动+攻击"流程，移动完成后自动发起攻击）
var _pending_attack_target: Unit = null
## 当前选中的地块
var selected_tile: HexTile = null
## 可移动范围缓存
var reachable_tiles: Dictionary = {}
## 可攻击目标缓存
var attackable_coords: Array[Vector2i] = []

signal turn_changed(turn: int, team: String)
signal state_changed(new_state: int)
signal battle_result(victory: bool)
signal unit_selected(unit: Unit)
signal message_shown(text: String)

## 所有单位
var player_units: Array[Unit] = []
var enemy_units: Array[Unit] = []

## 调试用：记录本次移动点击地块的中心坐标
var _debug_move_tile_center: Vector2 = Vector2.ZERO
## 调试用：记录本次移动点击地块的轴向坐标
var _debug_move_axial: Vector2i = Vector2i.ZERO

## 警告提示音播放器（目标地块被已行动完毕的友军占据时播放）
var _warn_player: AudioStreamPlayer = null
const WARN_SOUND_PATH: String = "res://assets/sounds/warn.wav"

## 敌方AI相关
## 当前敌方回合待行动单位队列
var _enemy_ai_queue: Array[Unit] = []
## 当前正在行动的敌方单位
var _current_enemy: Unit = null

## 当前回合数
var turn_count: int = 1

## 初始化战斗
func setup_battle(cam: CameraController, hud_node: CanvasLayer) -> void:
	camera = cam
	hud = hud_node
	turn_count = 1
	# 连接 Autoload HexGrids 的 tile_clicked 信号
	if not HexGrids.tile_clicked.is_connected(_on_hex_tile_tile_clicked):
		HexGrids.tile_clicked.connect(_on_hex_tile_tile_clicked)
	# 连接地块悬停信号，用于显示攻击伤害预测
	if not HexGrids.tile_hovered.is_connected(_on_hex_tile_tile_hovered):
		HexGrids.tile_hovered.connect(_on_hex_tile_tile_hovered)
	# 创建警告提示音播放器
	_warn_player = AudioStreamPlayer.new()
	_warn_player.name = "WarnSoundPlayer"
	add_child(_warn_player)
	if ResourceLoader.exists(WARN_SOUND_PATH):
		_warn_player.stream = load(WARN_SOUND_PATH)
	else:
		push_warning("警告音文件不存在: %s，请放置该文件后重启" % WARN_SOUND_PATH)
	# 注册场景中的玩家单位到战斗管理器与地块
	_register_units()
	# 为所有单位创建朝向指示器（默认朝向最近的敌人）
	_create_all_facing_indicators()

## 播放警告提示音
func _play_warn_sound() -> void:
	if _warn_player and _warn_player.stream:
		_warn_player.play()

## 为所有单位创建朝向指示器，并设置默认朝向（指向最近的敌人）
func _create_all_facing_indicators() -> void:
	# 友方单位朝向最近的敌方单位
	for unit in player_units:
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		_set_default_facing_to_nearest_enemy(unit)
		unit.create_facing_indicator()
	# 敌方单位朝向最近的友方单位
	for unit in enemy_units:
		if unit == null or not is_instance_valid(unit) or unit.is_dead:
			continue
		_set_default_facing_to_nearest_player(unit)
		unit.create_facing_indicator()

## 清除所有单位的朝向指示器
func _clear_all_facing_indicators() -> void:
	for unit in player_units + enemy_units:
		if unit != null and is_instance_valid(unit):
			unit.clear_facing_indicator()

## 设置友方单位默认朝向最近的敌方单位
func _set_default_facing_to_nearest_enemy(unit: Unit) -> void:
	var nearest: Unit = _find_nearest_enemy_unit(unit.grid_coord)
	if nearest == null:
		return
	var diff: Vector2i = nearest.grid_coord - unit.grid_coord
	var target_pixel: Vector2 = HexUtils.axial_to_pixel(diff.x, diff.y)
	if target_pixel != Vector2.ZERO:
		unit.facing_direction = target_pixel.normalized()
		unit._update_sprite_flip(unit.facing_direction)

## 设置敌方单位默认朝向最近的友方单位
func _set_default_facing_to_nearest_player(unit: Unit) -> void:
	var nearest: Unit = _find_nearest_player_unit(unit.grid_coord)
	if nearest == null:
		return
	var diff: Vector2i = nearest.grid_coord - unit.grid_coord
	var target_pixel: Vector2 = HexUtils.axial_to_pixel(diff.x, diff.y)
	if target_pixel != Vector2.ZERO:
		unit.facing_direction = target_pixel.normalized()
		unit._update_sprite_flip(unit.facing_direction)

## 查找距离指定坐标最近的敌方单位（用于友方朝向）
func _find_nearest_enemy_unit(start: Vector2i) -> Unit:
	var nearest: Unit = null
	var min_dist: int = 999999
	for enemy in enemy_units:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead:
			continue
		var d: int = HexUtils.hex_distance(start, enemy.grid_coord)
		if d < min_dist:
			min_dist = d
			nearest = enemy
	return nearest

## 由 facing_direction (Vector2) 计算旋转角度（弧度）
## facing_direction 默认朝右 (1,0) 对应 0 弧度
static func facing_angle_from_direction(dir: Vector2) -> float:
	if dir == Vector2.ZERO:
		return 0.0
	return dir.angle()
	

# 圆环点求取函数
func arc(r1:float,r2:float,edges:int = 3,start_angle:=0.0,end_engle:=360.0) -> PackedVector2Array:
	var points:PackedVector2Array   # 圆环的顶点
	var v1 = (Vector2.RIGHT * r1).rotated(deg_to_rad(start_angle+30.0))
	var v2 = (Vector2.RIGHT * r2).rotated(deg_to_rad(start_angle+30.0))
	var ang = (end_engle - start_angle)/float(edges)  # 单次旋转角度
	var arc1:PackedVector2Array     # 圆弧1
	var arc2:PackedVector2Array     # 圆弧2
	# 通过向量旋转求不同半径的两条圆弧顶点
	for i in range(edges+1):
		arc1.append(v1.rotated(deg_to_rad( ang * i))) 
		arc2.append(v2.rotated(deg_to_rad( ang * i)))
	
	var close_circle = fposmod((end_engle - start_angle),360.0) == 0 # 圆弧闭合形成圆
	
	if close_circle:
		arc1.set(arc1.size()-1,arc1[arc1.size()-1] + Vector2.UP * 0.01)
	# 顺时针添加圆弧1的顶点
	points.append_array(arc1)
	
	arc2.reverse()
	if close_circle:
		arc2.set(arc2.size()-1,arc2[arc2.size()-1] - Vector2.UP * 0.01)
	# 逆时针添加圆弧1的顶点
	points.append_array(arc2)
	
	return points


## 注册场景中的单位到战斗管理器，并将其关联到所在地块
func _register_units() -> void:
	player_units.clear()
	enemy_units.clear()
	# 从场景树收集所有 Unit 实例（仅子 Unit 节点在 group 中）
	# 容器节点（Fighter/Saber）不加入分组，避免 grid_coord 为默认值导致错误覆盖
	var units: Array[Node] = get_tree().get_nodes_in_group("player")
	for node in units:
		if node is Unit and node.get_parent() is Unit:
			player_units.append(node as Unit)
			_register_unit_to_tile(node as Unit)
	units = get_tree().get_nodes_in_group("enemy")
	for node in units:
		if node is Unit and node.get_parent() is Unit:
			enemy_units.append(node as Unit)
			_register_unit_to_tile(node as Unit)

## 将单位注册到其 grid_coord 对应的地块上
func _register_unit_to_tile(unit: Unit) -> void:
	# 如果 grid_coord 无对应地块，尝试从单位世界坐标反推 axial 坐标
	var tile: HexTile = HexGrids.get_tile(unit.grid_coord)
	if tile == null:
		var parent_node: Node2D = unit.get_parent() if unit.get_parent() is Node2D else unit
		var inferred_coord: Vector2i = HexUtils.pixel_to_axial(parent_node.global_position.x, parent_node.global_position.y)
		if HexGrids.get_tile(inferred_coord) != null:
			unit.grid_coord = inferred_coord
			tile = HexGrids.get_tile(inferred_coord)
			DebugLog.debug_nospam("unit_register", "单位 %s 从世界坐标反推 grid_coord=%s" % [unit.unit_name, str(inferred_coord)])
	if tile:
		tile.occupying_unit = unit
		DebugLog.debug_nospam("unit_register", "单位 %s 注册到地块 %s" % [unit.unit_name, str(unit.grid_coord)])
	else:
		DebugLog.debug_nospam("unit_register", "警告：单位 %s 的 grid_coord %s 无对应地块" % [unit.unit_name, str(unit.grid_coord)])
	# 连接死亡信号（一次性，避免重复连接）
	if not unit.unit_died.is_connected(_on_unit_unit_died):
		unit.unit_died.connect(_on_unit_unit_died)


## 高亮可行动单位
func _highlight_selectable_units() -> void:
	for unit in player_units:
		if unit.can_act():
			var tile: HexTile = HexGrids.get_tile(unit.grid_coord)
			if tile:
				tile.highlight_type = HexTile.HighlightType.SELECTED



## 处理选择单位
func _handle_select_unit(tile: HexTile) -> void:
	DebugLog.debug_nospam("func_call","_handle_select_unit")
	if tile.is_occupied() and tile.occupying_unit.team == Unit.Team.PLAYER and tile.occupying_unit.can_act():
		selected_unit = tile.occupying_unit
		unit_selected.emit(selected_unit)

		HexGrids.clear_highlights()
		# 选中单位的朝向指示器已持续显示，无需重新创建

		# 显示移动范围
		if not selected_unit.has_moved:
			HexGrids.highlight_move_range(selected_unit.grid_coord, selected_unit.move_range)
			var reachable_tiles: Dictionary = HexGrids.get_reachable_tiles(selected_unit.grid_coord, selected_unit.move_range)
			for coord in reachable_tiles:
				var t: HexTile = HexGrids.get_tile(coord)
				if t:
					t.highlight_type = tile.HighlightType.MOVE
					var highlight: Polygon2D = Polygon2D.new()					
					var top_corners: PackedVector2Array = HexUtils.hex_top_corners(
						Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
					)
					
					highlight.polygon = PackedVector2Array(top_corners)
					highlight.position = HexUtils.axial_to_pixel(coord.x, coord.y)
					highlight.color = Color(0.2, 0.6, 1.0, 0.35)
					highlight.z_index = 1
					highlight.offset = Vector2(0,4)
					DebugLog.debug_nospam("update_visual","HighlightType==MOVE")
					t.highlight_overlay = highlight
					add_child(highlight)
					
		# 显示攻击范围
		if not selected_unit.has_attacked:
			
			var attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER, selected_unit.has_moved, selected_unit.move_range)
			for coord in attackable_coords:
				var t: HexTile = HexGrids.get_tile(coord)
				if t:
					t.highlight_type = HexTile.HighlightType.ATTACK
					var highlight: Polygon2D = Polygon2D.new()					
					var top_corners: PackedVector2Array = HexUtils.hex_top_corners(
						Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
					)
					
					highlight.polygon = PackedVector2Array(top_corners)
					highlight.position = HexUtils.axial_to_pixel(coord.x, coord.y)
					highlight.color = Color(1.0, 0.2, 0.2, 0.35)
					highlight.z_index = 1
					highlight.offset = Vector2(0,4)
					DebugLog.debug_nospam("update_visual","HighlightType==ATTACK")
					t.highlight_overlay = highlight
					add_child(highlight)

		# 选中单位高亮：始终基于 selected_unit.grid_coord 高亮其所在地块。
		# 不能使用 get_global_mouse_position()，因为本函数也会被
		# _switch_to_next_player_unit 程序自动调用，此时鼠标位置不在
		# 新选中单位上（例如朝向选择刚点击过的地块），会导致错误高亮。
		var unit_tile: HexTile = HexGrids.get_tile(selected_unit.grid_coord)
		if unit_tile:
			unit_tile.highlight_type = HexTile.HighlightType.SELECTED
			DebugLog.debug_nospam("update_visual","HighlightType==SELECTED")
			if unit_tile.highlight_overlay != null:
				var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
					Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
				)
				unit_tile.highlight_overlay.polygon = PackedVector2Array(unit_corners)
				unit_tile.highlight_overlay.color = Color(1.0, 1.0, 0.2, 0.4)
				unit_tile.highlight_overlay.z_index = 1
				unit_tile.highlight_overlay.offset = Vector2(0,4)
			else:
				var highlight_unit: Polygon2D = Polygon2D.new()
				var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
					Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
				)
				highlight_unit.polygon = PackedVector2Array(unit_corners)
				highlight_unit.color = Color(1.0, 1.0, 0.2, 0.4)
				highlight_unit.z_index = 1
				highlight_unit.offset = Vector2(0,4)
				unit_tile.highlight_overlay = highlight_unit
				add_child(highlight_unit)
		_set_state(BattleState.SELECT_MOVE)
		
## 处理选择移动目标
func _handle_select_move(tile: HexTile) -> void:
	# 从全局鼠标位置计算轴向坐标，确保获取实际点击地块的坐标
	# （tile 参数可能来自场景中未初始化的 HexTile，axial_coord 始终为 ZERO）
	var mouse_pos: Vector2 = get_global_mouse_position()
	var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
	DebugLog.debug_nospam("func_call","_handle_select_move")
	
	# 使用类成员 selected_unit（在 _handle_select_unit 中设置），而非 tile.occupying_unit
	# 因为 tile 是点击的移动目标地块，其上没有单位
	if selected_unit == null:
		_set_state(BattleState.SELECT_UNIT)
		return
	
	# 提前计算可移动范围，用于阻挡单位检查
	var reachable_tiles: Dictionary = HexGrids.get_reachable_tiles(selected_unit.grid_coord, selected_unit.move_range)

	# 阻挡单位检查（在清除高亮之前）：
	# 若点击的可移动地块上有友军且该友军已移动/攻击过或回合已结束，
	# 播放警告音并直接返回，保持原选中状态和高亮显示不变
	if clicked_coord in reachable_tiles and not selected_unit.has_moved:
		var dest_tile: HexTile = HexGrids.get_tile(clicked_coord)
		if dest_tile and dest_tile.is_occupied():
			var blocker: Unit = dest_tile.occupying_unit
			if blocker.has_moved or blocker.has_attacked or blocker.is_turn_ended:
				_play_warn_sound()
				return  # 高亮和选中状态保持不变
			# 友军仍可行动 → 切换选中状态到该单位
			_set_state(BattleState.SELECT_UNIT)
			_handle_select_unit(dest_tile)
			return

	# 清除高亮，准备执行攻击或移动
	HexGrids.clear_highlights()
	if tile.highlight_overlay != null:
		tile.highlight_overlay.color  = Color.TRANSPARENT
	# 点击攻击范围内的敌人
	var attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER, selected_unit.has_moved, selected_unit.move_range)
	if clicked_coord in attackable_coords and not selected_unit.has_attacked:
		var target_tile: HexTile = HexGrids.get_tile(clicked_coord)
		var target: Unit = target_tile.occupying_unit if target_tile else null
		if target and target.team == Unit.Team.ENEMY:
			# 清除伤害预测标签
			_clear_damage_preview()
			# 检查是否需要先移动到攻击位置（移动+攻击流程）
			var direct_distance: int = HexUtils.hex_distance(selected_unit.grid_coord, clicked_coord)
			if direct_distance > selected_unit.attack_range and not selected_unit.has_moved:
				# 需要先移动：找到最优攻击位置
				var best_pos: Vector2i = HexGrids.find_best_attack_position(selected_unit.grid_coord, clicked_coord, selected_unit.attack_range, selected_unit.move_range)
				if best_pos != selected_unit.grid_coord:
					# 设置待攻击目标，移动完成后自动发起攻击
					_pending_attack_target = target
					# 执行移动
					var move_path: Array[Vector2i] = HexGrids.find_path(selected_unit.grid_coord, best_pos, selected_unit.move_range)
					if not move_path.is_empty():
						var old_tile: HexTile = HexGrids.get_tile(selected_unit.grid_coord)
						if old_tile:
							old_tile.occupying_unit = null
						var new_tile: HexTile = HexGrids.get_tile(best_pos)
						if new_tile:
							new_tile.occupying_unit = selected_unit
						if not selected_unit.unit_moved.is_connected(_on_unit_unit_moved):
							selected_unit.unit_moved.connect(_on_unit_unit_moved)
						selected_unit.move_along_path(move_path)
						_set_state(BattleState.UNIT_MOVING)
						return
			# 直接攻击（当前位置在攻击范围内）
			_is_processing_action = true
			await selected_unit.attack(target)
			_is_processing_action = false
			_end_turn_after_facing = true
			HexGrids.clear_highlights()
			_set_state(BattleState.SELECT_FACING)
			return

	# 点击可移动地块（阻挡单位已在上方处理，此处地块无单位）
	if clicked_coord in reachable_tiles and not selected_unit.has_moved:
		var path: Array[Vector2i] = HexGrids.find_path(selected_unit.grid_coord, clicked_coord, selected_unit.move_range)
		if not path.is_empty():
			# 清除旧位置
			var old_tile: HexTile = HexGrids.get_tile(selected_unit.grid_coord)
			if old_tile:
				old_tile.occupying_unit = null

			# 设置新位置
			var new_tile: HexTile = HexGrids.get_tile(clicked_coord)
			if new_tile:
				new_tile.occupying_unit = selected_unit

			# 避免重复连接信号（单位多次移动时会重复调用connect）
			# 必须在 _set_state(UNIT_MOVING) 之前连接，因为 _set_state 会清除 selected_unit
			if not selected_unit.unit_moved.is_connected(_on_unit_unit_moved):
				selected_unit.unit_moved.connect(_on_unit_unit_moved)
			selected_unit.move_along_path(path)
			_set_state(BattleState.UNIT_MOVING)
			# 记录点击地块中心坐标，供移动完成后对比
			_debug_move_tile_center = HexUtils.axial_to_pixel(clicked_coord.x, clicked_coord.y)
			_debug_move_axial = clicked_coord
			return

	# 点击自身（取消选择/待机）
	if selected_unit != null and clicked_coord == selected_unit.grid_coord:
		_set_state(BattleState.SELECT_UNIT)
		return

	# 点击其他玩家单位（切换选择）
	if tile.is_occupied() and tile.occupying_unit.team == Unit.Team.PLAYER and tile.occupying_unit.can_act():
		_set_state(BattleState.SELECT_UNIT)
		_handle_select_unit(tile)
		return

	# 点击无效区域，取消选择
	_set_state(BattleState.SELECT_UNIT)

## 处理选择攻击目标
func _handle_select_attack(tile: HexTile) -> void:
	# 从全局鼠标位置计算轴向坐标，确保获取实际点击地块的坐标
	# （tile 参数可能来自场景中未初始化的 HexTile，axial_coord 始终为 ZERO）
	var mouse_pos: Vector2 = get_global_mouse_position()
	var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
	DebugLog.debug_nospam("func_call","_handle_select_attack")
	if clicked_coord in attackable_coords:
		var target_tile: HexTile = HexGrids.get_tile(clicked_coord)
		var target: Unit = target_tile.occupying_unit if target_tile else null
		if target and target.team == Unit.Team.ENEMY:
			# 设置行动锁，防止攻击动画期间重入
			_is_processing_action = true
			# 异步执行攻击（含动画播放）
			await selected_unit.attack(target)
			_is_processing_action = false
			# 攻击结束后进入朝向选择状态，朝向选择完成后结束回合
			_end_turn_after_facing = true
			HexGrids.clear_highlights()
			_set_state(BattleState.SELECT_FACING)
			return

	# 取消
	_set_state(BattleState.SELECT_UNIT)

## 为指定地块创建高亮覆盖层（因为 HexTile._update_visual 为空，
## 需要手动创建 Polygon2D 覆盖层才能在画面上显示高亮）
func _create_highlight_overlay(coord: Vector2i, highlight_type: int) -> void:
	var t: HexTile = HexGrids.get_tile(coord)
	if t == null:
		return
	t.highlight_type = highlight_type
	# 移除旧覆盖层
	if t.highlight_overlay != null and is_instance_valid(t.highlight_overlay):
		t.highlight_overlay.queue_free()
	# 创建新覆盖层
	var highlight: Polygon2D = Polygon2D.new()
	var top_corners: PackedVector2Array = HexUtils.hex_top_corners(
		Vector2.ZERO, HexUtils.HEX_SIZE + 1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
	)
	highlight.polygon = PackedVector2Array(top_corners)
	highlight.position = HexUtils.axial_to_pixel(coord.x, coord.y)
	highlight.z_index = 1
	highlight.offset = Vector2(0, 4)
	match highlight_type:
		HexTile.HighlightType.MOVE:
			highlight.color = Color(0.2, 0.6, 1.0, 0.35)
		HexTile.HighlightType.ATTACK:
			highlight.color = Color(1.0, 0.2, 0.2, 0.35)
		HexTile.HighlightType.SELECTED:
			highlight.color = Color(1.0, 1.0, 0.2, 0.4)
		_:
			highlight.color = Color.TRANSPARENT
	t.highlight_overlay = highlight
	add_child(highlight)

## 显示剩余可用行动
func _show_remaining_actions(unit:Unit) -> void:
	selected_unit = unit
	# 先切换状态（_set_state 内部会清空成员变量和高亮预测），
	# 避免后续设置的高亮和成员变量被 _set_state 的清空操作覆盖
	_set_state(BattleState.SELECT_MOVE)
	HexGrids.clear_highlights()
	# 选中高亮
	_create_highlight_overlay(selected_unit.grid_coord, HexTile.HighlightType.SELECTED)

	if not selected_unit.has_moved:
		reachable_tiles = HexGrids.get_reachable_tiles(selected_unit.grid_coord, selected_unit.move_range)
		for coord in reachable_tiles:
			_create_highlight_overlay(coord, HexTile.HighlightType.MOVE)

	if not selected_unit.has_attacked:
		attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER, selected_unit.has_moved, selected_unit.move_range)
		for coord in attackable_coords:
			_create_highlight_overlay(coord, HexTile.HighlightType.ATTACK)
		# 移动后若无攻击目标，直接进入朝向选择（移动后必选朝向）
		if selected_unit.has_moved and attackable_coords.is_empty():
			_end_turn_after_facing = true
			_set_state(BattleState.SELECT_FACING)

## 设置状态
func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)
	#HexGrids.clear_highlights()
	# 状态切换时清除伤害预测标签
	_clear_damage_preview()
	# 在需要选中单位的状态（选择移动/攻击/朝向）中保留 selected_unit
	# 仅在回到 SELECT_UNIT 等非选择状态时清除，以便重新选择
	if state not in [BattleState.SELECT_MOVE, BattleState.SELECT_ATTACK, BattleState.SELECT_FACING]:
		selected_unit = null
	# 朝向指示器现在持续显示，切换状态时不清除
	reachable_tiles.clear()
	attackable_coords.clear()

	# 根据状态更新UI提示
	match state:
		BattleState.SELECT_UNIT:
			_highlight_selectable_units()
			# 所有玩家单位都无法行动时，自动进入敌方回合
			if _all_player_units_done():
				# 延迟一帧，避免在 _set_state 内部触发新的 _set_state 导致递归
				call_deferred("start_enemy_turn")
		BattleState.SELECT_MOVE:
			pass
		BattleState.SELECT_ATTACK:
			pass
		BattleState.SELECT_FACING:
			# 显示朝向选择高亮（6个相邻方向）
			if selected_unit != null:
				_show_facing_options(selected_unit)

## 检查所有玩家单位是否都无法行动（已移动且已攻击或已死亡）
func _all_player_units_done() -> bool:
	if player_units.is_empty():
		return false
	for player in player_units:
		if player != null and is_instance_valid(player) and not player.is_dead:
			if player.can_act():
				return false
	return true


## 点击地块
func _on_hex_tile_tile_clicked(tile: HexTile) -> void:
	# 正在执行异步行动（攻击动画/移动）时，忽略后续点击，防止重入
	if _is_processing_action:
		return
	match state:
		BattleState.SELECT_UNIT:
			_handle_select_unit(tile)
		BattleState.SELECT_MOVE:
			_handle_select_move(tile)
		BattleState.SELECT_ATTACK:
			_handle_select_attack(tile)
		BattleState.SELECT_FACING:
			_handle_select_facing(tile)

## 当前伤害预测标签（悬停时显示）
var _damage_preview_label: Label = null
## 当前正在显示伤害预览的目标单位（用于清除血条覆盖层）
var _damage_preview_target: Unit = null

## 地块悬停回调：在 SELECT_MOVE 状态下悬停攻击范围内的敌方单位时显示伤害预测
func _on_hex_tile_tile_hovered(tile: HexTile) -> void:
	_clear_damage_preview()
	# 仅在 SELECT_MOVE 状态且已选中单位且单位未攻击过时显示预测
	if state != BattleState.SELECT_MOVE or selected_unit == null or selected_unit.has_attacked:
		return
	if tile == null or not tile.is_occupied():
		return
	var target: Unit = tile.occupying_unit
	if target == null or target.team == Unit.Team.PLAYER or target.is_dead:
		return
	# 检查目标是否在攻击范围内
	var attackable: Array[Vector2i] = HexGrids.get_attackable_tiles(
		selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER,
		selected_unit.has_moved, selected_unit.move_range)
	if tile.axial_coord not in attackable:
		return
	_show_damage_preview(selected_unit, target, tile)

## 显示伤害预测：在目标血条上标记预期伤害，并在目标旁显示命中率与伤害数值
func _show_damage_preview(attacker: Unit, target: Unit, tile: HexTile) -> void:
	var hit_chance: float = attacker.calculate_hit_chance(target)
	var damage: float = attacker.attack_damage
	# 在目标血条上显示暗黄色伤害预览覆盖层（红色为预期血量，暗黄色为预期伤害）
	target.show_damage_preview(damage)
	_damage_preview_target = target
	# 创建标签显示命中率与伤害数值
	_damage_preview_label = Label.new()
	_damage_preview_label.text = "伤害:%d 命中:%d%%" % [int(damage), int(round(hit_chance))]
	_damage_preview_label.add_theme_color_override("font_color", Color.WHITE)
	_damage_preview_label.add_theme_font_size_override("font_size", 14)
	_damage_preview_label.z_index = 100
	# 标签位置：目标地块上方
	var label_pos: Vector2 = HexUtils.axial_to_pixel(tile.axial_coord.x, tile.axial_coord.y)
	label_pos.y -= 50.0
	_damage_preview_label.position = label_pos
	_damage_preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_damage_preview_label.add_theme_constant_override("outline_size", 4)
	add_child(_damage_preview_label)

## 清除伤害预测标签和血条覆盖层
func _clear_damage_preview() -> void:
	if _damage_preview_label != null and is_instance_valid(_damage_preview_label):
		_damage_preview_label.queue_free()
	_damage_preview_label = null
	# 清除目标血条上的伤害预览覆盖层
	if _damage_preview_target != null and is_instance_valid(_damage_preview_target):
		_damage_preview_target.clear_damage_preview()
	_damage_preview_target = null

## 单位行动完成回调
func _on_unit_action_finished(unit: Unit) -> void:
	pass # Replace with function body.

## 单位移动完成回调
func _on_unit_unit_moved(unit: Unit) -> void:
	if state == BattleState.UNIT_MOVING:
		# 修正单位到地块中心位置（移动过程中可能存在像素偏差）
		unit._sync_position_to_tile()
		selected_unit = unit
		# 检查是否有待攻击目标（移动+攻击流程）
		if _pending_attack_target != null and is_instance_valid(_pending_attack_target) and not _pending_attack_target.is_dead:
			# 移动完成后自动发起攻击
			var target: Unit = _pending_attack_target
			_pending_attack_target = null
			_is_processing_action = true
			await unit.attack(target)
			_is_processing_action = false
			_end_turn_after_facing = true
			HexGrids.clear_highlights()
			_set_state(BattleState.SELECT_FACING)
		else:
			# 清除待攻击目标（目标已死亡或无效）
			_pending_attack_target = null
			# 移动完成后直接显示剩余可用行动（攻击范围等）
			_show_remaining_actions(unit)

## 显示朝向选择高亮（6个相邻方向，白色）
func _show_facing_options(unit: Unit) -> void:
	HexGrids.clear_highlights()
	# 高亮当前单位所在地块
	var current_tile: HexTile = HexGrids.get_tile(unit.grid_coord)
	if current_tile:
		current_tile.highlight_type = HexTile.HighlightType.SELECTED
		# 朝向指示器已持续显示，无需重新创建
		unit._sync_position_to_tile()
	# 高亮6个相邻方向供玩家点击选择朝向（白色）
	for dir in HexUtils.HEX_DIRECTIONS:
		var neighbor_coord: Vector2i = unit.grid_coord + dir
		var t: HexTile = HexGrids.get_tile(neighbor_coord)
		if t:
			t.highlight_type = HexTile.HighlightType.MOVE
			# 创建白色高亮覆盖
			var highlight: Polygon2D = Polygon2D.new()
			var top_corners: PackedVector2Array = HexUtils.hex_top_corners(
				Vector2.ZERO, HexUtils.HEX_SIZE + 1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
			)
			highlight.polygon = PackedVector2Array(top_corners)
			highlight.position = HexUtils.axial_to_pixel(neighbor_coord.x, neighbor_coord.y)
			highlight.color = Color(1.0, 1.0, 1.0, 0.4)
			highlight.z_index = 1
			highlight.offset = Vector2(0, 4)
			# 移除旧覆盖
			if t.highlight_overlay != null and is_instance_valid(t.highlight_overlay):
				t.highlight_overlay.queue_free()
			t.highlight_overlay = highlight
			add_child(highlight)

## 选中朝向地块闪烁动画
func _flash_selected_facing_tile(coord: Vector2i) -> void:
	var t: HexTile = HexGrids.get_tile(coord)
	if t == null:
		return
	# 创建闪烁用的白色高亮覆盖
	var flash: Polygon2D = Polygon2D.new()
	var top_corners: PackedVector2Array = HexUtils.hex_top_corners(
		Vector2.ZERO, HexUtils.HEX_SIZE + 1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
	)
	flash.polygon = PackedVector2Array(top_corners)
	flash.position = HexUtils.axial_to_pixel(coord.x, coord.y)
	flash.color = Color(1.0, 1.0, 1.0, 1.0)
	flash.z_index = 2
	flash.offset = Vector2(0, 4)
	add_child(flash)
	# 创建 Tween 闪烁：透明度 1.0 → 0.2 → 1.0 → 0.0，结束后 queue_free
	var tween: Tween = create_tween()
	tween.set_loops(1)
	tween.tween_property(flash, "color:a", 0.2, 0.12)
	tween.tween_property(flash, "color:a", 1.0, 0.12)
	tween.tween_property(flash, "color:a", 0.2, 0.12)
	tween.tween_property(flash, "color:a", 1.0, 0.12)
	tween.tween_property(flash, "color:a", 0.0, 0.15)
	tween.tween_callback(flash.queue_free)

## 处理选择朝向
func _handle_select_facing(tile: HexTile) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
	DebugLog.debug_nospam("func_call","_handle_select_facing")
	if selected_unit == null:
		_end_turn_after_facing = false
		_set_state(BattleState.SELECT_UNIT)
		return

	# 取出并重置标志，决定朝向选择完成后是结束回合还是继续行动
	var end_turn: bool = _end_turn_after_facing
	_end_turn_after_facing = false

	# 点击自身地块：保持当前朝向，跳过朝向选择
	if clicked_coord == selected_unit.grid_coord:
		_flash_selected_facing_tile(clicked_coord)
		_finish_facing(end_turn)
		return

	# 点击相邻地块：设置朝向
	var diff: Vector2i = clicked_coord - selected_unit.grid_coord
	if diff in HexUtils.HEX_DIRECTIONS:
		selected_unit.set_facing_from_coord(diff)
		# 选中地块闪烁
		_flash_selected_facing_tile(clicked_coord)
		# 更新朝向指示器旋转（set_facing_from_coord 内部已调用 update_facing_indicator_rotation）
	_finish_facing(end_turn)

## 朝向选择完成后的收尾工作
## end_turn 为 true 时结束当前单位回合并切换到下一个未行动角色；
## 为 false 时（移动后路径）显示剩余可用行动
func _finish_facing(end_turn: bool) -> void:
	if end_turn:
		# 攻击后路径：结束当前单位回合
		if selected_unit != null and is_instance_valid(selected_unit):
			selected_unit.is_turn_ended = true
		_switch_to_next_player_unit()
	else:
		# 移动后路径：显示剩余可用行动
		_show_remaining_actions(selected_unit)

## 切换到下一个可行动的 Player 单位
## 若没有可行动单位，回到 SELECT_UNIT 状态（会自动检测是否进入敌方回合）
func _switch_to_next_player_unit() -> void:
	HexGrids.clear_highlights()
	# 朝向指示器持续显示，切换单位时不清除
	# 清除当前选中，避免误用
	selected_unit = null
	# 寻找下一个可行动的玩家单位
	var next_unit: Unit = null
	for unit in player_units:
		if unit != null and is_instance_valid(unit) and not unit.is_dead and unit.can_act():
			next_unit = unit
			break
	if next_unit == null:
		# 无可行动单位，回到 SELECT_UNIT 状态（_set_state 会检测是否进入敌方回合）
		_set_state(BattleState.SELECT_UNIT)
		return
	# 自动选中下一个单位并显示其可行动范围
	var next_tile: HexTile = HexGrids.get_tile(next_unit.grid_coord)
	if next_tile:
		_set_state(BattleState.SELECT_UNIT)
		_handle_select_unit(next_tile)

## 单位死亡回调
func _on_unit_unit_died(unit: Unit) -> void:
	# 从单位列表中移除死亡单位
	player_units.erase(unit)
	enemy_units.erase(unit)
	# 清除死亡单位的朝向指示器
	unit.clear_facing_indicator()
	# 清除地块上的占据单位
	if HexGrids.get_tile(unit.grid_coord) != null:
		var tile: HexTile = HexGrids.get_tile(unit.grid_coord)
		if tile.occupying_unit == unit:
			tile.occupying_unit = null
	# 检查战斗是否结束
	if player_units.is_empty():
		battle_result.emit(false)
	elif enemy_units.is_empty():
		battle_result.emit(true)

## ==================== 敌方AI ====================

## 开始敌方回合：依次让每个敌方单位行动
func start_enemy_turn() -> void:
	# 重置所有敌方单位本回合行动状态
	for enemy in enemy_units:
		enemy.has_moved = false
		enemy.has_attacked = false
		enemy.is_turn_ended = false
	# 构建行动队列（过滤已死亡单位）
	_enemy_ai_queue.clear()
	for enemy in enemy_units:
		if not enemy.is_dead:
			_enemy_ai_queue.append(enemy)
	turn_changed.emit(turn_count, "ENEMY")
	_set_state(BattleState.ENEMY_TURN)
	# 开始处理队列中的下一个单位
	_process_next_enemy()

## 处理队列中的下一个敌方单位
func _process_next_enemy() -> void:
	# 清理已完成或死亡的单位
	while not _enemy_ai_queue.is_empty():
		var front: Unit = _enemy_ai_queue[0]
		if front == null or not is_instance_valid(front) or front.is_dead:
			_enemy_ai_queue.pop_front()
			continue
		break

	if _enemy_ai_queue.is_empty():
		# 所有敌方单位行动完毕，重置玩家单位状态并切回玩家回合
		_current_enemy = null
		_reset_player_units_for_new_turn()
		# 回合数+1（敌方回合结束后进入新的玩家回合）
		turn_count += 1
		turn_changed.emit(turn_count, "PLAYER")
		_set_state(BattleState.SELECT_UNIT)
		return

	_current_enemy = _enemy_ai_queue.pop_front()
	_execute_enemy_action(_current_enemy)

## 执行单个敌方单位的行动：先移动靠近最近的玩家单位，再尝试攻击
func _execute_enemy_action(enemy: Unit) -> void:
	if enemy == null or enemy.is_dead:
		_process_next_enemy()
		return

	# 寻找最近的存活的玩家单位
	var target: Unit = _find_nearest_player_unit(enemy.grid_coord)
	if target == null:
		# 无可攻击目标，直接处理下一个
		_process_next_enemy()
		return

	# 1. 移动阶段：若未移动且不在攻击范围内，则向目标移动
	if not enemy.has_moved:
		var dist_to_target: int = HexUtils.hex_distance(enemy.grid_coord, target.grid_coord)
		if dist_to_target > enemy.attack_range:
			# 寻找能到达且离目标最近的地块
			var move_dest: Vector2i = _find_best_move_tile(enemy, target.grid_coord)
			if move_dest != enemy.grid_coord:
				_move_enemy_along_path(enemy, move_dest)
				return  # 等待移动完成信号后继续
		# 不需要移动或在攻击范围内，直接进入攻击阶段
		_enemy_try_attack(enemy, target)
		return
	# 已移动过，直接尝试攻击
	_enemy_try_attack(enemy, target)

## 敌方单位尝试攻击目标
func _enemy_try_attack(enemy: Unit, target: Unit) -> void:
	if not enemy.has_attacked and not enemy.is_dead and target != null and not target.is_dead:
		var dist: int = HexUtils.hex_distance(enemy.grid_coord, target.grid_coord)
		if dist <= enemy.attack_range:
			# 异步执行攻击（含动画），完成后继续处理下一个
			_do_enemy_attack_and_continue(enemy, target)
			return
	# 不需要攻击，直接设置朝向并处理下一个
	_finalize_enemy_action(enemy, target)

## 异步执行敌方攻击，完成后处理下一个单位
func _do_enemy_attack_and_continue(enemy: Unit, target: Unit) -> void:
	await enemy.attack(target)
	_finalize_enemy_action(enemy, target)

## 敌方单位行动完毕的收尾工作
func _finalize_enemy_action(enemy: Unit, target: Unit) -> void:
	if target != null and is_instance_valid(target) and not target.is_dead:
		var diff: Vector2i = target.grid_coord - enemy.grid_coord
		if diff != Vector2i.ZERO:
			enemy.set_facing_from_coord(diff)
	# 本单位行动完毕，处理下一个
	enemy.is_turn_ended = true
	# 短暂延迟后处理下一个，避免动画卡顿
	get_tree().create_timer(0.3).timeout.connect(_process_next_enemy)

## 敌方单位沿路径移动，移动完成后继续攻击
func _move_enemy_along_path(enemy: Unit, dest: Vector2i) -> void:
	var path: Array[Vector2i] = HexGrids.find_path(enemy.grid_coord, dest, enemy.move_range)
	if path.is_empty():
		# 无法寻路，直接尝试攻击
		var target: Unit = _find_nearest_player_unit(enemy.grid_coord)
		_enemy_try_attack(enemy, target)
		return
	# 清除旧位置占据
	var old_tile: HexTile = HexGrids.get_tile(enemy.grid_coord)
	if old_tile:
		old_tile.occupying_unit = null
	# 设置新位置占据（移动过程中提前注册到终点，避免其他单位寻路穿过）
	var new_tile: HexTile = HexGrids.get_tile(dest)
	if new_tile:
		new_tile.occupying_unit = enemy
	# 连接一次性信号：移动完成后继续攻击
	if not enemy.unit_moved.is_connected(_on_enemy_moved):
		enemy.unit_moved.connect(_on_enemy_moved, CONNECT_ONE_SHOT)
	enemy.move_along_path(path)

## 敌方单位移动完成回调：继续攻击目标
func _on_enemy_moved(unit: Unit) -> void:
	# 更新单位坐标（move_along_path 内部已更新 grid_coord）
	# 修正单位到地块中心位置（移动过程中可能存在像素偏差），与玩家单位移动后处理一致
	unit._sync_position_to_tile()
	var target: Unit = _find_nearest_player_unit(unit.grid_coord)
	_enemy_try_attack(unit, target)

## 寻找距离 start 最近的存活玩家单位
func _find_nearest_player_unit(start: Vector2i) -> Unit:
	var nearest: Unit = null
	var min_dist: int = 999999
	for player in player_units:
		if player == null or not is_instance_valid(player) or player.is_dead:
			continue
		var d: int = HexUtils.hex_distance(start, player.grid_coord)
		if d < min_dist:
			min_dist = d
			nearest = player
	return nearest

## 寻找敌方单位移动到哪个地块能离目标最近
func _find_best_move_tile(enemy: Unit, target_coord: Vector2i) -> Vector2i:
	var reachable: Dictionary = HexGrids.get_reachable_tiles(enemy.grid_coord, enemy.move_range)
	var best_coord: Vector2i = enemy.grid_coord
	var best_dist: int = HexUtils.hex_distance(enemy.grid_coord, target_coord)
	for coord in reachable:
		# reachable 不含被敌方占据的地块，但可能含被友军占据的（需要排除）
		var tile: HexTile = HexGrids.get_tile(coord)
		if tile == null or tile.is_occupied():
			continue
		var d: int = HexUtils.hex_distance(coord, target_coord)
		if d < best_dist:
			best_dist = d
			best_coord = coord
	return best_coord

## 重置所有玩家单位本回合行动状态
func _reset_player_units_for_new_turn() -> void:
	for player in player_units:
		if player != null and is_instance_valid(player) and not player.is_dead:
			player.has_moved = false
			player.has_attacked = false
			player.is_turn_ended = false


## ==================== 存档/读档/重试 ====================

## 获取当前战斗状态用于存档
func get_current_state() -> Dictionary:
	var current_team: String = "PLAYER"
	if state == BattleState.ENEMY_TURN:
		current_team = "ENEMY"
	return {
		"turn_count": turn_count,
		"current_team": current_team,
		"player_units": player_units,
		"enemy_units": enemy_units,
	}

## 从存档数据恢复战斗状态
func restore_from_save_data(save_data: SaveData) -> void:
	# 清除当前状态
	HexGrids.clear_highlights()
	# 重置异步操作状态（角色死亡时可能处于攻击/移动中，这些变量未清理）
	_is_processing_action = false
	_end_turn_after_facing = false
	_pending_attack_target = null
	_current_enemy = null
	_enemy_ai_queue.clear()
	# 清除所有单位的朝向指示器（稍后重新创建）
	_clear_all_facing_indicators()
	# 清除所有地块上的单位占据
	for unit in player_units + enemy_units:
		if unit != null and is_instance_valid(unit):
			var tile: HexTile = HexGrids.get_tile(unit.grid_coord)
			if tile and tile.occupying_unit == unit:
				tile.occupying_unit = null
	# 恢复回合数和队伍
	turn_count = save_data.turn_count
	# 重新注册单位列表（恢复死亡单位到列表中）
	player_units.clear()
	enemy_units.clear()
	# 恢复友方单位
	_restore_units(save_data.player_units_data, Unit.Team.PLAYER, player_units)
	# 恢复敌方单位
	_restore_units(save_data.enemy_units_data, Unit.Team.ENEMY, enemy_units)
	# 重新注册地块占据
	for unit in player_units + enemy_units:
		if not unit.is_dead:
			var tile: HexTile = HexGrids.get_tile(unit.grid_coord)
			if tile:
				tile.occupying_unit = unit
	# 设置状态
	var target_state: int = BattleState.SELECT_UNIT
	if save_data.current_team == "ENEMY":
		# 若存档时在敌方回合，恢复后直接进入玩家回合（简化处理）
		target_state = BattleState.SELECT_UNIT
	selected_unit = null
	_set_state(target_state)
	turn_changed.emit(turn_count, "PLAYER")
	# 仅在 hud 存在 update_turn 方法时调用（该方法可能未实现）
	if hud and hud.has_method("update_turn"):
		hud.update_turn(turn_count, "PLAYER")
	# 为所有单位重新创建朝向指示器（使用存档中的朝向）
	for unit in player_units + enemy_units:
		if unit != null and is_instance_valid(unit) and not unit.is_dead:
			unit.create_facing_indicator()

## 从存档数据恢复单位列表
func _restore_units(units_data: Array, team: Unit.Team, target_list: Array) -> void:
	# 从场景中收集所有对应队伍的单位节点
	var group_name: String = "player" if team == Unit.Team.PLAYER else "enemy"
	var scene_units: Array[Node] = get_tree().get_nodes_in_group(group_name)
	# 按父节点名称（Fighter/Saber/Enemy1 等）建立映射，用于存档匹配
	var name_to_unit: Dictionary = {}
	for node in scene_units:
		if node is Unit and node.get_parent() is Unit:
			name_to_unit[node.get_parent().name] = node
	# 根据存档数据恢复每个单位
	for unit_dict in units_data:
		var unit_name: String = unit_dict.get("unit_name", "")
		var unit: Unit = name_to_unit.get(unit_name, null)
		if unit == null or not is_instance_valid(unit):
			continue
		# 恢复属性
		unit.grid_coord = Vector2i(unit_dict.get("grid_x", 0), unit_dict.get("grid_y", 0))
		unit.health = unit_dict.get("health", unit.max_health)
		unit.max_health = unit_dict.get("max_health", 100.0)
		unit.mana = unit_dict.get("mana", unit.max_mana)
		unit.max_mana = unit_dict.get("max_mana", 50.0)
		unit.has_moved = unit_dict.get("has_moved", false)
		unit.has_attacked = unit_dict.get("has_attacked", false)
		unit.is_turn_ended = unit_dict.get("is_turn_ended", false)
		unit.facing_direction = Vector2(unit_dict.get("facing_x", 1.0), unit_dict.get("facing_y", 0.0))
		unit.is_dead = unit_dict.get("is_dead", false)
		# 同步世界位置
		var tile_center: Vector2 = HexUtils.axial_to_pixel(unit.grid_coord.x, unit.grid_coord.y)
		tile_center.y -= 25.0
		var parent_node: Node2D = unit.get_parent() as Node2D
		if parent_node:
			parent_node.global_position = tile_center
			parent_node.visible = not unit.is_dead
		# 恢复血条/法力条显示
		if unit.health_bar:
			unit.health_bar.max_value = unit.max_health
			unit.health_bar.value = unit.health
		if unit.mana_bar:
			unit.mana_bar.max_value = unit.max_mana
			unit.mana_bar.value = unit.mana
		# 恢复动画状态
		if unit.is_dead:
			if unit.animated_sprite and unit.animated_sprite.sprite_frames and unit.animated_sprite.sprite_frames.has_animation("death"):
				unit.animated_sprite.stop()
		else:
			if unit.animated_sprite and unit.animated_sprite.sprite_frames and unit.animated_sprite.sprite_frames.has_animation("idle"):
				unit.animated_sprite.play("idle")
			# 同步精灵图朝向（根据存档的 facing_direction 更新 flip_h）
			unit._update_sprite_flip(unit.facing_direction)
		# 添加到列表
		target_list.append(unit)
		# 重新连接死亡信号
		if not unit.unit_died.is_connected(_on_unit_unit_died):
			unit.unit_died.connect(_on_unit_unit_died)
