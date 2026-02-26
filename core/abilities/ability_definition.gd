extends Resource
class_name AbilityDefinition

@export var id: String = ""
@export var name_key: String = ""
@export var icon: Texture2D
@export var description_key: String = ""
@export var class_id: String = ""
@export var ability_type: String = "active"
@export var target_type: String = "enemy"
@export var self_cast_fallback: bool = false
@export var range_mode: String = "ranged"
@export var effect: AbilityEffect
@export var ranks: Array[RankData] = []

func get_display_name() -> String:
	return TranslationServer.translate(name_key)

func get_description_template() -> String:
	return TranslationServer.translate(description_key)

func get_max_rank() -> int:
	return ranks.size()
