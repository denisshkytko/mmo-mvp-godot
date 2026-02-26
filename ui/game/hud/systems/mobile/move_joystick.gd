extends Control
class_name MoveJoystick

signal move_dir_changed(dir: Vector2)

const DEADZONE_PX := 12.0
const DEBUG_JOYSTICK := true

var _active_touch_id: int = -1
var _mouse_active: bool = false
var _center: Vector2 = Vector2.ZERO
var _input_origin: Vector2 = Vector2.ZERO
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
	var local_pos := _event_position_local(event)
	if event.pressed:
		if _active_touch_id != -1:
			return
		if not _is_within_bounds(local_pos):
			if DEBUG_JOYSTICK:
				print("[MoveJoystick] touch press outside bounds local=", local_pos, " center=", _center, " radius=", _get_radius())
			return
		_active_touch_id = event.index
		_input_origin = local_pos
		_set_knob_visible(true)
		_update_from_local_pos(local_pos)
		accept_event()
		return

	if event.index != _active_touch_id:
		return
	_active_touch_id = -1
	_input_origin = _center
	_set_dir(Vector2.ZERO)
	_update_knob(Vector2.ZERO)
	_set_knob_visible(false)
	accept_event()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_touch_id:
		return
	_update_from_local_pos(_event_position_local(event))
	accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var local_pos := _event_position_local(event)
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if _active_touch_id != -1:
			return
		if not _is_within_bounds(local_pos):
			if DEBUG_JOYSTICK:
				print("[MoveJoystick] mouse press outside bounds local=", local_pos, " center=", _center, " radius=", _get_radius())
			return
		_mouse_active = true
		_input_origin = local_pos
		_set_knob_visible(true)
		_update_from_local_pos(local_pos)
		accept_event()
		return
	if not _mouse_active:
		return
	_mouse_active = false
	_input_origin = _center
	_set_dir(Vector2.ZERO)
	_update_knob(Vector2.ZERO)
	_set_knob_visible(false)
	accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_active:
		return
	_update_from_local_pos(_event_position_local(event))
	accept_event()


func _update_from_local_pos(local_pos: Vector2) -> void:
	var delta: Vector2 = local_pos - _input_origin
	var distance: float = delta.length()
	var dir: Vector2 = Vector2.ZERO
	if distance > DEADZONE_PX:
		dir = delta.normalized()
	_set_dir(dir)
	_update_knob(delta)


func _event_position_local(event: InputEvent) -> Vector2:
	var e: InputEvent = event.duplicate()
	make_input_local(e)
	if e is InputEventScreenTouch:
		return (e as InputEventScreenTouch).position
	if e is InputEventScreenDrag:
		return (e as InputEventScreenDrag).position
	if e is InputEventMouseButton:
		return (e as InputEventMouseButton).position
	if e is InputEventMouseMotion:
		return (e as InputEventMouseMotion).position
	return Vector2.ZERO


func _set_dir(dir: Vector2) -> void:
	if dir == _last_dir:
		return
	_last_dir = dir
	if DEBUG_JOYSTICK:
		print("[MoveJoystick] dir=", dir)
	emit_signal("move_dir_changed", dir)


func _update_knob(delta: Vector2) -> void:
	if knob == null:
		return
	var offset := Vector2.ZERO
	if delta.length() > 0.0:
		offset = delta.normalized() * min(delta.length(), _get_radius())
	knob.position = _input_origin + offset - knob.size * 0.5


func _update_center() -> void:
	_center = size * 0.5
	if _active_touch_id == -1 and not _mouse_active:
		_input_origin = _center
	if base != null:
		base.position = Vector2.ZERO
		base.size = size
	if knob != null:
		knob.position = _center - knob.size * 0.5


func _get_radius() -> float:
	return min(size.x, size.y) * 0.5


func _is_within_bounds(local_pos: Vector2) -> bool:
	return local_pos.distance_to(_center) <= _get_radius()


func _set_knob_visible(is_visible: bool) -> void:
	if knob != null:
		knob.visible = is_visible
