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

## 初始化战斗
func setup_battle(cam: CameraController, hud_node: CanvasLayer) -> void:
	camera = cam
	hud = hud_node

## 高亮可行动单位
func _highlight_selectable_units() -> void:
	for unit in player_units:
		if unit.can_act():
			var tile: HexTile = HexGrids.get_tile(unit.grid_coord)
			if tile:
				tile.highlight_type = HexTile.HighlightType.SELECTED
				var mouse_pos: Vector2 = get_global_mouse_position()
				var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
				# 设置新位置
				var new_tile: HexTile = HexGrids.get_tile(clicked_coord)
				if new_tile:
					new_tile.highlight_type = HexTile.HighlightType.SELECTED
					DebugLog.debug_nospam("update_visual","HighlightType==SELECTED")
					if new_tile.highlight_overlay != null:
			
						var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
							Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
						)
						new_tile.highlight_overlay.polygon = PackedVector2Array(unit_corners)
		
						new_tile.highlight_overlay.color = Color(1.0, 1.0, 0.2, 0.4)
						new_tile.highlight_overlay.z_index = 1
						new_tile.highlight_overlay.offset = Vector2(0,4)



## 处理选择单位
func _handle_select_unit(tile: HexTile) -> void:
	DebugLog.debug_nospam("func_call","_handle_select_unit")
	if tile.is_occupied() and tile.occupying_unit.team == Unit.Team.PLAYER and tile.occupying_unit.can_act():
		var selected_unit:Unit = tile.occupying_unit
		unit_selected.emit(selected_unit)
		
		HexGrids.clear_highlights()
		
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
			
			var attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER)
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

		# 选中单位高亮
		var mouse_pos: Vector2 = get_global_mouse_position()
		var cur_pixel: Vector2 = HexUtils.axial_to_pixel(selected_unit.grid_coord.x,selected_unit.grid_coord.y)
		var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
		if clicked_coord != selected_unit.grid_coord:
			# 设置新位置
			var new_tile: HexTile = HexGrids.get_tile(clicked_coord)
			if new_tile:
				new_tile.highlight_type = HexTile.HighlightType.SELECTED
				DebugLog.debug_nospam("update_visual","HighlightType==SELECTED")
				if new_tile.highlight_overlay != null:
			
					var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
						Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
					)
					new_tile.highlight_overlay.polygon = PackedVector2Array(unit_corners)
		
					new_tile.highlight_overlay.color = Color(1.0, 1.0, 0.2, 0.4)
					new_tile.highlight_overlay.z_index = 1
					new_tile.highlight_overlay.offset = Vector2(0,4)

				else:
					var highlight_unit: Polygon2D = Polygon2D.new()					
					var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
						Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
					)
					highlight_unit.polygon = PackedVector2Array(unit_corners)
		
					highlight_unit.color = Color(1.0, 1.0, 0.2, 0.4)
					highlight_unit.z_index = 1
					highlight_unit.offset = Vector2(0,4)
					new_tile.highlight_overlay = highlight_unit
					add_child(highlight_unit)
		else:
			tile.highlight_type = HexTile.HighlightType.SELECTED
			DebugLog.debug_nospam("update_visual","HighlightType==SELECTED")
			if tile.highlight_overlay != null:
			
				var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
					Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
				)
				tile.highlight_overlay.polygon = PackedVector2Array(unit_corners)
		
				tile.highlight_overlay.color = Color(1.0, 1.0, 0.2, 0.4)
				tile.highlight_overlay.z_index = 1
				tile.highlight_overlay.offset = Vector2(0,4)

			else:
				var highlight_unit: Polygon2D = Polygon2D.new()					
				var unit_corners: PackedVector2Array = HexUtils.hex_top_corners(
					Vector2.ZERO, HexUtils.HEX_SIZE+1, HexUtils.TERRAIN_HEIGHT.get(HexUtils.TerrainType.GRASS, 4.0)
				)
				highlight_unit.polygon = PackedVector2Array(unit_corners)
		
				highlight_unit.color = Color(1.0, 1.0, 0.2, 0.4)
				highlight_unit.z_index = 1
				highlight_unit.offset = Vector2(0,4)
		
				tile.highlight_overlay = highlight_unit
				add_child(highlight_unit)
		_set_state(BattleState.SELECT_MOVE)
		
## 处理选择移动目标
func _handle_select_move(tile: HexTile) -> void:
	# 从全局鼠标位置计算轴向坐标，确保获取实际点击地块的坐标
	# （tile 参数可能来自场景中未初始化的 HexTile，axial_coord 始终为 ZERO）
	var mouse_pos: Vector2 = get_global_mouse_position()
	var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
	DebugLog.debug_nospam("func_call","_handle_select_move")
	
	HexGrids.clear_highlights()
	if tile.highlight_overlay != null:
		tile.highlight_overlay.color  = Color.TRANSPARENT
	# 点击攻击范围内的敌人
	var selected_unit:Unit = tile.occupying_unit
	var attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER)
	if clicked_coord in attackable_coords and not selected_unit.has_attacked:
		var target: Unit = tile.occupying_unit
		if target and target.team == Unit.Team.ENEMY:
			selected_unit.attack(target)
			
			# 检查是否还能行动
			if not selected_unit.can_act():
				_set_state(BattleState.SELECT_UNIT)
			else:
				# 重新显示可用范围
				_show_remaining_actions(selected_unit)
			return
	
	var reachable_tiles: Dictionary = HexGrids.get_reachable_tiles(selected_unit.grid_coord, selected_unit.move_range)

	# 点击可移动地块
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

			selected_unit.move_along_path(path)
			_set_state(BattleState.UNIT_MOVING)
			# 记录点击地块中心坐标，供移动完成后对比
			_debug_move_tile_center = HexUtils.axial_to_pixel(clicked_coord.x, clicked_coord.y)
			_debug_move_axial = clicked_coord
			# 避免重复连接信号（单位多次移动时会重复调用connect）
			if not selected_unit.unit_moved.is_connected(_on_unit_unit_moved):
				selected_unit.unit_moved.connect(_on_unit_unit_moved)
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
		var target: Unit = tile.occupying_unit
		if target and target.team == Unit.Team.ENEMY:
			selected_unit.attack(target)
			HexGrids.clear_highlights()
			if not selected_unit.can_act():
				_set_state(BattleState.SELECT_UNIT)
			else:
				_show_remaining_actions(selected_unit)
			return

	# 取消
	_set_state(BattleState.SELECT_UNIT)

