extends RefCounted
class_name Buff

var id: String
var name: String
var duration: float
var time_left: float
var icon: Texture2D = null
var dispellable: bool = true

func _init(_id: String, _name: String, _duration: float, _icon: Texture2D = null, _dispellable: bool = true) -> void:
	id = _id
	name = _name
	duration = _duration
	time_left = _duration
	icon = _icon
	dispellable = _dispellable
