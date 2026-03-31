extends RefCounted
class_name FrameProfiler

static var enabled: bool = true
static var _usec_accum: Dictionary = {}
static var _samples: Dictionary = {}
static var _count_accum: Dictionary = {}
static var _count_samples: Dictionary = {}


static func add_usec(key: String, usec: int) -> void:
	if not enabled:
		return
	if key == "" or usec <= 0:
		return
	_usec_accum[key] = int(_usec_accum.get(key, 0)) + usec
	_samples[key] = int(_samples.get(key, 0)) + 1


static func consume_average_ms() -> Dictionary:
	var out: Dictionary = {}
	for key in _usec_accum.keys():
		var total_usec: int = int(_usec_accum.get(key, 0))
		var count: int = max(1, int(_samples.get(key, 0)))
		out[key] = (float(total_usec) / float(count)) / 1000.0
	_usec_accum.clear()
	_samples.clear()
	return out


static func add_count(key: String, value: float = 1.0) -> void:
	if not enabled:
		return
	if key == "":
		return
	_count_accum[key] = float(_count_accum.get(key, 0.0)) + value
	_count_samples[key] = int(_count_samples.get(key, 0)) + 1


static func consume_counts() -> Dictionary:
	var out: Dictionary = {}
	for key in _count_accum.keys():
		var total_count: float = float(_count_accum.get(key, 0.0))
		var count_samples: int = max(1, int(_count_samples.get(key, 0)))
		out[key] = {
			"total_count": total_count,
			"avg_count": total_count / float(count_samples),
			"samples": count_samples,
		}
	_count_accum.clear()
	_count_samples.clear()
	return out


static func consume_stats() -> Dictionary:
	var out: Dictionary = {}
	for key in _usec_accum.keys():
		var total_usec: int = int(_usec_accum.get(key, 0))
		var count: int = max(1, int(_samples.get(key, 0)))
		out[key] = {
			"total_ms": float(total_usec) / 1000.0,
			"avg_ms": (float(total_usec) / float(count)) / 1000.0,
			"samples": count,
		}
	_usec_accum.clear()
	_samples.clear()
	return out
