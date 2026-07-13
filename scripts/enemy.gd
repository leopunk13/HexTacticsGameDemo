extends Unit
class_name Enemy

func _ready() -> void:
	team = Team.ENEMY
	super._ready()
