extends RefCounted
class_name LootRights

# ------------------------------------------------------------
# LootRights (helper)
#
# Унифицирует механику "право на лут по первому удару игрока".
# НЕ меняет архитектуру проекта: просто убирает копипасту
# между мобами и NPC.
# ------------------------------------------------------------

static func capture_first_player_hit(current_owner_player_id: int, attacker: Node) -> int:
	# Уже есть право — ничего не меняем.
	if current_owner_player_id != 0:
		return current_owner_player_id
	# Некорректный атакующий
	if attacker == null or not is_instance_valid(attacker):
		return current_owner_player_id
	# Право получает только игрок.
	# Важно: attacker может быть хитбоксом/снарядом/дочерним узлом игрока,
	# поэтому поднимаемся по родителям и ищем узел из группы "player".
	var n: Node = attacker
	while n != null:
		if n.is_in_group("player"):
			return n.get_instance_id()
		n = n.get_parent()
	return current_owner_player_id


static func clear_owner() -> int:
	return 0


static func apply_owner_to_corpse(corpse: Node, owner_player_id: int) -> void:
	# Corpse лутается только owner-игроком.
	# Если owner нет — явно сбрасываем на null.
	if corpse == null or not is_instance_valid(corpse):
		return
	if not corpse.has_method("set_loot_owner_player"):
		return

	# В мультиплеере игроков может быть несколько.
	# Корректный owner — это ЛЮБОЙ узел из группы "player" с совпадающим instance_id.
	var p: Node = get_player_by_instance_id(corpse.get_tree(), owner_player_id)
	corpse.call("set_loot_owner_player", p)


static func get_player_by_instance_id(tree: SceneTree, player_id: int) -> Node:
	if tree == null:
		return null
	if player_id == 0:
		return null
	var players: Array = tree.get_nodes_in_group("player")
	for n in players:
		if n is Node and is_instance_valid(n):
			var pn: Node = n as Node
			if pn.get_instance_id() == player_id:
				return pn
	return null


static func can_reward_xp(owner_player_id: int, player: Node) -> bool:
	# Единое правило: XP/награды даются только если игрок владел правом на лут.
	if owner_player_id == 0:
		return false
	if player == null or not is_instance_valid(player):
		return false
	if not player.is_in_group("player"):
		return false
	return player.get_instance_id() == owner_player_id
