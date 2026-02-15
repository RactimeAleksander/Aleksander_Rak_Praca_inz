extends Node3D

@onready var multi_mesh_instance: MultiMeshInstance3D = $MultiMeshInstance3D

var voxels_dict = {} 
var free_indices = [] 
var dropped_items = []
var static_body: StaticBody3D
var highlight_mesh: MeshInstance3D

var audio_break: AudioStreamPlayer
var audio_place: AudioStreamPlayer
var audio_pickup: AudioStreamPlayer

func _notification(what):
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if voxels_dict.size() > 0:
			clear_world()

var sounds = {
	"WOOD": {
		"break": "res://sounds/wood_break.ogg",
		"walk": ["res://sounds/wood_walk1.ogg", "res://sounds/wood_walk2.ogg"]
	},
	"DIRT": {
		"break": "res://sounds/dirt_break.ogg",
		"walk": ["res://sounds/dirt_walk1.ogg", "res://sounds/dirt_walk2.ogg"]
	},
	"GRASS": {
		"break": "res://sounds/grass_break.ogg",
		"walk": ["res://sounds/grass_walk1.ogg", "res://sounds/grass_walk2.ogg", "res://sounds/grass_walk3.ogg"]
	},
	"STONE": {
		"break": "res://sounds/stone_break.ogg",
		"walk": ["res://sounds/stone_walk1.ogg", "res://sounds/stone_walk2.ogg", "res://sounds/stone_walk3.ogg"]
	},
	"LEAVES": {
		"break": "res://sounds/grass_break.ogg",
		"walk": ["res://sounds/leaf_walk1.ogg", "res://sounds/leaf_walk2.ogg"]
	}
}

const BLOCKS = {
	"EMPTY":  {"color": Color(0,0,0,0), "hardness": 0, "name": ""},
	"GRASS":  {"color": Color(0.35, 0.65, 0.2), "hardness": 1.0, "name": "Trawa"},
	"DIRT":   {"color": Color(0.4, 0.25, 0.15),  "hardness": 0.8, "name": "Ziemia"},
	"WOOD":   {"color": Color(0.3, 0.2, 0.1),   "hardness": 2.0, "name": "Drewno"},
	"LEAVES": {"color": Color(0.1, 0.5, 0.1),   "hardness": 0.2, "name": "Liście"},
	"STONE":  {"color": Color(0.5, 0.5, 0.5),   "hardness": 3.0, "name": "Kamień"}
}

const CHUNK_SIZE = 16

func _ready() -> void:
	static_body = StaticBody3D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)
	init_mesh()
	init_highlight()
	init_audio()
	generate_world_fast(100)

func init_mesh():
	var mm = multi_mesh_instance.multimesh
	mm.instance_count = 0
	mm.use_colors = true
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	if mm.mesh: mm.mesh.surface_set_material(0, mat)

func init_highlight():
	highlight_mesh = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	highlight_mesh.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.no_depth_test = true
	
	highlight_mesh.material_override = mat
	highlight_mesh.visible = false
	highlight_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(highlight_mesh)

func init_audio():
	audio_break = AudioStreamPlayer.new()
	audio_break.bus = "SFX"
	add_child(audio_break)
	
	audio_place = AudioStreamPlayer.new()
	audio_place.bus = "SFX"
	add_child(audio_place)
	
	audio_pickup = AudioStreamPlayer.new()
	audio_pickup.bus = "SFX"
	add_child(audio_pickup)

func play_sound(sound_type: String, block_type: String):
	if not sounds.has(block_type):
		return
	
	var data = sounds[block_type]
	var path = ""
	
	match sound_type:
		"break":
			if data.has("break"):
				path = data.break
				if FileAccess.file_exists(path):
					audio_break.stream = load(path)
					audio_break.play()
		"place":
			path = "res://sounds/block_place.ogg"
			if FileAccess.file_exists(path):
				audio_place.stream = load(path)
				audio_place.play()
		"walk":
			if data.has("walk"):
				var sounds_arr = data.walk
				path = sounds_arr[randi() % sounds_arr.size()]
				return path
	
	return path

func draw_outline(mesh: ImmediateMesh, corners: Array):
	mesh.surface_add_vertex(corners[0])
	mesh.surface_add_vertex(corners[1])
	mesh.surface_add_vertex(corners[1])
	mesh.surface_add_vertex(corners[2])
	mesh.surface_add_vertex(corners[2])
	mesh.surface_add_vertex(corners[3])
	mesh.surface_add_vertex(corners[3])
	mesh.surface_add_vertex(corners[0])

