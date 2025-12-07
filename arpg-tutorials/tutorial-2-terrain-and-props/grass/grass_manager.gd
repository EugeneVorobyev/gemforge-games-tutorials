##
## Component will control grass chunks
##
class_name GrassManager
extends Node3D

# Vectors to search for nearest chunks
const ndx: Array[Vector2i] = [
	Vector2i(1,-1),
	Vector2i(1,0),
	Vector2i(1,1),
	Vector2i(0,-1),
	Vector2i(0,1),
	Vector2i(-1,1),
	Vector2i(-1,0),
	Vector2i(-1,-1),
]

##==============================================================================
## Class stores the data for a grass chunk
##==============================================================================
class GrassChunk:
	## Identity vector (x, y) for a chunk in the grid
	var id: Vector2i
	## Real world position of the chunk
	var position: Vector2
	## The points of grass spawn
	var transforms: Array[Transform3D]
	## The mesh that will hold grass instances for the chunk
	var meshInstance: MultiMeshInstance3D
	## If the chunk already populated
	var populated: bool = false
	
	func _init(x: int, z: int):
		id = Vector2i(x, z)
				
	## Returns is this chunk has been activated
	func is_active() -> bool:
		return meshInstance != null
		
	func log():
		return "GrassChunk[id=(%d,%d), pos=(%d,%d)]" % [id.x, id.y, position.x, position.y]
##==============================================================================

const world_to_uv_scale = 0.01

## Level mesh, to understand how many chunks we need
@export var level: Level

## Grass mesh to scatter
@export var grass: MeshInstance3D

## Grass material
@export var grass_material: ShaderMaterial

## Size of a grass chunk
@export var size: int = 50

## Number of instances for chunk
@export var instance_count: int = 100

## Hold the offset of level object in the world
var world_offset: Vector2

## Holds the world chunks for grass
var chunks: Dictionary[Vector2i, GrassChunk] = {}

func _ready():
	if not level:
		return
	
	if not grass:
		push_warning("There is no grass mesh assigned.")
		return
		
	world_offset.x = level.position.x
	world_offset.y = level.position.z
	_update_chunks()
	
##
## This function will calculate the size of level
## and generate chunks of [code]MultimeshInstance3D[/code] type
## to hold grass instances
##
func _update_chunks():
	# What we want is to generate only chunks close
	# to the player position, as we don't need grass somewhere
	# on the level far away for now

	# 1. Generate a grid
	_generate_chunks()
	
	# 2. Get the set of chunks to populate with grass
	var chunk_keys = _get_close_chunks()

	# 3. Generate meshes for unpopulated chunks
	# 4. Scatter grass for unpopulated chunks
	for key in chunk_keys:
		print(chunks[key].log())
		var ch = chunks[key]
		if not ch.is_active():
			activate_chunk(chunks[key])

## Calculate number of chunks and generate them
## We use ceil to make sure the level completely covered by chunks
func _generate_chunks():
	var level_box := level.get_world_box()
	var chunks_x := ceili(level_box.size.x / size)
	var chunks_z := ceili(level_box.size.z / size)
	for cx in chunks_x:
		for cz in chunks_z:
			if not chunks.has(Vector2i(cx, cz)):			
				var ch := GrassChunk.new(cx, cz)
				ch.position	= Vector2(
					cx*size + world_offset.x, 
					cz*size + world_offset.y)				
				chunks.set(ch.id, ch)

## Activate multimesh instance to store grass
func activate_chunk(c: GrassChunk):
	# Create a multi mesh instance	
	var meshInstance = MultiMeshInstance3D.new()
	meshInstance.name = "ChuckMesh_%d_%d" % [c.id.x, c.id.y]
	meshInstance.position = Vector3(c.position.x, 0, c.position.y)
	meshInstance.material_override = grass_material
	
	# Setup a mesh for grass and how many we need
	var chunk_mesh = MultiMesh.new()
	chunk_mesh.mesh = grass.mesh
	chunk_mesh.transform_format = MultiMesh.TRANSFORM_3D
	chunk_mesh.use_colors = true
	chunk_mesh.instance_count = instance_count
	
	# Populate mesh with scattered items
	meshInstance.multimesh = chunk_mesh
	var places = scatter_transforms(size, c.position, instance_count)
	for t in instance_count:
		meshInstance.multimesh.set_instance_transform(t, places[t])
		meshInstance.multimesh.set_instance_color(t, random_green_yellow())
	
	# Place multi mesh to the level
	level.add_child(meshInstance)

## Finds the near chunks for target and return the list of keys
## TODO: add `distance: int` parameter and recursively search chunk of larger distance from player
func _get_close_chunks() -> Array[Vector2i]:
	# If there is active player get it's position otherwise use (0,0)
	var target_pos = Vector2(0, 0)
	var player = PlayerManager.get_player()
	if player:
		target_pos = Vector2(player.position.x, player.position.z)
	
	# The main chunk where player is located
	var target_chunk = _get_position_chunk_key(target_pos)

	# Store all found chunks
	var found_chunks: Array[Vector2i] = []
	found_chunks.append(target_chunk)
	
	# Calculate nearest indexes by distance
	# for now only closest or with distance=1 cell from player
	for near_vec in ndx:
		var target_vec = target_chunk + near_vec
		if target_vec.x >= 0 and target_vec.y >= 0:
			found_chunks.append(target_vec)	
	
	return found_chunks
	
## Scatters instances of grass for chunk
func scatter_transforms(chunk_size: int, pos: Vector2, count: int) -> Array[Transform3D]:
	var img: Image = level.level_map.get_image()
	var level_box := level.get_world_box()

	var result: Array[Transform3D] = []
	result.resize(count)

	for i in count:
		var x = randf_range(0.0, chunk_size)
		var y = randf_range(0.0, chunk_size)
		
		# adjust for chunk position
		var world_x = pos.x + x
		var world_y = pos.y + y

		# convert world → [0..1] UV
		var u = world_x / level_box.size.x
		var v = world_y / level_box.size.z
		
		# pick color from texture
		var px := int(u * img.get_width())
		var py := int(v * img.get_height())
		var col: Color = img.get_pixel(px, py)
		var density := col.r
		if density > 0.8: 
			continue
		
		# Usefull method to debug, but make sure Texture is NOT compressed
		# img.set_pixel(px, py, Color(1, 0, 0, 1))
		
		var s = randf_range(0.8, 1.5)
		var target_pos = Vector3(x, 0.1, y)

		var t := Transform3D()
		t = t.scaled(Vector3(s, s, s))
		t = t.translated(target_pos)

		result[i] = t

	return result

## Returns the chunk index by position
func _get_position_chunk_key(pos: Vector2) -> Vector2i:
	var idx_x := ceili((pos.x + world_offset.x)/ size)
	var idx_y := ceili((pos.y + world_offset.y)/ size)
	return Vector2i(idx_x, idx_y)

## Converts world position into a chunk index
func world_to_chunk(pos_xz: Vector2) -> Vector2i:
	var rel := pos_xz - world_offset
	var ix := int(floor(rel.x / size))
	var iz := int(floor(rel.y / size))
	return Vector2i(ix, iz)
	
func random_green_yellow() -> Color:
	var t := randf()  # 0..1
	return Color(lerp(0.0, 1.0, t), 1.0, 0.0, 1.0)
