extends Area2D
class_name Corpse

const OVERLAY_COLORS := preload("res://game/characters/shared/overlay_relation_colors.gd")

signal despawned

@onready var visual: ColorRect = $Visual
@onready var corpse_sprite: Sprite2D = $Sprite2D
@onready var model_highlight: CanvasItem = $ModelHighlight

@export var interact_radius: float = 60.0
@export var despawn_seconds: float = 30.0
@export var owner_is_player: bool = false
@export var y_sort_anchor_offset_y: float = 310.0

var _life_timer: float = 0.0
var _player_in_range: Node = null

var _range_check_timer: float = 0.0
var _player_cached: Node2D = null

var _blink_t: float = 0.0

# identity/state snapshot of the dead owner entity
var owner_entity_id: int = 0
var owner_display_name: String = ""
var owner_level: int = 0
var owner_resource_type: String = "mana"
var owner_max_hp: int = 1
var owner_max_resource: int = 1

# owner gating
var loot_owner_player_id: int = 0

# V2 loot
var loot_gold: int = 0
var loot_slots: Array = []

func setup_owner_snapshot(entity_owner: Node, owner_player_id: int = 0) -> void:
	if entity_owner == null or not is_instance_valid(entity_owner):
		return

	owner_entity_id = entity_owner.get_instance_id()
	owner_display_name = _resolve_owner_display_name(entity_owner)
	owner_level = _resolve_owner_level(entity_owner)
	owner_max_hp = max(1, _resolve_owner_max_hp(entity_owner))
	owner_resource_type = _resolve_owner_resource_type(entity_owner)
	owner_max_resource = max(1, _resolve_owner_max_resource(entity_owner))
	if owner_player_id != 0:
		loot_owner_player_id = owner_player_id
	if entity_owner != null and entity_owner.has_method("get_corpse_pose_snapshot"):
		var pose_v: Variant = entity_owner.call("get_corpse_pose_snapshot")
		if pose_v is Dictionary:
			apply_pose_snapshot(pose_v as Dictionary)

func apply_pose_snapshot(snapshot: Dictionary) -> void:
	if corpse_sprite == null:
		return
	var tex_v: Variant = snapshot.get("texture", null)
	if not (tex_v is Texture2D):
		return
	var tex := tex_v as Texture2D
	corpse_sprite.texture = tex
	corpse_sprite.visible = true
	if visual != null:
		visual.visible = false
	corpse_sprite.flip_h = bool(snapshot.get("flip_h", false))
	var scale_v: Variant = snapshot.get("scale", Vector2.ONE)
	if scale_v is Vector2:
		corpse_sprite.scale = scale_v as Vector2
	if model_highlight != null and is_instance_valid(model_highlight) and model_highlight is Node2D:
		var hs := corpse_sprite.scale
		if abs(hs.x) <= 0.0001:
			hs.x = 1.0
		if abs(hs.y) <= 0.0001:
			hs.y = 1.0
		var h2 := model_highlight as Node2D
		h2.scale = hs
		h2.position = Vector2.ZERO
	var offset_v: Variant = snapshot.get("offset", Vector2.ZERO)
	if offset_v is Vector2:
		corpse_sprite.position = offset_v as Vector2

func get_display_name() -> String:
	if owner_display_name != "":
		return owner_display_name
	return String(name)

func get_level() -> int:
	return max(0, owner_level)

func get_current_hp() -> int:
	return 0

func get_max_hp() -> int:
	return max(1, owner_max_hp)

func get_resource_type() -> String:
	return owner_resource_type

func get_current_resource() -> int:
	return 0

func get_max_resource() -> int:
	return max(1, owner_max_resource)

func _resolve_owner_display_name(entity_owner: Node) -> String:
	if entity_owner.has_method("get_display_name"):
		var v: String = String(entity_owner.call("get_display_name"))
		if v != "":
			return v
	if entity_owner.has_method("get_mob_name"):
		var mob_name: String = String(entity_owner.call("get_mob_name"))
		if mob_name != "":
			return mob_name
	if entity_owner.has_method("get_npc_name"):
		var npc_name: String = String(entity_owner.call("get_npc_name"))
		if npc_name != "":
			return npc_name
	return String(entity_owner.name)

func _resolve_owner_level(entity_owner: Node) -> int:
	if entity_owner.has_method("get_level"):
		return int(entity_owner.call("get_level"))
	var mob_level: Variant = entity_owner.get("mob_level")
	if mob_level != null:
		return int(mob_level)
	var npc_level: Variant = entity_owner.get("npc_level")
	if npc_level != null:
		return int(npc_level)
	return 0

