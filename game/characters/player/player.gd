extends CharacterBody2D
class_name Player

signal visual_layer_changed(new_z_index: int)
signal carrier_effects_stop()

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const PROG := preload("res://core/stats/progression.gd")
const OVERLAY_COLORS := preload("res://game/characters/shared/overlay_relation_colors.gd")

## NodeCache is a global helper (class_name). Avoid shadowing.
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")

const WARRIOR_MODEL_SCENE := preload("res://game/characters/player/models/WarriorModel.tscn")
const MAGE_MODEL_SCENE := preload("res://game/characters/player/models/MageModel.tscn")
const PALADIN_MODEL_SCENE := preload("res://game/characters/player/models/PaladinModel.tscn")
const PRIEST_MODEL_SCENE := preload("res://game/characters/player/models/PriestModel.tscn")
const SHAMAN_MODEL_SCENE := preload("res://game/characters/player/models/ShamanModel.tscn")
const HUNTER_MODEL_SCENE := preload("res://game/characters/player/models/HunterModel.tscn")
const MAX_LEVEL: int = 60
const ROAD_LAYER_NAME: StringName = &"road"
const ROAD_MOVE_SPEED_MULT: float = 1.2
const ROAD_LAYER_RESCAN_SEC: float = 1.0

@export var move_speed: float = MOVE_SPEED.PLAYER_BASE

# Combat state (used for HP regen rule: HP regenerates only out of combat)
var _targeters := {} # instance_id -> true
var _y_sort_origin_meta_fallback_warned: bool = false
var _road_tile_layer: TileMapLayer = null
var _next_road_layer_scan_sec: float = 0.0

func on_targeted_by(attacker: Node) -> void:
	if attacker == null:
		return
	_targeters[attacker.get_instance_id()] = true
	var gm := _get_game_manager()
	if gm == null or not gm.has_method("get_target") or not gm.has_method("set_target"):
		return
	var current: Node = gm.call("get_target") as Node
	if current == null and is_instance_valid(attacker):
		gm.call("set_target", attacker)

func on_untargeted_by(attacker: Node) -> void:
	if attacker == null:
		return
	_targeters.erase(attacker.get_instance_id())

func is_in_combat() -> bool:
	return _targeters.size() > 0

func is_out_of_combat() -> bool:
	return _targeters.size() == 0

# Primary stats are tuned per-character on the Player node (as you requested).
# Internally they are applied to the PlayerStats component.
@export_group("Primary Stats (Level 1)")
@export var base_str: int = 10
@export var base_agi: int = 10
@export var base_end: int = 10
@export var base_int: int = 10
@export var base_per: int = 10

@export_group("Primary Growth (Per Level)")
@export var str_per_level: int = 1
@export var agi_per_level: int = 1
@export var end_per_level: int = 1
@export var int_per_level: int = 1
@export var per_per_level: int = 1

var faction_id: String = "blue"
var class_id: String = "warrior"
var _starter_grant_waiting_for_db: bool = false

# Mobile input
var mobile_move_dir: Vector2 = Vector2.ZERO

# --- Public “state” fields (HUD/UI читает их напрямую) ---
var inventory: Inventory = null

var level: int = 1
var xp: int = 0
var xp_to_next: int = 10

var max_hp: int = 100
var current_hp: int = 100
var attack: int = 10
var defense: int = 2

var max_mana: int = 60
var mana: int = 60

var is_dead: bool = false

# --- Consumables (food / drink / potion) ---
var _consumable_cd_end_sec: Dictionary = {} # kind -> float end time

func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _normalize_consumable_cd_kind(item_type: String, raw_kind: String) -> String:
	var t: String = item_type.to_lower()
	var k: String = raw_kind.to_lower()
	if t == "potion" or k.begins_with("potion"):
		return "potion"
	if t == "food" or t == "drink" or k.begins_with("food") or k.begins_with("drink"):
		return "fooddrink"
	return k if k != "" else t

func _get_consumable_cd_left_exact(kind: String) -> float:
	if kind == "":
		return 0.0
	var end_sec: float = float(_consumable_cd_end_sec.get(kind, 0.0))
	if end_sec <= 0.0:
		return 0.0
	return max(0.0, end_sec - _now_sec())

func is_consumable_on_cooldown(kind: String) -> bool:
	if kind == "":
		return false
	if not _consumable_cd_end_sec.has(kind):
		return false
	return _now_sec() < float(_consumable_cd_end_sec.get(kind, 0.0))

func start_consumable_cooldown(kind: String, seconds: float) -> void:
	if kind == "" or seconds <= 0.0:
		return
	_consumable_cd_end_sec[kind] = _now_sec() + seconds

func get_consumable_cooldown_left(kind: String) -> float:
	var k: String = kind.to_lower()
	if k == "":
		return 0.0
	var left: float = _get_consumable_cd_left_exact(k)
	if left > 0.0:
		return left
	# Backward-compatible lookup for legacy/non-normalized keys.
	if k == "fooddrink":
		left = max(left, _get_consumable_cd_left_exact("food"))
		left = max(left, _get_consumable_cd_left_exact("drink"))
	if k == "potion":
		for key_v in _consumable_cd_end_sec.keys():
			var key: String = String(key_v).to_lower()
			if key.begins_with("potion"):
				left = max(left, _get_consumable_cd_left_exact(key))
	return left