func draw_highlight_box(pos: Vector3, normal: Vector3):
	var mesh = highlight_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var offset = 0.503
	var n = Vector3.ZERO
	
	if abs(normal.x) > abs(normal.y) and abs(normal.x) > abs(normal.z):
		n.x = sign(normal.x)
	elif abs(normal.y) > abs(normal.z):
		n.y = sign(normal.y)
	else:
		n.z = sign(normal.z)
	
	normal = n
	var c = []
	
	if normal == Vector3.UP:
		c = [
			pos + Vector3(-offset, offset, -offset),
			pos + Vector3(offset, offset, -offset),
			pos + Vector3(offset, offset, offset),
			pos + Vector3(-offset, offset, offset)
		]
	elif normal == Vector3.DOWN:
		c = [
			pos + Vector3(-offset, -offset, -offset),
			pos + Vector3(offset, -offset, -offset),
			pos + Vector3(offset, -offset, offset),
			pos + Vector3(-offset, -offset, offset)
		]
	elif normal == Vector3.LEFT:
		c = [
			pos + Vector3(-offset, -offset, -offset),
			pos + Vector3(-offset, offset, -offset),
			pos + Vector3(-offset, offset, offset),
			pos + Vector3(-offset, -offset, offset)
		]
	elif normal == Vector3.RIGHT:
		c = [
			pos + Vector3(offset, -offset, -offset),
			pos + Vector3(offset, offset, -offset),
			pos + Vector3(offset, offset, offset),
			pos + Vector3(offset, -offset, offset)
		]
	elif normal == Vector3.FORWARD:
		c = [
			pos + Vector3(-offset, -offset, offset),
			pos + Vector3(offset, -offset, offset),
			pos + Vector3(offset, offset, offset),
			pos + Vector3(-offset, offset, offset)
		]
	elif normal == Vector3.BACK:
		c = [
			pos + Vector3(-offset, -offset, -offset),
			pos + Vector3(offset, -offset, -offset),
			pos + Vector3(offset, offset, -offset),
			pos + Vector3(-offset, offset, -offset)
		]
	
	if c.size() > 0:
		draw_outline(mesh, c)
	
	mesh.surface_end()

func clear_world():
	voxels_dict.clear()
	free_indices.clear()
	
	for item in dropped_items:
		if item.has("node") and is_instance_valid(item.node): 
			item.node.queue_free()
	dropped_items.clear()
	
	for child in get_children():
		if is_instance_valid(child) and child is RigidBody3D:
			child.queue_free()
	
	if is_instance_valid(static_body):
		static_body.queue_free()
	
	static_body = StaticBody3D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)

func generate_world_fast(size: int):
	clear_world()
	await get_tree().process_frame
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.015
	
	var tree_noise = FastNoiseLite.new()
	tree_noise.seed = randi() + 50
	tree_noise.frequency = 0.05

	var temp_voxels = {}
	
	for x in range(size):
		for z in range(size):
			var val = noise.get_noise_2d(x, z)
			var height = int((val + 1.0) * 10.0) + 4
			
			for y in range(height):
				var type = "DIRT"
				if y == height - 1: 
					type = "GRASS"
				elif y < height - 4: 
					type = "STONE"
				
				temp_voxels[Vector3(x, y, z)] = {"color": BLOCKS[type].color, "type": type}
			
			if val < 0.1 and tree_noise.get_noise_2d(x, z) > 0.3:
				if x % 6 == 0 and z % 6 == 0: 
					place_tree(temp_voxels, x, height, z)
		
		if x % 20 == 0:
			await get_tree().process_frame

	voxels_dict = temp_voxels
	
	multi_mesh_instance.multimesh.instance_count = voxels_dict.size() + 10000
	
	var idx = 0
	var batch = 0
	
	for pos in voxels_dict:
		var data = voxels_dict[pos]
		data["mesh_idx"] = idx
		data["col"] = add_collision(pos)
		
		multi_mesh_instance.multimesh.set_instance_transform(idx, Transform3D(Basis(), pos))
		multi_mesh_instance.multimesh.set_instance_color(idx, data.color)
		idx += 1
		batch += 1
		
		if batch >= 2000:
			await get_tree().process_frame
			batch = 0
	
	var hidden = Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0))
	free_indices.clear()
	
	for i in range(idx, multi_mesh_instance.multimesh.instance_count):
		multi_mesh_instance.multimesh.set_instance_transform(i, hidden)
		free_indices.append(i)