func _resolve_owner_max_hp(entity_owner: Node) -> int:
	if entity_owner.has_method("get_max_hp"):
		return int(entity_owner.call("get_max_hp"))
	if entity_owner.has_node("Components/Stats"):
		var stats: Node = entity_owner.get_node("Components/Stats")
		if stats != null:
			var max_hp_v: Variant = stats.get("max_hp")
			if max_hp_v != null:
				return int(max_hp_v)
	var owner_max_hp_v: Variant = entity_owner.get("max_hp")
	if owner_max_hp_v != null:
		return int(owner_max_hp_v)
	return 1

func _resolve_owner_resource_type(entity_owner: Node) -> String:
	if entity_owner.has_method("get_resource_type"):
		var rt: String = String(entity_owner.call("get_resource_type"))
		if rt != "":
			return rt
	if entity_owner.has_node("Components/Resource"):
		var r: Node = entity_owner.get_node("Components/Resource")
		if r != null:
			var rv: Variant = r.get("resource_type")
			if rv != null and String(rv) != "":
				return String(rv)
	return "mana"

func _resolve_owner_max_resource(entity_owner: Node) -> int:
	if entity_owner.has_method("get_max_resource"):
		return int(entity_owner.call("get_max_resource"))
	if entity_owner.has_node("Components/Resource"):
		var r: Node = entity_owner.get_node("Components/Resource")
		if r != null:
			var mv: Variant = r.get("max_resource")
			if mv != null:
				return int(mv)
	return 1

func _ready() -> void:
	_life_timer = despawn_seconds
	add_to_group("y_sort_entities")
	refresh_local_overlap_sorting()

	var p: Node = get_tree().get_first_node_in_group("player")
	_player_cached = p as Node2D

	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)

func refresh_local_overlap_sorting() -> void:
	z_as_relative = true
	z_index = 0


func get_sort_anchor_global() -> Vector2:
	return global_position + Vector2(0.0, y_sort_anchor_offset_y)

func set_loot_owner_player(player_node: Node) -> void:
	if player_node == null:
		loot_owner_player_id = 0
		return
	loot_owner_player_id = player_node.get_instance_id()

func set_loot_v2(loot: Dictionary) -> void:
	# gold хранится отдельно
	loot_gold = int(loot.get("gold", 0))

	# slots в системе лута могут содержать и gold, и items
	# в corpse.loot_slots мы храним ТОЛЬКО items, иначе труп "не пустеет"
	var result_items: Array = []

	var s: Variant = loot.get("slots", [])
	if s is Array:
		var arr: Array = s as Array
		for v in arr:
			if v is Dictionary:
				var d := v as Dictionary
				if String(d.get("type", "")) == "item":
					# дополнительно фильтруем пустые/битые записи
					var id := String(d.get("id", ""))
					var count := int(d.get("count", 0))
					if id != "" and count > 0:
						result_items.append(d)

	loot_slots = result_items


func has_loot() -> bool:
	if loot_gold > 0:
		return true
	if loot_slots == null:
		return false
	if loot_slots.is_empty():
		return false

	# гарантируем что это реально items
	for v in loot_slots:
		if v is Dictionary and String((v as Dictionary).get("type", "")) == "item":
			return true
	return false


func _can_be_looted_by(player_node: Node) -> bool:
	if player_node == null:
		return false
	if not player_node.is_in_group("player"):
		return false
	if loot_owner_player_id == 0:
		return false
	return player_node.get_instance_id() == loot_owner_player_id

func _process(delta: float) -> void:
	# 1) despawn timer
	_life_timer -= delta
	if _life_timer <= 0.0:
		emit_signal("despawned")
		queue_free()
		return

	# 2) range check fallback (всегда с owner gating)
	_range_check_timer -= delta
	if _range_check_timer <= 0.0:
		_range_check_timer = 0.1

		# Не дергаем get_first_node_in_group() постоянно.
		# Для текущего прототипа игрок один, поэтому достаточно обновлять
		# кеш только если ссылка отсутствует или стала невалидной.
		if _player_cached == null or not is_instance_valid(_player_cached):
			var p: Node = get_tree().get_first_node_in_group("player")
			_player_cached = p as Node2D

		if _player_cached != null and is_instance_valid(_player_cached):
			var dist: float = global_position.distance_to(_player_cached.global_position)
			if dist <= interact_radius and has_loot() and _can_be_looted_by(_player_cached):
				_player_in_range = _player_cached
			else:
				_player_in_range = null
		else:
			_player_in_range = null

	# 3) interaction выполняется через Player/InteractionDetector (берётся только ближайший источник)
	_update_model_highlight()

	# 4) blink (только если игрок реально может лутать)
	if _player_cached != null and has_loot() and _can_be_looted_by(_player_cached) and _is_visible_by_camera():
		_blink_t += delta
		var k: float = 0.5 + 0.5 * sin(_blink_t * 9.0)
		visual.modulate.a = lerp(0.35, 1.0, k)
	else:
		visual.modulate.a = 1.0