func try_apply_consumable(item_id: String) -> Dictionary:
	# Applies the consumable's effect (instant or over-time) WITHOUT removing the item from inventory.
	# Returns {"ok": bool, "reason": String, "kind": String}
	if item_id == "" or is_dead:
		return {"ok": false, "reason": "invalid", "kind": ""}
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return {"ok": false, "reason": "no_db", "kind": ""}
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	var typ: String = String(meta.get("type", "")).to_lower()
	if typ != "food" and typ != "drink" and typ != "potion":
		return {"ok": false, "reason": "not_consumable", "kind": ""}
	# Required level gate (for usable items).
	var req_lvl: int = int(meta.get("required_level", 1))
	if req_lvl > level:
		return {"ok": false, "reason": "level", "kind": "" , "required_level": req_lvl}
	var cons: Dictionary = meta.get("consumable", {}) as Dictionary
	var raw_kind: String = String(cons.get("kind", typ)).to_lower()
	var kind: String = _normalize_consumable_cd_kind(typ, raw_kind)
	if is_consumable_on_cooldown(kind):
		return {"ok": false, "reason": "cooldown", "kind": kind}

	# Potions use keys hp/mp, while food/drink use hp_total/mp_total.
	var hp_total: int = int(cons.get("hp_total", cons.get("hp", 0)))
	var mp_total: int = int(cons.get("mp_total", cons.get("mp", 0)))
	var instant: bool = bool(cons.get("instant", false))
	var duration_sec: float = float(cons.get("duration_sec", 0.0))

	# Determine if anything can be applied.
	var hp_need: int = max(0, max_hp - current_hp)
	var mp_need: int = max(0, max_mana - mana)
	var can_hp: bool = hp_total > 0 and hp_need > 0
	var can_mp: bool = mp_total > 0 and mp_need > 0
	if not can_hp and not can_mp:
		# Show which resource is full (best-effort).
		var r := "full"
		if hp_total > 0 and mp_total > 0:
			r = "hpmp_full"
		elif hp_total > 0:
			r = "hp_full"
		elif mp_total > 0:
			r = "mp_full"
		return {"ok": false, "reason": r, "kind": kind}

	# Apply effect
	if instant or duration_sec <= 0.0:
		if can_hp:
			var add_hp: int = min(hp_total, hp_need)
			var hp_before: int = current_hp
			current_hp = min(max_hp, current_hp + add_hp)
			var actual_heal: int = max(0, current_hp - hp_before)
			if actual_heal > 0:
				DAMAGE_HELPER.show_heal(self, actual_heal)
		if can_mp:
			var add_mp: int = min(mp_total, mp_need)
			mana = min(max_mana, mana + add_mp)
		# Cooldown
		start_consumable_cooldown(kind, 5.0 if typ == "potion" else 10.0)
		return {"ok": true, "reason": "", "kind": kind}

	# Over-time: heal/restore once per second, capped by total.
	var hp_per_sec: int = 0
	var mp_per_sec: int = 0
	if hp_total > 0:
		hp_per_sec = int(ceil(float(hp_total) / max(1.0, duration_sec)))
	if mp_total > 0:
		mp_per_sec = int(ceil(float(mp_total) / max(1.0, duration_sec)))
	# Unique id so multiple consumables can stack.
	var buff_id: String = "cons_%s_%d" % [item_id, int(Time.get_ticks_msec())]
	var data := {
		"consumable": true,
		"kind": kind,
		"hot_hp_per_sec": hp_per_sec,
		"hot_mp_per_sec": mp_per_sec,
		"hot_hp_left": hp_total,
		"hot_mp_left": mp_total,
		"hot_tick_acc": 0.0,
	}
	add_or_refresh_buff(buff_id, duration_sec, data)
	start_consumable_cooldown(kind, 5.0 if typ == "potion" else 10.0)
	return {"ok": true, "reason": "", "kind": kind}

# --- Components ---
@onready var c_stats: PlayerStats = $Components/Stats as PlayerStats
@onready var c_buffs: PlayerBuffs = $Components/Buffs as PlayerBuffs
@onready var c_combat: PlayerCombat = $Components/Combat as PlayerCombat
@onready var c_ability_caster: PlayerAbilityCaster = $Components/AbilityCaster as PlayerAbilityCaster
@onready var c_inv: PlayerInventoryComponent = $Components/Inventory as PlayerInventoryComponent
@onready var c_equip: PlayerEquipmentComponent = $Components/Equipment as PlayerEquipmentComponent
@onready var c_spellbook: PlayerSpellbook = $Components/Spellbook as PlayerSpellbook
@onready var c_resource: ResourceComponent = $Components/Resource as ResourceComponent
@onready var c_danger: DangerMeterComponent = $Components/Danger as DangerMeterComponent
var cast_bar: CastBarWidget = null
var hp_bar: HealthBarWidget = null
var target_marker: CanvasItem = null
var model_highlight: CanvasItem = null
var overlay_bars_widget: OverlayBarsWidget = null
@onready var c_interaction: InteractionDetector = $InteractionDetector as InteractionDetector
@onready var world_collision: CollisionShape2D = $WorldCollider as CollisionShape2D
@onready var body_hitbox_shape: CollisionShape2D = $BodyHitboxArea/BodyHitbox as CollisionShape2D
@onready var interaction_shape: CollisionShape2D = $InteractionDetector/InteractionRadius as CollisionShape2D

@onready var visual_root: Node2D = $Visual as Node2D

const DEFAULT_CAST_BAR_OFFSET: Vector2 = Vector2(0.0, -42.0)

var _character_model: Node = null
var _pending_corpse_pose_snapshot: Dictionary = {}
var _corpse_spawned_for_current_death: bool = false


