class_name Unit
extends CharacterBody2D
## 玩家角色 - 移动、攻击、技能、生命/法力管理

signal health_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal player_died
signal level_up(new_level: int)
signal skill_used(slot: int)
signal action_finished(unit: Unit)
signal unit_moved(unit: Unit)
signal unit_attacked(unit: Unit, target: Unit)
signal unit_died(unit: Unit)


# 引用
# 注意：Player/Enemy 场景将 Unit 作为子节点实例化，因此 @onready 需要在子节点中查找
@onready var attack_area: Area2D = get_node_or_null("AttackArea")
@onready var attack_collision: CollisionShape2D = get_node_or_null("AttackArea/AttackCollision")
@onready var camera: Camera2D = get_node_or_null("Camera2D")
# AnimatedSprite2D 挂在父节点 Player/Enemy 上，作为同级节点查找
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("../AnimatedSprite2D")

## 队伍枚举
enum Team { PLAYER, ENEMY }

signal tile_clicked(tile: HexTile)

# 属性
## 单位名称
@export var unit_name: String = ""
@export var max_health: float = 100.0
@export var max_mana: float = 50.0
@export var move_speed: float = 200.0
@export var move_range: float = 5.0
@export var attack_damage: float = 25.0
@export var attack_range: float = 6.0
@export var attack_cooldown: float = 0.5
@export var armor_class: float = 20.0
## 所属队伍
@export var team: Team = Team.PLAYER

# ==================== 命中判定系统属性 ====================
## 技巧（决定基础命中，典型50~90）
@export var technique: float = 70.0
## 敏捷（决定基础闪避，典型0~40）
@export var agility: float = 20.0
## 武器命中修正（-10~+30）
@export var weapon_hit_modifier: float = 0.0
## 熟练加值（使用熟练武器时获得，+10~+20）
@export var proficiency_bonus: float = 10.0
## 是否熟练使用当前武器
@export var is_proficient: bool = true
## 护甲闪避惩罚（重甲为负值，-20~0）
@export var armor_dodge_penalty: float = 0.0

## 状态命中修正（key: 状态名, value: 命中修正值，如"精准"+15、"目盲"-30）
var status_hit_modifiers: Dictionary = {}
## 状态闪避修正（key: 状态名, value: 闪避修正值，如"迟缓"-15）
var status_dodge_modifiers: Dictionary = {}

## 命中率下限（总有失手可能）
const HIT_CHANCE_MIN: float = 5.0
## 命中率上限（总有命中可能）
const HIT_CHANCE_MAX: float = 95.0

var health: float
var mana: float
var is_attacking: bool = false
var attack_timer: float = 0.0
var facing_direction: Vector2 = Vector2.DOWN

## 本回合是否已移动
var has_moved: bool = false
## 移动动画相关
var _is_moving: bool = false
var _move_path: Array[Vector2i] = []
var _move_index: int = 0
var _move_speed: float = 200.0

## 本回合是否已攻击
var has_attacked: bool = false

var is_dead: bool = false
var invincible_timer: float = 0.0
var exp_points: int = 0
var level: int = 1
## 当前所在坐标
var grid_coord: Vector2i = Vector2i.ZERO

# 技能
var skill_cooldowns: Dictionary = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}
var skill_max_cooldowns: Dictionary = {1: 3.0, 2: 5.0, 3: 8.0, 4: 12.0}
var skill_mana_costs: Dictionary = {1: 10.0, 2: 15.0, 3: 20.0, 4: 25.0}

var utils: Node  # Utils单例引用


func _ready() -> void:
	health = max_health
	mana = max_mana
	if attack_collision:
		attack_collision.disabled = true
	# 根据队伍添加到对应分组
	if team == Team.PLAYER:
		add_to_group("player")
	elif team == Team.ENEMY:
		add_to_group("enemy")
	# 获取工具单例
	utils = get_node_or_null("/root/Utils")
	# 同步父节点（Player/Enemy）位置到地块中心
	# 场景中 Player 的初始 position 是手动设置的偏移值，与 grid_coord 对应的
	# 地块中心不一致，移动后会跳到正确位置造成视觉偏差
	_sync_position_to_tile()

