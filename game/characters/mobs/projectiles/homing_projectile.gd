extends Node2D
class_name HomingProjectile

signal impacted(target: Node2D)
signal impacted_with_result(target: Node2D, dealt_damage: int, dmg_type: String)

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")

@export var speed: float = 420.0
@export var hit_distance: float = 10.0
@export var max_lifetime: float = 6.0
@export var default_visual_scale: Vector2 = Vector2(0.2, 0.2)
@export var directional_animation: bool = false

var _target: Node2D = null
var _damage: int = 0
var _source: Node2D = null
var _hit: bool = false
var _life: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D as Sprite2D
@onready var _animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

func setup(target: Node2D, damage: int, source: Node2D = null, texture_override: Texture2D = null) -> void:
	_target = target
	_damage = damage
	_source = source
	_sync_sort_layer()
	if _sprite != null:
		_sprite.scale = default_visual_scale
	if _animated_sprite != null:
		_animated_sprite.scale = default_visual_scale
		if _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(StringName("dir_right")):
			_animated_sprite.play("dir_right")
		elif _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(StringName("default")):
			_animated_sprite.play("default")
	if texture_override != null and _sprite != null:
		_sprite.texture = texture_override

func _physics_process(delta: float) -> void:
	var t_total := Time.get_ticks_usec()
	if _hit:
		FRAME_PROFILER.add_usec("projectile.homing.physics.total", Time.get_ticks_usec() - t_total)
		return
	var t_sync := Time.get_ticks_usec()
	_sync_sort_layer()
	FRAME_PROFILER.add_usec("projectile.homing.physics.sync_layer", Time.get_ticks_usec() - t_sync)

	_life += delta
	if _life >= max_lifetime:
		queue_free()
		FRAME_PROFILER.add_usec("projectile.homing.physics.total", Time.get_ticks_usec() - t_total)
		return

	# Если цель пропала — удаляем снаряд
	if _target == null or not is_instance_valid(_target):
		queue_free()
		FRAME_PROFILER.add_usec("projectile.homing.physics.total", Time.get_ticks_usec() - t_total)
		return

	# Если источник нужен тебе как “контроль жизни снаряда” — оставляем.
	# Если моб умер и его удалили — снаряд тоже исчезнет, чтобы не было мусора.
	if _source != null and not is_instance_valid(_source):
		_source = null

	# Если игрок уже мёртв — не продолжаем
	if "is_dead" in _target and bool(_target.get("is_dead")):
		queue_free()
		FRAME_PROFILER.add_usec("projectile.homing.physics.total", Time.get_ticks_usec() - t_total)
		return

	# Движение: каждый кадр летим прямо к текущей позиции игрока (100% попадание)
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()

	if dist <= hit_distance:
		_apply_hit()
		FRAME_PROFILER.add_usec("projectile.homing.physics.total", Time.get_ticks_usec() - t_total)
		return

	var t_move := Time.get_ticks_usec()
	var dir: Vector2 = to_target / dist
	if _animated_sprite == null:
		rotation = dir.angle()
	else:
		_update_directional_animation(dir)
	global_position += dir * speed * delta
	FRAME_PROFILER.add_usec("projectile.homing.physics.move", Time.get_ticks_usec() - t_move)
	FRAME_PROFILER.add_usec("projectile.homing.physics.total", Time.get_ticks_usec() - t_total)

func _update_directional_animation(dir: Vector2) -> void:
	if _animated_sprite == null or _animated_sprite.sprite_frames == null:
		return
	if not directional_animation:
		if _animated_sprite.sprite_frames.has_animation(StringName("default")):
			_animated_sprite.play("default")
		return

	var abs_x: float = absf(dir.x)
	var abs_y: float = absf(dir.y)
	var name: StringName = &"dir_right"
	if abs_x >= abs_y:
		name = &"dir_right" if dir.x >= 0.0 else &"dir_left"
	else:
		name = &"dir_down" if dir.y >= 0.0 else &"dir_up"

	if _animated_sprite.sprite_frames.has_animation(name) and _animated_sprite.animation != name:
		_animated_sprite.play(name)

func _apply_hit() -> void:
	if _hit:
		return
	_hit = true
	var dealt: int = 0

	if _target != null and is_instance_valid(_target):
		if "is_dead" in _target and bool(_target.get("is_dead")):
			queue_free()
			return
		var source_node: Node2D = _source if _source != null and is_instance_valid(_source) else null
		dealt = DAMAGE_HELPER.apply_damage_typed_with_result(source_node, _target, _damage, "physical")

	impacted.emit(_target)
	impacted_with_result.emit(_target, dealt, "physical")

	queue_free()


func _sync_sort_layer() -> void:
	var layer_source: Node2D = _source if _source != null and is_instance_valid(_source) else _target
	if layer_source == null or not is_instance_valid(layer_source):
		return
	var base_z: int = 0
	var visual_v: Variant = layer_source.get("visual_root")
	if visual_v is CanvasItem and is_instance_valid(visual_v):
		base_z = int((visual_v as CanvasItem).z_index)
	elif layer_source is CanvasItem:
		base_z = int((layer_source as CanvasItem).z_index)
	z_as_relative = false
	z_index = base_z
	if has_method("set_y_sort_origin"):
		call("set_y_sort_origin", 0)
	else:
		set("y_sort_origin", 0)