func _update_model_highlight() -> void:
	if model_highlight == null or not is_instance_valid(model_highlight):
		return
	var can_loot: bool = (_player_cached != null and is_instance_valid(_player_cached) and has_loot() and _can_be_looted_by(_player_cached))
	model_highlight.visible = can_loot
	if not can_loot:
		return
	if model_highlight.has_method("set_colors"):
		var pulse: float = 0.65 + (0.35 * (0.5 + 0.5 * sin(_blink_t * 9.0)))
		var center: Color = OVERLAY_COLORS.GOLD
		center.a = pulse
		var edge: Color = OVERLAY_COLORS.GOLD
		edge.a = 0.5 * pulse
		model_highlight.call("set_colors", center, edge)

func _on_enter(body: Node) -> void:
	if not (body != null and body.is_in_group("player")):
		return
	# НЕ ставим игрока "в рендж", если он не owner
	if has_loot() and _can_be_looted_by(body):
		_player_in_range = body
	else:
		_player_in_range = null

func _on_exit(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null

func _is_visible_by_camera() -> bool:
	# упрощённо: если на экране — считаем visible
	# у тебя это уже было в проекте, оставляю поведение эквивалентным
	return true


func _try_open_loot() -> void:
	# Открываем лут строго если:
	# - игрок в радиусе
	# - у трупа есть лут
	# - игрок имеет право лутать
	if _player_cached == null or not is_instance_valid(_player_cached):
		return
	if not has_loot():
		return
	if not _can_be_looted_by(_player_cached):
		return

	var loot_ui := get_tree().get_first_node_in_group("loot_ui")
	if loot_ui == null:
		return

	# В LootHUD у тебя есть toggle_for_corpse(corpse)
	if loot_ui.has_method("toggle_for_corpse"):
		loot_ui.call("toggle_for_corpse", self)


func can_interact_with(player_node: Node) -> bool:
	if player_node == null or not is_instance_valid(player_node):
		return false
	if not has_loot():
		return false
	if not _can_be_looted_by(player_node):
		return false
	if player_node is Node2D:
		var dist: float = global_position.distance_to((player_node as Node2D).global_position)
		if dist > interact_radius:
			return false
	return true


func try_interact(player_node: Node) -> void:
	if not can_interact_with(player_node):
		return
	_player_cached = player_node as Node2D
	_try_open_loot()


func loot_all_to_player(player_node: Node) -> void:
	# Используется кнопкой "Забрать всё" из LootHUD
	if player_node == null:
		return
	if not _can_be_looted_by(player_node):
		return

	if loot_gold > 0 and player_node.has_method("add_gold"):
		player_node.call("add_gold", loot_gold)
	loot_gold = 0

	var kept: Array = []
	if loot_slots != null and loot_slots.size() > 0 and player_node.has_method("add_item"):
		for s in loot_slots:
			if not (s is Dictionary):
				continue
			var sd: Dictionary = s as Dictionary
			if String(sd.get("type", "")) != "item":
				continue
			var id := String(sd.get("id", ""))
			var count := int(sd.get("count", 0))
			if id == "" or count <= 0:
				continue
			# add_item returns how many did NOT fit.
			var remaining: int = int(player_node.call("add_item", id, count))
			if remaining > 0:
				sd["count"] = remaining
				kept.append(sd)

	loot_slots = kept
	if not has_loot():
		mark_looted()


func mark_looted() -> void:
	# Помечаем труп полностью пустым:
	# - больше не мигает
	# - интерактивность сброшена
	loot_gold = 0
	loot_slots = []
	loot_owner_player_id = 0
	_player_in_range = null
	visual.modulate.a = 1.0
	if model_highlight != null:
		model_highlight.visible = false
