extends Node2D
class_name SpawnPoint

# Единая точка спавна для всех типов групп.
# guard_facing используется в режиме Guard (задел на будущее).
@export_enum("Default", "Up", "Right", "Down", "Left") var guard_facing: int = 0

# (на будущее) произвольный тег/вариант, если понадобится.
@export var tag: String = ""