## 同步父节点（Player/Enemy）的全局位置到 grid_coord 对应的地块中心
## AnimatedSprite2D 的 position 偏移（如 (0,-11)）是视觉调整，使精灵
## 看起来"站在"地块上，不需要补偿——移动时也使用同样的地块中心坐标
func _sync_position_to_tile() -> void:
	var move_node: Node2D = get_parent() if get_parent() is Node2D else self
	var tile_center: Vector2 = HexUtils.axial_to_pixel(grid_coord.x, grid_coord.y)
	move_node.global_position = tile_center


## 设置单位属性
func setup(data: Dictionary) -> void:
	unit_name = data.get("name", unit_name)
	team = data.get("team", team)
	max_health = data.get("max_hp", max_health)
	health = max_health
	attack_damage = data.get("attack", attack_damage)
	armor_class = data.get("defense", armor_class)
	move_range = data.get("move_range", move_range)
	attack_range = data.get("attack_range", attack_range)
	grid_coord = data.get("coord", Vector2i.ZERO)
	#_update_visual()
	#var unit: Unit = Unit.new()
	#unit.unit_died.connect(_on_unit_died.bind(unit))
	#unit.unit_moved.connect(_on_unity)
	#unit.action_finished.connect(_on_action_finished)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_timers(delta)
	_handle_movement()
	_handle_input()
	_update_attack_area_position()
	_regen_mana(delta)


func _update_timers(delta: float) -> void:
	if attack_timer > 0:
		attack_timer -= delta
	if invincible_timer > 0:
		invincible_timer -= delta
	for slot in skill_cooldowns:
		if skill_cooldowns[slot] > 0:
			skill_cooldowns[slot] -= delta


func _handle_movement() -> void:
	if not _is_moving:
		return

	# 视觉表现（AnimatedSprite2D）挂在父节点 Player 上，
	# 因此需要移动父节点 Player 而非 Unit 自身，使精灵与逻辑节点一起移动
	var move_node: Node2D = get_parent() if get_parent() is Node2D else self

	# 沿路径逐点移动
	if _move_index >= _move_path.size():
		# 路径走完，结束移动
		_is_moving = false
		_move_path.clear()
		_move_index = 0
		has_moved = true
		# 切回待机动画
		if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")
		unit_moved.emit(self)
		return

	# 当前目标点的像素坐标（世界坐标）
	var target_coord: Vector2i = _move_path[_move_index]
	var target_pos: Vector2 = HexUtils.axial_to_pixel(target_coord.x, target_coord.y)
	# 朝目标移动（使用 global_position 确保世界坐标一致）
	var direction: Vector2 = (target_pos - move_node.global_position).normalized()
	# 根据移动方向水平分量翻转 run 动画
	_update_sprite_flip(direction)
	var step: float = _move_speed * get_physics_process_delta_time()

	if move_node.global_position.distance_to(target_pos) <= step:
		# 到达当前路径点
		move_node.global_position = target_pos
		grid_coord = target_coord
		_move_index += 1
		# 若已走完所有路径点，下一帧会进入上面的完成分支
	else:
		move_node.global_position += direction * step


func _handle_input() -> void:
	if Input.is_action_just_pressed("attack") and attack_timer <= 0 and not is_attacking:
		perform_attack()

	for slot in range(1, 5):
		if Input.is_action_just_pressed("skill_" + str(slot)):
			use_skill(slot)

	if Input.is_action_just_pressed("health_potion"):
		use_potion()


func _update_attack_area_position() -> void:
	if attack_collision:
		attack_collision.position = facing_direction * attack_range


func _regen_mana(delta: float) -> void:
	mana = min(mana + 3.0 * delta, max_mana)
	mana_changed.emit(mana, max_mana)


# ==================== 攻击 ====================

func perform_attack() -> void:
	is_attacking = true
	attack_timer = attack_cooldown
	if attack_collision:
		attack_collision.disabled = false

	# 攻击特效
	if utils:
		utils.spawn_circle_effect(get_parent(), global_position + facing_direction * attack_range, 25, Color(1.0, 0.8, 0.2, 0.6), 0.2, 1.5, 10)

	# 检测命中
	await get_tree().create_timer(0.05).timeout
	if attack_area:
		var bodies := attack_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("enemy") and body.has_method("take_damage"):
				body.take_damage(attack_damage, global_position)

	await get_tree().create_timer(0.15).timeout
	is_attacking = false
	if attack_collision:
		attack_collision.disabled = true


