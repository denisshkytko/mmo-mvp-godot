extends Resource
class_name AbilityDefinition

@export var id: String = ""
@export var name: String = ""
@export var icon: Texture2D
@export var description: String = ""
@export var description_ru: String = ""
@export var class_id: String = ""
@export var ability_type: String = "active"
@export var target_type: String = "enemy"
@export var self_cast_fallback: bool = false
@export var range_mode: String = "ranged"
@export var aura_radius: float = 0.0
@export var effect: AbilityEffect
@export var ranks: Array[RankData] = []

func get_display_name() -> String:
	return name if name != "" else id

func get_max_rank() -> int:
	return ranks.size()