func _ready() -> void:
	add_to_group("faction_units")
	add_to_group("y_sort_entities")
	_sync_y_sort_origin_from_world_collider()
	# setup components
	# push primary tuning from Player root into Stats component
	c_stats.base_str = base_str
	c_stats.base_agi = base_agi
	c_stats.base_end = base_end
	c_stats.base_int = base_int
	c_stats.base_per = base_per
	c_stats.str_per_level = str_per_level
	c_stats.agi_per_level = agi_per_level
	c_stats.end_per_level = end_per_level
	c_stats.int_per_level = int_per_level
	c_stats.per_per_level = per_per_level

	c_stats.setup(self)
	c_buffs.setup(self)
	c_combat.setup(self)
	if c_ability_caster != null:
		c_ability_caster.setup(self)

	# inventory ref (чтобы LootUI/InventoryUI не ломались)
	c_inv.setup(self)
	inventory = c_inv.inventory
	c_equip.setup(self)
	if c_spellbook != null:
		c_spellbook.setup(self)
		if not c_spellbook.spellbook_changed.is_connected(_on_spellbook_changed):
			c_spellbook.spellbook_changed.connect(_on_spellbook_changed)

	# init stats
	c_stats.recalculate_for_level(true)
	_enforce_level_cap_state()

	if c_resource != null:
		c_resource.setup(self)
		c_resource.configure_from_class_id(class_id)
		if c_resource.resource_type == "mana":
			c_resource.sync_from_owner_fields_if_mana()
		else:
			c_resource.set_empty()

	_apply_spellbook_passives()
	_apply_class_visual()
	if cast_bar != null:
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)

func get_danger_meter() -> DangerMeterComponent:
	return c_danger


func _physics_process(_delta: float) -> void:
	_update_visual_render_order()
	if is_dead:
		velocity = Vector2.ZERO
		_update_model_motion(Vector2.ZERO)
		move_and_slide()
		return
	if c_buffs != null and c_buffs.has_method("is_stunned") and bool(c_buffs.call("is_stunned")):
		_set_model_stunned(true)
		if c_ability_caster != null and c_ability_caster.is_casting():
			c_ability_caster.interrupt_cast("stunned")
		if cast_bar != null:
			cast_bar.set_cast_visible(false)
			cast_bar.set_progress01(0.0)
			cast_bar.set_icon_texture(null)
		velocity = Vector2.ZERO
		_update_model_motion(Vector2.ZERO)
		move_and_slide()
		return
	_set_model_stunned(false)

	var input_dir := Vector2.ZERO
	if mobile_move_dir != Vector2.ZERO:
		input_dir = mobile_move_dir
	else:
		input_dir = Vector2(
			Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
			Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
		)

	if Input.is_action_just_pressed("loot"):
		try_interact()

	if c_ability_caster != null and c_ability_caster.is_casting() and input_dir.length() > 0.0:
		c_ability_caster.interrupt_cast("movement")
	if c_ability_caster != null and c_ability_caster.is_casting():
		velocity = Vector2.ZERO
		_update_model_motion(Vector2.ZERO)
		move_and_slide()
		return

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	var move_mult: float = 1.0
	if c_buffs != null and c_buffs.has_method("get_move_speed_multiplier"):
		move_mult = float(c_buffs.call("get_move_speed_multiplier"))
	move_mult *= _get_road_move_speed_multiplier()
	if move_mult <= 0.0:
		move_mult = 1.0
	velocity = input_dir * move_speed * move_mult
	_update_model_motion(input_dir)
	move_and_slide()


func _get_road_move_speed_multiplier() -> float:
	var road_layer := _get_cached_road_layer()
	if road_layer == null:
		return 1.0
	var world_pos: Vector2 = get_world_collider_center_global()
	var cell: Vector2i = road_layer.local_to_map(road_layer.to_local(world_pos))
	return ROAD_MOVE_SPEED_MULT if road_layer.get_cell_source_id(cell) != -1 else 1.0


func _get_cached_road_layer() -> TileMapLayer:
	if _road_tile_layer != null and is_instance_valid(_road_tile_layer):
		return _road_tile_layer
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	if now_sec < _next_road_layer_scan_sec:
		return null
	_next_road_layer_scan_sec = now_sec + ROAD_LAYER_RESCAN_SEC
	var host := get_parent()
	if host == null:
		return null
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var current := stack.pop_back() as Node
		if current is TileMapLayer:
			var layer := current as TileMapLayer
			if String(layer.name).to_lower() == String(ROAD_LAYER_NAME):
				_road_tile_layer = layer
				return _road_tile_layer
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


func _update_visual_render_order() -> void:
	if visual_root == null or not is_instance_valid(visual_root):
		return
	visual_root.z_as_relative = true
	visual_root.z_index = 0
	var parent_2d := get_parent() as Node2D
	var under_player_pivot := parent_2d != null and String(parent_2d.name) == "__player_sort_pivot"
	if under_player_pivot or (parent_2d != null and parent_2d.y_sort_enabled):
		# In y-sort runtime all physical entities must stay on the same Z layer.
		# Ordering must come from Y-sort origin/anchor only.
		z_as_relative = true
		var parent_sort_z := int(parent_2d.z_index)
		if under_player_pivot:
			# Pivot already carries runtime host z; player itself must stay at local z=0
			# to avoid double z stacking against y-sorted tile layers.
			parent_sort_z = 0
		_apply_overlay_layer_offsets(parent_sort_z)
		if z_index != parent_sort_z:
			z_index = parent_sort_z
			emit_signal("visual_layer_changed", parent_sort_z)
		else:
			z_index = parent_sort_z
		return
	var resolved_z: int = _resolve_map_space_sort_z()
	resolved_z = clampi(resolved_z, RenderingServer.CANVAS_ITEM_Z_MIN + 2, RenderingServer.CANVAS_ITEM_Z_MAX)
	z_as_relative = false
	_apply_overlay_layer_offsets(resolved_z)
	if z_index != resolved_z:
		z_index = resolved_z
		emit_signal("visual_layer_changed", resolved_z)
	else:
		z_index = resolved_z

func _resolve_map_space_sort_z() -> int:
	var anchor := get_sort_anchor_global()
	var host := get_parent() as Node2D
	if host != null:
		for child in host.get_children():
			if child is TileMapLayer:
				var layer := child as TileMapLayer
				if not layer.y_sort_enabled:
					continue
				var cell: Vector2i = layer.local_to_map(layer.to_local(anchor))
				if layer.get_cell_source_id(cell) != -1:
					return int(cell.y) + int(layer.z_index)
	# Fallback: 64px world tile step.
	return int(floor(anchor.y / 64.0))