# ==================== 命中判定系统 ====================

## 计算攻击方命中值
## 命中值 = 基础命中(技巧) + 武器修正 + 熟练加值 + 地形修正 + 状态修正
func calculate_hit_value() -> float:
	var hit: float = technique + weapon_hit_modifier
	if is_proficient:
		hit += proficiency_bonus
	hit += _get_terrain_hit_modifier()
	for mod in status_hit_modifiers.values():
		hit += mod
	return hit

## 计算防御方闪避值
## 闪避值 = 基础闪避(敏捷) + 护甲惩罚 + 地形修正 + 状态修正
func calculate_dodge_value() -> float:
	var dodge: float = agility + armor_dodge_penalty
	dodge += _get_terrain_dodge_modifier()
	for mod in status_dodge_modifiers.values():
		dodge += mod
	return dodge

## 获取地形命中修正（高地打低地+10，反之-10）
## 此处以单位所处地块的地形高度作为"高地"判定依据
func _get_terrain_hit_modifier() -> float:
	var my_tile: HexTile = HexGrids.get_tile(grid_coord)
	if my_tile == null:
		return 0.0
	# 地形高度较高视为高地，获得命中加成
	match my_tile.terrain:
		HexUtils.TerrainType.FOREST:
			return 10.0
		_:
			return 0.0

## 获取地形闪避修正（树林、掩体等提供闪避）
func _get_terrain_dodge_modifier() -> float:
	var my_tile: HexTile = HexGrids.get_tile(grid_coord)
	if my_tile == null:
		return 0.0
	match my_tile.terrain:
		HexUtils.TerrainType.FOREST:
			return 15.0
		_:
			return 0.0

## 计算对目标的最终命中率（百分比，限制在5~95之间）
## 命中率 = 攻击方命中值 - 防御方闪避值
func calculate_hit_chance(target: Unit) -> float:
	var hit_value: float = calculate_hit_value()
	var dodge_value: float = target.calculate_dodge_value()
	var chance: float = hit_value - dodge_value
	return clampf(chance, HIT_CHANCE_MIN, HIT_CHANCE_MAX)

## 投百分骰（1d100）判定是否命中
## 投骰 <= 命中率 则命中
func roll_hit(target: Unit) -> bool:
	var chance: float = calculate_hit_chance(target)
	var roll: int = randi_range(1, 100)
	var hit: bool = roll <= int(round(chance))
	DebugLog.debug_nospam("hit_roll", "命中率=%d 投骰=%d 命中=%s" % [int(round(chance)), roll, str(hit)])
	return hit

## 添加状态命中修正（如"精准"+15、"目盲"-30）
func add_status_hit_modifier(status_name: String, modifier: float) -> void:
	status_hit_modifiers[status_name] = modifier

## 移除状态命中修正
func remove_status_hit_modifier(status_name: String) -> void:
	status_hit_modifiers.erase(status_name)

## 添加状态闪避修正（如"迟缓"-15）
func add_status_dodge_modifier(status_name: String, modifier: float) -> void:
	status_dodge_modifiers[status_name] = modifier

## 移除状态闪避修正
func remove_status_dodge_modifier(status_name: String) -> void:
	status_dodge_modifiers.erase(status_name)

## 攻击目标（回合制）
## 先进行命中判定，命中则造成伤害
func attack(target: Unit) -> void:
	if is_dead or target == null or target.is_dead:
		return
	has_attacked = true
	# 命中判定
	if not roll_hit(target):
		# 未命中，显示 MISS
		DebugLog.debug_nospam("attack", "攻击未命中！")
		if utils:
			utils.spawn_damage_number(get_parent(), 0, target.global_position, Color.GRAY)
		unit_attacked.emit(self, target)
		return
	# 命中，造成伤害
	target.take_damage(attack_damage)
	unit_attacked.emit(self, target)


# ==================== 受伤与死亡 ====================

