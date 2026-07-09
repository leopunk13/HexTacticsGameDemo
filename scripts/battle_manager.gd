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

## 选中单位时显示的朝向指示器（带箭头的圆环）
var _facing_indicator: Node2D = null

## 初始化战斗
func setup_battle(cam: CameraController, hud_node: CanvasLayer) -> void:
	camera = cam
	hud = hud_node
	# 连接 Autoload HexGrids 的 tile_clicked 信号
	if not HexGrids.tile_clicked.is_connected(_on_hex_tile_tile_clicked):
		HexGrids.tile_clicked.connect(_on_hex_tile_tile_clicked)
	# 注册场景中的玩家单位到战斗管理器与地块
	_register_units()

## 在选中单位下方创建带箭头的圆环，箭头指向 facing_direction
func _create_facing_indicator(unit: Unit) -> void:
	_clear_facing_indicator()
	var indicator: Node2D = Node2D.new()
	indicator.name = "FacingIndicator"
	# 圆环
	var ring: Polygon2D = Polygon2D.new()
	var ring_radius: float = 28.0
	var seg_count: int = 24
	var ring_points: PackedVector2Array = arc(ring_radius*0.6,ring_radius*0.7,seg_count)

	ring.polygon = ring_points
	ring.color = Color(1.0, 1.0, 0.2, 0.3)
	ring.z_index = 2
	indicator.add_child(ring)
	# 箭头（三角形），指向 facing_direction
	var arrow: Polygon2D = Polygon2D.new()
	var arrow_points: PackedVector2Array = PackedVector2Array()
	var arrow_dist: float = ring_radius*0.85
	var arrow_size: float = 5.0
	# 箭头朝向 facing_direction（默认朝右）
	arrow_points.append(Vector2(arrow_dist + arrow_size, 0))   # 尖端
	arrow_points.append(Vector2(arrow_dist - arrow_size, -arrow_size)) # 左下
	arrow_points.append(Vector2(arrow_dist - arrow_size, arrow_size))  # 右下
	arrow.polygon = arrow_points
	arrow.color = Color(1.0, 1.0, 0.2, 0.3)
	arrow.z_index = 3
	indicator.add_child(arrow)
	# 根据朝向旋转指示器
	var angle: float = facing_angle_from_direction(unit.facing_direction)
	indicator.rotation = angle
	# 挂载到单位父节点（Player/Enemy）下方，跟随移动
	var attach_to: Node2D = unit.get_parent() if unit.get_parent() is Node2D else unit
	attach_to.add_child(indicator)
	_facing_indicator = indicator

## 清除朝向指示器
func _clear_facing_indicator() -> void:
	if _facing_indicator != null and is_instance_valid(_facing_indicator):
		_facing_indicator.queue_free()
	_facing_indicator = null

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
		# 在选中单位下方显示朝向指示器（带箭头的圆环）
		_create_facing_indicator(selected_unit)
		
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
	
	# 使用类成员 selected_unit（在 _handle_select_unit 中设置），而非 tile.occupying_unit
	# 因为 tile 是点击的移动目标地块，其上没有单位
	if selected_unit == null:
		_set_state(BattleState.SELECT_UNIT)
		return
	
	HexGrids.clear_highlights()
	if tile.highlight_overlay != null:
		tile.highlight_overlay.color  = Color.TRANSPARENT
	# 点击攻击范围内的敌人
	var attackable_coords = HexGrids.get_attackable_tiles(selected_unit.grid_coord, selected_unit.attack_range, Unit.Team.PLAYER)
	if clicked_coord in attackable_coords and not selected_unit.has_attacked:
		var target_tile: HexTile = HexGrids.get_tile(clicked_coord)
		var target: Unit = target_tile.occupying_unit if target_tile else null
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
	# 在需要选中单位的状态（选择移动/攻击/朝向）中保留 selected_unit
	# 仅在回到 SELECT_UNIT 等非选择状态时清除，以便重新选择
	if state not in [BattleState.SELECT_MOVE, BattleState.SELECT_ATTACK, BattleState.SELECT_FACING]:
		selected_unit = null
	# 离开选中/朝向状态时清除朝向指示器
	if state != BattleState.SELECT_UNIT and state != BattleState.SELECT_FACING and state != BattleState.SELECT_MOVE:
		_clear_facing_indicator()
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

## 显示朝向选择高亮（6个相邻方向，白色）
func _show_facing_options(unit: Unit) -> void:
	HexGrids.clear_highlights()
	# 高亮当前单位所在地块
	var current_tile: HexTile = HexGrids.get_tile(unit.grid_coord)
	if current_tile:
		current_tile.highlight_type = HexTile.HighlightType.SELECTED
		# 在选中单位下方显示朝向指示器（带箭头的圆环）
		_create_facing_indicator(unit)
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
		_set_state(BattleState.SELECT_UNIT)
		return

	# 点击自身地块：保持当前朝向，跳过朝向选择
	if clicked_coord == selected_unit.grid_coord:
		_flash_selected_facing_tile(clicked_coord)
		_show_remaining_actions(selected_unit)
		return

	# 点击相邻地块：设置朝向并继续
	var diff: Vector2i = clicked_coord - selected_unit.grid_coord
	if diff in HexUtils.HEX_DIRECTIONS:
		selected_unit.set_facing_from_coord(diff)
		# 选中地块闪烁
		_flash_selected_facing_tile(clicked_coord)
		# 更新朝向指示器旋转
		if _facing_indicator != null and is_instance_valid(_facing_indicator):
			_facing_indicator.rotation = facing_angle_from_direction(selected_unit.facing_direction)
	_show_remaining_actions(selected_unit)

## 单位死亡回调
func _on_unit_unit_died(unit: Unit) -> void:
	pass # Replace with function body.