func _apply_overlay_layer_offsets(_base_visual_z: int) -> void:
	if target_marker != null and is_instance_valid(target_marker):
		target_marker.top_level = false
		target_marker.z_as_relative = true
		target_marker.z_index = -2
	if overlay_bars_widget != null and is_instance_valid(overlay_bars_widget):
		overlay_bars_widget.top_level = false
		overlay_bars_widget.z_as_relative = true
		overlay_bars_widget.z_index = 1

func refresh_local_overlap_sorting() -> void:
	_update_visual_render_order()


func _process(delta: float) -> void:
	if is_dead:
		return
	_ensure_model_attached_to_visual_root()

	if c_buffs != null:
		c_buffs.tick(delta)
	if c_stats != null:
		c_stats.tick(delta)
	if c_ability_caster != null:
		c_ability_caster.tick(delta)
	if c_combat != null and not (c_buffs != null and c_buffs.has_method("is_stunned") and bool(c_buffs.call("is_stunned"))):
		c_combat.tick(delta)

	if cast_bar != null and c_ability_caster != null:
		var casting := c_ability_caster.is_casting()
		cast_bar.set_cast_visible(casting)
		cast_bar.set_progress01(c_ability_caster.get_cast_progress() if casting else 0.0)
		cast_bar.set_icon_texture(c_ability_caster.get_cast_icon() if casting else null)
	_update_model_hp_bar()
	TargetMarkerHelper.set_marker_visible(target_marker, self)


func _ensure_model_attached_to_visual_root() -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if visual_root == null or not is_instance_valid(visual_root):
		return
	if _character_model.get_parent() == visual_root:
		return
	_character_model.reparent(visual_root, true)



func get_body_hitbox_center_global() -> Vector2:
	if body_hitbox_shape != null:
		return body_hitbox_shape.global_position
	return global_position

func get_world_collider_center_global() -> Vector2:
	if world_collision != null:
		return world_collision.global_position
	return global_position

func get_sort_anchor_global() -> Vector2:
	return get_world_collider_center_global()

func _sync_y_sort_origin_from_world_collider() -> void:
	if world_collision == null or not is_instance_valid(world_collision):
		return
	var origin_y := _compute_world_collider_sort_origin_y(world_collision)
	_apply_y_sort_origin(origin_y)

func _compute_world_collider_sort_origin_y(collider: CollisionShape2D) -> float:
	# Match debug green-diamond logic: collider center in global space, converted to this node local.
	return float(to_local(collider.global_position).y)


func _apply_y_sort_origin(origin_y: float) -> void:
	var origin_i := int(round(origin_y))
	if has_method("set_y_sort_origin"):
		call("set_y_sort_origin", origin_i)
		return
	if has_method("get_y_sort_origin"):
		set("y_sort_origin", origin_i)
		return
	for prop in get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			set("y_sort_origin", origin_i)
			return
	set_meta("__debug_y_sort_origin_local", origin_i)
	if not _y_sort_origin_meta_fallback_warned:
		_y_sort_origin_meta_fallback_warned = true
		push_warning("Player y_sort_origin is meta-only fallback; renderer may still sort by Player.global_position.")


func get_attack_damage() -> int:
	return c_combat.get_attack_damage()


func set_mobile_move_dir(dir: Vector2) -> void:
	mobile_move_dir = dir

func try_use_ability_slot(slot_index: int) -> void:
	if c_spellbook == null or c_ability_caster == null:
		return
	if slot_index < 0 or slot_index >= c_spellbook.loadout_slots.size():
		return
	var ability_id: String = c_spellbook.loadout_slots[slot_index]
	var target: Node = null
	var gm := _get_game_manager()
	if gm != null and gm.has_method("get_target"):
		target = gm.call("get_target")
	c_ability_caster.try_cast(ability_id, target)

func try_interact() -> void:
	if c_interaction != null:
		c_interaction.try_interact(self)

# Buffs API (BuffsUI/иконки)
func add_or_refresh_buff(id: String, duration_sec: float, data: Dictionary = {}) -> void:
	c_buffs.add_or_refresh_buff(id, duration_sec, data)

func remove_buff(id: String) -> void:
	c_buffs.remove_buff(id)

func get_buffs_snapshot() -> Array:
	return c_buffs.get_buffs_snapshot()


# CharacterHUD reads this if present
func get_stats_snapshot() -> Dictionary:
	if c_stats == null:
		return {}
	var snap: Dictionary = c_stats.get_stats_snapshot()
	# Add consumable HOT contribution (food/drink buffs) into regen numbers so CharacterHUD shows it.
	if c_buffs != null and c_buffs.has_method("get_consumable_hot_totals") and snap.has("derived"):
		var totals: Dictionary = c_buffs.call("get_consumable_hot_totals") as Dictionary
		var add_hp: float = float(totals.get("hp_per_sec", 0.0))
		var add_mp: float = float(totals.get("mp_per_sec", 0.0))
		if add_hp != 0.0 or add_mp != 0.0:
			var derived: Dictionary = snap.get("derived", {}) as Dictionary
			derived["hp_regen"] = float(derived.get("hp_regen", 0.0)) + add_hp
			derived["mana_regen"] = float(derived.get("mana_regen", 0.0)) + add_mp
			snap["derived"] = derived
			# Optional breakdown lines
			var breakdown: Dictionary = snap.get("derived_breakdown", {}) as Dictionary
			if add_hp != 0.0:
				var arr: Array = breakdown.get("hp_regen", [])
				arr.append({"source": "food/drink", "value": add_hp})
				breakdown["hp_regen"] = arr
			if add_mp != 0.0:
				var arr2: Array = breakdown.get("mana_regen", [])
				arr2.append({"source": "food/drink", "value": add_mp})
				breakdown["mana_regen"] = arr2
			snap["derived_breakdown"] = breakdown

	if c_buffs != null and c_buffs.has_method("get_attack_speed_multiplier"):
		var mult: float = float(c_buffs.call("get_attack_speed_multiplier"))
		if mult > 0.0 and mult != 1.0:
			# Stance/buff attack speed bonuses are additive in percentage points
			# (e.g. +42% should raise 12.23% to 54.23% without changing rating).
			var base_pct: float = float(snap.get("attack_speed_pct", 0.0))
			var bonus_pct_points: float = (mult - 1.0) * 100.0
			snap["attack_speed_pct"] = base_pct + bonus_pct_points
	return snap


