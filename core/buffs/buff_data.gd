extends Resource
class_name BuffData

@export var id: String = ""
@export var duration_sec: float = 0.0
@export var secondary_add: Dictionary = {}
@export var percent_add: Dictionary = {}
@export var flags: Dictionary = {}
@export var on_hit: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"id": id,
		"duration_sec": duration_sec,
		"secondary_add": secondary_add.duplicate(true),
		"percent_add": percent_add.duplicate(true),
		"flags": flags.duplicate(true),
		"on_hit": on_hit.duplicate(true),
	}
