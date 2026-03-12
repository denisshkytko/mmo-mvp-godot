extends Node2D
class_name HunterMagicShotProjectile

signal impacted(target: Node2D)

@export var speed: float = 520.0
@export var hit_distance: float = 10.0
@export var max_lifetime: float = 4.0

var _target: Node2D = null
var _source: Node2D = null
var _life: float = 0.0
var _done: bool = false

func setup(target: Node2D, source: Node2D = null) -> void:
	_target = target
	_source = source

func _physics_process(delta: float) -> void:
	if _done:
		return

	_life += delta
	if _life >= max_lifetime:
		queue_free()
		return

	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist <= hit_distance:
		_done = true
		impacted.emit(_target)
		queue_free()
		return

	var dir: Vector2 = to_target / dist
	rotation = dir.angle()
	global_position += dir * speed * delta