## 显示剩余可用行动
func _show_remaining_actions(unit:Unit) -> void:
	HexGrids.clear_highlights()
	attackable_coords.clear()
	reachable_tiles.clear()
	selected_unit = unit
	# 选中高亮
	var tile: HexTile = HexGrids.get_tile(selected_unit.grid_coord)
	if tile:
		tile.highlight_type = HexTile.HighlightType.SELECTED

	if not selected_unit.has_moved:
		reachable_tiles = HexGrids.get_reachable_tiles(selected_unit.grid_coord, selected_unit.move_range)
		for coord in reachable_tiles:
			var t: HexTile = HexGrids.get_tile(coord)
			if t:
				t.highlight_type = HexTile.HighlightType.MOVE

	if not selected_unit.has_attacked:
		attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER)
		for coord in attackable_coords:
			var t: HexTile = HexGrids.get_tile(coord)
			if t:
				t.highlight_type = HexTile.HighlightType.ATTACK

	_set_state(BattleState.SELECT_MOVE)

## 设置状态
func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)
	#HexGrids.clear_highlights()
	# SELECT_FACING 状态需要保留 selected_unit（在调用处已设置）
	if state != BattleState.SELECT_FACING:
		selected_unit = null
	reachable_tiles.clear()
	attackable_coords.clear()

	# 根据状态更新UI提示
	match state:
		BattleState.SELECT_UNIT:
			_highlight_selectable_units()
		BattleState.SELECT_MOVE:
			pass
		BattleState.SELECT_ATTACK:
			pass
		BattleState.SELECT_FACING:
			# 显示朝向选择高亮（6个相邻方向）
			if selected_unit != null:
				_show_facing_options(selected_unit)


## 点击地块
func _on_hex_tile_tile_clicked(tile: HexTile) -> void:
	match state:
		BattleState.SELECT_UNIT:
			_handle_select_unit(tile)
		BattleState.SELECT_MOVE:
			_handle_select_move(tile)
		BattleState.SELECT_ATTACK:
			_handle_select_attack(tile)
		BattleState.SELECT_FACING:
			_handle_select_facing(tile)

## 单位行动完成回调
func _on_unit_action_finished(unit: Unit) -> void:
	pass # Replace with function body.

## 单位移动完成回调
func _on_unit_unit_moved(unit: Unit) -> void:
	if state == BattleState.UNIT_MOVING:
		# 打印点击地块中心坐标与移动后精灵中心坐标用于对比调试
		var sprite_center: Vector2 = unit.global_position
		DebugLog.debug_nospam("position_debug", "axial=%s 点击地块中心=%s 移动后精灵中心=%s 偏差=%s" % [str(_debug_move_axial), str(_debug_move_tile_center), str(sprite_center), str(sprite_center - _debug_move_tile_center)])
		# 移动完成后进入朝向选择状态
		# 先设置 selected_unit，再 _set_state 会触发 _show_facing_options
		selected_unit = unit
		_set_state(BattleState.SELECT_FACING)

## 显示朝向选择高亮（6个相邻方向）
func _show_facing_options(unit: Unit) -> void:
	HexGrids.clear_highlights()
	# 高亮当前单位所在地块
	var current_tile: HexTile = HexGrids.get_tile(unit.grid_coord)
	if current_tile:
		current_tile.highlight_type = HexTile.HighlightType.SELECTED
	# 高亮6个相邻方向供玩家点击选择朝向
	for dir in HexUtils.HEX_DIRECTIONS:
		var neighbor_coord: Vector2i = unit.grid_coord + dir
		var t: HexTile = HexGrids.get_tile(neighbor_coord)
		if t:
			t.highlight_type = HexTile.HighlightType.MOVE

## 处理选择朝向
func _handle_select_facing(tile: HexTile) -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var clicked_coord: Vector2i = HexUtils.pixel_to_axial(mouse_pos.x, mouse_pos.y)
	DebugLog.debug_nospam("func_call","_handle_select_facing")
	if selected_unit == null:
		_set_state(BattleState.SELECT_UNIT)
		return

	# 点击自身地块：保持当前朝向，跳过朝向选择
	if clicked_coord == selected_unit.grid_coord:
		_show_remaining_actions(selected_unit)
		return

	# 点击相邻地块：设置朝向并继续
	var diff: Vector2i = clicked_coord - selected_unit.grid_coord
	if diff in HexUtils.HEX_DIRECTIONS:
		selected_unit.set_facing_from_coord(diff)
	_show_remaining_actions(selected_unit)

## 单位死亡回调
func _on_unit_unit_died(unit: Unit) -> void:
	pass # Replace with function body.
