extends AbilityEffect
class_name EffectApplyBuff

const BuffData := preload("res://core/buffs/buff_data.gd")

@export var buff_id: String = ""
@export var secondary_add: Dictionary = {}
@export var percent_add: Dictionary = {}
@export var flags: Dictionary = {}
@export var on_hit: Dictionary = {}

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or rank_data == null:
		return
	if target == null:
		target = caster

	var ability_id: String = String(context.get("ability_id", ""))
	var entry_id: String = buff_id
	if entry_id == "":
		entry_id = "buff:%s" % ability_id if ability_id != "" else "buff:"

	var data_res: BuffData = BuffData.new()
	data_res.id = entry_id
	data_res.duration_sec = float(rank_data.duration_sec)
	data_res.secondary_add = _resolve_dict(secondary_add, rank_data, false)
	data_res.percent_add = _resolve_dict(percent_add, rank_data, true)
	data_res.flags = _resolve_dict(flags, rank_data, false)
	data_res.on_hit = _resolve_dict(on_hit, rank_data, false)

	var data_dict := data_res.to_dict()
	data_dict["ability_id"] = ability_id
	data_dict["source"] = String(context.get("source", ""))

	_apply_buff_to_target(target, entry_id, data_res.duration_sec, data_dict)

func _apply_buff_to_target(target: Node, entry_id: String, duration_sec: float, data: Dictionary) -> void:
	if target == null:
		return
	if target.has_method("add_or_refresh_buff"):
		target.call("add_or_refresh_buff", entry_id, duration_sec, data)
		return
	if "c_buffs" in target and target.c_buffs != null:
		target.c_buffs.add_or_refresh_buff(entry_id, duration_sec, data)

func _resolve_dict(source: Dictionary, rank_data: RankData, is_percent: bool) -> Dictionary:
	var out: Dictionary = {}
	for key in source.keys():
		var value = source.get(key)
		var resolved := _resolve_value(value, rank_data, is_percent)
		if resolved == null:
			continue
		out[key] = resolved
	return out

func _resolve_value(value, rank_data: RankData, is_percent: bool):
	if value is String:
		match String(value):
			"value_flat":
				return float(rank_data.value_flat)
			"value_flat_2":
				return float(rank_data.value_flat_2)
			"value_pct":
				return float(rank_data.value_pct) / 100.0 if is_percent else float(rank_data.value_pct)
			"value_pct_2":
				return float(rank_data.value_pct_2) / 100.0 if is_percent else float(rank_data.value_pct_2)
			_:
				return null
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	if typeof(value) == TYPE_BOOL:
		return value
	return value