func place_tree(voxels: Dictionary, x: int, h: int, z: int):
	var trunk = randi_range(4, 5)
	
	for i in range(trunk):
		var pos = Vector3(x, h + i, z)
		voxels[pos] = {"color": BLOCKS["WOOD"].color, "type": "WOOD"}
	
	for lx in range(-2, 3):
		for lz in range(-2, 3):
			for ly in range(0, 3):
				if abs(lx) + abs(lz) + abs(ly-1) <= 3:
					var pos = Vector3(x + lx, h + trunk + ly - 1, z + lz)
					if not voxels.has(pos):
						voxels[pos] = {"color": BLOCKS["LEAVES"].color, "type": "LEAVES"}

func add_collision(pos):
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.position = pos
	static_body.add_child(shape)
	return shape

func destroy_block(pos: Vector3):
	var p = pos.round()
	if not voxels_dict.has(p):
		return
	
	var data = voxels_dict[p]
	var type = data.type
	
	play_sound("break", type)
	
	if type == "LEAVES":
		if randf() < 0.4:
			spawn_drop(p, BLOCKS["WOOD"].color, "WOOD")
	else:
		spawn_drop(p, data.color, type)
	
	remove_voxel(p)
	
	for offset in [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var neighbor = p + offset
		if voxels_dict.has(neighbor):
			var cluster = check_cluster(neighbor)
			if not cluster["connected"]:
				drop_cluster(cluster["blocks"])

func create_block(pos: Vector3, color: Color):
	var p = pos.round()
	if voxels_dict.has(p) or free_indices.is_empty(): 
		return
	
	var idx = free_indices.pop_back()
	var type = "DIRT"
	for key in BLOCKS:
		if BLOCKS[key].color.is_equal_approx(color): 
			type = key
	
	play_sound("place", type)
	
	var col = add_collision(p)
	multi_mesh_instance.multimesh.set_instance_transform(idx, Transform3D(Basis(), p))
	multi_mesh_instance.multimesh.set_instance_color(idx, color)
	voxels_dict[p] = {"color": color, "type": type, "col": col, "mesh_idx": idx}

func remove_voxel(pos: Vector3):
	if not voxels_dict.has(pos):
		return
	
	var data = voxels_dict[pos]
	if is_instance_valid(data.col):
		data.col.queue_free()
	var hidden = Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0))
	multi_mesh_instance.multimesh.set_instance_transform(data.mesh_idx, hidden)
	free_indices.append(data.mesh_idx)
	voxels_dict.erase(pos)