func take_damage(amount: float) -> void:
	if invincible_timer > 0 or is_dead:
		return

	health -= amount
	invincible_timer = 0.3

	# 受击闪烁
	for child in get_children():
		if child is ColorRect:
			var orig_color: Color = child.color
			var tween := create_tween()
			tween.tween_property(child, "color", Color(1, 0.3, 0.3), 0.1)
			tween.tween_property(child, "color", orig_color, 0.1)

	# 伤害数字
	if utils:
		utils.spawn_damage_number(get_parent(), amount, global_position, Color.RED)
		utils.screen_shake(camera, 5.0)

	health_changed.emit(health, max_health)

	if health <= 0:
		health = 0
		_die()


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	player_died.emit()

	# 死亡画面
	var overlay := ColorRect.new()
	overlay.size = Vector2(1280, 720)
	overlay.color = Color(0, 0, 0, 0)
	overlay.z_index = 1000
	get_parent().add_child(overlay)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.8, 2.0)

	var label := Label.new()
	label.text = "YOU DIED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	label.add_theme_font_size_override("font_size", 72)
	label.position = Vector2(440, 300)
	label.z_index = 1001
	label.modulate.a = 0.0
	get_parent().add_child(label)

	var label_tween := create_tween()
	label_tween.tween_property(label, "modulate:a", 1.0, 2.0)


# ==================== 技能系统 ====================

func use_skill(slot: int) -> void:
	if skill_cooldowns[slot] > 0:
		return
	if mana < skill_mana_costs[slot]:
		return

	mana -= skill_mana_costs[slot]
	skill_cooldowns[slot] = skill_max_cooldowns[slot]
	skill_used.emit(slot)
	mana_changed.emit(mana, max_mana)

	match slot:
		1: _skill_whirlwind()
		2: _skill_fireball()
		3: _skill_ground_slam()
		4: _skill_shadow_dash()


func _skill_whirlwind() -> void:
	# 旋风斩 - 周围80范围AOE
	if utils:
		var effect := Sprite2D.new()
		effect.texture = utils.get_circle_texture(80, Color(0.5, 0.8, 1.0, 0.5))
		effect.position = global_position
		effect.z_index = 10
		get_parent().add_child(effect)
		var tween := create_tween()
		tween.tween_property(effect, "rotation", PI * 4, 0.8)
		tween.parallel().tween_property(effect, "scale", Vector2(1.5, 1.5), 0.8)
		tween.parallel().tween_property(effect, "modulate:a", 0.0, 0.8)
		tween.tween_callback(effect.queue_free)

	# 伤害范围内敌人
	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(global_position) <= 80:
			enemy.take_damage(attack_damage * 1.5, global_position)


func _skill_fireball() -> void:
	# 火球术 - 向面朝方向发射
	var fireball := Area2D.new()
	fireball.collision_mask = 2
	fireball.monitoring = true
	fireball.monitorable = false

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 15.0
	collision.shape = shape
	fireball.add_child(collision)

	if utils:
		var sprite := Sprite2D.new()
		sprite.texture = utils.get_circle_texture(15, Color(1.0, 0.3, 0.0, 0.9))
		fireball.add_child(sprite)

		var light := PointLight2D.new()
		light.color = Color(1.0, 0.5, 0.0)
		light.energy = 2.0
		light.texture = utils.get_light_texture()
		fireball.add_child(light)

	fireball.position = global_position
	get_parent().add_child(fireball)

	var direction := facing_direction
	var speed := 400.0
	var damage := attack_damage * 2.0
	var lifetime := 3.0

	fireball.body_entered.connect(func(body):
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(damage, global_position)
		if utils:
			utils.spawn_circle_effect(get_parent(), fireball.global_position, 30, Color(1.0, 0.5, 0.0, 0.8), 0.3, 2.5, 10)
		fireball.queue_free()
	)

	var target_pos := fireball.position + direction * speed * lifetime
	var move_tween := create_tween()
	move_tween.tween_property(fireball, "position", target_pos, lifetime)
	move_tween.tween_callback(fireball.queue_free)


func _skill_ground_slam() -> void:
	# 地裂击 - 前方120范围AOE
	var center := global_position + facing_direction * 60

	if utils:
		utils.spawn_circle_effect(get_parent(), center, 120, Color(0.6, 0.3, 0.1, 0.7), 0.3, 1.3, 5)
		utils.screen_shake(camera, 8.0)

	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(center) <= 120:
			enemy.take_damage(attack_damage * 2.5, global_position)


