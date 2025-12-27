extends Node2D
class_name HomingProjectile

@export var speed: float = 420.0
@export var hit_distance: float = 10.0
@export var max_lifetime: float = 6.0

var _target: Node2D = null
var _damage: int = 0
var _source: Node2D = null
var _hit: bool = false
var _life: float = 0.0

func setup(target: Node2D, damage: int, source: Node2D = null) -> void:
	_target = target
	_damage = damage
	_source = source

func _physics_process(delta: float) -> void:
	if _hit:
		return

	_life += delta
	if _life >= max_lifetime:
		queue_free()
		return

	# Если цель пропала — удаляем снаряд
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	# Если источник нужен тебе как “контроль жизни снаряда” — оставляем.
	# Если моб умер и его удалили — снаряд тоже исчезнет, чтобы не было мусора.
	if _source != null and not is_instance_valid(_source):
		queue_free()
		return

	# Если игрок уже мёртв — не продолжаем
	if "is_dead" in _target and bool(_target.get("is_dead")):
		queue_free()
		return

	# Движение: каждый кадр летим прямо к текущей позиции игрока (100% попадание)
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()

	if dist <= hit_distance:
		_apply_hit()
		return

	var dir: Vector2 = to_target / dist
	global_position += dir * speed * delta

func _apply_hit() -> void:
	if _hit:
		return
	_hit = true

	if _target != null and is_instance_valid(_target):
		if "is_dead" in _target and bool(_target.get("is_dead")):
			queue_free()
			return

		if _target.has_method("take_damage"):
			_target.call("take_damage", _damage)

	queue_free()
