extends Node
class_name AbilityDatabase

signal initialized

var abilities: Dictionary = {}
var is_ready: bool = false

func _ready() -> void:
	if not is_ready:
		_load_abilities_from_dir("res://data/abilities")
		print("[AbilityDB] loaded abilities=", abilities.size())
		if abilities.size() == 0:
			push_warning("[AbilityDB] No abilities loaded from res://data/abilities (DirAccess.open failed or folder empty in build).")
		is_ready = true
		emit_signal("initialized")

func register_ability(definition: AbilityDefinition) -> void:
	if definition == null:
		return
	var key := definition.id
	if key == "":
		return
	abilities[key] = definition

func has_ability(ability_id: String) -> bool:
	return abilities.has(ability_id)

func get_ability(ability_id: String) -> AbilityDefinition:
	if abilities.has(ability_id):
		return abilities[ability_id] as AbilityDefinition
	return null

func get_rank_data(ability_id: String, rank: int) -> RankData:
	var ability := get_ability(ability_id)
	if ability == null:
		return null
	var idx := rank - 1
	if idx < 0 or idx >= ability.ranks.size():
		return null
	return ability.ranks[idx] as RankData

func get_rank_for_level(ability_id: String, level: int) -> int:
	var ability := get_ability(ability_id)
	if ability == null:
		return 0
	var best_rank := 0
	for i in range(ability.ranks.size()):
		var rank_data := ability.ranks[i] as RankData
		if rank_data == null:
			continue
		if rank_data.required_level <= level:
			best_rank = i + 1
	return best_rank

func get_max_rank(ability_id: String) -> int:
	var ability := get_ability(ability_id)
	return ability.get_max_rank() if ability != null else 0

func get_abilities_for_class(class_id: String) -> Array[AbilityDefinition]:
	var out: Array[AbilityDefinition] = []
	for ability in abilities.values():
		var def := ability as AbilityDefinition
		if def == null:
			continue
		if class_id == "" or def.class_id == class_id:
			out.append(def)
	return out

func _load_abilities_from_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[AbilityDB] DirAccess.open failed: " + path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path := path.path_join(name)
		if dir.current_is_dir():
			_load_abilities_from_dir(full_path)
		elif name.get_extension() == "tres":
			var res := load(full_path)
			if res is AbilityDefinition:
				register_ability(res)
		name = dir.get_next()
	dir.list_dir_end()
