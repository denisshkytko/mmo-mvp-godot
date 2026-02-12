extends Node
class_name AbilityDatabase

signal initialized

const ABILITIES_ROOT_PATH := "res://data/abilities"
const ABILITIES_MANIFEST_PATH := "res://data/abilities/abilities_manifest.tres"

var abilities: Dictionary = {}
var class_index: Dictionary = {}
var is_ready: bool = false

func _ready() -> void:
	if is_ready:
		return
	abilities.clear()
	class_index.clear()
	print("[AbilityDB] scan root=", ABILITIES_ROOT_PATH)
	if _load_from_manifest(ABILITIES_MANIFEST_PATH):
		print("[AbilityDB] loaded from manifest abilities=", abilities.size())
		is_ready = true
		emit_signal("initialized")
		return
	_load_abilities_from_dir(ABILITIES_ROOT_PATH)
	print("[AbilityDB] loaded abilities=", abilities.size())
	if abilities.size() == 0:
		push_warning("[AbilityDB] abilities=0. Likely no .tres discovered OR resources not included in export. See logs above.")
	is_ready = true
	emit_signal("initialized")

func register_ability(definition: AbilityDefinition) -> void:
	_register_def(definition)

func _register_def(definition: AbilityDefinition) -> void:
	if definition == null:
		push_warning("[AbilityDB] register_ability skipped null definition")
		return
	var key := String(definition.id)
	if key == "":
		push_warning("[AbilityDB] register_ability skipped: empty id")
		return
	var cls := String(definition.class_id)
	if cls == "":
		push_warning("[AbilityDB] register_ability skipped '%s': empty class_id" % key)
		return
	if OS.is_debug_build():
		print("[AbilityDB] reg id=", key, " class=", cls)
	abilities[key] = definition
	if not class_index.has(cls):
		class_index[cls] = PackedStringArray()
	var ids: PackedStringArray = class_index[cls] as PackedStringArray
	if not ids.has(key):
		ids.append(key)
	class_index[cls] = ids

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
	if class_id != "" and class_index.has(class_id):
		var ids: PackedStringArray = class_index[class_id] as PackedStringArray
		for ability_id in ids:
			var def := get_ability(String(ability_id))
			if def != null:
				out.append(def)
		return out
	for ability in abilities.values():
		var def := ability as AbilityDefinition
		if def == null:
			continue
		if class_id == "" or def.class_id == class_id:
			out.append(def)
	return out

func _load_from_manifest(path: String) -> bool:
	var loaded: Resource = load(path)
	if loaded == null:
		if OS.is_debug_build():
			print("[AbilityDB] manifest missing: ", path)
		return false
	if not (loaded is AbilitiesManifest):
		push_warning("[AbilityDB] Manifest has invalid type: " + path)
		return false
	var manifest := loaded as AbilitiesManifest
	if manifest.ability_defs.is_empty():
		push_warning("[AbilityDB] Manifest is empty: " + path)
		return false
	for def in manifest.ability_defs:
		_register_def(def)
	return abilities.size() > 0

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
		else:
			var ext := name.get_extension().to_lower()
			if ext == "import" or ext == "remap":
				name = dir.get_next()
				continue
			if ext == "tres" or ext == "res":
				if OS.is_debug_build():
					print("[AbilityDB] found resource=", full_path)
				var res: Resource = load(full_path)
				if res is AbilityDefinition:
					_register_def(res)
				else:
					var script_ref: Variant = null
					var resource_class: String = ""
					if res != null:
						script_ref = res.get_script()
						resource_class = res.get_class()
					push_warning("[AbilityDB] not AbilityDefinition: %s script=%s class=%s" % [full_path, str(script_ref), resource_class])
		name = dir.get_next()
	dir.list_dir_end()
