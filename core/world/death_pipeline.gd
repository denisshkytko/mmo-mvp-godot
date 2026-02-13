extends RefCounted
class_name DeathPipeline

const LOOT_RIGHTS := preload("res://core/loot/loot_rights.gd")
const NODE_CACHE := preload("res://core/runtime/node_cache.gd")
const CORPSE_SCENE: PackedScene = preload("res://game/world/corpses/Corpse.tscn")

# ------------------------------------------------------------
# DeathPipeline
#
# Единый безопасный пайплайн смерти для мобов/НПС:
# 1) создать труп
# 2) применить loot rights
# 3) сгенерировать лут
# 4) выдать XP (ТОЛЬКО owner-игроку)
# 5) очистить target в game_manager, если он указывал на self
# 6) вернуть corpse для сигнала died
# ------------------------------------------------------------

static func spawn_corpse(parent: Node, world_pos: Vector2) -> Corpse:
	if parent == null or not is_instance_valid(parent):
		return null
	var inst := CORPSE_SCENE.instantiate()
	var corpse := inst as Corpse
	if corpse == null:
		return null
	parent.add_child(corpse)
	corpse.global_position = world_pos
	return corpse


static func apply_loot_to_corpse(corpse: Corpse, level: int, loot_profile: Resource, loot_context: Dictionary = {}) -> void:
	if corpse == null or not is_instance_valid(corpse):
		return
	# Единственный механизм лута: LootProfile (пресеты из res://core/loot/profiles).
	# Если профиль не задан — лут не генерируем.
	if loot_profile == null:
		return
	var loot: Dictionary = LootSystem.generate_loot_from_profile(loot_profile, level, loot_context)
	if corpse.has_method("set_loot_v2"):
		corpse.call("set_loot_v2", loot)
	else:
		corpse.loot_gold = int(loot.get("gold", 0))


static func clear_if_targeted(self_node: Node) -> void:
	if self_node == null or not is_instance_valid(self_node):
		return
	var gm := NODE_CACHE.get_game_manager(self_node.get_tree())
	if gm != null and gm.has_method("get_target") and gm.has_method("clear_target"):
		if gm.call("get_target") == self_node:
			gm.call("clear_target")


static func grant_xp_if_owner(loot_owner_player_id: int, xp_amount: int, tree: SceneTree) -> void:
	if xp_amount <= 0:
		return
	var p := NODE_CACHE.get_player(tree)
	if LOOT_RIGHTS.can_reward_xp(loot_owner_player_id, p) and p != null and p.has_method("add_xp"):
		p.call("add_xp", xp_amount)


static func die_and_spawn(
	self_node: Node2D,
	loot_owner_player_id: int,
	xp_amount: int,
	level: int,
	loot_profile: Resource = null,
	loot_context: Dictionary = {}
) -> Corpse:
	if self_node == null or not is_instance_valid(self_node):
		return null

	var corpse := spawn_corpse(self_node.get_parent(), self_node.global_position)
	if corpse != null:
		corpse.setup_owner_snapshot(self_node)
		# 1) Назначаем owner-игрока (любой узел из группы "player").
		LOOT_RIGHTS.apply_owner_to_corpse(corpse, loot_owner_player_id)
		# 2) Если owner НЕ игрок (owner id не соответствует ни одному игроку) —
		#    лут не генерируем вообще (экономим ресурсы и избегаем "мертвого" лута).
		var owner_node: Node = LOOT_RIGHTS.get_player_by_instance_id(self_node.get_tree(), loot_owner_player_id)
		if owner_node != null:
			apply_loot_to_corpse(corpse, level, loot_profile, loot_context)

	grant_xp_if_owner(loot_owner_player_id, xp_amount, self_node.get_tree())
	clear_if_targeted(self_node)
	return corpse
