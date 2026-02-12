@tool
extends EditorScript

const ROOT := "res://data/abilities"
const ABILITY_DEF_SCRIPT := "res://core/abilities/ability_definition.gd"
const MANIFEST_SCRIPT := "res://core/abilities/abilities_manifest.gd"
const RANK_DATA_SCRIPT := "res://core/abilities/rank_data.gd"
const EFFECT_SCRIPTS := {
	"EffectHeal": "res://core/abilities/effects/effect_heal.gd",
	"EffectDamage": "res://core/abilities/effects/effect_damage.gd",
	"EffectMixedDamage": "res://core/abilities/effects/effect_mixed_damage.gd",
}


func _run() -> void:
	var files := _collect_tres(ROOT)
	var changed := 0
	for path in files:
		if path.ends_with(".bak"):
			continue
		if _patch_file(path):
			changed += 1
	print("[MIGRATE_BINDINGS] changed files=", changed)


func _collect_tres(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var dir_path := stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				stack.append(full)
			elif name.get_extension().to_lower() == "tres":
				out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


func _patch_file(path: String) -> bool:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		push_warning("[MIGRATE_BINDINGS] unreadable: " + path)
		return false
	var lines := txt.split("\n")
	if lines.is_empty():
		return false

	var ext_map := _collect_script_ext_ids(lines)
	var max_id := _max_ext_id(lines)
	var ext_insert_idx := _ext_insert_index(lines)

	var is_manifest := path.ends_with("abilities_manifest.tres")
	var main_script := MANIFEST_SCRIPT if is_manifest else ABILITY_DEF_SCRIPT
	var main_id := int(ext_map.get(main_script, -1))
	if main_id == -1:
		max_id += 1
		main_id = max_id
		lines.insert(ext_insert_idx, '[ext_resource type="Script" path="%s" id=%d]' % [main_script, main_id])
		ext_insert_idx += 1
		ext_map[main_script] = main_id

	var changed := _ensure_resource_script_binding(lines, main_id)

	# RankData subresources
	var rank_id := int(ext_map.get(RANK_DATA_SCRIPT, -1))
	if rank_id == -1:
		max_id += 1
		rank_id = max_id
		lines.insert(ext_insert_idx, '[ext_resource type="Script" path="%s" id=%d]' % [RANK_DATA_SCRIPT, rank_id])
		ext_insert_idx += 1
		ext_map[RANK_DATA_SCRIPT] = rank_id

	changed = _bind_subresources(lines, "RankData", rank_id) or changed

	# Effect subresources (minimum set for paladin)
	for klass in EFFECT_SCRIPTS.keys():
		var effect_path := str(EFFECT_SCRIPTS[klass])
		var effect_id := int(ext_map.get(effect_path, -1))
		if effect_id == -1:
			max_id += 1
			effect_id = max_id
			lines.insert(ext_insert_idx, '[ext_resource type="Script" path="%s" id=%d]' % [effect_path, effect_id])
			ext_insert_idx += 1
			ext_map[effect_path] = effect_id
		changed = _bind_subresources(lines, str(klass), effect_id) or changed

	if not changed:
		return false

	var backup := path + ".bak"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	DirAccess.rename_absolute(path, backup)

	var out := "\n".join(lines)
	if not out.ends_with("\n"):
		out += "\n"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	if fh == null:
		push_warning("[MIGRATE_BINDINGS] write failed: " + path)
		return false
	fh.store_string(out)
	fh.close()
	print("[MIGRATE_BINDINGS] fixed ", path)
	return true


func _collect_script_ext_ids(lines: Array) -> Dictionary:
	var out := {}
	for line_v in lines:
		var line := str(line_v).strip_edges()
		if not line.begins_with("[ext_resource"):
			continue
		if line.find('type="Script"') == -1:
			continue
		var p := _extract_attr(line, "path")
		var id := _extract_int_attr(line, "id")
		if p != "" and id != -1:
			out[p] = id
	return out


func _max_ext_id(lines: Array) -> int:
	var max_id := 0
	for line_v in lines:
		var line := str(line_v).strip_edges()
		if not line.begins_with("[ext_resource"):
			continue
		var id := _extract_int_attr(line, "id")
		if id > max_id:
			max_id = id
	return max_id


func _ext_insert_index(lines: Array) -> int:
	var idx := 0
	for i in range(lines.size()):
		var line := str(lines[i]).strip_edges()
		if line.begins_with("[sub_resource") or line == "[resource]":
			return i
		if line.begins_with("[ext_resource"):
			idx = i + 1
	return idx


func _ensure_resource_script_binding(lines: Array, ext_id: int) -> bool:
	var resource_idx := -1
	for i in range(lines.size()):
		if str(lines[i]).strip_edges() == "[resource]":
			resource_idx = i
			break
	if resource_idx == -1:
		return false
	var end_idx := lines.size()
	for i in range(resource_idx + 1, lines.size()):
		if str(lines[i]).strip_edges().begins_with("["):
			end_idx = i
			break
	for i in range(resource_idx + 1, end_idx):
		if str(lines[i]).strip_edges().begins_with("script = ExtResource("):
			return false
	lines.insert(resource_idx + 1, 'script = ExtResource("%d")' % ext_id)
	return true


func _bind_subresources(lines: Array, script_class: String, ext_id: int) -> bool:
	var changed := false
	var i := 0
	while i < lines.size():
		var line := str(lines[i]).strip_edges()
		if line.begins_with("[sub_resource"):
			var class_name := _extract_attr(line, "script_class")
			if class_name == "":
				class_name = _extract_attr(line, "type")
			if class_name == script_class:
				if not _subresource_has_script(lines, i):
					lines.insert(i + 1, 'script = ExtResource("%d")' % ext_id)
					changed = true
					i += 1
		i += 1
	return changed


func _subresource_has_script(lines: Array, start_idx: int) -> bool:
	var end_idx := lines.size()
	for i in range(start_idx + 1, lines.size()):
		if str(lines[i]).strip_edges().begins_with("["):
			end_idx = i
			break
	for i in range(start_idx + 1, end_idx):
		if str(lines[i]).strip_edges().begins_with("script = ExtResource("):
			return true
	return false


func _extract_attr(line: String, key: String) -> String:
	var token := key + "="
	var idx := line.find(token)
	if idx == -1:
		return ""
	var rest := line.substr(idx + token.length()).strip_edges()
	if rest.begins_with('"'):
		var end := rest.find('"', 1)
		if end == -1:
			return ""
		return rest.substr(1, end - 1)
	var end_space := rest.find(" ")
	var end_bracket := rest.find("]")
	var stop := -1
	if end_space == -1:
		stop = end_bracket
	elif end_bracket == -1:
		stop = end_space
	else:
		stop = min(end_space, end_bracket)
	if stop == -1:
		return rest
	return rest.substr(0, stop)


func _extract_int_attr(line: String, key: String) -> int:
	var raw := _extract_attr(line, key)
	if raw == "":
		return -1
	if raw.is_valid_int():
		return raw.to_int()
	return -1
