extends RefCounted
class_name NodeCache

# ------------------------------------------------------------
# NodeCache
#
# Маленький helper, чтобы не дергать get_first_node_in_group()
# из _process/_physics_process каждый кадр.
#
# Кэш обновляется не чаще, чем раз в CHECK_INTERVAL_MSEC.
# ------------------------------------------------------------

const CHECK_INTERVAL_MSEC := 250

static var _cached_player: Node = null
static var _cached_player_check_msec: int = 0

static var _cached_game_manager: Node = null
static var _cached_game_manager_check_msec: int = 0


static func get_player(tree: SceneTree) -> Node:
	if tree == null:
		return null

	var now_msec: int = Time.get_ticks_msec()
	if _cached_player == null or not is_instance_valid(_cached_player) or (now_msec - _cached_player_check_msec) >= CHECK_INTERVAL_MSEC:
		_cached_player_check_msec = now_msec
		_cached_player = tree.get_first_node_in_group("player")
		if _cached_player != null and not is_instance_valid(_cached_player):
			_cached_player = null

	return _cached_player


static func get_game_manager(tree: SceneTree) -> Node:
	if tree == null:
		return null

	var now_msec: int = Time.get_ticks_msec()
	if _cached_game_manager == null or not is_instance_valid(_cached_game_manager) or (now_msec - _cached_game_manager_check_msec) >= CHECK_INTERVAL_MSEC:
		_cached_game_manager_check_msec = now_msec
		_cached_game_manager = tree.get_first_node_in_group("game_manager")
		if _cached_game_manager != null and not is_instance_valid(_cached_game_manager):
			_cached_game_manager = null

	return _cached_game_manager
