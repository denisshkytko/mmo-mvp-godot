extends RefCounted
class_name SpellPowerScaling

# Unified spell-power scaling framework (2026-03).
# Buckets by effective cast time (sec):
# direct: 100 / 80 / 60 / 40
# dot:    70  / 60 / 50 / 40
# heal:   95  / 80 / 65 / 50
# hot:    85  / 75 / 60 / 50

static func _bucket_coeff_pct(cast_time_sec: float, kind: String) -> float:
	var ct: float = max(0.0, cast_time_sec)
	match kind:
		"direct":
			if ct >= 2.5:
				return 100.0
			if ct >= 1.5:
				return 80.0
			if ct >= 0.5:
				return 60.0
			return 40.0
		"dot":
			if ct >= 2.5:
				return 70.0
			if ct >= 1.5:
				return 60.0
			if ct >= 0.5:
				return 50.0
			return 40.0
		"heal":
			if ct >= 2.5:
				return 95.0
			if ct >= 1.5:
				return 80.0
			if ct >= 0.5:
				return 65.0
			return 50.0
		"hot":
			if ct >= 2.5:
				return 85.0
			if ct >= 1.5:
				return 75.0
			if ct >= 0.5:
				return 60.0
			return 50.0
		_:
			return 100.0


static func coeff_pct(rank_data: RankData, kind: String) -> float:
	if rank_data != null and rank_data.flags is Dictionary:
		var key := "sp_coeff_%s_pct" % kind
		if (rank_data.flags as Dictionary).has(key):
			return float((rank_data.flags as Dictionary).get(key, 100.0))
	return _bucket_coeff_pct(0.0 if rank_data == null else float(rank_data.cast_time_sec), kind)


static func bonus_flat(spell_power: float, rank_data: RankData, kind: String) -> int:
	if spell_power <= 0.0:
		return 0
	return int(round(spell_power * coeff_pct(rank_data, kind) / 100.0))
