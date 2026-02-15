extends CharacterBody3D

# Referencje do węzłów - znajdowane automatycznie
var head
var camera
var raycast
var world
var hotbar_ui
var selection_frame
var block_name_label

const SPEED = 5.0
const JUMP_VELOCITY = 4.8
var mouse_sensitivity = 0.002

# Początkowa pozycja gracza (spawn point)
var spawn_position = Vector3.ZERO
var spawn_rotation = Vector3.ZERO

var inventory = {} # { "GRASS": 10 }
var hotbar_slots = ["EMPTY", "EMPTY", "EMPTY", "EMPTY", "EMPTY", "EMPTY"]
var active_slot = 0
var label_timer = 0.0

var mining_progress = 0.0
var last_mined_pos = Vector3.INF

# System dźwięków chodzenia
var audio_player_footsteps: AudioStreamPlayer
var footstep_timer = 0.0
const FOOTSTEP_INTERVAL = 0.4

# Cache dla wykrywania bloków
var current_target_block = Vector3.INF
var current_target_normal = Vector3.ZERO

# Maksymalny zasięg interakcji z blokami
const MAX_REACH = 5.0

func _ready():
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Zapisz początkową pozycję jako spawn point
	spawn_position = global_position
	
	# Automatyczne znalezienie wszystkich węzłów
	setup_node_references()
	
	if head:
		spawn_rotation = head.rotation
	
	if block_name_label:
		block_name_label.modulate.a = 0.0
	
	# Setup footstep audio
	audio_player_footsteps = AudioStreamPlayer.new()
	audio_player_footsteps.bus = "SFX"
	add_child(audio_player_footsteps)
	
	update_ui()

func setup_node_references():
	"""Automatycznie znajduje wszystkie potrzebne węzły w scenie"""
	
	# Znajdź Head - może być dzieckiem tego węzła
	head = find_child("Head", true, false)
	if not head:
		print("BŁĄD: Nie znaleziono węzła 'Head'!")
		return
	
	# Znajdź Camera (PlayerView) pod Head
	camera = head.find_child("PlayerView", true, false)
	if not camera:
		camera = head.find_child("Camera3D", true, false)
	if not camera:
		print("BŁĄD: Nie znaleziono kamery!")
		return
	
	# Znajdź RayCast pod Camera (PlayerView)
	raycast = camera.find_child("RayCast3D", true, false)
	if not raycast:
		print("BŁĄD: Nie znaleziono RayCast3D!")
	else:
		# Ustaw zasięg raycasta
		raycast.target_position = Vector3(0, 0, -MAX_REACH)
	
	# Znajdź świat - zazwyczaj parent lub root
	world = get_parent()
	if not world or not world.has_method("destroy_block"):
		# Jeśli parent nie jest światem, szukaj w root
		var tree_root = get_tree().root
		for child in tree_root.get_children():
			if child.has_method("destroy_block"):
				world = child
				break
	
	# Znajdź UI elementy
	var ui_root = get_tree().root
	hotbar_ui = ui_root.find_child("Hotbar", true, false)
	selection_frame = ui_root.find_child("SelectionFrame", true, false)
	block_name_label = ui_root.find_child("BlockNameLabel", true, false)
	
	# Debug info
	print("=== Setup węzłów gracza ===")
	print("Head: ", head != null)
	print("Camera: ", camera != null)
	print("RayCast: ", raycast != null)
	print("World: ", world != null)
	print("Hotbar: ", hotbar_ui != null)
	print("SelectionFrame: ", selection_frame != null)
	print("BlockNameLabel: ", block_name_label != null)
	print("==========================")

func _input(event):
	if get_tree().paused: 
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if head and camera:
			head.rotate_y(-event.relative.x * mouse_sensitivity)
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, -1.5, 1.5)

	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				change_slot(wrapi(active_slot - 1, 0, 6))
			MOUSE_BUTTON_WHEEL_DOWN:
				change_slot(wrapi(active_slot + 1, 0, 6))
	
	elif event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			change_slot(event.keycode - KEY_1)

