class_name Level
extends Node3D

## Texture of the level
@export var level_map: Texture2D

## Ground mesh
@onready var ground = $ground

## Return global AABB for ground mesh
func get_world_box() -> AABB:
	return ground.get_aabb() * ground.global_transform

func _ready():
	_setup_ground_shader()

func _setup_ground_shader():
	var mat = ground.material_override
	if mat is ShaderMaterial:
		mat.set_shader_parameter("level_map", level_map)
