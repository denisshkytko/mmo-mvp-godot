@tool
extends EditorScript

const ABILITY_DEF_SCRIPT := "res://core/abilities/ability_definition.gd"
const MANIFEST_SCRIPT := "res://core/abilities/abilities_manifest.gd"
const RANK_DATA_SCRIPT := "res://core/abilities/rank_data.gd"
const EFFECT_SCRIPTS := {
	"EffectDamage": "res://core/abilities/effects/effect_damage.gd",
	"EffectHeal": "res://core/abilities/effects/effect_heal.gd",
	"EffectMixedDamage": "res://core/abilities/effects/effect_mixed_damage.gd",
	"EffectApplyBuff": "res://core/abilities/effects/effect_apply_buff.gd",
	"EffectApplyAura": "res://core/abilities/effects/effect_apply_aura.gd",
	"EffectApplyStance": "res://core/abilities/effects/effect_apply_stance.gd",
	"EffectResourceRestore": "res://core/abilities/effects/effect_resource_restore.gd",
	"EffectAOE": "res://core/abilities/effects/effect_aoe.gd",
}

const ABILITIES_DIR := "res://data/abilities/paladin"
const MANIFEST_PATH := "res://data/abilities/abilities_manifest.tres"


func _run() -> void:
	var files := _list_tres_files(ABILITIES_DIR)
	if files.is_empty():
		push_warning("[MIGRATE] no abilities found in " + ABILITIES_DIR)
		return

	var converted: Array[AbilityDefinition] = []
	for path in files:
		if path.ends_with("_broken.tres"):
			continue
		var def := _convert_file(path)
		if def != null:
			converted.append(def)

	print("[MIGRATE] converted ", converted.size(), " abilities")
	_write_manifest(converted)
	print("[MIGRATE] wrote abilities_manifest.tres")


func _convert_file(path: String) -> AbilityDefinition:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		push_warning("[MIGRATE] empty/unreadable file: " + path)
		return null

	var parsed := _parse_tres_text(txt)
	var def := _build_ability_definition(parsed, path)
	if def == null:
		push_warning("[MIGRATE] failed to parse AbilityDefinition: " + path)
		return null

	if def.id == "" or def.class_id == "":
		push_warning("[MIGRATE] missing id/class_id: " + path)
		return null

	_backup_file(path)
	var err := ResourceSaver.save(def, path)
	if err != OK:
		push_warning("[MIGRATE] save failed: %s err=%d" % [path, err])
		return null
	var loaded := load(path)
	if loaded == null or not (loaded is AbilityDefinition):
		push_warning("[MIGRATE] saved file is not AbilityDefinition: " + path)
		return null
	return loaded as AbilityDefinition


func _write_manifest(defs: Array[AbilityDefinition]) -> void:
	_backup_file(MANIFEST_PATH)
	var script := load(MANIFEST_SCRIPT)
	if script == null:
		push_warning("[MIGRATE] missing manifest script: " + MANIFEST_SCRIPT)
		return
	var manifest: AbilitiesManifest = script.new()
	manifest.ability_defs = defs
	var err := ResourceSaver.save(manifest, MANIFEST_PATH)
	if err != OK:
		push_warning("[MIGRATE] manifest save failed err=%d" % err)


func _backup_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var backup := path.trim_suffix(".tres") + "_broken.tres"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	DirAccess.rename_absolute(path, backup)


func _list_tres_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "tres":
			out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _parse_tres_text(txt: String) -> Dictionary:
	var ext_resources: Dictionary = {}
	var sub_resources: Dictionary = {}
	var resource_fields: Dictionary = {}
	var section := ""
	var current_sub_id := ""
	var current_sub: Dictionary = {}

	for raw in txt.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";"):
			continue
		if line.begins_with("["):
			if section == "sub" and current_sub_id != "":
				sub_resources[current_sub_id] = current_sub
				current_sub = {}
				current_sub_id = ""
			if line.begins_with("[ext_resource"):
				section = "ext"
				var ext_id := _extract_quoted_after(line, "id=")
				var ext_path := _extract_quoted_after(line, "path=")
				if ext_id != "" and ext_path != "":
					ext_resources[ext_id] = ext_path
			elif line.begins_with("[sub_resource"):
				section = "sub"
				current_sub_id = _extract_quoted_after(line, "id=")
				current_sub = {"type": _extract_quoted_after(line, "script_class=")}
				if current_sub["type"] == "":
					current_sub["type"] = _extract_quoted_after(line, "type=")
			elif line.begins_with("[resource]"):
				section = "resource"
			else:
				section = ""
			continue

		var eq := line.find("=")
		if eq == -1:
			continue
		var key := line.substr(0, eq).strip_edges()
		var value_text := line.substr(eq + 1).strip_edges()
		var value := _parse_value(value_text)
		if section == "sub" and current_sub_id != "":
			current_sub[key] = value
		elif section == "resource":
			resource_fields[key] = value

	if section == "sub" and current_sub_id != "":
		sub_resources[current_sub_id] = current_sub

	return {
		"ext": ext_resources,
		"sub": sub_resources,
		"res": resource_fields,
	}


