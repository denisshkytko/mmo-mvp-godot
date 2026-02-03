extends Control
class_name MoveJoystick

signal move_dir_changed(dir: Vector2)

const DEADZONE_PX := 12.0
const KNOB_RADIUS_PX := 60.0

var _active_touch_id: int = -1
var _center: Vector2 = Vector2.ZERO
var _last_dir: Vector2 = Vector2.ZERO

@onready var base: TextureRect = $Base
@onready var knob: TextureRect = $Knob


func _ready() -> void:
	_update_center()
	_update_knob(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_center()
		_update_knob(Vector2.ZERO)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
		return
	if event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _active_touch_id != -1:
			return
		if not get_global_rect().has_point(event.position):
			return
		_active_touch_id = event.index
		_update_from_global_pos(event.position)
		accept_event()
		return

	if event.index != _active_touch_id:
		return
	_active_touch_id = -1
	_set_dir(Vector2.ZERO)
	_update_knob(Vector2.ZERO)
	accept_event()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_touch_id:
		return
	_update_from_global_pos(event.position)
	accept_event()


func _update_from_global_pos(global_pos: Vector2) -> void:
	var local_pos: Vector2 = _to_local_canvas(global_pos)
	var delta: Vector2 = local_pos - _center
	var distance: float = delta.length()
	var dir: Vector2 = Vector2.ZERO
	if distance > DEADZONE_PX:
		dir = delta.normalized()
	_set_dir(dir)
	_update_knob(delta)


func _to_local_canvas(global_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse().xform(global_pos)


func _set_dir(dir: Vector2) -> void:
	if dir == _last_dir:
		return
	_last_dir = dir
	emit_signal("move_dir_changed", dir)


func _update_knob(delta: Vector2) -> void:
	var offset := Vector2.ZERO
	if delta.length() > 0.0:
		offset = delta.normalized() * min(delta.length(), KNOB_RADIUS_PX)
	knob.position = _center + offset - knob.size * 0.5


func _update_center() -> void:
	_center = size * 0.5
	base.position = Vector2.ZERO
	base.size = size
	knob.position = _center - knob.size * 0.5