func _get_game_manager() -> Node:
	return NodeCache.get_game_manager(get_tree())


func _request_save(kind: String) -> void:
	var gm: Node = _get_game_manager()
	if gm != null and gm.has_method("request_save"):
		gm.call("request_save", kind)

func _on_spellbook_changed() -> void:
	_apply_spellbook_passives()
	_apply_class_visual()
	if cast_bar != null:
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
	_request_save("spellbook_changed")

func _apply_spellbook_passives() -> void:
	if c_ability_caster == null or c_spellbook == null:
		return
	c_ability_caster.apply_active_aura(c_spellbook.aura_active)
	c_ability_caster.apply_active_stance(c_spellbook.stance_active)
	var passive_ids: Array[String] = c_spellbook.get_learned_by_type("passive")
	for ability_id in passive_ids:
		c_ability_caster.apply_passive(ability_id)
	if c_buffs != null and c_buffs.has_method("_sync_spirits_aid_ready_state"):
		c_buffs.call("_sync_spirits_aid_ready_state")
	if c_buffs != null and c_buffs.has_method("_sync_defensive_reflexes_ready_state"):
		c_buffs.call("_sync_defensive_reflexes_ready_state")


func add_gold(amount: int) -> void:
	c_inv.add_gold(amount)
	_request_save("gold")


func add_item(item_id: String, amount: int) -> int:
	var remaining: int = c_inv.add_item(item_id, amount)
	_request_save("item")

	return remaining

func consume_item(item_id: String, amount: int = 1) -> int:
	var removed: int = c_inv.consume_item(item_id, amount)
	if removed > 0:
		_request_save("item")
	return removed


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	if is_level_capped():
		return
	c_stats.add_xp(amount)
	_enforce_level_cap_state()
	_request_save("xp")

func is_level_capped() -> bool:
	return level >= MAX_LEVEL

func _enforce_level_cap_state() -> void:
	if level < MAX_LEVEL:
		return
	level = MAX_LEVEL
	xp = 0
	xp_to_next = 0


func get_inventory_snapshot() -> Dictionary:
	return c_inv.get_inventory_snapshot()

func get_quick_slots() -> Array[String]:
	if c_inv == null:
		return []
	return c_inv.get_quick_slots()

func get_equipment_snapshot() -> Dictionary:
	if c_equip == null:
		return {}
	return c_equip.get_equipment_snapshot()


func apply_inventory_snapshot(snapshot: Dictionary) -> void:
	# UI / save helpers: apply inventory slots + equipped bags back to component.
	if c_inv != null:
		c_inv.apply_inventory_snapshot(snapshot)

func set_quick_slots(slots: Array) -> void:
	if c_inv == null:
		return
	c_inv.set_quick_slots(slots)
	_request_save("item")

func apply_equipment_snapshot(snapshot: Dictionary) -> void:
	if c_equip != null:
		c_equip.apply_equipment_snapshot(snapshot)

func try_equip_from_inventory_slot(inv_slot_index: int, target_slot_id: String) -> bool:
	if c_equip == null:
		return false
	return c_equip.try_equip_from_inventory_slot(inv_slot_index, target_slot_id)

func get_last_equip_fail_reason() -> String:
	if c_equip == null:
		return ""
	return c_equip.get_last_equip_fail_reason()

func get_preferred_equipment_slot(item_id: String) -> String:
	if c_equip == null:
		return ""
	return c_equip.get_preferred_slot_for_item(item_id)


func try_equip_bag_from_inventory_slot(inv_slot_index: int, bag_index: int) -> bool:
	return c_inv.try_equip_bag_from_inventory_slot(inv_slot_index, bag_index)

func try_unequip_bag_to_inventory(bag_index: int, preferred_slot_index: int = -1) -> bool:
	return c_inv.try_unequip_bag_to_inventory(bag_index, preferred_slot_index)

func try_move_or_swap_bag_slots(from_bag_index: int, to_bag_index: int) -> bool:
	return c_inv.try_move_or_swap_bag_slots(from_bag_index, to_bag_index)

# Damage API
func take_damage(raw_damage: int) -> void:
	c_stats.take_damage(raw_damage)

func take_damage_typed(raw_damage: int, dmg_type: String = "physical") -> void:
	c_stats.take_damage_typed(raw_damage, dmg_type)

func take_damage_from(raw_damage: int, attacker: Node2D) -> int:
	return c_stats.take_damage_from_typed(raw_damage, attacker, "physical")

func take_damage_from_typed(raw_damage: int, attacker: Node2D, dmg_type: String = "physical") -> int:
	return c_stats.take_damage_from_typed(raw_damage, attacker, dmg_type)

func respawn_now() -> void:
	# телепорт на ближайший graveyard
	var gm: Node = _get_game_manager()
	if gm != null and gm.has_method("get_nearest_graveyard_position"):
		global_position = gm.call("get_nearest_graveyard_position", global_position)

	# восстановить HP/ману
	current_hp = max_hp
	if c_resource != null:
		if c_resource.resource_type == "mana":
			c_resource.set_full()
		else:
			c_resource.set_empty()

	# бафы не переносятся через смерть/респавн
	c_buffs.clear_all()
	_apply_spellbook_passives()

	is_dead = false
	_corpse_spawned_for_current_death = false
	if _character_model != null and is_instance_valid(_character_model):
		if _character_model.has_method("reset_after_respawn"):
			_character_model.call("reset_after_respawn")
	if c_buffs != null and c_buffs.has_method("_sync_spirits_aid_ready_state"):
		c_buffs.call("_sync_spirits_aid_ready_state")


