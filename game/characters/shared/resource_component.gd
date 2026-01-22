extends Node
class_name ResourceComponent

const PROG := preload("res://core/stats/progression.gd")

var owner_entity: Node = null
var resource_type: String = "mana"
var max_resource: int = 1
var resource: int = 1
var label_name: String = "Mana"

@export var rage_max_value: int = 100
@export var rage_gain_on_deal_flat: int = 2
@export var rage_gain_on_take_flat: int = 3
@export var rage_decay_delay_sec: float = 3.0
@export var rage_decay_per_sec: float = 10.0

var _last_combat_time_sec: float = -999999.0

func setup(owner: Node) -> void:
	owner_entity = owner

func set_type(t: String) -> void:
	resource_type = t
	label_name = "Rage" if t == "rage" else "Mana"

func configure_from_class_id(class_id: String) -> void:
	var t: String = "mana"
	if PROG != null:
		t = String(PROG.get_resource_type_for_class(class_id))
	set_type(t)

	if resource_type == "rage":
		max_resource = rage_max_value
		resource = clamp(resource, 0, max_resource)
		return

	sync_from_owner_fields_if_mana()
	max_resource = max(1, int(max_resource))
	resource = clamp(int(resource), 0, max_resource)

func sync_from_owner_fields_if_mana() -> void:
	if resource_type != "mana":
		return
	if owner_entity == null:
		return
	if owner_entity.get("max_mana") == null or owner_entity.get("mana") == null:
		return
	max_resource = max(1, int(owner_entity.get("max_mana")))
	resource = clamp(int(owner_entity.get("mana")), 0, max_resource)

func sync_to_owner_fields_if_mana() -> void:
	if resource_type != "mana":
		return
	if owner_entity == null:
		return
	if owner_entity.get("max_mana") == null or owner_entity.get("mana") == null:
		return
	owner_entity.set("max_mana", max_resource)
	owner_entity.set("mana", resource)

func mark_in_combat() -> void:
	_last_combat_time_sec = float(Time.get_ticks_msec()) / 1000.0

func on_damage_dealt() -> void:
	mark_in_combat()
	if resource_type == "rage":
		add(rage_gain_on_deal_flat)

func on_damage_taken() -> void:
	mark_in_combat()
	if resource_type == "rage":
		add(rage_gain_on_take_flat)

func add(delta: int) -> void:
	resource = clamp(resource + delta, 0, max_resource)
	if resource_type == "mana":
		sync_to_owner_fields_if_mana()

func set_full() -> void:
	resource = max_resource
	if resource_type == "mana":
		sync_to_owner_fields_if_mana()

func set_empty() -> void:
	resource = 0
	if resource_type == "mana":
		sync_to_owner_fields_if_mana()

func get_text() -> String:
	return "%s %d/%d" % [label_name, resource, max_resource]

func _process(delta: float) -> void:
	if resource_type != "rage":
		return
	if resource <= 0:
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	if (now_sec - _last_combat_time_sec) < rage_decay_delay_sec:
		return
	var decay_amount: int = int(floor(rage_decay_per_sec * delta))
	if decay_amount <= 0:
		return
	resource = max(0, resource - decay_amount)
