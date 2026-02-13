extends Node
class_name AbilityDatabase

signal initialized

const ABILITIES_ROOT_PATH := "res://data/abilities"
const ABILITIES_MANIFEST_PATH := "res://data/abilities/abilities_manifest.tres"

var abilities: Dictionary = {}
var class_index: Dictionary = {}
var is_ready: bool = false

func _debug_check_ability_scripts() -> void:
	if not OS.is_debug_build():
		return
	var script_res: Resource = load("res://core/abilities/ability_definition.gd")
	var script_class := "null"
	if script_res != null:
		script_class = script_res.get_class()
	print("[AbilityDB] ability_definition.gd loaded: ", script_res, " class=", script_class)
	var test_res: Resource = load("res://data/abilities/paladin/healing_light.tres")
	var test_class := "null"
	var test_script := "null"
	var script_class_prop := "<n/a>"
	var test_id := "<n/a>"
	var test_class_id := "<n/a>"
	var test_ranks_size := -1
	if test_res != null:
		test_class = test_res.get_class()
		test_script = str(test_res.get_script())
		script_class_prop = str(test_res.get("script_class"))
		test_id = str(test_res.get("id"))
		test_class_id = str(test_res.get("class_id"))
		var ranks_v: Variant = test_res.get("ranks")
		if ranks_v is Array:
			test_ranks_size = (ranks_v as Array).size()
	print("[AbilityDB] test heal_light: class=", test_class, " script=", test_script, " script_class=", script_class_prop, " is_ability_def=", test_res is AbilityDefinition, " id=", test_id, " class_id=", test_class_id, " ranks_size=", test_ranks_size)


func _ready() -> void:
	if is_ready:
		return
	abilities.clear()
	class_index.clear()
	_debug_check_ability_scripts()
	print("[AbilityDB] scan root=", ABILITIES_ROOT_PATH)
	if _load_from_manifest(ABILITIES_MANIFEST_PATH):
		print("[AbilityDB] loaded from manifest abilities=", abilities.size())
		_print_summary()
		is_ready = true
		emit_signal("initialized")
		return
	_load_abilities_from_dir(ABILITIES_ROOT_PATH)
	_print_summary()
	if abilities.size() == 0:
		push_warning("[AbilityDB] abilities=0. Likely no .tres discovered OR resources not included in export. See logs above.")
	is_ready = true
	emit_signal("initialized")

func register_ability(definition: AbilityDefinition) -> void:
	_register_def(definition, "runtime")

func _register_def(definition: AbilityDefinition, source_path: String = "") -> void:
	if definition == null:
		push_warning("[AbilityDB] register_ability skipped null definition")
		return
	var key := str(definition.id)
	if key == "" or key == "<null>":
		push_warning("[AbilityDB] AbilityDefinition has empty id: " + source_path)
		return
	var cls := str(definition.class_id)
	if cls == "" or cls == "<null>":
		push_warning("[AbilityDB] AbilityDefinition has empty class_id id=%s path=%s" % [key, source_path])
	print("[AbilityDB] register id=", key, " class=", cls)
	abilities[key] = definition
	if cls != "" and cls != "<null>":
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
			var def := get_ability(str(ability_id))
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

func get_starter_ability_ids_for_class(class_id: String) -> Array[String]:
	var out: Array[String] = []
	if class_id == "":
		return out
	var defs := get_abilities_for_class(class_id)
	for def in defs:
		if def == null or def.id == "":
			continue
		var rank_one := get_rank_data(def.id, 1)
		if rank_one == null:
			continue
		if rank_one.required_level == 1:
			out.append(def.id)
	out.sort()
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
		_register_def(def, path)
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
				if OS.is_debug_build():
					var loaded_class := "null"
					var loaded_script := "null"
					var loaded_script_class := "<n/a>"
					if res != null:
						loaded_class = res.get_class()
						loaded_script = str(res.get_script())
						loaded_script_class = str(res.get("script_class"))
					print("[AbilityDB] load ", full_path, " => ", res, " class=", loaded_class, " script=", loaded_script, " script_class=", loaded_script_class, " is_ability_def=", res is AbilityDefinition)
				if res == null:
					push_warning("[AbilityDB] load failed: " + full_path)
				elif not (res is AbilityDefinition):
					push_warning("[AbilityDB] NOT AbilityDefinition: %s class=%s script=%s script_class=%s" % [full_path, res.get_class(), str(res.get_script()), str(res.get("script_class"))])
				else:
					_register_def(res, full_path)
		name = dir.get_next()
	dir.list_dir_end()


func _print_summary() -> void:
	print("[AbilityDB] loaded abilities=", abilities.size())
	print("[AbilityDB] loaded classes=", class_index.keys())