func _skill_shadow_dash() -> void:
	# 暗影冲刺 - 快速移动
	var dash_distance := 200.0
	var start_pos := global_position

	# 残影
	if utils:
		for i in range(5):
			var afterimage := Sprite2D.new()
			afterimage.texture = utils.get_circle_texture(16, Color(0.3, 0.1, 0.5, 0.5))
			afterimage.position = start_pos + facing_direction * dash_distance * (float(i) / 5.0)
			afterimage.z_index = 5
			get_parent().add_child(afterimage)
			var t := create_tween()
			t.tween_property(afterimage, "modulate:a", 0.0, 0.5)
			t.tween_callback(afterimage.queue_free)

	invincible_timer = 0.3
	var dash_tween := create_tween()
	dash_tween.tween_property(self, "global_position", start_pos + facing_direction * dash_distance, 0.15)


# ==================== 药水 ====================

func use_potion() -> void:
	if health >= max_health:
		return
	health = min(health + max_health * 0.3, max_health)
	health_changed.emit(health, max_health)

	if utils:
		var heal := Sprite2D.new()
		heal.texture = utils.get_circle_texture(20, Color(0.0, 1.0, 0.3, 0.6))
		heal.position = global_position
		heal.z_index = 10
		get_parent().add_child(heal)
		var tween := create_tween()
		tween.tween_property(heal, "position:y", heal.position.y - 40, 0.8)
		tween.parallel().tween_property(heal, "modulate:a", 0.0, 0.8)
		tween.tween_callback(heal.queue_free)


# ==================== 经验与升级 ====================

func gain_exp(amount: int) -> void:
	exp_points += amount
	var exp_to_level := level * 100
	while exp_points >= exp_to_level:
		exp_points -= exp_to_level
		level += 1
		max_health += 10
		max_mana += 5
		attack_damage += 3
		health = max_health
		mana = max_mana
		level_up.emit(level)
		_level_up_effect()
		exp_to_level = level * 100


func _level_up_effect() -> void:
	if utils:
		utils.spawn_circle_effect(get_parent(), global_position, 40, Color(1.0, 1.0, 0.5, 0.8), 0.6, 3.0, 20)
		utils.spawn_damage_number(get_parent(), 0, global_position, Color.GOLD)

	var label := Label.new()
	label.text = "LEVEL UP!"
	label.position = global_position + Vector2(-30, -50)
	label.z_index = 100
	label.add_theme_color_override("font_color", Color.GOLD)
	label.add_theme_font_size_override("font_size", 24)
	get_parent().add_child(label)
	var t := create_tween()
	t.tween_property(label, "position:y", label.position.y - 60, 1.0)
	t.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	t.tween_callback(label.queue_free)


# ==================== 治疗接口（供掉落物使用）====================

func heal(amount: float) -> void:
	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)
	
## 是否可以行动
func can_act() -> bool:
	return not is_dead and (not has_moved or not has_attacked)

## 根据轴向坐标偏移设置朝向（共6个方向）
## diff 为目标地块与当前地块的轴向坐标差
func set_facing_from_coord(diff: Vector2i) -> void:
	# 将六边形轴向偏移转换为像素方向向量
	var target_pixel: Vector2 = HexUtils.axial_to_pixel(diff.x, diff.y)
	if target_pixel != Vector2.ZERO:
		facing_direction = target_pixel.normalized()
	# 根据朝向更新 idle 动画方向
	_update_sprite_flip(facing_direction)
	DebugLog.debug_nospam("update_visual", "朝向已设置: %s" % str(facing_direction))

## 根据方向向量更新精灵水平翻转
## direction.x < 0 朝左翻转；direction.x > 0 朝右不翻转；垂直方向保持当前翻转
func _update_sprite_flip(direction: Vector2) -> void:
	if animated_sprite == null:
		return
	# 仅在水平分量明显时翻转，避免垂直移动时频繁抖动
	if direction.x < -0.1:
		animated_sprite.flip_h = true
	elif direction.x > 0.1:
		animated_sprite.flip_h = false
	
## 移动到目标位置（沿路径）
func move_along_path(path: Array[Vector2i]) -> void:
	if path.is_empty() or has_moved or is_dead:
		action_finished.emit(self)
		return
	_move_path = path
	_move_index = 0
	_is_moving = true
	# 切换为跑步动画
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("run"):
		animated_sprite.play("run")


func _on_hex_tile_tile_clicked(tile: HexTile) -> void:
	var curPos = Vector2(position.x, position.y)
	tile.occupying_unit = self
