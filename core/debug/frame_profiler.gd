extends RefCounted
class_name FrameProfiler

static var enabled: bool = true
static var _usec_accum: Dictionary = {}
static var _samples: Dictionary = {}


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
