extends RefCounted
class_name ProfilerUtils

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")


static func measure_usec(key: String, callable: Callable) -> Variant:
	if not FRAME_PROFILER.enabled:
		return callable.call()
	var started_at := Time.get_ticks_usec()
	var result: Variant = callable.call()
	FRAME_PROFILER.add_usec(key, Time.get_ticks_usec() - started_at)
	return result


static func track_count(key: String, value: float = 1.0) -> void:
	FRAME_PROFILER.add_count(key, value)