func check_cluster(start: Vector3) -> Dictionary:
	var blocks = []
	var queue = [start]
	var visited = {start: true}
	var grounded = false
	
	while queue.size() > 0 and blocks.size() < 100:
		var curr = queue.pop_front()
		blocks.append(curr)
		
		for offset in [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var n = curr + offset
			if voxels_dict.has(n):
				var ntype = voxels_dict[n].type
				if ntype in ["DIRT", "STONE", "GRASS"]:
					grounded = true
					return {"blocks": blocks, "connected": true}
		
		var ctype = voxels_dict.get(curr, {}).get("type", "")
		
		for offset in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var n = curr + offset
			if voxels_dict.has(n) and not visited.has(n):
				var ntype = voxels_dict[n].type
				var valid = false
				
				if ctype in ["WOOD", "LEAVES"] and ntype in ["WOOD", "LEAVES"]:
					valid = true
				elif ctype == ntype and ctype not in ["DIRT", "STONE", "GRASS"]:
					valid = true
				
				if valid:
					visited[n] = true
					queue.append(n)
	
	return {"blocks": blocks, "connected": grounded}

func drop_cluster(blocks: Array):
	if blocks.is_empty(): 
		return
	
	var rb = RigidBody3D.new()
	var center = Vector3.ZERO
	var types = {}
	
	for b in blocks: 
		center += b
		if voxels_dict.has(b):
			types[b] = voxels_dict[b].type
	center /= blocks.size()
	
	rb.position = center
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	
	for bpos in blocks:
		if voxels_dict.has(bpos):
			var m = MeshInstance3D.new()
			m.mesh = BoxMesh.new()
			var mat = StandardMaterial3D.new()
			mat.albedo_color = voxels_dict[bpos].color
			m.material_override = mat
			m.position = bpos - center
			rb.add_child(m)
			remove_voxel(bpos)
	
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	rb.add_child(shape)
	add_child(rb)
	
	var data = {
		"rb": rb,
		"time": Time.get_ticks_msec() / 1000.0,
		"hit": false,
		"types": types
	}
	
	rb.body_entered.connect(func(_body):
		if not data.hit:
			data.hit = true
			
			var spawn_center = data.rb.global_position
			for bpos in data.types:
				var btype = data.types[bpos]
				
				var offset = Vector3(
					randf_range(-1.0, 1.0),
					randf_range(0.5, 1.5),
					randf_range(-1.0, 1.0)
				)
				var spos = spawn_center + offset
				
				if btype == "LEAVES":
					if randf() < 0.4:
						spawn_drop(spos, BLOCKS["WOOD"].color, "WOOD")
				else:
					spawn_drop(spos, BLOCKS[btype].color, btype)
			
			if is_instance_valid(data.rb):
				data.rb.queue_free()
	)
	
	get_tree().create_timer(10.0).timeout.connect(func():
		if not data.hit and is_instance_valid(data.rb):
			data.rb.queue_free()
	)

func spawn_drop(pos: Vector3, color: Color, type: String):
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(0.3, 0.3, 0.3)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.position = pos
	add_child(mesh)
	
	var time = Time.get_ticks_msec() / 1000.0
	dropped_items.append({
		"node": mesh, 
		"type": type, 
		"fall_speed": 0.0,
		"spawn_time": time,
		"can_pickup": false
	})

func _process(delta):
	if get_tree().paused or dropped_items.is_empty(): 
		return
	
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): 
		return
	
	var ppos = players[0].global_position
	var time = Time.get_ticks_msec() / 1000.0
	
	for i in range(dropped_items.size() - 1, -1, -1):
		var item = dropped_items[i]
		
		if not is_instance_valid(item.node):
			dropped_items.remove_at(i)
			continue
		
		if not item.can_pickup:
			if time - item.spawn_time >= 0.5:
				item.can_pickup = true
		
		var floor = (item.node.position + Vector3(0, -0.4, 0)).round()
		if not voxels_dict.has(floor):
			item.fall_speed += 12.0 * delta
			item.node.position.y -= item.fall_speed * delta
		else:
			item.fall_speed = 0
			item.node.position.y = lerp(item.node.position.y, floor.y + 0.6, 0.2)
		
		item.node.rotate_y(delta * 2.0)
		
		var dist = item.node.position.distance_to(ppos)
		if item.can_pickup and dist < 1.6:
			var sound = "res://sounds/block_pickup.ogg"
			if FileAccess.file_exists(sound):
				audio_pickup.stream = load(sound)
				audio_pickup.play()
			
			players[0].add_to_inventory(item.type)
			item.node.queue_free()
			dropped_items.remove_at(i)
		elif dist < 1.6 and not item.can_pickup:
			var pulse = sin(time * 10.0) * 0.05 + 1.0
			item.node.scale = Vector3.ONE * pulse

func get_block_hardness(pos: Vector3) -> float:
	var p = pos.round()
	return BLOCKS[voxels_dict[p].type].hardness if voxels_dict.has(p) else 1.0

func update_block_visual(pos: Vector3, damage: float):
	var p = pos.round()
	if voxels_dict.has(p):
		var d = voxels_dict[p]
		multi_mesh_instance.multimesh.set_instance_color(d.mesh_idx, d.color * clamp(1.0 - damage, 0.2, 1.0))

func reset_block_visual(pos: Vector3):
	var p = pos.round()
	if voxels_dict.has(p):
		var d = voxels_dict[p]
		multi_mesh_instance.multimesh.set_instance_color(d.mesh_idx, d.color)

func update_highlight(target_pos: Vector3, hit_normal: Vector3, is_valid: bool):
	var p = target_pos.round()
	
	if is_valid and voxels_dict.has(p):
		highlight_mesh.visible = true
		draw_highlight_box(p, hit_normal)
	else:
		highlight_mesh.visible = false

func hide_highlight():
	highlight_mesh.visible = false