func can_use_spirits_aid_on_death() -> bool:
	if c_buffs == null or not c_buffs.has_method("can_use_spirits_aid"):
		return false
	return bool(c_buffs.call("can_use_spirits_aid")) and is_dead

func use_spirits_aid_respawn() -> bool:
	if c_buffs == null or not c_buffs.has_method("consume_spirits_aid"):
		return false
	if not bool(c_buffs.call("consume_spirits_aid")):
		return false
	current_hp = max(1, int(round(float(max_hp) * 0.6)))
	if c_resource != null:
		if c_resource.resource_type == "mana":
			c_resource.resource = max(0, int(round(float(c_resource.max_resource) * 0.6)))
			c_resource.sync_to_owner_fields_if_mana()
		else:
			c_resource.set_empty()
	is_dead = false
	_corpse_spawned_for_current_death = false
	if _character_model != null and is_instance_valid(_character_model):
		if _character_model.has_method("reset_after_respawn"):
			_character_model.call("reset_after_respawn")
	_apply_spellbook_passives()
	if c_buffs.has_method("_sync_spirits_aid_ready_state"):
		c_buffs.call("_sync_spirits_aid_ready_state")
	_request_save("spirit_aid_used")
	return true


func apply_character_data(d: Dictionary) -> void:
	# имя/класс здесь не трогаем (они живут в сейве и UI), но статы/прогресс применяем
	level = clamp(int(d.get("level", level)), 1, MAX_LEVEL)
	xp = int(d.get("xp", xp))
	xp_to_next = int(d.get("xp_to_next", xp_to_next))
	_enforce_level_cap_state()
	class_id = String(d.get("class_id", d.get("class", class_id)))

	max_hp = int(d.get("max_hp", max_hp))
	current_hp = int(d.get("current_hp", current_hp))
	attack = int(d.get("attack", attack))
	defense = int(d.get("defense", defense))

	max_mana = int(d.get("max_mana", max_mana))
	mana = int(d.get("mana", mana))

	if c_resource != null:
		c_resource.configure_from_class_id(class_id)
		if c_resource.resource_type == "rage":
			var saved_value: int = int(d.get("resource", d.get("rage", c_resource.resource)))
			c_resource.max_resource = c_resource.rage_max_value
			c_resource.resource = clamp(saved_value, 0, c_resource.max_resource)
		else:
			c_resource.sync_from_owner_fields_if_mana()

	# Primary stats (new system, backward compatible)
	if c_stats != null:
		c_stats.apply_primary_data(d)
	faction_id = String(d.get("faction", faction_id))
	_apply_class_visual()

	# inventory snapshot
	var inv_v: Variant = d.get("inventory", null)
	if inv_v is Dictionary:
		c_inv.apply_inventory_snapshot(inv_v as Dictionary)

	var equip_v: Variant = d.get("equipment", null)
	if equip_v is Dictionary:
		c_equip.apply_equipment_snapshot(equip_v as Dictionary)
	else:
		c_equip.apply_equipment_snapshot({})

	var buffs_v: Variant = d.get("buffs", [])
	if buffs_v is Array:
		c_buffs.apply_buffs_snapshot(buffs_v as Array)
	if c_buffs != null and c_buffs.has_method("set_spirits_aid_cooldown_left"):
		c_buffs.call("set_spirits_aid_cooldown_left", float(d.get("spirits_aid_cd_left", 0.0)))
	if c_buffs != null and c_buffs.has_method("set_defensive_reflexes_cooldown_left"):
		c_buffs.call("set_defensive_reflexes_cooldown_left", float(d.get("defensive_reflexes_cd_left", 0.0)))

	var spellbook_v: Variant = d.get("spellbook", null)
	if spellbook_v is Dictionary and c_spellbook != null:
		var sdata := spellbook_v as Dictionary
		c_spellbook.learned_ranks = sdata.get("learned_ranks", {}) as Dictionary
		c_spellbook.loadout_slots = _to_string_array(sdata.get("loadout_slots", ["", "", "", "", ""]))
		c_spellbook.aura_active = String(sdata.get("aura_active", ""))
		c_spellbook.stance_active = String(sdata.get("stance_active", ""))
		c_spellbook.buff_slots = _to_string_array(sdata.get("buff_slots", [""]))
		c_spellbook._ensure_slots()
		c_spellbook.auto_assign_active_slots_from_learned()
		_apply_spellbook_passives()
	if cast_bar != null:
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
	if c_spellbook != null and ((not (spellbook_v is Dictionary)) or c_spellbook.learned_ranks.is_empty()):
		_grant_starter_abilities()

	# Derived stats must be recalculated after primaries + buffs are in place
	if c_stats != null:
		c_stats.recalculate_for_level(false)
	_enforce_level_cap_state()

	# защита от “вошёл мёртвым”
	is_dead = false


func _resolve_model_scene_for_class(id: String) -> PackedScene:
	match id.strip_edges().to_lower():
		"mage":
			return MAGE_MODEL_SCENE
		"paladin":
			return PALADIN_MODEL_SCENE
		"priest":
			return PRIEST_MODEL_SCENE
		"shaman":
			return SHAMAN_MODEL_SCENE
		"hunter":
			return HUNTER_MODEL_SCENE
		"warrior":
			return WARRIOR_MODEL_SCENE
		_:
			return WARRIOR_MODEL_SCENE

