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
	if key == "":
		push_warning("[AbilityDB] AbilityDefinition has empty id: " + source_path)
		return
	var cls := str(definition.class_id)
	if cls == "":
		push_warning("[AbilityDB] AbilityDefinition has empty class_id id=%s path=%s" % [key, source_path])
		return
	print("[AbilityDB] register id=", key, " class=", cls)
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

func _load_from_manifest(path: String) -> bool:
	var loaded: Resource = load(path)
	if loaded == null:
		if OS.is_debug_build():
			print("[AbilityDB] manifest missing: ", path)
		return false
	var defs: Array = []
	if loaded is AbilitiesManifest:
		var manifest := loaded as AbilitiesManifest
		defs = manifest.ability_defs
	else:
		var raw_defs: Variant = loaded.get("ability_defs")
		if raw_defs is Array:
			defs = raw_defs as Array
			push_warning("[AbilityDB] Manifest loaded as untyped Resource. Attempting to coerce ability_defs: " + path)
		else:
			push_warning("[AbilityDB] Manifest has invalid type: " + path)
			return false
	if defs.is_empty():
		push_warning("[AbilityDB] Manifest is empty: " + path)
		return false
	for raw_def in defs:
		var normalized := _coerce_ability_def(raw_def, path)
		_register_def(normalized, path)
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
					if res != null:
						loaded_class = res.get_class()
						loaded_script = str(res.get_script())
					print("[AbilityDB] load ", full_path, " => ", res, " class=", loaded_class, " script=", loaded_script)
				if res == null:
					push_warning("[AbilityDB] load failed: " + full_path)
				elif not (res is AbilityDefinition):
					push_warning("[AbilityDB] NOT AbilityDefinition: %s class=%s script=%s" % [full_path, res.get_class(), str(res.get_script())])
					var coerced := _coerce_ability_def(res, full_path)
					_register_def(coerced, full_path)
				else:
					_register_def(res, full_path)
		name = dir.get_next()
	dir.list_dir_end()


func _coerce_ability_def(raw_def: Variant, source_path: String) -> AbilityDefinition:
	if raw_def is AbilityDefinition:
		return raw_def as AbilityDefinition
	if not (raw_def is Resource):
		return null
	var src := raw_def as Resource
	var id := str(src.get("id"))
	var class_id := str(src.get("class_id"))
	if id == "" or class_id == "":
		return null
	var def := AbilityDefinition.new()
	def.id = id
	def.name = str(src.get("name"))
	def.icon = src.get("icon") as Texture2D
	def.description = str(src.get("description"))
	def.class_id = class_id
	def.ability_type = str(src.get("ability_type"))
	def.target_type = str(src.get("target_type"))
	def.range_mode = str(src.get("range_mode"))
	var aura_radius_raw: Variant = src.get("aura_radius")
	if aura_radius_raw is float or aura_radius_raw is int:
		def.aura_radius = aura_radius_raw
	else:
		def.aura_radius = str(aura_radius_raw).to_float()
	def.effect = src.get("effect") as AbilityEffect
	var ranks_v: Variant = src.get("ranks")
	if ranks_v is Array:
		for entry in (ranks_v as Array):
			if entry is RankData:
				def.ranks.append(entry as RankData)
	if OS.is_debug_build():
		print("[AbilityDB] coerced untyped Resource -> AbilityDefinition id=", def.id, " class=", def.class_id, " source=", source_path)
	return def


func _print_summary() -> void:
	print("[AbilityDB] loaded abilities=", abilities.size())
	print("[AbilityDB] loaded classes=", class_index.keys())
