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
	# Право получает только игрок
	if not attacker.is_in_group("player"):
		return current_owner_player_id
	return attacker.get_instance_id()


static func clear_owner() -> int:
	return 0


static func apply_owner_to_corpse(corpse: Node, owner_player_id: int) -> void:
	# Corpse лутается только owner-игроком.
	# Если owner нет — явно сбрасываем на null.
	if corpse == null or not is_instance_valid(corpse):
		return
	if not corpse.has_method("set_loot_owner_player"):
		return

	var p: Node = corpse.get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p) and p.get_instance_id() == owner_player_id:
		corpse.call("set_loot_owner_player", p)
	else:
		corpse.call("set_loot_owner_player", null)


static func can_reward_xp(owner_player_id: int, player: Node) -> bool:
	# Единое правило: XP/награды даются только если игрок владел правом на лут.
	if owner_player_id == 0:
		return false
	if player == null or not is_instance_valid(player):
		return false
	if not player.is_in_group("player"):
		return false
	return player.get_instance_id() == owner_player_id
