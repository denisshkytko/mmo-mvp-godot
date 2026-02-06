extends Resource
class_name AbilityDefinition

@export var id: String = ""
@export var name: String = ""
@export var icon: Texture2D
@export var description: String = ""
@export var class_id: String = ""
@export var ranks: Array[RankData] = []

func get_display_name() -> String:
	return name if name != "" else id

func get_max_rank() -> int:
	return ranks.size()
