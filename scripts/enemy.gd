extends CharacterBody2D
## 敌人 - AI状态机、战斗、掉落

signal enemy_died(enemy: CharacterBody2D, exp_reward: int)

enum State { IDLE, PATROL, CHASE, ATTACK }

@export var max_health: float = 60.0
@export var move_speed: float = 80.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 40.0
@export var detection_range: float = 300.0
@export var attack_cooldown: float = 1.0
@export var exp_reward: int = 25
@export var is_boss: bool = false

var health: float
var state: State = State.IDLE
var player: Node2D = null
var patrol_origin: Vector2
var patrol_target: Vector2
var patrol_timer: float = 0.0
var attack_timer: float = 0.0

@onready var body_rect: ColorRect = $BodySprite
@onready var hp_bar: ProgressBar = $HealthBar

var utils: Node


func _ready() -> void:
	health = max_health
	patrol_origin = global_position
	patrol_target = global_position
	patrol_timer = randf_range(1.0, 3.0)
	add_to_group("enemy")
	utils = get_node_or_null("/root/Utils")

	# 检测区域信号
	var detection_area := $DetectionArea as Area2D
	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)


func _physics_process(delta: float) -> void:
	if health <= 0:
		return

	attack_timer = max(attack_timer - delta, 0.0)

	# 自动检测玩家
	if not player or not is_instance_valid(player):
		player = _find_nearest_player()
		if not player:
			state = State.IDLE

	_update_state(delta)
	move_and_slide()


func _find_nearest_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p.global_position.distance_to(global_position) < detection_range:
			return p
	return null


func _update_state(delta: float) -> void:
	var dist_to_player := 9999.0
	if player and is_instance_valid(player):
		dist_to_player = global_position.distance_to(player.global_position)

	match state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
			patrol_timer -= delta
			if patrol_timer <= 0:
				state = State.PATROL
				var angle := randf() * TAU
				var distance := randf_range(50, 150)
				patrol_target = patrol_origin + Vector2(cos(angle), sin(angle)) * distance
			if dist_to_player < detection_range:
				state = State.CHASE

		State.PATROL:
			var dir := (patrol_target - global_position).normalized()
			velocity = dir * move_speed * 0.5
			if global_position.distance_to(patrol_target) < 10:
				state = State.IDLE
				patrol_timer = randf_range(1.0, 3.0)
			if dist_to_player < detection_range:
				state = State.CHASE

		State.CHASE:
			if not player or not is_instance_valid(player):
				state = State.IDLE
				player = null
				return
			if dist_to_player > detection_range * 1.5:
				state = State.IDLE
				patrol_origin = global_position
				player = null
				return
			if dist_to_player <= attack_range:
				state = State.ATTACK
				velocity = Vector2.ZERO
				return
			var dir := (player.global_position - global_position).normalized()
			velocity = dir * move_speed

		State.ATTACK:
			velocity = Vector2.ZERO
			if not player or not is_instance_valid(player):
				state = State.IDLE
				player = null
				return
			if dist_to_player > attack_range * 1.5:
				state = State.CHASE
				return
			if attack_timer <= 0:
				if player.has_method("take_damage"):
					player.take_damage(attack_damage)
				attack_timer = attack_cooldown


func _on_detection_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player = body
		state = State.CHASE


func _on_detection_body_exited(body: Node2D) -> void:
	if body == player:
		player = null
		state = State.IDLE


# ==================== 受伤与死亡 ====================

func take_damage(amount: float, attacker_pos: Vector2) -> void:
	if health <= 0:
		return

	health -= amount
	hp_bar.value = (health / max_health) * 100

	# 受击闪红


func _die() -> void:
	# 死亡特效
	if utils:
		utils.spawn_circle_effect(get_parent(), global_position, 25, Color(0.5, 0.0, 0.5, 0.6), 0.5, 2.0, 5)

	# 掉落物品
	_spawn_loot()

	# 通知玩家获取经验
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("gain_exp"):
			p.gain_exp(exp_reward)

	enemy_died.emit(self, exp_reward)
	queue_free()


# ==================== 掉落 ====================

func _spawn_loot() -> void:
	if randf() > 0.6:
		return

	var loot := Area2D.new()
	loot.collision_mask = 1  # Player layer
	loot.monitoring = true
	loot.monitorable = false

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	collision.shape = shape
	loot.add_child(collision)

	var loot_type := randi() % 3
	var loot_color: Color
	var loot_name: String

	match loot_type:
		0:
			loot_color = Color(1.0, 0.8, 0.0, 0.9)
			loot_name = "gold"
		1:
			loot_color = Color(0.0, 1.0, 0.3, 0.9)
			loot_name = "potion"
		2:
			loot_color = Color(0.5, 0.3, 1.0, 0.9)
			loot_name = "equipment"

	if utils:
		var sprite := Sprite2D.new()
		sprite.texture = utils.get_circle_texture(8, loot_color)
		loot.add_child(sprite)

	loot.position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	get_parent().add_child(loot)

	# 拾取
	loot.body_entered.connect(func(body):
		if body.is_in_group("player"):
			match loot_name:
				"gold":
					if body.has_method("gain_exp"):
						body.gain_exp(5)
				"potion":
					if body.has_method("heal"):
						body.heal(20)
				"equipment":
					if body.has_method("gain_exp"):
						body.gain_exp(15)
			loot.queue_free()
	)

	# 闪烁效果
	if loot.get_child_count() > 1:
		var sprite: Sprite2D = loot.get_child(1)
		var glow_tween := create_tween().set_loops()
		glow_tween.tween_property(sprite, "modulate:a", 0.5, 0.5)
		glow_tween.tween_property(sprite, "modulate:a", 1.0, 0.5)

	# 30秒后消失
	get_tree().create_timer(30.0).timeout.connect(loot.queue_free)