func _process(delta):
	if get_tree().paused: 
		return
	
	# Timer dla napisu nazwy bloku
	if label_timer > 0:
		label_timer -= delta
		if block_name_label:
			block_name_label.modulate.a = clamp(label_timer, 0.0, 1.0)

func _physics_process(delta):
	if get_tree().paused: 
		return

	# Grawitacja
	if not is_on_floor(): 
		velocity += get_gravity() * delta
	
	# Skok
	if Input.is_action_just_pressed("jump") and is_on_floor(): 
		velocity.y = JUMP_VELOCITY
	
	# Ruch
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir != Vector2.ZERO and head:
		var direction = (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	move_and_slide()
	
	# Dźwięki chodzenia
	handle_footsteps(delta, input_dir != Vector2.ZERO)
	
	# Interakcje z blokami
	handle_interactions(delta)

func handle_footsteps(delta: float, is_moving: bool):
	"""Odtwarza dźwięki kroków podczas chodzenia"""
	if not world or not is_on_floor() or not is_moving:
		footstep_timer = 0.0
		return
	
	footstep_timer += delta
	
	if footstep_timer >= FOOTSTEP_INTERVAL:
		footstep_timer = 0.0
		
		# Sprawdź na jakim bloku stoisz
		var floor_pos = (global_position + Vector3(0, -1.1, 0)).round()
		if world.voxels_dict.has(floor_pos):
			var block_type = world.voxels_dict[floor_pos].type
			var sound_path = world.play_sound("walk", block_type)
			
			if sound_path != "" and FileAccess.file_exists(sound_path):
				audio_player_footsteps.stream = load(sound_path)
				audio_player_footsteps.play()

func handle_interactions(delta):
	if not raycast or not world or not camera:
		return
	
	# Aktualizuj raycast
	raycast.force_raycast_update()
	
	# Sprawdź czy celujemy w blok
	if raycast.is_colliding():
		var collision_point = raycast.get_collision_point()
		var collision_normal = raycast.get_collision_normal()
		
		# POPRAWIONE WYKRYWANIE BLOKU:
		# Używamy round() zamiast floor() dla lepszej precyzji
		# Cofamy się niewielki kawałek od punktu kolizji w kierunku przeciwnym do normalu
		var target_pos = (collision_point - collision_normal * 0.1).round()
		
		# Sprawdź odległość od gracza - blok musi być w zasięgu
		var distance = camera.global_position.distance_to(collision_point)
		
		# Upewnij się że blok istnieje i jest w zasięgu
		if world.voxels_dict.has(target_pos) and distance <= MAX_REACH:
			current_target_block = target_pos
			current_target_normal = collision_normal
			
			# Zaktualizuj podświetlenie
			world.update_highlight(target_pos, collision_normal, true)
			
			# LPM - Niszczenie
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				handle_mining(delta, target_pos)
			else:
				cancel_mining()
			
			# PPM - Budowanie
			if Input.is_action_just_pressed("secondary_action"):
				handle_building(collision_point, collision_normal)
		else:
			# Blok nie istnieje lub jest za daleko - ukryj podświetlenie
			world.hide_highlight()
			cancel_mining()
			current_target_block = Vector3.INF
	else:
		# Nie celujemy w żaden blok
		world.hide_highlight()
		cancel_mining()
		current_target_block = Vector3.INF

func handle_mining(delta: float, target_pos: Vector3):
	"""Obsługuje kopanie bloków"""
	# Jeśli zmieniamy blok, resetujemy postęp
	if target_pos != last_mined_pos:
		if last_mined_pos != Vector3.INF:
			world.reset_block_visual(last_mined_pos)
		mining_progress = 0.0
		last_mined_pos = target_pos
	
	# Postęp kopania
	var hardness = world.get_block_hardness(target_pos)
	mining_progress += delta / hardness
	world.update_block_visual(target_pos, mining_progress)
	
	# Zniszczenie bloku
	if mining_progress >= 1.0:
		world.destroy_block(target_pos)
		world.hide_highlight()
		mining_progress = 0.0
		last_mined_pos = Vector3.INF

func handle_building(collision_point: Vector3, collision_normal: Vector3):
	"""Obsługuje stawianie bloków"""
	var type = hotbar_slots[active_slot]
	if type == "EMPTY" or inventory.get(type, 0) <= 0:
		return
	
	# Postaw blok w kierunku normalu (na powierzchni trafionego bloku)
	var pos = (collision_point + collision_normal * 0.5).round()
	
	# Sprawdź, czy nie koliduje z graczem
	var player_box = AABB(global_position - Vector3(0.4, 0.9, 0.4), Vector3(0.8, 1.8, 0.8))
	var block_box = AABB(pos - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
	
	if not player_box.intersects(block_box):
		world.create_block(pos, world.BLOCKS[type].color)
		inventory[type] -= 1
		if inventory[type] <= 0:
			hotbar_slots[active_slot] = "EMPTY"
		update_ui()

func cancel_mining():
	"""Anuluje kopanie i resetuje wizualizację"""
	if last_mined_pos != Vector3.INF and world:
		world.reset_block_visual(last_mined_pos)
		last_mined_pos = Vector3.INF
		mining_progress = 0.0

func add_to_inventory(type: String):
	"""Dodaje przedmiot do inwentarza"""
	# Dodaj do inwentarza
	if inventory.has(type):
		inventory[type] += 1
	else:
		inventory[type] = 1
	
	# Automatycznie dodaj do hotbara jeśli jest miejsce
	if not type in hotbar_slots:
		for i in range(6):
			if hotbar_slots[i] == "EMPTY":
				hotbar_slots[i] = type
				break
	
	update_ui()

func change_slot(index: int):
	"""Zmienia aktywny slot w hotbarze"""
	active_slot = index
	update_selection_frame()
	
	var type = hotbar_slots[active_slot]
	if type != "EMPTY" and world and block_name_label:
		block_name_label.text = world.BLOCKS[type].name
		block_name_label.modulate.a = 1.0
		label_timer = 2.0

func update_ui():
	"""Aktualizuje interfejs użytkownika"""
	if not hotbar_ui or not world:
		return
	
	for i in range(6):
		var type = hotbar_slots[i]
		if hotbar_ui.get_child_count() <= i:
			continue
			
		var slot = hotbar_ui.get_child(i)
		var preview = slot.find_child("Preview", true, false)
		var count_label = slot.find_child("Count", true, false)
		
		if type == "EMPTY" or inventory.get(type, 0) <= 0:
			if hotbar_slots[i] != "EMPTY":
				hotbar_slots[i] = "EMPTY"
			
			if preview: 
				preview.visible = false
			if count_label: 
				count_label.text = ""
		else:
			if preview:
				preview.visible = true
				preview.color = world.BLOCKS[type].color
			if count_label:
				count_label.text = str(inventory[type])
	
	update_selection_frame()

func update_selection_frame():
	"""Aktualizuje pozycję ramki wyboru w hotbarze"""
	if not is_inside_tree() or not hotbar_ui or not selection_frame: 
		return
	
	if hotbar_ui.get_child_count() > active_slot:
		var active_slot_node = hotbar_ui.get_child(active_slot)
		if active_slot_node:
			selection_frame.global_position = active_slot_node.global_position

func respawn():
	"""Resetuje pozycję gracza do spawn pointu"""
	# Resetuj pozycję
	global_position = spawn_position
	
	# Resetuj rotację
	if head:
		head.rotation.y = spawn_rotation.y
	if camera:
		camera.rotation.x = spawn_rotation.x
	
	# Resetuj prędkość
	velocity = Vector3.ZERO
	
	# Resetuj stan kopania
	mining_progress = 0.0
	last_mined_pos = Vector3.INF
	current_target_block = Vector3.INF
	
	print("Gracz zrespawnowany na pozycji: ", spawn_position)
