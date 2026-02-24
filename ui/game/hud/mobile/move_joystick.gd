extends Control
class_name MoveJoystick

signal move_dir_changed(dir: Vector2)

const DEADZONE_PX := 12.0

var _active_touch_id: int = -1
var _mouse_active: bool = false
var _center: Vector2 = Vector2.ZERO
var _last_dir: Vector2 = Vector2.ZERO

@onready var base: TextureRect = $Base
@onready var knob: TextureRect = $Knob


func _ready() -> void:
	_update_center()
	_set_knob_visible(false)
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
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _active_touch_id != -1:
			return
		if not _is_within_bounds(event.position):
			return
		_active_touch_id = event.index
		_set_knob_visible(true)
		_update_from_global_pos(event.position)
		accept_event()
		return

	if event.index != _active_touch_id:
		return
	_active_touch_id = -1
	_set_dir(Vector2.ZERO)
	_update_knob(Vector2.ZERO)
	_set_knob_visible(false)
	accept_event()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_touch_id:
		return
	_update_from_global_pos(event.position)
	accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _active_touch_id != -1:
			return
		if not _is_within_bounds(event.position):
			return
		_mouse_active = true
		_set_knob_visible(true)
		_update_from_global_pos(event.position)
		accept_event()
		return
	if not _mouse_active:
		return
	_mouse_active = false
	_set_dir(Vector2.ZERO)
	_update_knob(Vector2.ZERO)
	_set_knob_visible(false)
	accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_active:
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
	# For GUI/touch events we need stable conversion from viewport/global
	# coordinates into this Control local space. `to_local` handles canvas
	# transforms reliably for Control hierarchies.
	return to_local(global_pos)


func _set_dir(dir: Vector2) -> void:
	if dir == _last_dir:
		return
	_last_dir = dir
	emit_signal("move_dir_changed", dir)


func _update_knob(delta: Vector2) -> void:
	if knob == null:
		return
	var offset := Vector2.ZERO
	if delta.length() > 0.0:
		offset = delta.normalized() * min(delta.length(), _get_radius())
	knob.position = _center + offset - knob.size * 0.5


func _update_center() -> void:
	_center = size * 0.5
	if base != null:
		base.position = Vector2.ZERO
		base.size = size
	if knob != null:
		knob.position = _center - knob.size * 0.5


func _get_radius() -> float:
	return min(size.x, size.y) * 0.5


func _is_within_bounds(global_pos: Vector2) -> bool:
	var local_pos := _to_local_canvas(global_pos)
	return local_pos.distance_to(_center) <= _get_radius()


func _set_knob_visible(is_visible: bool) -> void:
	if knob != null:
		knob.visible = is_visible
