@tool
extends EditorScript

const ABILITIES_ROOT := "res://core/data/abilities"
const ABILITY_DEF_SCRIPT := "res://core/abilities/ability_definition.gd"
const MANIFEST_SCRIPT := "res://core/abilities/abilities_manifest.gd"
const RANK_DATA_SCRIPT := "res://core/abilities/rank_data.gd"
const EFFECT_SCRIPTS := {
	"EffectAOE": "res://core/abilities/effects/effect_aoe.gd",
	"EffectApplyAura": "res://core/abilities/effects/effect_apply_aura.gd",
	"EffectApplyBuff": "res://core/abilities/effects/effect_apply_buff.gd",
	"EffectApplyStance": "res://core/abilities/effects/effect_apply_stance.gd",
	"EffectDamage": "res://core/abilities/effects/effect_damage.gd",
	"EffectHeal": "res://core/abilities/effects/effect_heal.gd",
	"EffectMixedDamage": "res://core/abilities/effects/effect_mixed_damage.gd",
	"EffectResourceRestore": "res://core/abilities/effects/effect_resource_restore.gd",
}


func _run() -> void:
	var files := _list_tres_recursive(ABILITIES_ROOT)
	var changed := 0
	for path in files:
		if path.ends_with(".tres.broken"):
			continue
		if _fix_file(path):
			changed += 1
	print("[FIX_TRES] changed files=", changed)


func _list_tres_recursive(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var current := stack.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				name = dir.get_next()
				continue
			var full := current.path_join(name)
			if dir.current_is_dir():
				stack.append(full)
			elif name.get_extension().to_lower() == "tres":
				out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


func _fix_file(path: String) -> bool:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		push_warning("[FIX_TRES] unreadable file: " + path)
		return false
	var lines := txt.split("\n")
	if lines.is_empty():
		return false

	var ext_by_path := _collect_ext_scripts(lines)
	var max_ext_id := _max_ext_id(lines)
	var ext_insert_idx := _ext_insert_index(lines)

	var is_manifest := path.ends_with("abilities_manifest.tres")
	var main_script_path := MANIFEST_SCRIPT if is_manifest else ABILITY_DEF_SCRIPT

	var main_ext_id := ext_by_path.get(main_script_path, -1)
	if int(main_ext_id) == -1:
		max_ext_id += 1
		main_ext_id = max_ext_id
		lines.insert(ext_insert_idx, '[ext_resource type="Script" path="%s" id=%d]' % [main_script_path, main_ext_id])
		ext_insert_idx += 1

	var changed := _ensure_resource_script(lines, int(main_ext_id))

	var sub_blocks := _find_subresource_blocks(lines)
	for block in sub_blocks:
		var class_name := str(block.get("class", ""))
		var script_path := ""
		if class_name == "RankData":
			script_path = RANK_DATA_SCRIPT
		elif EFFECT_SCRIPTS.has(class_name):
			script_path = str(EFFECT_SCRIPTS[class_name])
		if script_path == "":
			continue
		var ext_id := ext_by_path.get(script_path, -1)
		if int(ext_id) == -1:
			max_ext_id += 1
			ext_id = max_ext_id
			lines.insert(ext_insert_idx, '[ext_resource type="Script" path="%s" id=%d]' % [script_path, ext_id])
			ext_insert_idx += 1
			sub_blocks = _find_subresource_blocks(lines)
		var header_idx := int(block.get("start", -1))
		if header_idx == -1:
			continue
		if _block_has_script_line(lines, header_idx):
			continue
		lines.insert(header_idx + 1, 'script = ExtResource("%d")' % int(ext_id))
		changed = true
		sub_blocks = _find_subresource_blocks(lines)

	if not changed:
		return false

	var backup := path + ".broken"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	DirAccess.rename_absolute(path, backup)
	var out_txt := "\n".join(lines)
	if not out_txt.ends_with("\n"):
		out_txt += "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[FIX_TRES] failed to write: " + path)
		return false
	f.store_string(out_txt)
	f.close()
	print("[FIX_TRES] fixed ", path)
	return true


func _collect_ext_scripts(lines: Array) -> Dictionary:
	var map := {}
	for line_v in lines:
		var line := str(line_v).strip_edges()
		if not line.begins_with("[ext_resource"):
			continue
		if line.find('type="Script"') == -1:
			continue
		var p := _extract_attr(line, "path")
		var id := _extract_int_attr(line, "id")
		if p != "" and id != -1:
			map[p] = id
	return map


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


func _ensure_resource_script(lines: Array, script_ext_id: int) -> bool:
	var r_idx := -1
	for i in range(lines.size()):
		if str(lines[i]).strip_edges() == "[resource]":
			r_idx = i
			break
	if r_idx == -1:
		return false
	var end_idx := lines.size()
	for j in range(r_idx + 1, lines.size()):
		if str(lines[j]).strip_edges().begins_with("["):
			end_idx = j
			break
	for k in range(r_idx + 1, end_idx):
		if str(lines[k]).strip_edges().begins_with("script = ExtResource("):
			return false
	lines.insert(r_idx + 1, 'script = ExtResource("%d")' % script_ext_id)
	return true


func _find_subresource_blocks(lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(lines.size()):
		var line := str(lines[i]).strip_edges()
		if not line.begins_with("[sub_resource"):
			continue
		var class_name := _extract_attr(line, "script_class")
		if class_name == "":
			class_name = _extract_attr(line, "type")
		out.append({"start": i, "class": class_name})
	return out


func _block_has_script_line(lines: Array, header_idx: int) -> bool:
	var end_idx := lines.size()
	for i in range(header_idx + 1, lines.size()):
		if str(lines[i]).strip_edges().begins_with("["):
			end_idx = i
			break
	for i in range(header_idx + 1, end_idx):
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
	var end_br := rest.find("]")
	var stop := -1
	if end_space == -1:
		stop = end_br
	elif end_br == -1:
		stop = end_space
	else:
		stop = min(end_space, end_br)
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