func _build_ability_definition(parsed: Dictionary, path: String) -> AbilityDefinition:
	var script := load(ABILITY_DEF_SCRIPT)
	if script == null:
		push_warning("[MIGRATE] missing AbilityDefinition script: " + ABILITY_DEF_SCRIPT)
		return null
	var def: AbilityDefinition = script.new()

	var ext := parsed.get("ext", {}) as Dictionary
	var sub := parsed.get("sub", {}) as Dictionary
	var res := parsed.get("res", {}) as Dictionary

	def.id = str(res.get("id", ""))
	def.name = str(res.get("name", ""))
	def.description = str(res.get("description", ""))
	def.class_id = str(res.get("class_id", ""))
	def.ability_type = str(res.get("ability_type", "active"))
	def.target_type = str(res.get("target_type", "enemy"))
	def.range_mode = str(res.get("range_mode", "ranged"))
	def.aura_radius = str(res.get("aura_radius", "0")).to_float()

	var icon_ref := res.get("icon")
	if typeof(icon_ref) == TYPE_DICTIONARY and icon_ref.get("kind") == "ext":
		var icon_path := str(ext.get(str(icon_ref.get("id")), ""))
		if icon_path != "":
			def.icon = load(icon_path) as Texture2D

	var effect_ref := res.get("effect")
	if typeof(effect_ref) == TYPE_DICTIONARY and effect_ref.get("kind") == "sub":
		def.effect = _build_effect(sub.get(str(effect_ref.get("id")), {}), sub, ext)

	var ranks_ref := res.get("ranks")
	if ranks_ref is Array:
		for entry in ranks_ref:
			if typeof(entry) == TYPE_DICTIONARY and entry.get("kind") == "sub":
				var rank := _build_rank_data(sub.get(str(entry.get("id")), {}))
				if rank != null:
					def.ranks.append(rank)

	if def.id == "" or def.class_id == "":
		push_warning("[MIGRATE] id/class_id missing in parsed file: " + path)
	return def


func _build_rank_data(data: Dictionary) -> RankData:
	var script := load(RANK_DATA_SCRIPT)
	if script == null:
		return null
	var rank: RankData = script.new()
	for k in [
		"required_level", "train_cost_gold", "resource_cost", "value_flat", "value_flat_2"
	]:
		rank.set(k, str(data.get(k, "0")).to_int())
	for kf in [
		"cooldown_sec", "cast_time_sec", "duration_sec", "value_pct", "value_pct_2"
	]:
		rank.set(kf, str(data.get(kf, "0")).to_float())
	rank.flags = data.get("flags", {}) if data.get("flags", {}) is Dictionary else {}
	return rank


func _build_effect(data: Dictionary, sub_map: Dictionary, ext: Dictionary) -> AbilityEffect:
	if data.is_empty():
		return null
	var effect_type := str(data.get("type", ""))
	var script_path := str(EFFECT_SCRIPTS.get(effect_type, ""))
	if script_path == "":
		return null
	var script := load(script_path)
	if script == null:
		return null
	var effect: AbilityEffect = script.new()
	for key in data.keys():
		if key == "type":
			continue
		var val = data[key]
		if typeof(val) == TYPE_DICTIONARY:
			if val.get("kind") == "sub":
				var nested := _build_effect(sub_map.get(str(val.get("id")), {}), sub_map, ext)
				effect.set(key, nested)
			elif val.get("kind") == "ext":
				var p := str(ext.get(str(val.get("id")), ""))
				effect.set(key, load(p) if p != "" else null)
		else:
			effect.set(key, val)
	return effect


func _parse_value(text: String):
	if text.begins_with('"') and text.ends_with('"'):
		return text.substr(1, text.length() - 2)
	if text == "true":
		return true
	if text == "false":
		return false
	if text.begins_with("ExtResource("):
		return {"kind": "ext", "id": _extract_quoted(text)}
	if text.begins_with("SubResource("):
		return {"kind": "sub", "id": _extract_quoted(text)}
	if text.begins_with("[") and text.ends_with("]"):
		var inner := text.substr(1, text.length() - 2).strip_edges()
		if inner == "":
			return []
		var arr: Array = []
		for part in _split_top_level(inner, ','):
			arr.append(_parse_value(part.strip_edges()))
		return arr
	if text.begins_with("{") and text.ends_with("}"):
		var inner_d := text.substr(1, text.length() - 2).strip_edges()
		var d := {}
		if inner_d == "":
			return d
		for item in _split_top_level(inner_d, ','):
			var kv := _split_first(item, ':')
			if kv.size() != 2:
				continue
			var k := _parse_value(kv[0].strip_edges())
			d[str(k)] = _parse_value(kv[1].strip_edges())
		return d
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	return text


func _split_first(s: String, delim: String) -> Array:
	var idx := s.find(delim)
	if idx == -1:
		return [s]
	return [s.substr(0, idx), s.substr(idx + 1)]


func _split_top_level(s: String, delim: String) -> Array[String]:
	var out: Array[String] = []
	var depth_br := 0
	var depth_cur := 0
	var in_str := false
	var token := ""
	for i in range(s.length()):
		var ch := s[i]
		if ch == '"':
			in_str = not in_str
			token += ch
			continue
		if not in_str:
			if ch == '[':
				depth_br += 1
			elif ch == ']':
				depth_br -= 1
			elif ch == '{':
				depth_cur += 1
			elif ch == '}':
				depth_cur -= 1
			elif ch == delim and depth_br == 0 and depth_cur == 0:
				out.append(token)
				token = ""
				continue
		token += ch
	out.append(token)
	return out


func _extract_quoted_after(line: String, token: String) -> String:
	var idx := line.find(token)
	if idx == -1:
		return ""
	var sub := line.substr(idx + token.length()).strip_edges()
	return _extract_quoted(sub)


func _extract_quoted(text: String) -> String:
	var a := text.find('"')
	if a == -1:
		return ""
	var b := text.find('"', a + 1)
	if b == -1:
		return ""
	return text.substr(a + 1, b - a - 1)