func _apply_class_visual() -> void:
	if visual_root == null:
		return
	if _character_model != null and is_instance_valid(_character_model):
		_character_model.queue_free()
		_character_model = null
	var model_scene := _resolve_model_scene_for_class(class_id)
	if model_scene == null:
		return
	var inst := model_scene.instantiate()
	if inst == null:
		return
	visual_root.add_child(inst)
	_character_model = inst
	_pending_corpse_pose_snapshot = {}
	_corpse_spawned_for_current_death = false
	if _character_model != null and _character_model.has_signal("death_pose_ready"):
		var cb := Callable(self, "_on_model_death_pose_ready")
		if not _character_model.is_connected("death_pose_ready", cb):
			_character_model.connect("death_pose_ready", cb)
	_apply_collision_profile_from_model(inst)
	_apply_overlay_profile_from_model(inst)
	_update_model_motion(Vector2.ZERO)

func _update_model_motion(dir: Vector2) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_move_direction"):
		_character_model.call("set_move_direction", dir)

func _set_model_stunned(active: bool) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_stunned"):
		_character_model.call("set_stunned", active)

func play_model_hurt() -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_hurt"):
		_character_model.call("play_hurt")

func play_model_death() -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_death"):
		_character_model.call("play_death")

func begin_death_sequence() -> void:
	if _corpse_spawned_for_current_death:
		return
	emit_signal("carrier_effects_stop")
	play_model_death()
	var timer := get_tree().create_timer(0.9)
	timer.timeout.connect(_spawn_player_corpse_after_death_animation, CONNECT_ONE_SHOT)

func get_corpse_pose_snapshot() -> Dictionary:
	if not _pending_corpse_pose_snapshot.is_empty():
		return _pending_corpse_pose_snapshot
	if _character_model != null and is_instance_valid(_character_model) and _character_model.has_method("build_corpse_pose_snapshot"):
		var v: Variant = _character_model.call("build_corpse_pose_snapshot")
		if v is Dictionary:
			return v as Dictionary
	return {}

func _on_model_death_pose_ready(snapshot: Dictionary) -> void:
	_pending_corpse_pose_snapshot = snapshot.duplicate(true)
	_spawn_player_corpse_after_death_animation()

func _spawn_player_corpse_after_death_animation() -> void:
	if _corpse_spawned_for_current_death:
		return
	if get_parent() != null:
		var corpse: Corpse = DeathPipeline.spawn_corpse(get_parent(), global_position)
		if corpse != null:
			corpse.setup_owner_snapshot(self, get_instance_id())
			corpse.owner_is_player = true
			var pose := get_corpse_pose_snapshot()
			if not pose.is_empty() and corpse.has_method("apply_pose_snapshot"):
				corpse.call("apply_pose_snapshot", pose)
	if _character_model != null and is_instance_valid(_character_model) and _character_model.has_method("hide_model_for_corpse"):
		_character_model.call("hide_model_for_corpse")
	_corpse_spawned_for_current_death = true

func play_model_combat_action(action_kind: String, is_moving_now: bool = false) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("play_combat_action"):
		_character_model.call("play_combat_action", action_kind, is_moving_now, class_id)

func face_model_to_world_position(world_position: Vector2) -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_facing_to_world_position"):
		_character_model.call("set_facing_to_world_position", world_position)

func restore_model_facing_to_movement() -> void:
	if _character_model == null or not is_instance_valid(_character_model):
		return
	if _character_model.has_method("set_move_direction"):
		_character_model.call("set_move_direction", velocity)

func _apply_collision_profile_from_model(model: Node) -> void:
	if model == null or not is_instance_valid(model):
		return
	if not model.has_method("get_collision_profile"):
		return
	var profile_v: Variant = model.call("get_collision_profile")
	if not (profile_v is Dictionary):
		return
	var profile := profile_v as Dictionary

	if world_collision != null:
		var world_shape_v: Variant = profile.get("world_collision_shape", null)
		if world_shape_v is Shape2D:
			world_collision.shape = (world_shape_v as Shape2D).duplicate(true)
		var world_offset_v: Variant = profile.get("world_collision_offset", world_collision.position)
		if world_offset_v is Vector2:
			world_collision.position = world_offset_v as Vector2
		var world_rot_v: Variant = profile.get("world_collision_rotation", world_collision.rotation)
		if world_rot_v is float or world_rot_v is int:
			world_collision.rotation = float(world_rot_v)
	_sync_y_sort_origin_from_world_collider()

	if body_hitbox_shape != null:
		var body_shape_v: Variant = profile.get("body_hitbox_shape", null)
		if body_shape_v is Shape2D:
			body_hitbox_shape.shape = (body_shape_v as Shape2D).duplicate(true)
		var body_offset_v: Variant = profile.get("body_hitbox_offset", body_hitbox_shape.position)
		if body_offset_v is Vector2:
			body_hitbox_shape.position = body_offset_v as Vector2
		var body_rot_v: Variant = profile.get("body_hitbox_rotation", body_hitbox_shape.rotation)
		if body_rot_v is float or body_rot_v is int:
			body_hitbox_shape.rotation = float(body_rot_v)

	if interaction_shape != null and interaction_shape.shape is CircleShape2D:
		var interaction_circle := interaction_shape.shape as CircleShape2D
		interaction_circle.radius = max(1.0, float(profile.get("interaction_radius", interaction_circle.radius)))
		var interaction_offset_v: Variant = profile.get("interaction_offset", interaction_shape.position)
		if interaction_offset_v is Vector2:
			interaction_shape.position = interaction_offset_v as Vector2

