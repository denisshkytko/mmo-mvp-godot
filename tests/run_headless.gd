extends SceneTree

var _passes: int = 0
var _fails: int = 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _run_tests()
	var total := _passes + _fails
	print("[SUMMARY] PASS: %d FAIL: %d TOTAL: %d" % [_passes, _fails, total])
	quit(0 if _fails == 0 else 1)


func _run_tests() -> void:
	await _run_test("DataDB loaded", _test_data_db)
	await _run_test("SaveSystem save + backup", _test_save_system)
	await _run_test("LootSystem loot generation", _test_loot_system)
	await _run_test("AppState transitions", _test_app_state)


func _run_test(name: String, fn: Callable) -> void:
	var result: Dictionary = await fn.call()
	var ok: bool = bool(result.get("ok", false))
	var reason: String = String(result.get("reason", ""))
	if ok:
		_pass(name)
	else:
		_fail(name, reason)


func _pass(name: String) -> void:
	_passes += 1
	print("[PASS] %s" % name)


func _fail(name: String, reason: String) -> void:
	_fails += 1
	print("[FAIL] %s: %s" % [name, reason])


func _test_data_db() -> Dictionary:
	var db := _get_autoload("/root/DataDB")
	if db == null:
		return _result(false, "DataDB autoload missing")
	await _wait_for_db(db)
	var items_size := 0
	var mobs_size := 0
	if db.has_variable("items"):
		items_size = int(db.items.size())
	if db.has_variable("mobs"):
		mobs_size = int(db.mobs.size())
	if items_size <= 0:
		return _result(false, "items db is empty")
	if mobs_size <= 0:
		return _result(false, "mobs db is empty")
	return _result(true)


func _test_save_system() -> Dictionary:
	var save_system := _get_autoload("/root/SaveSystem")
	if save_system == null:
		return _result(false, "SaveSystem autoload missing")
	if not save_system.has_method("_atomic_write_json"):
		return _result(false, "SaveSystem missing _atomic_write_json")

	var test_dir := "user://mmo_mvp/tests/"
	DirAccess.make_dir_recursive_absolute(test_dir)

	var test_id := "headless_smoke_%d" % int(Time.get_unix_time_from_system())
	var save_path := test_dir + test_id + ".json"
	var payload := {
		"id": test_id,
		"name": "Headless Smoke",
		"class": "adventurer",
		"level": 1
	}

	var ok_first: bool = bool(save_system.call("_atomic_write_json", save_path, payload))
	if not ok_first:
		_cleanup_save_artifacts(save_path)
		return _result(false, "failed to write initial save")
	if not FileAccess.file_exists(save_path):
		_cleanup_save_artifacts(save_path)
		return _result(false, "save file missing after first write")

	payload["level"] = 2
	var ok_second: bool = bool(save_system.call("_atomic_write_json", save_path, payload))
	if not ok_second:
		_cleanup_save_artifacts(save_path)
		return _result(false, "failed to overwrite save")

	var bak_path := save_path + ".bak"
	if not FileAccess.file_exists(bak_path):
		_cleanup_save_artifacts(save_path)
		return _result(false, "backup file not created")

	_cleanup_save_artifacts(save_path)
	return _result(true)


func _test_loot_system() -> Dictionary:
	var loot_system := _get_autoload("/root/LootSystem")
	if loot_system == null:
		return _result(false, "LootSystem autoload missing")
	var db := _get_autoload("/root/DataDB")
	if db == null:
		return _result(false, "DataDB autoload missing")
	await _wait_for_db(db)

	var profile_path := "res://core/loot/profiles/loot_profile_aggressive_default.tres"
	var profile := ResourceLoader.load(profile_path)
	if profile == null:
		return _result(false, "loot profile not found: %s" % profile_path)
	if not loot_system.has_method("generate_loot_from_profile"):
		return _result(false, "LootSystem missing generate_loot_from_profile")

	for _i in range(150):
		var loot: Dictionary = loot_system.call("generate_loot_from_profile", profile, 10, {})
		var slots: Array = loot.get("slots", [])
		for slot in slots:
			if not (slot is Dictionary):
				return _result(false, "loot slot is not a dictionary")
			var item_id := String(slot.get("id", ""))
			if item_id == "":
				return _result(false, "loot slot missing item id")
			if not db.has_method("has_item") or not bool(db.call("has_item", item_id)):
				return _result(false, "loot item not found in DataDB: %s" % item_id)
			var count := int(slot.get("count", 0))
			if count <= 0:
				return _result(false, "loot item count <= 0 for %s" % item_id)
			if db.has_method("get_item_stack_max"):
				var stack_max := int(db.call("get_item_stack_max", item_id))
				if stack_max > 0 and count > stack_max:
					return _result(false, "loot count %d exceeds stack_max %d for %s" % [count, stack_max, item_id])
	return _result(true)


func _test_app_state() -> Dictionary:
	var app_state := _get_autoload("/root/AppState")
	if app_state == null:
		return _result(false, "AppState autoload missing")
	if not app_state.has_method("set_state"):
		return _result(false, "AppState missing set_state")

	var original_state := int(app_state.current_state)
	var ok := true

	app_state.current_state = AppState.FlowState.BOOT
	ok = ok and bool(app_state.call("set_state", AppState.FlowState.LOGIN))
	ok = ok and bool(app_state.call("set_state", AppState.FlowState.CHARACTER_SELECT))
	ok = ok and bool(app_state.call("set_state", AppState.FlowState.WORLD))
	ok = ok and bool(app_state.call("set_state", AppState.FlowState.CHARACTER_SELECT))
	if not ok:
		app_state.current_state = original_state
		return _result(false, "legal transition path failed")

	app_state.current_state = AppState.FlowState.LOGIN
	var illegal_ok := bool(app_state.call("set_state", AppState.FlowState.WORLD))
	if illegal_ok or int(app_state.current_state) != AppState.FlowState.LOGIN:
		app_state.current_state = original_state
		return _result(false, "illegal transition LOGIN->WORLD not blocked")

	app_state.current_state = AppState.FlowState.BOOT
	illegal_ok = bool(app_state.call("set_state", AppState.FlowState.WORLD))
	if illegal_ok or int(app_state.current_state) != AppState.FlowState.BOOT:
		app_state.current_state = original_state
		return _result(false, "illegal transition BOOT->WORLD not blocked")

	app_state.current_state = original_state
	return _result(true)


func _get_autoload(path: String) -> Node:
	var root := get_root()
	if root == null:
		return null
	return root.get_node_or_null(path)


func _wait_for_db(db: Node) -> void:
	if db.has_variable("is_ready") and bool(db.is_ready):
		return
	if db.has_signal("initialized"):
		await db.initialized


func _cleanup_save_artifacts(save_path: String) -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	var bak_path := save_path + ".bak"
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)
	var tmp_path := save_path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)


func _result(ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason}
