extends Node

const LOGIN_SCENE: String = "res://ui/flow/LoginUI.tscn"
const CHARACTER_SELECT_SCENE: String = "res://ui/flow/CharacterSelectUI.tscn"
const WORLD_SCENE: String = "res://game/scenes/Main.tscn"


func go_login() -> void:
	get_tree().change_scene_to_file(LOGIN_SCENE)


func go_character_select() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func go_world() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)