func _apply_overlay_profile_from_model(model: Node) -> void:
	cast_bar = null
	hp_bar = null
	target_marker = null
	model_highlight = null
	overlay_bars_widget = null
	if model == null or not is_instance_valid(model):
		return
	overlay_bars_widget = _find_first_by_type(model, OverlayBarsWidget) as OverlayBarsWidget
	cast_bar = _find_first_by_type(model, CastBarWidget) as CastBarWidget
	hp_bar = _find_first_by_type(model, HealthBarWidget) as HealthBarWidget
	var marker_node := model.get_node_or_null("OverlayProfile/TargetMarker")
	if marker_node is CanvasItem:
		target_marker = marker_node as CanvasItem
		if visual_root != null and is_instance_valid(visual_root):
			_apply_overlay_layer_offsets(int(visual_root.z_index))
	var highlight_node := model.get_node_or_null("OverlayProfile/ModelHighlight")
	if highlight_node is CanvasItem:
		model_highlight = highlight_node as CanvasItem
	if overlay_bars_widget != null:
		overlay_bars_widget.set_show_name(true)
		overlay_bars_widget.set_display_name(get_display_name())
	var viewer_faction: String = faction_id
	var local_player: Node = NodeCache.get_player(get_tree())
	if local_player != null and local_player.has_method("get_faction_id"):
		viewer_faction = String(local_player.call("get_faction_id"))
	var player_color: Color = OVERLAY_COLORS.hp_color_for_faction_target(viewer_faction, faction_id)
	if hp_bar != null:
		hp_bar.set_fill_color(player_color)
	if overlay_bars_widget != null:
		overlay_bars_widget.set_name_visual(player_color, Color(0.0, 0.0, 0.0, 1.0), 3)
	_update_model_hp_bar()
	if cast_bar != null and not c_ability_caster.is_casting():
		cast_bar.set_cast_visible(false)
		cast_bar.set_progress01(0.0)
		cast_bar.set_icon_texture(null)
	if model_highlight != null:
		model_highlight.visible = false


func _update_model_hp_bar() -> void:
	if hp_bar == null:
		return
	if max_hp <= 0:
		return
	hp_bar.set_progress01(clamp(float(current_hp) / float(max_hp), 0.0, 1.0))

func _grant_starter_abilities() -> void:
	if c_spellbook == null:
		return
	var db := get_node_or_null("/root/AbilityDB") as AbilityDatabase
	if db == null:
		return
	if not db.is_ready:
		if not _starter_grant_waiting_for_db and not db.initialized.is_connected(_on_ability_db_initialized_for_starters):
			_starter_grant_waiting_for_db = true
			db.initialized.connect(_on_ability_db_initialized_for_starters, CONNECT_ONE_SHOT)
		return
	_starter_grant_waiting_for_db = false
	var starters := db.get_starter_ability_ids_for_class(class_id)
	if starters.is_empty():
		return
	var granted_any: bool = false
	for entry in starters:
		var ability_id := String(entry)
		if ability_id == "":
			continue
		var max_rank: int = int(max(1, db.get_max_rank(ability_id)))
		var before_rank := int(c_spellbook.learned_ranks.get(ability_id, 0))
		var after_rank := c_spellbook.learn_next_rank(ability_id, max_rank)
		if after_rank > before_rank:
			granted_any = true
	if granted_any:
		c_spellbook.auto_assign_active_slots_from_learned()
		_request_save("starter_abilities_lvl1")

func _on_ability_db_initialized_for_starters() -> void:
	_starter_grant_waiting_for_db = false
	_grant_starter_abilities()


func export_character_data() -> Dictionary:
	# берём основу из AppState (там id/name/class и т.д.)
	var base: Dictionary = AppState.selected_character_data.duplicate(true)

	base["faction"] = faction_id
	base["class_id"] = class_id
	base["level"] = level
	base["xp"] = xp
	base["xp_to_next"] = xp_to_next

	base["max_hp"] = max_hp
	base["current_hp"] = current_hp
	base["attack"] = attack
	base["defense"] = defense

	base["max_mana"] = max_mana
	base["mana"] = mana

	if c_resource != null:
		if c_resource.resource_type == "mana":
			c_resource.sync_from_owner_fields_if_mana()
		base["resource_type"] = c_resource.resource_type
		base["max_resource"] = c_resource.max_resource
		base["resource"] = c_resource.resource
		if c_resource.resource_type == "rage":
			base["max_rage"] = c_resource.max_resource
			base["rage"] = c_resource.resource

	# Primary stats (saved)
	if c_stats != null:
		base.merge(c_stats.export_primary_data(), true)

	# inventory
	base["inventory"] = c_inv.get_inventory_snapshot()
	base["equipment"] = c_equip.get_equipment_snapshot()

	# position
	base["pos"] = {"x": float(global_position.x), "y": float(global_position.y)}	

	# buffs
	base["buffs"] = c_buffs.get_buffs_snapshot()
	if c_buffs != null and c_buffs.has_method("get_spirits_aid_cooldown_left"):
		base["spirits_aid_cd_left"] = float(c_buffs.call("get_spirits_aid_cooldown_left"))
	if c_buffs != null and c_buffs.has_method("get_defensive_reflexes_cooldown_left"):
		base["defensive_reflexes_cd_left"] = float(c_buffs.call("get_defensive_reflexes_cooldown_left"))
	if c_spellbook != null:
		base["spellbook"] = {
			"learned_ranks": c_spellbook.learned_ranks,
			"loadout_slots": c_spellbook.loadout_slots,
			"aura_active": c_spellbook.aura_active,
			"stance_active": c_spellbook.stance_active,
			"buff_slots": c_spellbook.buff_slots
		}

	return base



func get_display_name() -> String:
	var app_state := get_node_or_null("/root/AppState")
	if app_state != null:
		var data_v: Variant = app_state.get("selected_character_data")
		if data_v is Dictionary:
			var n := String((data_v as Dictionary).get("name", "")).strip_edges()
			if n != "":
				return n
	return String(name).strip_edges()

func get_faction_id() -> String:
	return faction_id

func _to_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in value:
			out.append(String(entry))
	return out

func _find_first_by_type(root: Node, script_type: Variant) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	for child in root.get_children():
		if is_instance_of(child, script_type):
			return child
		if child is Node:
			var nested := _find_first_by_type(child, script_type)
			if nested != null:
				return nested
	return null
