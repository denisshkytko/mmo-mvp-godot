extends Resource
class_name MobSpellPreset

@export var id: String = ""
@export var class_id: String = ""
@export var name_key: String = ""
@export var primary_ability_id: String = ""
@export var secondary_ability_id_1: String = ""
@export var secondary_ability_id_2: String = ""

func get_ordered_ability_ids() -> Array[String]:
	var out: Array[String] = []
	if primary_ability_id != "":
		out.append(primary_ability_id)
	if secondary_ability_id_1 != "":
		out.append(secondary_ability_id_1)
	if secondary_ability_id_2 != "":
		out.append(secondary_ability_id_2)
	return out
