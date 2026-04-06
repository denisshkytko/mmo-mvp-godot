extends Node

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")

const CACHE_MAX_SIZE: int = 256
const CACHE_TTL_SEC: float = 4.0
const REQUEST_COOLDOWN_SEC: float = 0.20
const CACHE_SNAP: Vector2 = Vector2(8.0, 8.0)

var _path_cache: Dictionary = {}
var _request_time: Dictionary = {}

func request_path(nav_map: RID, start: Vector2, goal: Vector2, optimize: bool = true) -> PackedVector2Array:
	if not nav_map.is_valid():
		return PackedVector2Array()
	if not NavigationServer2D.map_is_active(nav_map):
		return PackedVector2Array()
	if NavigationServer2D.map_get_iteration_id(nav_map) <= 0:
		return PackedVector2Array()

	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	_prune(now_sec)
	var key := _make_key(nav_map, start, goal, optimize)
	if _path_cache.has(key):
		var entry: Dictionary = _path_cache[key]
		if now_sec - float(entry.get("time", 0.0)) <= CACHE_TTL_SEC:
			var cached_path: PackedVector2Array = entry.get("path", PackedVector2Array()) as PackedVector2Array
			if not cached_path.is_empty():
				return cached_path

	if _request_time.has(key):
		var last_t: float = float(_request_time[key])
		if now_sec - last_t < REQUEST_COOLDOWN_SEC and _path_cache.has(key):
			var cd_entry: Dictionary = _path_cache[key]
			return cd_entry.get("path", PackedVector2Array()) as PackedVector2Array
	_request_time[key] = now_sec

	var t_query := Time.get_ticks_usec()
	var start_nav := NavigationServer2D.map_get_closest_point(nav_map, start)
	var goal_nav := NavigationServer2D.map_get_closest_point(nav_map, goal)
	var path := NavigationServer2D.map_get_path(nav_map, start_nav, goal_nav, optimize)
	FRAME_PROFILER.add_usec("nav.path.query", Time.get_ticks_usec() - t_query)

	_cache_store(key, path, now_sec)
	return path

func clear_cache() -> void:
	_path_cache.clear()
	_request_time.clear()

func _make_key(nav_map: RID, start: Vector2, goal: Vector2, optimize: bool) -> String:
	var s := start.snapped(CACHE_SNAP)
	var g := goal.snapped(CACHE_SNAP)
	return "%d|%d,%d|%d,%d|%d" % [nav_map.get_id(), int(s.x), int(s.y), int(g.x), int(g.y), 1 if optimize else 0]

func _cache_store(key: String, path: PackedVector2Array, now_sec: float) -> void:
	if _path_cache.size() >= CACHE_MAX_SIZE:
		var oldest_key: String = ""
		var oldest_t: float = INF
		for k in _path_cache.keys():
			var e: Dictionary = _path_cache[k]
			var t: float = float(e.get("time", now_sec))
			if t < oldest_t:
				oldest_t = t
				oldest_key = String(k)
		if oldest_key != "":
			_path_cache.erase(oldest_key)
	_path_cache[key] = {
		"path": path,
		"time": now_sec
	}

func _prune(now_sec: float) -> void:
	var remove_keys: Array[String] = []
	for k in _path_cache.keys():
		var e: Dictionary = _path_cache[k]
		if now_sec - float(e.get("time", 0.0)) > CACHE_TTL_SEC:
			remove_keys.append(String(k))
	for k in remove_keys:
		_path_cache.erase(k)
